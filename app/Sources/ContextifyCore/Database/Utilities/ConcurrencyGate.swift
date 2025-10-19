//
//  ConcurrencyGate.swift
//  ContextifyCore
//
//  Continuation-based concurrency gate (no spin-wait, cancellation-safe)
//  Shared by: TimelineCacheMissGenerator, TranscriptMetadataOrchestrator
//

import Foundation

/// Actor-based concurrency gate using continuations with proper cancellation handling
/// Limits concurrent access to a shared resource (e.g., LLM API)
///
/// Usage:
/// ```swift
/// let gate = ConcurrencyGate(permits: 2)  // Max 2 concurrent
///
/// await gate.acquire()
/// defer { Task { await gate.release() } }
/// // ... protected work ..
/// ```
public actor ConcurrencyGate {
    private let maxPermits: Int
    private var availablePermits: Int
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Initialize gate with maximum concurrent permits
    /// - Parameter permits: Maximum number of concurrent acquisitions
    public init(permits: Int) {
        precondition(permits > 0, "Permits must be positive")
        self.maxPermits = permits
        self.availablePermits = permits
    }

    /// Acquire a permit (suspends if none available)
    /// Always pair with `release()` in a defer block
    /// Handles task cancellation gracefully
    public func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        // No permits available - wait in queue with cancellation support
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
    }

    /// Release a permit (resumes next waiter if any)
    public func release() {
        if let (id, continuation) = waiters.first {
            waiters.removeValue(forKey: id)
            continuation.resume()
        } else {
            availablePermits = min(availablePermits + 1, maxPermits)
        }
    }

    /// Cancel a specific waiter (for cancellation support)
    /// - Parameter id: UUID of waiter to cancel
    private func cancelWaiter(_ id: UUID) {
        _ = waiters.removeValue(forKey: id)
    }

    /// Current number of available permits (for debugging)
    public var available: Int {
        availablePermits
    }

    /// Current number of waiting tasks (for debugging)
    public var queueDepth: Int {
        waiters.count
    }
}
