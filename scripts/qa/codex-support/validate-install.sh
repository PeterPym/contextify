#!/bin/bash
# scripts/qa/codex-support/validate-install.sh
#
# Automated validation for Total Recall Codex support.
# Outputs report to /tmp/total-recall-codex-validation-<timestamp>.md

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="/tmp/total-recall-codex-validation-${TIMESTAMP}.md"

cat > "$REPORT" << REPORT
# Total Recall Codex Support Validation Report

**Generated:** $(date -Iseconds)
**Validator:** automated

---

## Pre-Flight Checks

REPORT

echo "=== Running validation suite ==="
echo "Report: $REPORT"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() {
  echo "PASS: $1"
  echo "- [x] $1" >> "$REPORT"
  ((TESTS_PASSED++))
}

fail() {
  echo "FAIL: $1"
  echo "- [ ] **FAIL:** $1" >> "$REPORT"
  ((TESTS_FAILED++))
}

skip() {
  echo "SKIP: $1"
  echo "- [ ] **SKIP:** $1" >> "$REPORT"
  ((TESTS_SKIPPED++))
}

# === PRE-FLIGHT CHECKS ===

if command -v contextify-query &> /dev/null; then
  VERSION=$(contextify-query --version 2>&1 || echo "unknown")
  pass "contextify-query found: $VERSION"
else
  fail "contextify-query not found in PATH"
  echo "Aborting validation" >> "$REPORT"
  exit 1
fi

if contextify-query status --json 2>/dev/null | grep -q '"projectCount"'; then
  pass "Contextify database accessible"
else
  fail "Contextify database not found"
fi

echo "" >> "$REPORT"
echo "## Installation Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === CLEAR STATE ===
rm -rf ~/.claude/skills/total-recall 2>/dev/null || true
rm -rf ~/.codex/skills/total-recall 2>/dev/null || true

# === TEST: Fresh Install ===
if contextify-query install-plugin 2>&1 | grep -qi "installed"; then
  pass "install-plugin completed successfully"
else
  fail "install-plugin failed"
fi

# === TEST: Claude skill exists ===
if [ -f ~/.claude/skills/total-recall/SKILL.md ]; then
  pass "Claude skill installed at ~/.claude/skills/total-recall/SKILL.md"
else
  fail "Claude skill NOT found at ~/.claude/skills/total-recall/SKILL.md"
fi

# === TEST: Codex skill exists ===
if [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  pass "Codex skill installed at ~/.codex/skills/total-recall/SKILL.md"
else
  fail "Codex skill NOT found at ~/.codex/skills/total-recall/SKILL.md"
fi

# === TEST: Not symlinked (Codex requirement) ===
if [ -L ~/.codex/skills/total-recall/SKILL.md ]; then
  fail "Codex skill is a symlink (Codex ignores symlinks)"
else
  pass "Codex skill is a real file (not symlink)"
fi

# === TEST: Content matches ===
if diff -q ~/.claude/skills/total-recall/SKILL.md ~/.codex/skills/total-recall/SKILL.md > /dev/null 2>&1; then
  pass "Skill content identical in both locations"
else
  fail "Skill content differs between Claude and Codex"
fi

echo "" >> "$REPORT"
echo "## CLI Integration Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === TEST: Claude skill discovery ===
CLAUDE_SKILLS=$(claude -p --dangerously-skip-permissions "/skills" 2>/dev/null || echo "CLAUDE_NOT_AVAILABLE")
if [ "$CLAUDE_SKILLS" = "CLAUDE_NOT_AVAILABLE" ]; then
  skip "Claude Code not available for skill discovery"
elif echo "$CLAUDE_SKILLS" | grep -qi "total-recall"; then
  pass "Claude Code discovered total-recall skill"
else
  fail "Claude Code did not list total-recall skill"
fi

# === TEST: Codex skill discovery ===
CODEX_SKILLS=$(codex exec --enable-skills --dangerously-bypass-approvals-and-sandbox "/skills" 2>/dev/null || echo "CODEX_NOT_AVAILABLE")
if [ "$CODEX_SKILLS" = "CODEX_NOT_AVAILABLE" ]; then
  skip "Codex CLI not available for skill discovery"
elif echo "$CODEX_SKILLS" | grep -qi "total-recall"; then
  pass "Codex CLI discovered total-recall skill"
else
  fail "Codex CLI did not list total-recall skill"
fi

# === TEST: Codex delegation gracefully ignored ===
CODEX_DELEG=$(codex exec --enable-skills --dangerously-bypass-approvals-and-sandbox \
  "Use the contextify-researcher agent to search for 'test'. Report what happened." 2>/dev/null || echo "CODEX_NOT_AVAILABLE")

if [ "$CODEX_DELEG" = "CODEX_NOT_AVAILABLE" ]; then
  skip "Codex CLI not available for delegation check"
elif echo "$CODEX_DELEG" | grep -qiE "(error|failed|not found|cannot spawn)"; then
  fail "Codex showed error when delegation requested"
elif echo "$CODEX_DELEG" | grep -qiE "(Contextify|results|no results|search)"; then
  pass "Codex handled delegation request gracefully"
else
  fail "Unexpected response to delegation request"
fi

echo "" >> "$REPORT"
echo "## Uninstall Tests" >> "$REPORT"
echo "" >> "$REPORT"

if contextify-query uninstall-plugin 2>&1 | grep -qi "Uninstalled"; then
  pass "uninstall-plugin completed successfully"
else
  fail "uninstall-plugin failed"
fi

if [ -e ~/.claude/skills/total-recall ]; then
  fail "Claude skill directory still present after uninstall"
else
  pass "Claude skill directory removed after uninstall"
fi

if [ -e ~/.codex/skills/total-recall ]; then
  fail "Codex skill directory still present after uninstall"
else
  pass "Codex skill directory removed after uninstall"
fi

cat >> "$REPORT" << SUMMARY

---

## Summary

- Passed: $TESTS_PASSED
- Failed: $TESTS_FAILED
- Skipped: $TESTS_SKIPPED

SUMMARY

if [ $TESTS_FAILED -gt 0 ]; then
  echo "Validation failed ($TESTS_FAILED failures)."
  exit 1
fi

echo "Validation succeeded."
