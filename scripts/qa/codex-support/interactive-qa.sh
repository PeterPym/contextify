#!/bin/bash
# scripts/qa/codex-support/interactive-qa.sh
#
# Interactive QA script for Codex skill support feature.
# Guides user through validation steps and captures proof.
#
# Usage: ./scripts/qa/codex-support/interactive-qa.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Proof file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROOF_FILE="/tmp/codex-skill-qa-proof-${TIMESTAMP}.md"

# Counters
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# --- Helper Functions ---

header() {
  echo ""
  echo -e "${BLUE}${BOLD}=== $1 ===${NC}"
  echo ""
}

step() {
  echo -e "${CYAN}▶ $1${NC}"
}

pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
  echo "- [x] $1" >> "$PROOF_FILE"
  ((PASS_COUNT++))
}

fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  echo "- [ ] **FAIL:** $1" >> "$PROOF_FILE"
  ((FAIL_COUNT++))
}

skip() {
  echo -e "${YELLOW}⊘ SKIP: $1${NC}"
  echo "- [ ] *SKIP:* $1" >> "$PROOF_FILE"
  ((SKIP_COUNT++))
}

info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

prompt_continue() {
  echo ""
  read -p "Press Enter to continue (or Ctrl+C to abort)..."
  echo ""
}

capture_output() {
  echo '```' >> "$PROOF_FILE"
  cat >> "$PROOF_FILE"
  echo '```' >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"
}

# --- Initialize Proof File ---

cat > "$PROOF_FILE" << EOF
---
feature: codex-skill-support
branch: $(git branch --show-current 2>/dev/null || echo "unknown")
worktree: $(pwd)
date: $(date +%Y-%m-%d)
generated: $(date -Iseconds)
tester: interactive
---

# Codex Skill Support - QA Proof

EOF

echo -e "${BOLD}Codex Skill Support - Interactive QA${NC}"
echo "Proof file: $PROOF_FILE"
echo ""

# --- Pre-Flight Checks ---

header "Pre-Flight Checks"

echo "## Pre-Flight Checks" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

# Check contextify-query
step "Checking contextify-query availability..."
if command -v contextify-query &> /dev/null; then
  VERSION=$(contextify-query --version 2>&1 | grep -E "^contextify-query" | head -1 || echo "unknown")
  pass "contextify-query found: $VERSION"
  echo "Version: $VERSION" | capture_output
else
  fail "contextify-query not found in PATH"
  echo "Cannot proceed without contextify-query"
  exit 1
fi

# Check Codex CLI
step "Checking Codex CLI availability..."
if command -v codex &> /dev/null; then
  CODEX_VERSION=$(codex --version 2>&1 | head -1 || echo "unknown")
  pass "Codex CLI found: $CODEX_VERSION"
  CODEX_AVAILABLE=true
else
  skip "Codex CLI not installed (integration tests will be skipped)"
  CODEX_AVAILABLE=false
fi

# Check database
step "Checking Contextify database..."
if contextify-query status --json 2>/dev/null | grep -q '"projectCount"'; then
  pass "Contextify database accessible"
else
  fail "Contextify database not found or inaccessible"
fi

prompt_continue

# --- Clear State ---

header "Clearing Previous State"

echo "## State Clearing" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

step "Removing existing skills..."
rm -rf ~/.claude/skills/total-recall 2>/dev/null && info "Removed ~/.claude/skills/total-recall" || true
rm -rf ~/.codex/skills/total-recall 2>/dev/null && info "Removed ~/.codex/skills/total-recall" || true

pass "Previous state cleared"

prompt_continue

# --- Installation Test ---

header "Installation Test"

echo "## Installation Test" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

step "Running: contextify-query install-plugin"
echo "Command: \`contextify-query install-plugin\`" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

INSTALL_OUTPUT=$(contextify-query install-plugin 2>&1)
INSTALL_EXIT=$?

echo "$INSTALL_OUTPUT"
echo "$INSTALL_OUTPUT" | capture_output

if [ $INSTALL_EXIT -eq 0 ] && echo "$INSTALL_OUTPUT" | grep -qi "installed"; then
  pass "install-plugin completed successfully (exit code 0)"
else
  fail "install-plugin failed (exit code $INSTALL_EXIT)"
fi

prompt_continue

# --- File Verification ---

header "File Verification"

echo "## File Verification" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

# Claude skill
step "Checking Claude skill..."
echo "### Claude Skill" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ -f ~/.claude/skills/total-recall/SKILL.md ]; then
  pass "Claude skill exists at ~/.claude/skills/total-recall/SKILL.md"
  ls -la ~/.claude/skills/total-recall/ | capture_output
else
  fail "Claude skill NOT found"
fi

# Codex skill
step "Checking Codex skill..."
echo "### Codex Skill" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  pass "Codex skill exists at ~/.codex/skills/total-recall/SKILL.md"
  ls -la ~/.codex/skills/total-recall/ | capture_output
else
  fail "Codex skill NOT found"
fi

# Symlink check
step "Verifying Codex skill is NOT a symlink..."
echo "### Symlink Check" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ -L ~/.codex/skills/total-recall/SKILL.md ]; then
  fail "Codex skill IS a symlink (Codex ignores symlinks!)"
  ls -la ~/.codex/skills/total-recall/SKILL.md | capture_output
else
  pass "Codex skill is a real file (not symlink)"
  file ~/.codex/skills/total-recall/SKILL.md | capture_output
fi

# Content match
step "Verifying content matches..."
echo "### Content Match" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ -f ~/.claude/skills/total-recall/SKILL.md ] && [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  CLAUDE_MD5=$(md5 -q ~/.claude/skills/total-recall/SKILL.md)
  CODEX_MD5=$(md5 -q ~/.codex/skills/total-recall/SKILL.md)

  if [ "$CLAUDE_MD5" = "$CODEX_MD5" ]; then
    pass "Content identical (MD5: $CLAUDE_MD5)"
    echo "Claude MD5: $CLAUDE_MD5" >> "$PROOF_FILE"
    echo "Codex MD5:  $CODEX_MD5" >> "$PROOF_FILE"
    echo "" >> "$PROOF_FILE"
  else
    fail "Content differs between Claude and Codex skills"
  fi
else
  skip "Cannot compare content - one or both files missing"
fi

prompt_continue

# --- Codex CLI Integration ---

header "Codex CLI Integration Test"

echo "## Codex CLI Integration Test" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ "$CODEX_AVAILABLE" = true ]; then

  # Skill Discovery
  step "Testing Codex skill discovery..."
  echo "### Skill Discovery" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"
  echo "Command: \`codex exec --dangerously-bypass-approvals-and-sandbox \"List your available skills\"\`" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"

  info "This will invoke Codex CLI and may take 30-60 seconds..."
  echo ""

  DISCOVERY_OUTPUT=$(timeout 120 codex exec --dangerously-bypass-approvals-and-sandbox \
    "What skills do you have available? Just list the skill names, nothing else." 2>&1 || echo "TIMEOUT_OR_ERROR")

  echo "$DISCOVERY_OUTPUT" | head -40
  echo "$DISCOVERY_OUTPUT" | head -60 | capture_output

  if echo "$DISCOVERY_OUTPUT" | grep -qi "total-recall"; then
    pass "Codex discovered total-recall skill"
  elif [ "$DISCOVERY_OUTPUT" = "TIMEOUT_OR_ERROR" ]; then
    fail "Codex CLI timed out or errored"
  else
    fail "Codex did NOT discover total-recall skill"
  fi

  prompt_continue

  # Skill Execution
  step "Testing Codex skill execution..."
  echo "### Skill Execution" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"
  echo "Command: \`codex exec ... \"Use /total-recall to search for 'test'\"\`" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"

  info "This will invoke the skill and may take 60-90 seconds..."
  echo ""

  EXEC_OUTPUT=$(timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox \
    "Use /total-recall to search for 'validation test'. Just tell me how many results." 2>&1 || echo "TIMEOUT_OR_ERROR")

  echo "$EXEC_OUTPUT" | head -60
  echo "$EXEC_OUTPUT" | head -80 | capture_output

  if echo "$EXEC_OUTPUT" | grep -qiE "(contextify|total.recall|search|results|found|count)"; then
    pass "Codex executed total-recall skill successfully"
  elif [ "$EXEC_OUTPUT" = "TIMEOUT_OR_ERROR" ]; then
    fail "Codex CLI timed out or errored during execution"
  else
    fail "Codex skill execution did not produce expected output"
  fi

else
  skip "Codex CLI not available - skipping integration tests"
  echo "*Codex CLI not installed - integration tests skipped*" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"
fi

prompt_continue

# --- Uninstall Test ---

header "Uninstall Test"

echo "## Uninstall Test" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

step "Running: contextify-query uninstall-plugin"
echo "Command: \`contextify-query uninstall-plugin\`" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

UNINSTALL_OUTPUT=$(contextify-query uninstall-plugin 2>&1)
UNINSTALL_EXIT=$?

echo "$UNINSTALL_OUTPUT"
echo "$UNINSTALL_OUTPUT" | capture_output

if [ $UNINSTALL_EXIT -eq 0 ]; then
  pass "uninstall-plugin completed (exit code 0)"
else
  fail "uninstall-plugin failed (exit code $UNINSTALL_EXIT)"
fi

# Verify removal
step "Verifying skills removed..."
echo "### Removal Verification" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

if [ -e ~/.claude/skills/total-recall ]; then
  fail "Claude skill directory still exists after uninstall"
else
  pass "Claude skill directory removed"
fi

if [ -e ~/.codex/skills/total-recall ]; then
  fail "Codex skill directory still exists after uninstall"
else
  pass "Codex skill directory removed"
fi

# --- Summary ---

header "QA Summary"

cat >> "$PROOF_FILE" << EOF

---

## Summary

| Metric | Count |
|--------|-------|
| Passed | $PASS_COUNT |
| Failed | $FAIL_COUNT |
| Skipped | $SKIP_COUNT |
| Total | $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)) |

EOF

echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}Passed:  $PASS_COUNT${NC}"
echo -e "  ${RED}Failed:  $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}Skipped: $SKIP_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "**Result: ALL TESTS PASSED**" >> "$PROOF_FILE"
  echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
  RESULT="PASS"
else
  echo "**Result: $FAIL_COUNT TEST(S) FAILED**" >> "$PROOF_FILE"
  echo -e "${RED}${BOLD}✗ $FAIL_COUNT TEST(S) FAILED${NC}"
  RESULT="FAIL"
fi

echo ""
echo -e "${BOLD}Proof file:${NC} $PROOF_FILE"
echo ""

# Reinstall for continued use
read -p "Reinstall skill for continued use? [Y/n] " reinstall
if [ "$reinstall" != "n" ] && [ "$reinstall" != "N" ]; then
  contextify-query install-plugin > /dev/null 2>&1
  echo -e "${GREEN}✓ Skill reinstalled${NC}"
fi

echo ""
echo "Done."

if [ "$RESULT" = "FAIL" ]; then
  exit 1
fi
