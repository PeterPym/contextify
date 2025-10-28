#!/bin/bash
# Clean up FK violations before enabling PRAGMA foreign_keys
# Run this if app fails to start with FK constraint errors

set -e

DB_PATH=~/Library/Application\ Support/Contextify/transcripts.db

echo "Backing up database first..."
./scripts/db_manager.sh backup

echo "Cleaning up orphaned assistant_usage records..."
sqlite3 "$DB_PATH" "DELETE FROM assistant_usage WHERE entry_id NOT IN (SELECT id FROM transcript_entries);"

echo "Cleaning up orphaned timeline_cache records..."
sqlite3 "$DB_PATH" "DELETE FROM timeline_cache WHERE entry_id NOT IN (SELECT id FROM transcript_entries);"

echo "Verifying integrity..."
sqlite3 "$DB_PATH" "PRAGMA integrity_check;" | head -1

echo "✓ Database cleaned. App can now start and run pending migrations."
