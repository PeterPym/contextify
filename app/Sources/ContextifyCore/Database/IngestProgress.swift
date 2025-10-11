import Foundation

// MARK: - Progress Protocol

/// Protocol for reporting hoover/stream progress
public protocol IngestProgressSink: AnyObject {
  /// Called once at start. totalLines may be nil if unknown.
  func didStartTranscript(name: String, totalLines: Int?)

  /// Called repeatedly during processing. totalLines can be nil if already provided.
  func didAdvance(linesProcessed: Int, totalLines: Int?)

  func didCompleteTranscript(durationMs: Int)
  func didFailTranscript(error: String)
  func didStartProject(name: String, transcriptCount: Int)
  func didCompleteProject(name: String)
}

// MARK: - No-Op Sink

/// No-op implementation for background tasks
public final class NoOpProgressSink: IngestProgressSink {
  public init() {}

  public func didStartTranscript(name: String, totalLines: Int?) {}
  public func didAdvance(linesProcessed: Int, totalLines: Int?) {}
  public func didCompleteTranscript(durationMs: Int) {}
  public func didFailTranscript(error: String) {}
  public func didStartProject(name: String, transcriptCount: Int) {}
  public func didCompleteProject(name: String) {}
}

// MARK: - Logging Sink

/// Progress sink that logs to OSLog
public final class LoggingProgressSink: IngestProgressSink {
  private let log: Logger

  public init(log: Logger) {
    self.log = log
  }

  public func didStartTranscript(name: String, totalLines: Int?) {
    if let total = totalLines {
      log.info("Starting transcript: \(name) (\(total) lines)")
    } else {
      log.info("Starting transcript: \(name)")
    }
  }

  public func didAdvance(linesProcessed: Int, totalLines: Int?) {
    if let total = totalLines {
      log.debug("Progress: \(linesProcessed)/\(total) lines")
    } else {
      log.debug("Progress: \(linesProcessed) lines")
    }
  }

  public func didCompleteTranscript(durationMs: Int) {
    log.info("Completed transcript in \(durationMs)ms")
  }

  public func didFailTranscript(error: String) {
    log.error("Failed to process transcript: \(error)")
  }

  public func didStartProject(name: String, transcriptCount: Int) {
    log.info("Starting project: \(name) (\(transcriptCount) transcripts)")
  }

  public func didCompleteProject(name: String) {
    log.info("Completed project: \(name)")
  }
}

import OSLog
