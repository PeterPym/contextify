#!/usr/bin/env bash
# run-skill-query.sh - Execute a single gold query via headless Claude Code
#
# Usage: run-skill-query.sh <natural_question> <db_path> [timeout_seconds]
#
# Outputs structured JSON to stdout. Exit 0 on success, 1 on timeout/error.

set -euo pipefail

QUESTION="$1"
DB_PATH="$2"
TIMEOUT="${3:-120}"

PROMPT="You are a benchmark evaluator. You MUST search conversation history using the contextify CLI. Do NOT answer from memory or training data.

Step 1: Construct a search query and run:
contextify search \"<your query>\" --db-path $DB_PATH --json --limit 20

Step 2: For promising results, drill into the full conversation:
contextify context <transcriptId> --db-path $DB_PATH --json --limit 10

Step 3: Report what you found. Include specific details, names, numbers, and quotes from the conversation history.

Question: $QUESTION"

# Capture raw output and handle both JSON and error cases
RAW_OUTPUT=$(timeout "$TIMEOUT" claude -p "$PROMPT" \
  --output-format json \
  --model sonnet \
  --no-session-persistence \
  --permission-mode bypassPermissions \
  --allowedTools "Bash(contextify*)" \
  2>/dev/null) || {
    EXIT_CODE=$?
    # Timeout or other error - output a valid JSON error
    python3 -c "
import json
print(json.dumps({
    'response': '',
    'turns': 0,
    'cost_usd': 0,
    'duration_s': 0,
    'error': 'claude -p exited with code $EXIT_CODE'
}))
"
    exit 0  # exit 0 so evaluator processes the error JSON
}

# Parse the claude JSON output into our standard format
echo "$RAW_OUTPUT" | python3 -c "
import sys, json
try:
    raw = sys.stdin.read()
    d = json.loads(raw)
    result = d.get('result', '')
    turns = d.get('num_turns', 0)
    cost = d.get('costUSD', 0)
    duration = d.get('duration_ms', 0) / 1000
    print(json.dumps({
        'response': result,
        'turns': turns,
        'cost_usd': cost,
        'duration_s': duration
    }))
except (json.JSONDecodeError, KeyError) as e:
    # If claude returned plain text instead of JSON, use it as the response
    print(json.dumps({
        'response': raw.strip() if 'raw' in dir() else '',
        'turns': 0,
        'cost_usd': 0,
        'duration_s': 0,
        'error': str(e)
    }))
"
