//
//  AppStoreOnboardingCoordinator.swift
//  Contextify
//
//  Central coordinator for App Store onboarding state.
//  Manages the two-step wizard that ensures users choose a database location
//  and grant transcript permissions before the app can proceed.
//

import SwiftUI
import Combine
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Coordinates App Store onboarding state for the mandatory first-run wizard.
///
/// **Responsibilities:**
/// - Own and publish onboarding completion state
/// - Provide single source of truth for wizard visibility
/// - Handle state transitions (complete, stale bookmark)
///
/// **Usage:**
/// - Inject as `@ObservedObject` in `ContextifyApp`
/// - Check `shouldShowWizard` to gate main app content
/// - Call `markComplete()` when wizard finishes
/// - Call `markBookmarkStale()` if bookmark resolution fails
@MainActor
public final class AppStoreOnboardingCoordinator: ObservableObject {
  public static let shared = AppStoreOnboardingCoordinator()

  /// Published completion state. Delegates to unified HUDPreferences check.
  /// For App Store builds: flag AND valid bookmark.
  /// For DMG builds: always true.
  @Published public private(set) var isComplete: Bool

  /// True while the onComplete Task is running the post-onboarding startup sequence.
  /// Used to prevent the main window's .task from racing with onComplete.
  /// Set by markComplete(), cleared by the onComplete Task when done.
  @Published public private(set) var isHandlingCompletion: Bool = false

  /// Throttle refreshState() calls to avoid expensive bookmark resolution
  private var lastRefreshTime: Date?
  private let refreshThrottleDuration: TimeInterval = 5.0

  private init() {
    // Use unified definition from HUDPreferences
    self.isComplete = HUDPreferences.hasCompletedAppStoreOnboarding()
    log.info("[ONBOARD-INIT] isComplete=\(self.isComplete)")
  }

  /// Returns true if the onboarding wizard should be shown.
  /// Only true for builds that haven't completed onboarding.
  public var shouldShowWizard: Bool {
    !isComplete
  }

  /// Mark onboarding as complete. Called when user finishes the wizard.
  ///
  /// Sets `isHandlingCompletion = true` BEFORE `isComplete = true` to prevent the
  /// main window's `.task` from racing with the `onComplete` Task. The onComplete
  /// Task owns the full startup sequence and must call `finishHandlingCompletion()`
  /// when done.
  public func markComplete() {
    // CRITICAL: Set this BEFORE isComplete to prevent race with .task
    isHandlingCompletion = true

    HUDPreferences.setAppStoreOnboardingCompleted(true)
    isComplete = true
    lastRefreshTime = Date()
    log.info("[ONBOARD-COMPLETE] Onboarding marked complete (isHandlingCompletion=true)")

    // NOTE: DB initialization moved to onComplete async Task to avoid blocking UI.
    // The wizard dismisses immediately; startup sequence runs in background.
  }

  /// Called by the onComplete Task after the post-onboarding startup sequence finishes.
  /// Clears `isHandlingCompletion` flag.
  public func finishHandlingCompletion() {
    isHandlingCompletion = false
    log.info("[ONBOARD-COMPLETE] Startup sequence finished (isHandlingCompletion=false)")
  }

  /// Mark the database bookmark as stale/invalid.
  /// Clears completion state and triggers re-onboarding.
  public func markBookmarkStale() {
    HUDPreferences.clearAppStoreOnboardingState()
    isComplete = false
    lastRefreshTime = nil
    log.warning("[ONBOARD-STALE] Bookmark marked stale, onboarding reset")
  }

  /// Refresh state by re-evaluating onboarding completion.
  /// Called on app activation to detect if bookmark folder was deleted.
  public func refreshState() {
    let now = Date()
    if let lastCheck = lastRefreshTime,
       now.timeIntervalSince(lastCheck) < refreshThrottleDuration {
      return  // Throttle expensive bookmark resolution
    }

    let newComplete = HUDPreferences.hasCompletedAppStoreOnboarding()
    if newComplete != isComplete {
      log.info("[ONBOARD-REFRESH] State changed: complete=\(newComplete)")
      isComplete = newComplete
    }
    lastRefreshTime = now
  }
}

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when user resets database location in Settings (App Store builds).
  /// Triggers re-display of onboarding wizard.
  public static let databaseLocationReset = Notification.Name("dev.contextify.databaseLocationReset")
}
