import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptWatcher")

/// Watches transcript files for changes and triggers incremental streaming
@MainActor
public final class TranscriptWatcher {
  private let hooverEngine: HooverEngine
  private let transcriptRepo: TranscriptRepository
  private var watchers: [String: DispatchSourceFileSystemObject] = [:]
  private var debounceTimers: [String: Timer] = [:]

  public init(hooverEngine: HooverEngine, transcriptRepo: TranscriptRepository) {
    self.hooverEngine = hooverEngine
    self.transcriptRepo = transcriptRepo
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
    for (transcriptId, _) in watchers {
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

  /// Process file change after debounce
  private func processFileChange(transcriptId: String, fileURL: URL) {
    Task { @MainActor in
      do {
        guard let transcript = try transcriptRepo.get(transcriptId) else {
          log.error("Transcript not found: \(transcriptId)")
          return
        }

        log.debug("Processing file change for transcript: \(transcriptId)")

        // Stream new lines using hoover engine (it will resume from checkpoint)
        try hooverEngine.hooverTranscript(
          transcript,
          fileURL: fileURL,
          progress: NoOpProgressSink()
        )

        // Notify observers
        NotificationCenter.default.post(
          name: NSNotification.Name("TranscriptUpdated"),
          object: transcriptId
        )

        log.debug("Streamed new content for transcript: \(transcriptId)")
      } catch {
        log.error("Failed to stream transcript changes: \(error.localizedDescription)")
      }
    }
  }
}
