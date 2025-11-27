#!/bin/bash
# Generate real Claude Code transcripts for App Store review
# Uses actual Claude CLI to create valid JSONL files with safe content

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/sample-transcripts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper function: send message and get session ID
# Usage: session_id=$(send_first_message "/path/to/project" "message")
send_first_message() {
  local project_dir="$1"
  local message="$2"
  cd "$project_dir"

  # Get session ID from JSON output
  local response=$(claude -p --output-format json --dangerously-skip-permissions "$message" 2>/dev/null)
  local session_id=$(echo "$response" | jq -r '.session_id // empty' 2>/dev/null)

  if [ -z "$session_id" ]; then
    # Fallback: try to get from recent session
    session_id=$(claude --resume --output-format json -p "continue" 2>/dev/null | jq -r '.session_id // empty')
  fi

  echo "$session_id"
}

# Helper function: continue conversation with session ID
# Usage: send_followup "session_id" "message"
send_followup() {
  local session_id="$1"
  local message="$2"

  if [ -n "$session_id" ]; then
    claude --resume "$session_id" -p --dangerously-skip-permissions "$message" >/dev/null 2>&1
  else
    # Fallback to --continue if no session ID
    claude -p --continue --dangerously-skip-permissions "$message" >/dev/null 2>&1
  fi
}

echo "=== Generating Sample Transcripts for App Store Review ==="
echo ""

# Create project directories in user's home (more realistic than /tmp)
SAMPLE_PROJECTS="$HOME/code/sample-projects"
mkdir -p "$SAMPLE_PROJECTS/taskflow" "$SAMPLE_PROJECTS/weatherly" "$SAMPLE_PROJECTS/recipebox"
echo "Created sample projects in: $SAMPLE_PROJECTS"
echo ""

#######################################
# PROJECT 1: TaskFlow - CLI Task Manager
#######################################

echo -e "${GREEN}[1/3] Generating TaskFlow transcripts...${NC}"

cd $SAMPLE_PROJECTS/taskflow
git init -q 2>/dev/null || true

# Session 1: Project Setup
echo "  Session 1: Project Setup"
echo -e "    ${CYAN}Turn 1/6${NC}"
SESSION1=$(send_first_message "$SAMPLE_PROJECTS/taskflow" \
  "I want to create a simple CLI task manager in Python called TaskFlow. It should let me add, list, and complete tasks. Can you help me set up the basic project structure? Just describe what you would create - don't actually create files.")

sleep 2
echo -e "    ${CYAN}Turn 2/6${NC}"
send_followup "$SESSION1" \
  "Great! Can you describe what the Task model would look like? I want each task to have a title, description, and created date."

sleep 2
echo -e "    ${CYAN}Turn 3/6${NC}"
send_followup "$SESSION1" \
  "Now describe the storage layer to save tasks to a JSON file."

sleep 2
echo -e "    ${CYAN}Turn 4/6${NC}"
send_followup "$SESSION1" \
  "Perfect. Now describe the CLI commands: add, list, and done."

sleep 2
echo -e "    ${CYAN}Turn 5/6${NC}"
send_followup "$SESSION1" \
  "I tested it and the list command works but add isn't saving. What might be wrong?"

sleep 2
echo -e "    ${CYAN}Turn 6/6${NC}"
send_followup "$SESSION1" \
  "That fixed it! Thanks for the help with the initial setup."

echo "  Session 1 complete (ID: ${SESSION1:-unknown})"

# Session 2: Adding Priority Feature (new session)
echo "  Session 2: Priority Feature"
sleep 3

echo -e "    ${CYAN}Turn 1/6${NC}"
SESSION2=$(send_first_message "$SAMPLE_PROJECTS/taskflow" \
  "I want to add priority levels to TaskFlow tasks. Let's use High, Medium, Low. How would you approach this?")

sleep 2
echo -e "    ${CYAN}Turn 2/6${NC}"
send_followup "$SESSION2" \
  "Can we show priorities in the list view with colors? High=red, Medium=yellow, Low=green"

sleep 2
echo -e "    ${CYAN}Turn 3/6${NC}"
send_followup "$SESSION2" \
  "The colors don't show up in my terminal. I'm seeing weird escape codes instead."

sleep 2
echo -e "    ${CYAN}Turn 4/6${NC}"
send_followup "$SESSION2" \
  "That worked! Can we also sort by priority when listing?"

sleep 2
echo -e "    ${CYAN}Turn 5/6${NC}"
send_followup "$SESSION2" \
  "One more thing - I want to filter the list to show only high priority incomplete tasks."

sleep 2
echo -e "    ${CYAN}Turn 6/6${NC}"
send_followup "$SESSION2" \
  "This is really coming together. The priority feature is complete. Thanks!"

echo "  Session 2 complete (ID: ${SESSION2:-unknown})"

#######################################
# PROJECT 2: Weatherly - Weather Dashboard
#######################################

echo -e "${GREEN}[2/3] Generating Weatherly transcripts...${NC}"

cd $SAMPLE_PROJECTS/weatherly
git init -q 2>/dev/null || true

# Session 1: API Integration
echo "  Session 1: API Integration"
sleep 3

echo -e "    ${CYAN}Turn 1/7${NC}"
SESSION3=$(send_first_message "$SAMPLE_PROJECTS/weatherly" \
  "Let's build a weather dashboard called Weatherly. I want to display current weather for a city using a public weather API. How would you structure this Python project?")

sleep 2
echo -e "    ${CYAN}Turn 2/7${NC}"
send_followup "$SESSION3" \
  "How should I configure the API key securely so it doesn't get committed to git?"

sleep 2
echo -e "    ${CYAN}Turn 3/7${NC}"
send_followup "$SESSION3" \
  "Good security practice. Now describe how you'd fetch the current weather for a city."

sleep 2
echo -e "    ${CYAN}Turn 4/7${NC}"
send_followup "$SESSION3" \
  "Can you describe a nice terminal display with the weather info using Unicode symbols?"

sleep 2
echo -e "    ${CYAN}Turn 5/7${NC}"
send_followup "$SESSION3" \
  "Love it! But the temperature would be in Kelvin. How do we show Fahrenheit?"

sleep 2
echo -e "    ${CYAN}Turn 6/7${NC}"
send_followup "$SESSION3" \
  "The API sometimes fails with timeout errors. How would you add retry logic?"

sleep 2
echo -e "    ${CYAN}Turn 7/7${NC}"
send_followup "$SESSION3" \
  "Excellent. The dashboard design is solid. Thanks for the help!"

echo "  Session 1 complete (ID: ${SESSION3:-unknown})"

#######################################
# PROJECT 3: RecipeBox - Recipe Manager
#######################################

echo -e "${GREEN}[3/3] Generating RecipeBox transcripts...${NC}"

cd $SAMPLE_PROJECTS/recipebox
git init -q 2>/dev/null || true

# Session 1: Recipe Search Feature
echo "  Session 1: Search Feature"
sleep 3

echo -e "    ${CYAN}Turn 1/7${NC}"
SESSION4=$(send_first_message "$SAMPLE_PROJECTS/recipebox" \
  "I'm building RecipeBox, a recipe manager. I want to implement search that finds recipes by ingredient. For example, searching 'chicken' should find all recipes containing chicken. How would you design this?")

sleep 2
echo -e "    ${CYAN}Turn 2/7${NC}"
send_followup "$SESSION4" \
  "The search should be case-insensitive and support partial matches. How would you implement that?"

sleep 2
echo -e "    ${CYAN}Turn 3/7${NC}"
send_followup "$SESSION4" \
  "Can we also search by recipe name, not just ingredients?"

sleep 2
echo -e "    ${CYAN}Turn 4/7${NC}"
send_followup "$SESSION4" \
  "What if I want to search for multiple ingredients? Like recipes with both chicken AND garlic?"

sleep 2
echo -e "    ${CYAN}Turn 5/7${NC}"
send_followup "$SESSION4" \
  "Can we add an OR option too? Sometimes I want chicken OR beef."

sleep 2
echo -e "    ${CYAN}Turn 6/7${NC}"
send_followup "$SESSION4" \
  "The search is slow with many recipes. How would you optimize it for better performance?"

sleep 2
echo -e "    ${CYAN}Turn 7/7${NC}"
send_followup "$SESSION4" \
  "FTS5 sounds perfect. This search feature is exactly what I needed. Thanks!"

echo "  Session 1 complete (ID: ${SESSION4:-unknown})"

#######################################
# CODEX CLI SESSIONS (if codex is available)
#######################################

# Helper function: send first Codex message and capture session ID
# Usage: session_id=$(codex_first_message "/path/to/project" "message")
codex_first_message() {
  local project_dir="$1"
  local message="$2"

  # Run codex exec and capture output
  local output=$(codex exec -C "$project_dir" --dangerously-bypass-approvals-and-sandbox "$message" 2>&1)

  # Extract session ID from "codex resume <id>" line
  local session_id=$(echo "$output" | grep -o 'codex resume [a-f0-9-]*' | awk '{print $3}')

  echo "$session_id"
}

# Helper function: continue Codex conversation
# Usage: codex_followup "session_id" "message"
codex_followup() {
  local session_id="$1"
  local message="$2"

  if [ -n "$session_id" ]; then
    codex exec resume "$session_id" --dangerously-bypass-approvals-and-sandbox "$message" >/dev/null 2>&1
  fi
}

if command -v codex &> /dev/null; then
  echo ""
  echo -e "${GREEN}[4/4] Generating Codex CLI transcripts...${NC}"

  # TaskFlow - Codex session (export feature)
  echo "  TaskFlow: Export Feature"
  echo -e "    ${CYAN}Turn 1/4${NC}"
  CODEX_TF=$(codex_first_message "$SAMPLE_PROJECTS/taskflow" \
    "Can we add an export feature to TaskFlow? I want to export tasks to CSV. Just describe the approach, don't create files.")

  sleep 2
  echo -e "    ${CYAN}Turn 2/4${NC}"
  codex_followup "$CODEX_TF" \
    "Can we also support JSON export for backup purposes?"

  sleep 2
  echo -e "    ${CYAN}Turn 3/4${NC}"
  codex_followup "$CODEX_TF" \
    "What about importing from those formats?"

  sleep 2
  echo -e "    ${CYAN}Turn 4/4${NC}"
  codex_followup "$CODEX_TF" \
    "Perfect! Now I can backup and restore my tasks. Thanks!"

  echo "  TaskFlow Codex session complete (ID: ${CODEX_TF:-unknown})"

  # Weatherly - Codex session (alerts feature)
  echo "  Weatherly: Alerts Feature"
  sleep 3

  echo -e "    ${CYAN}Turn 1/4${NC}"
  CODEX_WL=$(codex_first_message "$SAMPLE_PROJECTS/weatherly" \
    "I want Weatherly to alert me when severe weather is coming. How would you design this feature?")

  sleep 2
  echo -e "    ${CYAN}Turn 2/4${NC}"
  codex_followup "$CODEX_WL" \
    "Can we get desktop notifications for high-priority alerts?"

  sleep 2
  echo -e "    ${CYAN}Turn 3/4${NC}"
  codex_followup "$CODEX_WL" \
    "How would I run this as a background service on macOS?"

  sleep 2
  echo -e "    ${CYAN}Turn 4/4${NC}"
  codex_followup "$CODEX_WL" \
    "This is exactly what I needed for storm season. Thanks!"

  echo "  Weatherly Codex session complete (ID: ${CODEX_WL:-unknown})"

  # RecipeBox - Codex session (pantry feature)
  echo "  RecipeBox: Pantry Feature"
  sleep 3

  echo -e "    ${CYAN}Turn 1/4${NC}"
  CODEX_RB=$(codex_first_message "$SAMPLE_PROJECTS/recipebox" \
    "I want to add a pantry feature to RecipeBox that tracks what ingredients I have and suggests recipes I can make. How would you design this?")

  sleep 2
  echo -e "    ${CYAN}Turn 2/4${NC}"
  codex_followup "$CODEX_RB" \
    "How would I add ingredients to my pantry?"

  sleep 2
  echo -e "    ${CYAN}Turn 3/4${NC}"
  codex_followup "$CODEX_RB" \
    "Can it also show recipes where I'm missing just one or two ingredients?"

  sleep 2
  echo -e "    ${CYAN}Turn 4/4${NC}"
  codex_followup "$CODEX_RB" \
    "This is brilliant. I'll actually use this. Thanks!"

  echo "  RecipeBox Codex session complete (ID: ${CODEX_RB:-unknown})"

else
  echo ""
  echo -e "${YELLOW}Codex CLI not found - skipping Codex transcripts${NC}"
fi

#######################################
# Copy transcripts to sample directory
#######################################

echo ""
echo -e "${YELLOW}Copying transcripts to sample directory...${NC}"

# Claude Code transcripts
CLAUDE_PROJECTS="$HOME/.claude/projects"
mkdir -p "$SAMPLE_DIR/claude/projects"

# Copy Claude Code project transcripts
# Path pattern: -Users-<username>-code-sample-projects-<project>
for project in taskflow weatherly recipebox; do
  # Build the expected path pattern from SAMPLE_PROJECTS
  # e.g., ~/code/sample-projects/taskflow -> -Users-rob-code-sample-projects-taskflow
  encoded_path=$(echo "$SAMPLE_PROJECTS/$project" | sed 's|^/||; s|/|-|g; s|^|-|')
  src_dir="$CLAUDE_PROJECTS/$encoded_path"
  if [ -d "$src_dir" ]; then
    cp -r "$src_dir" "$SAMPLE_DIR/claude/projects/$encoded_path"
    count=$(find "$src_dir" -name "*.jsonl" | wc -l | tr -d ' ')
    echo "  Copied $project Claude transcripts ($count sessions)"
  fi
done

# Codex transcripts (stored by date)
CODEX_SESSIONS="$HOME/.codex/sessions"
mkdir -p "$SAMPLE_DIR/codex/sessions"

# Find and copy Codex sessions for our projects
# Codex stores in YYYY/MM/DD structure, we need to find sessions with cwd=$SAMPLE_PROJECTS/taskflow etc.
if [ -d "$CODEX_SESSIONS" ]; then
  # Find recent session files and check their cwd
  find "$CODEX_SESSIONS" -name "*.jsonl" -mmin -60 2>/dev/null | while read -r session_file; do
    # Check if this session is for one of our projects
    if grep -q "sample-projects/taskflow\|sample-projects/weatherly\|sample-projects/recipebox" "$session_file" 2>/dev/null; then
      # Preserve directory structure
      rel_path="${session_file#$CODEX_SESSIONS/}"
      target_dir="$SAMPLE_DIR/codex/sessions/$(dirname "$rel_path")"
      mkdir -p "$target_dir"
      cp "$session_file" "$target_dir/"
      echo "  Copied Codex session: $(basename "$session_file")"
    fi
  done
fi

#######################################
# Summary
#######################################

echo ""
echo "=== Transcript Generation Complete ==="
echo ""
echo "Generated transcripts:"
echo ""
echo "Claude Code:"
find "$SAMPLE_DIR/claude" -name "*.jsonl" 2>/dev/null | while read -r f; do
  echo "  $(basename "$(dirname "$f")")/$(basename "$f")"
done
echo ""
echo "Codex CLI:"
find "$SAMPLE_DIR/codex" -name "*.jsonl" 2>/dev/null | while read -r f; do
  echo "  $(basename "$f")"
done
echo ""
echo "Next steps:"
echo "  1. Review transcripts in $SAMPLE_DIR"
echo "  2. Test with Contextify (clean DB)"
echo "  3. Package as sample-data.zip"
echo "  4. Upload to contextify.sh/review/"
