import XCTest
@testable import ContextifyCore

final class FTSSafeWrapTests: XCTestCase {

  // MARK: - safeWrapPreservingQuotes

  func testSimpleBareTokens() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("hello world")
    XCTAssertEqual(result, "\"hello\" AND \"world\"")
  }

  func testPreservesExistingQuotedPhrase() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("\"cli ai setup\" security")
    XCTAssertEqual(result, "\"cli ai setup\" AND \"security\"")
  }

  func testMixedQuotedAndBare() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("v1.5.0 Cloud Launch \"ct 389\" release plan")
    XCTAssertEqual(result, "\"v1.5.0\" AND \"Cloud\" AND \"Launch\" AND \"ct 389\" AND \"release\" AND \"plan\"")
  }

  func testSingleQuotedPhrase() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("\"review loop\"")
    XCTAssertEqual(result, "\"review loop\"")
  }

  func testPreservesOperators() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("\"review loop\" OR \"auto compact\"")
    XCTAssertEqual(result, "\"review loop\" OR \"auto compact\"")
  }

  func testPreservesAndOperator() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("\"cli ai setup\" AND security")
    XCTAssertEqual(result, "\"cli ai setup\" AND \"security\"")
  }

  func testEmptyString() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("")
    XCTAssertEqual(result, "")
  }

  func testWhitespaceOnly() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("   ")
    XCTAssertEqual(result, "")
  }

  func testDottedVersion() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("v1.5.0")
    XCTAssertEqual(result, "\"v1.5.0\"")
  }

  // MARK: - preprocessHyphens -> safeWrap integration

  func testHyphenPreprocessThenSafeWrap() {
    // Simulates the buildSearchQuery flow for a mixed query
    let hyphenResult = FTSQueryBuilder.preprocessHyphens("v1.5.0 Cloud Launch ct-389 release plan")
    // Should have quoted "ct 389"
    XCTAssertTrue(hyphenResult.query.contains("\"ct 389\""))
    // Then safe wrap should handle remaining bare tokens
    let wrapped = FTSQueryBuilder.safeWrapPreservingQuotes(hyphenResult.query)
    XCTAssertTrue(wrapped.contains("\"v1.5.0\""))
    XCTAssertTrue(wrapped.contains("\"ct 389\""))
    XCTAssertTrue(wrapped.contains("\"Cloud\""))
  }

  func testHyphenatedWithOperators() {
    // When original has operators, preprocessor runs but safeWrap is skipped
    let hyphenResult = FTSQueryBuilder.preprocessHyphens("review-loop OR auto-compact")
    XCTAssertEqual(hyphenResult.query, "\"review loop\" OR \"auto compact\"")
  }

  // MARK: - ct-734 regression: quoted queries get quote validation

  func testPreprocessAutoClosesUnbalancedQuote() {
    // preprocessHyphens auto-closes an unclosed quote by wrapping the segment.
    // ct-734: buildSearchQuery now validates quote balance on the ORIGINAL input
    // before preprocessing, so auto-closing never masks user errors.
    let result = FTSQueryBuilder.preprocessHyphens("\"hello")
    let quoteCount = result.query.filter { $0 == "\"" }.count
    XCTAssertEqual(quoteCount % 2, 0, "Preprocessing auto-closes unbalanced quotes")
    XCTAssertTrue(result.query.contains("\"hello\""))

    // The original input has odd quotes - buildSearchQuery would reject this
    // before preprocessing ever runs.
    let originalQuoteCount = "\"hello".filter { $0 == "\"" }.count
    XCTAssertEqual(originalQuoteCount % 2, 1, "Original input has unbalanced quotes")
  }

  func testBalancedQuotesPassValidation() {
    let result = FTSQueryBuilder.preprocessHyphens("\"hello world\"")
    let quoteCount = result.query.filter { $0 == "\"" }.count
    XCTAssertEqual(quoteCount % 2, 0, "Balanced quotes should have even count")
  }
}
