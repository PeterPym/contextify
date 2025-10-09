#!/bin/bash
# Migrate AI assistant transcripts from old project path to new project path
# Supports: Claude Code and Codex/AI CLI
#
# Usage: ./scripts/migrate-transcripts.sh <old-path> <new-path>
#
# Example:
#   ./scripts/migrate-transcripts.sh /Users/rob/code/contextify /Users/rob/code/projects/contextify
#
# This script:
# - Creates a timestamped backup of original transcripts
# - Migrates Claude Code transcripts to new location
# - Updates Codex transcripts in-place (with backup)
# - Replaces all instances of old path with new path in content
# - Preserves JSONL structure and timestamps

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
log() {
    echo -e "${GREEN}[migrate]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[warning]${NC} $1"
}

error() {
    echo -e "${RED}[error]${NC} $1"
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    error "Usage: $0 <old-path> <new-path>

Example:
  $0 /Users/rob/code/contextify /Users/rob/code/projects/contextify"
fi

OLD_PATH="$1"
NEW_PATH="$2"

# Normalize paths (remove trailing slashes)
OLD_PATH="${OLD_PATH%/}"
NEW_PATH="${NEW_PATH%/}"

# Convert paths to Claude's directory naming scheme
# Claude uses: ~/.claude/projects/-Users-rob-code-contextify
old_dir_name=$(echo "$OLD_PATH" | sed 's|/|-|g')
new_dir_name=$(echo "$NEW_PATH" | sed 's|/|-|g')

OLD_DIR="$HOME/.claude/projects/$old_dir_name"
NEW_DIR="$HOME/.claude/projects/$new_dir_name"

log "Migration Configuration:"
echo "  Old path: $OLD_PATH"
echo "  New path: $NEW_PATH"
echo "  Old transcript dir: $OLD_DIR"
echo "  New transcript dir: $NEW_DIR"
echo ""

# Check if old directory exists
if [ ! -d "$OLD_DIR" ]; then
    error "Old transcript directory not found: $OLD_DIR"
fi

# Check if old directory has any transcripts
transcript_count=$(ls -1 "$OLD_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$transcript_count" -eq 0 ]; then
    error "No transcript files found in: $OLD_DIR"
fi

log "Found $transcript_count transcript files to migrate"

# Warn if new directory already exists
if [ -d "$NEW_DIR" ]; then
    warn "New transcript directory already exists: $NEW_DIR"
    read -p "Files may be overwritten. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Migration cancelled"
        exit 0
    fi
else
    mkdir -p "$NEW_DIR"
    log "Created new transcript directory: $NEW_DIR"
fi

# Create backup
backup_dir="$HOME/transcript-backup-$(date +%Y%m%d-%H%M%S)"
log "Creating backup..."
mkdir -p "$backup_dir"
cp -r "$OLD_DIR" "$backup_dir/"
log "Backup saved to: $backup_dir"

# Migrate Claude Code transcripts
log "Migrating Claude Code transcripts..."
claude_migrated=0
claude_failed=0

for file in "$OLD_DIR"/*.jsonl; do
    filename=$(basename "$file")

    # Use sed to replace all occurrences of old path with new path
    if sed "s|$OLD_PATH|$NEW_PATH|g" "$file" > "$NEW_DIR/$filename"; then
        claude_migrated=$((claude_migrated + 1))
        echo "  ✓ $filename"
    else
        claude_failed=$((claude_failed + 1))
        warn "Failed to migrate: $filename"
    fi
done

# Migrate Codex transcripts
log "Migrating Codex/AI CLI transcripts..."
codex_dir="$HOME/.codex/sessions"
codex_migrated=0
codex_failed=0

if [ -d "$codex_dir" ]; then
    # Find all JSONL files in Codex sessions directory (including subdirectories)
    while IFS= read -r -d '' file; do
        # Check if file contains session_meta with matching cwd
        if grep -q "\"cwd\":\"$OLD_PATH\"" "$file" 2>/dev/null; then
            filename=$(basename "$file")
            relative_path="${file#$codex_dir/}"

            # Create backup of original file
            backup_file="$backup_dir/codex/$relative_path"
            mkdir -p "$(dirname "$backup_file")"
            cp "$file" "$backup_file"

            # Replace paths in place with backup
            if sed -i.bak "s|$OLD_PATH|$NEW_PATH|g" "$file"; then
                rm -f "$file.bak"
                codex_migrated=$((codex_migrated + 1))
                echo "  ✓ $filename (Codex)"
            else
                codex_failed=$((codex_failed + 1))
                warn "Failed to migrate Codex file: $filename"
            fi
        fi
    done < <(find "$codex_dir" -name "*.jsonl" -type f -print0)

    if [ $codex_migrated -eq 0 ]; then
        log "No Codex transcripts found for old path"
    fi
else
    log "Codex sessions directory not found, skipping Codex migration"
fi

echo ""
log "Migration Summary:"
echo "  ✓ Claude Code: $claude_migrated files"
if [ $codex_migrated -gt 0 ]; then
    echo "  ✓ Codex/AI CLI: $codex_migrated files"
fi
total_migrated=$((claude_migrated + codex_migrated))
total_failed=$((claude_failed + codex_failed))
if [ $total_failed -gt 0 ]; then
    warn "Failed: $total_failed files"
fi
echo "  📦 Backup: $backup_dir"
echo "  📁 Claude Code location: $NEW_DIR"
if [ $codex_migrated -gt 0 ]; then
    echo "  📁 Codex location: $codex_dir (in-place updates)"
fi
echo ""

if [ $total_failed -eq 0 ]; then
    log "Migration completed successfully!"
    echo ""
    echo "Your transcripts are now available at the new project path."
    echo "The old Claude Code transcripts remain at: $OLD_DIR"
    echo ""
    echo "To verify in Contextify:"
    echo "  1. Ensure project root is set to: $NEW_PATH"
    echo "  2. Open Timeline → Show All Transcripts"
    echo "  3. You should see $total_migrated transcript(s)"
else
    warn "Migration completed with errors. Check failed files manually."
fi
