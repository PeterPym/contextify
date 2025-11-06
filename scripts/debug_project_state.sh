#!/bin/bash
# Debug project switcher state mismatch

set -euo pipefail

# Find database location
DB_PATH=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null || echo "$HOME/Library/Application Support/Contextify/contextify.db")

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Database not found at: $DB_PATH"
  exit 1
fi

echo "=== Project Switcher State Debug ==="
echo "Database: $DB_PATH"
echo ""

echo "--- All Projects (ordered by display_order) ---"
sqlite3 "$DB_PATH" <<SQL
SELECT
  id,
  name,
  display_order,
  CASE WHEN hidden = 1 THEN '(hidden)' ELSE '' END as hidden_flag,
  CASE WHEN is_orphaned = 1 THEN '(orphaned)' ELSE '' END as orphaned_flag
FROM projects
WHERE hidden = 0
ORDER BY
  CASE WHEN display_order IS NULL THEN 999999 ELSE display_order END,
  created_at;
SQL

echo ""
echo "--- Currently Selected Project ---"
sqlite3 "$DB_PATH" <<SQL
SELECT
  p.id,
  p.name,
  p.root_path,
  ps.selected_at
FROM projects p
LEFT JOIN project_selection ps ON p.id = ps.project_id
WHERE ps.project_id IS NOT NULL
ORDER BY ps.selected_at DESC
LIMIT 1;
SQL

echo ""
echo "--- Recent Project Visits (last 5) ---"
sqlite3 "$DB_PATH" <<SQL
SELECT
  p.name,
  p.id,
  datetime(pv.last_viewed_ts, 'unixepoch') as last_viewed
FROM project_visits pv
JOIN projects p ON pv.project_id = p.id
ORDER BY pv.last_viewed_ts DESC
LIMIT 5;
SQL

echo ""
echo "--- Session Follow Policies ---"
sqlite3 "$DB_PATH" <<SQL
SELECT
  p.name as project,
  fp.session_id,
  fp.follow_mode
FROM follow_policies fp
JOIN projects p ON fp.project_id = p.id;
SQL

echo ""
echo "=== Diagnostic Tips ==="
echo "1. Check if selected project matches the UI active tab"
echo "2. Check if session_id in follow_policies matches expected transcript"
echo "3. Verify display_order matches visual tab order"
echo ""
echo "To fix mismatches, try switching projects in the UI"
