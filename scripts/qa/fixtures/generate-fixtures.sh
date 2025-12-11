#!/bin/bash
# Generate real fixture transcripts using CLI tools
# Follows methodology from appstore-metadata/review-materials/generate-transcripts.sh
# Run once to populate fixtures for deterministic QA testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/transcripts"

echo "=== Generating QA Fixture Transcripts ==="
echo ""

# Check for required tools
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude CLI not found"
  exit 1
fi

if ! command -v codex &>/dev/null; then
  echo "ERROR: codex CLI not found"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found (needed to parse session IDs)"
  exit 1
fi

# Helper function: send first Claude message and get session ID
# Usage: session_id=$(claude_first_message "/path/to/project" "message")
claude_first_message() {
  local project_dir="$1"
  local message="$2"
  cd "$project_dir"

  local response
  response=$(claude -p --output-format json --dangerously-skip-permissions "$message" 2>/dev/null) || true
  local session_id
  session_id=$(echo "$response" | jq -r '.session_id // empty' 2>/dev/null) || true

  echo "$session_id"
}

# Helper function: continue Claude conversation with session ID
# Usage: claude_followup "session_id" "message"
claude_followup() {
  local session_id="$1"
  local message="$2"

  if [ -n "$session_id" ]; then
    claude --resume "$session_id" -p --dangerously-skip-permissions "$message" >/dev/null 2>&1 || true
  else
    claude -p --continue --dangerously-skip-permissions "$message" >/dev/null 2>&1 || true
  fi
}

# Helper function: send Codex message (single exec, multi-turn via prompt)
# Usage: codex_exec "/path/to/project" "message"
codex_exec() {
  local project_dir="$1"
  local message="$2"

  timeout 60 codex exec -C "$project_dir" --dangerously-bypass-approvals-and-sandbox "$message" >/dev/null 2>&1 || true
}

# Create test project directories
# Note: Use /private/tmp directly since macOS /tmp symlinks there
# and CLIs record the resolved path in transcripts
TEST_PROJECT_1="/private/tmp/contextify-qa-fixture-gen-1"
TEST_PROJECT_2="/private/tmp/contextify-qa-fixture-gen-2"
TEST_PROJECT_3="/private/tmp/contextify-qa-fixture-gen-3"

for proj in "$TEST_PROJECT_1" "$TEST_PROJECT_2" "$TEST_PROJECT_3"; do
  rm -rf "$proj"
  mkdir -p "$proj"
  cd "$proj"
  git init -q
  git config user.email "qa@contextify.test"
  git config user.name "QA Test"
  echo "# QA Test Project" > README.md
  git add README.md
  git commit -q -m "Initial commit"
done

echo "Created test projects"
echo ""

#######################################
# PROJECT 1: Both Claude + Codex
#######################################
echo "=== Project 1: Claude + Codex (multi-provider) ==="

# Claude transcript (multi-turn with session tracking)
echo "  Claude transcript (4 turns)..."
echo "    Turn 1/4"
SESSION1=$(claude_first_message "$TEST_PROJECT_1" \
  "QA_FIXTURE_SEARCH_TERM_CLAUDE - I want to create a simple calculator. What operations should it support?")
sleep 2

echo "    Turn 2/4"
claude_followup "$SESSION1" "How would you implement the addition function?"
sleep 2

echo "    Turn 3/4"
claude_followup "$SESSION1" "What about subtraction?"
sleep 2

echo "    Turn 4/4"
claude_followup "$SESSION1" "Thanks! This is enough for the QA fixture."
sleep 2

echo "  Claude session complete (ID: ${SESSION1:-unknown})"

# Codex transcript (multi-turn via single exec)
echo "  Codex transcript (multi-step)..."
codex_exec "$TEST_PROJECT_1" \
  "QA_FIXTURE_SEARCH_TERM_CODEX - Step 1: What is 10 + 5? Step 2: Multiply that by 2. Step 3: What is the square root? Just answer each step briefly."
sleep 2

echo "  Codex session complete"

#######################################
# PROJECT 2: Claude only
#######################################
echo ""
echo "=== Project 2: Claude only ==="

echo "  Claude transcript (4 turns)..."
echo "    Turn 1/4"
SESSION2=$(claude_first_message "$TEST_PROJECT_2" \
  "This is project 2 for QA testing. List three primary colors.")
sleep 2

echo "    Turn 2/4"
claude_followup "$SESSION2" "Now list three secondary colors."
sleep 2

echo "    Turn 3/4"
claude_followup "$SESSION2" "What color do you get mixing red and blue?"
sleep 2

echo "    Turn 4/4"
claude_followup "$SESSION2" "Great, that's all I needed for this QA fixture."
sleep 2

echo "  Claude session complete (ID: ${SESSION2:-unknown})"

#######################################
# PROJECT 3: Codex only
#######################################
echo ""
echo "=== Project 3: Codex only ==="

echo "  Codex transcript (multi-step)..."
codex_exec "$TEST_PROJECT_3" \
  "Project 3 QA test: Step 1: Name 3 planets. Step 2: Name 3 continents. Step 3: Name 3 oceans. Answer each step briefly."
sleep 2

echo "  Codex session complete"

#######################################
# Copy generated transcripts to fixtures
#######################################
echo ""
echo "=== Copying to fixtures ==="

# Copy Claude transcripts
mkdir -p "$FIXTURE_DIR/claude"
for proj_num in 1 2; do
  proj_var="TEST_PROJECT_$proj_num"
  proj_path="${!proj_var}"
  proj_hash=$(echo "$proj_path" | tr '/' '-')

  src_dir="$HOME/.claude/projects/$proj_hash"
  if [ -d "$src_dir" ]; then
    latest=$(ls -t "$src_dir"/*.jsonl 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      dest="$FIXTURE_DIR/claude/project${proj_num}.jsonl"
      cp "$latest" "$dest"
      lines=$(wc -l < "$dest" | tr -d ' ')
      echo "  Claude project $proj_num: $dest ($lines lines)"
    fi
  else
    echo "  WARN: No Claude transcripts found for project $proj_num"
  fi
done

# Copy Codex transcripts
mkdir -p "$FIXTURE_DIR/codex"
for proj_num in 1 3; do
  proj_var="TEST_PROJECT_$proj_num"
  proj_path="${!proj_var}"

  # Find transcript with matching cwd (search recent files)
  latest=""
  while IFS= read -r f; do
    if grep -q "\"cwd\":\"$proj_path\"" "$f" 2>/dev/null; then
      latest="$f"
      break
    fi
  done < <(find "$HOME/.codex/sessions" -name "*.jsonl" -mmin -10 2>/dev/null | sort -r)

  if [ -n "$latest" ]; then
    dest="$FIXTURE_DIR/codex/project${proj_num}.jsonl"
    cp "$latest" "$dest"
    lines=$(wc -l < "$dest" | tr -d ' ')
    echo "  Codex project $proj_num: $dest ($lines lines)"
  else
    echo "  WARN: No Codex transcripts found for project $proj_num"
  fi
done

#######################################
# Summary
#######################################
echo ""
echo "=== Done ==="
echo "Fixtures generated:"
find "$FIXTURE_DIR" -name "*.jsonl" -exec ls -la {} \;
echo ""
echo "Update backup_and_isolate_transcripts() to use these fixtures."
