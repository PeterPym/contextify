#!/bin/bash
# Multi-dimensional transcript classification
#
# Usage:
#   ./scripts/classify_transcript_detailed.sh <file_path_or_transcript_id>
#
# Returns JSON with multi-dimensional classification:
#   - primary: conversational | metadata-only | sidechain-only | empty
#   - metadata_axes: has_snapshots, has_events, has_summaries, has_usage
#   - content_axes: has_sidechain, has_meta, has_tool_use, has_thinking, has_images
#   - state: active | unavailable | error | unprocessed

set -euo pipefail

source "$(dirname "$0")/../lib/db_location.sh"

# Database discovery (override with DB_PATH env var if needed)
if [ -z "${DB_PATH:-}" ]; then
  if DB_DIR=$(get_contextify_db_dir); then
    DB_PATH="$DB_DIR/contextify.db"
  fi
fi

if [ $# -eq 0 ]; then
  echo "Usage: $0 <file_path_or_transcript_id>"
  exit 1
fi

INPUT="$1"

# Resolve transcript ID to file path if needed
if [[ "$INPUT" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
  if [ ! -f "$DB_PATH" ]; then
    LEGACY_PATH="$(dirname "$DB_PATH")/transcripts.db"
    if [ -f "$LEGACY_PATH" ]; then
      DB_PATH="$LEGACY_PATH"
    else
      echo "{\"error\": \"Database not found\", \"path\": \"$DB_PATH\"}"
      exit 1
    fi
  fi
  FILE_PATH=$(sqlite3 "$DB_PATH" "SELECT file_path FROM transcripts WHERE id = '$INPUT';" 2>/dev/null || echo "")
  if [ -z "$FILE_PATH" ]; then
    echo "{\"error\": \"Transcript ID not found\", \"id\": \"$INPUT\"}"
    exit 1
  fi
  TRANSCRIPT_ID="$INPUT"
else
  FILE_PATH="$INPUT"
  TRANSCRIPT_ID=""
fi

if [ ! -f "$FILE_PATH" ]; then
  echo "{\"error\": \"File not found\", \"path\": \"$FILE_PATH\"}"
  exit 1
fi

# Get database state if we have transcript ID
DB_STATE="unknown"
DB_ENTRY_COUNT=0
DB_SNAPSHOT_COUNT=0
DB_EVENT_COUNT=0
DB_SUMMARY_COUNT=0

if [ -n "$TRANSCRIPT_ID" ] && [ -f "$DB_PATH" ]; then
  DB_STATE=$(sqlite3 "$DB_PATH" "SELECT status FROM transcripts WHERE id = '$TRANSCRIPT_ID';" 2>/dev/null || echo "unknown")
  DB_ENTRY_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '$TRANSCRIPT_ID' AND display_in_timeline = 1;" 2>/dev/null || echo "0")
  DB_SNAPSHOT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM file_snapshots WHERE transcript_id = '$TRANSCRIPT_ID';" 2>/dev/null || echo "0")
  DB_EVENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM system_events WHERE transcript_id = '$TRANSCRIPT_ID';" 2>/dev/null || echo "0")
  DB_SUMMARY_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_summaries WHERE transcript_id = '$TRANSCRIPT_ID';" 2>/dev/null || echo "0")
fi

# Analyze file content (sample first 100 lines for performance)
SAMPLE=$(head -100 "$FILE_PATH" 2>/dev/null || echo "")
LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")

if [ -z "$SAMPLE" ] || [ "$LINE_COUNT" -eq 0 ]; then
  cat <<EOF
{
  "file": "$FILE_PATH",
  "line_count": 0,
  "primary_classification": "empty",
  "state": "$DB_STATE",
  "dimensions": {
    "metadata": {"snapshots": 0, "events": 0, "summaries": 0},
    "content": {},
    "database": {"entry_count": 0, "ingested": false}
  }
}
EOF
  exit 0
fi

# Detect provider
PROVIDER="unknown"
if echo "$SAMPLE" | jq -e 'select(.type == "file-history-snapshot")' >/dev/null 2>&1; then
  PROVIDER="claude-code"
elif echo "$SAMPLE" | jq -e 'select(.type == "session_meta")' >/dev/null 2>&1; then
  PROVIDER="codex-cli"
elif echo "$SAMPLE" | jq -e 'select(has("uuid") and has("sessionId"))' >/dev/null 2>&1; then
  PROVIDER="claude-code"
fi

# Count record types
RECORD_TYPES=$(echo "$SAMPLE" | jq -r '.type' 2>/dev/null | sort | uniq -c | awk '{printf "%s:%s,", $2, $1}' | sed 's/,$//')

# Analyze dimensions
HAS_USER_CONV=false
HAS_ASSISTANT=false
HAS_SIDECHAIN=false
HAS_META=false
HAS_FILE_SNAPSHOT=false
HAS_SUMMARY=false
HAS_SYSTEM=false
HAS_TOOL_USE=false
HAS_THINKING=false
HAS_IMAGES=false

# Check for conversational content (non-sidechain, non-meta)
if echo "$SAMPLE" | jq -e 'select(.type == "user" and (.isSidechain // false) == false and (.isMeta // false) == false)' >/dev/null 2>&1; then
  HAS_USER_CONV=true
fi

# Check for non-sidechain assistant messages
if echo "$SAMPLE" | jq -e 'select(.type == "assistant" and (.isSidechain // false) == false)' >/dev/null 2>&1; then
  HAS_ASSISTANT=true
fi

# Check special flags
if echo "$SAMPLE" | jq -e 'select(.isSidechain == true)' >/dev/null 2>&1; then
  HAS_SIDECHAIN=true
fi

if echo "$SAMPLE" | jq -e 'select(.isMeta == true)' >/dev/null 2>&1; then
  HAS_META=true
fi

# Check metadata types
if echo "$SAMPLE" | jq -e 'select(.type == "file-history-snapshot")' >/dev/null 2>&1; then
  HAS_FILE_SNAPSHOT=true
fi

if echo "$SAMPLE" | jq -e 'select(.type == "summary")' >/dev/null 2>&1; then
  HAS_SUMMARY=true
fi

if echo "$SAMPLE" | jq -e 'select(.type == "system")' >/dev/null 2>&1; then
  HAS_SYSTEM=true
fi

# Check content types
if echo "$SAMPLE" | jq -e 'select(.message.content[]?.type == "tool_use")' >/dev/null 2>&1; then
  HAS_TOOL_USE=true
fi

if echo "$SAMPLE" | jq -e 'select(.message.content[]?.type == "thinking")' >/dev/null 2>&1; then
  HAS_THINKING=true
fi

if echo "$SAMPLE" | jq -e 'select(.message.content[]?.type == "image")' >/dev/null 2>&1; then
  HAS_IMAGES=true
fi

# Determine primary classification
PRIMARY="unknown"

if $HAS_USER_CONV || $HAS_ASSISTANT; then
  PRIMARY="conversational"
elif $HAS_SIDECHAIN && ! $HAS_USER_CONV && ! $HAS_ASSISTANT; then
  PRIMARY="sidechain-only"
elif $HAS_FILE_SNAPSHOT || $HAS_SUMMARY || $HAS_SYSTEM; then
  PRIMARY="metadata-only"
else
  PRIMARY="empty"
fi

# Build JSON output
cat <<EOF
{
  "file": "$FILE_PATH",
  "provider": "$PROVIDER",
  "line_count": $LINE_COUNT,
  "primary_classification": "$PRIMARY",
  "state": "$DB_STATE",
  "dimensions": {
    "conversation": {
      "has_user": $HAS_USER_CONV,
      "has_assistant": $HAS_ASSISTANT,
      "db_entry_count": $DB_ENTRY_COUNT
    },
    "metadata": {
      "has_snapshots": $HAS_FILE_SNAPSHOT,
      "has_summaries": $HAS_SUMMARY,
      "has_events": $HAS_SYSTEM,
      "db_snapshot_count": $DB_SNAPSHOT_COUNT,
      "db_event_count": $DB_EVENT_COUNT,
      "db_summary_count": $DB_SUMMARY_COUNT
    },
    "content_flags": {
      "has_sidechain": $HAS_SIDECHAIN,
      "has_meta": $HAS_META,
      "has_tool_use": $HAS_TOOL_USE,
      "has_thinking": $HAS_THINKING,
      "has_images": $HAS_IMAGES
    }
  },
  "record_type_counts": "$RECORD_TYPES",
  "analysis_note": "Sampled first 100 lines of $LINE_COUNT total"
}
EOF
