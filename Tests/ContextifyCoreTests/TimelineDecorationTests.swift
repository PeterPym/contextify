import XCTest
import GRDB
@testable import ContextifyCore

/// Tests for timeline entry decoration features:
/// - Layer 1: General sidechain/spawned agent decoration
/// - Layer 2: Contextify-specific decoration
final class TimelineDecorationTests: XCTestCase {

  // MARK: - Test Fixtures

  private func makeTestDatabase() throws -> (DatabaseManager, DatabasePool, URL) {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("decoration-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    return (dbManager, pool, tempDir)
  }

  private func insertProject(_ pool: DatabasePool, id: String = "p1") throws {
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, last_viewed_ts, hidden, is_orphaned, created_at, updated_at)
        VALUES (?, 'Test Project', '/test', 0, 0, 0, 0, 0)
      """, arguments: [id])
    }
  }

  private func insertTranscript(_ pool: DatabasePool, id: String = "t1", projectId: String = "p1", filePath: String? = nil) throws {
    let path = filePath ?? "/test/transcript-\(id).jsonl"
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count,
          last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES (?, ?, ?, 'claude.code', 0, 1, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [id, projectId, path])
    }
  }

  private func insertEntry(_ pool: DatabasePool, id: String, transcriptId: String = "t1", projectId: String = "p1", kind: String = "assistant") throws {
    // Use entry ID as content_sha256 to ensure uniqueness per (transcript_id, content_sha256)
    // This respects the v35 UNIQUE constraint added for P5 optimization
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO transcript_entries (id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued)
        VALUES (?, ?, ?, 'claude.code', ?, 1000, 'test content', ?, 1, 0, 1000, 1000, 0)
      """, arguments: [id, transcriptId, projectId, kind, "sha-\(id)"])
    }
  }

  private func insertToolInvocation(
    _ pool: DatabasePool,
    id: String = UUID().uuidString,
    entryId: String,
    transcriptId: String = "t1",
    toolName: String,
    toolKey: String?,
    sidechainTranscriptId: String? = nil,
    isContextify: Bool = false,
    toolResultEntryId: String? = nil
  ) throws {
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO tool_invocations (id, entry_id, transcript_id, tool_name, tool_key,
          sidechain_transcript_id, is_contextify, tool_result_entry_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1000, 1000)
      """, arguments: [id, entryId, transcriptId, toolName, toolKey, sidechainTranscriptId, isContextify ? 1 : 0, toolResultEntryId])
    }
  }

  // MARK: - Layer 1: Spawned Agent Tests

  func testGetSpawnedAgentEntries_taskWithSidechain_returnsAgentType() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Entry with Task tool that has sidechain
    try insertProject(pool)
    try insertTranscript(pool)
    try insertTranscript(pool, id: "sc-001")  // Sidechain transcript
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Task", toolKey: "Explore", sidechainTranscriptId: "sc-001")

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")

    // Assert
    XCTAssertEqual(result["e1"]?.agentType, "Explore", "Entry should have Explore as spawned agent type")
  }

  func testGetSpawnedAgentEntries_taskWithoutSidechain_stillReturnsBadge() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Entry with Task tool but NO sidechain (agent still running or linkage pending)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Task", toolKey: "Explore", sidechainTranscriptId: nil)

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")

    // Assert: Badge should show immediately when Task is invoked, not waiting for sidechain
    XCTAssertEqual(result["e1"]?.agentType, "Explore", "Task invocation should show badge immediately")
  }

  func testGetSpawnedAgentEntries_taskWithModel_returnsModelInfo() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Entry with Task tool that has model info
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    // Insert tool invocation with metadata_json containing model
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO tool_invocations (id, entry_id, transcript_id, tool_name, tool_key,
          metadata_json, is_contextify, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1000, 1000)
      """, arguments: [UUID().uuidString, "e1", "t1", "Task", "Explore", "{\"model\": \"haiku\", \"prompt\": \"test\"}", 0])
    }

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")

    // Assert
    XCTAssertEqual(result["e1"]?.agentType, "Explore", "Should have Explore as agent type")
    XCTAssertEqual(result["e1"]?.model, "haiku", "Should have haiku as model")
  }

  func testGetSpawnedAgentEntries_regularTool_returnsEmpty() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Entry with Bash tool (not Task)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Bash", toolKey: nil, sidechainTranscriptId: nil)

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")

    // Assert
    XCTAssertTrue(result.isEmpty, "Regular tools should not appear in spawned agents")
  }

  func testGetSpawnedAgentEntries_multipleAgents_returnsAll() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Multiple Task invocations with sidechains
    try insertProject(pool)
    try insertTranscript(pool)
    try insertTranscript(pool, id: "sc-1")  // Sidechain transcript
    try insertTranscript(pool, id: "sc-2")  // Sidechain transcript
    try insertEntry(pool, id: "e1")
    try insertEntry(pool, id: "e2")
    try insertEntry(pool, id: "e3")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Task", toolKey: "Explore", sidechainTranscriptId: "sc-1")
    try insertToolInvocation(pool, entryId: "e2", toolName: "Task", toolKey: "Plan", sidechainTranscriptId: "sc-2")
    try insertToolInvocation(pool, entryId: "e3", toolName: "Bash", toolKey: nil) // No sidechain

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")

    // Assert
    XCTAssertEqual(result.count, 2, "Should have 2 spawned agents")
    XCTAssertEqual(result["e1"]?.agentType, "Explore")
    XCTAssertEqual(result["e2"]?.agentType, "Plan")
    XCTAssertNil(result["e3"], "Bash entry should not be in result")
  }

  func testGetSpawnedAgentEntries_projectLevel_returnsAllTranscripts() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Two transcripts with spawned agents
    try insertProject(pool)
    try insertTranscript(pool, id: "t1")
    try insertTranscript(pool, id: "t2")
    try insertTranscript(pool, id: "sc-1")  // Sidechain transcript
    try insertTranscript(pool, id: "sc-2")  // Sidechain transcript
    try insertEntry(pool, id: "e1", transcriptId: "t1")
    try insertEntry(pool, id: "e2", transcriptId: "t2")
    try insertToolInvocation(pool, entryId: "e1", transcriptId: "t1", toolName: "Task", toolKey: "Explore", sidechainTranscriptId: "sc-1")
    try insertToolInvocation(pool, entryId: "e2", transcriptId: "t2", toolName: "Task", toolKey: "Plan", sidechainTranscriptId: "sc-2")

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getSpawnedAgentEntries(projectId: "p1")

    // Assert
    XCTAssertEqual(result.count, 2, "Should have 2 spawned agents across both transcripts")
    XCTAssertEqual(result["e1"]?.agentType, "Explore")
    XCTAssertEqual(result["e2"]?.agentType, "Plan")
  }

  // MARK: - Layer 2: Contextify-Specific Tests

  func testGetContextifyEntryIds_skillInvocation_returnsEntryId() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify skill call
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Skill", toolKey: "query:contextify-reinject", isContextify: true)

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert
    XCTAssertTrue(result.contains("e1"), "Contextify skill entry should be in result")
  }

  func testGetContextifyEntryIds_agentInvocation_returnsEntryId() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify agent call (Task with sidechain)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertTranscript(pool, id: "sc-1")  // Sidechain transcript
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Task",
      toolKey: "query:contextify-researcher",
      sidechainTranscriptId: "sc-1",
      isContextify: true
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert
    XCTAssertTrue(result.contains("e1"), "Contextify agent entry should be in result")
  }

  func testGetContextifyEntryIds_regularSkill_returnsEmpty() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Non-Contextify skill call
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(pool, entryId: "e1", toolName: "Skill", toolKey: "linear-integration", isContextify: false)

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert
    XCTAssertFalse(result.contains("e1"), "Non-Contextify skill should not be in result")
  }

  // MARK: - Combined Layer Tests

  func testContextifyAgent_hasBothSpawnedAgentAndContextifyFlag() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify agent (Task with sidechain + is_contextify)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertTranscript(pool, id: "sc-1")  // Sidechain transcript
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Task",
      toolKey: "query:contextify-researcher",
      sidechainTranscriptId: "sc-1",
      isContextify: true
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let spawnedAgents = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")
    let contextifyEntries = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert: Entry appears in BOTH results
    XCTAssertEqual(spawnedAgents["e1"]?.agentType, "query:contextify-researcher", "Should be in spawned agents")
    XCTAssertTrue(contextifyEntries.contains("e1"), "Should be in Contextify entries")
  }

  func testRegularAgent_hasOnlySpawnedAgentNotContextify() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Regular agent (Task with sidechain, NOT Contextify)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertTranscript(pool, id: "sc-1")  // Sidechain transcript
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Task",
      toolKey: "Explore",
      sidechainTranscriptId: "sc-1",
      isContextify: false
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let spawnedAgents = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")
    let contextifyEntries = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert: Entry appears in spawned agents but NOT Contextify
    XCTAssertEqual(spawnedAgents["e1"]?.agentType, "Explore", "Should be in spawned agents")
    XCTAssertFalse(contextifyEntries.contains("e1"), "Should NOT be in Contextify entries")
  }

  func testContextifySkill_hasOnlyContextifyNotSpawnedAgent() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify skill (NO sidechain, is_contextify = true)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Skill",
      toolKey: "query:contextify-reinject",
      sidechainTranscriptId: nil,  // Skills don't spawn sidechains
      isContextify: true
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let spawnedAgents = try orchestrator.getSpawnedAgentEntries(transcriptId: "t1")
    let contextifyEntries = try orchestrator.getContextifyEntryIds(transcriptId: "t1")

    // Assert: Entry appears in Contextify but NOT spawned agents
    XCTAssertNil(spawnedAgents["e1"], "Skills should NOT be in spawned agents")
    XCTAssertTrue(contextifyEntries.contains("e1"), "Should be in Contextify entries")
  }

  // MARK: - ContextifyEntryInfo Tests

  func testGetContextifyEntryInfo_invocationEntry_returnsToolKeyAndIsResultFalse() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify skill invocation
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Skill",
      toolKey: "total-recall",
      isContextify: true
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryInfo(projectId: "p1")

    // Assert
    XCTAssertNotNil(result["e1"], "Should have entry info for invocation")
    XCTAssertEqual(result["e1"]?.toolKey, "total-recall", "Should have correct toolKey")
    XCTAssertEqual(result["e1"]?.isResult, false, "Invocation should have isResult=false")
  }

  func testGetContextifyEntryInfo_resultEntry_returnsToolKeyAndIsResultTrue() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify skill with result entry
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")  // Invocation entry
    try insertEntry(pool, id: "e2")  // Result entry
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Skill",
      toolKey: "query:contextify-researcher",
      isContextify: true,
      toolResultEntryId: "e2"
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryInfo(projectId: "p1")

    // Assert: Both invocation and result should be mapped
    XCTAssertNotNil(result["e1"], "Should have entry info for invocation")
    XCTAssertEqual(result["e1"]?.isResult, false, "Invocation should have isResult=false")

    XCTAssertNotNil(result["e2"], "Should have entry info for result")
    XCTAssertEqual(result["e2"]?.toolKey, "query:contextify-researcher", "Result should have same toolKey")
    XCTAssertEqual(result["e2"]?.isResult, true, "Result should have isResult=true")
  }

  func testGetContextifyEntryInfo_nilToolKey_stillReturnsEntry() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Contextify entry with nil toolKey (edge case)
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Skill",
      toolKey: nil,  // No toolKey
      isContextify: true
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryInfo(projectId: "p1")

    // Assert: Entry should still be returned with nil toolKey
    XCTAssertNotNil(result["e1"], "Should have entry info even with nil toolKey")
    XCTAssertNil(result["e1"]?.toolKey, "toolKey should be nil")
    XCTAssertEqual(result["e1"]?.isResult, false)
  }

  func testGetContextifyEntryInfo_nonContextify_notReturned() throws {
    let (dbManager, pool, tempDir) = try makeTestDatabase()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup: Non-Contextify tool invocation
    try insertProject(pool)
    try insertTranscript(pool)
    try insertEntry(pool, id: "e1")
    try insertToolInvocation(
      pool,
      entryId: "e1",
      toolName: "Skill",
      toolKey: "some-other-skill",
      isContextify: false
    )

    // Execute
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let result = try orchestrator.getContextifyEntryInfo(projectId: "p1")

    // Assert: Non-Contextify entries should not be returned
    XCTAssertNil(result["e1"], "Non-Contextify entry should not be in result")
  }
}
