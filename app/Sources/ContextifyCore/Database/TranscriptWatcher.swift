import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptWatcher")

/// Errors that can occur during transcript watching
public enum TranscriptWatcherError: Error {
  case transcriptNotFound
}

/// Watches transcript files for changes and triggers incremental streaming
public final class TranscriptWatcher {
  private let hooverEngine: HooverEngine
  private let transcriptRepo: TranscriptRepository
  private var metadataInvalidator: ((String) throws -> Void)?
  private var rehoover: ((String, URL, String, String?) throws -> Void)?
  private var watchers: [String: DispatchSourceFileSystemObject] = [:]
  private var debounceTimers: [String: Timer] = [:]
  private var lastEventTime: [String: Date] = [:]
  private let watcherQueue = DispatchQueue(label: "dev.contextify.transcriptWatcher")
  private var heartbeatStarted = false

  // Event deduplication: filter events within 50ms of previous event for same transcript
  private let minEventInterval: TimeInterval = 0.05
  private let heartbeatInterval: TimeInterval = 60.0

  public init(
    hooverEngine: HooverEngine,
    transcriptRepo: TranscriptRepository,
    metadataInvalidator: ((String) throws -> Void)? = nil,
    rehoover: ((String, URL, String, String?) throws -> Void)? = nil
  ) {
    self.hooverEngine = hooverEngine
    self.transcriptRepo = transcriptRepo
    self.metadataInvalidator = metadataInvalidator
    self.rehoover = rehoover
  }

  /// Set metadata invalidation callback (useful when orchestrator needs weak self reference)
  public func setMetadataInvalidator(_ invalidator: @escaping (String) throws -> Void) {
    self.metadataInvalidator = invalidator
  }

  /// Set re-hoover callback for security-scoped re-ingestion (useful when orchestrator needs weak self reference)
  public func setRehoover(_ rehooverCallback: @escaping (String, URL, String, String?) throws -> Void) {
    self.rehoover = rehooverCallback
  }

  /// Check if a transcript is being watched
  public func isWatching(transcriptId: String) -> Bool {
    return watcherQueue.sync {
      watchers[transcriptId] != nil
    }
  }

  /// Start watching a transcript file for changes (idempotent - skips if already watching)
  public func watch(transcriptId: String, fileURL: URL) throws {
    log.info("[WATCHER-WATCH-START] Request to watch transcript: \(transcriptId, privacy: .public) at path: \(fileURL.path, privacy: .public)")
    log.info("[FSEVENTS-WATCH-START] transcript=\(transcriptId, privacy: .public) path=\(fileURL.path, privacy: .public)")

    // Start heartbeat on first watch (only once)
    watcherQueue.sync {
      if !heartbeatStarted {
        heartbeatStarted = true
        startHeartbeat()
      }
    }

    // Idempotence check inside lock to prevent race condition where two threads
    // both pass the check before either adds to the dictionary
    let alreadyWatching = watcherQueue.sync { watchers[transcriptId] != nil }
    if alreadyWatching {
      log.info("[WATCHER-WATCH-SKIP] Already watching transcript: \(transcriptId, privacy: .public) - skipping")
      return
    }

    // NOTE: Initial ingestion removed - orchestrator always hoovers during discovery
    // before starting watchers, so this was 100% redundant (causing 50% wasted work).
    // Watcher now only monitors FUTURE file changes, not existing content.

    let fileDescriptor = open(fileURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      log.error("Failed to open file for watching: \(fileURL.path, privacy: .public)")
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .extend],
      queue: DispatchQueue.main
    )

    source.setEventHandler { [weak self] in
      self?.handleFileChange(transcriptId: transcriptId, fileURL: fileURL)
    }

    source.setCancelHandler {
      close(fileDescriptor)
    }

    source.resume()

    // Thread-safe dictionary mutation - double-check inside lock to catch any race
    // that occurred during ingestion
    let wasAdded = watcherQueue.sync { () -> Bool in
      if watchers[transcriptId] != nil {
        log.warning("[WATCHER-WATCH-RACE] Race detected - watcher was added during ingestion for: \(transcriptId, privacy: .public)")
        return false
      }
      watchers[transcriptId] = source
      return true
    }

    if wasAdded {
      log.info("[WATCHER-WATCH-DONE] ✅ Now watching transcript: \(transcriptId, privacy: .public)")
    } else {
      // Clean up the source we just created since we didn't use it
      source.cancel()
      log.info("[WATCHER-WATCH-SKIP] Skipping - watcher was added by another thread during ingestion: \(transcriptId, privacy: .public)")
    }
  }

  /// Stop watching a transcript
  public func stopWatching(transcriptId: String) {
    watcherQueue.sync {
      if let source = watchers[transcriptId] {
        source.cancel()
        watchers.removeValue(forKey: transcriptId)
        log.info("[FSEVENTS-WATCH-STOP] transcript=\(transcriptId, privacy: .public)")
      }

      if let timer = debounceTimers[transcriptId] {
        timer.invalidate()
        debounceTimers.removeValue(forKey: transcriptId)
      }
    }

    log.debug("Stopped watching transcript: \(transcriptId)")
  }

  /// Stop all watchers
  public func stopAll() {
    let allKeys = watcherQueue.sync { Array(watchers.keys) }
    for transcriptId in allKeys {
      stopWatching(transcriptId: transcriptId)
    }
  }

  /// Handle file change event (debounced)
  private func handleFileChange(transcriptId: String, fileURL: URL) {
    // Event deduplication: filter duplicate events within minEventInterval
    let now = Date()
    let shouldProcess = watcherQueue.sync { () -> Bool in
      if let lastEvent = lastEventTime[transcriptId] {
        let interval = now.timeIntervalSince(lastEvent)
        if interval < minEventInterval {
          log.debug("[WATCHER-EVENT-DEDUPE] Ignoring duplicate event within \(Int(interval * 1000), privacy: .public)ms for: \(transcriptId, privacy: .public)")
          return false
        }
      }
      lastEventTime[transcriptId] = now
      return true
    }

    guard shouldProcess else { return }

    log.info("[WATCHER-EVENT] File change detected for transcript: \(transcriptId, privacy: .public) path: \(fileURL.path, privacy: .public)")
    log.info("[FSEVENTS-CHANGE] transcript=\(transcriptId, privacy: .public) flags=write")

    watcherQueue.sync {
      // Cancel existing timer
      debounceTimers[transcriptId]?.invalidate()

      // Create new debounce timer
      log.debug("[WATCHER-DEBOUNCE] Starting debounce timer (\(MonitorConfig.fileWatcherDebounce, privacy: .public)s) for: \(transcriptId, privacy: .public)")
      let timer = Timer.scheduledTimer(withTimeInterval: MonitorConfig.fileWatcherDebounce, repeats: false) { [weak self] _ in
        self?.processFileChange(transcriptId: transcriptId, fileURL: fileURL)
      }

      debounceTimers[transcriptId] = timer
    }
  }

  /// Process file change after debounce (runs off main thread)
  private func processFileChange(transcriptId: String, fileURL: URL) {
    log.info("[WATCHER-PROCESS-START] Processing file change after debounce for: \(transcriptId, privacy: .public)")

    // Use background queue to avoid blocking UI
    watcherQueue.async { [weak self] in
      guard let self else { return }
      do {
        guard let transcript = try self.transcriptRepo.get(transcriptId) else {
          log.error("[WATCHER-PROCESS-ERROR] Transcript not found: \(transcriptId, privacy: .public)")
          return
        }

        log.info("[WATCHER-HOOVER-TRIGGER] Triggering incremental hoover for: \(transcriptId, privacy: .public)")
        log.info("[FSEVENTS-TRIGGER-INGEST] transcript=\(transcriptId, privacy: .public)")

        // Invalidate cached metadata (file changed, so metadata may be stale)
        try? self.metadataInvalidator?(transcriptId)

        // NOTE: All transcript re-ingestion goes through TranscriptOrchestrator
        // so security-scoped access is consistently applied in sandbox builds.
        if let rehoover = self.rehoover {
          // Use orchestrator callback (applies security-scoped access for external transcripts)
          try rehoover(transcript.projectId, fileURL, transcript.provider, transcript.providerSessionId)
        } else {
          // Fallback: direct hoover (legacy path, no security scope)
          _ = try self.hooverEngine.hooverTranscript(
            transcript,
            fileURL: fileURL,
            progress: NoOpProgressSink()
          )
        }

        log.info("[WATCHER-NOTIFY] Posting TranscriptUpdated notification for: \(transcriptId, privacy: .public)")

        // Notify observers on main thread
        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: NSNotification.Name("TranscriptUpdated"),
            object: transcriptId,
            userInfo: ["projectId": transcript.projectId]
          )
        }

        log.info("[WATCHER-PROCESS-DONE] ✅ Streamed new content for transcript: \(transcriptId, privacy: .public)")
      } catch {
        log.error("[WATCHER-PROCESS-ERROR] Failed to stream transcript changes: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - Heartbeat

  private func startHeartbeat() {
    // Start periodic heartbeat on watcherQueue (called from within watcherQueue.sync in watch())
    // This runs on a background queue, sleeps, then logs heartbeat
    DispatchQueue.global(qos: .utility).async { [weak self] in
      while let strongSelf = self {
        Thread.sleep(forTimeInterval: strongSelf.heartbeatInterval)
        strongSelf.emitHeartbeat()
      }
    }
  }

  private func emitHeartbeat() {
    // Access watchers count on watcherQueue (this is called from background queue, not watcherQueue)
    watcherQueue.async { [weak self] in
      guard let self else { return }
      let count = self.watchers.count
      log.info("[FSEVENTS-HEARTBEAT] watching=\(count, privacy: .public)")
    }
  }
}
