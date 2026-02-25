#!/usr/bin/env bash
# analyze_intent_classification.sh
# Surveys the database to find timeline summaries with "infer from message" placeholder
# and analyzes the original user messages to identify missing patterns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database location
DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"

# Output directory
OUTPUT_DIR="$PROJECT_ROOT/build/analysis"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/intent-classification-analysis-${TIMESTAMP}.txt"
CSV_FILE="$OUTPUT_DIR/intent-classification-data-${TIMESTAMP}.csv"

if [[ ! -f "$DB_PATH" ]]; then
  echo "❌ Database not found at: $DB_PATH"
  exit 1
fi

echo "🔍 Analyzing intent classification placeholders..."
echo "Database: $DB_PATH"
echo "Output: $OUTPUT_FILE"
echo ""

# SQL query to find all instances of the placeholder
QUERY="
SELECT
  tc.entry_id,
  te.content AS user_message,
  tc.present_form,
  tc.past_form,
  tc.disposition,
  tc.generated_at,
  te.timestamp,
  te.session_id,
  p.root_path AS project_path
FROM timeline_cache tc
INNER JOIN transcript_entries te ON tc.entry_id = te.id
INNER JOIN projects p ON te.project_id = p.id
WHERE
  te.kind = 'user'
  AND (
    tc.present_form LIKE '%infer from message%'
    OR tc.past_form LIKE '%infer from message%'
  )
ORDER BY tc.generated_at DESC;
"

# Execute query and save raw data
echo "📊 Querying database..."
sqlite3 -header -csv "$DB_PATH" "$QUERY" > "$CSV_FILE"

TOTAL_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | xargs)

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  echo "✅ No placeholder instances found! Intent classification is working well."
  exit 0
fi

echo "⚠️  Found $TOTAL_COUNT instances of placeholder text"
echo ""

# Generate analysis report
{
  echo "============================================================"
  echo "INTENT CLASSIFICATION PLACEHOLDER ANALYSIS"
  echo "Generated: $(date)"
  echo "Database: $DB_PATH"
  echo "============================================================"
  echo ""
  echo "SUMMARY"
  echo "-------"
  echo "Total placeholder instances: $TOTAL_COUNT"
  echo ""
  echo "DATA LOCATION"
  echo "-------------"
  echo "Raw CSV data: $CSV_FILE"
  echo ""
  echo "============================================================"
  echo "USER MESSAGES WITH PLACEHOLDERS"
  echo "============================================================"
  echo ""

  # Process each row and extract user messages
  tail -n +2 "$CSV_FILE" | while IFS=, read -r entry_id user_message present past disposition generated_at timestamp session_id project; do
    echo "-----------------------------------------------------------"
    echo "Entry ID: $entry_id"
    echo "Timestamp: $(date -r "$timestamp" 2>/dev/null || echo "$timestamp")"
    echo "Session: $session_id"
    echo "Project: $project"
    echo ""
    echo "USER MESSAGE:"
    # Remove CSV quotes and unescape content
    cleaned_msg=$(echo "$user_message" | sed 's/^"//;s/"$//' | sed 's/""/"/g')
    echo "$cleaned_msg"
    echo ""
    echo "GENERATED SUMMARY (present):"
    echo "$(echo "$present" | sed 's/^"//;s/"$//' | sed 's/""/"/g')"
    echo ""
    echo "GENERATED SUMMARY (past):"
    echo "$(echo "$past" | sed 's/^"//;s/"$//' | sed 's/""/"/g')"
    echo ""
    echo "Disposition: $disposition"
    echo ""
  done

  echo "============================================================"
  echo "PATTERN ANALYSIS RECOMMENDATIONS"
  echo "============================================================"
  echo ""
  echo "To identify missing patterns, review the user messages above and:"
  echo ""
  echo "1. Look for common imperative verbs not in classifyUserIntent():"
  echo "   - Current verbs: add, create, make, write, update, modify, delete,"
  echo "     remove, fix, change, show, display, list, get, set, enable,"
  echo "     disable, start, stop, run, execute, install, configure, test,"
  echo "     debug, check, verify, search, find, open, close"
  echo ""
  echo "2. Identify statement patterns (declarative sentences):"
  echo "   - 'this broke X'"
  echo "   - 'the X is Y'"
  echo "   - 'X doesn't work'"
  echo "   - 'need to X'"
  echo ""
  echo "3. Look for terse/informal commands:"
  echo "   - Single words: 'revert', 'investigate', 'deploy'"
  echo "   - Shortened: 'gotta', 'lemme', 'wanna'"
  echo ""
  echo "4. Context-dependent requests:"
  echo "   - 'the issue from earlier'"
  echo "   - 'that bug'"
  echo "   - References without explicit verbs"
  echo ""
  echo "============================================================"
  echo ""
  echo "Next steps:"
  echo "  1. Run: scripts/logging/generate_intent_improvements.py $CSV_FILE"
  echo "     (This will extract unique patterns and suggest code changes)"
  echo ""
  echo "  2. Review and update: Contextify/Contextify/FoundationLLM.swift"
  echo "     Function: classifyUserIntent() (lines 282-375)"
  echo ""
  echo "  3. Consider updating the LLM prompt template (line 1109)"
  echo "     From: 'You requested \(assistantName) to [infer from message]'"
  echo "     To: 'You [infer concise action verb from MESSAGE]'"
  echo ""

} > "$OUTPUT_FILE"

# Display summary
cat "$OUTPUT_FILE"

echo ""
echo "✅ Analysis complete!"
echo "📄 Full report: $OUTPUT_FILE"
echo "📊 Raw data: $CSV_FILE"
echo ""
echo "To generate pattern recommendations, run:"
echo "  python3 scripts/logging/generate_intent_improvements.py \"$CSV_FILE\""
