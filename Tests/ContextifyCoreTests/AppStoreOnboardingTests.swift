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

  func testHasCompletedAppStoreOnboarding_defaultsFalse() {
    // Given: Fresh state (setUp cleared it)

    // When/Then
    XCTAssertFalse(HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  func testSetAppStoreOnboardingCompleted_setsFlag() {
    // Given
    XCTAssertFalse(HUDPreferences.hasCompletedAppStoreOnboarding())

    // When
    HUDPreferences.setAppStoreOnboardingCompleted(true)

    // Then
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  func testSetAppStoreOnboardingCompleted_canToggle() {
    // Given
    HUDPreferences.setAppStoreOnboardingCompleted(true)
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())

    // When
    HUDPreferences.setAppStoreOnboardingCompleted(false)

    // Then
    XCTAssertFalse(HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  func testClearAppStoreOnboardingState_clearsFlag() {
    // Given
    HUDPreferences.setAppStoreOnboardingCompleted(true)
    XCTAssertTrue(HUDPreferences.hasCompletedAppStoreOnboarding())

    // When
    HUDPreferences.clearAppStoreOnboardingState()

    // Then
    XCTAssertFalse(HUDPreferences.hasCompletedAppStoreOnboarding())
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

  // MARK: - Integration Tests

  func testDatabaseManager_unsandboxedBuild_doesNotRequireOnboarding() throws {
    // Given: Unsandboxed build (default for unit tests)
    #if DEBUG
    Sandbox.isSandboxedOverrideForTests = false
    #endif

    // When/Then: Should not throw OnboardingRequiredError
    // Note: We can't actually test openDatabase() without side effects,
    // but we can verify the guard condition logic
    XCTAssertFalse(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  #if DEBUG
  func testDatabaseManager_sandboxedWithoutOnboarding_wouldRequireOnboarding() {
    // Given: Simulated sandbox without onboarding
    Sandbox.isSandboxedOverrideForTests = true
    HUDPreferences.clearAppStoreOnboardingState()

    // Then: The condition that triggers OnboardingRequiredError should be true
    XCTAssertTrue(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
  }

  func testDatabaseManager_sandboxedWithOnboarding_wouldNotRequireOnboarding() {
    // Given: Simulated sandbox WITH onboarding complete
    Sandbox.isSandboxedOverrideForTests = true
    HUDPreferences.setAppStoreOnboardingCompleted(true)

    // Then: The condition that triggers OnboardingRequiredError should be false
    XCTAssertFalse(Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding())
  }
  #endif
}
