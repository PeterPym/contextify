#!/bin/bash
set -euo pipefail

# =============================================================================
# Set Baseline - Mark a benchmark run as the official baseline for comparison
# =============================================================================
#
# Usage:
#   ./set-baseline.sh [run-id]
#
# If no run-id provided, uses the most recent benchmark run.
#
# Creates:
#   scripts/performance/baseline.json -> results/benchmark-XXXXXX.json (symlink)
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
BASELINE_LINK="$SCRIPT_DIR/baseline.json"

# Find the target metrics file
if [[ $# -ge 1 ]]; then
    # User specified a run ID or filename
    TARGET="$1"
    if [[ -f "$RESULTS_DIR/$TARGET" ]]; then
        METRICS_FILE="$RESULTS_DIR/$TARGET"
    elif [[ -f "$RESULTS_DIR/benchmark-$TARGET.json" ]]; then
        METRICS_FILE="$RESULTS_DIR/benchmark-$TARGET.json"
    elif [[ -f "$TARGET" ]]; then
        METRICS_FILE="$TARGET"
    else
        echo "ERROR: Cannot find metrics file for: $TARGET"
        echo "Looked in:"
        echo "  - $RESULTS_DIR/$TARGET"
        echo "  - $RESULTS_DIR/benchmark-$TARGET.json"
        echo "  - $TARGET"
        exit 1
    fi
else
    # Use most recent benchmark
    METRICS_FILE=$(ls -t "$RESULTS_DIR"/benchmark-*.json 2>/dev/null | head -1)
    if [[ -z "$METRICS_FILE" ]]; then
        echo "ERROR: No benchmark results found in $RESULTS_DIR"
        echo "Run a benchmark first: ./run-perf-suite.sh --full"
        exit 1
    fi
fi

# Verify it's valid JSON
if ! python3 -c "import json; json.load(open('$METRICS_FILE'))" 2>/dev/null; then
    echo "ERROR: Invalid JSON file: $METRICS_FILE"
    exit 1
fi

# Extract metadata for display
RUN_ID=$(python3 -c "import json; print(json.load(open('$METRICS_FILE')).get('run_id', 'unknown'))")
TIMESTAMP=$(python3 -c "import json; print(json.load(open('$METRICS_FILE')).get('timestamp', 'unknown'))")
COMMIT=$(python3 -c "import json; print(json.load(open('$METRICS_FILE')).get('git_commit', 'unknown'))")

# Create relative symlink
RELATIVE_PATH="results/$(basename "$METRICS_FILE")"
rm -f "$BASELINE_LINK"
ln -s "$RELATIVE_PATH" "$BASELINE_LINK"

echo "Baseline set successfully!"
echo ""
echo "  Run ID:    $RUN_ID"
echo "  Timestamp: $TIMESTAMP"
echo "  Commit:    $COMMIT"
echo "  File:      $METRICS_FILE"
echo "  Symlink:   $BASELINE_LINK -> $RELATIVE_PATH"
echo ""
echo "Future runs can be compared with: ./compare.sh"
