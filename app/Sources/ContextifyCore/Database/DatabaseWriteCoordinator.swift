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
/// Uses a readers-writer pattern: multiple ingest scopes can run concurrently
/// (HooverScheduler supports maxConcurrency=6), but sync is exclusive -- it
/// waits for all active ingests to finish, and blocks new ingests while running.
///
/// TranscriptOrchestrator's lightweight writes (via DatabaseWriteQueue)
/// are NOT gated here. They use the main pool's writer with retry logic.
public actor DatabaseWriteCoordinator {
  public static let shared = DatabaseWriteCoordinator()

  /// Number of currently active ingest scopes (0 = no ingest running).
  private var activeIngestCount: Int = 0
  /// Whether a sync scope is currently held.
  private var syncActive: Bool = false
  /// Whether a sync scope is waiting to acquire (blocks new ingest).
  private var syncWaiting: Bool = false

  private var pendingIngestContinuations: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
  private var pendingSyncContinuation: (id: UUID, continuation: CheckedContinuation<Bool, Never>)? = nil

  /// Continuations waiting for ingest to finish (for post-ingest sync trigger).
  private var ingestCompleteContinuations: [CheckedContinuation<Void, Never>] = []

  // MARK: - Public API

  /// Suspends until all active ingest scopes have completed.
  /// Returns immediately if no ingest is active.
  /// Used by CloudSyncManager to trigger sync right after ingest finishes.
  public func waitForIngestComplete() async {
    guard activeIngestCount > 0 else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      ingestCompleteContinuations.append(continuation)
    }
  }

  /// Execute a closure while holding an ingest scope.
  /// Multiple ingest scopes can run concurrently.
  /// If sync is active or waiting, suspends until sync completes.
  public func withIngestScope<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async rethrows -> T {
    await acquireIngest()
    do {
      let result = try await body()
      releaseIngest()
      return result
    } catch {
      releaseIngest()
      throw error
    }
  }

  /// Execute a closure while holding the sync scope (exclusive).
  /// Waits for all active ingest scopes to complete (with timeout).
  /// Returns nil if the timeout expires, allowing the caller to defer.
  public func withSyncScope<T: Sendable>(
    timeout: Duration = .seconds(30),
    _ body: @Sendable () async throws -> T
  ) async rethrows -> T? {
    let acquired = await acquireSync(timeout: timeout)
    guard acquired else { return nil }
    do {
      let result = try await body()
      releaseSync()
      return result
    } catch {
      releaseSync()
      throw error
    }
  }

  /// Whether any ingest scope is currently held.
  public var isIngestActive: Bool { activeIngestCount > 0 }

  /// Whether the sync scope is currently held.
  public var isSyncActive: Bool { syncActive }

  // MARK: - Ingest Scope Management

  private func acquireIngest() async {
    // If sync is active or waiting, suspend until sync finishes
    if syncActive || syncWaiting {
      log.info("Ingest waiting for sync to complete")
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        pendingIngestContinuations.append((id: UUID(), continuation: continuation))
      }
    }
    activeIngestCount += 1
    log.debug("Acquired ingest scope (count: \(self.activeIngestCount, privacy: .public))")
  }

  private func releaseIngest() {
    activeIngestCount = max(0, activeIngestCount - 1)
    log.debug("Released ingest scope (count: \(self.activeIngestCount, privacy: .public))")

    // If all ingests are done and sync is waiting, grant sync
    if activeIngestCount == 0, let pending = pendingSyncContinuation {
      pendingSyncContinuation = nil
      syncActive = true
      syncWaiting = false
      log.debug("All ingests complete, granting sync scope")
      pending.continuation.resume(returning: true)
    }

    // Notify any waitForIngestComplete() callers
    if activeIngestCount == 0 && !ingestCompleteContinuations.isEmpty {
      let waiters = ingestCompleteContinuations
      ingestCompleteContinuations = []
      log.debug("Notifying \(waiters.count, privacy: .public) ingest-complete waiter(s)")
      for waiter in waiters {
        waiter.resume()
      }
    }
  }

  // MARK: - Sync Scope Management

  private func acquireSync(timeout: Duration) async -> Bool {
    if activeIngestCount == 0 && !syncActive {
      syncActive = true
      log.debug("Acquired sync scope immediately")
      return true
    }

    if syncActive || pendingSyncContinuation != nil {
      // Another sync is already running or waiting. Only one sync waiter is
      // supported to avoid overwriting the pending continuation and leaking it.
      log.warning("Sync scope already active or queued, deferring")
      return false
    }

    // Ingest is active -- wait for all to finish
    log.info("Sync waiting for \(self.activeIngestCount, privacy: .public) active ingest(s) to complete")
    syncWaiting = true

    let waiterId = UUID()
    let acquired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      pendingSyncContinuation = (id: waiterId, continuation: continuation)

      Task {
        try? await Task.sleep(for: timeout)
        await self.cancelSyncWaiter(id: waiterId)
      }
    }

    if !acquired {
      syncWaiting = false
      log.info("Sync scope acquisition timed out")
    }
    return acquired
  }

  private func cancelSyncWaiter(id: UUID) {
    guard let pending = pendingSyncContinuation, pending.id == id else {
      return // Already granted
    }
    pendingSyncContinuation = nil
    syncWaiting = false
    pending.continuation.resume(returning: false)
    // Resume any blocked ingest continuations since sync is no longer waiting
    resumePendingIngests()
  }

  private func releaseSync() {
    guard syncActive else {
      log.warning("Attempted to release sync scope but it is not active")
      return
    }
    syncActive = false
    log.debug("Released sync scope")
    // Resume any ingest continuations that were blocked while sync was active
    resumePendingIngests()
  }

  private func resumePendingIngests() {
    guard !pendingIngestContinuations.isEmpty else { return }
    let pending = pendingIngestContinuations
    pendingIngestContinuations = []
    log.debug("Resuming \(pending.count, privacy: .public) pending ingest scope(s)")
    for entry in pending {
      entry.continuation.resume()
    }
  }
}
