import Foundation
import XCTest
@testable import ContextifyCore

final class DatabaseWriteCoordinatorTests: XCTestCase {

  // MARK: - Mutual Exclusion

  func testIngestScopeAcquiredImmediatelyWhenIdle() async {
    let coordinator = DatabaseWriteCoordinator()
    let tracker = OrderTracker()

    await coordinator.withIngestScope {
      await tracker.record("executed")
      let isActive = await coordinator.isIngestActive
      XCTAssertTrue(isActive, "isIngestActive should be true while scope is held")
    }

    let events = await tracker.events
    XCTAssertEqual(events, ["executed"], "Body should have executed")
    let isActive = await coordinator.isIngestActive
    XCTAssertFalse(isActive, "isIngestActive should be false after scope release")
  }

  func testSyncScopeAcquiredImmediatelyWhenIdle() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let tracker = OrderTracker()

    let result = try await coordinator.withSyncScope(timeout: .seconds(5)) {
      await tracker.record("executed")
      let isActive = await coordinator.isSyncActive
      XCTAssertTrue(isActive, "isSyncActive should be true while scope is held")
      return 42
    }

    XCTAssertEqual(result, 42, "Should return body result")
    let events = await tracker.events
    XCTAssertEqual(events, ["executed"], "Body should have executed")
    let isActive = await coordinator.isSyncActive
    XCTAssertFalse(isActive, "isSyncActive should be false after scope release")
  }

  func testSyncBlockedByActiveIngest() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let ingestStarted = expectation(description: "ingest started")
    let syncStarted = expectation(description: "sync started")
    let syncFinished = expectation(description: "sync finished")

    // Track execution order
    let orderTracker = OrderTracker()

    // Task 1: Hold ingest scope for a short time
    Task {
      await coordinator.withIngestScope {
        await orderTracker.record("ingest-acquired")
        ingestStarted.fulfill()
        // Hold scope briefly
        try? await Task.sleep(for: .milliseconds(200))
        await orderTracker.record("ingest-releasing")
      }
    }

    // Wait for ingest to start
    await fulfillment(of: [ingestStarted], timeout: 2)

    // Task 2: Try to acquire sync scope - should wait
    Task {
      syncStarted.fulfill()
      let result = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await orderTracker.record("sync-acquired")
        return true
      }
      XCTAssertEqual(result, true, "Sync should have succeeded after ingest released")
      syncFinished.fulfill()
    }

    await fulfillment(of: [syncStarted, syncFinished], timeout: 5)

    let events = await orderTracker.events
    // Verify ordering: ingest acquired -> ingest releasing -> sync acquired
    XCTAssertEqual(events, ["ingest-acquired", "ingest-releasing", "sync-acquired"])
  }

  func testIngestBlockedByActiveSync() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let syncStarted = expectation(description: "sync started")
    let ingestFinished = expectation(description: "ingest finished")

    let orderTracker = OrderTracker()

    // Task 1: Hold sync scope
    Task {
      let _ = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await orderTracker.record("sync-acquired")
        syncStarted.fulfill()
        try await Task.sleep(for: .milliseconds(200))
        await orderTracker.record("sync-releasing")
      }
    }

    await fulfillment(of: [syncStarted], timeout: 2)

    // Task 2: Ingest should wait
    Task {
      await coordinator.withIngestScope {
        await orderTracker.record("ingest-acquired")
      }
      ingestFinished.fulfill()
    }

    await fulfillment(of: [ingestFinished], timeout: 5)

    let events = await orderTracker.events
    XCTAssertEqual(events, ["sync-acquired", "sync-releasing", "ingest-acquired"])
  }

  // MARK: - Timeout

  func testSyncScopeTimesOutWhenIngestHoldsScope() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let ingestStarted = expectation(description: "ingest started")
    let syncTimedOut = expectation(description: "sync timed out")

    // Task 1: Hold ingest scope longer than sync timeout
    Task {
      await coordinator.withIngestScope {
        ingestStarted.fulfill()
        // Hold scope for longer than sync timeout
        try? await Task.sleep(for: .seconds(2))
      }
    }

    await fulfillment(of: [ingestStarted], timeout: 2)

    // Task 2: Sync should timeout with a short deadline
    Task {
      let result = try await coordinator.withSyncScope(timeout: .milliseconds(200)) {
        XCTFail("Sync body should not execute on timeout")
        return 99
      }
      XCTAssertNil(result, "withSyncScope should return nil on timeout")
      syncTimedOut.fulfill()
    }

    await fulfillment(of: [syncTimedOut], timeout: 3)
  }

  // MARK: - FIFO Ordering

  func testPendingScopesResumeInFIFOOrder() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let holderStarted = expectation(description: "holder started")
    let allFinished = expectation(description: "all finished")

    let orderTracker = OrderTracker()

    // Task 1: Hold the scope
    Task {
      await coordinator.withIngestScope {
        holderStarted.fulfill()
        try? await Task.sleep(for: .milliseconds(300))
      }
    }

    await fulfillment(of: [holderStarted], timeout: 2)

    // Tasks 2 & 3: Queue two waiters
    Task {
      let _ = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await orderTracker.record("waiter-1")
      }
    }

    // Small delay to ensure ordering of enqueue
    try await Task.sleep(for: .milliseconds(50))

    Task {
      await coordinator.withIngestScope {
        await orderTracker.record("waiter-2")
      }
      allFinished.fulfill()
    }

    await fulfillment(of: [allFinished], timeout: 5)

    let events = await orderTracker.events
    XCTAssertEqual(events, ["waiter-1", "waiter-2"], "Waiters should resume in FIFO order")
  }

  // MARK: - Scope State

  func testScopeStateReflectsCurrentHolder() async {
    let coordinator = DatabaseWriteCoordinator()

    // Initially idle
    var ingestActive = await coordinator.isIngestActive
    var syncActive = await coordinator.isSyncActive
    XCTAssertFalse(ingestActive)
    XCTAssertFalse(syncActive)

    // During ingest
    await coordinator.withIngestScope {
      let ia = await coordinator.isIngestActive
      let sa = await coordinator.isSyncActive
      XCTAssertTrue(ia)
      XCTAssertFalse(sa)
    }

    // After release
    ingestActive = await coordinator.isIngestActive
    syncActive = await coordinator.isSyncActive
    XCTAssertFalse(ingestActive)
    XCTAssertFalse(syncActive)
  }

  // MARK: - Error Classification

  func testSyncStateDeferredEquality() {
    XCTAssertEqual(SyncState.deferred, SyncState.deferred)
    XCTAssertNotEqual(SyncState.deferred, SyncState.idle)
    XCTAssertNotEqual(SyncState.deferred, SyncState.syncing)
    XCTAssertNotEqual(SyncState.deferred, SyncState.error("test"))
    XCTAssertNotEqual(SyncState.deferred, SyncState.disabled)
  }

  func testSyncStateEquality() {
    // Verify existing cases still work
    XCTAssertEqual(SyncState.idle, SyncState.idle)
    XCTAssertEqual(SyncState.syncing, SyncState.syncing)
    XCTAssertEqual(SyncState.disabled, SyncState.disabled)
    XCTAssertEqual(SyncState.error("msg"), SyncState.error("msg"))
    XCTAssertNotEqual(SyncState.error("a"), SyncState.error("b"))
    XCTAssertNotEqual(SyncState.idle, SyncState.syncing)
  }

  // MARK: - Concurrent Ingest (Readers-Writer Pattern)

  func testMultipleConcurrentIngestScopesAllowed() async {
    let coordinator = DatabaseWriteCoordinator()
    let bothRunning = expectation(description: "both ingests running concurrently")
    bothRunning.expectedFulfillmentCount = 2

    let tracker = OrderTracker()

    // Two concurrent ingest scopes should both acquire immediately
    Task {
      await coordinator.withIngestScope {
        await tracker.record("ingest-1-start")
        bothRunning.fulfill()
        try? await Task.sleep(for: .milliseconds(200))
        await tracker.record("ingest-1-end")
      }
    }

    Task {
      await coordinator.withIngestScope {
        await tracker.record("ingest-2-start")
        bothRunning.fulfill()
        try? await Task.sleep(for: .milliseconds(200))
        await tracker.record("ingest-2-end")
      }
    }

    await fulfillment(of: [bothRunning], timeout: 2)

    // Both should be active at the same time
    let isActive = await coordinator.isIngestActive
    XCTAssertTrue(isActive, "isIngestActive should be true with concurrent ingests")
  }

  func testSyncBlockedUntilAllConcurrentIngestsFinish() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let bothIngestsStarted = expectation(description: "both ingests started")
    bothIngestsStarted.expectedFulfillmentCount = 2
    let syncCompleted = expectation(description: "sync completed")

    let tracker = OrderTracker()

    // Two concurrent ingests
    Task {
      await coordinator.withIngestScope {
        await tracker.record("ingest-1-start")
        bothIngestsStarted.fulfill()
        try? await Task.sleep(for: .milliseconds(300))
        await tracker.record("ingest-1-end")
      }
    }

    Task {
      await coordinator.withIngestScope {
        await tracker.record("ingest-2-start")
        bothIngestsStarted.fulfill()
        try? await Task.sleep(for: .milliseconds(400))
        await tracker.record("ingest-2-end")
      }
    }

    await fulfillment(of: [bothIngestsStarted], timeout: 2)

    // Sync should wait for BOTH ingests to finish
    Task {
      let result = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await tracker.record("sync-acquired")
        return true
      }
      XCTAssertEqual(result, true)
      syncCompleted.fulfill()
    }

    await fulfillment(of: [syncCompleted], timeout: 5)

    let events = await tracker.events
    // Sync should be after both ingests end
    let syncIndex = events.firstIndex(of: "sync-acquired")!
    let ingest1End = events.firstIndex(of: "ingest-1-end")!
    let ingest2End = events.firstIndex(of: "ingest-2-end")!
    XCTAssertTrue(syncIndex > ingest1End, "Sync should start after ingest 1 finishes")
    XCTAssertTrue(syncIndex > ingest2End, "Sync should start after ingest 2 finishes")
  }

  // MARK: - Second Sync Waiter Guard

  func testSecondSyncWaiterDoesNotOverwriteFirst() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let ingestStarted = expectation(description: "ingest started")
    let syncAResult = expectation(description: "sync A result")
    let syncBResult = expectation(description: "sync B result")

    let tracker = OrderTracker()

    // Hold ingest so both syncs must wait
    Task {
      await coordinator.withIngestScope {
        ingestStarted.fulfill()
        try? await Task.sleep(for: .milliseconds(500))
        await tracker.record("ingest-done")
      }
    }

    await fulfillment(of: [ingestStarted], timeout: 2)

    // Sync A: should queue as the pending waiter
    Task {
      let result = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await tracker.record("sync-A-acquired")
        return "A"
      }
      await tracker.record("sync-A-result-\(result ?? "nil")")
      syncAResult.fulfill()
    }

    // Small delay to ensure A queues first
    try await Task.sleep(for: .milliseconds(50))

    // Sync B: should be rejected immediately (not overwrite A's continuation)
    Task {
      let result = try await coordinator.withSyncScope(timeout: .seconds(5)) {
        await tracker.record("sync-B-acquired")
        return "B"
      }
      await tracker.record("sync-B-result-\(result ?? "nil")")
      syncBResult.fulfill()
    }

    await fulfillment(of: [syncAResult, syncBResult], timeout: 5)

    let events = await tracker.events
    // Sync B should have been rejected (nil result), sync A should have succeeded
    XCTAssertTrue(events.contains("sync-B-result-nil"), "Second sync waiter should be rejected")
    XCTAssertTrue(events.contains("sync-A-result-A"), "First sync waiter should succeed after ingest")
    XCTAssertFalse(events.contains("sync-B-acquired"), "Second sync should never acquire scope")
  }

  // MARK: - Scope Release Between Transcripts

  func testScopeReleasedBetweenConsecutiveIngestCalls() async {
    let coordinator = DatabaseWriteCoordinator()

    // Simulate per-transcript ingest: acquire, do work, release, repeat
    for i in 0..<3 {
      await coordinator.withIngestScope {
        let isActive = await coordinator.isIngestActive
        XCTAssertTrue(isActive, "Scope should be active during transcript \(i)")
      }
      // Between transcripts, scope should be free
      let isActive = await coordinator.isIngestActive
      XCTAssertFalse(isActive, "Scope should be free between transcript \(i) and \(i+1)")
    }
  }

  func testSyncCanRunBetweenIngestTranscripts() async throws {
    let coordinator = DatabaseWriteCoordinator()
    let firstIngestDone = expectation(description: "first ingest done")
    let syncCompleted = expectation(description: "sync completed in gap")

    let orderTracker = OrderTracker()

    // Simulate two transcripts with a sync in between
    Task {
      // Transcript 1
      await coordinator.withIngestScope {
        await orderTracker.record("ingest-1")
      }
      firstIngestDone.fulfill()

      // Brief gap - sync should fit here
      try? await Task.sleep(for: .milliseconds(100))

      // Transcript 2
      await coordinator.withIngestScope {
        await orderTracker.record("ingest-2")
      }
    }

    await fulfillment(of: [firstIngestDone], timeout: 2)

    // Sync should fit in the gap between transcripts
    Task {
      let result = try await coordinator.withSyncScope(timeout: .seconds(2)) {
        await orderTracker.record("sync")
        return true
      }
      XCTAssertNotNil(result, "Sync should have succeeded in the gap")
      syncCompleted.fulfill()
    }

    await fulfillment(of: [syncCompleted], timeout: 5)

    let events = await orderTracker.events
    XCTAssertTrue(events.contains("sync"), "Sync should have executed")
  }
}

// MARK: - Test Helpers

/// Thread-safe helper to track execution order in concurrent tests.
private actor OrderTracker {
  var events: [String] = []

  func record(_ event: String) {
    events.append(event)
  }
}
