#!/bin/bash
# Contextify Demo Recording - Interactive Steps
# Run: ./scripts/release/demo-recording.sh [version]
# Example: ./scripts/release/demo-recording.sh 1.0.0-build4
#
# Quick restore: ./scripts/release/demo-recording.sh --restore

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source shared cleanup library
source "$PROJECT_ROOT/scripts/lib/cleanup.sh"

# Handle --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
  echo "Contextify Demo Recording Script"
  echo ""
  echo "Usage: ./scripts/release/demo-recording.sh [command|version]"
  echo ""
  echo "Commands:"
  echo "  (none)      Start interactive demo recording workflow"
  echo "  --status    Check current transcript state (real vs sample data)"
  echo "  --clean     Remove sample data only (keeps real projects)"
  echo "  --restore   Restore real transcripts from backup (auto-merges any real work)"
  echo "  --reset     Alias for --restore"
  echo "  --help      Show this help"
  echo ""
  echo "Examples:"
  echo "  ./scripts/release/demo-recording.sh              # Start demo workflow"
  echo "  ./scripts/release/demo-recording.sh 1.0.0-build4 # Use specific archive"
  echo "  ./scripts/release/demo-recording.sh --status     # Check current state"
  echo "  ./scripts/release/demo-recording.sh --clean      # Remove sample data"
  echo "  ./scripts/release/demo-recording.sh --restore    # Restore from backup"
  exit 0
fi

# Handle --status flag to check current state
if [[ "${1:-}" == "--status" || "${1:-}" == "status" ]]; then
  echo "Transcript State Check"
  echo "======================"
  echo ""

  # Check backup
  if [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
    BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
    echo "✅ Backup exists: ~/.claude/projects-REAL-BACKUP ($BACKUP_COUNT projects)"
  else
    echo "⚠️  No backup at ~/.claude/projects-REAL-BACKUP"
  fi
  echo ""

  # Check current projects
  if [[ -d ~/.claude/projects ]]; then
    CURRENT_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | wc -l | tr -d ' ')
    SAMPLE_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | grep -c "sample-projects" || echo 0)
    REAL_COUNT=$((CURRENT_COUNT - SAMPLE_COUNT))

    if [[ "$SAMPLE_COUNT" -gt 0 && "$REAL_COUNT" -gt 0 ]]; then
      echo "⚠️  MIXED STATE: ~/.claude/projects/"
      echo "   $REAL_COUNT real projects + $SAMPLE_COUNT sample projects"
      echo ""
      echo "   Sample projects (can be removed):"
      ls ~/.claude/projects/ 2>/dev/null | grep "sample-projects" | sed 's/^/     /'
      echo ""
      echo "   Real projects (first 5):"
      ls ~/.claude/projects/ 2>/dev/null | grep -v "sample-projects" | head -5 | sed 's/^/     /'
      if [[ "$REAL_COUNT" -gt 5 ]]; then
        echo "     ... and $((REAL_COUNT - 5)) more"
      fi
    elif [[ "$SAMPLE_COUNT" -gt 0 ]]; then
      echo "📦 SAMPLE DATA ONLY: ~/.claude/projects/ ($SAMPLE_COUNT sample projects)"
      echo "   Sample projects:"
      ls ~/.claude/projects/ 2>/dev/null | grep "sample-projects" | sed 's/^/     /'
    else
      echo "✅ REAL DATA: ~/.claude/projects/ ($REAL_COUNT projects)"
      echo "   Projects (first 5):"
      ls ~/.claude/projects/ 2>/dev/null | head -5 | sed 's/^/     /'
      if [[ "$REAL_COUNT" -gt 5 ]]; then
        echo "     ... and $((REAL_COUNT - 5)) more"
      fi
    fi
  else
    echo "❌ No projects at ~/.claude/projects"
  fi

  echo ""
  echo "Quick commands:"
  echo "  ./scripts/release/demo-recording.sh --restore  # Restore from backup"
  echo "  ./scripts/release/demo-recording.sh --clean    # Remove sample data only"
  echo "  ./scripts/release/demo-recording.sh            # Start demo workflow"
  exit 0
fi

# Handle --clean flag to remove sample data without needing backup
if [[ "${1:-}" == "--clean" || "${1:-}" == "clean" ]]; then
  echo "Removing sample data..."
  echo ""

  SAMPLE_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | grep -c "sample-projects" || echo 0)
  if [[ "$SAMPLE_COUNT" -eq 0 ]]; then
    echo "✅ No sample data found - nothing to remove"
    exit 0
  fi

  echo "Removing $SAMPLE_COUNT sample project(s):"
  for dir in ~/.claude/projects/*sample-projects*; do
    if [[ -d "$dir" ]]; then
      echo "  Removing: $(basename "$dir")"
      rm -rf "$dir"
    fi
  done

  # Also remove sample codex sessions if present
  if ls ~/.codex/sessions/ 2>/dev/null | grep -q "sample"; then
    echo "  Removing sample Codex sessions..."
    rm -rf ~/.codex/sessions/*sample* 2>/dev/null || true
  fi

  echo ""
  echo "✅ Sample data removed!"
  echo ""
  REAL_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | wc -l | tr -d ' ')
  echo "Remaining: $REAL_COUNT real projects"
  exit 0
fi

# Restore function - can be called from --restore flag or from pause() during workflow
do_restore() {
  echo "Restoring real transcripts from backup..."
  echo ""

  if [[ ! -d ~/.claude/projects-REAL-BACKUP ]]; then
    echo "❌ No backup found at ~/.claude/projects-REAL-BACKUP"
    echo ""
    echo "Tip: If you just have mixed data (real + sample), use --clean instead:"
    echo "  ./scripts/release/demo-recording.sh --clean"
    return 1
  fi

  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
  echo "Found backup with $BACKUP_COUNT projects"
  echo ""

  # Auto-merge any non-sample work done during demo mode back to backup
  SAMPLE_PATTERN="sample-projects"
  MERGED_COUNT=0

  echo "Checking for real work done during demo mode..."

  # Claude Code: merge any non-sample project directories
  if [[ -d ~/.claude/projects ]]; then
    for dir in ~/.claude/projects/*/; do
      dirname=$(basename "$dir")
      if [[ ! "$dirname" =~ $SAMPLE_PATTERN ]]; then
        if [[ -d ~/.claude/projects-REAL-BACKUP/"$dirname" ]]; then
          # Directory exists in backup - merge new files
          echo "  Merging updates: $dirname"
          cp -rn "$dir"* ~/.claude/projects-REAL-BACKUP/"$dirname"/ 2>/dev/null || true
        else
          # New directory - copy entire thing
          echo "  Adding new project: $dirname"
          cp -r "$dir" ~/.claude/projects-REAL-BACKUP/
        fi
        MERGED_COUNT=$((MERGED_COUNT + 1))
      fi
    done
  fi

  # Codex: merge any non-sample session files
  if [[ -d ~/.codex/sessions && -d ~/.codex/sessions-REAL-BACKUP ]]; then
    # Find session files that aren't in the sample data
    for year_dir in ~/.codex/sessions/*/; do
      if [[ -d "$year_dir" ]]; then
        year=$(basename "$year_dir")
        for month_dir in "$year_dir"*/; do
          if [[ -d "$month_dir" ]]; then
            month=$(basename "$month_dir")
            for day_dir in "$month_dir"*/; do
              if [[ -d "$day_dir" ]]; then
                day=$(basename "$day_dir")
                # Copy any new session files
                target_dir=~/.codex/sessions-REAL-BACKUP/"$year"/"$month"/"$day"
                mkdir -p "$target_dir"
                for session in "$day_dir"*.jsonl; do
                  if [[ -f "$session" ]]; then
                    session_name=$(basename "$session")
                    if [[ ! -f "$target_dir/$session_name" ]]; then
                      echo "  Adding Codex session: $year/$month/$day/$session_name"
                      cp "$session" "$target_dir/"
                      MERGED_COUNT=$((MERGED_COUNT + 1))
                    fi
                  fi
                done
              fi
            done
          fi
        done
      fi
    done
  fi

  if [[ "$MERGED_COUNT" -gt 0 ]]; then
    echo ""
    echo "✅ Merged $MERGED_COUNT items back to backup"
  else
    echo "  No new work to merge"
  fi
  echo ""

  # Remove current data (sample or mixed)
  rm -rf ~/.claude/projects ~/.codex/sessions

  # Restore backups
  mv ~/.claude/projects-REAL-BACKUP ~/.claude/projects
  mv ~/.codex/sessions-REAL-BACKUP ~/.codex/sessions 2>/dev/null || true

  # Clean up stub project directories
  if [[ -d ~/code/sample-projects ]]; then
    rm -rf ~/code/sample-projects
    echo "✅ Stub project directories removed"
  fi

  echo "✅ Real transcripts restored!"
  echo ""
  echo "Projects now in ~/.claude/projects/:"
  ls ~/.claude/projects/ 2>/dev/null | head -10
  COUNT=$(ls ~/.claude/projects/ 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$COUNT" -gt 10 ]]; then
    echo "... and $((COUNT - 10)) more"
  fi
  return 0
}

# Handle --restore flag for quick recovery after bailing early
if [[ "${1:-}" == "--restore" || "${1:-}" == "restore" || "${1:-}" == "--reset" || "${1:-}" == "reset" ]]; then
  do_restore
  exit $?
fi

# Demo recording uses ONLY release builds from build/archives/
# Dev builds (build/Contextify.xcarchive from xc.sh dev-archive) are not used because:
# 1. Demo should match the exact binary submitted to Apple
# 2. Release builds are versioned and auditable
# 3. Dev builds are scratch and may be overwritten frequently

# Version can be passed as argument or defaults to latest archive
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  # Find latest version directory in canonical release location
  LATEST=$(ls -t build/archives/ 2>/dev/null | grep "^v" | head -1)
  if [[ -z "$LATEST" ]]; then
    echo "❌ No release archives found in build/archives/"
    echo "   Run: ./scripts/release/build.sh X.Y.Z"
    echo "   (Do NOT use xc.sh dev-archive - that creates scratch builds)"
    exit 1
  fi
  ARCHIVE_PATH="build/archives/$LATEST/appstore/Contextify.xcarchive"
else
  ARCHIVE_PATH="build/archives/v${VERSION}/appstore/Contextify.xcarchive"
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Contextify.app"
BUNDLE_ID="sh.contextify.Contextify"
SANDBOX_CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
SANDBOX_APP_SUPPORT="$SANDBOX_CONTAINER/Data/Library/Application Support/Contextify"

pause() {
  echo ""
  echo "Press Enter to continue, or type 'restore' to restore real transcripts and exit..."
  read -r input
  if [[ "$input" == "restore" ]]; then
    echo ""
    do_restore
    exit 0
  fi
  echo ""
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Contextify Demo Recording Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Your real transcripts have been backed up to:"
echo "  ~/.claude/projects-REAL-BACKUP"
echo "  ~/.codex/sessions-REAL-BACKUP"
echo ""
echo "Archive path: $ARCHIVE_PATH"
echo "App path:     $APP_PATH"
echo ""

# Verify archive exists
if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ ERROR: Archive not found at $APP_PATH"
  echo "   Run: ./scripts/release/build.sh X.Y.Z"
  echo "   (Do NOT use xc.sh dev-archive - that creates scratch builds)"
  exit 1
fi
echo "✅ Archive verified"
pause

# Step 1: Backup real data and install sample data
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 1: Backup Real Data & Install Sample Data"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Handle backup
SAMPLE_PATTERN="sample-projects"
CURRENT_HAS_REAL=false
CURRENT_HAS_SAMPLE=false

if [[ -d ~/.claude/projects ]]; then
  if ls ~/.claude/projects/ 2>/dev/null | grep -q "$SAMPLE_PATTERN"; then
    CURRENT_HAS_SAMPLE=true
  fi
  if ls ~/.claude/projects/ 2>/dev/null | grep -v "$SAMPLE_PATTERN" | grep -q .; then
    CURRENT_HAS_REAL=true
  fi
fi

if [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$CURRENT_HAS_REAL" == "true" ]]; then
    # Real data exists but backup also exists - might lose new data!
    CURRENT_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | grep -v "$SAMPLE_PATTERN" | wc -l | tr -d ' ')
    echo "⚠️  WARNING: ~/.claude/projects contains $CURRENT_COUNT real project(s)"
    echo "   but backup already exists with $BACKUP_COUNT project(s)"
    echo ""
    echo "   This may happen if you've used Claude Code since the backup was created."
    echo "   Options:"
    echo "     1. Press Enter to MERGE new projects into backup, then continue"
    echo "     2. Press Ctrl+C to abort and handle manually"
    echo ""
    read -r
    echo "Merging new projects into backup..."
    cp -rn ~/.claude/projects/* ~/.claude/projects-REAL-BACKUP/ 2>/dev/null || true
    echo "✅ Backup updated at ~/.claude/projects-REAL-BACKUP"
  else
    echo "✅ Backup exists at ~/.claude/projects-REAL-BACKUP"
    echo "   ($BACKUP_COUNT project directories preserved)"
  fi
else
  echo "Backing up real transcripts..."
  mv ~/.claude/projects ~/.claude/projects-REAL-BACKUP 2>/dev/null || true
  mv ~/.codex/sessions ~/.codex/sessions-REAL-BACKUP 2>/dev/null || true
  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
  echo "✅ Backed up $BACKUP_COUNT projects to ~/.claude/projects-REAL-BACKUP"
fi

echo ""
echo "Installing sample transcripts (clean install)..."
rm -rf ~/.claude/projects ~/.codex/sessions
mkdir -p ~/.claude/projects ~/.codex/sessions
cp -r appstore-metadata/review-materials/sample-transcripts/claude/projects/* ~/.claude/projects/
cp -r appstore-metadata/review-materials/sample-transcripts/codex/sessions/* ~/.codex/sessions/
echo ""
echo "✅ Sample data installed:"
ls ~/.claude/projects/

# Create stub project directories so Claude Code can be launched
echo ""
echo "Creating stub project directories for real-time demo..."
mkdir -p ~/code/sample-projects/taskflow
mkdir -p ~/code/sample-projects/recipebox
mkdir -p ~/code/sample-projects/weatherly
# Initialize as git repos so Claude Code doesn't complain
for dir in ~/code/sample-projects/{taskflow,recipebox,weatherly}; do
  if [ ! -d "$dir/.git" ]; then
    git -C "$dir" init -q
    echo "# Sample Project" > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m "Initial commit"
  fi
done
echo "✅ Stub directories created at ~/code/sample-projects/"
echo "   You can now run: cd ~/code/sample-projects/taskflow && claude"
pause

# Step 2: Quit app and clean all state (uses shared cleanup from xc.sh)
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 2: Quit App & Clean All State"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Quit any running instance first
echo "Quitting Contextify if running..."
osascript -e 'tell application "Contextify" to quit' >/dev/null 2>&1 || true
pkill -x Contextify >/dev/null 2>&1 || true
sleep 1
echo "✅ App quit"

# Use db_manager.sh for database cleanup (single source of truth)
echo ""
echo "Cleaning database via db_manager.sh..."
CONTEXTIFY_DIST=appstore "$PROJECT_ROOT/scripts/db_manager.sh" clean --force 2>&1 | grep -E "^[ℹ✓⚠✗]" || true

# Clean remaining state (caches, UserDefaults) using shared library
echo ""
echo "Cleaning caches and preferences..."
clean_caches_for_bid "$BUNDLE_ID"
echo "  Cleared: Caches"
clean_userdefaults_for_bid "$BUNDLE_ID"
echo "  Cleared: UserDefaults (bundle + $CONTEXTIFY_SUITE suite)"

echo "✅ All app state cleaned"
pause

# Step 3: Reset TCC permissions (so permission dialogs appear)
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 3: Reset TCC Permissions"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Resetting macOS privacy permissions for $BUNDLE_ID..."
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
echo "✅ TCC permissions reset"
echo ""
echo "The permission dialog WILL appear when the app launches."
pause

# Step 4: Install to Applications and Launch
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 4: Install to Applications & Launch"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "For a realistic demo, we'll install the archived app to /Applications."
echo "This is the EXACT binary that will be submitted to Apple."
echo ""
echo "Source: $APP_PATH"
echo "Target: /Applications/Contextify.app"
echo ""

# Check if already installed
if [[ -d "/Applications/Contextify.app" ]]; then
  echo "⚠️  Contextify.app already exists in /Applications"
  echo "   It will be replaced with the archived build."
  echo ""
fi

echo "Press Enter to install to /Applications, or type 'skip' to launch from archive..."
read -r input
if [[ "$input" != "skip" ]]; then
  echo "Installing to /Applications..."
  rm -rf /Applications/Contextify.app 2>/dev/null || true
  cp -R "$APP_PATH" /Applications/
  echo "✅ Installed to /Applications/Contextify.app"

  # Offer to add to Dock (default: yes)
  echo ""
  echo "Add to Dock for realistic demo launch? (Y/n)"
  read -r add_dock
  if [[ "$add_dock" != "n" && "$add_dock" != "N" ]]; then
    # Add to Dock using defaults
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Contextify.app</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
    killall Dock
    sleep 2
    echo "✅ Added to Dock"
    ADDED_TO_DOCK=true
  else
    ADDED_TO_DOCK=false
  fi

  LAUNCH_PATH="/Applications/Contextify.app"
else
  LAUNCH_PATH="$APP_PATH"
  ADDED_TO_DOCK=false
fi

echo ""
if [[ "$ADDED_TO_DOCK" == "true" ]]; then
  echo "Launch app now? (y/N) - or launch from Dock for realistic demo"
else
  echo "Launch app now? (Y/n)"
fi
read -r do_launch

if [[ "$ADDED_TO_DOCK" == "true" ]]; then
  # Default no if added to dock (user will launch from dock)
  if [[ "$do_launch" == "y" || "$do_launch" == "Y" ]]; then
    open "$LAUNCH_PATH"
    echo "✅ App launched"
  else
    echo "👉 Launch from Dock when ready to record"
  fi
else
  # Default yes if not added to dock
  if [[ "$do_launch" != "n" && "$do_launch" != "N" ]]; then
    open "$LAUNCH_PATH"
    echo "✅ App launched"
  else
    echo "👉 Launch manually: open \"$LAUNCH_PATH\""
  fi
fi
echo ""
echo "VERIFY: The app should:"
echo "  1. Show a permission dialog for ~/.claude/"
echo "  2. NOT show any existing projects (fresh database)"
echo ""
pause

# Step 5: Recording instructions
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 5: Start Recording"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Open QuickTime Player:"
echo "  File → New Screen Recording"
echo ""
echo "Select the area or full screen, then click Record."
pause

# Demo scenes
echo "═══════════════════════════════════════════════════════════════"
echo "  DEMO SCENES TO RECORD"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Scene 1: PERMISSION DIALOG (Critical for Apple)"
echo "  - If not shown, quit app and re-launch from Dock or /Applications"
echo "  - Grant access to ~/.claude/ when prompted"
echo "  - Pause so viewer can see the dialog text"
pause

echo "Scene 2: PROJECT DETECTION"
echo "  - Show project tabs appearing: taskflow, weatherly, recipebox"
echo "  - Click through each tab briefly"
pause

echo "Scene 3: TIMELINE VIEW"
echo "  - Select a project (e.g., taskflow)"
echo "  - Scroll through the conversation timeline"
echo "  - Show timestamps and message content"
pause

echo "Scene 4: LLM SUMMARIES"
echo "  - Point out summary badges on entries"
echo "  - Hover/click to show summary text"
echo "  - Wait for any summaries still generating"
pause

echo "Scene 5: SEARCH (Cmd+F)"
echo "  - Press Cmd+F to open Quick Search"
echo "  - Type a query (e.g., 'authentication' or 'API')"
echo "  - Show results filtering in real-time"
echo "  - Click a result to navigate"
pause

echo "Scene 6: DEEP SEARCH (Cmd+Shift+F) - if available"
echo "  - Press Cmd+Shift+F for cross-project search"
echo "  - Show results from multiple projects"
pause

echo "Scene 7: REAL-TIME UPDATE (Shows live monitoring)"
echo "  - Keep Contextify visible"
echo "  - Open a NEW terminal and run Claude Code on a sample project:"
echo ""
echo "    cd ~/.claude/projects/"
echo "    ls  # should show: taskflow, weatherly, recipebox"
echo "    # Pick one and use claude --resume or start new session"
echo ""
echo "  - Send a simple message like: 'What is 2+2?'"
echo "  - Watch Contextify detect the new message in real-time"
echo "  - Show the summary generating for the new entry"
pause

echo "Scene 8: SETTINGS (Cmd+,)"
echo "  - Open Settings"
echo "  - Show database location options"
echo "  - Close Settings"
pause

echo "Scene 9: END"
echo "  - Return to timeline view"
echo "  - Stop recording"
pause

# Step 6: Save video
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 6: Save Video"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Stop the QuickTime recording and save as:"
echo "  website/review-4a125b1d/demo-video.mp4"
echo ""
echo "Or save anywhere and we'll move it."
pause

# Step 7: Cleanup option
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 7: Restore Real Data"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Ready to restore your real transcripts?"
echo ""
echo "This will:"
echo "  - Remove sample data from ~/.claude/projects and ~/.codex/sessions"
echo "  - Restore your backups"
echo ""
echo "Type 'restore' and press Enter to restore, or Ctrl+C to exit:"
read -r confirm

if [ "$confirm" = "restore" ]; then
  rm -rf ~/.claude/projects ~/.codex/sessions
  mv ~/.claude/projects-REAL-BACKUP ~/.claude/projects
  mv ~/.codex/sessions-REAL-BACKUP ~/.codex/sessions 2>/dev/null || true
  # Clean up stub project directories
  rm -rf ~/code/sample-projects
  echo ""
  echo "✅ Real transcripts restored!"
  echo "✅ Stub project directories removed"
  echo ""
  echo "You can now resume using Claude Code and Codex."
else
  echo ""
  echo "Skipped restore. Run manually when ready:"
  echo "  rm -rf ~/.claude/projects ~/.codex/sessions"
  echo "  mv ~/.claude/projects-REAL-BACKUP ~/.claude/projects"
  echo "  mv ~/.codex/sessions-REAL-BACKUP ~/.codex/sessions"
  echo "  rm -rf ~/code/sample-projects  # Remove stub directories"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  NEXT STEPS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. Verify video saved to: website/review-4a125b1d/demo-video.mp4"
echo "2. Deploy: ./scripts/deploy-website.sh"
echo "3. Export & upload: bash scripts/xc.sh export-pkg && bash scripts/xc.sh upload"
echo "4. Submit in App Store Connect with review notes"
echo ""
echo "Done!"
