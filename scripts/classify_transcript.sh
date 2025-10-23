#!/bin/bash
# Classify a transcript file by examining its structure
#
# Usage:
#   ./scripts/classify_transcript.sh <file_path>
#   ./scripts/classify_transcript.sh <transcript_id>
#
# Returns JSON with:
#   - type: "claude-code" | "codex-cli" | "unknown"
#   - has_conversation: boolean
#   - has_metadata: boolean
#   - record_types: array of record types found
#   - classification: "conversational" | "metadata-only" | "empty"

set -euo pipefail

# Database location
DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

# Argument handling
if [ $# -eq 0 ]; then
  echo "Usage: $0 <file_path_or_transcript_id>"
  exit 1
fi

INPUT="$1"

# Determine if input is a transcript ID (UUID format) or file path
if [[ "$INPUT" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
  # It's a transcript ID - look up the file path
  if [ ! -f "$DB_PATH" ]; then
    echo "{\"error\": \"Database not found\", \"path\": \"$DB_PATH\"}"
    exit 1
  fi

  FILE_PATH=$(sqlite3 "$DB_PATH" "SELECT file_path FROM transcripts WHERE id = '$INPUT';" 2>/dev/null || echo "")

  if [ -z "$FILE_PATH" ]; then
    echo "{\"error\": \"Transcript ID not found\", \"id\": \"$INPUT\"}"
    exit 1
  fi
else
  FILE_PATH="$INPUT"
fi

# Verify file exists
if [ ! -f "$FILE_PATH" ]; then
  echo "{\"error\": \"File not found\", \"path\": \"$FILE_PATH\"}"
  exit 1
fi

# Analyze first 50 lines to determine type and structure
SAMPLE=$(head -50 "$FILE_PATH" 2>/dev/null || echo "")

if [ -z "$SAMPLE" ]; then
  echo "{\"type\": \"unknown\", \"classification\": \"empty\", \"file\": \"$FILE_PATH\"}"
  exit 0
fi

# Determine provider type
PROVIDER="unknown"
if echo "$SAMPLE" | jq -e 'select(.type == "file-history-snapshot")' >/dev/null 2>&1; then
  PROVIDER="claude-code"
elif echo "$SAMPLE" | jq -e 'select(.type == "session_meta")' >/dev/null 2>&1; then
  PROVIDER="codex-cli"
elif echo "$SAMPLE" | jq -e 'select(has("uuid") and has("sessionId"))' >/dev/null 2>&1; then
  PROVIDER="claude-code"
fi

# Count record types
RECORD_TYPES=$(echo "$SAMPLE" | jq -r '.type' 2>/dev/null | sort -u | jq -R . | jq -s .)

# Check for conversation vs metadata
HAS_USER=false
HAS_ASSISTANT=false
HAS_METADATA=false

if echo "$SAMPLE" | jq -e 'select(.type == "user" and (.isSidechain // false) == false and (.isMeta // false) == false)' >/dev/null 2>&1; then
  HAS_USER=true
fi

if echo "$SAMPLE" | jq -e 'select(.type == "assistant")' >/dev/null 2>&1; then
  HAS_ASSISTANT=true
fi

if echo "$SAMPLE" | jq -e 'select(.type == "file-history-snapshot" or .type == "summary" or .type == "system")' >/dev/null 2>&1; then
  HAS_METADATA=true
fi

# Classify transcript
CLASSIFICATION="unknown"
if $HAS_USER || $HAS_ASSISTANT; then
  CLASSIFICATION="conversational"
elif $HAS_METADATA; then
  CLASSIFICATION="metadata-only"
else
  # Check if file has any content
  LINE_COUNT=$(wc -l < "$FILE_PATH")
  if [ "$LINE_COUNT" -eq 0 ]; then
    CLASSIFICATION="empty"
  else
    CLASSIFICATION="unknown"
  fi
fi

# Build JSON output
cat <<EOF
{
  "file": "$FILE_PATH",
  "type": "$PROVIDER",
  "classification": "$CLASSIFICATION",
  "has_conversation": $(if $HAS_USER || $HAS_ASSISTANT; then echo "true"; else echo "false"; fi),
  "has_metadata": $HAS_METADATA,
  "record_types": $RECORD_TYPES,
  "line_count": $(wc -l < "$FILE_PATH")
}
EOF
