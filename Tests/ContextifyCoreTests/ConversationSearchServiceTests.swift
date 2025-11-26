import XCTest
import GRDB
@testable import ContextifyCore

final class ConversationSearchServiceTests: XCTestCase {

  // MARK: - Query Builder Tests

  func testBuildSafeFTSQuery_simpleTokens() {
    let result = ConversationSearchService.buildSafeFTSQuery("unread count")
    XCTAssertEqual(result, "\"unread\" AND \"count\"")
  }

  func testBuildSafeFTSQuery_singleToken() {
    let result = ConversationSearchService.buildSafeFTSQuery("search")
    XCTAssertEqual(result, "\"search\"")
  }

  func testBuildSafeFTSQuery_phraseSearch() {
    let result = ConversationSearchService.buildSafeFTSQuery("\"exact phrase\"")
    XCTAssertEqual(result, "\"exact phrase\"")
  }

  func testBuildSafeFTSQuery_phraseSearchStripsInternalQuotes() {
    let result = ConversationSearchService.buildSafeFTSQuery("\"exact \"quoted\" phrase\"")
    XCTAssertEqual(result, "\"exact quoted phrase\"")
  }

  func testBuildSafeFTSQuery_specialCharacters() {
    let result = ConversationSearchService.buildSafeFTSQuery("foo* (bar) \"baz\"")
    XCTAssertEqual(result, "\"foo\" AND \"bar\" AND \"baz\"")
  }

  func testBuildSafeFTSQuery_emptyString() {
    let result = ConversationSearchService.buildSafeFTSQuery("")
    XCTAssertEqual(result, "")
  }

  func testBuildSafeFTSQuery_whitespaceOnly() {
    let result = ConversationSearchService.buildSafeFTSQuery("   ")
    XCTAssertEqual(result, "")
  }

  func testBuildSafeFTSQuery_leadingTrailingWhitespace() {
    let result = ConversationSearchService.buildSafeFTSQuery("  hello world  ")
    XCTAssertEqual(result, "\"hello\" AND \"world\"")
  }

  func testBuildSafeFTSQuery_multipleSpaces() {
    let result = ConversationSearchService.buildSafeFTSQuery("hello   world")
    XCTAssertEqual(result, "\"hello\" AND \"world\"")
  }

  func testBuildSafeFTSQuery_codeIdentifier() {
    // Should treat code identifiers as single tokens
    let result = ConversationSearchService.buildSafeFTSQuery("UNREAD_COUNT_UPDATED")
    XCTAssertEqual(result, "\"UNREAD_COUNT_UPDATED\"")
  }

  func testBuildSafeFTSQuery_mixedCasePreserved() {
    let result = ConversationSearchService.buildSafeFTSQuery("UnreadCount")
    XCTAssertEqual(result, "\"UnreadCount\"")
  }

  func testBuildSafeFTSQuery_parenthesesRemoved() {
    let result = ConversationSearchService.buildSafeFTSQuery("function()")
    XCTAssertEqual(result, "\"function\"")
  }

  func testBuildSafeFTSQuery_asterisksRemoved() {
    let result = ConversationSearchService.buildSafeFTSQuery("test*")
    XCTAssertEqual(result, "\"test\"")
  }

  // MARK: - Search Scope Tests

  func testSearchScope_project() {
    let scope = ConversationSearchScope.project("project-123")
    XCTAssertEqual(scope, ConversationSearchScope.project("project-123"))
  }

  func testSearchScope_allProjects() {
    let scope = ConversationSearchScope.allProjects
    XCTAssertEqual(scope, ConversationSearchScope.allProjects)
  }

  func testSearchScope_multipleProjects() {
    let scope = ConversationSearchScope.projects(["p1", "p2", "p3"])
    XCTAssertEqual(scope, ConversationSearchScope.projects(["p1", "p2", "p3"]))
  }

  // MARK: - Search Request Tests

  func testSearchRequest_defaultValues() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects)
    XCTAssertEqual(request.query, "test")
    XCTAssertEqual(request.scope, .allProjects)
    XCTAssertEqual(request.limit, 50)
    XCTAssertEqual(request.offset, 0)
  }

  func testSearchRequest_limitCapped() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects, limit: 100)
    XCTAssertEqual(request.limit, 50)  // Should be capped at 50
  }

  func testSearchRequest_offsetCapped() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects, offset: 10000)
    XCTAssertEqual(request.offset, 5000)  // Should be capped at 5000
  }

  func testSearchRequest_validValues() {
    let request = ConversationSearchRequest(query: "test", scope: .project("p1"), limit: 25, offset: 100)
    XCTAssertEqual(request.query, "test")
    XCTAssertEqual(request.scope, .project("p1"))
    XCTAssertEqual(request.limit, 25)
    XCTAssertEqual(request.offset, 100)
  }

  // MARK: - Search Result Tests

  func testSearchResult_cappedResults() {
    let result = ConversationSearchResult(
      hits: [],
      totalCount: 5000,
      cappedResults: true,
      query: "test",
      scope: .allProjects
    )
    XCTAssertTrue(result.cappedResults)
    XCTAssertEqual(result.totalCount, 5000)
  }

  func testSearchResult_uncappedResults() {
    let result = ConversationSearchResult(
      hits: [],
      totalCount: 100,
      cappedResults: false,
      query: "test",
      scope: .project("p1")
    )
    XCTAssertFalse(result.cappedResults)
    XCTAssertEqual(result.totalCount, 100)
  }

  // MARK: - Search Hit Tests

  func testSearchHit_identifiable() {
    let hit = ConversationSearchHit(
      id: "entry-123",
      projectId: "project-456",
      projectName: "Test Project",
      role: "user",
      content: "Hello world",
      createdAt: Date(),
      rank: -0.5,
      snippet: "Hello <mark>world</mark>"
    )

    XCTAssertEqual(hit.id, "entry-123")
    XCTAssertEqual(hit.projectId, "project-456")
    XCTAssertEqual(hit.projectName, "Test Project")
    XCTAssertEqual(hit.role, "user")
  }

  func testSearchHit_equatable() {
    let date = Date()
    let hit1 = ConversationSearchHit(
      id: "entry-123",
      projectId: "p1",
      projectName: "Project",
      role: "user",
      content: "content",
      createdAt: date,
      rank: -0.5,
      snippet: "snippet"
    )

    let hit2 = ConversationSearchHit(
      id: "entry-123",
      projectId: "p1",
      projectName: "Project",
      role: "user",
      content: "content",
      createdAt: date,
      rank: -0.5,
      snippet: "snippet"
    )

    XCTAssertEqual(hit1, hit2)
  }
}
