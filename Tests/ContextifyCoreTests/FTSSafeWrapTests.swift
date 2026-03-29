import XCTest
@testable import ContextifyCore

final class FTSSafeWrapTests: XCTestCase {

  // MARK: - safeWrapPreservingQuotes

  func testSimpleBareTokens() {
    // Simple words are left unquoted for porter stemming
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("hello world")
    XCTAssertEqual(result, "hello AND world")
  }

  func testPreservesExistingQuotedPhrase() {
    // "security" is a simple word -> unquoted; quoted phrase preserved
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("\"cli ai setup\" security")
    XCTAssertEqual(result, "\"cli ai setup\" AND security")
  }

  func testMixedQuotedAndBare() {
    // v1.5.0 has dots -> quoted; Cloud, Launch, release, plan are simple -> unquoted
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("v1.5.0 Cloud Launch \"ct 389\" release plan")
    XCTAssertEqual(result, "\"v1.5.0\" AND Cloud AND Launch AND \"ct 389\" AND release AND plan")
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
    XCTAssertEqual(result, "\"cli ai setup\" AND security")
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
    // v1.5.0 has dots -> stays quoted; Cloud is simple -> unquoted
    XCTAssertTrue(wrapped.contains("\"v1.5.0\""))
    XCTAssertTrue(wrapped.contains("\"ct 389\""))
    XCTAssertTrue(wrapped.contains("Cloud"))
    // Cloud should NOT be quoted (simple word, porter stemming applies)
    XCTAssertFalse(wrapped.contains("\"Cloud\""))
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

  // MARK: - isSimpleWord (porter stemming unquoting)

  func testIsSimpleWord_basicWord() {
    XCTAssertTrue(FTSQueryBuilder.isSimpleWord("deploy"))
  }

  func testIsSimpleWord_withWildcard() {
    XCTAssertTrue(FTSQueryBuilder.isSimpleWord("deploy*"))
  }

  func testIsSimpleWord_ftsKeyword() {
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("NOT"))
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("AND"))
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("OR"))
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("NEAR"))
  }

  func testIsSimpleWord_colonToken() {
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("role:user"))
  }

  func testIsSimpleWord_dotToken() {
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("v1.5.0"))
  }

  func testIsSimpleWord_caretToken() {
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord("^start"))
  }

  func testIsSimpleWord_underscore() {
    // Underscores are word characters, should be simple
    XCTAssertTrue(FTSQueryBuilder.isSimpleWord("UNREAD_COUNT"))
  }

  func testIsSimpleWord_empty() {
    XCTAssertFalse(FTSQueryBuilder.isSimpleWord(""))
  }

  // MARK: - buildSafeFTSQuery (porter stemming integration)

  func testBuildSafe_simpleWordUnquoted() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("deploy")
    XCTAssertEqual(result, "deploy")
  }

  func testBuildSafe_ftsKeywordStaysQuoted() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("NOT")
    XCTAssertEqual(result, "\"NOT\"")
  }

  func testBuildSafe_colonTokenStaysQuoted() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("role:user")
    XCTAssertEqual(result, "\"role:user\"")
  }

  func testBuildSafe_dotTokenStaysQuoted() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("v1.5.0")
    XCTAssertEqual(result, "\"v1.5.0\"")
  }

  func testBuildSafe_mixedSimpleAndOperator() {
    // "deploy OR migrate" - deploy and migrate are simple words, OR is operator
    let result = FTSQueryBuilder.buildSafeFTSQuery("deploy OR migrate")
    // OR is an FTS5 keyword -> quoted; deploy and migrate are simple -> unquoted
    // All joined with AND
    XCTAssertEqual(result, "deploy AND \"OR\" AND migrate")
  }

  func testBuildSafe_wildcardPreservedOnSimpleWord() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("deploy*")
    XCTAssertEqual(result, "deploy*")
  }

  func testBuildSafe_multipleSimpleWords() {
    let result = FTSQueryBuilder.buildSafeFTSQuery("deploy refactoring")
    XCTAssertEqual(result, "deploy AND refactoring")
  }

  // MARK: - safeWrapPreservingQuotes (porter stemming for bare tokens)

  func testSafeWrap_simpleWordsUnquoted() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("release plan")
    XCTAssertEqual(result, "release AND plan")
  }

  func testSafeWrap_wildcardPreserved() {
    let result = FTSQueryBuilder.safeWrapPreservingQuotes("deploy*")
    XCTAssertEqual(result, "deploy*")
  }
}
