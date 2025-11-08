#!/bin/bash

# Pipeline Completeness Checker
# ==============================
# Purpose: Capture logs and verify that all pipeline stages are active
# Use when: Feature not appearing in UI, unclear where data is lost
#
# This script identifies broken pipeline stages by checking for activity
# at each stage: File System → Discovery → Hoover → Database → Timeline → UI

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Test identification
TEST_NAME="${TEST_NAME:-pipeline-check}"
DURATION="${DURATION:-30}"

# Subsystem and categories covering the full pipeline
SUBSYSTEM="dev.contextify"
CATEGORIES='category IN {"ProjectActivity", "HooverEngine", "TranscriptWatcher", "TranscriptOrchestrator", "ConversationMonitor", "UIRender", "EntryRow"}'
LEVEL="info"

# Pipeline stages (in order from input to output)
# Format: "Stage Name:TAG1,TAG2,TAG3"
PIPELINE_STAGES=(
    "File System Events:FSEVENTS-,WATCHER-EVENT"
    "Project Switch:SWITCH-"
    "Transcript Discovery:DISC-,TRANS-DISC,BATCH-DISC"
    "Hoover Engine:HOOVER-START,HOOVER-DONE,HOOVER-UPDATE"
    "File Watcher:WATCHER-NOTIFY,WATCHER-HOOVER"
    "Database Updates:INCR-UPDATE-START,INCR-UPDATE-ENTRIES"
    "Timeline Updates:TIMELINE-APPEND,TIMELINE-LOAD"
    "Viewport Updates:VIEWPORT-,VIEW-UPDATE"
    "UI Rendering:ROW-APPEAR"
)

# ============================================================================
# SCRIPT LOGIC
# ============================================================================

LOGFILE="/tmp/${TEST_NAME}-$(date +%Y%m%d-%H%M%S).log"
REPORT_FILE="/tmp/${TEST_NAME}-report-$(date +%Y%m%d-%H%M%S).txt"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PIPELINE COMPLETENESS CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test:     $TEST_NAME"
echo "Duration: ${DURATION}s"
echo "Log:      $LOGFILE"
echo "Report:   $REPORT_FILE"
echo ""

# Build pattern matching all pipeline tags
ALL_TAGS=()
for stage in "${PIPELINE_STAGES[@]}"; do
    tags="${stage#*:}"
    IFS=',' read -ra tag_array <<< "$tags"
    ALL_TAGS+=("${tag_array[@]}")
done

PATTERN=$(IFS="|"; echo "${ALL_TAGS[*]}")

echo "📊 Capturing logs for ${DURATION} seconds..."
echo "   Watching pipeline: File System → Discovery → Hoover → Database → Timeline → UI"
echo ""

# Capture logs
log stream \
  --predicate "subsystem BEGINSWITH \"$SUBSYSTEM\" AND $CATEGORIES" \
  --level "$LEVEL" \
  --style compact 2>&1 | \
  grep --line-buffered -E "\[($PATTERN)\]" > "$LOGFILE" &

LOG_PID=$!

# Wait for test duration
sleep "$DURATION"

# Stop log capture
kill $LOG_PID 2>/dev/null || true
sleep 1

echo "✅ Log capture complete"
echo ""

# ============================================================================
# PIPELINE ANALYSIS
# ============================================================================

echo "🔍 Analyzing pipeline completeness..."
echo ""

declare -a ACTIVE_STAGES
declare -a BROKEN_STAGES
declare -A STAGE_COUNTS

for stage_def in "${PIPELINE_STAGES[@]}"; do
    stage_name="${stage_def%%:*}"
    tags="${stage_def#*:}"

    # Convert comma-separated tags to grep pattern
    pattern=$(echo "$tags" | tr ',' '|')

    # Count occurrences
    count=$(grep -cE "\[($pattern)\]" "$LOGFILE" 2>/dev/null || echo "0")
    STAGE_COUNTS["$stage_name"]=$count

    if [ "$count" -gt 0 ]; then
        ACTIVE_STAGES+=("$stage_name")
    else
        BROKEN_STAGES+=("$stage_name")
    fi
done

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PIPELINE COMPLETENESS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generated: $(date)
Test: $TEST_NAME
Duration: ${DURATION}s
Log: $LOGFILE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  STAGE-BY-STAGE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    for stage_def in "${PIPELINE_STAGES[@]}"; do
        stage_name="${stage_def%%:*}"
        count="${STAGE_COUNTS[$stage_name]}"

        if [ "$count" -eq 0 ]; then
            printf "❌ %-30s %5d events  PIPELINE BROKEN HERE\n" "$stage_name:" "$count"
        elif [ "$count" -lt 5 ]; then
            printf "⚠️  %-30s %5d events  LOW ACTIVITY\n" "$stage_name:" "$count"
        else
            printf "✅ %-30s %5d events\n" "$stage_name:" "$count"
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DIAGNOSIS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ ${#BROKEN_STAGES[@]} -eq 0 ]; then
        echo "🎉 RESULT: COMPLETE PIPELINE"
        echo ""
        echo "All stages are active. Data is flowing through the entire pipeline."
        echo "If you're still seeing issues, the problem may be:"
        echo "  - Timing/performance (use analyze-gaps.sh)"
        echo "  - Logic errors within a working stage"
        echo "  - UI state management issues"
    else
        echo "💥 RESULT: PIPELINE BROKEN"
        echo ""
        echo "The following stages have NO activity:"
        for stage in "${BROKEN_STAGES[@]}"; do
            echo "  ❌ $stage"
        done
        echo ""
        echo "This indicates where data is being lost in the pipeline."
        echo ""

        # Identify first broken stage
        first_broken=""
        last_working=""
        for stage_def in "${PIPELINE_STAGES[@]}"; do
            stage_name="${stage_def%%:*}"
            count="${STAGE_COUNTS[$stage_name]}"

            if [ "$count" -eq 0 ] && [ -z "$first_broken" ]; then
                first_broken="$stage_name"
                break
            elif [ "$count" -gt 0 ]; then
                last_working="$stage_name"
            fi
        done

        if [ -n "$last_working" ] && [ -n "$first_broken" ]; then
            echo "🔍 FOCUS INVESTIGATION HERE:"
            echo "   Last working stage:  $last_working"
            echo "   First broken stage:  $first_broken"
            echo ""
            echo "Check the connection between these two stages:"
            echo "  - Is the working stage posting notifications?"
            echo "  - Is the broken stage listening for those notifications?"
            echo "  - Are there any errors/exceptions in the logs?"
        elif [ -n "$first_broken" ] && [ -z "$last_working" ]; then
            echo "🔍 FOCUS INVESTIGATION HERE:"
            echo "   First stage is broken: $first_broken"
            echo ""
            echo "The pipeline is failing at the very first stage."
            echo "  - Is the app monitoring the correct directory?"
            echo "  - Are file system events being generated?"
            echo "  - Check StartupCoordinator project initialization"
        fi
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Full log: $LOGFILE"
    echo "Report saved to: $REPORT_FILE"
    echo ""
    echo "Next steps:"
    echo "  - Review full log: cat $LOGFILE"
    echo "  - Check for errors: grep -i error $LOGFILE"
    echo "  - Analyze timing: ./scripts/logging/analyze-gaps.sh $LOGFILE"
    echo ""
}

# Generate and display report
generate_report | tee "$REPORT_FILE"

# Exit with appropriate code
if [ ${#BROKEN_STAGES[@]} -eq 0 ]; then
    exit 0
else
    exit 1
fi
