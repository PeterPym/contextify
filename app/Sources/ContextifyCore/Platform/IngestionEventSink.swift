import Foundation

// MARK: - Ingestion Event Sink Protocol

/// Protocol for receiving ingestion progress events.
///
/// Implementations can:
/// - Post NotificationCenter notifications (macOS app)
/// - Print JSONL to stdout (CLI)
/// - Log to a file (debugging)
/// - Aggregate metrics (testing)
///
/// ## Event Lifecycle
/// 1. `ingestionStarted` - emitted once at ingestion start
/// 2. `progressUpdate` - emitted periodically during processing
/// 3. `fileError` - emitted for each file-level error (parsing failure, missing file, etc.)
/// 4. `ingestionCompleted` - emitted once at ingestion end
///
/// ## Thread Safety
/// Implementations must be thread-safe as events may be emitted from background threads.
public protocol IngestionEventSink: Sendable {
  /// Emitted once at ingestion start.
  ///
  /// - Parameters:
  ///   - runId: Unique identifier for this ingestion run.
  ///   - transcriptCount: Total number of transcripts to process.
  func ingestionStarted(runId: String, transcriptCount: Int)

  /// Emitted periodically during processing.
  ///
  /// - Parameters:
  ///   - transcriptId: ID of the transcript being processed.
  ///   - entriesInserted: Number of entries inserted so far for this transcript.
  ///   - totalEntries: Estimated total entries in this transcript (may be nil if unknown).
  func progressUpdate(transcriptId: String, entriesInserted: Int, totalEntries: Int?)

  /// Emitted for each file-level error.
  ///
  /// - Parameters:
  ///   - path: File path that caused the error.
  ///   - error: Error description.
  func fileError(path: String, error: String)

  /// Emitted once at ingestion end.
  ///
  /// - Parameters:
  ///   - runId: Unique identifier for this ingestion run (matches `ingestionStarted`).
  ///   - success: True if ingestion completed without fatal errors.
  ///   - summary: Summary statistics for the ingestion run.
  func ingestionCompleted(runId: String, success: Bool, summary: IngestionSummary)
}

// MARK: - Ingestion Summary

/// Summary statistics for a completed ingestion run.
public struct IngestionSummary: Sendable, Equatable {
  /// Number of transcripts processed.
  public let transcriptsProcessed: Int

  /// Number of transcript entries inserted.
  public let entriesInserted: Int

  /// Number of entries skipped (metadata, empty content, etc.).
  public let entriesSkipped: Int

  /// Number of parse errors encountered.
  public let errorsEncountered: Int

  /// Duration of the ingestion run in seconds.
  public let durationSeconds: Double

  public init(
    transcriptsProcessed: Int,
    entriesInserted: Int,
    entriesSkipped: Int,
    errorsEncountered: Int,
    durationSeconds: Double
  ) {
    self.transcriptsProcessed = transcriptsProcessed
    self.entriesInserted = entriesInserted
    self.entriesSkipped = entriesSkipped
    self.errorsEncountered = errorsEncountered
    self.durationSeconds = durationSeconds
  }
}

// MARK: - Default Implementations

/// A no-op event sink that discards all events.
/// Useful as a default when no progress tracking is needed.
public struct NullIngestionEventSink: IngestionEventSink {
  public init() {}

  public func ingestionStarted(runId: String, transcriptCount: Int) {}
  public func progressUpdate(transcriptId: String, entriesInserted: Int, totalEntries: Int?) {}
  public func fileError(path: String, error: String) {}
  public func ingestionCompleted(runId: String, success: Bool, summary: IngestionSummary) {}
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import Foundation

/// Event sink that posts NotificationCenter notifications for UI updates.
/// Used by the macOS app to update progress indicators.
///
/// ## Thread Safety
/// Methods may be called from any thread. Implementation dispatches all notifications
/// to the main queue, ensuring UI observers receive updates on the main thread.
/// The class is `@unchecked Sendable` because `NotificationCenter` is not formally
/// `Sendable`, but is documented as thread-safe for posting notifications.
public final class NotificationCenterEventSink: IngestionEventSink, @unchecked Sendable {
  /// Notification posted when ingestion starts.
  public static let ingestionStartedNotification = Notification.Name("IngestionStarted")

  /// Notification posted for progress updates.
  public static let progressUpdateNotification = Notification.Name("IngestionProgressUpdate")

  /// Notification posted when a file error occurs.
  public static let fileErrorNotification = Notification.Name("IngestionFileError")

  /// Notification posted when ingestion completes.
  public static let ingestionCompletedNotification = Notification.Name("IngestionCompleted")

  /// The notification center to post to.
  private let center: NotificationCenter

  /// Create an event sink that posts to the given notification center.
  ///
  /// - Parameter center: The notification center to use (defaults to `.default`).
  public init(center: NotificationCenter = .default) {
    self.center = center
  }

  public func ingestionStarted(runId: String, transcriptCount: Int) {
    DispatchQueue.main.async { [center] in
      center.post(
        name: Self.ingestionStartedNotification,
        object: nil,
        userInfo: ["runId": runId, "transcriptCount": transcriptCount]
      )
    }
  }

  public func progressUpdate(transcriptId: String, entriesInserted: Int, totalEntries: Int?) {
    DispatchQueue.main.async { [center] in
      var userInfo: [String: Any] = [
        "transcriptId": transcriptId,
        "entriesInserted": entriesInserted
      ]
      if let total = totalEntries {
        userInfo["totalEntries"] = total
      }
      center.post(
        name: Self.progressUpdateNotification,
        object: nil,
        userInfo: userInfo
      )
    }
  }

  public func fileError(path: String, error: String) {
    DispatchQueue.main.async { [center] in
      center.post(
        name: Self.fileErrorNotification,
        object: nil,
        userInfo: ["path": path, "error": error]
      )
    }
  }

  public func ingestionCompleted(runId: String, success: Bool, summary: IngestionSummary) {
    DispatchQueue.main.async { [center] in
      center.post(
        name: Self.ingestionCompletedNotification,
        object: nil,
        userInfo: [
          "runId": runId,
          "success": success,
          "transcriptsProcessed": summary.transcriptsProcessed,
          "entriesInserted": summary.entriesInserted,
          "errorsEncountered": summary.errorsEncountered,
          "durationSeconds": summary.durationSeconds
        ]
      )
    }
  }
}
#endif
