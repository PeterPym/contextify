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
/// - Cache bookmark validity to avoid repeated resolution
///
/// **Usage:**
/// - Inject as `@ObservedObject` in `ContextifyApp`
/// - Check `shouldShowWizard` to gate main app content
/// - Call `markComplete()` when wizard finishes
/// - Call `markBookmarkStale()` if bookmark resolution fails
@MainActor
public final class AppStoreOnboardingCoordinator: ObservableObject {
  public static let shared = AppStoreOnboardingCoordinator()

  /// Published completion state. For App Store builds: flag AND valid bookmark.
  /// For DMG builds: always true.
  @Published public private(set) var isComplete: Bool

  /// Cached bookmark validity to avoid expensive resolution on every access.
  private var cachedBookmarkValid: Bool?
  private var lastBookmarkCheckTime: Date?
  private let bookmarkCacheDuration: TimeInterval = 5.0  // Re-check every 5 seconds max

  private init() {
    // DMG builds: always complete (no onboarding required)
    // App Store builds: check flag AND bookmark validity
    if !Sandbox.isSandboxed {
      self.isComplete = true
      log.info("[ONBOARD-INIT] DMG build detected, onboarding not required")
    } else {
      let flagSet = HUDPreferences.hasCompletedAppStoreOnboarding()
      let bookmarkValid = Self.validateDatabaseBookmark()
      self.isComplete = flagSet && bookmarkValid
      log.info("[ONBOARD-INIT] App Store build: flag=\(flagSet), bookmark=\(bookmarkValid), complete=\(self.isComplete)")
    }
  }

  /// Returns true if the onboarding wizard should be shown.
  /// Only true for App Store (sandboxed) builds that haven't completed onboarding.
  public var shouldShowWizard: Bool {
    Sandbox.isSandboxed && !isComplete
  }

  /// Mark onboarding as complete. Called when user finishes the wizard.
  public func markComplete() {
    guard Sandbox.isSandboxed else {
      log.warning("[ONBOARD-COMPLETE] markComplete() called in DMG build (no-op)")
      return
    }

    HUDPreferences.setAppStoreOnboardingCompleted(true)
    cachedBookmarkValid = true
    lastBookmarkCheckTime = Date()
    isComplete = true
    log.info("[ONBOARD-COMPLETE] Onboarding marked complete")
  }

  /// Mark the database bookmark as stale/invalid.
  /// Clears completion state and triggers re-onboarding.
  public func markBookmarkStale() {
    guard Sandbox.isSandboxed else {
      log.warning("[ONBOARD-STALE] markBookmarkStale() called in DMG build (no-op)")
      return
    }

    HUDPreferences.clearAppStoreOnboardingState()
    cachedBookmarkValid = false
    lastBookmarkCheckTime = nil
    isComplete = false
    log.warning("[ONBOARD-STALE] Bookmark marked stale, onboarding reset")
  }

  /// Refresh state by re-evaluating bookmark validity.
  /// Called on app activation to detect if bookmark folder was deleted.
  public func refreshState() {
    guard Sandbox.isSandboxed else { return }

    let now = Date()
    if let lastCheck = lastBookmarkCheckTime,
       now.timeIntervalSince(lastCheck) < bookmarkCacheDuration {
      // Skip re-check if we checked recently
      return
    }

    let flagSet = HUDPreferences.hasCompletedAppStoreOnboarding()
    let bookmarkValid = Self.validateDatabaseBookmark()
    let newComplete = flagSet && bookmarkValid

    if newComplete != isComplete {
      log.info("[ONBOARD-REFRESH] State changed: flag=\(flagSet), bookmark=\(bookmarkValid), complete=\(newComplete)")
      isComplete = newComplete
    }

    cachedBookmarkValid = bookmarkValid
    lastBookmarkCheckTime = now
  }

  // MARK: - Private Helpers

  /// Validates that the database bookmark resolves to an accessible directory.
  private static func validateDatabaseBookmark() -> Bool {
    guard let url = HUDPreferences.resolveDatabaseBookmark() else {
      return false
    }

    // Check if directory exists and is accessible
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
  }
}

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when user resets database location in Settings (App Store builds).
  /// Triggers re-display of onboarding wizard.
  public static let databaseLocationReset = Notification.Name("dev.contextify.databaseLocationReset")
}
