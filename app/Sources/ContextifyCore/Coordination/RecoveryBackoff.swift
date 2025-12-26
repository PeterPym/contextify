//
//  RecoveryBackoff.swift
//  ContextifyCore
//
//  Pure value type for recovery backoff logic with exponential delay and failure cap.
//  Extracted from HealthMonitoringCoordinator for testability.
//

import Foundation

/// Pure value type for managing recovery attempt backoff.
///
/// Implements exponential backoff with a failure cap:
/// - 0 failures: no backoff
/// - 1 failure: 60s backoff
/// - 2 failures: 120s backoff
/// - 3 failures: 240s backoff
/// - 4 failures: 480s backoff
/// - 5+ failures: recovery disabled (cap reached)
///
/// Time is injected via `now:` parameter for deterministic testing.
public struct RecoveryBackoff: Sendable, Equatable {
    /// Number of consecutive recovery failures
    public private(set) var failureCount: Int = 0

    /// Timestamp of the last recovery failure
    public private(set) var lastFailure: Date?

    /// Maximum failures before recovery is permanently disabled
    public static let failureCap = 5

    /// Base backoff interval in seconds (doubles with each failure)
    public static let baseBackoffSeconds = 30

    /// Maximum backoff interval in seconds
    public static let maxBackoffSeconds = 600

    public init() {}

    /// Record a recovery success, resetting backoff state.
    public mutating func recordSuccess() {
        failureCount = 0
        lastFailure = nil
    }

    /// Record a recovery failure, incrementing backoff.
    /// - Parameter now: Current time (inject for testing)
    public mutating func recordFailure(now: Date = Date()) {
        failureCount += 1
        lastFailure = now
    }

    /// Reset backoff state (e.g., on project switch).
    public mutating func reset() {
        failureCount = 0
        lastFailure = nil
    }

    /// Check if recovery should be attempted based on backoff state.
    /// - Parameter now: Current time (inject for testing)
    /// - Returns: `true` if recovery should be attempted, `false` if blocked by backoff or cap
    public func shouldAttempt(now: Date = Date()) -> Bool {
        // After failureCap failures, give up permanently
        if failureCount >= Self.failureCap {
            return false
        }

        // No failures = no backoff
        guard failureCount > 0 else {
            return true
        }

        // Calculate exponential backoff: 30 * 2^failureCount, capped at 600s
        let backoffSeconds = min(Self.baseBackoffSeconds * (1 << failureCount), Self.maxBackoffSeconds)

        // Check if we're still within the backoff window
        if let lastFailure = lastFailure,
           now.timeIntervalSince(lastFailure) < Double(backoffSeconds) {
            return false
        }

        return true
    }

    /// Current backoff interval in seconds (0 if no failures).
    public var currentBackoffSeconds: Int {
        guard failureCount > 0 else { return 0 }
        return min(Self.baseBackoffSeconds * (1 << failureCount), Self.maxBackoffSeconds)
    }
}
