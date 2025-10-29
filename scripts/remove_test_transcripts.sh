#!/bin/bash
#
# Remove test transcripts and their database entries
#
# Removes:
# - Test transcripts from -tmp-test-project
# - TEST-CONVERT.jsonl from contextify project
# - Associated database entries and transcript_entries

set -euo pipefail

DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at: $DB_PATH"
    exit 1
fi

echo "🔍 Finding test transcripts..."

# List what will be deleted
echo ""
echo "Files to be removed:"
echo "  ~/.claude/projects/-tmp-test-project/test-roundtrip-session.jsonl"
echo "  ~/.claude/projects/-tmp-test-project/test-session-12345.jsonl"
echo "  ~/.claude/projects/-Users-rob-code-projects-contextify/TEST-CONVERT.jsonl"

echo ""
echo "Database entries to be removed:"
sqlite3 "$DB_PATH" "
SELECT
  t.id,
  p.name as project,
  t.file_path
FROM transcripts t
JOIN projects p ON p.id = t.project_id
WHERE t.file_path LIKE '%test-%'
   OR t.file_path LIKE '%TEST-%'
ORDER BY t.file_path;
" -header -column

echo ""
read -p "Remove these test transcripts? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 0
fi

# Create backup
BACKUP_DIR="$HOME/code/projects/contextify/build/db-backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_PATH="$BACKUP_DIR/transcripts.db-pre-test-cleanup-$TIMESTAMP"

echo "📦 Creating backup: $BACKUP_PATH"
cp "$DB_PATH" "$BACKUP_PATH"

# Delete from database
echo "🗑️  Removing database entries..."
sqlite3 "$DB_PATH" <<'SQL'
BEGIN TRANSACTION;

-- Delete transcript entries first (FK constraint)
DELETE FROM transcript_entries
WHERE transcript_id IN (
  SELECT id FROM transcripts
  WHERE file_path LIKE '%test-%'
     OR file_path LIKE '%TEST-%'
);

-- Delete transcripts
DELETE FROM transcripts
WHERE file_path LIKE '%test-%'
   OR file_path LIKE '%TEST-%';

COMMIT;
SQL

# Delete files
echo "🗑️  Removing files..."
rm -f ~/.claude/projects/-tmp-test-project/test-roundtrip-session.jsonl
rm -f ~/.claude/projects/-tmp-test-project/test-session-12345.jsonl
rm -f ~/.claude/projects/-Users-rob-code-projects-contextify/TEST-CONVERT.jsonl

# Try to remove empty directory
rmdir ~/.claude/projects/-tmp-test-project 2>/dev/null && echo "  Removed empty test directory" || true

echo "✅ Test transcripts removed!"
echo "Backup saved to: $BACKUP_PATH"
