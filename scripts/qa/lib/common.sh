#!/bin/bash
# Common utilities for Contextify QA tests
# Source this file in test scripts: source "$(dirname "$0")/../lib/common.sh"

set -euo pipefail

# Source shared cleanup library (use internal var to avoid conflict with caller's SCRIPT_DIR)
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_COMMON_LIB_DIR/../../lib/cleanup.sh"

# Bundle IDs for the two app variants
BUNDLE_ID_DMG="dev.contextify"
BUNDLE_ID_APPSTORE="sh.contextify.Contextify"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
DB_PATH="${DB_PATH:-$HOME/Library/Application Support/Contextify/contextify.db}"
DMG_APP_PATH="${DMG_APP_PATH:-$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app}"
APPSTORE_APP_PATH="${APPSTORE_APP_PATH:-$REPO_ROOT/.derived-appstore/Build/Products/Debug/Contextify.app}"

# Fixture mode configuration
QA_FIXTURE_MODE="${QA_FIXTURE_MODE:-0}"
QA_FIXTURE_DIR="${QA_FIXTURE_DIR:-$REPO_ROOT/scripts/qa/fixtures}"

# Test project path (used by fixture transcript seeding)
# Default matches CI and local test expectations
TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"

# Log capture state
LOGFILE=""
LOG_PID=""

# Test state
TEST_ID="${TEST_ID:-QA-XX}"
TEST_NAME="${TEST_NAME:-Unknown Test}"
TEST_FAILED=0

# Timeout command (detected at first use)
TIMEOUT_CMD=""
TIMEOUT_CMD_CHECKED=0

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────

log_info() { echo "[INFO] $*"; }
log_success() { echo "[PASS] $*"; }
log_error() { echo "[FAIL] $*" >&2; }
log_warn() { echo "[WARN] $*"; }
log_debug() {
  if [ "${QA_DEBUG:-0}" = "1" ]; then
    echo "[DEBUG] $*"
  fi
}

log_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_subheader() {
  echo ""
  echo "── $* ──────────────────────────────────────────────────────────────────"
}

# ─────────────────────────────────────────────────────────────────────────────
# Database Operations
# ─────────────────────────────────────────────────────────────────────────────

db_query() {
  local query="$1"
  # Add timeout to handle occasional WAL locks from GRDB
  sqlite3 -cmd ".timeout 2000" "$DB_PATH" "$query" 2>/dev/null || echo ""
}

db_count() {
  local query="$1"
  local result
  result=$(db_query "$query")
  echo "${result:-0}" | xargs
}

db_exists() {
  [ -f "$DB_PATH" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Capture
# ─────────────────────────────────────────────────────────────────────────────

start_log_capture() {
  local log_dir="${1:-/tmp}"
  LOGFILE="${log_dir}/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S).log"

  # Start log stream in background
  log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' \
    --level debug > "$LOGFILE" 2>&1 &
  LOG_PID=$!

  # Let logger initialize
  sleep 2
  log_info "Log capture started: $LOGFILE (PID: $LOG_PID)"
}

stop_log_capture() {
  if [ -n "${LOG_PID:-}" ]; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    LOG_PID=""
    log_info "Log capture stopped"
  fi
}

# Wait for a log pattern to appear (avoids blind sleeps)
wait_for_log_pattern() {
  local pattern="$1"
  local timeout="${2:-30}"
  local elapsed=0

  log_debug "Waiting for log pattern: $pattern (timeout: ${timeout}s)"

  while [ $elapsed -lt "$timeout" ]; do
    if [ -f "$LOGFILE" ] && grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
      log_debug "Pattern found after ${elapsed}s"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  log_warn "Timeout waiting for pattern: $pattern"
  return 1
}

# Wait for any of multiple patterns
wait_for_any_pattern() {
  local timeout="$1"
  shift
  local patterns=("$@")
  local elapsed=0

  while [ $elapsed -lt "$timeout" ]; do
    for pattern in "${patterns[@]}"; do
      if [ -f "$LOGFILE" ] && grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
        log_debug "Pattern found: $pattern"
        return 0
      fi
    done
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

# Get count of log pattern matches
log_count() {
  local pattern="$1"
  local count
  count=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")
  # Trim whitespace and ensure single number
  echo "$count" | head -1 | tr -d '[:space:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# App Control
# ─────────────────────────────────────────────────────────────────────────────

app_is_running() {
  pgrep -x "Contextify" > /dev/null 2>&1
}

kill_app_if_running() {
  local found_any=0

  # Check for any Contextify process
  if pgrep -x "Contextify" > /dev/null 2>&1; then
    found_any=1
  fi

  # Also check by bundle ID paths (catches launched-but-not-yet-running)
  if pgrep -f "Contextify.app/Contents/MacOS/Contextify" > /dev/null 2>&1; then
    found_any=1
  fi

  if [ "$found_any" -eq 1 ]; then
    log_info "Killing all Contextify instances..."

    # Method 1: Kill by process name
    pkill -9 -x "Contextify" 2>/dev/null || true

    # Method 2: Kill by app path patterns (catches both DMG and App Store builds)
    pkill -9 -f "derived-dmg.*Contextify" 2>/dev/null || true
    pkill -9 -f "derived-appstore.*Contextify" 2>/dev/null || true

    # Method 3: Quit gracefully via AppleScript (handles any Contextify)
    osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true

    # Method 4: killall as final fallback
    killall -9 "Contextify" 2>/dev/null || true

    sleep 2

    # Verify kill succeeded
    if pgrep -x "Contextify" > /dev/null 2>&1; then
      log_warn "Contextify still running after kill attempts!"
      # One more aggressive attempt
      pkill -9 -f "Contextify" 2>/dev/null || true
      sleep 1
    fi

    log_info "Kill complete"
  fi
}

launch_dmg_app() {
  log_info "Launching DMG build: $DMG_APP_PATH"

  if [ ! -d "$DMG_APP_PATH" ]; then
    log_error "DMG app not found: $DMG_APP_PATH"
    log_error "Build with: bash scripts/xc.sh --dist=dmg build"
    return 1
  fi

  # Launch with Sparkle auto-updates disabled to prevent modal interference
  open "$DMG_APP_PATH" --args -SUEnableAutomaticChecks NO

  # Wait for startup completion
  if wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 45; then
    log_success "App launched and startup complete"
    return 0
  else
    log_warn "Startup completion log not detected, checking if app is running..."
    if app_is_running; then
      log_success "App is running"
      return 0
    fi
    log_error "App launch failed"
    return 1
  fi
}

launch_appstore_app() {
  log_info "Launching App Store build: $APPSTORE_APP_PATH"

  if [ ! -d "$APPSTORE_APP_PATH" ]; then
    log_error "App Store app not found: $APPSTORE_APP_PATH"
    log_error "Build with: bash scripts/xc.sh --dist=appstore Debug build"
    return 1
  fi

  open "$APPSTORE_APP_PATH"

  # App Store build may show permission wizard first
  sleep 3

  if app_is_running; then
    log_success "App Store build launched"
    return 0
  fi

  log_error "App Store build launch failed"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# UI Automation (AppleScript + System Events)
# Prerequisite: Terminal must have Accessibility permission
# ─────────────────────────────────────────────────────────────────────────────

# Activate Contextify and bring to front
activate_app() {
  osascript -e 'tell application "Contextify" to activate' 2>/dev/null || true
  sleep 0.5
}

# Check if a window exists
window_exists() {
  local window_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"Contextify\" to exists window \"$window_name\"" 2>/dev/null || echo "false"
}

# Get window count
get_window_count() {
  osascript -e 'tell application "System Events" to tell process "Contextify" to count windows' 2>/dev/null || echo "0"
}

# Click a button by name in Contextify's frontmost window
# Note: Returns 0 even if button not found (safe under set -e)
# Use click_button_retry for critical buttons that must succeed
click_button() {
  local button_name="$1"
  log_debug "Clicking button: $button_name"
  osascript -e "tell application \"System Events\" to tell process \"Contextify\" to click button \"$button_name\" of window 1" 2>/dev/null || true
  sleep 0.3
}

# Click a button by index within a group (for SwiftUI buttons that don't expose names)
# Usage: click_group_button 1 1  # Click button 1 in group 1
click_group_button() {
  local group_num="$1"
  local button_num="$2"
  log_debug "Clicking button $button_num in group $group_num"
  osascript -e "tell application \"System Events\" to tell process \"Contextify\" to tell window 1 to tell group $group_num to click button $button_num" 2>/dev/null || true
  sleep 0.3
}

# Click a button by name, trying multiple times
click_button_retry() {
  local button_name="$1"
  local max_attempts="${2:-3}"
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if osascript -e "tell application \"System Events\" to tell process \"Contextify\" to click button \"$button_name\" of window 1" 2>/dev/null; then
      log_debug "Button clicked: $button_name (attempt $attempt)"
      sleep 0.3
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  log_warn "Could not click button: $button_name"
  return 1
}

# Press Return/Enter key
press_return() {
  osascript -e 'tell application "System Events" to keystroke return' 2>/dev/null
  sleep 0.3
}

# Press Escape key
press_escape() {
  osascript -e 'tell application "System Events" to key code 53' 2>/dev/null
  sleep 0.3
}

# Send keyboard shortcut to Contextify specifically
# Usage: send_shortcut "t" "command down"
#        send_shortcut "]" "command down, shift down"
send_shortcut() {
  local key="$1"
  local modifiers="$2"
  log_debug "Sending shortcut: $key with {$modifiers}"
  # Activate Contextify first, then send keystroke to its process specifically
  osascript -e '
    tell application "Contextify" to activate
    delay 0.2
    tell application "System Events"
      tell process "Contextify"
        keystroke "'"$key"'" using {'"$modifiers"'}
      end tell
    end tell
  ' 2>/dev/null
  sleep 0.3
}

# Type text
type_text() {
  local text="$1"
  osascript -e "tell application \"System Events\" to keystroke \"$text\"" 2>/dev/null
  sleep 0.2
}

# ─────────────────────────────────────────────────────────────────────────────
# Permission Handling (App Store builds)
# ─────────────────────────────────────────────────────────────────────────────

# Grant folder permission via NSOpenPanel
# The panel opens at the correct location, just need to confirm
grant_folder_permission() {
  local permission_log_pattern="$1"
  local timeout="${2:-15}"

  log_info "Waiting for permission dialog..."

  # Wait for permission modal
  if ! wait_for_log_pattern "$permission_log_pattern" "$timeout"; then
    log_warn "Permission modal did not appear (pattern: $permission_log_pattern)"
    return 1
  fi

  sleep 1

  # Try to click "Choose Folder" or "Grant Access" button
  if click_button_retry "Choose Folder" 3 || \
     click_button_retry "Grant Access" 3 || \
     click_button_retry "Open" 3; then
    sleep 0.5
    # NSOpenPanel opens at correct location, press Enter to confirm
    press_return
    log_success "Folder permission granted"
    return 0
  fi

  log_warn "Could not grant folder permission"
  return 1
}

# Skip folder permission
skip_folder_permission() {
  local permission_log_pattern="$1"
  local timeout="${2:-10}"

  if ! wait_for_log_pattern "$permission_log_pattern" "$timeout"; then
    log_warn "Permission modal did not appear"
    return 1
  fi

  sleep 0.5

  # Try various skip/cancel buttons
  click_button_retry "Skip" 2 || \
    click_button_retry "Later" 2 || \
    click_button_retry "Cancel" 2 || \
    press_escape

  log_success "Folder permission skipped"
  return 0
}

# Complete onboarding wizard by clicking Continue
complete_onboarding() {
  local max_attempts="${1:-5}"
  local attempt=1

  log_info "Completing onboarding wizard..."

  while [ $attempt -le $max_attempts ]; do
    if click_button_retry "Continue" 2 || \
       click_button_retry "Get Started" 2 || \
       click_button_retry "Done" 2; then
      sleep 1
      # Check if we're past onboarding
      if wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 10; then
        log_success "Onboarding completed"
        return 0
      fi
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  log_warn "Could not complete onboarding automatically"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Timeout Command Detection
# ─────────────────────────────────────────────────────────────────────────────

# Detect timeout/gtimeout availability (macOS doesn't ship timeout by default)
# Sets TIMEOUT_CMD to "timeout", "gtimeout", or "" (empty if neither available)
detect_timeout_cmd() {
  if [ "$TIMEOUT_CMD_CHECKED" = "1" ]; then
    return 0
  fi
  TIMEOUT_CMD_CHECKED=1

  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
    log_debug "Using timeout command: timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
    log_debug "Using timeout command: gtimeout"
  else
    TIMEOUT_CMD=""
    log_debug "No timeout command available (timeout/gtimeout not found)"
  fi
}

# Run a command with timeout
# Usage: run_with_timeout SECONDS COMMAND [ARGS...]
# Requires timeout or gtimeout (checked by orchestrator prereqs)
run_with_timeout() {
  local timeout_secs="$1"
  shift

  detect_timeout_cmd

  if [ -n "$TIMEOUT_CMD" ]; then
    "$TIMEOUT_CMD" "$timeout_secs" "$@"
  else
    log_error "timeout/gtimeout required but not found (install coreutils)"
    log_error "Command was: $*"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Filesystem Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Find most recent transcript file
find_recent_transcript() {
  local provider="$1"  # "codex" or "claude"
  local age_minutes="${2:-5}"

  if [ "$provider" = "codex" ]; then
    find ~/.codex/sessions -name "*.jsonl" -mmin -"$age_minutes" 2>/dev/null | head -1
  else
    find ~/.claude/projects -name "*.jsonl" -mmin -"$age_minutes" 2>/dev/null | head -1
  fi
}

# Create a test project directory with git init
create_test_project() {
  local project_path="$1"
  local project_name
  project_name=$(basename "$project_path")

  if [ -d "$project_path" ]; then
    log_info "Test project already exists: $project_path"
    return 0
  fi

  log_info "Creating test project: $project_path"
  mkdir -p "$project_path"
  cd "$project_path"
  git init -q
  git config user.email "qa@contextify.test"
  git config user.name "QA Test"
  echo "# $project_name" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  cd - > /dev/null

  log_success "Test project created: $project_path"
}

# ─────────────────────────────────────────────────────────────────────────────
# State Reset Helpers (uses shared cleanup library)
# ─────────────────────────────────────────────────────────────────────────────

# Clear Contextify UserDefaults (both domains)
# Uses shared cleanup library for consistency with xc.sh
clear_user_defaults() {
  log_info "Clearing UserDefaults..."
  clean_userdefaults_for_bid "$BUNDLE_ID_APPSTORE"
  log_success "UserDefaults cleared"
}

# Get App Store sandbox container Application Support path
# Always returns the sandbox path (for clean installs we want to target this even if it doesn't exist)
get_appstore_app_support() {
  echo "$HOME/Library/Containers/$BUNDLE_ID_APPSTORE/Data/Library/Application Support/Contextify"
}

# Get App Store database path
get_appstore_db_path() {
  echo "$(get_appstore_app_support)/contextify.db"
}

# Reset App Store app state completely (DB, prefs, bookmarks, caches)
# This is equivalent to: bash scripts/xc.sh --dist=appstore reset-state
reset_appstore_state() {
  local preserve_bookmarks="${1:-false}"
  log_info "Resetting App Store app state..."

  # Always use sandbox container path for App Store builds
  local as_path
  as_path="$(get_appstore_app_support)"

  if [ -d "$as_path" ]; then
    if [ "$preserve_bookmarks" = "true" ]; then
      # Preserve bookmarks.plist, remove everything else
      local bookmarks_file="$as_path/bookmarks.plist"
      local temp_bookmarks="/tmp/qa-bookmarks-backup-$$.plist"

      if [ -f "$bookmarks_file" ]; then
        log_info "Backing up bookmarks..."
        cp "$bookmarks_file" "$temp_bookmarks"
      fi

      log_info "Removing Application Support (preserving bookmarks)..."
      rm -rf "$as_path"

      if [ -f "$temp_bookmarks" ]; then
        mkdir -p "$as_path"
        mv "$temp_bookmarks" "$bookmarks_file"
      fi
    else
      log_info "Removing Application Support..."
      rm -rf "$as_path"
    fi
  fi

  # Clean caches and UserDefaults using shared library
  clean_caches_for_bid "$BUNDLE_ID_APPSTORE"
  clean_userdefaults_for_bid "$BUNDLE_ID_APPSTORE"

  log_success "App Store state reset complete"
}

# Reset DMG app state (simpler, no sandbox)
reset_dmg_state() {
  log_info "Resetting DMG app state..."

  # Remove standard Application Support
  local as_path="$HOME/Library/Application Support/Contextify"
  if [ -d "$as_path" ]; then
    log_info "Removing Application Support..."
    rm -rf "$as_path"
  fi

  # Clean caches and UserDefaults
  clean_caches_for_bid "$BUNDLE_ID_DMG"
  clean_userdefaults_for_bid "$BUNDLE_ID_DMG"

  log_success "DMG state reset complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Fixture Transcript Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Seed a fixture transcript into the appropriate provider location
# Usage: seed_fixture_transcript "codex"|"claude" [fixture_name]
# Returns: path to seeded transcript file
# Requires: TEST_PROJECT to be set
seed_fixture_transcript() {
  local provider="$1"
  local fixture_name="${2:-simple-session.jsonl}"
  local src_file="$QA_FIXTURE_DIR/transcripts/$provider/$fixture_name"
  local dest_dir=""
  local dest_file=""

  # Validate TEST_PROJECT is set
  if [ -z "${TEST_PROJECT:-}" ]; then
    log_error "TEST_PROJECT is not set; required for fixture transcripts"
    return 1
  fi

  if [ ! -f "$src_file" ]; then
    log_error "Fixture transcript not found: $src_file"
    return 1
  fi

  case "$provider" in
    codex)
      # Codex uses date-based hierarchy: ~/.codex/sessions/YYYY/MM/DD/
      local date_path
      date_path=$(date +%Y/%m/%d)
      dest_dir="$HOME/.codex/sessions/$date_path"
      dest_file="$dest_dir/qa-fixture-$(date +%Y-%m-%dT%H-%M-%S)-$(uuidgen | tr '[:upper:]' '[:lower:]').jsonl"
      ;;
    claude)
      # Claude uses project-hash directories: ~/.claude/projects/<hash>/
      # Note: This is a simplified hash (tr '/' '-'), not Claude's actual algorithm.
      # Tests validate CWD-based discovery, not directory hash logic.
      local project_hash
      project_hash=$(echo "$TEST_PROJECT" | tr '/' '-')
      dest_dir="$HOME/.claude/projects/$project_hash"
      dest_file="$dest_dir/$(uuidgen | tr '[:upper:]' '[:lower:]').jsonl"
      ;;
    *)
      log_error "Unknown provider: $provider (expected 'codex' or 'claude')"
      return 1
      ;;
  esac

  mkdir -p "$dest_dir"

  # Escape sed replacement metacharacters in the path
  local escaped_project
  escaped_project=$(printf '%s' "$TEST_PROJECT" | sed -e 's/[\\&|]/\\&/g')

  # Copy and update cwd to point to test project
  sed "s|\"cwd\": \"[^\"]*\"|\"cwd\": \"$escaped_project\"|g" "$src_file" > "$dest_file"

  # Touch to ensure fresh mtime for discovery
  touch "$dest_file"

  log_info "Seeded fixture transcript: $dest_file" >&2
  echo "$dest_file"
}

# Focus the HUD search field
# Usage: focus_search_field
focus_search_field() {
  send_shortcut "f" "command down"
  sleep 0.3
}

# ─────────────────────────────────────────────────────────────────────────────
# Database Fixture Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Install a fixture database for migration testing
# Usage: install_db_fixture "v16-contextify.db"
install_db_fixture() {
  local fixture_name="$1"
  local src="$QA_FIXTURE_DIR/db/$fixture_name"

  if [ ! -f "$src" ]; then
    log_error "DB fixture not found: $src"
    return 1
  fi

  # Backup current DB if exists
  if [ -f "$DB_PATH" ]; then
    mv "$DB_PATH" "${DB_PATH}.qa-backup"
    log_info "Backed up existing DB to ${DB_PATH}.qa-backup"
  fi

  mkdir -p "$(dirname "$DB_PATH")"
  cp "$src" "$DB_PATH"

  # Remove WAL/SHM files if present
  rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"

  log_info "Installed DB fixture: $fixture_name"
}

# Restore DB from QA backup
restore_db_from_backup() {
  if [ -f "${DB_PATH}.qa-backup" ]; then
    rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
    mv "${DB_PATH}.qa-backup" "$DB_PATH"
    log_info "Restored DB from backup"
  else
    rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
    log_info "No DB backup found; removed test DB"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

# Default cleanup function for tests
# Individual tests should call setup_test_cleanup_trap() or define their own
cleanup_test() {
  log_info "Cleaning up test..."
  stop_log_capture

  # Keep test artifacts for debugging unless QA_CLEANUP=1
  if [ "${QA_CLEANUP:-0}" = "1" ]; then
    log_info "Removing test artifacts..."
    # Add cleanup logic here if needed
  else
    log_info "Test artifacts preserved for debugging"
    [ -n "${LOGFILE:-}" ] && log_info "Logs: $LOGFILE"
  fi
}

# Set up the default cleanup trap (tests should call this in main())
# NOTE: Not set at module level to avoid affecting orchestrator scripts
setup_test_cleanup_trap() {
  trap cleanup_test EXIT
}

# ─────────────────────────────────────────────────────────────────────────────
# Transcript Backup/Restore (isolate tests from production data)
# ─────────────────────────────────────────────────────────────────────────────

CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
CODEX_SESSIONS_DIR="$HOME/.codex/sessions"
CLAUDE_BACKUP_DIR="$HOME/.claude/projects-QA-BACKUP"
CODEX_BACKUP_DIR="$HOME/.codex/sessions-QA-BACKUP"

# Backup real transcripts and install minimal test data
# Usage: backup_and_isolate_transcripts
backup_and_isolate_transcripts() {
  log_info "Backing up production transcripts for isolated QA..."

  # Backup Claude projects (if not already backed up)
  if [ -d "$CLAUDE_PROJECTS_DIR" ] && [ ! -d "$CLAUDE_BACKUP_DIR" ]; then
    mv "$CLAUDE_PROJECTS_DIR" "$CLAUDE_BACKUP_DIR"
    log_info "Backed up Claude projects to $CLAUDE_BACKUP_DIR"
  elif [ -d "$CLAUDE_BACKUP_DIR" ]; then
    log_info "Claude backup already exists, removing current projects"
    rm -rf "$CLAUDE_PROJECTS_DIR"
  fi

  # Backup Codex sessions (if not already backed up)
  if [ -d "$CODEX_SESSIONS_DIR" ] && [ ! -d "$CODEX_BACKUP_DIR" ]; then
    mv "$CODEX_SESSIONS_DIR" "$CODEX_BACKUP_DIR"
    log_info "Backed up Codex sessions to $CODEX_BACKUP_DIR"
  elif [ -d "$CODEX_BACKUP_DIR" ]; then
    log_info "Codex backup already exists, removing current sessions"
    rm -rf "$CODEX_SESSIONS_DIR"
  fi

  # Create empty directories for test data
  mkdir -p "$CLAUDE_PROJECTS_DIR"
  mkdir -p "$CODEX_SESSIONS_DIR"

  log_success "Transcripts isolated for QA"
}

# Restore production transcripts from backup
# Usage: restore_transcripts_from_backup
restore_transcripts_from_backup() {
  log_info "Restoring production transcripts..."

  # Restore Claude projects
  if [ -d "$CLAUDE_BACKUP_DIR" ]; then
    rm -rf "$CLAUDE_PROJECTS_DIR"
    mv "$CLAUDE_BACKUP_DIR" "$CLAUDE_PROJECTS_DIR"
    log_info "Restored Claude projects"
  fi

  # Restore Codex sessions
  if [ -d "$CODEX_BACKUP_DIR" ]; then
    rm -rf "$CODEX_SESSIONS_DIR"
    mv "$CODEX_BACKUP_DIR" "$CODEX_SESSIONS_DIR"
    log_info "Restored Codex sessions"
  fi

  log_success "Production transcripts restored"
}

# Check if transcripts are currently isolated (backup exists)
# Usage: if transcripts_are_isolated; then ...
transcripts_are_isolated() {
  [ -d "$CLAUDE_BACKUP_DIR" ] || [ -d "$CODEX_BACKUP_DIR" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Test Framework
# ─────────────────────────────────────────────────────────────────────────────

# Mark test as failed (non-fatal, allows continued validation)
mark_failed() {
  TEST_FAILED=1
}

# Check if test is currently passing
test_is_passing() {
  [ "$TEST_FAILED" -eq 0 ]
}

# Exit with appropriate code based on test state
exit_with_result() {
  echo ""
  log_header "TEST RESULT: $TEST_ID - $TEST_NAME"

  if [ "$TEST_FAILED" -eq 0 ]; then
    log_success "PASSED"
    exit 0
  else
    log_error "FAILED"
    [ -n "${LOGFILE:-}" ] && log_info "Review logs: $LOGFILE"
    exit 1
  fi
}
