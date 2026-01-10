#!/bin/bash
# Performance profiling wrapper for Contextify
# Usage: ./scripts/performance/profile.sh [options]
#
# Examples:
#   ./scripts/performance/profile.sh                      # Time Profiler, 60s, launch app
#   ./scripts/performance/profile.sh -t 30                # Time Profiler, 30s
#   ./scripts/performance/profile.sh -T "Energy Log" -t 120  # Energy profiling, 120s
#   ./scripts/performance/profile.sh -a                   # Attach to running app
#   ./scripts/performance/profile.sh -s                   # Use 'sample' command instead
#   ./scripts/performance/profile.sh -s -t 10             # Sample for 10s

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
TEMPLATE="Time Profiler"
DURATION=60
MODE="launch"  # launch or attach
USE_SAMPLE=false
APP_PATH="$PROJECT_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app"
PROFILES_DIR="$PROJECT_ROOT/build/profiles"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -T TEMPLATE   Instruments template (default: "Time Profiler")
                Common: "Time Profiler", "Energy Log", "Allocations", "Leaks"
  -t SECONDS    Duration in seconds (default: 60)
  -a            Attach to running Contextify instead of launching
  -s            Use 'sample' command instead of xctrace (simpler output)
  -o PATH       Output directory (default: build/profiles)
  -h            Show this help

Examples:
  $(basename "$0")                        # Time Profiler, 60s, launch app
  $(basename "$0") -t 30                  # Time Profiler, 30s
  $(basename "$0") -T "Energy Log" -t 120 # Energy profiling
  $(basename "$0") -a                     # Attach to running app
  $(basename "$0") -s -t 10               # Sample command, 10s
EOF
    exit 0
}

while getopts "T:t:aso:h" opt; do
    case $opt in
        T) TEMPLATE="$OPTARG" ;;
        t) DURATION="$OPTARG" ;;
        a) MODE="attach" ;;
        s) USE_SAMPLE=true ;;
        o) PROFILES_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

mkdir -p "$PROFILES_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEMPLATE_SLUG=$(echo "$TEMPLATE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

# Build app if launching and it doesn't exist
if [[ "$MODE" == "launch" && ! -d "$APP_PATH" ]]; then
    echo "Building app..."
    bash "$PROJECT_ROOT/scripts/xc.sh" build
fi

if [[ "$USE_SAMPLE" == true ]]; then
    # Use macOS 'sample' command - simpler, text output
    OUTPUT="$PROFILES_DIR/${TIMESTAMP}-sample.txt"

    if [[ "$MODE" == "launch" ]]; then
        echo "Launching Contextify..."
        open "$APP_PATH"
        sleep 2  # Wait for launch
    fi

    # Find PID
    PID=$(pgrep -x Contextify || true)
    if [[ -z "$PID" ]]; then
        echo "Error: Contextify not running"
        exit 1
    fi

    echo "Sampling PID $PID for ${DURATION}s (1ms intervals)..."
    echo "Output: $OUTPUT"
    echo ""

    # sample <pid> <duration> <interval_ms> -file <output>
    sample "$PID" "$DURATION" 1 -file "$OUTPUT"

    echo ""
    echo "Sample complete: $OUTPUT"
    echo ""
    echo "Quick analysis:"
    echo "  grep -A5 'Call graph' '$OUTPUT' | head -20"
    echo ""
    echo "Find hotspots:"
    echo "  grep -E '^\s+[0-9]+ .*(Contextify|GRDB|sqlite)' '$OUTPUT' | sort -rn | head -20"

else
    # Use xctrace (Instruments)
    OUTPUT="$PROFILES_DIR/${TIMESTAMP}-${TEMPLATE_SLUG}.trace"

    echo "Profiling with '$TEMPLATE' for ${DURATION}s..."
    echo "Output: $OUTPUT"
    echo ""

    if [[ "$MODE" == "launch" ]]; then
        xctrace record \
            --template "$TEMPLATE" \
            --launch "$APP_PATH" \
            --time-limit "${DURATION}s" \
            --output "$OUTPUT"
    else
        # Find running app
        PID=$(pgrep -x Contextify || true)
        if [[ -z "$PID" ]]; then
            echo "Error: Contextify not running. Launch it first or use launch mode."
            exit 1
        fi

        xctrace record \
            --template "$TEMPLATE" \
            --attach "$PID" \
            --time-limit "${DURATION}s" \
            --output "$OUTPUT"
    fi

    echo ""
    echo "Trace saved: $OUTPUT"
    echo ""
    echo "Open in Instruments:"
    echo "  open '$OUTPUT'"
    echo ""
    echo "Export to XML (large files):"
    echo "  xctrace export --input '$OUTPUT' --output '${OUTPUT%.trace}.xml'"
fi
