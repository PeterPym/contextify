import XCTest
@testable import ContextifyCore

final class MenuBarStatusTests: XCTestCase {
  override func setUp() {
    super.setUp()
    HUDPreferences.setBackgroundUtilityModeEnabled(false)
    HUDPreferences.setMenuBarExtraEnabled(false)
  }

  override func tearDown() {
    HUDPreferences.setBackgroundUtilityModeEnabled(false)
    HUDPreferences.setMenuBarExtraEnabled(false)
    super.tearDown()
  }

  func testResolvedMenuBarExtraEnabled_whenUtilityModeEnabled_returnsTrue() {
    XCTAssertTrue(
      AppPresentationPreferences.resolvedMenuBarExtraEnabled(
        menuBarExtraEnabled: false,
        backgroundUtilityModeEnabled: true
      )
    )
  }

  func testShouldStartWithoutMainWindow_whenQuietLaunchEnabled_returnsTrue() {
    XCTAssertTrue(
      AppPresentationPreferences.shouldStartWithoutMainWindow(
        quietLaunch: true,
        backgroundUtilityModeEnabled: false
      )
    )
  }

  func testShouldStartWithoutMainWindow_whenBackgroundUtilityEnabled_returnsTrue() {
    XCTAssertTrue(
      AppPresentationPreferences.shouldStartWithoutMainWindow(
        quietLaunch: false,
        backgroundUtilityModeEnabled: true
      )
    )
  }

  func testShouldStartWithoutMainWindow_whenNeitherFlagEnabled_returnsFalse() {
    XCTAssertFalse(
      AppPresentationPreferences.shouldStartWithoutMainWindow(
        quietLaunch: false,
        backgroundUtilityModeEnabled: false
      )
    )
  }

  func testEnablingBackgroundUtilityModePreservesExplicitMenuBarPreference() {
    HUDPreferences.setMenuBarExtraEnabled(false)

    HUDPreferences.setBackgroundUtilityModeEnabled(true)

    XCTAssertTrue(HUDPreferences.isBackgroundUtilityModeEnabled())
    XCTAssertFalse(HUDPreferences.isMenuBarExtraEnabled())
    XCTAssertTrue(
      AppPresentationPreferences.resolvedMenuBarExtraEnabled(
        menuBarExtraEnabled: HUDPreferences.isMenuBarExtraEnabled(),
        backgroundUtilityModeEnabled: HUDPreferences.isBackgroundUtilityModeEnabled()
      )
    )
  }

  func testDisablingBackgroundUtilityModeRestoresPriorExplicitMenuBarPreference() {
    HUDPreferences.setMenuBarExtraEnabled(false)
    HUDPreferences.setBackgroundUtilityModeEnabled(true)

    HUDPreferences.setBackgroundUtilityModeEnabled(false)

    XCTAssertFalse(HUDPreferences.isBackgroundUtilityModeEnabled())
    XCTAssertFalse(HUDPreferences.isMenuBarExtraEnabled())
  }

  func testMenuBarExtraCannotBeDisabledWhileUtilityModeIsEnabled() {
    HUDPreferences.setBackgroundUtilityModeEnabled(true)

    HUDPreferences.setMenuBarExtraEnabled(false)

    XCTAssertFalse(HUDPreferences.isMenuBarExtraEnabled())
    XCTAssertTrue(
      AppPresentationPreferences.resolvedMenuBarExtraEnabled(
        menuBarExtraEnabled: HUDPreferences.isMenuBarExtraEnabled(),
        backgroundUtilityModeEnabled: HUDPreferences.isBackgroundUtilityModeEnabled()
      )
    )
  }

  func testDerivePresentationShowsBackgroundActivityWhenCloudIsIdle() {
    let presentation = MenuBarStatusDeriver.derivePresentation(
      syncState: .disabled,
      cloudOffline: false,
      cloudStatus: nil,
      cloudStatusError: nil,
      backgroundIngestMessage: "Indexing 2/5 projects..."
    )

    XCTAssertEqual(presentation.displayState, .localActivity)
    XCTAssertEqual(presentation.statusText, "Background work active")
    XCTAssertEqual(presentation.localActivityText, "Indexing 2/5 projects...")
    XCTAssertEqual(presentation.cloudText, "Cloud sync off")
  }

  func testDerivePresentationShowsCloudSyncingBeforeLocalActivity() {
    let session = CloudActivePushSessionStatus(
      syncSessionId: "sync-1",
      phase: "syncing",
      entriesResolved: 3,
      entriesTotal: 10,
      progressPercent: 30,
      throughputEntriesPerMin: nil,
      etaSeconds: nil,
      checkpointSafe: nil,
      completionState: "in_progress",
      needsAttentionCount: 0,
      lastBatchAt: nil
    )
    let status = CloudSyncStatus(activePushSession: session)

    let presentation = MenuBarStatusDeriver.derivePresentation(
      syncState: .syncing,
      cloudOffline: false,
      cloudStatus: status,
      cloudStatusError: nil,
      backgroundIngestMessage: "Indexing 1/4 projects..."
    )

    XCTAssertEqual(presentation.displayState, .cloudSyncing)
    XCTAssertEqual(presentation.statusText, "Cloud syncing")
    XCTAssertEqual(presentation.cloudText, "Cloud syncing 3/10 entries")
  }

  func testDerivePresentationShowsCloudNeedsAttentionBeforeOfflineOrLocalActivity() {
    let session = CloudActivePushSessionStatus(
      syncSessionId: "sync-2",
      phase: "stalled",
      entriesResolved: nil,
      entriesTotal: nil,
      progressPercent: nil,
      throughputEntriesPerMin: nil,
      etaSeconds: nil,
      checkpointSafe: nil,
      completionState: "blocked",
      needsAttentionCount: 2,
      lastBatchAt: nil
    )
    let status = CloudSyncStatus(activePushSession: session)

    let presentation = MenuBarStatusDeriver.derivePresentation(
      syncState: .idle,
      cloudOffline: true,
      cloudStatus: status,
      cloudStatusError: "server said blocked",
      backgroundIngestMessage: "Indexing 3/6 projects..."
    )

    XCTAssertEqual(presentation.displayState, .cloudNeedsAttention)
    XCTAssertEqual(presentation.statusText, "Cloud needs attention")
    XCTAssertEqual(presentation.cloudText, "Cloud needs attention")
  }

  func testDerivePresentationShowsIdleWhenNothingIsActive() {
    let presentation = MenuBarStatusDeriver.derivePresentation(
      syncState: .disabled,
      cloudOffline: false,
      cloudStatus: nil,
      cloudStatusError: nil,
      backgroundIngestMessage: nil
    )

    XCTAssertEqual(presentation.displayState, .idle)
    XCTAssertEqual(presentation.statusText, "Up to date")
    XCTAssertEqual(presentation.localActivityText, "No background work")
    XCTAssertEqual(presentation.cloudText, "Cloud sync off")
  }
}
