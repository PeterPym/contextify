# Sample Transcript Plan for App Store Review

**Purpose:** Create synthetic transcripts for Apple's App Store review team to test Contextify's features.

**Requirements:**
- Multiple projects (demonstrates project switching)
- Multiple sessions per project (demonstrates timeline)
- Both Claude Code AND Codex CLI transcripts (demonstrates multi-provider support)
- Realistic developer conversations (demonstrates summarization)
- Searchable content (demonstrates search feature)
- Safe/innocuous content (nothing proprietary)
- QA-testable end-to-end workflow

---

## Repository Location

```
appstore-metadata/review-materials/
├── README.md                          # Setup instructions for Apple reviewers
├── sample-data.zip                    # Packaged for download
├── qa-test.sh                         # QA script to verify sample data works
└── sample-transcripts/
    ├── claude/
    │   └── projects/
    │       ├── -tmp-taskflow/         # Project 1: TaskFlow (Claude Code)
    │       │   ├── session-001.jsonl
    │       │   └── session-002.jsonl
    │       └── -tmp-weatherly/        # Project 2: Weatherly (Claude Code)
    │           └── session-001.jsonl
    └── codex/
        └── sessions/
            └── 2025/
                └── 11/
                    ├── 20/            # Project 1: TaskFlow (Codex)
                    │   └── rollout-2025-11-20T14-30-00-tf001.jsonl
                    ├── 21/            # Project 2: Weatherly (Codex)
                    │   └── rollout-2025-11-21T10-00-00-wl001.jsonl
                    └── 22/            # Project 3: RecipeBox (Codex only)
                        └── rollout-2025-11-22T09-00-00-rb001.jsonl
```

**Coverage Matrix:**

| Project | Claude Code | Codex CLI | Total Sessions |
|---------|-------------|-----------|----------------|
| TaskFlow | 2 sessions | 1 session | 3 |
| Weatherly | 1 session | 1 session | 2 |
| RecipeBox | - | 1 session | 1 |
| **Total** | **3** | **3** | **6** |

**Note:**
- Claude Code paths use `-tmp-` prefix (e.g., `/tmp/taskflow` → `-tmp-taskflow`)
- Codex uses date-based hierarchy with `cwd` in `session_meta` for project association

---

## Project 1: TaskFlow - CLI Task Manager

**Fictional Path:** `/tmp/taskflow`
**Encoded Path:** `-tmp-taskflow`
**Description:** A command-line task management tool written in Python

### Session 1: Project Setup (15 messages)
**Theme:** Initial project creation and basic structure
**Duration:** ~10 minutes of conversation

**Conversation Script:**

```
USER: I want to create a simple CLI task manager in Python called TaskFlow.
      It should let me add, list, and complete tasks. Can you help me set up the project structure?

ASSISTANT: I'll help you create TaskFlow. Let me set up a clean project structure with proper organization.
           [Creates directory structure, __init__.py, main.py, models.py]
           I've created the basic structure. The project has:
           - taskflow/main.py - Entry point with CLI commands
           - taskflow/models.py - Task data model
           - taskflow/storage.py - JSON file persistence

USER: Great! Can you implement the Task model first? I want each task to have a title,
      description, and created date.

ASSISTANT: [Implements Task dataclass with title, description, created_at, completed fields]
           I've created a Task dataclass with:
           - title (required)
           - description (optional)
           - created_at (auto-generated)
           - completed (boolean, default False)

USER: Now let's add the storage layer to save tasks to a JSON file.

ASSISTANT: [Implements TaskStorage class with save/load methods]
           The storage layer is ready. Tasks are persisted to ~/.taskflow/tasks.json

USER: Perfect. Now implement the CLI commands: add, list, and done.

ASSISTANT: [Implements CLI using argparse with add, list, done subcommands]
           CLI is complete! You can now:
           - taskflow add "Buy groceries" --desc "Milk, eggs, bread"
           - taskflow list
           - taskflow done 1

USER: Let me test it... the list command works but add isn't saving. Can you check?

ASSISTANT: [Debugs and finds missing save() call after adding task]
           Found the bug! The add command wasn't calling storage.save() after appending.
           Fixed now - tasks persist correctly.

USER: Works perfectly now. Thanks!
```

**Key Terms for Search:** "task", "CLI", "Python", "bug", "save", "storage"

---

### Session 2: Adding Priority Feature (20 messages)
**Theme:** Feature development and testing
**Duration:** ~15 minutes of conversation

**Conversation Script:**

```
USER: I want to add priority levels to tasks. Let's use High, Medium, Low.

ASSISTANT: I'll add a Priority enum and update the Task model.
           [Adds Priority enum, updates Task model, modifies CLI]
           Done! Tasks now support --priority flag (high/medium/low, default: medium)

USER: Can we show priorities in the list view with colors? High=red, Medium=yellow, Low=green

ASSISTANT: [Adds colorama dependency, implements colored output]
           Added color coding to the list output. High priority tasks show in red.

USER: The colors don't show up in my terminal. Getting some weird escape codes.

ASSISTANT: Ah, we need to initialize colorama for Windows compatibility.
           [Adds colorama.init() call]
           Fixed! The colors should display correctly now on all platforms.

USER: Works great! Can we also sort by priority when listing?

ASSISTANT: [Adds --sort flag with options: priority, date, name]
           Added sorting options. Use 'taskflow list --sort priority' to sort by priority.

USER: One more thing - I want to filter the list to show only high priority incomplete tasks.

ASSISTANT: [Adds --filter and --status flags to list command]
           You can now filter: 'taskflow list --filter high --status pending'

USER: This is really coming together. Let me test the full workflow...
      Everything works! The priority feature is complete.
```

**Key Terms for Search:** "priority", "feature", "color", "sort", "filter", "test"

---

### Session 3: Bug Fix Session (12 messages)
**Theme:** Debugging and fixing issues
**Duration:** ~8 minutes of conversation

**Conversation Script:**

```
USER: I found a bug - when I mark task 5 as done, it marks task 4 instead.
      The indexing seems off by one.

ASSISTANT: Let me investigate the done command implementation.
           [Reads done command code, finds off-by-one error]
           Found it! The done command uses 1-based indexing for user input but
           the internal list is 0-based. I wasn't subtracting 1 before accessing.

USER: Can you fix it and add a test to prevent regression?

ASSISTANT: [Fixes indexing, adds unit test for done command]
           Fixed the indexing and added a test case. The test verifies that
           'done 3' marks the third task (index 2) as completed.

USER: Run the tests to make sure everything passes.

ASSISTANT: [Runs pytest, all tests pass]
           All 8 tests pass. The bug is fixed and won't regress.

USER: Great work. Can you also add better error handling for invalid task numbers?

ASSISTANT: [Adds bounds checking and user-friendly error messages]
           Added validation. If you try 'done 99' on a list with 5 tasks,
           you'll get: "Error: Task 99 not found. You have 5 tasks (1-5)."

USER: Perfect. Bug squashed!
```

**Key Terms for Search:** "bug", "error", "fix", "test", "indexing", "regression"

---

## Project 2: Weatherly - Weather Dashboard

**Fictional Path:** `/tmp/weatherly`
**Encoded Path:** `-tmp-weatherly`
**Description:** A terminal-based weather dashboard using a public API

### Session 1: API Integration (18 messages)
**Theme:** Working with external APIs
**Duration:** ~12 minutes of conversation

**Conversation Script:**

```
USER: Let's build a weather dashboard called Weatherly. I want to display current
      weather for a city using the OpenWeatherMap API.

ASSISTANT: I'll set up a Python project that fetches weather data from OpenWeatherMap.
           [Creates project structure with config, api, display modules]
           Basic structure ready. You'll need an API key from openweathermap.org

USER: I have the API key. How do I configure it securely?

ASSISTANT: [Implements .env file support with python-dotenv]
           Create a .env file with OPENWEATHER_API_KEY=your_key
           The app loads it automatically and never commits secrets to git.

USER: Good security practice. Now let's fetch the current weather for a city.

ASSISTANT: [Implements WeatherAPI class with get_current() method]
           The API client is ready. It fetches temperature, humidity, conditions,
           and wind speed for any city.

USER: Can you add a nice terminal display with the weather info?

ASSISTANT: [Implements rich library display with weather icons using Unicode]
           Created a formatted display with:
           ☀️ Conditions, 🌡️ Temperature, 💧 Humidity, 💨 Wind Speed

USER: Love it! But the temperature is in Kelvin. Can we show Fahrenheit?

ASSISTANT: [Adds unit conversion and --units flag]
           Added temperature conversion. Use --units metric for Celsius or
           --units imperial for Fahrenheit (default).

USER: The API sometimes fails with timeout errors. Can we add retry logic?

ASSISTANT: [Implements retry with exponential backoff using tenacity]
           Added automatic retries with exponential backoff.
           Will retry 3 times before giving up.

USER: Excellent. The dashboard is working great!
```

**Key Terms for Search:** "API", "weather", "temperature", "error", "retry", "display"

---

### Session 2: Adding Forecast Feature (14 messages)
**Theme:** Extending functionality
**Duration:** ~10 minutes of conversation

**Conversation Script:**

```
USER: Can we add a 5-day forecast to Weatherly?

ASSISTANT: [Implements get_forecast() method using OpenWeatherMap forecast endpoint]
           Added forecast support. It shows daily high/low temps and conditions.

USER: How do we display 5 days of data in the terminal nicely?

ASSISTANT: [Creates tabular display using rich Tables]
           Created a table view:
           | Day       | High | Low  | Conditions |
           |-----------|------|------|------------|
           | Monday    | 72°F | 58°F | Sunny      |
           | Tuesday   | 68°F | 55°F | Cloudy     |

USER: Can we add a simple ASCII chart for temperature trends?

ASSISTANT: [Implements mini sparkline chart using Unicode block characters]
           Added a temperature trend chart: ▁▂▃▅▆▇▅▃▂▁
           Shows relative temps across the 5 days.

USER: This is really polished. One last thing - can we cache results to avoid
      hitting the API too often?

ASSISTANT: [Implements file-based cache with 30-minute TTL]
           Added caching. Results are stored in ~/.weatherly/cache/ with 30min TTL.
           Subsequent calls within 30 minutes use cached data.

USER: Perfect! Weatherly is feature-complete for now.
```

**Key Terms for Search:** "forecast", "cache", "display", "chart", "temperature"

---

## Project 3: RecipeBox - Recipe Manager

**Fictional Path:** `/tmp/recipebox`
**Encoded Path:** `-tmp-recipebox`
**Description:** A simple recipe storage and search application

### Session 1: Recipe Search Feature (16 messages)
**Theme:** Implementing search functionality
**Duration:** ~12 minutes of conversation

**Conversation Script:**

```
USER: I'm building RecipeBox, a recipe manager. I want to implement search
      that finds recipes by ingredient. For example, searching "chicken"
      should find all recipes containing chicken.

ASSISTANT: I'll implement an ingredient-based search. Let me first look at your
           Recipe model structure.
           [Reads existing Recipe model with name, ingredients list, instructions]
           Your Recipe model is well-structured. I'll add a search method.

USER: The search should be case-insensitive and support partial matches.

ASSISTANT: [Implements search with case-insensitive partial matching]
           Search is ready. "chick" will match "chicken", "Chicken", "CHICKEN".

USER: Can we also search by recipe name, not just ingredients?

ASSISTANT: [Extends search to check both name and ingredients]
           Updated! Search now checks recipe names and all ingredients.
           "pasta" finds "Pasta Carbonara" and any recipe using pasta.

USER: What if I want to search for multiple ingredients? Like recipes with
      both chicken AND garlic?

ASSISTANT: [Implements multi-term search with AND logic]
           Added multi-ingredient search. Use: recipebox search "chicken garlic"
           Returns only recipes containing ALL search terms.

USER: Can we add an OR option too? Sometimes I want chicken OR beef.

ASSISTANT: [Adds --any flag for OR logic]
           Added --any flag.
           - Default: recipebox search "chicken garlic" (must have both)
           - With flag: recipebox search "chicken beef" --any (either one)

USER: The search is slow with many recipes. Can we optimize it?

ASSISTANT: [Implements SQLite FTS5 full-text search for better performance]
           Migrated to SQLite with FTS5 full-text search.
           Search is now instant even with thousands of recipes.

USER: Wow, that's so much faster! Great improvement.

ASSISTANT: FTS5 is perfect for this use case. It also supports ranking results
           by relevance, so the best matches appear first.

USER: This search feature is exactly what I needed. Thanks!
```

**Key Terms for Search:** "search", "ingredient", "recipe", "chicken", "database", "performance"

---

## Technical Specifications

### JSONL Record Format

Each line in the JSONL file is a complete JSON object. Required fields:

**User Message:**
```json
{
  "type": "user",
  "uuid": "550e8400-e29b-41d4-a716-446655440001",
  "timestamp": "2025-11-20T10:15:30.000Z",
  "parentUuid": null,
  "sessionId": "abc123-def456-ghi789",
  "version": "1.0.22",
  "userType": "external",
  "cwd": "/tmp/taskflow",
  "gitBranch": "main",
  "isSidechain": false,
  "message": {
    "role": "user",
    "content": "I want to create a simple CLI task manager..."
  }
}
```

**Assistant Message:**
```json
{
  "type": "assistant",
  "uuid": "550e8400-e29b-41d4-a716-446655440002",
  "timestamp": "2025-11-20T10:15:45.000Z",
  "parentUuid": "550e8400-e29b-41d4-a716-446655440001",
  "sessionId": "abc123-def456-ghi789",
  "version": "1.0.22",
  "userType": "external",
  "cwd": "/tmp/taskflow",
  "gitBranch": "main",
  "isSidechain": false,
  "message": {
    "id": "msg_01234567890",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-5-20250929",
    "content": [
      {
        "type": "text",
        "text": "I'll help you create TaskFlow..."
      }
    ],
    "stop_reason": "end_turn",
    "stop_sequence": null,
    "usage": {
      "input_tokens": 150,
      "output_tokens": 200,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    }
  }
}
```

### Timestamp Guidelines

- Use ISO 8601 format: `2025-11-20T10:15:30.000Z`
- Sessions span 8-15 minutes of "real" conversation time
- Message gaps: 15-60 seconds between user/assistant pairs
- Different sessions on different dates (Nov 20, 21, 22, etc.)

### Session IDs

Each session needs a unique UUID:
- TaskFlow Session 1: `tf-session-001-aaaa-bbbb-cccc`
- TaskFlow Session 2: `tf-session-002-dddd-eeee-ffff`
- TaskFlow Session 3: `tf-session-003-gggg-hhhh-iiii`
- Weatherly Session 1: `wl-session-001-jjjj-kkkk-llll`
- Weatherly Session 2: `wl-session-002-mmmm-nnnn-oooo`
- RecipeBox Session 1: `rb-session-001-pppp-qqqq-rrrr`

---

## Content Guidelines for Apple Review

### DO Include:
- Generic programming tasks (CRUD, API calls, search)
- Common developer workflows (setup, feature dev, debugging)
- Standard libraries and tools (Python, CLI, JSON, SQLite)
- Professional technical language
- Error handling and testing discussions

### DO NOT Include:
- Any real company names or products
- Personal information or identifiers
- Controversial topics
- Complex business logic that might seem proprietary
- Any content that could be misinterpreted

### Searchable Terms (for testing search feature):
- Common: "error", "bug", "fix", "test", "feature"
- Project-specific: "task", "weather", "recipe", "search"
- Technical: "API", "database", "cache", "performance"

---

## Codex CLI Format Specification

Codex uses a different record structure than Claude Code.

### Session Meta (Required First Record)
```json
{
  "timestamp": "2025-11-20T14:30:00.000Z",
  "type": "session_meta",
  "payload": {
    "id": "019tf001-0000-0000-0000-000000000001",
    "timestamp": "2025-11-20T14:30:00.000Z",
    "cwd": "/tmp/taskflow",
    "originator": "codex_cli_rs",
    "cli_version": "0.48.0",
    "instructions": null,
    "source": "cli",
    "git": {
      "commit_hash": "abc123def456",
      "branch": "main",
      "repository_url": ""
    }
  }
}
```

### Response Item (User Message)
```json
{
  "timestamp": "2025-11-20T14:30:15.000Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user",
    "content": [
      {
        "type": "input_text",
        "text": "Let's continue working on TaskFlow..."
      }
    ]
  }
}
```

### Response Item (Assistant Message)
```json
{
  "timestamp": "2025-11-20T14:30:30.000Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "I'll help you with that..."
      }
    ]
  }
}
```

---

## Codex Session Scripts

### TaskFlow - Codex Session (Nov 20)
**File:** `codex/sessions/2025/11/20/rollout-2025-11-20T14-30-00-tf001.jsonl`
**Theme:** Adding export feature (continues from Claude Code sessions)

```
USER: Can we add an export feature to TaskFlow? I want to export tasks to CSV.

ASSISTANT: I'll add CSV export functionality. Let me create an export module.
           [Implements export.py with to_csv() method]
           You can now run: taskflow export --format csv --output tasks.csv

USER: Can we also support JSON export for backup purposes?

ASSISTANT: [Adds JSON export with pretty-printing]
           Added JSON export: taskflow export --format json --output backup.json
           The JSON format preserves all task metadata including timestamps.

USER: What about importing from those formats?

ASSISTANT: [Implements import functionality for both CSV and JSON]
           Import is ready:
           - taskflow import tasks.csv --format csv
           - taskflow import backup.json --format json

USER: Perfect! Now I can backup and restore my tasks.
```

### Weatherly - Codex Session (Nov 21)
**File:** `codex/sessions/2025/11/21/rollout-2025-11-21T10-00-00-wl001.jsonl`
**Theme:** Adding alerts feature

```
USER: I want Weatherly to alert me when severe weather is coming.

ASSISTANT: I'll implement weather alerts using OpenWeatherMap's alerts API.
           [Adds alerts module with severity levels]
           Alerts now show warnings for: storms, extreme temps, high winds.

USER: Can we get desktop notifications for high-priority alerts?

ASSISTANT: [Integrates with macOS notification center using pync]
           Desktop notifications enabled. Severe weather triggers a system alert.

USER: How do I run this as a background service?

ASSISTANT: [Creates launchd plist for background monitoring]
           Created a launchd service. Install with:
           cp weatherly.plist ~/Library/LaunchAgents/
           launchctl load ~/Library/LaunchAgents/weatherly.plist

USER: This is exactly what I needed for storm season. Thanks!
```

### RecipeBox - Codex Session (Nov 22)
**File:** `codex/sessions/2025/11/22/rollout-2025-11-22T09-00-00-rb001.jsonl`
**Theme:** Building the recipe manager from scratch (Codex only project)

```
USER: I want to build a recipe manager called RecipeBox. Store recipes locally
      with ingredients and instructions. Simple CLI interface.

ASSISTANT: I'll create RecipeBox with SQLite storage for flexibility.
           [Sets up project structure with models, database, CLI]
           Basic structure ready:
           - recipebox add "Pasta Carbonara"
           - recipebox list
           - recipebox show "Pasta Carbonara"

USER: How do I add ingredients to a recipe?

ASSISTANT: [Implements ingredient management]
           Use the interactive add flow:
           recipebox add "Chicken Stir Fry"
           > Enter ingredients (one per line, blank to finish):
           > chicken breast
           > soy sauce
           > vegetables
           >

USER: Can I search by ingredient? Like find all recipes with chicken?

ASSISTANT: [Implements ingredient search with FTS5]
           Search is ready: recipebox search --ingredient "chicken"
           Returns all recipes containing that ingredient.

USER: What if I want recipes I can make with what I have?

ASSISTANT: [Adds pantry matching feature]
           New feature:
           recipebox pantry add chicken rice vegetables
           recipebox suggest
           Shows recipes you can make with current pantry items!

USER: This is brilliant. I'll actually use this.
```

---

## QA Testing Workflow

### Prerequisites
- Clean Contextify database (or fresh install)
- Sample data downloaded and extracted

### qa-test.sh Script
```bash
#!/bin/bash
# QA Test Script for Sample Transcript Data
# Verifies the full workflow from download to app display

set -e

SAMPLE_URL="https://contextify.sh/review-4a125b1d/sample-data.zip"
CLAUDE_DIR="$HOME/.claude/projects"
CODEX_DIR="$HOME/.codex/sessions"
DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"

echo "=== Contextify Sample Data QA Test ==="
echo ""

# Step 1: Backup existing data
echo "Step 1: Backing up existing data..."
if [ -d "$CLAUDE_DIR" ]; then
    mv "$CLAUDE_DIR" "$CLAUDE_DIR.backup.$(date +%s)"
    echo "  Backed up existing Claude projects"
fi
if [ -d "$CODEX_DIR" ]; then
    mv "$CODEX_DIR" "$CODEX_DIR.backup.$(date +%s)"
    echo "  Backed up existing Codex sessions"
fi
if [ -f "$DB_PATH" ]; then
    mv "$DB_PATH" "$DB_PATH.backup.$(date +%s)"
    echo "  Backed up existing database"
fi

# Step 2: Download sample data
echo ""
echo "Step 2: Downloading sample data..."
TEMP_DIR=$(mktemp -d)
curl -L -o "$TEMP_DIR/sample-data.zip" "$SAMPLE_URL"
unzip -q "$TEMP_DIR/sample-data.zip" -d "$TEMP_DIR"

# Step 3: Install sample transcripts
echo ""
echo "Step 3: Installing sample transcripts..."
mkdir -p "$CLAUDE_DIR"
mkdir -p "$CODEX_DIR"
cp -r "$TEMP_DIR/sample-transcripts/claude/projects/"* "$CLAUDE_DIR/"
cp -r "$TEMP_DIR/sample-transcripts/codex/sessions/"* "$CODEX_DIR/"
echo "  Installed Claude Code transcripts to $CLAUDE_DIR"
echo "  Installed Codex transcripts to $CODEX_DIR"

# Step 4: Count installed files
echo ""
echo "Step 4: Verifying installation..."
CLAUDE_COUNT=$(find "$CLAUDE_DIR" -name "*.jsonl" | wc -l | tr -d ' ')
CODEX_COUNT=$(find "$CODEX_DIR" -name "*.jsonl" | wc -l | tr -d ' ')
echo "  Claude Code sessions: $CLAUDE_COUNT"
echo "  Codex CLI sessions: $CODEX_COUNT"

if [ "$CLAUDE_COUNT" -lt 3 ] || [ "$CODEX_COUNT" -lt 3 ]; then
    echo "ERROR: Missing transcript files!"
    exit 1
fi

# Step 5: Launch Contextify
echo ""
echo "Step 5: Ready for manual testing"
echo ""
echo "Next steps:"
echo "  1. Launch Contextify"
echo "  2. Verify 3 projects appear: TaskFlow, Weatherly, RecipeBox"
echo "  3. Verify timeline shows conversations"
echo "  4. Verify LLM summaries generate"
echo "  5. Test search: 'error', 'bug', 'recipe'"
echo "  6. Test Deep Search (Cmd+Shift+F)"
echo ""
echo "To restore your original data:"
echo "  rm -rf $CLAUDE_DIR $CODEX_DIR $DB_PATH"
echo "  mv $CLAUDE_DIR.backup.* $CLAUDE_DIR"
echo "  mv $CODEX_DIR.backup.* $CODEX_DIR"
echo "  mv $DB_PATH.backup.* $DB_PATH"
echo ""
echo "=== QA Setup Complete ==="
```

### Manual QA Checklist

After running qa-test.sh, verify in Contextify:

**Project Discovery:**
- [ ] TaskFlow appears in project list
- [ ] Weatherly appears in project list
- [ ] RecipeBox appears in project list

**Timeline Display:**
- [ ] TaskFlow shows 3 sessions (2 Claude + 1 Codex)
- [ ] Weatherly shows 2 sessions (1 Claude + 1 Codex)
- [ ] RecipeBox shows 1 session (Codex only)

**Message Content:**
- [ ] User messages display correctly
- [ ] Assistant messages display correctly
- [ ] Timestamps are reasonable (Nov 20-22, 2025)

**LLM Summaries:**
- [ ] Summaries generate for conversations
- [ ] Summary content is relevant to conversation

**Search (Quick Search - Cmd+F):**
- [ ] Search "error" finds bug fix discussion
- [ ] Search "recipe" finds RecipeBox content
- [ ] Search "weather" finds Weatherly content

**Deep Search (Cmd+Shift+F):**
- [ ] Opens in separate window
- [ ] Shows results from multiple projects
- [ ] Context pane shows surrounding messages

**Provider Indicators:**
- [ ] Claude Code sessions show correct icon/label
- [ ] Codex sessions show correct icon/label

---

## Delivery Checklist

- [ ] Create all 6 JSONL files with proper format (3 Claude + 3 Codex)
- [ ] Validate JSON syntax for each file
- [ ] Run qa-test.sh on clean system
- [ ] Verify all projects appear in Contextify
- [ ] Verify search finds expected terms
- [ ] Verify LLM summaries generate
- [ ] Package as sample-data.zip
- [ ] Write reviewer README with setup instructions
- [ ] Upload to contextify.sh/review-4a125b1d/
- [ ] Test download and setup process end-to-end
- [ ] Update App Review Notes in App Store Connect
