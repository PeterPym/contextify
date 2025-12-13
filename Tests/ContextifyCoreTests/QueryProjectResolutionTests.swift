import XCTest
import GRDB
@testable import ContextifyCore

final class QueryProjectResolutionTests: XCTestCase {

  func testResolveProjectId_usesLongestMatchingRoot() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-project-resolution-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let projectA = Project(
      id: "pA",
      name: "A",
      rootPath: "/Users/rob/code/projects/contextify",
      rootBookmark: nil,
      lastViewedTs: 100,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    let projectB = Project(
      id: "pB",
      name: "B",
      rootPath: "/Users/rob/code/projects",
      rootBookmark: nil,
      lastViewedTs: 200,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    try await pool.write { db in
      try projectA.insert(db)
      try projectB.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let resolved = try service.resolveProjectId(forPath: "/Users/rob/code/projects/contextify/app/Sources")
    XCTAssertEqual(resolved, "pA")
  }

  func testResolveProjectId_isCaseInsensitive() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-project-resolution-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "p1",
      name: "MyApp",
      rootPath: "/Users/rob/Code/MyApp",
      rootBookmark: nil,
      lastViewedTs: 100,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    try await pool.write { db in
      try project.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let resolved = try service.resolveProjectId(forPath: "/users/rob/code/myapp/src")
    XCTAssertEqual(resolved, "p1")
  }

  func testResolveProjectId_notFoundProvidesSuggestions() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-project-resolution-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let visible = Project(
      id: "p1",
      name: "Visible",
      rootPath: "/Users/rob/code/visible",
      rootBookmark: nil,
      lastViewedTs: 200,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    let hidden = Project(
      id: "p2",
      name: "Hidden",
      rootPath: "/Users/rob/code/hidden",
      rootBookmark: nil,
      lastViewedTs: 500,
      hidden: true,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    try await pool.write { db in
      try visible.insert(db)
      try hidden.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    do {
      _ = try service.resolveProjectId(forPath: "/Users/rob/code/unknown")
      XCTFail("Expected notFound")
    } catch let error as ContextifyQueryService.ProjectResolutionError {
      switch error {
      case let .notFound(_, suggestions, totalProjectCount):
        XCTAssertEqual(totalProjectCount, 1)
        XCTAssertEqual(suggestions.map(\.id), ["p1"])
      default:
        XCTFail("Expected notFound, got \(error)")
      }
    }
  }
}

