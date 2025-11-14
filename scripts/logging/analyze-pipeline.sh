#!/bin/bash

# Post-Hoc Pipeline Analysis Tool
# ================================
# Purpose: Analyze captured logs to identify where pipeline breaks
# Use when: You have a log file and need to understand what went wrong
#
# Unlike monitor-pipeline-check.sh (captures + analyzes), this only analyzes
# existing log files. Useful for CI/CD, offline analysis, or re-analyzing old logs.

set -euo pipefail

# ============================================================================
# USAGE AND VALIDATION
# ============================================================================

LOGFILE="${1:-}"

usage() {
    cat <<EOF
Usage: $0 <logfile>

Analyze pipeline completeness from captured log files.

Arguments:
  logfile    Path to log file (required)

Examples:
  # Analyze recent monitoring session
  $0 /tmp/pipeline-check-20251108-140637.log

  # Analyze any captured logs
  $0 /tmp/contextify-monitor-*.log

Output:
  - Stage-by-stage activity counts
  - Identification of broken stages
  - Suggested next steps

EOF
    exit 1
}

if [ -z "$LOGFILE" ]; then
    echo "Error: Log file required"
    usage
fi

if [ ! -f "$LOGFILE" ]; then
    echo "Error: File not found: $LOGFILE"
    exit 1
fi

# ============================================================================
# PIPELINE STAGE DEFINITIONS
# ============================================================================

# Same pipeline stages as monitor-pipeline-check.sh
PIPELINE_STAGES=(
    "File System Events:FSEVENTS-,WATCHER-EVENT"
    "Project Switch:SWITCH-"
    "Transcript Discovery:DISC-,TRANS-DISC,BATCH-DISC"
    "Hoover Engine:HOOVER-START,HOOVER-DONE,HOOVER-UPDATE"
    "File Watcher:WATCHER-NOTIFY,WATCHER-HOOVER"
    "Database Updates:DB-UPDATE,HOOVER-UPDATE-ROWS,INCR-UPDATE-START,INCR-UPDATE-ENTRIES"
    "Timeline Updates:TIMELINE-APPEND,TIMELINE-LOAD"
    "Viewport Updates:VIEWPORT-,VIEW-UPDATE"
    "UI Rendering:ROW-APPEAR"
)

# ============================================================================
# ANALYSIS
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PIPELINE ANALYSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Log file: $LOGFILE"
echo "Log size: $(ls -lh "$LOGFILE" | awk '{print $5}')"
echo "Log lines: $(wc -l < "$LOGFILE")"
echo ""

declare -a ACTIVE_STAGES
declare -a BROKEN_STAGES
declare -a STAGE_NAMES
declare -a STAGE_VALUES

get_stage_count() {
    local search="$1"
    local idx
    for idx in "${!STAGE_NAMES[@]}"; do
        if [[ "${STAGE_NAMES[$idx]}" == "$search" ]]; then
            printf '%s' "${STAGE_VALUES[$idx]}"
            return
        fi
    done
    printf '0'
}

for stage_def in "${PIPELINE_STAGES[@]}"; do
    stage_name="${stage_def%%:*}"
    tags="${stage_def#*:}"

    # Convert comma-separated tags to prefix-matching regexes inside []
    # e.g. "DISC-" becomes "DISC-[^]]*" so `[DISC-PROJECT-START]` counts toward discovery
    IFS=',' read -ra tag_array <<< "$tags"
    expanded_tags=()
    for tag in "${tag_array[@]}"; do
        expanded_tags+=("${tag}[^]]*")
    done
    pattern=$(IFS='|'; echo "${expanded_tags[*]}")

    # Count occurrences
    if output=$(grep -cE "\[($pattern)\]" "$LOGFILE" 2>/dev/null); then
        count="$output"
    else
        count="0"
    fi
    count="${count//$'\n'/}"
    STAGE_NAMES+=("$stage_name")
    STAGE_VALUES+=("$count")

    if [ "$count" -gt 0 ]; then
        ACTIVE_STAGES+=("$stage_name")
    else
        BROKEN_STAGES+=("$stage_name")
    fi
done

# ============================================================================
# REPORT
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STAGE-BY-STAGE ACTIVITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for stage_def in "${PIPELINE_STAGES[@]}"; do
    stage_name="${stage_def%%:*}"
    count="$(get_stage_count "$stage_name")"

    if [ "$count" -eq 0 ]; then
        printf "❌ %-30s %6d events  PIPELINE BROKEN\n" "$stage_name:" "$count"
    elif [ "$count" -lt 5 ]; then
        printf "⚠️  %-30s %6d events  LOW ACTIVITY\n" "$stage_name:" "$count"
    else
        printf "✅ %-30s %6d events\n" "$stage_name:" "$count"
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
    echo "All stages show activity. Data is flowing through the entire pipeline."
    echo ""
    echo "If you're still experiencing issues, consider:"
    echo "  - Timing/performance analysis: ./scripts/logging/analyze-gaps.sh $LOGFILE"
    echo "  - Content verification: grep -i error $LOGFILE"
    echo "  - Logic errors within individual stages (not pipeline breakage)"
else
    echo "💥 RESULT: PIPELINE BROKEN"
    echo ""
    echo "Broken stages (no activity):"
    for stage in "${BROKEN_STAGES[@]}"; do
        echo "  ❌ $stage"
    done
    echo ""

    # Identify transition point
    first_broken=""
    last_working=""
    for stage_def in "${PIPELINE_STAGES[@]}"; do
        stage_name="${stage_def%%:*}"
        count="$(get_stage_count "$stage_name")"

        if [ "$count" -eq 0 ] && [ -z "$first_broken" ]; then
            first_broken="$stage_name"
            break
        elif [ "$count" -gt 0 ]; then
            last_working="$stage_name"
        fi
    done

    if [ -n "$last_working" ] && [ -n "$first_broken" ]; then
        echo "🔍 BREAKPOINT IDENTIFIED:"
        echo "   ✅ Last working: $last_working"
        echo "   ❌ First broken: $first_broken"
        echo ""
        echo "Investigation focus:"
        echo "  - Review logs between these stages: grep -A5 -B5 '$last_working\\|$first_broken' $LOGFILE"
        echo "  - Check if $last_working triggers $first_broken"
        echo "  - Look for errors: grep -i error $LOGFILE | grep -E '$last_working|$first_broken'"
    elif [ -n "$first_broken" ] && [ -z "$last_working" ]; then
        echo "🔍 PIPELINE FAILS IMMEDIATELY:"
        echo "   ❌ First stage broken: $first_broken"
        echo ""
        echo "Investigation focus:"
        echo "  - Is the app initialized correctly?"
        echo "  - Is it monitoring the right project directory?"
        echo "  - Check StartupCoordinator logs: grep STARTUP $LOGFILE"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  QUICK CHECKS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Error check
if output=$(grep -ci error "$LOGFILE" 2>/dev/null); then
    error_count="${output//$'\n'/}"
else
    error_count="0"
fi

if [ "$error_count" -gt 0 ]; then
    echo "⚠️  Errors found: $error_count occurrences"
    echo "   View: grep -i error $LOGFILE"
    echo ""
fi

# Project switches
switch_count="$(get_stage_count "Project Switch")"
if [ "$switch_count" -gt 0 ]; then
    echo "ℹ️  Project switches: $switch_count"
    echo "   Pipeline analysis may be affected by project switching"
    echo "   View: grep SWITCH- $LOGFILE"
    echo ""
fi

# Activity level
total_events=0
for stage_def in "${PIPELINE_STAGES[@]}"; do
    stage_name="${stage_def%%:*}"
    count=$(get_stage_count "$stage_name")
    total_events=$((total_events + count))
done

if [ "$total_events" -eq 0 ]; then
    echo "❌ NO ACTIVITY DETECTED"
    echo "   The log contains no pipeline events"
    echo "   - Is this the correct log file?"
    echo "   - Was monitoring configured correctly?"
    echo ""
elif [ "$total_events" -lt 10 ]; then
    echo "⚠️  LOW ACTIVITY: $total_events total events"
    echo "   - Monitor duration may have been too short"
    echo "   - App may have been idle during monitoring"
    echo ""
else
    echo "✅ Activity level: $total_events total events (healthy)"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Exit with appropriate code
if [ ${#BROKEN_STAGES[@]} -eq 0 ]; then
    exit 0
else
    exit 1
fi
