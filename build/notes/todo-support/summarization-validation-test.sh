#!/bin/bash
# Test script for summarization fixes
# Hit enter to copy each test message, paste into Claude Code, observe summary

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

copy_to_clipboard() {
    echo -n "$1" | pbcopy
    echo -e "${GREEN}Copied to clipboard!${NC}"
}

echo "==========================================="
echo "  Summarization Fix Validation Script"
echo "==========================================="
echo ""
echo "Instructions:"
echo "1. Have Contextify running and watching a Claude Code session"
echo "2. Press ENTER to copy a test message"
echo "3. Paste into Claude Code (or send as user message)"
echo "4. Check the timeline summary in Contextify"
echo "5. Press ENTER for expected result, then ENTER for next test"
echo ""
read -p "Press ENTER to begin..."

# ============================================
# ECHO/PASSTHROUGH TESTS (Examples 2, 3, 6, 14, 17)
# ============================================

echo ""
echo -e "${CYAN}=== TEST 1: Short User Message Echo (Example 2) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: Short messages should NOT just echo 'You said: X'"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "you run it"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: Should be a proper summary like 'You requested to run it' or 'You asked Claude Code to execute'${NC}"
echo -e "${GREEN}BAD: 'You said: you run it' (literal echo)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 2: Short Assistant Response (Example 3) ===${NC}"
echo -e "${YELLOW}Type: ASSISTANT message${NC}"
echo "Testing: Short responses should get meaningful summaries"
echo "(For this test, ask Claude to do something simple and watch its 'Done.' response)"
read -p "Press ENTER to copy a prompt that should get short response..."
copy_to_clipboard "just say Done."
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'Claude Code confirms completion' or 'Claude Code acknowledges the request'${NC}"
echo -e "${GREEN}BAD: 'Claude Code Done.' (literal echo with prefix)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 3: Duplicate Attribution (Example 14) ===${NC}"
echo -e "${YELLOW}Type: ASSISTANT message${NC}"
echo "Testing: Should NOT produce 'Claude Code Claude Code...'"
echo "(Send a message about Claude Code's features)"
read -p "Press ENTER to copy test prompt..."
copy_to_clipboard "tell me briefly about Claude Code's queue system"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'Claude Code explained the queue system' (single attribution)${NC}"
echo -e "${GREEN}BAD: 'Claude Code Claude Code's Queue System' (duplicate attribution)${NC}"
read -p "Press ENTER for next test..."

# ============================================
# FORMAT ISSUE TESTS (Examples 1, 4, 9, 15)
# ============================================

echo ""
echo -e "${CYAN}=== TEST 4: Markdown Table (Examples 1, 15) ===${NC}"
echo -e "${YELLOW}Type: ASSISTANT message${NC}"
echo "Testing: Tables should NOT appear in summary"
read -p "Press ENTER to copy test prompt..."
copy_to_clipboard "show me a markdown table with 3 columns: Name, Path, Port"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'Claude Code provided a table' or 'Claude Code listed items'${NC}"
echo -e "${GREEN}BAD: '| Name | Path | Port |' or '|---|' in summary${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 5: XML Tags in Response (Example 9) ===${NC}"
echo -e "${YELLOW}Type: USER message with bash command${NC}"
echo "Testing: XML tags should NOT leak into summary"
read -p "Press ENTER to copy test command..."
copy_to_clipboard "gs"
echo ""
echo "(This simulates a bash command input)"
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You executed a command' or 'You ran gs'${NC}"
echo -e "${GREEN}BAD: '<bash-input>gs</bash-input>' in summary${NC}"
read -p "Press ENTER for next test..."

# ============================================
# ATTRIBUTION ERROR TESTS (Examples 5, 8, 10, 11, 12, 13, 16)
# ============================================

echo ""
echo -e "${CYAN}=== TEST 6: Investigation vs Question (Example 5) ===${NC}"
echo -e "${YELLOW}Type: ASSISTANT message${NC}"
echo "Testing: 'Let me find...' is an ACTION, not a question"
read -p "Press ENTER to copy test prompt..."
copy_to_clipboard "find how the database migration works"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'Claude Code searched/investigated/looked into...'${NC}"
echo -e "${GREEN}BAD: 'Claude Code asked how...' (misattributed as question)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 7: Pronoun Confusion - Addressing Assistant (Example 8) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: 'are you stuck?' should refer to Claude, not user"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "are you stuck?"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You asked if Claude Code was stuck'${NC}"
echo -e "${GREEN}BAD: 'You asked if you were stuck' (pronoun confusion)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 8: Suggestion vs Request (Example 10) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: 'we should...' is a SUGGESTION, not a request"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "we should have better documentation for this"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You suggested improving documentation' or 'You noted documentation could be better'${NC}"
echo -e "${GREEN}BAD: 'You requested to create documentation' (misattributed as request)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 9: First-Person Pronoun Conversion (Example 11) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: 'my video' should become 'your video' in summary"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "my video is about 35 minutes long"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You mentioned your video is 35 minutes' (converted pronoun)${NC}"
echo -e "${GREEN}BAD: 'You noted that my video is 35 minutes' (unconverted pronoun)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 10: Future Work vs Completion (Example 12) ===${NC}"
echo -e "${YELLOW}Type: ASSISTANT message${NC}"
echo "Testing: 'Ready to implement' is PROPOSAL, not completion"
read -p "Press ENTER to copy test prompt..."
copy_to_clipboard "plan out how you would add dark mode, but don't implement yet"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'Claude Code proposed/outlined dark mode implementation'${NC}"
echo -e "${GREEN}BAD: 'Claude Code implemented dark mode' (future work claimed as done)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 11: Multi-clause Imperative (Example 13) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: 'great. commit and push' has a REQUEST after acknowledgment"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "great. commit and push"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You requested to commit and push' or 'You asked Claude Code to commit'${NC}"
echo -e "${GREEN}BAD: 'You noted...' (missed the imperative)${NC}"
read -p "Press ENTER for next test..."

echo ""
echo -e "${CYAN}=== TEST 12: File Path vs Command (Example 16) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: File paths should NOT be treated as slash commands"
read -p "Press ENTER to copy test message..."
copy_to_clipboard "/private/tmp/test-output.json"
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You referenced a file path' or 'You mentioned /private/tmp/...'${NC}"
echo -e "${GREEN}BAD: 'You performed command /private/tmp/...' (file path as command)${NC}"
read -p "Press ENTER for next test..."

# ============================================
# NESTED CONTENT TEST (Example 7)
# ============================================

echo ""
echo -e "${CYAN}=== TEST 13: Nested JSON Content (Example 7) ===${NC}"
echo -e "${YELLOW}Type: USER message${NC}"
echo "Testing: JSON blobs should not be summarized literally"
read -p "Press ENTER to copy test message..."
copy_to_clipboard 'this seems poorly formatted: { "name": "test", "value": 123 }'
echo ""
read -p "Press ENTER to see expected summary..."
echo -e "${GREEN}EXPECTED: 'You noted something was poorly formatted' (summarize framing, not JSON)${NC}"
echo -e "${GREEN}BAD: Summary contains the JSON content literally${NC}"
read -p "Press ENTER to finish..."

echo ""
echo "==========================================="
echo -e "${GREEN}  All tests complete!${NC}"
echo "==========================================="
echo ""
echo "Review the summaries you observed against the expected results."
echo "Report: /tmp/summarization-fixes-report.md"
