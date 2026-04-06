import XCTest
@testable import ContextifyCore

final class GitAnchorSearchTests: XCTestCase {

  func testExtractCues_detectsFilesCommandsAndSymbols() {
    let cues = GitAnchorSearch.extractCues(
      from: "use /total-recall to inspect bloon-frontmatter-inject.sh and session_id handling"
    )

    XCTAssertTrue(cues.contains { $0.kind == .file && $0.normalized == "bloon-frontmatter-inject.sh" })
    XCTAssertTrue(cues.contains { $0.kind == .symbol && $0.normalized == "session_id" })
  }

  func testExtractCues_keepsStandaloneCommandCue() {
    let cues = GitAnchorSearch.extractCues(
      from: "/mission failed after sync-parent changed"
    )

    XCTAssertTrue(cues.contains { $0.kind == .command && $0.normalized == "mission" })
    XCTAssertTrue(cues.contains { $0.kind == .symbol && $0.normalized == "sync-parent" })
  }

  func testExtractCues_literalFilenames_stillExtractedForAnchorGitFallback() {
    // Regression: --anchor-git with literal filenames must still extract file cues.
    // This path remains the backwards-compatible fallback when --anchor-files is not used.
    let cues = GitAnchorSearch.extractCues(
      from: "DatabaseSchema.swift migration changes"
    )

    XCTAssertTrue(cues.contains { $0.kind == .file && $0.normalized == "DatabaseSchema.swift" },
      "Literal filenames in query must still be extracted as .file cues for --anchor-git fallback")
  }

  func testExtractCues_keywordQuery_extractsNoFileCues() {
    // Validates the architecture gap: keyword queries don't produce useful file cues.
    // This is why --anchor-files exists - the AI must pass files explicitly.
    let cues = GitAnchorSearch.extractCues(
      from: "database schema migration decision"
    )

    let fileCues = cues.filter { $0.kind == .file }
    XCTAssertTrue(fileCues.isEmpty,
      "Pure keyword queries should not produce file cues - this is the gap --anchor-files fills")
  }

  func testRerank_prefersCommitAndFileMentions() {
    let baselineHits = [
      ContextifyQueryService.SearchHit(
        id: "baseline-first",
        projectId: "p1",
        projectName: "Test",
        transcriptId: "t1",
        transcriptTitle: "General discussion",
        provider: "claude.code",
        kind: "assistant",
        timestamp: 1_700_000_000,
        score: -50,
        contentSnippet: "broad discussion without anchor cues",
        contentTruncated: false,
        gitCommit: nil,
        cwd: "/repo"
      ),
      ContextifyQueryService.SearchHit(
        id: "anchored",
        projectId: "p1",
        projectName: "Test",
        transcriptId: "t2",
        transcriptTitle: "Frontmatter fix",
        provider: "claude.code",
        kind: "assistant",
        timestamp: 1_700_000_100,
        score: -40,
        contentSnippet: "Updated bloon-frontmatter-inject.sh for session_id handling",
        contentTruncated: false,
        gitCommit: "abc123456789",
        cwd: "/repo"
      )
    ]

    let plan = GitAnchorPlan(
      cues: [
        GitAnchorCue(rawValue: "bloon-frontmatter-inject.sh", normalized: "bloon-frontmatter-inject.sh", kind: .file),
        GitAnchorCue(rawValue: "session_id", normalized: "session_id", kind: .symbol)
      ],
      files: ["/repo/scripts/bloon-frontmatter-inject.sh"],
      commits: [GitAnchorCommit(hash: "abc123", timestamp: 1_700_000_050)]
    )

    let reranked = GitAnchorSearch.rerank(hits: baselineHits, using: plan, requestedLimit: 2)
    XCTAssertEqual(reranked.hits.first?.id, "anchored")
    XCTAssertTrue(reranked.topResultsChanged)
  }

  func testRerank_preservesOrderWithoutSignal() {
    let baselineHits = [
      ContextifyQueryService.SearchHit(
        id: "first",
        projectId: "p1",
        projectName: "Test",
        transcriptId: "t1",
        transcriptTitle: nil,
        provider: "claude.code",
        kind: "assistant",
        timestamp: 1_700_000_000,
        score: -50,
        contentSnippet: "general conversation",
        contentTruncated: false,
        gitCommit: nil,
        cwd: nil
      ),
      ContextifyQueryService.SearchHit(
        id: "second",
        projectId: "p1",
        projectName: "Test",
        transcriptId: "t2",
        transcriptTitle: nil,
        provider: "claude.code",
        kind: "assistant",
        timestamp: 1_700_000_200,
        score: -40,
        contentSnippet: "more general conversation",
        contentTruncated: false,
        gitCommit: nil,
        cwd: nil
      )
    ]

    let plan = GitAnchorPlan(
      cues: [GitAnchorCue(rawValue: "total-recall", normalized: "total-recall", kind: .command)],
      files: [],
      commits: []
    )

    let reranked = GitAnchorSearch.rerank(hits: baselineHits, using: plan, requestedLimit: 2)
    XCTAssertEqual(reranked.hits.map(\.id), ["first", "second"])
    XCTAssertFalse(reranked.topResultsChanged)
  }
}
