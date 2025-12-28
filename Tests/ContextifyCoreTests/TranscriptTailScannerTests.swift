import XCTest
@testable import ContextifyCore

final class TranscriptTailScannerTests: XCTestCase {
  func testHighConfidenceWithMultipleNewEntries() async throws {
    let lines = (0..<6).map { index in
      let timestamp = "2025-12-27T12:00:0\(index)Z"
      return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{}}"#
    }
    let fileURL = try writeTempFile(lines: lines)
    let scanner = TranscriptTailScanner()

    let result = await scanner.scanTail(
      fileURL: fileURL,
      baselineLastEntryTs: Date(timeIntervalSince1970: 0).timeIntervalSince1970,
      baselineFileSize: nil,
      provider: TranscriptProviderID.claude
    )

    XCTAssertEqual(result.confidence, .high)
    XCTAssertEqual(result.approxNewEntries, 6)
  }

  func testMediumConfidenceWithSingleEntry() async throws {
    let lines = [
      #"{"timestamp":"2025-12-27T12:10:00Z","type":"event_msg","payload":{}}"#
    ]
    let fileURL = try writeTempFile(lines: lines)
    let scanner = TranscriptTailScanner()

    let result = await scanner.scanTail(
      fileURL: fileURL,
      baselineLastEntryTs: Date(timeIntervalSince1970: 0).timeIntervalSince1970,
      baselineFileSize: nil,
      provider: TranscriptProviderID.codex
    )

    XCTAssertEqual(result.confidence, .medium)
    XCTAssertEqual(result.approxNewEntries, 1)
  }

  func testTruncationReturnsNilConfidence() async throws {
    let lines = [
      #"{"timestamp":"2025-12-27T12:20:00Z","type":"event_msg","payload":{}}"#
    ]
    let fileURL = try writeTempFile(lines: lines)
    let scanner = TranscriptTailScanner()
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

    let result = await scanner.scanTail(
      fileURL: fileURL,
      baselineLastEntryTs: 0,
      baselineFileSize: currentSize + 10,
      provider: TranscriptProviderID.claude
    )

    XCTAssertNil(result.confidence)
    XCTAssertNil(result.approxNewEntries)
  }

  func testCorruptTailReturnsLowConfidence() async throws {
    let lines = [
      #"{"timestamp":"2025-12-27T12:30:00Z","type":"event_msg","payload":{}}"#,
      "{invalid json",
      "not json"
    ]
    let fileURL = try writeTempFile(lines: lines)
    let scanner = TranscriptTailScanner()

    let result = await scanner.scanTail(
      fileURL: fileURL,
      baselineLastEntryTs: 0,
      baselineFileSize: nil,
      provider: TranscriptProviderID.codex
    )

    XCTAssertEqual(result.confidence, .low)
    XCTAssertNil(result.approxNewEntries)
  }

  private func writeTempFile(lines: [String]) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("tail-scan-\(UUID().uuidString).jsonl")
    let contents = lines.joined(separator: "\n") + "\n"
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }
}
