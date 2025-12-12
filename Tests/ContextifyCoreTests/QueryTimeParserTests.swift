import XCTest
@testable import ContextifyCore

final class QueryTimeParserTests: XCTestCase {

  func testParseTimestamp_unixSeconds() throws {
    XCTAssertEqual(try QueryTimeParser.parseTimestamp("1700000000"), 1700000000)
  }

  func testParseTimestamp_isoDateOnly() throws {
    XCTAssertEqual(try QueryTimeParser.parseTimestamp("1970-01-01"), 0)
  }

  func testParseTimestamp_isoDateTimeZ() throws {
    XCTAssertEqual(try QueryTimeParser.parseTimestamp("1970-01-01T00:00:01Z"), 1)
  }

  func testParseSinceUntil_daysComputesSince() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let range = try QueryTimeParser.parseSinceUntil(since: nil, until: nil, days: 1, now: now)
    XCTAssertEqual(range.sinceTimestamp, 1000 - 86400)
    XCTAssertNil(range.untilTimestamp)
  }

  func testParseSinceUntil_rejectsDaysWithSinceOrUntil() {
    XCTAssertThrowsError(try QueryTimeParser.parseSinceUntil(since: "0", until: nil, days: 1)) { error in
      XCTAssertTrue(String(describing: error).contains("invalidValue"))
    }
  }

  func testParseSinceUntil_rejectsSinceAfterUntil() {
    XCTAssertThrowsError(try QueryTimeParser.parseSinceUntil(since: "2", until: "1", days: nil)) { error in
      XCTAssertTrue(String(describing: error).contains("invalidValue"))
    }
  }
}

