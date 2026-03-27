import XCTest
@testable import ContextifyCore

final class FTSHyphenPreprocessingTests: XCTestCase {

  // MARK: - Task ID Rewriting

  func testTaskIdRewrite() {
    let result = FTSQueryBuilder.preprocessHyphens("ct-361")
    XCTAssertEqual(result.query, "\"ct 361\"")
    XCTAssertTrue(result.hints.isEmpty)
  }

  func testTaskIdUppercase() {
    let result = FTSQueryBuilder.preprocessHyphens("DELTA-789")
    XCTAssertEqual(result.query, "\"DELTA 789\"")
  }

  func testTaskIdTwoLetterPrefix() {
    let result = FTSQueryBuilder.preprocessHyphens("bl-42")
    XCTAssertEqual(result.query, "\"bl 42\"")
  }

  // MARK: - Bare Hyphenated Token Rewriting

  func testBareHyphenatedToken() {
    let result = FTSQueryBuilder.preprocessHyphens("cli-ai-setup")
    XCTAssertEqual(result.query, "\"cli ai setup\"")
  }

  func testTwoPartHyphenated() {
    let result = FTSQueryBuilder.preprocessHyphens("review-loop")
    XCTAssertEqual(result.query, "\"review loop\"")
  }

  func testAutoCompact() {
    let result = FTSQueryBuilder.preprocessHyphens("auto-compact")
    XCTAssertEqual(result.query, "\"auto compact\"")
  }

  // MARK: - Trailing Hyphen Hint

  func testTrailingHyphenEmitsHint() {
    let result = FTSQueryBuilder.preprocessHyphens("cc-")
    XCTAssertEqual(result.query, "cc-")
    XCTAssertEqual(result.hints.count, 1)
    XCTAssertTrue(result.hints[0].contains("trailing hyphen"))
  }

  // MARK: - Quoted Terms Preserved

  func testQuotedTermsPreserved() {
    let result = FTSQueryBuilder.preprocessHyphens("\"cli-ai-setup\"")
    XCTAssertEqual(result.query, "\"cli-ai-setup\"")
    XCTAssertTrue(result.hints.isEmpty)
  }

  func testMixedQuotedAndBare() {
    let result = FTSQueryBuilder.preprocessHyphens("\"review-loop\" auto-compact")
    XCTAssertEqual(result.query, "\"review-loop\" \"auto compact\"")
  }

  // MARK: - Operators Preserved

  func testOperatorsPreserved() {
    let result = FTSQueryBuilder.preprocessHyphens("review-loop OR auto-compact")
    XCTAssertEqual(result.query, "\"review loop\" OR \"auto compact\"")
  }

  func testAndOperatorPreserved() {
    let result = FTSQueryBuilder.preprocessHyphens("cli-ai-setup AND security")
    XCTAssertEqual(result.query, "\"cli ai setup\" AND security")
  }

  // MARK: - Wildcard Handling

  func testHyphenatedWithWildcard() {
    let result = FTSQueryBuilder.preprocessHyphens("review-loop*")
    XCTAssertEqual(result.query, "\"review\" AND loop*")
  }

  // MARK: - No Hyphens (Passthrough)

  func testNoHyphensUnchanged() {
    let result = FTSQueryBuilder.preprocessHyphens("simple query terms")
    XCTAssertEqual(result.query, "simple query terms")
    XCTAssertTrue(result.hints.isEmpty)
  }

  func testEmptyQuery() {
    let result = FTSQueryBuilder.preprocessHyphens("")
    XCTAssertEqual(result.query, "")
  }

  // MARK: - Complex Expressions

  func testParenthesesPreserved() {
    let result = FTSQueryBuilder.preprocessHyphens("(deploy-fix) OR rollback")
    XCTAssertEqual(result.query, "(deploy-fix) OR rollback")
  }

  func testTaskIdWithOtherTerms() {
    let result = FTSQueryBuilder.preprocessHyphens("ct-708 benchmark harness")
    XCTAssertEqual(result.query, "\"ct 708\" benchmark harness")
  }

  func testMultipleHyphenatedTokens() {
    let result = FTSQueryBuilder.preprocessHyphens("cli-ai-setup review-loop ct-361")
    XCTAssertEqual(result.query, "\"cli ai setup\" \"review loop\" \"ct 361\"")
  }
}
