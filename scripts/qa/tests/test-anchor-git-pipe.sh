#!/usr/bin/env bash
# Regression test: --anchor-git must not hang due to pipe buffer exhaustion.
# Covers the fix in runProcess() where stdout and stderr pipes could deadlock
# when subprocess output exceeds the ~64KB macOS pipe buffer.
#
# Requires: contextify CLI in PATH, benchmark snapshot available.
# Run: bash scripts/qa/tests/test-anchor-git-pipe.sh

set -euo pipefail
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== anchor-git pipe deadlock regression ==="

# Locate benchmark snapshot
MANIFEST="$(cd "$(dirname "$0")/../../benchmark" && pwd)/snapshot-manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "SKIP: benchmark snapshot manifest not found at $MANIFEST"
  exit 0
fi
DB_PATH=$(python3 -c "
import json, os
with open('$MANIFEST') as f:
    m = json.load(f)
if 'path_relative_to_home' in m:
    print(os.path.join(os.path.expanduser('~'), m['path_relative_to_home']))
else:
    print(os.path.expanduser(m['path']))
")
if [[ ! -f "$DB_PATH" ]]; then
  echo "SKIP: benchmark snapshot not found at $DB_PATH"
  exit 0
fi

# Test 1: anchor-git search completes within 15s (would hang before fix)
echo ""
echo "Test 1: --anchor-git search completes without hanging"
if timeout 15 contextify search "DatabaseSchema.swift migration" \
    --db-path "$DB_PATH" --json --limit 3 --anchor-git >/dev/null 2>&1; then
  ok "anchor-git search completed within 15s"
else
  fail "anchor-git search timed out or failed (pipe deadlock?)"
fi

# Test 2: query with many symbol cues (triggers cue extraction + git ls-files)
echo ""
echo "Test 2: query with symbol cues completes without hanging"
if timeout 15 contextify search "forceStateless hallucination retry FTSQueryBuilder" \
    --db-path "$DB_PATH" --json --limit 3 --anchor-git >/dev/null 2>&1; then
  ok "symbol-cue query completed within 15s"
else
  fail "symbol-cue query timed out or failed"
fi

# Test 3: verify git ls-files output exceeds pipe buffer (precondition for deadlock)
echo ""
echo "Test 3: verify repo has enough tracked files to fill pipe buffer"
LS_SIZE=$(git ls-files | wc -c | tr -d ' ')
if [[ "$LS_SIZE" -gt 65536 ]]; then
  ok "git ls-files output is ${LS_SIZE} bytes (>64KB, would have deadlocked)"
else
  echo "  ~ git ls-files output is ${LS_SIZE} bytes (<64KB, deadlock not testable in this repo)"
fi

# Test 4: non-zero exit from git doesn't hang (stderr-only scenario)
echo ""
echo "Test 4: anchor-git with bad db path returns error promptly"
if timeout 10 contextify search "test" \
    --db-path /nonexistent/path.db --json --limit 1 --anchor-git >/dev/null 2>&1; then
  fail "should have returned non-zero for missing db"
else
  EXIT_CODE=$?
  if [[ "$EXIT_CODE" -eq 124 ]]; then
    fail "timed out (hung on error path)"
  else
    ok "returned error promptly (exit $EXIT_CODE)"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
