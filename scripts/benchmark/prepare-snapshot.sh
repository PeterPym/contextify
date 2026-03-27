#!/usr/bin/env bash
# Prepare a frozen DB snapshot for the Total Recall benchmark.
# Run this once to create the snapshot, or again to refresh it.
#
# The snapshot is stored outside the repo (too large for git) at:
#   ~/Library/Application Support/Contextify/benchmark/contextify-benchmark-v1.db
#
# Each benchmark run copies this to /tmp/ and uses --db-path.

set -euo pipefail

SNAPSHOT_DIR="$HOME/Library/Application Support/Contextify/benchmark"
PROD_DB="$HOME/Library/Application Support/Contextify/contextify.db"
VERSION=1
SNAPSHOT_PATH="$SNAPSHOT_DIR/contextify-benchmark-v${VERSION}.db"

if [ ! -f "$PROD_DB" ]; then
  echo "Error: Production DB not found at $PROD_DB"
  echo "Open Contextify to initialize the database."
  exit 1
fi

if [ -f "$SNAPSHOT_PATH" ]; then
  echo "Snapshot already exists: $SNAPSHOT_PATH"
  echo "Size: $(du -h "$SNAPSHOT_PATH" | cut -f1)"
  echo ""
  read -p "Replace with fresh snapshot? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Keeping existing snapshot."
    exit 0
  fi
fi

mkdir -p "$SNAPSHOT_DIR"
echo "Copying production DB to snapshot..."
cp "$PROD_DB" "$SNAPSHOT_PATH"
chmod 444 "$SNAPSHOT_PATH"  # read-only to prevent accidental writes

# Print manifest info
ENTRIES=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM transcript_entries")
PROJECTS=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM projects")
TRANSCRIPTS=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM transcripts")
SIZE=$(du -h "$SNAPSHOT_PATH" | cut -f1)

echo ""
echo "Snapshot created:"
echo "  Path: $SNAPSHOT_PATH"
echo "  Size: $SIZE"
echo "  Entries: $ENTRIES"
echo "  Projects: $PROJECTS"
echo "  Transcripts: $TRANSCRIPTS"
echo ""
echo "Update scripts/benchmark/snapshot-manifest.json if version changed."
