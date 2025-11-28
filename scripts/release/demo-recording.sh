#!/bin/bash
# Contextify Demo Recording - Interactive Steps
# Run: ./scripts/release/demo-recording.sh [version]
# Example: ./scripts/release/demo-recording.sh 1.0.0-build4

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Version can be passed as argument or defaults to latest archive
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  # Find latest archive
  LATEST=$(ls -t build/archives/ 2>/dev/null | head -1)
  if [[ -z "$LATEST" ]]; then
    echo "❌ No archives found in build/archives/"
    echo "   Run: bash scripts/xc.sh --dist=appstore Release archive"
    exit 1
  fi
  ARCHIVE_PATH="build/archives/$LATEST"
else
  ARCHIVE_PATH="build/archives/v${VERSION}.xcarchive"
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Contextify.app"
BUNDLE_ID="sh.contextify.Contextify"
SANDBOX_CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
SANDBOX_APP_SUPPORT="$SANDBOX_CONTAINER/Data/Library/Application Support/Contextify"

pause() {
  echo ""
  echo "Press Enter to continue..."
  read -r
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
  echo "   Run: bash scripts/xc.sh --dist=appstore Release archive"
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
if [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
  echo "✅ Backup exists at ~/.claude/projects-REAL-BACKUP"
  BACKUP_COUNT=$(ls ~/.claude/projects-REAL-BACKUP/ 2>/dev/null | wc -l | tr -d ' ')
  echo "   ($BACKUP_COUNT project directories preserved)"
else
  echo "Backing up real transcripts..."
  mv ~/.claude/projects ~/.claude/projects-REAL-BACKUP 2>/dev/null || true
  mv ~/.codex/sessions ~/.codex/sessions-REAL-BACKUP 2>/dev/null || true
  echo "✅ Backed up to ~/.claude/projects-REAL-BACKUP"
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
pause

# Step 2: Clean SANDBOXED database (App Store build uses container)
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 2: Clean Sandboxed Database"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "App Store builds use sandboxed container at:"
echo "  $SANDBOX_APP_SUPPORT"
echo ""
if [[ -d "$SANDBOX_APP_SUPPORT" ]]; then
  echo "Removing sandboxed database and state..."
  rm -rf "$SANDBOX_APP_SUPPORT"
  echo "✅ Sandboxed database cleaned"
else
  echo "ℹ️  No sandboxed database found (fresh install)"
fi
pause

# Step 3: Reset TCC permissions (so permission dialogs appear)
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 3: Reset TCC Permissions"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Resetting macOS privacy permissions for $BUNDLE_ID..."
echo "This ensures the permission dialog appears on launch."
echo ""
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
echo "✅ TCC permissions reset"
echo ""
echo "NOTE: You should see a permission dialog when the app launches."
pause

# Step 4: Launch app
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 4: Launch Archived App"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Launching App Store archive build from:"
echo ""
echo "  $APP_PATH"
echo ""
echo "This is the EXACT binary that will be submitted to Apple."
echo ""
open "$APP_PATH"
echo "✅ App launched"
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
echo "  - If not shown, quit app and re-launch: open \"$APP_PATH\""
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
  echo ""
  echo "✅ Real transcripts restored!"
  echo ""
  echo "You can now resume using Claude Code and Codex."
else
  echo ""
  echo "Skipped restore. Run manually when ready:"
  echo "  rm -rf ~/.claude/projects ~/.codex/sessions"
  echo "  mv ~/.claude/projects-REAL-BACKUP ~/.claude/projects"
  echo "  mv ~/.codex/sessions-REAL-BACKUP ~/.codex/sessions"
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
