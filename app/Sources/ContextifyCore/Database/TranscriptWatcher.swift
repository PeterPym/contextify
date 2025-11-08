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
  private var watchers: [String: DispatchSourceFileSystemObject] = [:]
  private var debounceTimers: [String: Timer] = [:]
  private let watcherQueue = DispatchQueue(label: "dev.contextify.transcriptWatcher")

  public init(
    hooverEngine: HooverEngine,
    transcriptRepo: TranscriptRepository,
    metadataInvalidator: ((String) throws -> Void)? = nil
  ) {
    self.hooverEngine = hooverEngine
    self.transcriptRepo = transcriptRepo
    self.metadataInvalidator = metadataInvalidator
  }

  /// Set metadata invalidation callback (useful when orchestrator needs weak self reference)
  public func setMetadataInvalidator(_ invalidator: @escaping (String) throws -> Void) {
    self.metadataInvalidator = invalidator
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

    // Idempotence: skip if already watching
    if isWatching(transcriptId: transcriptId) {
      log.info("[WATCHER-WATCH-SKIP] Already watching transcript: \(transcriptId, privacy: .public) - skipping")
      return
    }

    // Perform initial ingestion of existing content before starting watcher
    do {
      log.info("[WATCHER-INGEST-START] Performing initial ingestion for: \(transcriptId, privacy: .public)")
      guard let transcript = try transcriptRepo.get(transcriptId) else {
        log.error("[WATCHER-INGEST-ERROR] Transcript not found during initial ingest: \(transcriptId, privacy: .public)")
        throw TranscriptWatcherError.transcriptNotFound
      }

      // Ingest existing content (HooverEngine resumes from last checkpoint, so safe for existing ingestions)
      _ = try hooverEngine.hooverTranscript(
        transcript,
        fileURL: fileURL,
        progress: NoOpProgressSink()
      )
      log.info("[WATCHER-INGEST-DONE] Initial ingestion complete for: \(transcriptId, privacy: .public)")
    } catch {
      log.error("[WATCHER-INGEST-ERROR] Initial ingestion failed for \(transcriptId, privacy: .public): \(error, privacy: .public)")
      // Continue to set up watcher even if initial ingest fails
    }

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

    // Thread-safe dictionary mutation
    watcherQueue.sync {
      watchers[transcriptId] = source
    }

    log.info("[WATCHER-WATCH-DONE] ✅ Now watching transcript: \(transcriptId, privacy: .public)")
  }

  /// Stop watching a transcript
  public func stopWatching(transcriptId: String) {
    watcherQueue.sync {
      if let source = watchers[transcriptId] {
        source.cancel()
        watchers.removeValue(forKey: transcriptId)
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
    log.info("[WATCHER-EVENT] File change detected for transcript: \(transcriptId, privacy: .public) path: \(fileURL.path, privacy: .public)")

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

        // Invalidate cached metadata (file changed, so metadata may be stale)
        try? self.metadataInvalidator?(transcriptId)

        // Stream new lines using hoover engine (it will resume from checkpoint)
        _ = try self.hooverEngine.hooverTranscript(
          transcript,
          fileURL: fileURL,
          progress: NoOpProgressSink()
        )

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
}
