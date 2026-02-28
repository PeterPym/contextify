#!/bin/bash
#
# Convert empty string provider_session_id to NULL
#
# Issue: Records have provider_session_id = '' (empty string) which
# violates the UNIQUE constraint when multiple records exist.
# The UNIQUE index excludes NULL values, so we need to convert
# empty strings to NULL.

set -euo pipefail

DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    exit 1
fi

echo "📊 Checking for empty string provider_session_id..."

EMPTY_COUNT=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE provider_session_id = ''
")

echo "Found $EMPTY_COUNT transcripts with empty string provider_session_id"

if [ "$EMPTY_COUNT" = "0" ]; then
    echo "✅ No empty strings to fix"
    exit 0
fi

# Create backup
BACKUP_DIR="$HOME/code/projects/contextify/build/db-backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_PATH="$BACKUP_DIR/transcripts.db-pre-empty-string-fix-$TIMESTAMP"

echo "📦 Creating backup: $BACKUP_PATH"
cp "$DB_PATH" "$BACKUP_PATH"

echo "🔧 Converting empty strings to NULL..."

sqlite3 "$DB_PATH" <<'SQL'
BEGIN TRANSACTION;

-- Convert empty string to NULL
UPDATE transcripts
SET provider_session_id = NULL
WHERE provider_session_id = '';

COMMIT;
SQL

echo "✅ Fix complete!"

# Verify
REMAINING=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE provider_session_id = ''
")

echo "Remaining empty strings: $REMAINING"
echo "✅ Done! Backup saved to: $BACKUP_PATH"
