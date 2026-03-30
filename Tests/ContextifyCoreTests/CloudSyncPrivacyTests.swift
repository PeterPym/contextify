import XCTest
import GRDB
@testable import ContextifyCore

final class CloudSyncPrivacyTests: XCTestCase {

  private func makeTestDB() throws -> (DatabaseManager, URL) {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-privacy-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    return (dbManager, tempDir)
  }

  private func insertProject(pool: DatabasePool, id: String, name: String, cloudSyncEnabled: Bool = true) throws {
    let now = Int(Date().timeIntervalSince1970)
    let project = Project(
      id: id,
      name: name,
      rootPath: "/test/\(name)",
      rootBookmark: nil,
      lastViewedTs: 0,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      cloudSyncEnabled: cloudSyncEnabled,
      createdAt: now,
      updatedAt: now
    )
    try pool.write { db in try project.insert(db) }
  }

  private func insertTranscriptAndEntry(
    pool: DatabasePool,
    projectId: String,
    transcriptId: String,
    entryId: String,
    content: String = "test content",
    timestamp: Int = 100
  ) throws {
    let now = Int(Date().timeIntervalSince1970)
    let transcript = Transcript(
      id: transcriptId,
      projectId: projectId,
      filePath: "/test/\(transcriptId).jsonl",
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: 0,
      fileSize: nil,
      lineCount: 1,
      bookmark: nil,
      lastProcessedLine: 0,
      lastProcessedEntryId: nil,
      parserVersion: 1,
      status: "active",
      ingestState: "complete",
      lastError: nil,
      createdAt: now,
      updatedAt: now
    )
    let entry = TranscriptEntry(
      id: entryId,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: timestamp,
      content: content,
      contentSha256: "sha-\(entryId)",
      displayInTimeline: 1,
      gitBranch: nil,
      gitCommit: nil,
      cwd: nil,
      createdAt: now,
      updatedAt: now,
      isQueued: 0,
      isSidechain: 0
    )
    try pool.write { db in
      try transcript.insert(db)
      try entry.insert(db)
    }
  }

  // MARK: - exportForCloudPush respects cloud_sync_enabled

  func testExportForCloudPushExcludesDisabledProjects() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    // Create two projects: one enabled, one disabled
    try insertProject(pool: pool, id: "p-enabled", name: "enabled-project", cloudSyncEnabled: true)
    try insertProject(pool: pool, id: "p-disabled", name: "disabled-project", cloudSyncEnabled: false)

    try insertTranscriptAndEntry(pool: pool, projectId: "p-enabled", transcriptId: "t1", entryId: "e1", content: "should sync", timestamp: 100)
    try insertTranscriptAndEntry(pool: pool, projectId: "p-disabled", transcriptId: "t2", entryId: "e2", content: "should not sync", timestamp: 200)

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL)
    let export = try service.exportForCloudPush()

    XCTAssertEqual(export.entries.count, 1, "Only entries from enabled projects should be exported")
    XCTAssertEqual(export.entries.first?.id, "e1")
    XCTAssertEqual(export.entries.first?.content, "should sync")
  }

  func testCountEntriesForCloudPushExcludesDisabledProjects() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    try insertProject(pool: pool, id: "p-enabled", name: "enabled", cloudSyncEnabled: true)
    try insertProject(pool: pool, id: "p-disabled", name: "disabled", cloudSyncEnabled: false)

    try insertTranscriptAndEntry(pool: pool, projectId: "p-enabled", transcriptId: "t1", entryId: "e1", timestamp: 100)
    try insertTranscriptAndEntry(pool: pool, projectId: "p-disabled", transcriptId: "t2", entryId: "e2", timestamp: 200)

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL)
    let count = try service.countEntriesForCloudPush()

    XCTAssertEqual(count, 1, "Count should only include entries from sync-enabled projects")
  }

  // MARK: - Toggle cloud sync

  func testSetProjectCloudSyncEnabled() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    try insertProject(pool: pool, id: "p1", name: "my-project", cloudSyncEnabled: true)

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Disable
    let matched = try service.setProjectCloudSyncEnabled(projectMatch: "my-project", enabled: false)
    XCTAssertEqual(matched, "my-project")

    let projects = try service.listProjectsCloudSyncStatus()
    XCTAssertEqual(projects.count, 1)
    XCTAssertFalse(projects.first!.cloudSyncEnabled)

    // Re-enable
    let matched2 = try service.setProjectCloudSyncEnabled(projectMatch: "my-project", enabled: true)
    XCTAssertEqual(matched2, "my-project")

    let projects2 = try service.listProjectsCloudSyncStatus()
    XCTAssertTrue(projects2.first!.cloudSyncEnabled)
  }

  // MARK: - Default is enabled

  func testNewProjectDefaultsToCloudSyncEnabled() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    let repo = ProjectRepositoryImpl(db: pool)
    let id = try repo.create(name: "new-project", rootPath: "/test/new", bookmark: nil)

    let project = try repo.get(id: id)
    XCTAssertNotNil(project)
    XCTAssertTrue(project!.cloudSyncEnabled, "New projects should default to cloud sync enabled")
  }

  // MARK: - Re-enabling includes entries again

  func testReEnablingProjectRestoresExport() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    try insertProject(pool: pool, id: "p1", name: "toggled-project", cloudSyncEnabled: false)
    try insertTranscriptAndEntry(pool: pool, projectId: "p1", transcriptId: "t1", entryId: "e1", content: "test")

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Excluded - should export 0
    let export1 = try service.exportForCloudPush()
    XCTAssertEqual(export1.entries.count, 0)

    // Re-enable - should export 1
    _ = try service.setProjectCloudSyncEnabled(projectMatch: "toggled-project", enabled: true)
    let export2 = try service.exportForCloudPush()
    XCTAssertEqual(export2.entries.count, 1)
  }

  // MARK: - Pull-side filtering

  func testImportFromCloudPullSkipsFullyExcludedRepoGroup() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    // Create a project that is excluded, with a repo_group_key
    let now = Int(Date().timeIntervalSince1970)
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, last_viewed_ts, hidden, is_orphaned,
          cloud_sync_enabled, repo_group_key, created_at, updated_at)
        VALUES ('p-excl', 'excluded-project', '/test/excluded', 0, 0, 0, 0, 'repo-key-1', ?, ?)
      """, arguments: [now, now])
    }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Pull data for the excluded project
    let result = try service.importFromCloudPull(
      projects: [["id": "p-excl", "root_path": "/test/excluded", "name": "excluded-project"]],
      transcripts: [["id": "t-pull", "project_id": "p-excl", "file_path": "/test/t.jsonl", "provider": "claude.code"]],
      entries: [[
        "id": "e-pull", "transcript_id": "t-pull", "project_id": "p-excl",
        "provider": "claude.code", "kind": "user", "timestamp": 200,
        "content": "pulled content", "content_sha256": "sha-pull",
        "display_in_timeline": 1, "created_at": now, "updated_at": now
      ]],
      summaries: []
    )

    // Entry should be skipped because the project is fully excluded
    XCTAssertEqual(result.entriesImported, 0, "Entries for fully excluded projects should be skipped during pull")
  }

  func testImportFromCloudPullAllowsMixedRepoGroup() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    // Create two projects sharing a repo_group_key: one enabled, one disabled
    let now = Int(Date().timeIntervalSince1970)
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, last_viewed_ts, hidden, is_orphaned,
          cloud_sync_enabled, repo_group_key, created_at, updated_at)
        VALUES ('p-on', 'enabled-wt', '/test/proj', 0, 0, 0, 1, 'repo-key-2', ?, ?)
      """, arguments: [now, now])
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, last_viewed_ts, hidden, is_orphaned,
          cloud_sync_enabled, repo_group_key, created_at, updated_at)
        VALUES ('p-off', 'disabled-wt', '/test/proj-wb1', 0, 0, 0, 0, 'repo-key-2', ?, ?)
      """, arguments: [now, now])
    }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Pull data for the disabled worktree's project - should still import because group is mixed
    let result = try service.importFromCloudPull(
      projects: [["id": "p-off", "root_path": "/test/proj-wb1", "name": "disabled-wt"]],
      transcripts: [["id": "t-mix", "project_id": "p-off", "file_path": "/test/t.jsonl", "provider": "claude.code"]],
      entries: [[
        "id": "e-mix", "transcript_id": "t-mix", "project_id": "p-off",
        "provider": "claude.code", "kind": "user", "timestamp": 300,
        "content": "mixed group content", "content_sha256": "sha-mix",
        "display_in_timeline": 1, "created_at": now, "updated_at": now
      ]],
      summaries: []
    )

    // Entry should be imported because the repo group has at least one enabled member
    XCTAssertEqual(result.entriesImported, 1, "Entries for mixed repo groups should be imported during pull")
  }

  // MARK: - ct-806: Divergent transcript vs entry project IDs

  /// Regression test for ct-806. HooverEngine can reassign entries to a different
  /// project than the transcript (cwd-based resolution). exportForCloudPush() must
  /// include projects referenced by BOTH entries and transcripts, or the server
  /// rejects the transcript insert with a FK violation.
  func testExportForCloudPushIncludesTranscriptReferencedProjects() throws {
    let (dbManager, tempDir) = try makeTestDB()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let pool = try dbManager.pool

    // Two projects: one from discovery (transcript points here), one from cwd resolution (entry points here)
    try insertProject(pool: pool, id: "proj-discovery", name: "discovery-project")
    try insertProject(pool: pool, id: "proj-cwd", name: "cwd-resolved-project")

    // Transcript references the discovery project
    let now = Int(Date().timeIntervalSince1970)
    let transcript = Transcript(
      id: "tx-divergent",
      projectId: "proj-discovery",
      filePath: "/test/discovery-project/session.jsonl",
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: 0,
      fileSize: nil,
      lineCount: 1,
      bookmark: nil,
      lastProcessedLine: 0,
      lastProcessedEntryId: nil,
      parserVersion: 1,
      status: "active",
      ingestState: "complete",
      lastError: nil,
      createdAt: now,
      updatedAt: now
    )
    // Entry references the cwd-resolved project (different from transcript's project)
    let entry = TranscriptEntry(
      id: "e-divergent",
      transcriptId: "tx-divergent",
      projectId: "proj-cwd",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 500,
      content: "divergent project test",
      contentSha256: "sha-divergent",
      displayInTimeline: 1,
      gitBranch: nil,
      gitCommit: nil,
      cwd: nil,
      createdAt: now,
      updatedAt: now,
      isQueued: 0,
      isSidechain: 0
    )
    try pool.write { db in
      try transcript.insert(db)
      try entry.insert(db)
    }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let service = try ContextifyQueryService(databaseURL: dbURL)
    let export = try service.exportForCloudPush()

    // Entry should reference the cwd-resolved project
    XCTAssertEqual(export.entries.count, 1)
    XCTAssertEqual(export.entries.first?.projectId, "proj-cwd")

    // Transcript should reference the discovery project
    XCTAssertEqual(export.transcripts.count, 1)
    XCTAssertEqual(export.transcripts.first?.projectId, "proj-discovery")

    // Both projects must be included in the export (server needs both for FK integrity)
    let exportedProjectIds = Set(export.projects.map { $0.id })
    XCTAssertTrue(
      exportedProjectIds.contains("proj-discovery"),
      "Export must include transcript-referenced project for server FK integrity"
    )
    XCTAssertTrue(
      exportedProjectIds.contains("proj-cwd"),
      "Export must include entry-referenced project for server FK integrity"
    )
    XCTAssertEqual(exportedProjectIds.count, 2, "Both divergent projects must be exported")
  }
}
