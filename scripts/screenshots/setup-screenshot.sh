#!/bin/bash
# Setup windows for Contextify screenshots
# Positions Terminal and Contextify for optimal screenshot composition
# within App Store screenshot dimensions
#
# Usage: ./setup-screenshot.sh [options] [window-number]
#   --db-only     Only setup database (project order), skip window positioning
#   window-number: Optional. iTerm2 window index (1, 2, 3, etc.)
#                 If omitted, uses current window after 3-second countdown.

set -e

# Parse arguments
DB_ONLY=false
WINDOW_INDEX=""

for arg in "$@"; do
  case $arg in
    --db-only)
      DB_ONLY=true
      ;;
    *)
      WINDOW_INDEX="$arg"
      ;;
  esac
done

# ============================================================================
# DATABASE SETUP: Project order for screenshot 1
# ============================================================================
setup_database() {
  echo "🗄️  Setting up database for screenshots..."

  # Find database location from defaults
  DB_PATH=$(defaults read dev.contextify "dev.contextify.customDatabaseLocation" 2>/dev/null || echo "")
  if [ -z "$DB_PATH" ]; then
    DB_PATH="$HOME/Library/Application Support/Contextify"
  fi
  DB_FILE="$DB_PATH/contextify.db"

  if [ ! -f "$DB_FILE" ]; then
    echo "❌ Database not found at: $DB_FILE"
    return 1
  fi

  echo "   Database: $DB_FILE"

  # Set project display order:
  # contextify=0, cli-ai-setup=1, Euler=2, correspondence=3, administration=4
  echo "   Setting project order: contextify, cli-ai-setup, Euler, correspondence, administration"

  sqlite3 "$DB_FILE" <<'EOSQL'
UPDATE projects SET display_order = 0 WHERE name = 'contextify';
UPDATE projects SET display_order = 1 WHERE name = 'cli-ai-setup';
UPDATE projects SET display_order = 2 WHERE name = 'Euler';
UPDATE projects SET display_order = 3 WHERE name = 'correspondence';
UPDATE projects SET display_order = 4 WHERE name = 'administration';
-- Push others down
UPDATE projects SET display_order = display_order + 100
  WHERE name NOT IN ('contextify', 'cli-ai-setup', 'Euler', 'correspondence', 'administration')
  AND display_order IS NOT NULL AND display_order < 100;
EOSQL

  echo "✅ Database setup complete"
  echo ""
  echo "   Project order now:"
  sqlite3 "$DB_FILE" "SELECT display_order, name FROM projects WHERE hidden = 0 ORDER BY display_order ASC NULLS LAST LIMIT 7"
  echo ""
}

# ============================================================================
# DEMO ENTRIES: Seed compelling conversation entries for screenshot 1
# ============================================================================
seed_demo_entries() {
  echo "📝 Seeding demo conversation entries..."

  DB_PATH=$(defaults read dev.contextify "dev.contextify.customDatabaseLocation" 2>/dev/null || echo "")
  if [ -z "$DB_PATH" ]; then
    DB_PATH="$HOME/Library/Application Support/Contextify"
  fi
  DB_FILE="$DB_PATH/contextify.db"

  # Get contextify project ID
  PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE name = 'contextify' LIMIT 1")
  if [ -z "$PROJECT_ID" ]; then
    echo "❌ contextify project not found"
    return 1
  fi

  # Check if demo entries already exist with correct summaries
  EXISTING_COUNT=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*)
    FROM transcript_entries te
    INNER JOIN timeline_cache tc ON te.id = tc.entry_id
    WHERE te.id LIKE 'demo-entry-%'
      AND te.display_in_timeline = 1
      AND tc.generator_signature = 'screenshot-demo-v1'
  ")

  if [ "$EXISTING_COUNT" -eq 5 ]; then
    echo "✅ Demo entries already seeded (5 entries found, skipping reseed)"
    echo ""
    return 0
  fi

  # Create a demo transcript if needed
  TRANSCRIPT_ID="demo-screenshot-transcript"
  DEMO_PATH="/tmp/demo-screenshot.jsonl"

  # Base timestamp: now minus 10 minutes, entries spaced 2 min apart
  NOW=$(date +%s)
  TS1=$((NOW - 600))
  TS2=$((NOW - 480))
  TS3=$((NOW - 360))
  TS4=$((NOW - 240))
  TS5=$((NOW - 120))

  # Generator signature for cache
  GEN_SIG="screenshot-demo-v1"

  sqlite3 "$DB_FILE" <<EOSQL
-- Clean up any previous demo entries
DELETE FROM timeline_cache WHERE entry_id LIKE 'demo-entry-%';
DELETE FROM transcript_entries WHERE id LIKE 'demo-entry-%';
DELETE FROM transcripts WHERE id = '$TRANSCRIPT_ID';

-- Hide any real entries that would appear after our first demo entry (TS1)
-- We set display_in_timeline = 0 instead of deleting so cleanup can restore them
UPDATE transcript_entries
SET display_in_timeline = 0
WHERE project_id = '$PROJECT_ID'
  AND timestamp >= $TS1
  AND id NOT LIKE 'demo-entry-%';

-- Create demo transcript
INSERT OR REPLACE INTO transcripts (
  id, project_id, file_path, provider, last_modified, line_count, status, ingest_state, created_at, updated_at
) VALUES (
  '$TRANSCRIPT_ID', '$PROJECT_ID', '$DEMO_PATH', 'claude.code', $NOW, 5, 'active', 'complete', $NOW, $NOW
);

-- Entry 1: User request
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-entry-1', '$TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'user', $TS1,
  'Add dark mode support to the settings panel',
  'demo-sha-1', 1, $NOW, $NOW, ${TS1}.0, 'demo-window-1'
);

-- Entry 2: Claude working
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-entry-2', '$TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'assistant', $TS2,
  'I have updated the color tokens and fixed contrast issues in the sidebar.',
  'demo-sha-2', 1, $NOW, $NOW, ${TS2}.0, 'demo-window-2'
);

-- Entry 3: Claude completion
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-entry-3', '$TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'assistant', $TS3,
  'Dark mode implementation complete. All components now respect the system appearance setting.',
  'demo-sha-3', 1, $NOW, $NOW, ${TS3}.0, 'demo-window-3'
);

-- Entry 4: User follow-up
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-entry-4', '$TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'user', $TS4,
  'Looks great! Run the tests to make sure nothing broke.',
  'demo-sha-4', 1, $NOW, $NOW, ${TS4}.0, 'demo-window-4'
);

-- Entry 5: Claude test results
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-entry-5', '$TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'assistant', $TS5,
  'All 47 tests passing. Build succeeded with zero warnings.',
  'demo-sha-5', 1, $NOW, $NOW, ${TS5}.0, 'demo-window-5'
);

-- Pre-populate timeline cache with summaries
INSERT OR REPLACE INTO timeline_cache (
  content_sha256, window_sha256, entry_id, generator_signature, disposition,
  present_form, past_form, selected_form, generated_at
) VALUES
  ('demo-sha-1', 'demo-window-1', 'demo-entry-1', '$GEN_SIG', 'directive',
   'You requested dark mode support for the settings panel', 'You requested dark mode support for the settings panel', 'present', $NOW),
  ('demo-sha-2', 'demo-window-2', 'demo-entry-2', '$GEN_SIG', 'completion',
   'Claude Code updated color tokens and fixed sidebar contrast', 'Claude Code updated color tokens and fixed sidebar contrast', 'present', $NOW),
  ('demo-sha-3', 'demo-window-3', 'demo-entry-3', '$GEN_SIG', 'completion',
   'Claude Code completed dark mode implementation', 'Claude Code completed dark mode implementation', 'present', $NOW),
  ('demo-sha-4', 'demo-window-4', 'demo-entry-4', '$GEN_SIG', 'directive',
   'You requested to run the test suite', 'You requested to run the test suite', 'present', $NOW),
  ('demo-sha-5', 'demo-window-5', 'demo-entry-5', '$GEN_SIG', 'completion',
   'Claude Code confirmed all 47 tests passing', 'Claude Code confirmed all 47 tests passing', 'present', $NOW);
EOSQL

  echo "✅ Demo entries seeded (5 entries for contextify project)"
  echo ""
}

# ============================================================================
# MIXED DEMO ENTRIES: Claude Code + Codex interleaved for screenshot 2
# ============================================================================
seed_mixed_demo_entries() {
  echo "📝 Seeding mixed provider demo entries (Claude Code + Codex)..."

  DB_PATH=$(defaults read dev.contextify "dev.contextify.customDatabaseLocation" 2>/dev/null || echo "")
  if [ -z "$DB_PATH" ]; then
    DB_PATH="$HOME/Library/Application Support/Contextify"
  fi
  DB_FILE="$DB_PATH/contextify.db"

  # Get contextify project ID
  PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE name = 'contextify' LIMIT 1")
  if [ -z "$PROJECT_ID" ]; then
    echo "❌ contextify project not found"
    return 1
  fi

  # Check if mixed demo entries already exist with correct summaries
  EXISTING_COUNT=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*)
    FROM transcript_entries te
    INNER JOIN timeline_cache tc ON te.id = tc.entry_id
    WHERE te.id LIKE 'demo-mixed-%'
      AND te.display_in_timeline = 1
      AND tc.generator_signature = 'screenshot-mixed-demo-v1'
  ")

  if [ "$EXISTING_COUNT" -eq 5 ]; then
    echo "✅ Mixed provider demo entries already seeded (5 entries found, skipping reseed)"
    echo ""
    return 0
  fi

  # Create demo transcripts for both providers
  CLAUDE_TRANSCRIPT_ID="demo-mixed-claude-transcript"
  CODEX_TRANSCRIPT_ID="demo-mixed-codex-transcript"
  DEMO_CLAUDE_PATH="/tmp/demo-mixed-claude.jsonl"
  DEMO_CODEX_PATH="/tmp/demo-mixed-codex.jsonl"

  # Base timestamp: now minus 10 minutes, entries spaced apart
  NOW=$(date +%s)
  TS1=$((NOW - 600))  # Claude Code user
  TS2=$((NOW - 480))  # Claude Code assistant
  TS3=$((NOW - 360))  # Codex user
  TS4=$((NOW - 240))  # Codex assistant
  TS5=$((NOW - 120))  # Claude Code assistant (sees codex work)

  GEN_SIG="screenshot-mixed-demo-v1"

  sqlite3 "$DB_FILE" <<EOSQL
-- Clean up any previous demo entries
DELETE FROM timeline_cache WHERE entry_id LIKE 'demo-mixed-%';
DELETE FROM transcript_entries WHERE id LIKE 'demo-mixed-%';
DELETE FROM transcripts WHERE id IN ('$CLAUDE_TRANSCRIPT_ID', '$CODEX_TRANSCRIPT_ID');

-- Hide any real entries that would appear after our first demo entry
UPDATE transcript_entries
SET display_in_timeline = 0
WHERE project_id = '$PROJECT_ID'
  AND timestamp >= $TS1
  AND id NOT LIKE 'demo-mixed-%';

-- Create demo transcripts
INSERT OR REPLACE INTO transcripts (
  id, project_id, file_path, provider, last_modified, line_count, status, ingest_state, created_at, updated_at
) VALUES
  ('$CLAUDE_TRANSCRIPT_ID', '$PROJECT_ID', '$DEMO_CLAUDE_PATH', 'claude.code', $NOW, 3, 'active', 'complete', $NOW, $NOW),
  ('$CODEX_TRANSCRIPT_ID', '$PROJECT_ID', '$DEMO_CODEX_PATH', 'codex.cli', $NOW, 2, 'active', 'complete', $NOW, $NOW);

-- Entry 1: Claude Code user request
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-mixed-1', '$CLAUDE_TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'user', $TS1,
  'Refactor the auth module to use async/await',
  'demo-mixed-sha-1', 1, $NOW, $NOW, ${TS1}.0, 'demo-mixed-window-1'
);

-- Entry 2: Claude Code assistant response
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-mixed-2', '$CLAUDE_TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'assistant', $TS2,
  'I have refactored the authentication module to use async/await patterns throughout.',
  'demo-mixed-sha-2', 1, $NOW, $NOW, ${TS2}.0, 'demo-mixed-window-2'
);

-- Entry 3: Codex user request
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-mixed-3', '$CODEX_TRANSCRIPT_ID', '$PROJECT_ID', 'codex.cli', 'user', $TS3,
  'Write unit tests for the auth module',
  'demo-mixed-sha-3', 1, $NOW, $NOW, ${TS3}.0, 'demo-mixed-window-3'
);

-- Entry 4: Codex assistant response
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-mixed-4', '$CODEX_TRANSCRIPT_ID', '$PROJECT_ID', 'codex.cli', 'assistant', $TS4,
  'Generated 12 test cases covering authentication flows, token refresh, and error handling.',
  'demo-mixed-sha-4', 1, $NOW, $NOW, ${TS4}.0, 'demo-mixed-window-4'
);

-- Entry 5: Claude Code sees the tests and confirms
INSERT INTO transcript_entries (
  id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256,
  display_in_timeline, created_at, updated_at, created_ts, window_sha256
) VALUES (
  'demo-mixed-5', '$CLAUDE_TRANSCRIPT_ID', '$PROJECT_ID', 'claude.code', 'assistant', $TS5,
  'All 12 new tests are passing. The async refactor is complete.',
  'demo-mixed-sha-5', 1, $NOW, $NOW, ${TS5}.0, 'demo-mixed-window-5'
);

-- Pre-populate timeline cache with summaries
INSERT OR REPLACE INTO timeline_cache (
  content_sha256, window_sha256, entry_id, generator_signature, disposition,
  present_form, past_form, selected_form, generated_at
) VALUES
  ('demo-mixed-sha-1', 'demo-mixed-window-1', 'demo-mixed-1', '$GEN_SIG', 'directive',
   'You requested async/await refactor for the auth module', 'You requested async/await refactor for the auth module', 'present', $NOW),
  ('demo-mixed-sha-2', 'demo-mixed-window-2', 'demo-mixed-2', '$GEN_SIG', 'completion',
   'Claude Code refactored auth module to async/await', 'Claude Code refactored auth module to async/await', 'present', $NOW),
  ('demo-mixed-sha-3', 'demo-mixed-window-3', 'demo-mixed-3', '$GEN_SIG', 'directive',
   'You requested unit tests for auth module', 'You requested unit tests for auth module', 'present', $NOW),
  ('demo-mixed-sha-4', 'demo-mixed-window-4', 'demo-mixed-4', '$GEN_SIG', 'completion',
   'Codex generated 12 test cases for auth flows', 'Codex generated 12 test cases for auth flows', 'present', $NOW),
  ('demo-mixed-sha-5', 'demo-mixed-window-5', 'demo-mixed-5', '$GEN_SIG', 'completion',
   'Claude Code confirmed all 12 tests passing', 'Claude Code confirmed all 12 tests passing', 'present', $NOW);
EOSQL

  echo "✅ Mixed demo entries seeded (5 entries: 3 Claude Code, 2 Codex)"
  echo ""
}

# Function to clean up demo entries
cleanup_demo_entries() {
  echo "🧹 Cleaning up demo entries..."

  DB_PATH=$(defaults read dev.contextify "dev.contextify.customDatabaseLocation" 2>/dev/null || echo "")
  if [ -z "$DB_PATH" ]; then
    DB_PATH="$HOME/Library/Application Support/Contextify"
  fi
  DB_FILE="$DB_PATH/contextify.db"

  # Get contextify project ID for restoring hidden entries
  PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE name = 'contextify' LIMIT 1")

  sqlite3 "$DB_FILE" <<EOSQL
-- Remove demo entries (both single and mixed)
DELETE FROM timeline_cache WHERE entry_id LIKE 'demo-entry-%' OR entry_id LIKE 'demo-mixed-%';
DELETE FROM transcript_entries WHERE id LIKE 'demo-entry-%' OR id LIKE 'demo-mixed-%';
DELETE FROM transcripts WHERE id IN ('demo-screenshot-transcript', 'demo-mixed-claude-transcript', 'demo-mixed-codex-transcript');

-- Restore any real entries we hid
UPDATE transcript_entries
SET display_in_timeline = 1
WHERE project_id = '$PROJECT_ID'
  AND display_in_timeline = 0
  AND id NOT LIKE 'demo-entry-%'
  AND id NOT LIKE 'demo-mixed-%';
EOSQL

  echo "✅ Demo entries removed and hidden entries restored"
}

# Run database setup
setup_database

# Handle demo entries based on flags
case "${1:-}" in
  --seed-demo)
    seed_demo_entries
    exit 0
    ;;
  --seed-mixed)
    seed_mixed_demo_entries
    exit 0
    ;;
  --cleanup-demo)
    cleanup_demo_entries
    exit 0
    ;;
esac

# If --db-only, exit here
if [ "$DB_ONLY" = true ]; then
  echo "Done (--db-only mode)"
  exit 0
fi

echo "Setting up windows for screenshot..."
echo ""

# Save original window positions to temp file for restoration
POSITIONS_FILE="/tmp/contextify-screenshot-positions.txt"
rm -f "$POSITIONS_FILE"

echo "💾 Saving original window positions..."

# Save Contextify window position
osascript <<EOF > /dev/null 2>&1
tell application "System Events"
    tell process "Contextify"
        if (count of windows) > 0 then
            set pos to position of window 1
            set sz to size of window 1
            do shell script "echo 'CONTEXTIFY_X=" & (item 1 of pos) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_Y=" & (item 2 of pos) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_W=" & (item 1 of sz) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_H=" & (item 2 of sz) & "' >> $POSITIONS_FILE"
        end if
    end tell
end tell
EOF

if [ -n "$WINDOW_INDEX" ]; then
    echo "🔍 Using iTerm2 window #$WINDOW_INDEX"
    # Save specified iTerm2 window position
    osascript <<EOF > /dev/null 2>&1
tell application "iTerm2"
    if (count of windows) >= $WINDOW_INDEX then
        tell window $WINDOW_INDEX
            set bnds to bounds
            do shell script "echo 'ITERM_INDEX=$WINDOW_INDEX' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_X=" & (item 1 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_Y=" & (item 2 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_W=" & ((item 3 of bnds) - (item 1 of bnds)) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_H=" & ((item 4 of bnds) - (item 2 of bnds)) & "' >> $POSITIONS_FILE"
        end tell
    end if
end tell
EOF
else
    echo "⏱️  You have 3 seconds to click on the iTerm2 window you want to use..."
    echo "   (The frontmost iTerm2 window will be positioned)"
    echo ""

    # Countdown to let user select the correct iTerm2 window
    for i in 3 2 1; do
        echo "   $i..."
        sleep 1
    done

    # Save current iTerm2 window position
    osascript <<EOF > /dev/null 2>&1
tell application "iTerm2"
    if (count of windows) > 0 then
        tell current window
            set bnds to bounds
            set idx to index
            do shell script "echo 'ITERM_INDEX=" & idx & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_X=" & (item 1 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_Y=" & (item 2 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_W=" & ((item 3 of bnds) - (item 1 of bnds)) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_H=" & ((item 4 of bnds) - (item 2 of bnds)) & "' >> $POSITIONS_FILE"
        end tell
    end if
end tell
EOF
fi

echo ""
echo "Positioning windows..."

# Get screen dimensions
SCREEN_WIDTH=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $2}' | head -1)
SCREEN_HEIGHT=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $4}' | head -1)

echo "Screen resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

# Target screenshot size (App Store requirement)
SHOT_WIDTH=1440
SHOT_HEIGHT=900

# Position the capture area in upper-left region (easier to see)
# Leave room at top for Terminal title bar (starts at Y=50)
CAPTURE_X=200
CAPTURE_Y=50

# Window dimensions and positions (Apple marketing style: compact HUD + context)
# 15% larger than original, centered with equal left/right padding
# Contextify: Compact HUD design (~483px wide, stays out of the way)
CONTEXTIFY_WIDTH=483
CONTEXTIFY_HEIGHT=633
CONTEXTIFY_X=337
CONTEXTIFY_Y=277

# iTerm2: Terminal for context (shows real development workflow)
# Positioned with 50px gap, bottoms aligned at Y=910, centered in 1440px frame
TERMINAL_WIDTH=633
TERMINAL_HEIGHT=460
TERMINAL_X=870
TERMINAL_Y=450

# OLD DIMENSIONS (split-screen style, equal emphasis):
# CONTEXTIFY_WIDTH=580
# CONTEXTIFY_HEIGHT=700
# CONTEXTIFY_X=$((CAPTURE_X + 10))  # 210
# CONTEXTIFY_Y=$((CAPTURE_Y + 100))  # 150
# TERMINAL_WIDTH=800
# TERMINAL_HEIGHT=850
# TERMINAL_X=$((CAPTURE_X + 610))  # 810
# TERMINAL_Y=$((CAPTURE_Y + 25))  # 75

# Position Contextify first (on the left, showcasing the app!)
osascript <<EOF
tell application "Contextify"
    activate
    delay 0.3
end tell

tell application "System Events"
    tell process "Contextify"
        set position of window 1 to {$CONTEXTIFY_X, $CONTEXTIFY_Y}
        set size of window 1 to {$CONTEXTIFY_WIDTH, $CONTEXTIFY_HEIGHT}
    end tell
end tell
EOF

sleep 0.5

# Position iTerm2 (uses specified window or current window)
if [ -n "$WINDOW_INDEX" ]; then
    # Use specified window index
    osascript <<EOF
tell application "iTerm2"
    if (count of windows) < $WINDOW_INDEX then
        error "iTerm2 window #$WINDOW_INDEX not found. Only " & (count of windows) & " windows available."
    end if
    tell window $WINDOW_INDEX
        set bounds to {$TERMINAL_X, $TERMINAL_Y, $TERMINAL_X + $TERMINAL_WIDTH, $TERMINAL_Y + $TERMINAL_HEIGHT}
    end tell
end tell
EOF
else
    # Use current window (user selected during countdown)
    osascript <<EOF
tell application "iTerm2"
    if (count of windows) is 0 then
        activate
        create window with default profile
        delay 0.5
    end if
    tell current window
        set bounds to {$TERMINAL_X, $TERMINAL_Y, $TERMINAL_X + $TERMINAL_WIDTH, $TERMINAL_Y + $TERMINAL_HEIGHT}
    end tell
end tell
EOF
fi

echo "✅ Windows positioned!"
echo ""
echo "Screenshot area: ${SHOT_WIDTH}x${SHOT_HEIGHT} at (${CAPTURE_X}, ${CAPTURE_Y})"
echo "Contextify (L):  ${CONTEXTIFY_WIDTH}x${CONTEXTIFY_HEIGHT} at (${CONTEXTIFY_X}, ${CONTEXTIFY_Y})"
echo "iTerm2 (R):      ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT} at (${TERMINAL_X}, ${TERMINAL_Y})"
echo ""

# Give focus to Contextify window before returning
osascript -e 'tell application "Contextify" to activate' > /dev/null 2>&1
sleep 0.3
