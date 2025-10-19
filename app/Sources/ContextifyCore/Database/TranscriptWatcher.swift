import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptWatcher")

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

  /// Start watching a transcript file for changes
  public func watch(transcriptId: String, fileURL: URL) throws {
    // Stop existing watcher if any
    stopWatching(transcriptId: transcriptId)

    let fileDescriptor = open(fileURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      log.error("Failed to open file for watching: \(fileURL.path)")
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
    watchers[transcriptId] = source

    log.debug("Started watching transcript: \(transcriptId)")
  }

  /// Stop watching a transcript
  public func stopWatching(transcriptId: String) {
    if let source = watchers[transcriptId] {
      source.cancel()
      watchers.removeValue(forKey: transcriptId)
    }

    if let timer = debounceTimers[transcriptId] {
      timer.invalidate()
      debounceTimers.removeValue(forKey: transcriptId)
    }

    log.debug("Stopped watching transcript: \(transcriptId)")
  }

  /// Stop all watchers
  public func stopAll() {
    for transcriptId in Array(watchers.keys) {
      stopWatching(transcriptId: transcriptId)
    }
  }

  /// Handle file change event (debounced)
  private func handleFileChange(transcriptId: String, fileURL: URL) {
    // Cancel existing timer
    debounceTimers[transcriptId]?.invalidate()

    // Create new debounce timer
    let timer = Timer.scheduledTimer(withTimeInterval: MonitorConfig.fileWatcherDebounce, repeats: false) { [weak self] _ in
      self?.processFileChange(transcriptId: transcriptId, fileURL: fileURL)
    }

    debounceTimers[transcriptId] = timer
  }

  /// Process file change after debounce (runs off main thread)
  private func processFileChange(transcriptId: String, fileURL: URL) {
    // Use background queue to avoid blocking UI
    watcherQueue.async { [weak self] in
      guard let self else { return }
      do {
        guard let transcript = try self.transcriptRepo.get(transcriptId) else {
          log.error("Transcript not found: \(transcriptId)")
          return
        }

        log.debug("Processing file change for transcript: \(transcriptId)")

        // Invalidate cached metadata (file changed, so metadata may be stale)
        try? self.metadataInvalidator?(transcriptId)

        // Stream new lines using hoover engine (it will resume from checkpoint)
        _ = try self.hooverEngine.hooverTranscript(
          transcript,
          fileURL: fileURL,
          progress: NoOpProgressSink()
        )

        // Notify observers on main thread
        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: NSNotification.Name("TranscriptUpdated"),
            object: transcriptId,
            userInfo: ["projectId": transcript.projectId]
          )
        }

        log.debug("Streamed new content for transcript: \(transcriptId)")
      } catch {
        log.error("Failed to stream transcript changes: \(error.localizedDescription)")
      }
    }
  }
}
