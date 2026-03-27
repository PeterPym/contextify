#!/usr/bin/env bash
# run-skill-query.sh - Execute a single gold query via headless Claude Code
#
# Loads the actual Total Recall SKILL.md so the benchmark tests real skill behavior.
#
# Usage: run-skill-query.sh <natural_question> <db_path> [timeout_seconds]
#
# Outputs structured JSON to stdout on success (exit 0).
# Exits non-zero on infra failure (timeout, auth, malformed output).

set -euo pipefail

QUESTION="$1"
DB_PATH="$2"
TIMEOUT="${3:-120}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load the actual SKILL.md - this is the whole point of the skill benchmark
SKILL_PATH="${REPO_ROOT}/contextify-query/user-skill/total-recall/SKILL.md"
if [[ ! -f "$SKILL_PATH" ]]; then
  echo "ERROR: SKILL.md not found at $SKILL_PATH" >&2
  exit 1
fi
SKILL_CONTENT=$(cat "$SKILL_PATH")

# Probe for timeout command (macOS may need gtimeout from coreutils)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "ERROR: neither timeout nor gtimeout found in PATH" >&2
  exit 1
fi

STDERR_LOG=$(mktemp /tmp/skill-runner-stderr-XXXXXX)
trap "rm -f '$STDERR_LOG'" EXIT

PROMPT="You are a benchmark evaluator. A user is asking you a question about their past AI conversations. Use the Total Recall skill below to search and answer.

IMPORTANT: Always pass --db-path $DB_PATH to every contextify command. This overrides the default database location.

--- BEGIN SKILL ---
$SKILL_CONTENT
--- END SKILL ---

Now answer this user question by following the skill instructions above:

$QUESTION"

# Run claude -p and capture output. Non-zero exit = infra failure.
RAW_OUTPUT=$("$TIMEOUT_BIN" "$TIMEOUT" claude -p "$PROMPT" \
  --output-format json \
  --model sonnet \
  --no-session-persistence \
  --permission-mode bypassPermissions \
  --allowedTools "Bash(contextify*)" \
  2>"${STDERR_LOG}") || {
    EXIT_CODE=$?
    echo "ERROR: claude -p exited with code $EXIT_CODE" >&2
    if [ -s "$STDERR_LOG" ]; then
      echo "stderr:" >&2
      head -20 "$STDERR_LOG" >&2
    fi
    exit 1
}

# Parse the claude JSON output into our standard format
echo "$RAW_OUTPUT" | python3 -c "
import sys, json

raw = sys.stdin.read()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    print('ERROR: claude returned invalid JSON', file=sys.stderr)
    sys.exit(1)

result = d.get('result', '')
if not result:
    print('ERROR: claude returned empty result', file=sys.stderr)
    sys.exit(1)

turns = d.get('num_turns', 0)
cost = d.get('costUSD', 0)
duration = d.get('duration_ms', 0) / 1000

print(json.dumps({
    'response': result,
    'turns': turns,
    'cost_usd': cost,
    'duration_s': duration
}))
"
