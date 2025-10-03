import XCTest
@testable import ContextifyCore

final class ContextifyTests: XCTestCase {
  @MainActor
  func testInitialStateDefaults() throws {
    let viewModel = HUDViewModel()
    XCTAssertEqual(viewModel.status, "Ready")
    XCTAssertEqual(viewModel.branchDisplay, "—")
  }
}
