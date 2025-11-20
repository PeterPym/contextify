//
//  TimelineFixValidationTests.swift
//  ContextifyTests
//
//  Manual validation tests for timeline summarization fix
//  Tests 15 real conversation turns from production database
//

import XCTest
@testable import Contextify

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
final class TimelineFixValidationTests: XCTestCase {

    struct TestCase {
        let number: Int
        let message: String
        let expectedDisposition: String
        let expectedVerbPattern: String
        let category: String
        let description: String
    }

    // MARK: - Test Cases from Production Database

    let testCases: [TestCase] = [
        // MISATTRIBUTED PROPOSALS (6 cases - expected to be FIXED)
        TestCase(
            number: 1,
            message: "Let me create a simple helper script or add functionality to handle common screenshot types with preset dimensions and overlay text. This would make repeated screenshot tasks much faster.",
            expectedDisposition: "proposal",
            expectedVerbPattern: "propos",  // matches "proposed", "proposing"
            category: "Proposal",
            description: "Let me [verb] pattern"
        ),
        TestCase(
            number: 2,
            message: "Now I'll create the script that adds text overlays using ImageMagick. The script should: take input image, text to overlay, output path, and optionally font size and color.",
            expectedDisposition: "proposal",
            expectedVerbPattern: "propos",
            category: "Proposal",
            description: "I'll [verb] pattern"
        ),
        TestCase(
            number: 3,
            message: "The user wants me to: 1. Commit the changes 2. Then see if I can trigger the transcript inventory window to appear. Let me commit first, then explore the trigger mechanism.",
            expectedDisposition: "proposal",
            expectedVerbPattern: "propos",
            category: "Proposal",
            description: "Let me [verb] pattern (mixed)"
        ),
        TestCase(
            number: 4,
            message: "Now I need to update the restoration part to restore both the main Contextify window and iTerm2 window that was active before the screenshot workflow started.",
            expectedDisposition: "proposal",
            expectedVerbPattern: "not",  // matches "noted", "noted need"
            category: "Proposal",
            description: "I need to [verb] pattern"
        ),
        TestCase(
            number: 5,
            message: "Looking at the presets, the 'settings' preset opens the ConversationMonitor settings. But there should be a Settings window or panel that allows adjusting other database and backup features.",
            expectedDisposition: "analysis",
            expectedVerbPattern: "analyz",  // matches "analyzed", "analyzing"
            category: "Analysis",
            description: "Analysis misclassified as proposal"
        ),
        TestCase(
            number: 6,
            message: "Since Contextify is the hero app for screenshots, would you like me to adjust the script to give Contextify more prominence in the window arrangement?",
            expectedDisposition: "proposal",
            expectedVerbPattern: "propos",
            category: "Proposal",
            description: "Would you like me to [verb] pattern"
        ),

        // CORRECT COMPLETIONS (5 cases - expected to remain CORRECT)
        TestCase(
            number: 7,
            message: "Good, I've updated it so it just shows the project name. Now it will say: Current Project: contextify",
            expectedDisposition: "completion",
            expectedVerbPattern: "updat",  // matches "updated", "updating"
            category: "Completion",
            description: "I've [verb]ed pattern"
        ),
        TestCase(
            number: 8,
            message: "Perfect! I've added the new property: allSessionsLastUpdate in ConversationMonitor to track when the complete session list was last refreshed. Now the inventory header will show accurate update times.",
            expectedDisposition: "completion",
            expectedVerbPattern: "add",  // matches "added", "adding"
            category: "Completion",
            description: "I've [verb]ed with result"
        ),
        TestCase(
            number: 9,
            message: "Done! I've added window restoration to the screenshot workflow: What was added: 1. setup-screenshot.sh saves current active app 2. capture-screenshot.sh performs the capture 3. restore-screenshot.sh returns to saved app",
            expectedDisposition: "completion",
            expectedVerbPattern: "add",
            category: "Completion",
            description: "Done! I've [verb]ed"
        ),
        TestCase(
            number: 10,
            message: "I've updated the dimensions. Now let me test the updated script to make sure it works properly with the new size.",
            expectedDisposition: "completion",
            expectedVerbPattern: "updat",
            category: "Completion",
            description: "I've [verb]ed with follow-up"
        ),
        TestCase(
            number: 11,
            message: "The README needs updating to reflect: 1. The new drafts/releases workflow 2. The text overlay feature 3. The preset screenshot dimensions",
            expectedDisposition: "completion",
            expectedVerbPattern: "updat",
            category: "Completion",
            description: "Implied completion"
        ),

        // CORRECT ANALYSIS (2 cases - expected to remain CORRECT)
        TestCase(
            number: 12,
            message: "The user wants me to look at three screenshots they've already taken to understand what style and dimensions they prefer. Let me read these image files to analyze their characteristics.",
            expectedDisposition: "analysis",
            expectedVerbPattern: "analyz",
            category: "Analysis",
            description: "Let me [analysis verb] - investigation"
        ),
        TestCase(
            number: 13,
            message: "Let me calculate the new dimensions: Current: 420×550 pixels. 15% increase: 420 × 1.15 = 483 width, 550 × 1.15 = 632.5 height. Rounded: 483×633 pixels.",
            expectedDisposition: "analysis",
            expectedVerbPattern: "calculat",
            category: "Analysis",
            description: "Let me [analysis verb] - calculation"
        ),
    ]

    // MARK: - Manual Validation Test

    func testTimelineFixManualValidation() async throws {
        print("\n")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Timeline Summarization Fix - Manual Validation")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")

        var results: [(test: TestCase, actualDisp: String, actualSummary: String, pass: Bool)] = []

        for testCase in testCases {
            print("Test \(testCase.number): \(testCase.description)")
            print("  Message: \(String(testCase.message.prefix(80)))...")
            print("  Expected: disposition=\(testCase.expectedDisposition), verb contains '\(testCase.expectedVerbPattern)'")

            do {
                let result = try await FoundationLLM.shared._testTimelineSummary(
                    message: testCase.message,
                    kind: .assistant,
                    provider: TimelineSourceContext.Provider(id: .claudeCode, displayName: "Claude Code")
                )

                let actualDisp = result.disposition
                let actualSummary = result.summary
                let summaryLower = actualSummary.lowercased()

                // Check disposition match
                let dispositionMatch = actualDisp == testCase.expectedDisposition

                // Check verb pattern in summary (case-insensitive partial match)
                let verbMatch = summaryLower.contains(testCase.expectedVerbPattern.lowercased())

                let pass = dispositionMatch && verbMatch

                results.append((testCase, actualDisp, actualSummary, pass))

                print("  Actual:   disposition=\(actualDisp), summary=\(actualSummary)")
                print("  Result:   \(pass ? "✅ PASS" : "❌ FAIL")")
                if !dispositionMatch {
                    print("            ⚠️  Disposition mismatch")
                }
                if !verbMatch {
                    print("            ⚠️  Verb pattern not found in summary")
                }
                print("")

            } catch {
                print("  Result:   ❌ ERROR - \(error)")
                print("")
                results.append((testCase, "ERROR", error.localizedDescription, false))
            }
        }

        // Print summary
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  VALIDATION SUMMARY")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")

        let proposalTests = results.filter { $0.test.category == "Proposal" }
        let completionTests = results.filter { $0.test.category == "Completion" }
        let analysisTests = results.filter { $0.test.category == "Analysis" }

        let proposalPass = proposalTests.filter { $0.pass }.count
        let completionPass = completionTests.filter { $0.pass }.count
        let analysisPass = analysisTests.filter { $0.pass }.count
        let totalPass = results.filter { $0.pass }.count

        print("Proposals:   \(proposalPass)/\(proposalTests.count) correct (\(Int(Double(proposalPass)/Double(proposalTests.count)*100))%)")
        print("             Target: ≥6/7 (85%) - \(proposalPass >= 6 ? "✅ MET" : "❌ NOT MET")")
        print("")
        print("Completions: \(completionPass)/\(completionTests.count) correct (\(Int(Double(completionPass)/Double(completionTests.count)*100))%)")
        print("             Target: ≥5/6 (83%) - \(completionPass >= 5 ? "✅ MET" : "❌ NOT MET")")
        print("")
        print("Analysis:    \(analysisPass)/\(analysisTests.count) correct (\(Int(Double(analysisPass)/Double(analysisTests.count)*100))%)")
        print("             Target: 2/2 (100%) - \(analysisPass == 2 ? "✅ MET" : "❌ NOT MET")")
        print("")
        print("Overall:     \(totalPass)/\(results.count) correct (\(Int(Double(totalPass)/Double(results.count)*100))%)")
        print("             Target: ≥13/15 (87%) - \(totalPass >= 13 ? "✅ MET" : "❌ NOT MET")")
        print("")

        // Write detailed results to file
        let resultsPath = "/tmp/timeline-fix-validation-results.md"
        var markdown = """
        # Timeline Fix Validation Results

        **Date:** \(Date())
        **Branch:** feature/timeline-summarization-disposition-fix

        ## Summary

        - Proposals: \(proposalPass)/\(proposalTests.count) correct (\(Int(Double(proposalPass)/Double(proposalTests.count)*100))%)
        - Completions: \(completionPass)/\(completionTests.count) correct (\(Int(Double(completionPass)/Double(completionTests.count)*100))%)
        - Analysis: \(analysisPass)/\(analysisTests.count) correct (\(Int(Double(analysisPass)/Double(analysisTests.count)*100))%)
        - Overall: \(totalPass)/\(results.count) correct (\(Int(Double(totalPass)/Double(results.count)*100))%)

        ## Detailed Results

        | # | Category | Expected Disp | Expected Verb | Actual Disp | Actual Summary | Pass/Fail |
        |---|----------|---------------|---------------|-------------|----------------|-----------|

        """

        for result in results {
            let status = result.pass ? "✅ PASS" : "❌ FAIL"
            let summaryPreview = String(result.actualSummary.prefix(60))
            markdown += "| \(result.test.number) | \(result.test.category) | \(result.test.expectedDisposition) | \(result.test.expectedVerbPattern)* | \(result.actualDisp) | \(summaryPreview)... | \(status) |\n"
        }

        try markdown.write(toFile: resultsPath, atomically: true, encoding: .utf8)
        print("Detailed results written to: \(resultsPath)")
        print("")

        // Assert success criteria
        XCTAssertGreaterThanOrEqual(proposalPass, 6, "Proposal accuracy should be ≥85% (6/7)")
        XCTAssertGreaterThanOrEqual(completionPass, 5, "Completion accuracy should be ≥83% (5/6)")
        XCTAssertEqual(analysisPass, 2, "Analysis accuracy should be 100% (2/2)")
        XCTAssertGreaterThanOrEqual(totalPass, 13, "Overall accuracy should be ≥87% (13/15)")
    }
}
#endif
