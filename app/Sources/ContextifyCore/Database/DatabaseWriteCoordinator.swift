// SPDX-License-Identifier: MIT
// DatabaseWriteCoordinator.swift - Mutual exclusion for sync and ingest write streams

import Foundation

#if canImport(OSLog)
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "WriteCoordinator")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "WriteCoordinator")
#endif

/// Gates heavy write operations (cloud sync pull and bulk ingest) so they
/// never compete for the SQLite WAL writer lock simultaneously.
///
/// This actor does NOT replace DatabaseWriteQueue or BulkIngestManager.
/// It operates at a higher level, ensuring the two heavy write streams
/// (cloud pull and local ingest) are mutually exclusive.
///
/// TranscriptOrchestrator's lightweight writes (via DatabaseWriteQueue)
/// are NOT gated here. They use the main pool's writer with retry logic,
/// which is fast enough to interleave with either heavy writer.
public actor DatabaseWriteCoordinator {
  public static let shared = DatabaseWriteCoordinator()

  private var activeScope: WriteScope? = nil
  private var pendingContinuations: [(id: UUID, scope: WriteScope, continuation: CheckedContinuation<Bool, Never>)] = []

  public enum WriteScope: String, Sendable {
    case ingest
    case sync
  }

  /// Execute a closure while holding the ingest scope.
  /// If sync is active, suspends until sync completes.
  public func withIngestScope<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async rethrows -> T {
    await acquireScope(.ingest)
    defer { releaseScope(.ingest) }
    return try await body()
  }

  /// Execute a closure while holding the sync scope.
  /// If ingest is active, suspends until ingest completes (with timeout).
  /// Returns nil if the timeout expires, allowing the caller to defer.
  public func withSyncScope<T: Sendable>(
    timeout: Duration = .seconds(30),
    _ body: @Sendable () async throws -> T
  ) async rethrows -> T? {
    let acquired = await acquireScopeWithTimeout(.sync, timeout: timeout)
    guard acquired else { return nil }
    defer { releaseScope(.sync) }
    return try await body()
  }

  /// Whether an ingest scope is currently held.
  public var isIngestActive: Bool { activeScope == .ingest }

  /// Whether a sync scope is currently held.
  public var isSyncActive: Bool { activeScope == .sync }

  // MARK: - Internal Scope Management

  private func acquireScope(_ scope: WriteScope) async {
    if activeScope == nil {
      activeScope = scope
      log.debug("Acquired \(scope.rawValue, privacy: .public) scope immediately")
      return
    }
    log.info("Waiting for \(scope.rawValue, privacy: .public) scope (active: \(self.activeScope?.rawValue ?? "none", privacy: .public))")
    let _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      pendingContinuations.append((id: UUID(), scope: scope, continuation: continuation))
    }
    // When resumed by releaseScope -> resumeNextPending, activeScope is already set.
  }

  private func acquireScopeWithTimeout(_ scope: WriteScope, timeout: Duration) async -> Bool {
    if activeScope == nil {
      activeScope = scope
      log.debug("Acquired \(scope.rawValue, privacy: .public) scope immediately")
      return true
    }

    log.info("Waiting for \(scope.rawValue, privacy: .public) scope with timeout (active: \(self.activeScope?.rawValue ?? "none", privacy: .public))")

    let waiterId = UUID()

    // Enqueue the continuation, then race it against a timeout task.
    // The continuation resumes with `true` if the scope was granted,
    // or `false` if the timeout expired and cancelled the waiter.
    let acquired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      pendingContinuations.append((id: waiterId, scope: scope, continuation: continuation))

      // Fire-and-forget timeout task. After the deadline, if this waiter
      // is still pending, cancel it by resuming with false.
      Task { [weak self] in
        try? await Task.sleep(for: timeout)
        await self?.cancelPendingWaiter(id: waiterId)
      }
    }

    if !acquired {
      log.info("Timeout waiting for \(scope.rawValue, privacy: .public) scope")
    }
    return acquired
  }

  /// Cancel a pending waiter by ID. Resumes its continuation with `false`.
  /// No-op if the waiter was already granted (removed from pending list).
  private func cancelPendingWaiter(id: UUID) {
    guard let index = pendingContinuations.firstIndex(where: { $0.id == id }) else {
      // Already granted by resumeNextPending; nothing to do.
      return
    }
    let entry = pendingContinuations.remove(at: index)
    entry.continuation.resume(returning: false)
  }

  private func releaseScope(_ scope: WriteScope) {
    guard activeScope == scope else {
      log.warning("Attempted to release \(scope.rawValue, privacy: .public) scope but active scope is \(self.activeScope?.rawValue ?? "none", privacy: .public)")
      return
    }
    activeScope = nil
    log.debug("Released \(scope.rawValue, privacy: .public) scope")
    resumeNextPending()
  }

  private func resumeNextPending() {
    guard !pendingContinuations.isEmpty else { return }
    let entry = pendingContinuations.removeFirst()
    activeScope = entry.scope
    log.debug("Resumed pending \(entry.scope.rawValue, privacy: .public) scope")
    entry.continuation.resume(returning: true)
  }
}
