import XCTest
@testable import ContextifyCore

final class StateWriterTests: XCTestCase {

  func testWriteState_createsSidecarFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-state-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    FileManager.default.createFile(atPath: dbURL.path, contents: Data())

    StateWriter.writeState(
      databaseURL: dbURL,
      schemaVersion: 28,
      appVersion: "1.2.3",
      buildFlavor: "dmg",
      capabilities: ["fts_search"]
    )

    let stateDir = tempDir.appendingPathComponent(".state", isDirectory: true)
    let stateURL = stateDir.appendingPathComponent("state.json")
    let readmeURL = stateDir.appendingPathComponent("README.md")

    XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: readmeURL.path))

    let data = try Data(contentsOf: stateURL)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(json?["state_version"] as? Int, 1)
    XCTAssertEqual(json?["database_path"] as? String, dbURL.path)
    XCTAssertEqual(json?["database_dir"] as? String, tempDir.path)
    XCTAssertEqual(json?["schema_version"] as? Int, 28)
    XCTAssertEqual(json?["build_flavor"] as? String, "dmg")
    XCTAssertEqual(json?["app_version"] as? String, "1.2.3")
    XCTAssertEqual(json?["capabilities"] as? [String], ["fts_search"])
  }

  func testWriteState_newDirectoryDoesNotDeleteOldSidecar() throws {
    let baseDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-state-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: baseDir) }

    let oldDir = baseDir.appendingPathComponent("old")
    let newDir = baseDir.appendingPathComponent("new")
    try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)

    let oldDB = oldDir.appendingPathComponent("contextify.db")
    let newDB = newDir.appendingPathComponent("contextify.db")
    FileManager.default.createFile(atPath: oldDB.path, contents: Data())
    FileManager.default.createFile(atPath: newDB.path, contents: Data())

    StateWriter.writeState(
      databaseURL: oldDB,
      schemaVersion: 1,
      appVersion: "1.0",
      buildFlavor: "dmg",
      capabilities: []
    )

    StateWriter.writeState(
      databaseURL: newDB,
      schemaVersion: 2,
      appVersion: "1.0",
      buildFlavor: "dmg",
      capabilities: []
    )

    let oldStateURL = oldDir.appendingPathComponent(".state/state.json")
    let newStateURL = newDir.appendingPathComponent(".state/state.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldStateURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: newStateURL.path))
  }
}

