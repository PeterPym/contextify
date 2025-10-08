import XCTest
@testable import Contextify

final class TimelineFastPathTests: XCTestCase {
    func testAssistantAckFastPath() async {
        let result = await FoundationLLM.shared._testSummarizeAssistantFastPath("Ack!")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.summary, "Claude acknowledges the request.")
        XCTAssertEqual(result?.isCompletion, false)
    }

    func testAssistantCompletionFastPath() async {
        let result = await FoundationLLM.shared._testSummarizeAssistantFastPath("✅ Done. Wrote /tmp/out.md.")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.summary, "Claude reported the task as completed.")
        XCTAssertEqual(result?.isCompletion, true)
    }
}

final class FormattingTests: XCTestCase {
    func testAssistantPrefixAndLength() async {
        let sanitized = await FoundationLLM.shared._testSanitize(String(repeating: "x", count: 200), kind: .assistant)
        XCTAssertTrue(sanitized.hasPrefix("Claude"))
        XCTAssertLessThanOrEqual(sanitized.count, 110)
    }

    func testUserPrefixesRespected() async {
        let made = await FoundationLLM.shared._testSanitize("You made the change.", kind: .user)
        XCTAssertEqual(made, "You made the change.")
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
final class GroundingTests: XCTestCase {
    func testUngroundedAckIsCorrected() async throws {
        let payload = GuidedTimelineSummary(
            summary: "Claude proposes reviewing the backfill logic for edge cases.",
            isCompletion: false,
            disposition: "analysis",
            grounding: "ungrounded",
            confidence: 0.4
        )
        let result = try await FoundationLLM.shared._testPostProcess(kind: .assistant, payload: payload, message: "Ack!")
        XCTAssertEqual(result.summary, "Claude acknowledges the request.")
        XCTAssertFalse(result.isCompletion)
    }

    func testLongExplanationNotTruncated() async throws {
        let message = "The number of log entries shown on startup is controlled in ConversationMonitor.swift at line 310 where the recent entries array is limited to 5 displayable items."
        let payload = GuidedTimelineSummary(
            summary: "Claude explains the startup log entry configuration",
            isCompletion: false,
            disposition: "analysis",
            grounding: "ungrounded",
            confidence: 0.6
        )
        let result = try await FoundationLLM.shared._testPostProcess(
            kind: .assistant,
            payload: payload,
            message: message
        )
        // Should NOT throw because confidence is above threshold and leakage is minimal
        XCTAssertTrue(result.summary.contains("explains") || result.summary.contains("startup"))
        XCTAssertFalse(result.summary.hasPrefix("Claude The number"))
    }

    func testConfirmedWithDetailNotTruncated() async throws {
        let message = "Yes, confirmed. The current logic at line 283 takes the last 5 lines from the conversation history and formats them for display in the timeline view."
        let payload = GuidedTimelineSummary(
            summary: "Claude confirms the line extraction logic",
            isCompletion: false,
            disposition: "analysis",
            grounding: "ungrounded",
            confidence: 0.7
        )
        let result = try await FoundationLLM.shared._testPostProcess(
            kind: .assistant,
            payload: payload,
            message: message
        )
        XCTAssertTrue(result.summary.contains("confirms"))
        XCTAssertFalse(result.summary.hasPrefix("Claude Yes, confirmed"))
    }

    func testSubstantialLeakageTriggersRejection() async {
        let message = "The file is located at /tmp/foo.txt"
        let payload = GuidedTimelineSummary(
            summary: "Claude explains the database connection pooling strategy",
            isCompletion: false,
            disposition: "analysis",
            grounding: "ungrounded",
            confidence: 0.8
        )
        // Should throw because summary introduces many topics not in message
        do {
            _ = try await FoundationLLM.shared._testPostProcess(
                kind: .assistant,
                payload: payload,
                message: message
            )
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected - summary should be rejected and trigger retry
        }
    }

    func testLowConfidenceWithLeakageTriggersRejection() async {
        let message = "The value is 42."
        let payload = GuidedTimelineSummary(
            summary: "Claude analyzes the configuration parameters",
            isCompletion: false,
            disposition: "analysis",
            grounding: "grounded",
            confidence: 0.2
        )
        // Should throw because confidence is very low with leakage
        do {
            _ = try await FoundationLLM.shared._testPostProcess(
                kind: .assistant,
                payload: payload,
                message: message
            )
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected - summary should be rejected and trigger retry
        }
    }

    func testGroundedWithMinimalLeakageAccepted() async throws {
        let message = "I've updated the configuration file to use the new API endpoint."
        let payload = GuidedTimelineSummary(
            summary: "Claude updated the configuration file",
            isCompletion: true,
            disposition: "completion",
            grounding: "grounded",
            confidence: 0.9
        )
        let result = try await FoundationLLM.shared._testPostProcess(
            kind: .assistant,
            payload: payload,
            message: message
        )
        XCTAssertTrue(result.summary.contains("updated"))
        XCTAssertTrue(result.summary.contains("configuration"))
    }

    func testUngroundedButMinimalLeakageAccepted() async throws {
        let message = "Looking at the code, the function is defined in utils.swift"
        let payload = GuidedTimelineSummary(
            summary: "Claude identifies the function location",
            isCompletion: false,
            disposition: "analysis",
            grounding: "ungrounded",
            confidence: 0.75
        )
        let result = try await FoundationLLM.shared._testPostProcess(
            kind: .assistant,
            payload: payload,
            message: message
        )
        // Should accept because leakage is minimal (<3 tokens) and confidence is reasonable
        XCTAssertTrue(result.summary.contains("identifies") || result.summary.contains("function"))
    }
}
#endif

final class ActionHintTests: XCTestCase {
    @MainActor
    func testAffirmWithHintExtraction() {
        let hint = ConversationMonitor.shared._testDistilledActionHint(from: "Would you like me to ensure five displayable entries?")
        XCTAssertEqual(hint, "Would you like me to ensure five displayable entries")
    }

    @MainActor
    func testUseActionHintGate() {
        XCTAssertTrue(ConversationMonitor.shared._testShouldUseActionHint("Yes."))
        XCTAssertTrue(ConversationMonitor.shared._testShouldUseActionHint("OK, proceed"))
        XCTAssertFalse(ConversationMonitor.shared._testShouldUseActionHint("Yes, but also explain why."))
    }
}
