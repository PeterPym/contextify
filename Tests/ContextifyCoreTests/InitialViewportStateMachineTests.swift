import XCTest
@testable import ContextifyCore

final class InitialViewportStateMachineTests: XCTestCase {
  func testBeginAwaitingIsIdempotentForSameContext() {
    var machine = InitialViewportStateMachine()
    XCTAssertTrue(machine.beginAwaiting(projectId: "proj", sessionId: "session"))
    XCTAssertTrue(machine.isAwaiting)
    XCTAssertEqual(machine.awaitingContext?.projectId, "proj")
    XCTAssertFalse(machine.beginAwaiting(projectId: "proj", sessionId: "session"))
  }

  func testSnapshotAcceptanceTransitionsAndStopsRearming() {
    var machine = InitialViewportStateMachine()
    XCTAssertTrue(machine.beginAwaiting(projectId: "proj", sessionId: nil))
    XCTAssertTrue(machine.acceptSnapshot(projectId: "proj", sessionId: nil))
    XCTAssertTrue(machine.isSnapshotAccepted)
    XCTAssertFalse(machine.beginAwaiting(projectId: "proj", sessionId: nil))
  }

  func testDifferentProjectOrSessionRestartsAwaitingState() {
    var machine = InitialViewportStateMachine()
    XCTAssertTrue(machine.beginAwaiting(projectId: "projA", sessionId: "first"))
    XCTAssertTrue(machine.beginAwaiting(projectId: "projB", sessionId: "first"))
    XCTAssertTrue(machine.isAwaiting)
    XCTAssertEqual(machine.awaitingContext?.projectId, "projB")
    XCTAssertTrue(machine.beginAwaiting(projectId: "projB", sessionId: "other"))
    XCTAssertEqual(machine.awaitingContext?.sessionId, "other")
  }

  func testResetReturnsToIdle() {
    var machine = InitialViewportStateMachine()
    XCTAssertTrue(machine.beginAwaiting(projectId: "proj", sessionId: nil))
    machine.acceptSnapshot(projectId: "proj", sessionId: nil)
    XCTAssertTrue(machine.isSnapshotAccepted)
    machine.reset()
    XCTAssertFalse(machine.isAwaiting)
    XCTAssertFalse(machine.isSnapshotAccepted)
    XCTAssertNil(machine.activeContext)
  }
}
