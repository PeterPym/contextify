import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptWatcher")

/// Errors that can occur during transcript watching
public enum TranscriptWatcherError: Error {
  case transcriptNotFound
}

/// Watches transcript files for changes and triggers incremental streaming
public final class TranscriptWatcher: @unchecked Sendable {
  private let hooverEngine: HooverEngine
  private let transcriptRepo: TranscriptRepository
  private var metadataInvalidator: ((String) throws -> Void)?
  private var rehoover: ((String, URL, String, String?) throws -> Void)?
  private let accessProvider: TranscriptAccessProvider?
  private var watchers: [String: DispatchSourceFileSystemObject] = [:]
  private var debounceTimers: [String: Timer] = [:]
  private var lastEventTime: [String: Date] = [:]
  private let watcherQueue = DispatchQueue(label: "dev.contextify.transcriptWatcher")
  private var heartbeatStarted = false
  private var shouldStopHeartbeat = false

  // Event deduplication: filter events within 50ms of previous event for same transcript
  private let minEventInterval: TimeInterval = 0.05
  private let heartbeatInterval: TimeInterval = 60.0

  public init(
    hooverEngine: HooverEngine,
    transcriptRepo: TranscriptRepository,
    accessProvider: TranscriptAccessProvider? = nil,
    metadataInvalidator: ((String) throws -> Void)? = nil,
    rehoover: ((String, URL, String, String?) throws -> Void)? = nil
  ) {
    self.hooverEngine = hooverEngine
    self.transcriptRepo = transcriptRepo
    self.accessProvider = accessProvider
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
  public func watch(transcriptId: String, fileURL: URL, provider: String) throws {
    log.info("[WATCHER-WATCH-START] Request to watch transcript: \(transcriptId, privacy: .public) at path: \(fileURL.path, privacy: .public)")
    log.info("[FSEVENTS-WATCH-START] transcript=\(transcriptId, privacy: .public) path=\(fileURL.path, privacy: .public)")

    // Defensive check: refuse to watch files in sandbox container paths
    // These can't be accessed and will cause recovery loops
    if SandboxPathFilter.isSandboxContainerPath(fileURL.path) {
      log.warning("[WATCHER-WATCH-SKIP] Refusing to watch sandbox container path: \(fileURL.path, privacy: .public)")
      return
    }

    // Combined: start heartbeat on first watch and check if already watching (single sync call)
    let alreadyWatching = watcherQueue.sync { () -> Bool in
      if !heartbeatStarted {
        heartbeatStarted = true
        startHeartbeat()
      }
      return watchers[transcriptId] != nil
    }

    if alreadyWatching {
      log.info("[WATCHER-WATCH-SKIP] Already watching transcript: \(transcriptId, privacy: .public) - skipping")
      return
    }

    // NOTE: Initial ingestion removed - orchestrator always hoovers during discovery
    // before starting watchers, so this was 100% redundant (causing 50% wasted work).
    // Watcher now only monitors FUTURE file changes, not existing content.

    if needsSecurityScope(for: provider),
       let accessProvider {
      log.debug("[WATCHER-SCOPE] Starting watcher inside security scope for provider=\(provider, privacy: .public)")
      try accessProvider.withAccess(for: provider) { _ in
        self.armWatcher(transcriptId: transcriptId, fileURL: fileURL)
      }
    } else {
      armWatcher(transcriptId: transcriptId, fileURL: fileURL)
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
    watcherQueue.sync {
      shouldStopHeartbeat = true
    }

    let allKeys = watcherQueue.sync { Array(watchers.keys) }
    for transcriptId in allKeys {
      stopWatching(transcriptId: transcriptId)
    }
  }

  /// Handle file change event (debounced)
  private func handleFileChange(transcriptId: String, fileURL: URL, eventData: DispatchSource.FileSystemEvent) {
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

    // Decode event flags
    var flagsArray: [String] = []
    if eventData.contains(.write) { flagsArray.append("write") }
    if eventData.contains(.extend) { flagsArray.append("extend") }
    if eventData.contains(.attrib) { flagsArray.append("attrib") }
    if eventData.contains(.link) { flagsArray.append("link") }
    if eventData.contains(.rename) { flagsArray.append("rename") }
    if eventData.contains(.revoke) { flagsArray.append("revoke") }
    if eventData.contains(.funlock) { flagsArray.append("funlock") }
    let flagsString = flagsArray.isEmpty ? "none" : flagsArray.joined(separator: "|")

    log.info("[WATCHER-EVENT] File change detected for transcript: \(transcriptId, privacy: .public) path: \(fileURL.path, privacy: .public)")
    log.info("[FSEVENTS-CHANGE] transcript=\(transcriptId, privacy: .public) flags=\(flagsString, privacy: .public)")

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

  private func armWatcher(transcriptId: String, fileURL: URL) {
    log.debug("[WATCHER-ARM-START] Arming watcher for transcript=\(transcriptId, privacy: .public) path=\(fileURL.path, privacy: .public)")

    let fileDescriptor = open(fileURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      let errorCode = errno
      log.error("[WATCHER-FD-OPEN-FAILED] Failed to open file descriptor: path=\(fileURL.path, privacy: .public) errno=\(errorCode) (\(String(cString: strerror(errorCode))))")
      return
    }
    log.debug("[WATCHER-FD-OPEN] Opened file descriptor fd=\(fileDescriptor) for transcript=\(transcriptId, privacy: .public)")

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .extend],
      queue: DispatchQueue.main
    )
    log.debug("[WATCHER-SOURCE-CREATE] Created dispatch source for transcript=\(transcriptId, privacy: .public)")

    source.setEventHandler { [weak self] in
      guard let self, let source = source as? DispatchSourceFileSystemObject else { return }
      let eventData = source.data
      self.handleFileChange(transcriptId: transcriptId, fileURL: fileURL, eventData: eventData)
    }

    source.setCancelHandler {
      close(fileDescriptor)
    }

    source.resume()
    log.debug("[WATCHER-SOURCE-RESUME] Resumed dispatch source for transcript=\(transcriptId, privacy: .public)")

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
      log.debug("[WATCHER-WATCH-DONE] ✅ Now watching transcript: \(transcriptId, privacy: .public)")
    } else {
      // Clean up the source we just created since we didn't use it
      source.cancel()
      log.debug("[WATCHER-WATCH-SKIP] Skipping - watcher was added by another thread during ingestion: \(transcriptId, privacy: .public)")
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
    // Start periodic heartbeat on background queue
    // Loop exits when shouldStopHeartbeat is set or self is deallocated
    DispatchQueue.global(qos: .utility).async { [weak self] in
      while let strongSelf = self {
        Thread.sleep(forTimeInterval: strongSelf.heartbeatInterval)

        // Check if we should stop
        let shouldStop = strongSelf.watcherQueue.sync { strongSelf.shouldStopHeartbeat }
        if shouldStop {
          log.info("[FSEVENTS-HEARTBEAT] Stopping heartbeat")
          break
        }

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

  private func needsSecurityScope(for provider: String) -> Bool {
    guard Sandbox.isSandboxed else { return false }
    return provider == TranscriptProviderID.claude || provider == TranscriptProviderID.codex
  }
}
