#!/usr/bin/env bash
# run-skill-query.sh - Execute a single gold query via headless Claude Code
#
# Loads the actual Total Recall SKILL.md so the benchmark tests real skill behavior.
# Uses stream-json output to capture tool calls for behavioral verification.
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
SKILL_HASH=$(shasum -a 256 "$SKILL_PATH" | cut -c1-8)

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
STREAM_OUTPUT=$(mktemp /tmp/skill-runner-stream-XXXXXX)
trap "rm -f '$STDERR_LOG' '$STREAM_OUTPUT'" EXIT

PROMPT="You are a benchmark evaluator. A user is asking you a question about their past AI conversations. Use the Total Recall skill below to search and answer.

IMPORTANT: Always pass --db-path $DB_PATH to every contextify command. This overrides the default database location.

The skill hash for this session is: $SKILL_HASH
You MUST include this exact hash in your output header as: skill:$SKILL_HASH
Do NOT attempt to compute the hash yourself. Use the value provided above.

--- BEGIN SKILL ---
$SKILL_CONTENT
--- END SKILL ---

Now answer this user question by following the skill instructions above:

$QUESTION"

# Run claude -p with stream-json to capture tool calls
"$TIMEOUT_BIN" "$TIMEOUT" claude -p "$PROMPT" \
  --output-format stream-json \
  --verbose \
  --model sonnet \
  --no-session-persistence \
  --permission-mode bypassPermissions \
  --allowedTools "Bash(contextify*)" --allowedTools "Bash(shasum*)" \
  2>"${STDERR_LOG}" > "${STREAM_OUTPUT}" || {
    EXIT_CODE=$?
    echo "ERROR: claude -p exited with code $EXIT_CODE" >&2
    if [ -s "$STDERR_LOG" ]; then
      echo "stderr:" >&2
      head -20 "$STDERR_LOG" >&2
    fi
    exit 1
}

# Parse the stream-json output: extract result, tool calls, and behavioral signals
python3 -c "
import sys, json

stream_path = '${STREAM_OUTPUT}'
lines = open(stream_path).readlines()

result_text = ''
num_turns = 0
duration_ms = 0
cost_usd = 0
tool_commands = []

for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue

    etype = event.get('type', '')

    # Extract tool_use events (bash commands the agent ran)
    if etype == 'assistant':
        msg = event.get('message', {})
        for block in msg.get('content', []):
            if block.get('type') == 'tool_use' and block.get('name') == 'Bash':
                cmd = block.get('input', {}).get('command', '')
                if cmd:
                    tool_commands.append(cmd)

    # Extract final result
    elif etype == 'result':
        result_text = event.get('result', '')
        num_turns = event.get('num_turns', 0)
        duration_ms = event.get('duration_ms', 0)
        cost_usd = event.get('total_cost_usd', 0)

if not result_text:
    print('ERROR: no result in stream output', file=sys.stderr)
    sys.exit(1)

# Behavioral signals from tool calls
behavioral = {
    'used_days_365': any('--days 365' in cmd or '--days=365' in cmd for cmd in tool_commands),
    'used_snippet_tokens_100': any('--snippet-tokens 100' in cmd for cmd in tool_commands),
    'used_db_path': any('--db-path' in cmd for cmd in tool_commands),
    'contextify_commands': [cmd for cmd in tool_commands if 'contextify' in cmd],
}

print(json.dumps({
    'response': result_text,
    'turns': num_turns,
    'cost_usd': cost_usd,
    'duration_s': duration_ms / 1000,
    'tool_commands': tool_commands,
    'behavioral': behavioral,
}))
"
