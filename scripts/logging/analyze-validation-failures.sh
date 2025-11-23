#!/bin/bash
# Extract and analyze failed summarization validation from log files
#
# Usage: ./analyze-validation-failures.sh [log-pattern] [output.csv]
#
# Examples:
#   ./analyze-validation-failures.sh                              # Analyze /tmp/transcript-queue-monitor-*.log
#   ./analyze-validation-failures.sh "mylogs-*.log" output.csv    # Custom logs and output
#
# Output: CSV file with timestamp, leaked_count, confidence, and leaked_tokens

LOG_PATTERN="${1:-/tmp/transcript-queue-monitor-*.log}"
OUTPUT_FILE="${2:-/tmp/failed-summaries-$(date +%Y%m%d-%H%M%S).csv}"

echo "═══════════════════════════════════════════════════════════════"
echo "  Timeline Summarization Validation Failure Analysis"
echo "═══════════════════════════════════════════════════════════════"
echo "Log pattern: $LOG_PATTERN"
echo "Output file: $OUTPUT_FILE"
echo ""

# Check if log files exist
if ! ls $LOG_PATTERN >/dev/null 2>&1; then
    echo "ERROR: No log files found matching pattern: $LOG_PATTERN"
    exit 1
fi

# Write CSV header
echo "timestamp,leaked_count,confidence,leaked_tokens" > "$OUTPUT_FILE"

# Extract all VALIDATION-REJECT lines with excessive leakage
grep -h "VALIDATION-REJECT.*excessive leakage" $LOG_PATTERN 2>/dev/null | \
while IFS= read -r line; do
    # Parse timestamp
    timestamp=$(echo "$line" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}')

    # Parse leaked count
    leaked_count=$(echo "$line" | grep -oE 'leaked=[0-9]+' | cut -d= -f2)

    # Parse confidence
    confidence=$(echo "$line" | grep -oE 'confidence=[0-9.]+' | cut -d= -f2)

    # Parse leaked tokens (after ): at end of line)
    leaked_tokens=$(echo "$line" | sed 's/.*): //' | tr ',' ';')

    echo "\"$timestamp\",$leaked_count,$confidence,\"$leaked_tokens\"" >> "$OUTPUT_FILE"
done

# Count results
total_rejections=$(tail -n +2 "$OUTPUT_FILE" | wc -l | tr -d ' ')

if [ "$total_rejections" -eq 0 ]; then
    echo "✅ No validation failures found - all summaries passed validation"
    echo ""
    exit 0
fi

echo "Found $total_rejections failed summarization attempts"
echo ""

# Show leakage statistics
echo "Leakage count distribution:"
tail -n +2 "$OUTPUT_FILE" | cut -d, -f2 | sort -n | uniq -c | while read count leaked; do
    printf "  %2d tokens: %3d occurrences\n" "$leaked" "$count"
done

# Show top leaked tokens
echo ""
echo "Most common leaked tokens (top 20):"
tail -n +2 "$OUTPUT_FILE" | cut -d, -f4 | tr ';' '\n' | grep -v '^$' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/"//g' | \
    sort | uniq -c | sort -rn | head -20 | while read count token; do
    printf "  %3d: %s\n" "$count" "$token"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CSV written to: $OUTPUT_FILE"
echo ""
echo "To view in terminal:"
echo "  column -t -s, \"$OUTPUT_FILE\" | less -S"
echo ""
echo "To analyze further:"
echo "  # Count by leaked token count"
echo "  awk -F, 'NR>1 {print \$2}' \"$OUTPUT_FILE\" | sort -n | uniq -c"
echo ""
echo "  # Find specific tokens"
echo "  grep 'sometoken' \"$OUTPUT_FILE\""
echo "═══════════════════════════════════════════════════════════════"
