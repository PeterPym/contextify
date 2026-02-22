// SPDX-License-Identifier: MIT
// CloudSyncScheduler.swift - Timer-based scheduler for periodic cloud sync

import Foundation

#if canImport(OSLog)
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "CloudSyncScheduler")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "CloudSyncScheduler")
#endif

// MARK: - CloudSyncScheduler

/// Timer-based scheduler that triggers periodic cloud sync operations.
///
/// Wraps a repeating `Timer` that fires at a configurable interval and
/// delegates to `CloudSyncManager.sync(using:)`. The scheduler checks
/// whether a sync is already in progress before triggering, preventing
/// overlapping operations.
///
/// The scheduler does NOT start automatically. Call `start()` after
/// cloud sync has been configured.
///
/// Usage:
/// ```swift
/// let scheduler = CloudSyncScheduler(
///   syncManager: manager,
///   queryService: queryService,
///   interval: 300  // 5 minutes
/// )
/// scheduler.start()
/// // ...later...
/// scheduler.stop()
/// ```
@MainActor
@Observable
public final class CloudSyncScheduler {

  // MARK: - Observable State

  /// Whether the scheduler is currently running.
  public private(set) var isEnabled: Bool = false

  /// When the next scheduled sync will fire, or nil if the scheduler is stopped.
  public private(set) var nextSyncDate: Date?

  // MARK: - Private State

  private var timer: Timer?
  private let interval: TimeInterval
  private weak var syncManager: CloudSyncManager?
  private let queryService: ContextifyQueryService

  // MARK: - Initialization

  /// Creates a new cloud sync scheduler.
  ///
  /// - Parameters:
  ///   - syncManager: The sync manager to trigger on each interval.
  ///   - queryService: The query service passed to `syncManager.sync(using:)`.
  ///   - interval: Time between sync attempts in seconds. Defaults to 300 (5 minutes).
  public init(
    syncManager: CloudSyncManager,
    queryService: ContextifyQueryService,
    interval: TimeInterval = 300
  ) {
    self.syncManager = syncManager
    self.queryService = queryService
    self.interval = interval
  }

  // MARK: - Public Methods

  /// Start the repeating sync timer.
  ///
  /// Creates a `Timer` on the main run loop that fires every `interval` seconds.
  /// If the scheduler is already running, this method stops the existing timer
  /// before creating a new one.
  public func start() {
    if timer != nil {
      log.info("Scheduler already running, restarting timer")
      stopTimer()
    }

    let syncInterval = interval
    let newTimer = Timer.scheduledTimer(
      withTimeInterval: syncInterval,
      repeats: true
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.timerFired()
      }
    }

    timer = newTimer
    isEnabled = true
    nextSyncDate = Date().addingTimeInterval(interval)

    log.info("Scheduler started with interval \(Int(syncInterval), privacy: .public)s, next sync at \(self.nextSyncDate?.description ?? "nil", privacy: .public)")
  }

  /// Stop the repeating sync timer.
  ///
  /// Invalidates the timer and clears the next sync date. The scheduler
  /// can be restarted later by calling `start()`.
  public func stop() {
    stopTimer()
    isEnabled = false
    nextSyncDate = nil

    log.info("Scheduler stopped")
  }

  /// Trigger an immediate sync outside the regular timer schedule.
  ///
  /// After the sync completes (or is skipped), the timer is reset so
  /// the next automatic sync fires a full interval from now.
  public func syncNow() {
    log.info("Immediate sync requested")
    triggerSync()
    resetTimer()
  }

  // MARK: - Private Helpers

  /// Called when the repeating timer fires.
  private func timerFired() {
    log.debug("Timer fired")
    triggerSync()
    nextSyncDate = Date().addingTimeInterval(interval)
  }

  /// Trigger a sync if the manager is not already syncing.
  private func triggerSync() {
    guard let syncManager else {
      log.warning("Sync manager has been deallocated, stopping scheduler")
      stop()
      return
    }

    guard syncManager.syncState != .syncing else {
      log.info("Sync skipped: already syncing")
      return
    }

    let service = queryService
    Task { @MainActor in
      await syncManager.sync(using: service)
    }
  }

  /// Reset the timer by invalidating and recreating it.
  private func resetTimer() {
    guard isEnabled else { return }

    stopTimer()

    let syncInterval = interval
    let newTimer = Timer.scheduledTimer(
      withTimeInterval: syncInterval,
      repeats: true
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.timerFired()
      }
    }

    timer = newTimer
    nextSyncDate = Date().addingTimeInterval(interval)

    log.debug("Timer reset, next sync at \(self.nextSyncDate?.description ?? "nil", privacy: .public)")
  }

  /// Invalidate and nil out the timer without changing isEnabled/nextSyncDate.
  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
}
