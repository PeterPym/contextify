#!/bin/bash
set -euo pipefail

# =============================================================================
# Contextify Performance Benchmark Suite
# =============================================================================
#
# Usage:
#   ./run-perf-suite.sh [options]
#
# Options:
#   --full          Run full benchmark (default)
#   --quick         Run quick benchmark (startup + one project only)
#   --instruments   Enable Instruments profiling (slower)
#   --notes "text"  Add notes to this run
#   --help          Show this help
#
# Output:
#   - JSON metrics: scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.json
#   - Markdown report: scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.md
#   - Full logs: /tmp/contextify-benchmark-YYYYMMDD-HHMMSS.log
#   - History updated: build/docs/performance/benchmark-history.md
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/timing.sh"
source "$SCRIPT_DIR/lib/metrics.sh"
source "$SCRIPT_DIR/lib/report.sh"

# Configuration
APP_NAME="Contextify"
APP_PATH="$PROJECT_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app"
DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
BACKUP_DB_PATH=""
RUN_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$SCRIPT_DIR/results"
LOG_FILE="/tmp/contextify-benchmark-$RUN_TIMESTAMP.log"
METRICS_FILE="$RESULTS_DIR/benchmark-$RUN_TIMESTAMP.json"
REPORT_FILE="$RESULTS_DIR/benchmark-$RUN_TIMESTAMP.md"
HISTORY_FILE="$PROJECT_ROOT/build/docs/performance/benchmark-history.md"

# Options
MODE="full"
USE_INSTRUMENTS=false
RUN_NOTES=""

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            MODE="full"
            shift
            ;;
        --quick)
            MODE="quick"
            shift
            ;;
        --instruments)
            USE_INSTRUMENTS=true
            shift
            ;;
        --notes)
            RUN_NOTES="$2"
            shift 2
            ;;
        --help)
            head -30 "$0" | tail -25
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

cleanup_on_exit() {
    # best-effort cleanup; never fail
    stop_log_stream || true
    kill_app || true
    restore_db || true
    [[ -n "${INSTRUMENTS_PID:-}" ]] && kill "$INSTRUMENTS_PID" 2>/dev/null || true
}

log_section() {
    log ""
    log "========================================"
    log "$*"
    log "========================================"
}

ensure_app_built() {
    if [[ ! -d "$APP_PATH" ]]; then
        log "ERROR: App not found at $APP_PATH"
        log "Run: bash scripts/xc.sh build"
        exit 1
    fi
}

kill_app() {
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        log "Killing existing $APP_NAME process..."
        pkill -x "$APP_NAME" || true
        sleep 1
    fi
}

backup_db() {
    if [[ -f "$DB_PATH" ]]; then
        BACKUP_DB_PATH="/tmp/contextify-db-backup-$RUN_TIMESTAMP.db"
        log "Backing up database to $BACKUP_DB_PATH"
        cp "$DB_PATH" "$BACKUP_DB_PATH"
    fi
}

restore_db() {
    if [[ -n "$BACKUP_DB_PATH" && -f "$BACKUP_DB_PATH" ]]; then
        log "Restoring database from backup"
        cp "$BACKUP_DB_PATH" "$DB_PATH"
    fi
}

delete_db() {
    log "Deleting database for fresh run"
    rm -f "$DB_PATH"
    rm -f "$DB_PATH-wal"
    rm -f "$DB_PATH-shm"
}

launch_app() {
    log "Launching $APP_NAME..."
    open "$APP_PATH"
}

launch_app_with_instruments() {
    local trace_path="/tmp/contextify-trace-$RUN_TIMESTAMP.trace"
    log "Launching with Instruments (Time Profiler)..."
    log "Trace will be saved to: $trace_path"

    # Start Instruments in background
    xcrun xctrace record --template "Time Profiler" \
        --output "$trace_path" \
        --launch "$APP_PATH/Contents/MacOS/Contextify" &

    INSTRUMENTS_PID=$!
    log "Instruments PID: $INSTRUMENTS_PID"
}

wait_for_startup() {
    local timeout=${1:-30}
    log "Waiting for app startup (timeout: ${timeout}s)..."
    wait_for_process "$APP_NAME" "$timeout"
}

wait_for_idle() {
    # Wait for app to reach idle state by monitoring CPU usage
    local timeout=${1:-300}
    local idle_threshold=5  # CPU % below which we consider idle
    local idle_count=0
    local required_idle=3   # Need 3 consecutive idle readings

    log "Waiting for app to reach idle state..."

    for ((i=0; i<timeout; i++)); do
        local pid
        pid="$(pgrep -x "$APP_NAME" | head -1 || true)"
        if [[ -z "$pid" ]]; then
            log "ERROR: $APP_NAME is not running (crashed?)"
            return 2
        fi

        local cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
        cpu=${cpu%.*}  # Remove decimal

        if [[ $cpu -lt $idle_threshold ]]; then
            idle_count=$((idle_count + 1))
            if [[ $idle_count -ge $required_idle ]]; then
                log "App reached idle state (CPU: ${cpu}%)"
                return 0
            fi
        else
            idle_count=0
        fi

        # Log progress every 30 seconds
        if [[ $((i % 30)) -eq 0 && $i -gt 0 ]]; then
            local mem=$(get_process_memory_mb "$APP_NAME")
            log "  Progress: ${i}s elapsed, CPU: ${cpu}%, Memory: ${mem}MB"
        fi

        sleep 1
    done

    log "WARNING: Timeout waiting for idle state"
    return 1
}

capture_memory_sample() {
    get_process_memory_mb "$APP_NAME"
}

stream_logs() {
    # Stream unified logs for Contextify to log file
    command -v log >/dev/null || { log "Missing macOS 'log' tool"; exit 1; }
    log "Starting log capture..."
    log stream --predicate 'subsystem == "dev.contextify"' \
        --style compact >> "$LOG_FILE" 2>&1 &
    LOG_STREAM_PID=$!
}

stop_log_stream() {
    if [[ -n "${LOG_STREAM_PID:-}" ]]; then
        kill $LOG_STREAM_PID 2>/dev/null || true
    fi
}

# =============================================================================
# Benchmark Phases
# =============================================================================

phase_corpus_stats() {
    log_section "Phase: Corpus Statistics"

    local stats=$(get_corpus_stats)
    log "Corpus stats: $stats"
    add_metric_object "corpus" "$stats"
}

phase_startup() {
    log_section "Phase: Startup Benchmark"

    kill_app
    delete_db

    local start_ms=$(get_timestamp_ms)

    if $USE_INSTRUMENTS; then
        launch_app_with_instruments
    else
        launch_app
    fi

    wait_for_startup 30
    local startup_ms=$(get_timestamp_ms)

    local startup_duration=$((startup_ms - start_ms))
    log "Cold startup time: ${startup_duration}ms"
    add_metric "startup_cold_ms" "$startup_duration"
}

phase_ingest() {
    log_section "Phase: Full Ingest Benchmark"

    local start_ms=$(get_timestamp_ms)
    local peak_memory=0

    log "Monitoring ingest progress..."
    log "This may take 15-20 minutes for a large corpus."
    log ""

    # Monitor until idle
    local elapsed=0
    while true; do
        # Use errexit-safe pattern: capture non-zero exit without triggering set -e
        local rc=0
        wait_for_idle 10 || rc=$?
        if [[ $rc -eq 0 ]]; then
            break
        elif [[ $rc -eq 2 ]]; then
            log "ERROR: App crashed during ingest"
            return 1
        fi

        elapsed=$((elapsed + 10))
        local mem=$(capture_memory_sample)

        # Track peak memory
        if (( $(echo "$mem > $peak_memory" | bc -l) )); then
            peak_memory=$mem
        fi

        log "  Ingest progress: ${elapsed}s, Memory: ${mem}MB, Peak: ${peak_memory}MB"
    done

    local end_ms=$(get_timestamp_ms)
    local ingest_duration=$((end_ms - start_ms))

    log "Ingest complete!"
    log "  Total time: $(format_duration_ms $ingest_duration)"
    log "  Peak memory: ${peak_memory}MB"

    add_metric "ingest_total_ms" "$ingest_duration"
    add_metric "peak_memory_mb" "$peak_memory"

    # Calculate ingest rate from corpus stats
    local total_lines=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['metrics']['corpus']['total_lines'])")
    if [[ $ingest_duration -gt 0 && $total_lines -gt 0 ]]; then
        local lines_per_sec=$((total_lines * 1000 / ingest_duration))
        log "  Ingest rate: ${lines_per_sec} lines/sec"
        add_metric "ingest_lines" "$total_lines"
        add_metric "ingest_lines_per_sec" "$lines_per_sec"
    fi
}

phase_project_switch() {
    log_section "Phase: Project Switch Benchmark"

    # This phase requires UI automation or manual intervention
    # For now, we'll measure what we can from logs

    log "NOTE: Project switch timing requires UI interaction or AppleScript automation."
    log "Analyze logs for 'selectProject' timing."

    # Placeholder - would need AppleScript or XCUITest for full automation
    add_metric_string "switch_cold_ms" "manual"
    add_metric_string "switch_warm_ms" "manual"
    add_metric_string "ui_update_ms" "manual"
}

phase_queries() {
    log_section "Phase: Query Performance"

    # Query performance is measured from logs
    # Look for specific log patterns

    log "Query performance will be extracted from logs."
    log "Look for patterns:"
    log "  - 'loadFeedFromSQL' for timeline queries"
    log "  - 'searchEntries' for search queries"
    log "  - 'getSessions' for session list queries"

    add_metric_string "query_timeline_ms" "from_logs"
    add_metric_string "query_search_ms" "from_logs"
    add_metric_string "query_sessions_ms" "from_logs"
}

phase_cleanup() {
    log_section "Phase: Cleanup"

    kill_app
    stop_log_stream

    # Cleanup Instruments if running
    if [[ -n "${INSTRUMENTS_PID:-}" ]]; then
        kill "$INSTRUMENTS_PID" 2>/dev/null || true
    fi

    # Restore original database if we backed it up
    restore_db

    # Record log file info
    local log_size=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
    add_metric_string "log_file" "$LOG_FILE"
    add_metric "log_size_mb" "${log_size:-0}"

    log "Log file: $LOG_FILE (${log_size:-0}MB)"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_section "Contextify Performance Benchmark Suite"
    log "Mode: $MODE"
    log "Instruments: $USE_INSTRUMENTS"
    log "Notes: ${RUN_NOTES:-none}"
    log "Timestamp: $RUN_TIMESTAMP"
    log ""

    # Ensure results directory exists
    mkdir -p "$RESULTS_DIR"

    # Check prerequisites
    ensure_app_built

    # Initialize metrics
    init_metrics "$METRICS_FILE"

    if [[ -n "$RUN_NOTES" ]]; then
        add_metric_string "run_notes" "$RUN_NOTES"
    fi

    # Kill app before backup
    kill_app

    # Backup existing database
    backup_db

    # Set up exit trap for cleanup
    trap cleanup_on_exit EXIT INT TERM

    # Start log capture
    stream_logs

    # Run phases
    phase_corpus_stats
    phase_startup

    if [[ "$MODE" == "full" ]]; then
        phase_ingest
        phase_project_switch
        phase_queries
    fi

    phase_cleanup

    # Save results
    save_metrics
    generate_report "$METRICS_FILE" "$REPORT_FILE"
    append_to_history "$METRICS_FILE" "$HISTORY_FILE"

    log_section "Benchmark Complete"
    log "Results:"
    log "  Metrics: $METRICS_FILE"
    log "  Report:  $REPORT_FILE"
    log "  Logs:    $LOG_FILE"
    log "  History: $HISTORY_FILE"
    log ""
    log "View report: cat $REPORT_FILE"
}

# Run main
main "$@"
