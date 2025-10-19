//
//  CircuitBreaker.swift
//  ContextifyCore
//
//  Sliding-window circuit breaker for LLM calls with half-open recovery
//  Shared by: TimelineCacheMissGenerator, TranscriptMetadataOrchestrator
//

import Foundation

/// Actor-based circuit breaker with sliding time window and half-open recovery
/// Opens when failure rate exceeds threshold over a time window
///
/// States:
/// - closed: Normal operation, requests allowed
/// - open: Failure threshold exceeded, requests blocked until cooldown expires
/// - halfOpen: Cooldown expired, testing recovery with limited requests
///
/// Usage:
/// ```swift
/// let breaker = CircuitBreaker(windowSeconds: 300, failureThreshold: 0.6)
///
/// if await breaker.allow() {
///     do {
///         try await dangerousOperation()
///         await breaker.record(success: true)
///     } catch {
///         await breaker.record(success: false)
///     }
/// } else {
///     // Circuit open - use fallback
/// }
/// ```
public actor CircuitBreaker {
    public enum State: Equatable, Sendable {
        case closed
        case open(until: Date)
        case halfOpen
    }

    private var outcomes: [(timestamp: Date, success: Bool)] = []
    private let historyWindowSeconds: TimeInterval
    private let failureThreshold: Double
    private let minimumRequests: Int
    private let cooldownSeconds: TimeInterval

    private(set) var state: State = .closed

    /// Initialize circuit breaker
    /// - Parameters:
    ///   - windowSeconds: Time window for tracking requests (default: 300s / 5min)
    ///   - failureThreshold: Failure ratio to trigger open (default: 0.6 / 60%)
    ///   - minimumRequests: Minimum requests before opening (default: 5)
    ///   - cooldownSeconds: Time to wait before attempting recovery (default: 60s)
    public init(
        windowSeconds: TimeInterval = 300,
        failureThreshold: Double = 0.6,
        minimumRequests: Int = 5,
        cooldownSeconds: TimeInterval = 60
    ) {
        precondition(failureThreshold > 0 && failureThreshold <= 1.0, "Threshold must be in (0, 1]")
        precondition(minimumRequests > 0, "Minimum requests must be positive")
        precondition(cooldownSeconds > 0, "Cooldown must be positive")

        self.historyWindowSeconds = windowSeconds
        self.failureThreshold = failureThreshold
        self.minimumRequests = minimumRequests
        self.cooldownSeconds = cooldownSeconds
    }

    /// Check if request is allowed
    /// - Returns: true if request should proceed, false if circuit is open
    public func allow() -> Bool {
        cleanHistory()

        switch state {
        case .closed:
            return true
        case .open(let until):
            if Date() >= until {
                // Cooldown expired - transition to half-open
                state = .halfOpen
                return true
            } else {
                return false
            }
        case .halfOpen:
            // In half-open state, allow requests to test recovery
            return true
        }
    }

    /// Record operation result
    /// - Parameter success: true if operation succeeded, false if failed
    public func record(success: Bool) {
        outcomes.append((Date(), success))
        cleanHistory()

        let total = outcomes.count
        let failures = outcomes.filter { !$0.success }.count
        let failureRate = total == 0 ? 0.0 : Double(failures) / Double(total)

        switch state {
        case .closed:
            // Check if we should open
            if total >= minimumRequests && failureRate >= failureThreshold {
                state = .open(until: Date().addingTimeInterval(cooldownSeconds))
            }

        case .open:
            // Stay open (cooldown handled in allow())
            break

        case .halfOpen:
            if success {
                // Success in half-open - transition to closed
                state = .closed
                // Clear history to start fresh
                outcomes.removeAll()
            } else {
                // Failure in half-open - reopen circuit
                state = .open(until: Date().addingTimeInterval(cooldownSeconds))
            }
        }
    }

    /// Record a successful operation (convenience)
    public func recordSuccess() {
        record(success: true)
    }

    /// Record a failed operation (convenience)
    public func recordFailure() {
        record(success: false)
    }

    /// Reset circuit breaker state (for manual recovery)
    public func reset() {
        outcomes.removeAll()
        state = .closed
    }

    /// Get current statistics (for observability)
    public func stats() -> (total: Int, failures: Int, ratio: Double, isOpen: Bool, state: State) {
        cleanHistory()
        let total = outcomes.count
        let failures = outcomes.filter { !$0.success }.count
        let ratio = total > 0 ? Double(failures) / Double(total) : 0.0
        let isOpen: Bool
        switch state {
        case .open, .halfOpen: isOpen = true
        case .closed:          isOpen = false
        }

        return (total, failures, ratio, isOpen, state)
    }

    /// Check if circuit should open based on current state
    /// - Returns: true if circuit should be open (for compatibility with old API)
    public func shouldOpen() -> Bool {
        return !allow()
    }

    // MARK: - Private

    private func cleanHistory() {
        let cutoff = Date().addingTimeInterval(-historyWindowSeconds)
        outcomes.removeAll { $0.timestamp < cutoff }
    }
}
