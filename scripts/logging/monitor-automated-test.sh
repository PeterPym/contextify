#!/bin/bash

# Self-Validating Automated Test Harness
# =====================================
# Purpose: Run app, capture logs, validate against expected patterns, report pass/fail
# Use when: Verifying bug fixes, regression testing, automated CI checks
#
# This script knows what "success" looks like and reports deviations automatically.
# Unlike interactive monitoring, this runs unattended and generates a report.

set -euo pipefail

# ============================================================================
# CONFIGURATION - Customize for your specific test
# ============================================================================

# Test identification
TEST_NAME="${TEST_NAME:-generic-test}"
TEST_DESCRIPTION="${TEST_DESCRIPTION:-Automated test harness}"

# Subsystem and categories to monitor
SUBSYSTEM="dev.contextify"
CATEGORIES='category IN {"HooverEngine", "TranscriptWatcher", "ConversationMonitor", "TranscriptOrchestrator"}'
LEVEL="info"

# Test duration in seconds
DURATION="${DURATION:-30}"

# Tags to capture (what events we're monitoring)
MONITOR_TAGS=(
    "WATCHER-EVENT"
    "HOOVER-START"
    "HOOVER-DONE"
    "INCR-UPDATE-ENTRIES"
    "TIMELINE-APPEND"
)

# Expectations: Define what "success" looks like
# Format: "TAG:min-max:rule" or "TAG:TAG2:match"
# Rules:
#   - "min-max" = count must be within range (e.g., "1-100" means at least 1)
#   - "TAG2:match" = count must equal TAG2's count
#   - "TAG2:ratio:N" = count should be ~N times TAG2's count (within 20%)
EXPECTATIONS=(
    # File watching should trigger
    "WATCHER-EVENT:0-1000:optional"

    # Hoover operations should complete
    "HOOVER-START:0-1000:optional"
    "HOOVER-DONE:HOOVER-START:match"

    # Database updates should match hoover completions
    "INCR-UPDATE-ENTRIES:0-1000:optional"

    # Timeline should be updated when DB changes
    "TIMELINE-APPEND:0-1000:optional"
)

# ============================================================================
# SCRIPT LOGIC
# ============================================================================

LOGFILE="/tmp/${TEST_NAME}-$(date +%Y%m%d-%H%M%S).log"
REPORT_FILE="/tmp/${TEST_NAME}-report-$(date +%Y%m%d-%H%M%S).txt"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AUTOMATED TEST HARNESS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test:        $TEST_NAME"
echo "Description: $TEST_DESCRIPTION"
echo "Duration:    ${DURATION}s"
echo "Log file:    $LOGFILE"
echo "Report:      $REPORT_FILE"
echo ""
echo "Monitoring tags: ${MONITOR_TAGS[@]}"
echo ""

# Optional: Kill and restart app for clean test
if [ "${RESTART_APP:-false}" = "true" ]; then
    echo "🔄 Restarting application..."
    pkill -9 Contextify 2>/dev/null || true
    sleep 2
    open -a "${APP_PATH:-/Users/rob/code/projects/contextify/.derived-dmg/Build/Products/Debug/Contextify.app}"
    sleep 3
fi

# Build grep pattern from tags
PATTERN=$(IFS="|"; echo "${MONITOR_TAGS[*]}")

echo "📊 Capturing logs for ${DURATION} seconds..."
echo ""

# Capture logs in background
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
# ANALYSIS - Validate against expectations
# ============================================================================

echo "🔍 Analyzing results..."
echo ""

# Count occurrences of each tag
declare -A TAG_COUNTS
for tag in "${MONITOR_TAGS[@]}"; do
    count=$(grep -c "\[$tag\]" "$LOGFILE" 2>/dev/null || echo "0")
    TAG_COUNTS[$tag]=$count
done

# Validate expectations
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

declare -a FAILURES
declare -a WARNINGS
declare -a PASSES

for expectation in "${EXPECTATIONS[@]}"; do
    # Parse expectation format
    tag="${expectation%%:*}"
    rest="${expectation#*:}"
    rule="${rest##*:}"
    middle="${rest%:*}"

    actual="${TAG_COUNTS[$tag]:-0}"

    if [[ "$rule" == "match" ]]; then
        # Expect counts to match
        target_tag="$middle"
        expected="${TAG_COUNTS[$target_tag]:-0}"

        if [ "$actual" -eq "$expected" ]; then
            PASSES+=("✅ $tag: $actual (matches $target_tag)")
            ((PASS_COUNT++))
        else
            FAILURES+=("❌ $tag: $actual (expected $expected to match $target_tag)")
            ((FAIL_COUNT++))
        fi

    elif [[ "$rule" =~ ^[0-9]+-[0-9]+$ ]]; then
        # Range check
        min="${rule%-*}"
        max="${rule#*-}"

        if [ "$actual" -ge "$min" ] && [ "$actual" -le "$max" ]; then
            PASSES+=("✅ $tag: $actual (within range $min-$max)")
            ((PASS_COUNT++))
        elif [ "$actual" -eq 0 ] && [ "$min" -eq 0 ]; then
            WARNINGS+=("⚠️  $tag: $actual (no activity, but within acceptable range)")
            ((WARN_COUNT++))
        else
            FAILURES+=("❌ $tag: $actual (expected $min-$max)")
            ((FAIL_COUNT++))
        fi

    elif [[ "$middle" == *":"* ]]; then
        # Ratio check (e.g., "HOOVER-START:ratio:2" means 2x START count)
        target_tag="${middle%:*}"
        multiplier="${middle#*:}"
        expected="${TAG_COUNTS[$target_tag]:-0}"
        expected=$((expected * multiplier))
        tolerance=$((expected / 5))  # 20% tolerance

        if [ "$actual" -ge $((expected - tolerance)) ] && [ "$actual" -le $((expected + tolerance)) ]; then
            PASSES+=("✅ $tag: $actual (~${multiplier}x $target_tag)")
            ((PASS_COUNT++))
        else
            FAILURES+=("❌ $tag: $actual (expected ~$expected, ${multiplier}x $target_tag)")
            ((FAIL_COUNT++))
        fi

    elif [ "$rule" = "optional" ]; then
        # Just informational
        if [ "$actual" -gt 0 ]; then
            PASSES+=("✅ $tag: $actual")
            ((PASS_COUNT++))
        else
            WARNINGS+=("⚠️  $tag: $actual (optional, no activity)")
            ((WARN_COUNT++))
        fi
    fi
done

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TEST REPORT: $TEST_NAME
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generated: $(date)
Description: $TEST_DESCRIPTION
Duration: ${DURATION}s
Log file: $LOGFILE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Passed:  $PASS_COUNT
Failed:  $FAIL_COUNT
Warnings: $WARN_COUNT

EOF

    if [ $FAIL_COUNT -eq 0 ]; then
        echo "🎉 OVERALL: PASS"
    else
        echo "💥 OVERALL: FAIL"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo "Failures:"
        printf '%s\n' "${FAILURES[@]}"
        echo ""
    fi

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo "Warnings:"
        printf '%s\n' "${WARNINGS[@]}"
        echo ""
    fi

    if [ ${#PASSES[@]} -gt 0 ]; then
        echo "Passes:"
        printf '%s\n' "${PASSES[@]}"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RAW TAG COUNTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for tag in "${MONITOR_TAGS[@]}"; do
        printf "%-30s: %5d\n" "$tag" "${TAG_COUNTS[$tag]:-0}"
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Full log: $LOGFILE"
    echo "Report saved to: $REPORT_FILE"
    echo ""
}

# Generate and display report
generate_report | tee "$REPORT_FILE"

# Exit with appropriate code
if [ $FAIL_COUNT -eq 0 ]; then
    exit 0
else
    exit 1
fi
