#!/bin/bash
# scripts/qa/codex-support/interactive-qa-app.sh
#
# Interactive QA script for testing Codex skill support via the Contextify app UI.
# Guides user through Settings > CLI tab toggle testing.
#
# Usage: ./scripts/qa/codex-support/interactive-qa-app.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Proof file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROOF_FILE="/tmp/codex-skill-app-qa-proof-${TIMESTAMP}.md"

# Counters
PASS_COUNT=0
FAIL_COUNT=0

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
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  echo "- [ ] **FAIL:** $1" >> "$PROOF_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

prompt_action() {
  echo ""
  echo -e "${BOLD}$1${NC}"
  read -p "Press Enter when done..."
  echo ""
}

check_skill_exists() {
  local path="$1"
  local name="$2"
  if [ -f "$path" ]; then
    pass "$name skill exists"
    return 0
  else
    fail "$name skill does NOT exist"
    return 1
  fi
}

check_skill_removed() {
  local path="$1"
  local name="$2"
  if [ ! -e "$path" ]; then
    pass "$name skill removed"
    return 0
  else
    fail "$name skill still exists"
    return 1
  fi
}

check_not_symlink() {
  local path="$1"
  if [ -L "$path" ]; then
    fail "Codex skill is a symlink (should be real file)"
    return 1
  else
    pass "Codex skill is a real file (not symlink)"
    return 0
  fi
}

# --- Initialize Proof File ---

cat > "$PROOF_FILE" << EOF
---
feature: codex-skill-support
test-type: app-ui
branch: $(git branch --show-current 2>/dev/null || echo "unknown")
date: $(date +%Y-%m-%d)
generated: $(date -Iseconds)
---

# Codex Skill Support - App UI QA Proof

Testing Settings > CLI tab toggle functionality.

EOF

echo -e "${BOLD}Codex Skill Support - App UI QA${NC}"
echo "Proof file: $PROOF_FILE"
echo ""

# --- Pre-Flight ---

header "Pre-Flight"

echo "## Pre-Flight" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_APP="$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app"

# Build the feature branch
step "Building feature branch..."
echo "Build output:" >> "$PROOF_FILE"
if bash "$REPO_ROOT/scripts/xc.sh" build > /tmp/qa-build-output.txt 2>&1; then
  if grep -q "BUILD SUCCEEDED" /tmp/qa-build-output.txt; then
    pass "Build succeeded"
    echo "- Build: SUCCEEDED" >> "$PROOF_FILE"
  else
    fail "Build did not report success"
    cat /tmp/qa-build-output.txt
    exit 1
  fi
else
  fail "Build failed"
  cat /tmp/qa-build-output.txt
  exit 1
fi

# Verify dev build exists
if [ ! -d "$DEV_APP" ]; then
  fail "Dev build not found at $DEV_APP"
  exit 1
fi
pass "Dev build exists"

# Kill any running Contextify
step "Stopping any running Contextify..."
if pgrep -x "Contextify" > /dev/null; then
  pkill -x "Contextify" 2>/dev/null || true
  sleep 1
  info "Stopped existing Contextify process"
fi

# Start the dev build
step "Starting dev build..."
open "$DEV_APP"
sleep 3

# Verify it's the right build
step "Verifying correct build is running..."
APP_PATH=$(ps aux | grep "Contextify.app" | grep -v grep | head -1 | sed 's/.*\(\/.*Contextify\.app\).*/\1/' || echo "")
if echo "$APP_PATH" | grep -q "derived-dmg"; then
  pass "DMG dev build running"
  echo "Build: DMG dev build (unsandboxed)" >> "$PROOF_FILE"
  echo "Path: $APP_PATH" >> "$PROOF_FILE"
elif echo "$APP_PATH" | grep -q "derived-appstore"; then
  fail "Wrong build type - App Store build running instead of DMG"
  echo "Build: App Store (wrong)" >> "$PROOF_FILE"
  exit 1
else
  fail "Wrong build running: $APP_PATH"
  echo "Expected: .derived-dmg build"
  echo "Got: $APP_PATH"
  exit 1
fi

echo "" >> "$PROOF_FILE"

# --- Clear State ---

header "Clear State"

echo "## Clear State" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

step "Clearing existing skills..."
rm -rf ~/.claude/skills/total-recall 2>/dev/null || true
rm -rf ~/.codex/skills/total-recall 2>/dev/null || true
pass "Cleared existing skills"

echo ""
echo "Current state:"
echo "  Claude: $(ls ~/.claude/skills/total-recall/SKILL.md 2>&1 || echo 'not installed')"
echo "  Codex:  $(ls ~/.codex/skills/total-recall/SKILL.md 2>&1 || echo 'not installed')"

# --- Test Enable ---

header "Test Enable"

echo "## Test Enable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

prompt_action "In Contextify.app:
  1. Open Settings (Cmd+,)
  2. Go to CLI tab
  3. Click 'Enable' button"

step "Verifying skills were installed..."

echo "### After Enable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

# Check Claude skill
if check_skill_exists ~/.claude/skills/total-recall/SKILL.md "Claude"; then
  echo "Claude: $(ls -la ~/.claude/skills/total-recall/SKILL.md)" >> "$PROOF_FILE"
fi

# Check Codex skill
if check_skill_exists ~/.codex/skills/total-recall/SKILL.md "Codex"; then
  echo "Codex: $(ls -la ~/.codex/skills/total-recall/SKILL.md)" >> "$PROOF_FILE"

  # Check not symlink
  check_not_symlink ~/.codex/skills/total-recall/SKILL.md
  echo "File type: $(file ~/.codex/skills/total-recall/SKILL.md)" >> "$PROOF_FILE"
fi

# Check content matches
if [ -f ~/.claude/skills/total-recall/SKILL.md ] && [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  CLAUDE_MD5=$(md5 -q ~/.claude/skills/total-recall/SKILL.md 2>/dev/null || echo "error")
  CODEX_MD5=$(md5 -q ~/.codex/skills/total-recall/SKILL.md 2>/dev/null || echo "error")

  if [ "$CLAUDE_MD5" = "$CODEX_MD5" ] && [ "$CLAUDE_MD5" != "error" ]; then
    pass "Content identical (MD5: $CLAUDE_MD5)"
  else
    fail "Content mismatch or error"
  fi
fi

echo "" >> "$PROOF_FILE"

# --- Test Disable ---

header "Test Disable"

echo "## Test Disable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

prompt_action "In Contextify.app:
  1. Settings > CLI tab
  2. Click 'Disable' button"

step "Verifying skills were removed..."

echo "### After Disable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

check_skill_removed ~/.claude/skills/total-recall "Claude"
check_skill_removed ~/.codex/skills/total-recall "Codex"

echo "" >> "$PROOF_FILE"

# --- Test Re-Enable ---

header "Test Re-Enable (Idempotency)"

echo "## Test Re-Enable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

prompt_action "In Contextify.app:
  1. Settings > CLI tab
  2. Click 'Enable' button again"

step "Verifying skills were reinstalled..."

echo "### After Re-Enable" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

check_skill_exists ~/.claude/skills/total-recall/SKILL.md "Claude"
check_skill_exists ~/.codex/skills/total-recall/SKILL.md "Codex"

if [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  check_not_symlink ~/.codex/skills/total-recall/SKILL.md
fi

echo "" >> "$PROOF_FILE"

# --- Summary ---

header "Summary"

cat >> "$PROOF_FILE" << EOF

---

## Summary

| Metric | Count |
|--------|-------|
| Passed | $PASS_COUNT |
| Failed | $FAIL_COUNT |
| Total | $((PASS_COUNT + FAIL_COUNT)) |

EOF

echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}Passed:  $PASS_COUNT${NC}"
echo -e "  ${RED}Failed:  $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "**Result: ALL TESTS PASSED**" >> "$PROOF_FILE"
  echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
else
  echo "**Result: $FAIL_COUNT TEST(S) FAILED**" >> "$PROOF_FILE"
  echo -e "${RED}${BOLD}✗ $FAIL_COUNT TEST(S) FAILED${NC}"
fi

echo ""
echo -e "${BOLD}Proof file:${NC} $PROOF_FILE"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
fi
