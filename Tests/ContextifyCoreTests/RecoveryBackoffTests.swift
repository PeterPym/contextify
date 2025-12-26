//
//  RecoveryBackoffTests.swift
//  ContextifyCoreTests
//
//  Tests for RecoveryBackoff pure backoff logic.
//

import XCTest
@testable import ContextifyCore

final class RecoveryBackoffTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsZeroFailures() {
        let backoff = RecoveryBackoff()

        XCTAssertEqual(backoff.failureCount, 0)
        XCTAssertNil(backoff.lastFailure)
        XCTAssertEqual(backoff.currentBackoffSeconds, 0)
    }

    func testInitialStateShouldAttempt() {
        let backoff = RecoveryBackoff()

        XCTAssertTrue(backoff.shouldAttempt())
    }

    // MARK: - Record Failure

    func testRecordFailureIncrementsCount() {
        var backoff = RecoveryBackoff()
        let now = Date()

        backoff.recordFailure(now: now)

        XCTAssertEqual(backoff.failureCount, 1)
        XCTAssertEqual(backoff.lastFailure, now)
    }

    func testMultipleFailuresAccumulate() {
        var backoff = RecoveryBackoff()
        let now = Date()

        backoff.recordFailure(now: now)
        backoff.recordFailure(now: now)
        backoff.recordFailure(now: now)

        XCTAssertEqual(backoff.failureCount, 3)
    }

    func testRecordFailureSetsLastFailure() {
        var backoff = RecoveryBackoff()
        let timestamp = Date(timeIntervalSince1970: 1000)

        backoff.recordFailure(now: timestamp)

        XCTAssertEqual(backoff.lastFailure, timestamp)
    }

    // MARK: - Record Success

    func testRecordSuccessResetsState() {
        var backoff = RecoveryBackoff()
        let now = Date()

        backoff.recordFailure(now: now)
        backoff.recordFailure(now: now)
        backoff.recordSuccess()

        XCTAssertEqual(backoff.failureCount, 0)
        XCTAssertNil(backoff.lastFailure)
    }

    // MARK: - Reset

    func testResetResetsState() {
        var backoff = RecoveryBackoff()
        let now = Date()

        backoff.recordFailure(now: now)
        backoff.recordFailure(now: now)
        backoff.reset()

        XCTAssertEqual(backoff.failureCount, 0)
        XCTAssertNil(backoff.lastFailure)
    }

    // MARK: - Failure Cap

    func testFailureCapDisablesRecovery() {
        var backoff = RecoveryBackoff()
        let now = Date()
        let later = now.addingTimeInterval(10000)  // Way past any backoff

        // Record exactly failureCap failures
        for _ in 0..<RecoveryBackoff.failureCap {
            backoff.recordFailure(now: now)
        }

        // Should be disabled even with time passed
        XCTAssertFalse(backoff.shouldAttempt(now: later))
        XCTAssertEqual(backoff.failureCount, RecoveryBackoff.failureCap)
    }

    func testJustBelowFailureCapAllowsRecovery() {
        var backoff = RecoveryBackoff()
        let now = Date()
        let later = now.addingTimeInterval(10000)  // Way past any backoff

        // Record failureCap - 1 failures
        for _ in 0..<(RecoveryBackoff.failureCap - 1) {
            backoff.recordFailure(now: now)
        }

        // Should still be allowed (after backoff window)
        XCTAssertTrue(backoff.shouldAttempt(now: later))
    }

    // MARK: - Exponential Backoff

    func testBackoffWindowBlocksRecovery() {
        var backoff = RecoveryBackoff()
        let failureTime = Date()

        backoff.recordFailure(now: failureTime)

        // Immediately after failure, should be blocked
        XCTAssertFalse(backoff.shouldAttempt(now: failureTime))

        // Still within backoff window (1 failure = 60s backoff)
        let withinWindow = failureTime.addingTimeInterval(30)
        XCTAssertFalse(backoff.shouldAttempt(now: withinWindow))
    }

    func testBackoffWindowExpiryAllowsRecovery() {
        var backoff = RecoveryBackoff()
        let failureTime = Date()

        backoff.recordFailure(now: failureTime)

        // 1 failure = 60s backoff, check at 61s
        let afterWindow = failureTime.addingTimeInterval(61)
        XCTAssertTrue(backoff.shouldAttempt(now: afterWindow))
    }

    func testExponentialBackoffDoubles() {
        var backoff = RecoveryBackoff()
        let failureTime = Date()

        // 1 failure = 60s backoff
        backoff.recordFailure(now: failureTime)
        XCTAssertEqual(backoff.currentBackoffSeconds, 60)

        // 2 failures = 120s backoff
        backoff.recordFailure(now: failureTime)
        XCTAssertEqual(backoff.currentBackoffSeconds, 120)

        // 3 failures = 240s backoff
        backoff.recordFailure(now: failureTime)
        XCTAssertEqual(backoff.currentBackoffSeconds, 240)

        // 4 failures = 480s backoff
        backoff.recordFailure(now: failureTime)
        XCTAssertEqual(backoff.currentBackoffSeconds, 480)
    }

    func testBackoffCapsAtMaximum() {
        var backoff = RecoveryBackoff()
        let failureTime = Date()

        // Push past what would be 600s
        for _ in 0..<10 {
            backoff.recordFailure(now: failureTime)
        }

        // Should not exceed maxBackoffSeconds
        XCTAssertLessThanOrEqual(backoff.currentBackoffSeconds, RecoveryBackoff.maxBackoffSeconds)
    }

    // MARK: - Equatable

    func testEquatableInitialState() {
        let a = RecoveryBackoff()
        let b = RecoveryBackoff()

        XCTAssertEqual(a, b)
    }

    func testEquatableAfterSameFailures() {
        var a = RecoveryBackoff()
        var b = RecoveryBackoff()
        let now = Date()

        a.recordFailure(now: now)
        b.recordFailure(now: now)

        XCTAssertEqual(a, b)
    }

    func testNotEqualWithDifferentCounts() {
        var a = RecoveryBackoff()
        var b = RecoveryBackoff()
        let now = Date()

        a.recordFailure(now: now)
        b.recordFailure(now: now)
        b.recordFailure(now: now)

        XCTAssertNotEqual(a, b)
    }

    // MARK: - Constants

    func testConstantsAreCorrect() {
        XCTAssertEqual(RecoveryBackoff.failureCap, 5)
        XCTAssertEqual(RecoveryBackoff.baseBackoffSeconds, 30)
        XCTAssertEqual(RecoveryBackoff.maxBackoffSeconds, 600)
    }
}
