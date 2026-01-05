#!/bin/bash
set -euo pipefail

# =============================================================================
# Compare Benchmark Runs
# =============================================================================
#
# Usage:
#   ./compare.sh                    # Compare latest run to baseline
#   ./compare.sh [run-id]           # Compare specific run to baseline
#   ./compare.sh [run-a] [run-b]    # Compare two specific runs
#
# Output:
#   - Console summary with delta percentages
#   - Optional: /tmp/benchmark-comparison-XXXXXX.md (detailed report)
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
BASELINE_LINK="$SCRIPT_DIR/baseline.json"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

find_metrics_file() {
    local target="$1"

    if [[ -f "$RESULTS_DIR/$target" ]]; then
        echo "$RESULTS_DIR/$target"
    elif [[ -f "$RESULTS_DIR/benchmark-$target.json" ]]; then
        echo "$RESULTS_DIR/benchmark-$target.json"
    elif [[ -f "$target" ]]; then
        echo "$target"
    else
        echo ""
    fi
}

get_latest_run() {
    ls -t "$RESULTS_DIR"/benchmark-*.json 2>/dev/null | head -1
}

# =============================================================================
# Argument Parsing
# =============================================================================

BASELINE_FILE=""
COMPARE_FILE=""

if [[ $# -eq 0 ]]; then
    # Compare latest to baseline
    if [[ ! -L "$BASELINE_LINK" ]]; then
        echo "ERROR: No baseline set. Run: ./set-baseline.sh"
        exit 1
    fi
    BASELINE_FILE=$(readlink -f "$BASELINE_LINK" 2>/dev/null || readlink "$BASELINE_LINK")
    # Handle relative symlink
    if [[ ! -f "$BASELINE_FILE" ]]; then
        BASELINE_FILE="$SCRIPT_DIR/$(readlink "$BASELINE_LINK")"
    fi
    COMPARE_FILE=$(get_latest_run)

    if [[ -z "$COMPARE_FILE" ]]; then
        echo "ERROR: No benchmark results found"
        exit 1
    fi

    # Don't compare baseline to itself
    if [[ "$(basename "$BASELINE_FILE")" == "$(basename "$COMPARE_FILE")" ]]; then
        echo "ERROR: Latest run IS the baseline. Run a new benchmark first."
        exit 1
    fi
elif [[ $# -eq 1 ]]; then
    # Compare specified run to baseline
    if [[ ! -L "$BASELINE_LINK" ]]; then
        echo "ERROR: No baseline set. Run: ./set-baseline.sh"
        exit 1
    fi
    BASELINE_FILE=$(readlink -f "$BASELINE_LINK" 2>/dev/null || readlink "$BASELINE_LINK")
    if [[ ! -f "$BASELINE_FILE" ]]; then
        BASELINE_FILE="$SCRIPT_DIR/$(readlink "$BASELINE_LINK")"
    fi
    COMPARE_FILE=$(find_metrics_file "$1")

    if [[ -z "$COMPARE_FILE" ]]; then
        echo "ERROR: Cannot find metrics file: $1"
        exit 1
    fi
else
    # Compare two specified runs
    BASELINE_FILE=$(find_metrics_file "$1")
    COMPARE_FILE=$(find_metrics_file "$2")

    if [[ -z "$BASELINE_FILE" ]]; then
        echo "ERROR: Cannot find metrics file: $1"
        exit 1
    fi
    if [[ -z "$COMPARE_FILE" ]]; then
        echo "ERROR: Cannot find metrics file: $2"
        exit 1
    fi
fi

# =============================================================================
# Comparison Logic
# =============================================================================

python3 << 'PYTHON_SCRIPT' "$BASELINE_FILE" "$COMPARE_FILE"
import json
import sys

baseline_file = sys.argv[1]
compare_file = sys.argv[2]

with open(baseline_file) as f:
    baseline = json.load(f)

with open(compare_file) as f:
    compare = json.load(f)

bm = baseline.get('metrics', {})
cm = compare.get('metrics', {})

# ANSI colors
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
BOLD = '\033[1m'
NC = '\033[0m'

def fmt_delta(old, new, lower_is_better=True):
    """Format a delta with color coding."""
    if old is None or new is None:
        return "N/A"
    if isinstance(old, str) or isinstance(new, str):
        return "N/A"
    if old == 0:
        return "N/A"

    delta_pct = ((new - old) / old) * 100

    # Determine if this is good or bad
    if lower_is_better:
        is_good = delta_pct < 0
    else:
        is_good = delta_pct > 0

    color = GREEN if is_good else RED if abs(delta_pct) > 5 else YELLOW
    sign = "+" if delta_pct > 0 else ""

    return f"{color}{sign}{delta_pct:.1f}%{NC}"

def fmt_value(val, unit=""):
    if val is None:
        return "N/A"
    if isinstance(val, str):
        return val
    if isinstance(val, float):
        return f"{val:.1f}{unit}"
    return f"{val}{unit}"

print(f"\n{BOLD}═══════════════════════════════════════════════════════════════{NC}")
print(f"{BOLD}                    BENCHMARK COMPARISON{NC}")
print(f"{BOLD}═══════════════════════════════════════════════════════════════{NC}\n")

print(f"{BOLD}Baseline:{NC} {baseline.get('timestamp', 'unknown')[:16]} @ {baseline.get('git_commit', 'unknown')}")
print(f"{BOLD}Compare:{NC}  {compare.get('timestamp', 'unknown')[:16]} @ {compare.get('git_commit', 'unknown')}")
print()

# Metrics to compare (key, label, unit, lower_is_better)
metrics = [
    ('startup_cold_ms', 'Cold Startup', 'ms', True),
    ('ingest_total_ms', 'Total Ingest Time', 'ms', True),
    ('ingest_lines_per_sec', 'Ingest Rate', '/sec', False),
    ('peak_memory_mb', 'Peak Memory', 'MB', True),
    ('switch_cold_ms', 'Project Switch (cold)', 'ms', True),
    ('switch_warm_ms', 'Project Switch (warm)', 'ms', True),
    ('query_timeline_ms', 'Timeline Query', 'ms', True),
    ('query_search_ms', 'Search Query', 'ms', True),
]

print(f"{'Metric':<25} {'Baseline':>12} {'Current':>12} {'Delta':>12}")
print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*12}")

for key, label, unit, lower_is_better in metrics:
    b_val = bm.get(key)
    c_val = cm.get(key)

    delta = fmt_delta(b_val, c_val, lower_is_better)
    b_str = fmt_value(b_val, unit)
    c_str = fmt_value(c_val, unit)

    print(f"{label:<25} {b_str:>12} {c_str:>12} {delta:>20}")

print()

# Summary
print(f"{BOLD}Summary:{NC}")

startup_b = bm.get('startup_cold_ms')
startup_c = cm.get('startup_cold_ms')
if startup_b and startup_c and isinstance(startup_b, (int, float)) and isinstance(startup_c, (int, float)):
    if startup_c < startup_b:
        print(f"  {GREEN}✓{NC} Startup improved by {((startup_b - startup_c) / startup_b) * 100:.1f}%")
    elif startup_c > startup_b:
        print(f"  {RED}✗{NC} Startup regressed by {((startup_c - startup_b) / startup_b) * 100:.1f}%")
    else:
        print(f"  {YELLOW}={NC} Startup unchanged")

ingest_b = bm.get('ingest_lines_per_sec')
ingest_c = cm.get('ingest_lines_per_sec')
if ingest_b and ingest_c and isinstance(ingest_b, (int, float)) and isinstance(ingest_c, (int, float)):
    if ingest_c > ingest_b:
        print(f"  {GREEN}✓{NC} Ingest rate improved by {((ingest_c - ingest_b) / ingest_b) * 100:.1f}%")
    elif ingest_c < ingest_b:
        print(f"  {RED}✗{NC} Ingest rate regressed by {((ingest_b - ingest_c) / ingest_b) * 100:.1f}%")
    else:
        print(f"  {YELLOW}={NC} Ingest rate unchanged")

mem_b = bm.get('peak_memory_mb')
mem_c = cm.get('peak_memory_mb')
if mem_b and mem_c and isinstance(mem_b, (int, float)) and isinstance(mem_c, (int, float)):
    if mem_c < mem_b:
        print(f"  {GREEN}✓{NC} Memory reduced by {((mem_b - mem_c) / mem_b) * 100:.1f}%")
    elif mem_c > mem_b:
        print(f"  {RED}✗{NC} Memory increased by {((mem_c - mem_b) / mem_b) * 100:.1f}%")
    else:
        print(f"  {YELLOW}={NC} Memory unchanged")

print()
PYTHON_SCRIPT
