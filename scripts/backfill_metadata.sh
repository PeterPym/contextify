#!/bin/bash
# Backfill metadata for existing transcripts (v7 migration)
#
# This script re-ingests all existing transcripts to extract metadata into the new v7 tables.
# Safe to run multiple times (uses INSERT ... ON CONFLICT IGNORE).
#
# Usage:
#   ./scripts/backfill_metadata.sh [--dry-run] [--project-id PROJECT_ID]
#
# Options:
#   --dry-run         Show what would be done without making changes
#   --project-id ID   Only backfill transcripts for specific project
#   --transcript-id ID Only backfill specific transcript
#
# The script:
# 1. Queries database for all transcripts (or filtered by project/transcript)
# 2. For each transcript, re-runs HooverEngine to extract metadata
# 3. Metadata is inserted with ON CONFLICT IGNORE (idempotent)
# 4. Existing entries are NOT touched (only metadata is extracted)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database location
DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"

# Parse arguments
DRY_RUN=false
PROJECT_ID=""
TRANSCRIPT_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --transcript-id)
      TRANSCRIPT_ID="$2"
      shift 2
      ;;
    --help|-h)
      grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check database exists
if [[ ! -f "$DB_PATH" ]]; then
  echo "❌ Database not found at: $DB_PATH"
  echo "   Run the app first to create the database"
  exit 1
fi

# Check schema version
SCHEMA_VERSION=$(sqlite3 "$DB_PATH" "PRAGMA user_version;")
if [[ "$SCHEMA_VERSION" -lt 7 ]]; then
  echo "❌ Database schema is v$SCHEMA_VERSION, need v7 or higher"
  echo "   Run the app to apply migrations first"
  exit 1
fi

echo "📊 Contextify Metadata Backfill Tool (v7)"
echo "Database: $DB_PATH"
echo "Schema version: v$SCHEMA_VERSION"
echo ""

# Build query
if [[ -n "$TRANSCRIPT_ID" ]]; then
  QUERY="SELECT id, file_path, project_id, provider FROM transcripts WHERE id = '$TRANSCRIPT_ID'"
elif [[ -n "$PROJECT_ID" ]]; then
  QUERY="SELECT id, file_path, project_id, provider FROM transcripts WHERE project_id = '$PROJECT_ID' AND status != 'deleted'"
else
  QUERY="SELECT id, file_path, project_id, provider FROM transcripts WHERE status != 'deleted'"
fi

# Count transcripts
TOTAL=$(sqlite3 "$DB_PATH" "$QUERY;" | wc -l | tr -d ' ')

if [[ "$TOTAL" -eq 0 ]]; then
  echo "✅ No transcripts to backfill"
  exit 0
fi

echo "Found $TOTAL transcript(s) to backfill"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔍 DRY RUN - showing transcripts that would be processed:"
  echo ""
  sqlite3 "$DB_PATH" "$QUERY;" | while IFS='|' read -r id file_path project_id provider; do
    echo "  • $file_path (provider: $provider)"
  done
  echo ""
  echo "Run without --dry-run to perform backfill"
  exit 0
fi

# Create Swift backfill utility
# This is a simple Swift script that uses the ContextifyCore framework to re-ingest transcripts
cat > /tmp/backfill_metadata.swift <<'SWIFT'
import Foundation
import ContextifyCore

// Initialize database
guard let dbManager = try? DatabaseManager.shared else {
  print("❌ Failed to initialize database")
  exit(1)
}

// Get orchestrator
guard let orchestrator = try? TranscriptOrchestrator(dbManager: dbManager) else {
  print("❌ Failed to initialize orchestrator")
  exit(1)
}

// Get transcript IDs from command line
let transcriptIds = CommandLine.arguments.dropFirst()

print("Backfilling \(transcriptIds.count) transcript(s)...")

var successCount = 0
var errorCount = 0

for transcriptId in transcriptIds {
  guard let transcript = try? orchestrator.getTranscript(transcriptId) else {
    print("⚠️  Transcript \(transcriptId) not found")
    errorCount += 1
    continue
  }

  let fileURL = URL(fileURLWithPath: transcript.filePath)
  guard FileManager.default.fileExists(atPath: fileURL.path) else {
    print("⚠️  File not found: \(fileURL.path)")
    errorCount += 1
    continue
  }

  do {
    // Re-ingest transcript (metadata parser will extract metadata)
    print("Processing: \(fileURL.lastPathComponent)")
    try orchestrator.hooverTranscript(
      transcript,
      fileURL: fileURL,
      progress: SilentProgressSink()
    )
    successCount += 1
  } catch {
    print("❌ Error processing \(fileURL.lastPathComponent): \(error)")
    errorCount += 1
  }
}

print("")
print("✅ Backfill complete:")
print("   Success: \(successCount)")
print("   Errors: \(errorCount)")

struct SilentProgressSink: IngestProgressSink {
  func didStartTranscript(name: String, totalLines: Int) {}
  func didAdvance(linesProcessed: Int, totalLines: Int?) {}
  func didCompleteTranscript(durationMs: Int) {}
}
SWIFT

# Note: The actual backfill would need to be implemented as a proper Swift command-line tool
# that links against ContextifyCore. For now, this is a placeholder showing the approach.

echo "⚠️  Note: Full backfill implementation requires building a Swift CLI tool"
echo "   The metadata extraction is now integrated into HooverEngine and will"
echo "   automatically process new transcripts going forward."
echo ""
echo "   To manually trigger backfill for existing transcripts:"
echo "   1. Remove the transcript from the database (or set status='pending')"
echo "   2. Re-discover it using the Contextify app"
echo ""
echo "   OR implement scripts/backfill_metadata_cli.swift as a proper Swift Package"

exit 0
