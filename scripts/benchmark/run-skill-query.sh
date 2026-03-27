#!/usr/bin/env bash
# run-skill-query.sh - Execute a single gold query via headless Claude Code
#
# Usage: run-skill-query.sh <natural_question> <db_path> [timeout_seconds]
#
# Outputs structured JSON to stdout on success (exit 0).
# Exits non-zero on infra failure (timeout, auth, malformed output).

set -euo pipefail

QUESTION="$1"
DB_PATH="$2"
TIMEOUT="${3:-120}"

# Probe for timeout command (macOS may need gtimeout from coreutils)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "ERROR: neither timeout nor gtimeout found in PATH" >&2
  exit 1
fi

PROMPT="You are a benchmark evaluator. You MUST search conversation history using the contextify CLI. Do NOT answer from memory or training data.

Step 1: Construct a search query and run:
contextify search \"<your query>\" --db-path $DB_PATH --json --limit 20

Step 2: For promising results, drill into the full conversation:
contextify context <transcriptId> --db-path $DB_PATH --json --limit 10

Step 3: Report what you found. Include specific details, names, numbers, and quotes from the conversation history.

Question: $QUESTION"

# Run claude -p and capture output. Non-zero exit = infra failure.
RAW_OUTPUT=$("$TIMEOUT_BIN" "$TIMEOUT" claude -p "$PROMPT" \
  --output-format json \
  --model sonnet \
  --no-session-persistence \
  --permission-mode bypassPermissions \
  --allowedTools "Bash(contextify*)" \
  2>/dev/null) || {
    EXIT_CODE=$?
    echo "ERROR: claude -p exited with code $EXIT_CODE" >&2
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
