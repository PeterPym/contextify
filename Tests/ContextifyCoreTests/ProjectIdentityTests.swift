import XCTest
@testable import ContextifyCore

final class ProjectIdentityTests: XCTestCase {

  var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProjectIdentityTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    super.tearDown()
  }

  // MARK: - reverseManglePath Tests

  func testReverseManglePath_ClaudeCode_SimpleDirectory() throws {
    // Given: A Claude Code transcript directory with simple path (no hyphens)
    let projectDir = tempDir.appendingPathComponent("simple-project")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let claudeDir = tempDir.appendingPathComponent("-Users-rob-simple-project")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    // Create a transcript file with CWD
    let transcriptPath = claudeDir.appendingPathComponent("test-session.jsonl")
    let transcriptContent = """
      {"cwd":"\(projectDir.path)","timestamp":"2025-01-01T00:00:00Z"}
      """
    try transcriptContent.write(to: transcriptPath, atomically: true, encoding: .utf8)

    // When: Reverse mangling the path
    let result = try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: claudeDir)

    // Then: Should extract correct CWD from transcript
    XCTAssertEqual(result, projectDir.path)
  }

  func testReverseManglePath_ClaudeCode_HyphenatedDirectory() throws {
    // Given: A Claude Code transcript directory with hyphenated project name
    let projectDir = tempDir.appendingPathComponent("cli-ai-setup")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    // Claude Code mangles /path/to/cli-ai-setup to -path-to-cli-ai-setup
    // Naive replacement would produce /path/to/cli/ai/setup (WRONG!)
    let claudeDir = tempDir.appendingPathComponent("-path-to-cli-ai-setup")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    // Create a transcript file with CWD
    let transcriptPath = claudeDir.appendingPathComponent("test-session.jsonl")
    let transcriptContent = """
      {"cwd":"\(projectDir.path)","timestamp":"2025-01-01T00:00:00Z"}
      """
    try transcriptContent.write(to: transcriptPath, atomically: true, encoding: .utf8)

    // When: Reverse mangling the path
    let result = try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: claudeDir)

    // Then: Should extract correct CWD with hyphens preserved
    XCTAssertEqual(result, projectDir.path)
    XCTAssertTrue(result.hasSuffix("cli-ai-setup"), "Expected hyphens to be preserved")
    XCTAssertFalse(result.hasSuffix("cli/ai/setup"), "Should NOT have replaced hyphens with slashes")
  }

  func testReverseManglePath_ClaudeCode_MultipleHyphens() throws {
    // Given: A project with multiple hyphenated segments
    let projectDir = tempDir.appendingPathComponent("cloaked-email-litigation")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let claudeDir = tempDir.appendingPathComponent("-path-cloaked-email-litigation")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    // Create transcript with CWD
    let transcriptPath = claudeDir.appendingPathComponent("test-session.jsonl")
    let transcriptContent = """
      {"cwd":"\(projectDir.path)","timestamp":"2025-01-01T00:00:00Z"}
      """
    try transcriptContent.write(to: transcriptPath, atomically: true, encoding: .utf8)

    // When: Reverse mangling
    let result = try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: claudeDir)

    // Then: Should preserve all hyphens
    XCTAssertEqual(result, projectDir.path)
    XCTAssertTrue(result.hasSuffix("cloaked-email-litigation"))
  }

  func testReverseManglePath_ClaudeCode_NoTranscripts() throws {
    // Given: Claude directory with no transcript files
    let claudeDir = tempDir.appendingPathComponent("-Users-rob-empty")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    // When: Attempting to reverse mangle
    // Then: Should throw error
    XCTAssertThrowsError(try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: claudeDir)) { error in
      guard case ProjectIdentityError.cannotReadSessionMetadata = error else {
        XCTFail("Expected cannotReadSessionMetadata error, got \(error)")
        return
      }
    }
  }

  func testReverseManglePath_Codex_ValidSessionJson() throws {
    // Given: A Codex session directory with session.json
    let projectDir = tempDir.appendingPathComponent("codex-project")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let codexDir = tempDir.appendingPathComponent("abc123-session")
    try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

    let sessionJson = codexDir.appendingPathComponent("session.json")
    let sessionContent = """
      {"project_root":"\(projectDir.path)"}
      """
    try sessionContent.write(to: sessionJson, atomically: true, encoding: .utf8)

    // When: Reverse mangling
    let result = try ProjectIdentity.reverseManglePath(provider: "codex.cli", directory: codexDir)

    // Then: Should extract project_root from session.json
    XCTAssertEqual(result, projectDir.path)
  }

  func testReverseManglePath_Codex_MissingSessionJson() throws {
    // Given: Codex directory without session.json
    let codexDir = tempDir.appendingPathComponent("abc123-nosession")
    try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

    // When: Attempting to reverse mangle
    // Then: Should throw error
    XCTAssertThrowsError(try ProjectIdentity.reverseManglePath(provider: "codex.cli", directory: codexDir)) { error in
      guard case ProjectIdentityError.cannotReadSessionMetadata = error else {
        XCTFail("Expected cannotReadSessionMetadata error, got \(error)")
        return
      }
    }
  }

  func testReverseManglePath_UnknownProvider() throws {
    // Given: Unknown provider
    let dir = tempDir.appendingPathComponent("unknown-provider")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // When: Attempting to reverse mangle
    // Then: Should throw error
    XCTAssertThrowsError(try ProjectIdentity.reverseManglePath(provider: "unknown.provider", directory: dir)) { error in
      guard case ProjectIdentityError.unknownProvider = error else {
        XCTFail("Expected unknownProvider error, got \(error)")
        return
      }
    }
  }

  // MARK: - computeProjectID Tests

  func testComputeProjectID_SameInputsSameOutput() {
    let id1 = ProjectIdentity.computeProjectID(provider: "claude.code", path: "/Users/rob/project")
    let id2 = ProjectIdentity.computeProjectID(provider: "claude.code", path: "/Users/rob/project")
    XCTAssertEqual(id1, id2)
  }

  func testComputeProjectID_DifferentPathsDifferentIDs() {
    let id1 = ProjectIdentity.computeProjectID(provider: "claude.code", path: "/Users/rob/project1")
    let id2 = ProjectIdentity.computeProjectID(provider: "claude.code", path: "/Users/rob/project2")
    XCTAssertNotEqual(id1, id2)
  }

  func testComputeProjectID_DifferentProvidersDifferentIDs() {
    let id1 = ProjectIdentity.computeProjectID(provider: "claude.code", path: "/Users/rob/project")
    let id2 = ProjectIdentity.computeProjectID(provider: "codex.cli", path: "/Users/rob/project")
    XCTAssertNotEqual(id1, id2)
  }

  // MARK: - canonicalizePath Tests

  func testCanonicalizePath_RemovesTrailingSlash() throws {
    let path = try ProjectIdentity.canonicalizePath(tempDir.path + "/")
    XCTAssertFalse(path.hasSuffix("/"))
    XCTAssertEqual(path, tempDir.path)
  }

  func testCanonicalizePath_ExpandsTilde() throws {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let path = try ProjectIdentity.canonicalizePath("~")
    XCTAssertEqual(path, homeDir)
  }

  func testCanonicalizePath_NonexistentPath() {
    let nonexistent = tempDir.appendingPathComponent("does-not-exist").path
    XCTAssertThrowsError(try ProjectIdentity.canonicalizePath(nonexistent)) { error in
      guard case ProjectIdentityError.invalidPath = error else {
        XCTFail("Expected invalidPath error, got \(error)")
        return
      }
    }
  }

  // MARK: - extractCwdFromJSONLine Tests

  func testExtractCwdFromJSONLine_TopLevelCwd() {
    // Given: Claude Code style JSON with top-level cwd
    let line = """
      {"cwd":"/path/top-level","timestamp":"2025-01-01T00:00:00Z"}
      """

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should return top-level cwd
    XCTAssertEqual(result, "/path/top-level")
  }

  func testExtractCwdFromJSONLine_PayloadCwd() {
    // Given: Codex style JSON with payload.cwd
    let line = """
      {"type":"session_meta","payload":{"cwd":"/path/codex"}}
      """

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should return payload.cwd
    XCTAssertEqual(result, "/path/codex")
  }

  func testExtractCwdFromJSONLine_BothPresent_PrefersTopLevel() {
    // Given: JSON with both top-level cwd and payload.cwd (different values)
    let line = """
      {"cwd":"/path/direct","payload":{"cwd":"/path/payload"}}
      """

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should prefer top-level cwd (documented precedence)
    XCTAssertEqual(result, "/path/direct")
  }

  func testExtractCwdFromJSONLine_MalformedJSON() {
    // Given: Malformed JSON
    let line = "not valid json {"

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should return nil
    XCTAssertNil(result)
  }

  func testExtractCwdFromJSONLine_NoCwdField() {
    // Given: Valid JSON but no cwd field
    let line = """
      {"type":"message","content":"hello"}
      """

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should return nil
    XCTAssertNil(result)
  }

  func testExtractCwdFromJSONLine_EmptyLine() {
    // Given: Empty line
    let line = ""

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should return nil
    XCTAssertNil(result)
  }

  func testExtractCwdFromJSONLine_RealCodexFormat() {
    // Given: Actual Codex session_meta format from the bug report
    let line = """
      {"type":"session_meta","payload":{"cwd":"/Users/rob/code/sample-projects/demo-video","model":"o3","provider":"openai"}}
      """

    // When: Extracting CWD
    let result = ProjectIdentity.extractCwdFromJSONLine(line)

    // Then: Should correctly extract the cwd from payload
    XCTAssertEqual(result, "/Users/rob/code/sample-projects/demo-video")
  }
}
