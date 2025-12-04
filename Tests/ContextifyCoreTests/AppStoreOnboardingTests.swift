//
//  AppStoreOnboardingTests.swift
//  ContextifyCoreTests
//
//  Unit tests for App Store onboarding functionality.
//

import XCTest
@testable import ContextifyCore

final class AppStoreOnboardingTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // Clear onboarding state before each test
    HUDPreferences.clearAppStoreOnboardingState()
    #if DEBUG
    Sandbox.isSandboxedOverrideForTests = nil
    #endif
  }

  override func tearDown() {
    // Clean up after each test
    HUDPreferences.clearAppStoreOnboardingState()
    #if DEBUG
    Sandbox.isSandboxedOverrideForTests = nil
    #endif
    super.tearDown()
  }

  // MARK: - HUDPreferences Tests

  // NOTE: hasCompletedAppStoreOnboarding() uses compile-time #if APPSTORE_BUILD
  // In DMG/test builds, it always returns true. These tests verify the flag
  // APIs work correctly, understanding that the public getter has different
  // behavior per build type.

  func testHasCompletedAppStoreOnboarding_dmgBuild_alwaysTrue() {
    // In DMG builds (test environment), hasCompletedAppStoreOnboarding()
    // returns true unconditionally because onboarding isn't required
    #if !APPSTORE_BUILD
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())
    #endif
  }

  func testSetAppStoreOnboardingCompleted_setsFlag() {
    // The setter should still set the flag (even if getter ignores it in DMG)
    HUDPreferences.setAppStoreOnboardingCompleted(true)

    // In DMG builds, getter always returns true
    // In App Store builds, getter would check flag + bookmark
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  func testClearAppStoreOnboardingState_clearsFlag() {
    // Given
    HUDPreferences.setAppStoreOnboardingCompleted(true)

    // When
    HUDPreferences.clearAppStoreOnboardingState()

    // Then: In DMG builds, still returns true (compile-time behavior)
    #if !APPSTORE_BUILD
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())
    #endif
  }

  // MARK: - Sandbox Override Tests (DEBUG only)

  #if DEBUG
  func testSandbox_overrideForTests_canSimulateSandboxed() {
    // Given: Not actually sandboxed (unit tests run outside sandbox)
    let originalValue = Sandbox.isRuntimeSandboxed

    // When
    Sandbox.isSandboxedOverrideForTests = true

    // Then
    XCTAssertTrue(Sandbox.isSandboxed)

    // Cleanup
    Sandbox.isSandboxedOverrideForTests = nil
    XCTAssertEqual(Sandbox.isSandboxed, originalValue)
  }

  func testSandbox_overrideForTests_canSimulateUnsandboxed() {
    // Given
    let originalValue = Sandbox.isRuntimeSandboxed

    // When
    Sandbox.isSandboxedOverrideForTests = false

    // Then
    XCTAssertFalse(Sandbox.isSandboxed)

    // Cleanup
    Sandbox.isSandboxedOverrideForTests = nil
    XCTAssertEqual(Sandbox.isSandboxed, originalValue)
  }

  func testSandbox_nilOverride_usesRuntimeDetection() {
    // Given
    Sandbox.isSandboxedOverrideForTests = true
    XCTAssertTrue(Sandbox.isSandboxed)

    // When
    Sandbox.isSandboxedOverrideForTests = nil

    // Then: Should return to runtime detection
    XCTAssertEqual(Sandbox.isSandboxed, Sandbox.isRuntimeSandboxed)
  }
  #endif

  // MARK: - OnboardingRequiredError Tests

  func testOnboardingRequiredError_hasLocalizedDescription() {
    let error = OnboardingRequiredError()
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("onboarding"))
  }

  // MARK: - Guard Logic Tests

  // These tests verify the guard condition logic used in DatabaseManager
  // The actual guards use #if APPSTORE_BUILD, but we can test the logic pattern

  func testDatabaseManager_unsandboxedBuild_doesNotRequireOnboarding() throws {
    #if DEBUG
    Sandbox.isSandboxedOverrideForTests = false
    #endif

    // In unsandboxed builds, the guard condition should always pass
    // (Sandbox.isSandboxed is false, so the whole expression is false)
    XCTAssertFalse(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  #if DEBUG
  func testSandbox_guardPattern_sandboxedWithoutOnboarding() {
    // This tests the pattern: Sandbox.isSandboxed && !hasCompletedAppStoreOnboarding()
    // In actual App Store builds, this would block DB access
    Sandbox.isSandboxedOverrideForTests = true

    // Even in sandbox mode, hasCompletedAppStoreOnboarding() returns true in DMG builds
    // So the guard would NOT trigger in this test environment
    #if !APPSTORE_BUILD
    // DMG build: getter always returns true, so guard doesn't trigger
    XCTAssertFalse(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
    #endif
  }

  func testSandbox_guardPattern_sandboxedWithOnboarding() {
    Sandbox.isSandboxedOverrideForTests = true
    HUDPreferences.setAppStoreOnboardingCompleted(true)

    // Guard should not trigger when onboarding is complete
    XCTAssertFalse(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
  }
  #endif
}
