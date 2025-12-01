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
  if [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
    echo "Press Enter to continue, Esc to restore and exit..."
    read -rsn1 key
    if [[ "$key" == $'\e' ]]; then
      echo ""
      echo "Restoring..."
      do_restore
      exit 0
    fi
  else
    echo "Press Enter to continue..."
    read -rsn1
  fi
  echo ""
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Contextify Demo Recording"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Archive: $ARCHIVE_PATH"
echo ""

# Verify archive exists
if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ ERROR: Archive not found at $APP_PATH"
  echo "   Run: ./scripts/release/build.sh X.Y.Z"
  echo "   (Do NOT use xc.sh dev-archive - that creates scratch builds)"
  exit 1
fi
echo "✅ Archive verified"

# Open background image for demo recording
BACKGROUND_IMG="$PROJECT_ROOT/build/assets/demo-video-background.jpg"
if [[ -f "$BACKGROUND_IMG" ]]; then
  PREVIEW_WAS_RUNNING=$(pgrep -x "Preview" >/dev/null && echo "yes" || echo "no")
  echo ""
  echo "Background: build/assets/demo-video-background.jpg"
  echo "  Set as desktop background before recording"
  osascript <<EOF
tell application "Preview"
  activate
  open POSIX file "$BACKGROUND_IMG"
  delay 0.3
end tell
EOF
  # Only configure toolbars if Preview wasn't already running
  if [[ "$PREVIEW_WAS_RUNNING" == "no" ]]; then
    osascript <<'EOF'
tell application "System Events"
  tell process "Preview"
    try
      click menu item "Hide Toolbar" of menu "View" of menu bar 1
    end try
    try
      click menu item "Hide Markup Toolbar" of menu "View" of menu bar 1
    end try
  end tell
end tell
EOF
  fi
fi

# Check if archive is stale compared to main branch
echo ""
echo "Checking archive freshness..."
ARCHIVE_MTIME=$(stat -f "%m" "$ARCHIVE_PATH/Info.plist" 2>/dev/null)
if [[ -n "$ARCHIVE_MTIME" ]]; then
  # Get commits on main since archive was built
  ARCHIVE_DATE=$(date -r "$ARCHIVE_MTIME" "+%Y-%m-%d %H:%M:%S")
  COMMITS_SINCE=$(git log main --oneline --since="@$ARCHIVE_MTIME" 2>/dev/null || true)
  if [[ -n "$COMMITS_SINCE" ]]; then
    COMMIT_COUNT=$(echo "$COMMITS_SINCE" | wc -l | tr -d ' ')
  else
    COMMIT_COUNT=0
  fi

  if [[ "$COMMIT_COUNT" -gt 0 ]]; then
    # Check for fix commits specifically
    FIX_COMMITS=$(echo "$COMMITS_SINCE" | grep -i "fix" || true)
    if [[ -n "$FIX_COMMITS" ]]; then
      FIX_COUNT=$(echo "$FIX_COMMITS" | wc -l | tr -d ' ')
    else
      FIX_COUNT=0
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  WARNING: ARCHIVE MAY BE STALE                            ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Archive built: $ARCHIVE_DATE"
    echo "║  Commits on main since then: $COMMIT_COUNT"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$FIX_COUNT" -gt 0 ]]; then
      echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
      echo "🚨  DANGER: $FIX_COUNT FIX COMMIT(S) NOT IN THIS ARCHIVE!      🚨"
      echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
      echo ""
      echo "Fix commits missing from archive:"
      echo "$FIX_COMMITS" | sed 's/^/  /'
      echo ""
    fi

    echo "Recent commits not in archive:"
    echo "$COMMITS_SINCE" | head -10 | sed 's/^/  /'
    if [[ "$COMMIT_COUNT" -gt 10 ]]; then
      echo "  ... and $((COMMIT_COUNT - 10)) more"
    fi
    echo ""
    echo "To rebuild: ./scripts/release/build.sh $VERSION --skip-dmg"
    echo ""
    echo "Press Enter to continue anyway, or Ctrl+C to abort and rebuild..."
    read -r
  else
    echo "✅ Archive is up-to-date with main branch"
  fi
else
  echo "⚠️  Could not determine archive build time"
fi
pause

# STEP 1: Backup, clean state, reset permissions (all automated)
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 1: Prepare Environment"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# --- Backup real data ---
SAMPLE_PATTERN="sample-projects"
CURRENT_HAS_REAL=false

if [[ -d ~/.claude/projects ]]; then
  if ls ~/.claude/projects/ 2>/dev/null | grep -v "$SAMPLE_PATTERN" | grep -q .; then
    CURRENT_HAS_REAL=true
  fi
fi

if [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$CURRENT_HAS_REAL" == "true" ]]; then
    CURRENT_COUNT=$(ls ~/.claude/projects/ 2>/dev/null | grep -v "$SAMPLE_PATTERN" | wc -l | tr -d ' ')
    echo "⚠️  Merging $CURRENT_COUNT new projects into existing backup..."
    cp -rn ~/.claude/projects/* ~/.claude/projects-REAL-BACKUP/ 2>/dev/null || true
  fi
  echo "✓ Backup: ~/.claude/projects-REAL-BACKUP ($BACKUP_COUNT projects)"
else
  mv ~/.claude/projects ~/.claude/projects-REAL-BACKUP 2>/dev/null || true
  mv ~/.codex/sessions ~/.codex/sessions-REAL-BACKUP 2>/dev/null || true
  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
  echo "✓ Backed up $BACKUP_COUNT projects"
fi

# --- Install sample data ---
rm -rf ~/.claude/projects ~/.codex/sessions
mkdir -p ~/.claude/projects ~/.codex/sessions
cp -r appstore-metadata/review-materials/sample-transcripts/claude/projects/* ~/.claude/projects/
cp -r appstore-metadata/review-materials/sample-transcripts/codex/sessions/* ~/.codex/sessions/
echo "✓ Sample data: $(ls ~/.claude/projects/ | tr '\n' ' ')"

# --- Create stub project directories ---
mkdir -p ~/code/sample-projects/{taskflow,recipebox,weatherly}
for dir in ~/code/sample-projects/{taskflow,recipebox,weatherly}; do
  if [ ! -d "$dir/.git" ]; then
    git -C "$dir" init -q
    echo "# Sample Project" > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m "Initial commit"
  fi
done
echo "✓ Stub dirs: ~/code/sample-projects/{taskflow,recipebox,weatherly}"

# --- Quit app ---
osascript -e 'tell application "Contextify" to quit' >/dev/null 2>&1 || true
pkill -x Contextify >/dev/null 2>&1 || true
sleep 1
echo "✓ App quit"

# --- Clean database ---
CONTEXTIFY_DIST=appstore "$PROJECT_ROOT/scripts/db_manager.sh" clean --force >/dev/null 2>&1
echo "✓ Database cleaned"

# --- Clean caches/preferences ---
clean_caches_for_bid "$BUNDLE_ID"
clean_userdefaults_for_bid "$BUNDLE_ID"
echo "✓ Caches/prefs cleared"

# --- Reset TCC ---
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
echo "✓ TCC permissions reset (dialog will appear on launch)"

echo ""
pause

# STEP 2: Install to Applications
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 2: Install App"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Installing to /Applications..."
rm -rf /Applications/Contextify.app 2>/dev/null || true
cp -R "$APP_PATH" /Applications/
echo "✓ Installed: /Applications/Contextify.app"

# Offer to add to Dock (default: no)
echo ""
echo "Add to Dock? (y/N)"
read -r add_dock
if [[ "$add_dock" == "y" || "$add_dock" == "Y" ]]; then
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Contextify.app</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
  killall Dock
  sleep 2
  echo "✓ Added to Dock"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 3: Start Screen Recording and Perform Demo"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  DEMO CHECKLIST                                               ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  1. Permission dialog    │  5. Search (Cmd+F)                 ║"
echo "║  2. Project tabs         │  6. Deep search (Cmd+Shift+F)      ║"
echo "║  3. Timeline scroll      │  7. Real-time: claude in terminal  ║"
echo "║  4. LLM summaries        │  8. Settings (Cmd+,)               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Launch: open /Applications/Contextify.app"
echo "Real-time demo: cd ~/code/sample-projects/taskflow && claude"
echo ""

# Demo video output path - use drafts folder, auto-increment filename
DRAFTS_DIR="$PROJECT_ROOT/website/review-4a125b1d/drafts"
mkdir -p "$DRAFTS_DIR"

# Find next available filename
COUNTER=1
while [[ -f "$DRAFTS_DIR/demo-recording-$COUNTER.mov" ]]; do
  COUNTER=$((COUNTER + 1))
done
DEMO_VIDEO="$DRAFTS_DIR/demo-recording-$COUNTER.mov"

echo "Start recording? (Y/n)"
echo "  Output: $DEMO_VIDEO"
read -r start_rec
if [[ "$start_rec" != "n" && "$start_rec" != "N" ]]; then
  echo ""
  echo "Recording #$COUNTER..."
  echo ""
  # -v = video, -k = show clicks, -C = capture cursor
  # Run in background, suppress its prompt, use our own stop prompt
  screencapture -v -k -C "$DEMO_VIDEO" 2>/dev/null &
  SCREENCAP_PID=$!
  sleep 1  # Let screencapture initialize

  echo "Stop recording? (Y/n)"
  read -r stop_rec

  # Kill screencapture
  kill "$SCREENCAP_PID" 2>/dev/null || true
  wait "$SCREENCAP_PID" 2>/dev/null || true

  echo ""
  if [[ -f "$DEMO_VIDEO" ]]; then
    echo "✓ Recording saved: $DEMO_VIDEO"
  else
    echo "⚠️  Recording may have failed. Check $DRAFTS_DIR/"
  fi
else
  echo ""
  echo "Manual: QuickTime > File > New Screen Recording"
  echo "Save to: $DRAFTS_DIR/"
fi

echo ""
echo "Post-production: Crop/trim in iMovie or QuickTime, export to:"
echo "  website/review-4a125b1d/demo-video.mp4"

# Step 4: Restore
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 4: Restore Real Data"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Restore real transcripts? (Y/n)"
read -r confirm

if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
  do_restore
else
  echo ""
  echo "Skipped. Run later: ./scripts/release/demo-recording.sh --restore"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  NEXT STEPS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. Post-production:"
echo "   - Open draft in iMovie or QuickTime"
echo "   - Crop to app window, trim start/end"
echo "   - Export as MP4 to: website/review-4a125b1d/demo-video.mp4"
echo ""
echo "2. Deploy: ./scripts/deploy-website.sh"
echo "3. Upload: bash scripts/xc.sh upload"
echo "4. Submit in App Store Connect"
echo ""
echo "Done!"
