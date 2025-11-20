#!/bin/bash
# Timeline Summarization Fix - Manual Validation Runner
#
# This script provides a structured way to validate the 15 test cases
# Run this after building the DEBUG version of Contextify
#
# Usage: bash scripts/run-timeline-validation.sh

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Timeline Summarization Fix - Manual Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Testing 15 real conversation turns from production database"
echo ""
echo "Test Categories:"
echo "  - 6 Misattributed Proposals (expected to be FIXED)"
echo "  - 5 Correct Completions (expected to remain CORRECT)"
echo "  - 2 Correct Analysis (expected to remain CORRECT)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create results directory
mkdir -p build/notes
RESULTS_FILE="build/notes/timeline-fix-validation-results.md"

# Initialize results file
cat > "$RESULTS_FILE" <<'EOF'
# Timeline Fix Validation Results

**Date:** $(date +%Y-%m-%d)
**Branch:** feature/timeline-summarization-disposition-fix
**Commit:** $(git rev-parse --short HEAD)

## Test Results

| # | Category | Expected Disp | Expected Verb | Actual Disp | Actual Verb | Pass/Fail | Notes |
|---|----------|---------------|---------------|-------------|-------------|-----------|-------|
EOF

echo "Instructions for Manual Testing:"
echo ""
echo "1. Open Contextify.xcodeproj in Xcode"
echo "2. Ensure DEBUG configuration is active"
echo "3. Add this test code in a playground or test file:"
echo ""
echo "────────────────────────────────────────────────────────────────────"
cat <<'SWIFT'
import Foundation

@available(macOS 26.0, *)
func testTimelineSummary(number: Int, message: String, expectedDisp: String, expectedVerb: String) async {
    do {
        let result = try await FoundationLLM.shared._testTimelineSummary(
            message: message,
            kind: .assistant,
            provider: TimelineSourceContext.Provider(id: .claudeCode, displayName: "Claude Code")
        )

        let actualVerb = extractMainVerb(from: result.summary)
        let pass = (result.disposition == expectedDisp) && actualVerb.contains(expectedVerb)

        print("Test \(number): \(pass ? "✅ PASS" : "❌ FAIL")")
        print("  Expected: disposition=\(expectedDisp), verb=\(expectedVerb)")
        print("  Actual:   disposition=\(result.disposition), verb=\(actualVerb)")
        print("  Summary:  \(result.summary)")
        print("")
    } catch {
        print("Test \(number): ❌ ERROR - \(error)")
    }
}

func extractMainVerb(from summary: String) -> String {
    // Extract the main verb from "Claude Code [verb] [rest]"
    let components = summary.components(separatedBy: " ")
    if components.count >= 3 {
        return components[2]
    }
    return ""
}
SWIFT
echo "────────────────────────────────────────────────────────────────────"
echo ""
echo "4. Run each test case (see test-cases.txt for full list)"
echo "5. Record results in: $RESULTS_FILE"
echo ""

# Generate test cases file
TEST_CASES_FILE="build/notes/timeline-test-cases.txt"
cat > "$TEST_CASES_FILE" <<'EOF'
Timeline Summarization Fix - Test Cases
========================================

Run each test case through the test function above and record:
- Actual disposition
- Actual verb (extracted from summary)
- Pass/Fail status

═══════════════════════════════════════════════════════════════════════════════
MISATTRIBUTED PROPOSALS (Expected to be FIXED)
═══════════════════════════════════════════════════════════════════════════════

Test 1: Let me [verb] pattern
Message: "Let me create a simple helper script or add functionality to handle common screenshot types with preset dimensions and overlay text. This would make repeated screenshot tasks much faster."
Expected Disposition: proposal
Expected Verb: "proposed"
Category: Proposal

Test 2: I'll [verb] pattern
Message: "Now I'll create the script that adds text overlays using ImageMagick. The script should: take input image, text to overlay, output path, and optionally font size and color."
Expected Disposition: proposal
Expected Verb: "proposed"
Category: Proposal

Test 3: Let me [verb] pattern (mixed)
Message: "The user wants me to: 1. Commit the changes 2. Then see if I can trigger the transcript inventory window to appear. Let me commit first, then explore the trigger mechanism."
Expected Disposition: proposal
Expected Verb: "proposed"
Category: Proposal

Test 4: I need to [verb] pattern
Message: "Now I need to update the restoration part to restore both the main Contextify window and iTerm2 window that was active before the screenshot workflow started."
Expected Disposition: proposal
Expected Verb: "noted" (or similar proposal verb)
Category: Proposal

Test 5: Analysis misclassified as proposal
Message: "Looking at the presets, the 'settings' preset opens the ConversationMonitor settings. But there should be a Settings window or panel that allows adjusting other database and backup features."
Expected Disposition: analysis
Expected Verb: "analyzed" (or "noted")
Category: Analysis (was misclassified as proposal)

Test 6: Would you like me to [verb] pattern
Message: "Since Contextify is the hero app for screenshots, would you like me to adjust the script to give Contextify more prominence in the window arrangement?"
Expected Disposition: proposal
Expected Verb: "proposed"
Category: Proposal

═══════════════════════════════════════════════════════════════════════════════
CORRECT COMPLETIONS (Expected to remain CORRECT)
═══════════════════════════════════════════════════════════════════════════════

Test 7: I've [verb]ed pattern
Message: "Good, I've updated it so it just shows the project name. Now it will say: Current Project: contextify"
Expected Disposition: completion
Expected Verb: "updated"
Category: Completion

Test 8: I've [verb]ed with result
Message: "Perfect! I've added the new property: allSessionsLastUpdate in ConversationMonitor to track when the complete session list was last refreshed. Now the inventory header will show accurate update times."
Expected Disposition: completion
Expected Verb: "added"
Category: Completion

Test 9: Done! I've [verb]ed
Message: "Done! I've added window restoration to the screenshot workflow: What was added: 1. setup-screenshot.sh saves current active app 2. capture-screenshot.sh performs the capture 3. restore-screenshot.sh returns to saved app"
Expected Disposition: completion
Expected Verb: "added"
Category: Completion

Test 10: I've [verb]ed with follow-up
Message: "I've updated the dimensions. Now let me test the updated script to make sure it works properly with the new size."
Expected Disposition: completion
Expected Verb: "updated"
Category: Completion

Test 11: Implied completion
Message: "The README needs updating to reflect: 1. The new drafts/releases workflow 2. The text overlay feature 3. The preset screenshot dimensions"
Expected Disposition: completion
Expected Verb: "updated" (or "noted")
Category: Completion

═══════════════════════════════════════════════════════════════════════════════
CORRECT ANALYSIS (Expected to remain CORRECT)
═══════════════════════════════════════════════════════════════════════════════

Test 12: Let me [analysis verb] - investigation
Message: "The user wants me to look at three screenshots they've already taken to understand what style and dimensions they prefer. Let me read these image files to analyze their characteristics."
Expected Disposition: analysis
Expected Verb: "analyzed"
Category: Analysis

Test 13: Let me [analysis verb] - calculation
Message: "Let me calculate the new dimensions: Current: 420×550 pixels. 15% increase: 420 × 1.15 = 483 width, 550 × 1.15 = 632.5 height. Rounded: 483×633 pixels."
Expected Disposition: analysis
Expected Verb: "calculated"
Category: Analysis

═══════════════════════════════════════════════════════════════════════════════

Success Criteria:
  - Proposals: ≥6/7 correct (85%) - CRITICAL
  - Completions: ≥5/6 correct (83%) - MAINTAIN
  - Analysis: 2/2 correct (100%) - MAINTAIN
  - Overall: ≥13/15 correct (87%)

EOF

echo "Test cases written to: $TEST_CASES_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next Steps:"
echo "  1. Review test cases: cat $TEST_CASES_FILE"
echo "  2. Run tests in Xcode (use the Swift code above)"
echo "  3. Record results in: $RESULTS_FILE"
echo "  4. Calculate success rates"
echo ""
echo "Alternatively, run the integrated test:"
echo "  open build/notes/timeline-test-cases.txt"
echo "  # Then manually test each case using the app's DEBUG functions"
echo ""
