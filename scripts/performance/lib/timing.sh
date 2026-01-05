#!/bin/bash
# Timing utilities for benchmark suite

# Get current timestamp in milliseconds
get_timestamp_ms() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: use python for millisecond precision
        python3 -c "import time; print(int(time.time() * 1000))"
    else
        date +%s%3N
    fi
}

# Get current timestamp in seconds (floating point)
get_timestamp_sec() {
    python3 -c "import time; print(time.time())"
}

# Calculate duration between two timestamps (ms)
# Usage: calc_duration_ms $start_ms $end_ms
calc_duration_ms() {
    local start=$1
    local end=$2
    echo $((end - start))
}

# Calculate duration between two timestamps (seconds, floating point)
# Usage: calc_duration_sec $start_sec $end_sec
calc_duration_sec() {
    local start=$1
    local end=$2
    python3 -c "print(round($end - $start, 3))"
}

# Format milliseconds as human readable
# Usage: format_duration_ms 1234 -> "1.234s"
format_duration_ms() {
    local ms=$1
    python3 -c "print(f'{$ms/1000:.3f}s')"
}

# Wait for process to appear
# Usage: wait_for_process "Contextify" 30
wait_for_process() {
    local process_name=$1
    local timeout=${2:-30}
    local count=0

    while ! pgrep -x "$process_name" > /dev/null 2>&1; do
        sleep 0.1
        count=$((count + 1))
        if [[ $count -gt $((timeout * 10)) ]]; then
            echo "TIMEOUT waiting for $process_name" >&2
            return 1
        fi
    done
    return 0
}

# Wait for process to exit
# Usage: wait_for_process_exit "Contextify" 60
wait_for_process_exit() {
    local process_name=$1
    local timeout=${2:-60}
    local count=0

    while pgrep -x "$process_name" > /dev/null 2>&1; do
        sleep 0.1
        count=$((count + 1))
        if [[ $count -gt $((timeout * 10)) ]]; then
            echo "TIMEOUT waiting for $process_name to exit" >&2
            return 1
        fi
    done
    return 0
}

# Get memory usage of process in MB
# Usage: get_process_memory "Contextify"
get_process_memory_mb() {
    local process_name=$1
    local pid=$(pgrep -x "$process_name" | head -1)
    if [[ -n "$pid" ]]; then
        # macOS: use ps to get RSS in KB, convert to MB
        ps -o rss= -p "$pid" | awk '{printf "%.1f", $1/1024}'
    else
        echo "0"
    fi
}

# Get peak memory from Instruments trace (if available)
# Usage: get_peak_memory_from_trace /path/to/trace
get_peak_memory_from_trace() {
    local trace_path=$1
    # This would parse Instruments output - placeholder for now
    echo "N/A"
}
