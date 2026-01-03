#!/bin/bash
# Test script for summarization fixes
# Single Enter to advance through tests, auto-copies each prompt to clipboard

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Test data: array of "prompt|expected_good|expected_bad|description|type|example_refs"
tests=(
    "you run it|'You requested to run it' or 'You asked Claude Code to execute'|'You said: you run it' (literal echo)|Short User Message Echo|USER|Example 2"
    "just say Done.|'Claude Code confirms completion' or 'Claude Code acknowledges'|'Claude Code Done.' (literal echo)|Short Assistant Response|ASSISTANT|Example 3"
    "tell me briefly about Claude Code's queue system|'Claude Code explained the queue system' (single attribution)|'Claude Code Claude Code's Queue System' (duplicate)|Duplicate Attribution|ASSISTANT|Example 14"
    "show me a markdown table with 3 columns: Name, Path, Port|'Claude Code provided a table' or 'Claude Code listed items'|'| Name | Path |' or '|---|' in summary|Markdown Table|ASSISTANT|Examples 1, 15"
    "gs|'You executed a command' or 'You ran gs'|'<bash-input>gs</bash-input>' in summary|XML Tags in Response|USER|Example 9"
    "find how the database migration works|'Claude Code searched/investigated/looked into...'|'Claude Code asked how...' (misattributed as question)|Investigation vs Question|ASSISTANT|Example 5"
    "are you stuck?|'You asked if Claude Code was stuck'|'You asked if you were stuck' (pronoun confusion)|Pronoun Confusion|USER|Example 8"
    "we should have better documentation for this|'You suggested improving documentation'|'You requested to create documentation'|Suggestion vs Request|USER|Example 10"
    "my video is about 35 minutes long|'You mentioned your video is 35 minutes'|'You noted that my video is 35 minutes'|First-Person Pronoun|USER|Example 11"
    "plan out how you would add dark mode, but don't implement yet|'Claude Code proposed/outlined dark mode'|'Claude Code implemented dark mode'|Future Work vs Completion|ASSISTANT|Example 12"
    "great. commit and push|'You requested to commit and push'|'You noted...' (missed imperative)|Multi-clause Imperative|USER|Example 13"
    "/private/tmp/test-output.json|'You referenced a file path'|'You performed command /private/tmp/...'|File Path vs Command|USER|Example 16"
    "this seems poorly formatted: { \"name\": \"test\", \"value\": 123 }|'You noted something was poorly formatted'|Summary contains the JSON content literally|Nested JSON Content|USER|Example 7"
)

current=0
total=${#tests[@]}

show_test() {
    local idx=$1
    local test_data="${tests[$idx]}"
    IFS='|' read -r prompt expected_good expected_bad description type example_refs <<< "$test_data"

    clear
    echo "==========================================="
    echo -e "  Test $((idx + 1)) of $total: ${CYAN}${description}${NC}"
    echo "==========================================="
    echo ""
    echo -e "${YELLOW}Type: ${type} message${NC}"
    echo -e "${DIM}Reference: ${example_refs}${NC}"
    echo ""
    echo -e "Prompt: ${CYAN}${prompt}${NC}"
    echo ""
    echo -e "${GREEN}GOOD: ${expected_good}${NC}"
    echo -e "${YELLOW}BAD:  ${expected_bad}${NC}"
    echo ""

    # Auto-copy to clipboard
    echo -n "$prompt" | pbcopy
    echo -e "${DIM}[Copied to clipboard]${NC}"
    echo ""
    echo -e "${DIM}Press ENTER for next test (or 'q' to quit)${NC}"
}

echo "==========================================="
echo "  Summarization Fix Validation Script"
echo "==========================================="
echo ""
echo "Instructions:"
echo "1. Have Contextify running watching a Claude Code session"
echo "2. Each test auto-copies a prompt to clipboard"
echo "3. Paste into Claude Code and observe the timeline summary"
echo "4. Press ENTER to advance to next test"
echo ""
read -p "Press ENTER to begin..."

# Show first test
show_test 0

while true; do
    read -r input

    if [[ "$input" == "q" || "$input" == "Q" ]]; then
        echo ""
        echo "Exited at test $((current + 1)) of $total"
        exit 0
    fi

    current=$((current + 1))

    if [[ $current -ge $total ]]; then
        clear
        echo "==========================================="
        echo -e "${GREEN}  All $total tests complete!${NC}"
        echo "==========================================="
        echo ""
        echo "Review the summaries you observed against expected results."
        echo ""
        echo "Handled by TimelineSummaryFallback (should pass):"
        echo "  - Tests 1-5, 7-9, 11-12: Echo, format, pronoun, suggestion, imperative, path"
        echo ""
        echo "Requires prompt improvements (may still fail):"
        echo "  - Test 6: Investigation vs Question (Example 5)"
        echo "  - Test 10: Future Work vs Completion (Example 12)"
        echo "  - Test 13: Nested JSON Content (Example 7)"
        exit 0
    fi

    show_test $current
done
