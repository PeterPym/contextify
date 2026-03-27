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
TMP_SNAPSHOT="${SNAPSHOT_PATH}.tmp"

# Use sqlite3 .backup for WAL-safe consistent snapshot
echo "Creating consistent SQLite backup..."
rm -f "$TMP_SNAPSHOT"
sqlite3 "$PROD_DB" ".timeout 5000" ".backup '$TMP_SNAPSHOT'"
chmod 444 "$TMP_SNAPSHOT"
mv -f "$TMP_SNAPSHOT" "$SNAPSHOT_PATH"

# Print manifest info
ENTRIES=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM transcript_entries")
PROJECTS=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM projects")
TRANSCRIPTS=$(sqlite3 "$SNAPSHOT_PATH" "SELECT COUNT(*) FROM transcripts")
SIZE=$(du -h "$SNAPSHOT_PATH" | cut -f1)
HASH_PREFIX=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print substr($1, 1, 16)}')

echo ""
echo "Snapshot created:"
echo "  Path: $SNAPSHOT_PATH"
echo "  Size: $SIZE"
echo "  Entries: $ENTRIES"
echo "  Projects: $PROJECTS"
echo "  Transcripts: $TRANSCRIPTS"
echo "  Hash prefix: $HASH_PREFIX"
echo ""
echo "Update scripts/benchmark/snapshot-manifest.json with hash_prefix: $HASH_PREFIX"
