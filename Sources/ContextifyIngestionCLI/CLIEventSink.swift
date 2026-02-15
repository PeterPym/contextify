// SPDX-License-Identifier: MIT
// CLIEventSink.swift - JSONL event output for CLI scripting

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif
import Foundation

/// CLI implementation of IngestionEventSink that outputs JSONL events to stdout.
/// Designed for scripting and automation - each event is a single-line JSON object.
///
/// ## Thread Safety
/// All output (both human and jsonl) is serialized through a single lock.
/// Methods may be called from any thread; all writes are synchronized to prevent interleaving.
public final class CLIEventSink: IngestionEventSink, @unchecked Sendable {

  public enum OutputFormat: Sendable {
    case jsonl      // Machine-readable single-line JSON per event
    case human      // Human-readable progress output
  }

  /// Internal state protected by the lock
  private struct State: Sendable {
    var lastProgressUpdate: Date = .distantPast
  }

  private let format: OutputFormat
  private let outputStream: FileHandle
  private let lock = NSLock()
  private var _state = State()
  private let progressThrottleInterval: TimeInterval = 0.5
  private let quiet: Bool

  public init(format: OutputFormat = .jsonl, outputStream: FileHandle = .standardOutput, quiet: Bool = false) {
    self.format = format
    self.outputStream = outputStream
    self.quiet = quiet
  }

  // MARK: - Private Output Helpers

  /// Write to output stream under lock. All output goes through this method.
  private func writeOutput(_ string: String) {
    lock.lock()
    defer { lock.unlock() }
    outputStream.write(Data(string.utf8))
  }

  /// Write to stderr under lock (for errors).
  private func writeError(_ string: String) {
    lock.lock()
    defer { lock.unlock() }
    FileHandle.standardError.write(Data(string.utf8))
  }

  /// Generate ISO8601 timestamp using value-type formatting (thread-safe).
  private func timestamp() -> String {
    Date().ISO8601Format()
  }

  // MARK: - IngestionEventSink Protocol

  public func ingestionStarted(runId: String, transcriptCount: Int) {
    guard !quiet else { return }
    switch format {
    case .jsonl:
      emitJSON([
        "event": "started",
        "runId": runId,
        "transcriptCount": transcriptCount,
        "timestamp": timestamp()
      ])
    case .human:
      writeOutput("Starting ingestion run: \(runId)\n")
      writeOutput("Total transcripts: \(transcriptCount)\n")
      writeOutput("\n")
    }
  }

  public func progressUpdate(transcriptId: String, entriesInserted: Int, totalEntries: Int?) {
    guard !quiet else { return }
    switch format {
    case .jsonl:
      var output: [String: Any] = [
        "event": "progress",
        "transcriptId": transcriptId,
        "entriesInserted": entriesInserted
      ]
      if let total = totalEntries {
        output["totalEntries"] = total
      }
      emitJSON(output)
    case .human:
      // Throttle human-readable updates - all state access under lock
      let now = Date()
      lock.lock()
      let shouldUpdate = now.timeIntervalSince(_state.lastProgressUpdate) >= progressThrottleInterval
      if shouldUpdate {
        _state.lastProgressUpdate = now
        // Write output while still holding lock to prevent interleaving
        var message = "Processing \(transcriptId): \(entriesInserted) entries"
        if let total = totalEntries {
          message += " / \(total)"
        }
        outputStream.write(Data("\(message)\n".utf8))
      }
      lock.unlock()
    }
  }

  public func fileError(path: String, error: String) {
    switch format {
    case .jsonl:
      emitJSON([
        "event": "fileError",
        "path": path,
        "error": error
      ])
    case .human:
      writeOutput("[ERROR] \(path): \(error)\n")
    }
  }

  public func ingestionCompleted(runId: String, success: Bool, summary: IngestionSummary) {
    guard !quiet else { return }
    switch format {
    case .jsonl:
      emitJSON([
        "event": "completed",
        "runId": runId,
        "success": success,
        "transcriptsProcessed": summary.transcriptsProcessed,
        "entriesInserted": summary.entriesInserted,
        "entriesSkipped": summary.entriesSkipped,
        "errorsEncountered": summary.errorsEncountered,
        "durationSeconds": summary.durationSeconds
      ])
    case .human:
      // Build multi-line output and write atomically under lock
      var output = "\n"
      output += "Ingestion \(success ? "complete" : "failed")!\n"
      output += "  Transcripts processed: \(summary.transcriptsProcessed)\n"
      output += "  Entries inserted: \(summary.entriesInserted)\n"
      output += "  Entries skipped: \(summary.entriesSkipped)\n"
      output += "  Errors: \(summary.errorsEncountered)\n"
      output += "  Duration: \(String(format: "%.2f", summary.durationSeconds))s\n"
      writeOutput(output)
    }
  }

  // MARK: - Private

  private func emitJSON(_ dict: [String: Any]) {
    do {
      let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
      if var json = String(data: data, encoding: .utf8) {
        json.append("\n")
        writeOutput(json)
      }
    } catch {
      writeError("JSON encoding error: \(error)\n")
    }
  }
}
