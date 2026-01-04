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
APP_BINARY="$APP_PATH/Contents/MacOS/Contextify"
RUN_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="$SCRIPT_DIR/results"
LOG_FILE="/tmp/contextify-benchmark-$RUN_TIMESTAMP.log"
METRICS_FILE="$RESULTS_DIR/benchmark-$RUN_TIMESTAMP.json"
REPORT_FILE="$RESULTS_DIR/benchmark-$RUN_TIMESTAMP.md"
HISTORY_FILE="$PROJECT_ROOT/build/docs/performance/benchmark-history.md"

# Benchmark isolation paths (using new CLI flags)
BENCH_DB_PATH="/tmp/bench-$RUN_TIMESTAMP.db"
BENCH_TRANSCRIPT_PATH=""  # Set via --corpus option
BENCH_BATCH_SIZE=""       # Set via --batch-size option (default: 1000)

# Legacy mode paths
DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
BACKUP_DB_PATH=""

# Runtime state
APP_PID=""
TRACE_PATH=""

# Options
MODE="full"
USE_INSTRUMENTS=false
USE_CLI_FLAGS=true  # Use new --database-path --no-summaries --quiet flags
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
        --corpus)
            BENCH_TRANSCRIPT_PATH="$2"
            shift 2
            ;;
        --legacy)
            USE_CLI_FLAGS=false
            shift
            ;;
        --notes)
            RUN_NOTES="$2"
            shift 2
            ;;
        --batch-size)
            BENCH_BATCH_SIZE="$2"
            shift 2
            ;;
        --help)
            cat << 'EOF'
Contextify Performance Benchmark Suite

Usage:
  ./run-perf-suite.sh [options]

Options:
  --full            Run full benchmark (default)
  --quick           Run quick benchmark (startup only)
  --instruments     Enable Instruments profiling (Time Profiler)
  --corpus PATH     Use snapshot corpus at PATH (default: live transcripts)
  --batch-size N    Set batch size for ingest (default: 1000)
  --legacy          Use legacy mode (backup/restore DB instead of CLI flags)
  --notes "text"    Add notes to this run
  --help            Show this help

Examples:
  # Quick startup-only benchmark
  ./run-perf-suite.sh --quick

  # Full benchmark with Instruments profiling
  ./run-perf-suite.sh --full --instruments

  # Benchmark with snapshot corpus for reproducibility
  ./run-perf-suite.sh --corpus ~/benchmarks/corpus-v1 --notes "baseline v1.0.7"

Output:
  - JSON metrics: scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.json
  - Markdown report: scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.md
  - Full logs: /tmp/contextify-benchmark-YYYYMMDD-HHMMSS.log
EOF
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
    if ! $USE_CLI_FLAGS; then
        restore_db || true
    fi
    [[ -n "${INSTRUMENTS_PID:-}" ]] && kill "$INSTRUMENTS_PID" 2>/dev/null || true
    [[ -n "${APP_PID:-}" ]] && kill "$APP_PID" 2>/dev/null || true
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

build_cli_args() {
    local args=()

    # Always use isolated database
    args+=("--database-path" "$BENCH_DB_PATH")

    # Skip LLM summaries for pure ingest benchmark
    args+=("--no-summaries")

    # Run headless (no window, no dock icon)
    args+=("--quiet")

    # Use corpus if specified
    if [[ -n "$BENCH_TRANSCRIPT_PATH" ]]; then
        args+=("--transcript-path" "$BENCH_TRANSCRIPT_PATH")
    fi

    echo "${args[@]}"
}

launch_app() {
    local env_vars=""
    if [[ -n "$BENCH_BATCH_SIZE" ]]; then
        env_vars="CONTEXTIFY_BATCH_LINES=$BENCH_BATCH_SIZE"
        log "Using batch size: $BENCH_BATCH_SIZE"
    fi

    if $USE_CLI_FLAGS; then
        local cli_args=$(build_cli_args)
        log "Launching $APP_NAME with CLI flags: $cli_args"
        if [[ -n "$env_vars" ]]; then
            env $env_vars "$APP_BINARY" $cli_args &
        else
            "$APP_BINARY" $cli_args &
        fi
        APP_PID=$!
        log "App PID: $APP_PID"
    else
        log "Launching $APP_NAME (legacy mode)..."
        open "$APP_PATH"
    fi
}

launch_app_with_instruments() {
    local trace_path="/tmp/contextify-trace-$RUN_TIMESTAMP.trace"
    log "Launching with Instruments (Time Profiler)..."
    log "Trace will be saved to: $trace_path"

    if $USE_CLI_FLAGS; then
        local cli_args=$(build_cli_args)
        log "CLI flags: $cli_args"

        # Start Instruments with CLI args
        xcrun xctrace record --template "Time Profiler" \
            --output "$trace_path" \
            --launch "$APP_BINARY" -- $cli_args &
    else
        # Legacy mode - no CLI flags
        xcrun xctrace record --template "Time Profiler" \
            --output "$trace_path" \
            --launch "$APP_BINARY" &
    fi

    INSTRUMENTS_PID=$!
    log "Instruments PID: $INSTRUMENTS_PID"
    TRACE_PATH="$trace_path"
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

    # In CLI flags mode, we use isolated DB path - no need to touch production DB
    if ! $USE_CLI_FLAGS; then
        delete_db
    fi

    # Clean up any previous benchmark DB
    rm -f "$BENCH_DB_PATH" "$BENCH_DB_PATH-wal" "$BENCH_DB_PATH-shm"

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

    # Record CLI flags mode
    if $USE_CLI_FLAGS; then
        add_metric_string "isolation_mode" "cli_flags"
        add_metric_string "bench_db_path" "$BENCH_DB_PATH"
        if [[ -n "$BENCH_TRANSCRIPT_PATH" ]]; then
            add_metric_string "transcript_path" "$BENCH_TRANSCRIPT_PATH"
        fi
    else
        add_metric_string "isolation_mode" "legacy"
    fi
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
        wait "$INSTRUMENTS_PID" 2>/dev/null || true
    fi

    # Restore original database if we backed it up (legacy mode only)
    if ! $USE_CLI_FLAGS; then
        restore_db
    fi

    # Record log file info
    local log_size=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
    add_metric_string "log_file" "$LOG_FILE"
    add_metric "log_size_mb" "${log_size:-0}"

    log "Log file: $LOG_FILE (${log_size:-0}MB)"

    # Record trace file if Instruments was used
    if [[ -n "$TRACE_PATH" && -d "$TRACE_PATH" ]]; then
        local trace_size=$(du -m "$TRACE_PATH" 2>/dev/null | cut -f1)
        add_metric_string "trace_file" "$TRACE_PATH"
        add_metric "trace_size_mb" "${trace_size:-0}"
        log "Trace file: $TRACE_PATH (${trace_size:-0}MB)"
    fi

    # Record benchmark DB size
    if [[ -f "$BENCH_DB_PATH" ]]; then
        local db_size=$(du -m "$BENCH_DB_PATH" 2>/dev/null | cut -f1)
        add_metric "final_db_size_mb" "${db_size:-0}"
        log "Benchmark DB: $BENCH_DB_PATH (${db_size:-0}MB)"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_section "Contextify Performance Benchmark Suite"
    log "Mode: $MODE"
    log "Instruments: $USE_INSTRUMENTS"
    log "CLI Flags: $USE_CLI_FLAGS"
    log "Corpus: ${BENCH_TRANSCRIPT_PATH:-live transcripts}"
    log "Notes: ${RUN_NOTES:-none}"
    log "Timestamp: $RUN_TIMESTAMP"
    log ""

    # Ensure results directory exists
    mkdir -p "$RESULTS_DIR"

    # Check prerequisites
    ensure_app_built

    # Initialize metrics
    init_metrics "$METRICS_FILE"

    add_metric_string "mode" "$MODE"
    add_metric_string "instruments" "$USE_INSTRUMENTS"

    if [[ -n "$RUN_NOTES" ]]; then
        add_metric_string "run_notes" "$RUN_NOTES"
    fi

    # Kill app before backup
    kill_app

    # Only backup/restore in legacy mode
    if ! $USE_CLI_FLAGS; then
        backup_db
    fi

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
    if [[ -n "${TRACE_PATH:-}" ]]; then
        log "  Trace:   $TRACE_PATH"
    fi
    log "  History: $HISTORY_FILE"
    log ""
    log "View report: cat $REPORT_FILE"
    if [[ -n "${TRACE_PATH:-}" ]]; then
        log "Open trace: open $TRACE_PATH"
    fi
}

# Run main
main "$@"
