import XCTest
import ContextifyCore

final class QueryCLIShimMarkerTests: XCTestCase {
  func testDataContainsMarker_falseWhenMissing() {
    let data = Data("hello world".utf8)
    XCTAssertFalse(ContextifyQueryShimMarker.dataContainsMarker(data))
  }

  func testDataContainsMarker_trueWhenPresent() {
    let data = Data(("xx" + ContextifyQueryShimMarker.markerString + "yy").utf8)
    XCTAssertTrue(ContextifyQueryShimMarker.dataContainsMarker(data))
  }
}

