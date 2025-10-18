//
//  CircuitBreaker.swift
//  ContextifyCore
//
//  Sliding-window circuit breaker for LLM calls
//  Shared by: TimelineCacheMissGenerator, TranscriptMetadataOrchestrator
//

import Foundation

/// Actor-based circuit breaker with sliding time window
/// Opens when failure rate exceeds threshold over a time window
///
/// Usage:
/// ```swift
/// let breaker = CircuitBreaker(windowSeconds: 300, failureThreshold: 0.6)
///
/// if await breaker.shouldOpen() {
///     // Circuit open - use fallback
/// } else {
///     do {
///         try await dangerousOperation()
///         await breaker.recordSuccess()
///     } catch {
///         await breaker.recordFailure()
///     }
/// }
/// ```
public actor CircuitBreaker {
    private var requestHistory: [RequestOutcome] = []
    private let historyWindowSeconds: TimeInterval
    private let failureThreshold: Double
    private let minimumRequests: Int

    public struct RequestOutcome {
        public let timestamp: Date
        public let success: Bool

        public init(timestamp: Date, success: Bool) {
            self.timestamp = timestamp
            self.success = success
        }
    }

    /// Initialize circuit breaker
    /// - Parameters:
    ///   - windowSeconds: Time window for tracking requests (default: 300s / 5min)
    ///   - failureThreshold: Failure ratio to trigger open (default: 0.6 / 60%)
    ///   - minimumRequests: Minimum requests before opening (default: 5)
    public init(
        windowSeconds: TimeInterval = 300,
        failureThreshold: Double = 0.6,
        minimumRequests: Int = 5
    ) {
        precondition(failureThreshold > 0 && failureThreshold <= 1.0, "Threshold must be in (0, 1]")
        precondition(minimumRequests > 0, "Minimum requests must be positive")

        self.historyWindowSeconds = windowSeconds
        self.failureThreshold = failureThreshold
        self.minimumRequests = minimumRequests
    }

    /// Check if circuit should open (use fallback)
    /// - Returns: true if failure rate exceeds threshold
    public func shouldOpen() -> Bool {
        cleanHistory()
        guard requestHistory.count >= minimumRequests else { return false }

        let failures = requestHistory.filter { !$0.success }.count
        let ratio = Double(failures) / Double(requestHistory.count)
        return ratio >= failureThreshold
    }

    /// Record a successful operation
    public func recordSuccess() {
        requestHistory.append(RequestOutcome(timestamp: Date(), success: true))
        cleanHistory()
    }

    /// Record a failed operation
    public func recordFailure() {
        requestHistory.append(RequestOutcome(timestamp: Date(), success: false))
        cleanHistory()
    }

    /// Reset circuit breaker state (for manual recovery)
    public func reset() {
        requestHistory.removeAll()
    }

    /// Get current statistics (for observability)
    public func stats() -> (total: Int, failures: Int, ratio: Double, isOpen: Bool) {
        cleanHistory()
        let total = requestHistory.count
        let failures = requestHistory.filter { !$0.success }.count
        let ratio = total > 0 ? Double(failures) / Double(total) : 0.0
        let isOpen = total >= minimumRequests && ratio >= failureThreshold

        return (total, failures, ratio, isOpen)
    }

    // MARK: - Private

    private func cleanHistory() {
        let cutoff = Date().addingTimeInterval(-historyWindowSeconds)
        requestHistory.removeAll { $0.timestamp < cutoff }
    }
}
