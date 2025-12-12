import XCTest
@testable import ContextifyCore

final class QueryCLIFeedbackInboxTests: XCTestCase {

  func testRecordListDismissArchiveAndClear() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-feedback-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    let inbox = QueryCLIFeedbackInbox(root: tempRoot) { fixedNow }

    let recorded = try inbox.record(
      summary: "Need transcripts listing",
      intent: "Discover transcript ids",
      gap: "No transcripts command",
      workaround: nil,
      proposal: "Add transcripts command",
      cliVersion: "dev",
      appSchemaVersion: 28,
      capabilities: ["fts_search"],
      force: false
    )

    XCTAssertTrue(recorded.recorded.id.hasPrefix("fb_"))
    XCTAssertTrue(recorded.recorded.path.hasSuffix(".json"))
    XCTAssertEqual(recorded.recorded.summary, "Need transcripts listing")

    let list = try inbox.list()
    XCTAssertEqual(list.count, 1)
    XCTAssertEqual(list.first?.id, recorded.recorded.id)

    let loaded = try inbox.load(id: recorded.recorded.id)
    XCTAssertEqual(loaded.summary, "Need transcripts listing")

    try inbox.dismiss(id: recorded.recorded.id)
    XCTAssertEqual(try inbox.list().count, 0)

    _ = try inbox.record(
      summary: "A",
      intent: nil,
      gap: nil,
      workaround: nil,
      proposal: nil,
      cliVersion: "dev",
      appSchemaVersion: 28,
      capabilities: [],
      force: true
    )
    _ = try inbox.record(
      summary: "B",
      intent: nil,
      gap: nil,
      workaround: nil,
      proposal: nil,
      cliVersion: "dev",
      appSchemaVersion: 28,
      capabilities: [],
      force: true
    )

    let archived = try inbox.archive(olderThanDays: nil)
    XCTAssertEqual(archived, 2)

    _ = try inbox.record(
      summary: "C",
      intent: nil,
      gap: nil,
      workaround: nil,
      proposal: nil,
      cliVersion: "dev",
      appSchemaVersion: 28,
      capabilities: [],
      force: true
    )
    let cleared = try inbox.clearAll()
    XCTAssertEqual(cleared, 1)
  }
}

