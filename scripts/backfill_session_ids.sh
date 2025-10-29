#!/bin/bash
#
# Backfill provider_session_id for Claude Code transcripts
#
# Issue: Existing transcripts have NULL provider_session_id, causing
# UNIQUE constraint violations during discovery because the lookup
# by (provider, provider_session_id) fails to find existing records.
#
# Solution: Extract session ID from file_path for all Claude Code
# transcripts where provider_session_id is NULL or empty.

set -euo pipefail

DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    exit 1
fi

echo "📊 Checking for transcripts with NULL/empty provider_session_id..."

# Count transcripts that need backfilling
NULL_COUNT=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE provider = 'claude.code'
  AND (provider_session_id IS NULL OR provider_session_id = '')
")

echo "Found $NULL_COUNT Claude Code transcripts with NULL/empty provider_session_id"

if [ "$NULL_COUNT" = "0" ]; then
    echo "✅ No backfill needed"
    exit 0
fi

echo ""
echo "Sample transcripts that will be updated:"
sqlite3 "$DB_PATH" "
SELECT
  SUBSTR(id, 1, 8) || '...' as id,
  SUBSTR(file_path, -50) as file_path
FROM transcripts
WHERE provider = 'claude.code'
  AND (provider_session_id IS NULL OR provider_session_id = '')
LIMIT 5
" -header -column

echo ""
read -p "Backfill provider_session_id for $NULL_COUNT transcripts? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 0
fi

# Create backup first
BACKUP_DIR="$HOME/code/projects/contextify/build/db-backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_PATH="$BACKUP_DIR/transcripts.db-pre-sessionid-backfill-$TIMESTAMP"

echo "📦 Creating backup: $BACKUP_PATH"
cp "$DB_PATH" "$BACKUP_PATH"

echo "🔧 Backfilling provider_session_id..."

# Extract session ID from file_path
# Example: /path/to/24388147-2814-4c8d-9b04-78a50ae06ac1.jsonl
#          → 24388147-2814-4c8d-9b04-78a50ae06ac1

# Use a simpler approach: iterate through each record in a loop
sqlite3 "$DB_PATH" "
SELECT id, file_path
FROM transcripts
WHERE provider = 'claude.code'
  AND (provider_session_id IS NULL OR provider_session_id = '')
" | while IFS='|' read -r id filepath; do
  # Extract filename using basename
  filename=$(basename "$filepath")
  # Remove .jsonl extension
  session_id="${filename%.jsonl}"

  # Update the record
  sqlite3 "$DB_PATH" "
    UPDATE transcripts
    SET provider_session_id = '$session_id'
    WHERE id = '$id'
  "
done

echo "✅ Backfill complete!"

# Show summary
UPDATED=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE provider = 'claude.code'
  AND provider_session_id IS NOT NULL
  AND provider_session_id != ''
")

echo "Updated: $UPDATED transcripts now have provider_session_id"

# Verify no NULLs remain
REMAINING=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE provider = 'claude.code'
  AND (provider_session_id IS NULL OR provider_session_id = '')
")

echo "Remaining NULL/empty: $REMAINING"

echo ""
echo "✅ Done! Backup saved to:"
echo "   $BACKUP_PATH"
echo ""
echo "Next steps:"
echo "1. Restart Contextify: killall Contextify && bash scripts/xc.sh build"
echo "2. Discovery should now work without UNIQUE constraint errors"
