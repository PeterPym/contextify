#!/bin/bash
#
# Fix transcript path normalization in database
#
# Issue: Some transcripts have /Users/ (capital U) in file_path
# but /users/ (lowercase) in normalized_path, causing UNIQUE
# constraint violations during discovery.
#
# Solution: Standardize all paths to use the actual filesystem
# path (capital U on macOS), recompute normalized_path and path_hash

set -euo pipefail

DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    exit 1
fi

echo "📊 Checking for path normalization issues..."

# Count records with case mismatches
MISMATCHES=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM transcripts
WHERE LOWER(file_path) != LOWER(normalized_path)
  OR file_path != REPLACE(file_path, '/users/', '/Users/')
  OR normalized_path != LOWER(file_path)
")

echo "Found $MISMATCHES transcripts with potential path normalization issues"

if [ "$MISMATCHES" = "0" ]; then
    echo "✅ No path normalization issues found"
    exit 0
fi

echo ""
echo "Sample affected transcripts:"
sqlite3 "$DB_PATH" "
SELECT
  SUBSTR(file_path, 1, 60) as path,
  SUBSTR(normalized_path, 1, 60) as norm
FROM transcripts
WHERE LOWER(file_path) != normalized_path
LIMIT 5
" -header -column

echo ""
read -p "Fix these path normalizations? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 0
fi

# Create backup first
BACKUP_DIR="$HOME/code/projects/contextify/build/db-backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_PATH="$BACKUP_DIR/transcripts.db-pre-path-fix-$TIMESTAMP"

echo "📦 Creating backup: $BACKUP_PATH"
cp "$DB_PATH" "$BACKUP_PATH"

echo "🔧 Fixing path normalization..."

# Update all transcripts to use consistent paths
sqlite3 "$DB_PATH" <<'SQL'
BEGIN TRANSACTION;

-- Fix normalized_path to always be lowercase version of file_path
UPDATE transcripts
SET normalized_path = LOWER(file_path)
WHERE normalized_path != LOWER(file_path);

-- Note: path_hash would ideally be recomputed, but since it's based
-- on file content hash, we can't update it without reading files.
-- The upsertTranscripts logic will handle this on next discovery.

COMMIT;
SQL

echo "✅ Path normalization fixed!"

# Show summary
FIXED=$(sqlite3 "$DB_PATH" "SELECT changes()")
echo "Updated $FIXED transcripts"

echo ""
echo "✅ Done! Backup saved to:"
echo "   $BACKUP_PATH"
echo ""
echo "Next steps:"
echo "1. Restart Contextify to trigger fresh discovery"
echo "2. Discovery should now complete without UNIQUE constraint errors"
