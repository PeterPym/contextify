#!/usr/bin/env bash
# Prepare a frozen DB snapshot for the Total Recall benchmark.
# Run this once to create the snapshot, or again to refresh it.
#
# The snapshot is stored outside the repo (too large for git) at:
#   ~/Library/Application Support/Contextify/benchmark/contextify-benchmark-v1.db
#
# Each benchmark run copies this to /tmp/ and uses --db-path.
#
# Tagged transcript exclusion (ct-814):
#   Transcripts tagged with "benchmark" or "evaluation" in the transcript_tags
#   table are excluded from snapshots by default. This prevents meta-entries
#   from prior search/evaluation sessions contaminating MRR scores.
#   Use --no-exclude-tags to skip this filtering.

set -euo pipefail

SNAPSHOT_DIR="$HOME/Library/Application Support/Contextify/benchmark"
PROD_DB="$HOME/Library/Application Support/Contextify/contextify.db"
VERSION=1
SNAPSHOT_PATH="$SNAPSHOT_DIR/contextify-benchmark-v${VERSION}.db"
EXCLUDE_TAGS=true
DEFAULT_EXCLUDED_TAGS="benchmark,evaluation"
# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-exclude-tags)
      EXCLUDE_TAGS=false; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$PROD_DB" ]; then
  echo "Error: Production DB not found at $PROD_DB"
  echo "Open Contextify to initialize the database."
  exit 1
fi

if [ -f "$SNAPSHOT_PATH" ]; then
  echo "Replacing existing snapshot ($(du -h "$SNAPSHOT_PATH" | cut -f1))..."
fi

mkdir -p "$SNAPSHOT_DIR"
TMP_SNAPSHOT="${SNAPSHOT_PATH}.tmp"

# Use sqlite3 .backup for WAL-safe consistent snapshot
echo "Creating consistent SQLite backup..."
rm -f "$TMP_SNAPSHOT"
sqlite3 "$PROD_DB" ".timeout 5000" ".backup '$TMP_SNAPSHOT'"

# Exclude tagged transcripts (ct-814)
if [ "$EXCLUDE_TAGS" = "true" ]; then
  # Check if transcript_tags table exists (only present after v39 migration)
  HAS_TAGS_TABLE=$(sqlite3 "$TMP_SNAPSHOT" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='transcript_tags'")
  if [ "$HAS_TAGS_TABLE" -gt 0 ]; then
    IFS=',' read -ra TAGS <<< "$DEFAULT_EXCLUDED_TAGS"
    PLACEHOLDERS=""
    for tag in "${TAGS[@]}"; do
      tag_trimmed="$(echo "$tag" | xargs)"
      if [ -n "$PLACEHOLDERS" ]; then PLACEHOLDERS="${PLACEHOLDERS},"; fi
      PLACEHOLDERS="${PLACEHOLDERS}'${tag_trimmed}'"
    done

    TAGGED_COUNT=$(sqlite3 "$TMP_SNAPSHOT" "SELECT COUNT(DISTINCT transcript_id) FROM transcript_tags WHERE tag IN ($PLACEHOLDERS)")
    if [ "$TAGGED_COUNT" -gt 0 ]; then
      echo "Excluding $TAGGED_COUNT tagged transcript(s) (tags: $DEFAULT_EXCLUDED_TAGS)..."
      EXCLUDED_ENTRIES=$(sqlite3 "$TMP_SNAPSHOT" "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id IN (SELECT DISTINCT transcript_id FROM transcript_tags WHERE tag IN ($PLACEHOLDERS))")
      sqlite3 "$TMP_SNAPSHOT" <<EOSQL
DELETE FROM transcript_entries WHERE transcript_id IN (
  SELECT DISTINCT transcript_id FROM transcript_tags WHERE tag IN ($PLACEHOLDERS)
);
DELETE FROM transcript_entries_fts WHERE entry_id NOT IN (SELECT id FROM transcript_entries);
DELETE FROM transcripts WHERE id IN (
  SELECT DISTINCT transcript_id FROM transcript_tags WHERE tag IN ($PLACEHOLDERS)
);
DELETE FROM transcript_metadata WHERE transcript_id NOT IN (SELECT id FROM transcripts);
DELETE FROM transcript_tags WHERE transcript_id NOT IN (SELECT id FROM transcripts);
VACUUM;
EOSQL
      echo "  Removed $EXCLUDED_ENTRIES entries from $TAGGED_COUNT transcript(s)"
    else
      echo "No tagged transcripts to exclude."
    fi
  else
    echo "No transcript_tags table found (pre-v39 DB), skipping tag exclusion."
  fi
fi

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
