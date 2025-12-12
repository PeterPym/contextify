import XCTest
import Foundation
@testable import ContextifyCore

final class DatabaseDiscoveryTests: XCTestCase {

  override func tearDown() {
    super.tearDown()
    HUDPreferences.clearCustomDatabaseLocation()
    HUDPreferences.clearAppStoreOnboardingState()
  }

  func testSetCustomDatabaseLocationMirrorsLegacyKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    HUDPreferences.setCustomDatabaseLocation(tempDir)

    XCTAssertEqual(HUDPreferences.getCustomDatabaseLocation(), tempDir.path)
    XCTAssertEqual(HUDPreferences.getLegacyDatabaseLocation(), tempDir.path)
  }

  #if os(macOS)
  func testSetCustomDatabaseLocationWithBookmarkMirrorsLegacyKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let bookmarkData = try tempDir.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    HUDPreferences.setCustomDatabaseLocation(tempDir, bookmarkData: bookmarkData)

    XCTAssertEqual(HUDPreferences.getCustomDatabaseLocation(), tempDir.path)
    XCTAssertEqual(HUDPreferences.getLegacyDatabaseLocation(), tempDir.path)
  }
  #endif

  func testClearCustomDatabaseLocationClearsLegacyKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    HUDPreferences.setCustomDatabaseLocation(tempDir)
    HUDPreferences.clearCustomDatabaseLocation()

    XCTAssertNil(HUDPreferences.getCustomDatabaseLocation())
    XCTAssertNil(HUDPreferences.getLegacyDatabaseLocation())
  }

  func testClearAppStoreOnboardingStateClearsLegacyKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    HUDPreferences.setCustomDatabaseLocation(tempDir)
    HUDPreferences.setAppStoreOnboardingCompleted(true)
    HUDPreferences.clearAppStoreOnboardingState()

    XCTAssertNil(HUDPreferences.getCustomDatabaseLocation())
    XCTAssertNil(HUDPreferences.getLegacyDatabaseLocation())
  }
}

