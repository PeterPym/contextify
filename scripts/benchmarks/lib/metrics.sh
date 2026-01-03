#!/bin/bash
# Metrics collection utilities

METRICS_FILE=""
METRICS_JSON=""

# Initialize metrics collection
# Usage: init_metrics "/path/to/metrics.json"
init_metrics() {
    METRICS_FILE=$1
    METRICS_JSON=$(cat <<EOF
{
    "run_id": "$(uuidgen | tr '[:upper:]' '[:lower:]')",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "machine": "$(hostname)",
    "os_version": "$(sw_vers -productVersion)",
    "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
    "git_branch": "$(git branch --show-current 2>/dev/null || echo 'unknown')",
    "metrics": {}
}
EOF
)
}

# Add a metric value
# Usage: add_metric "startup_time_ms" 187
add_metric() {
    local key=$1
    local value=$2
    METRICS_JSON=$(echo "$METRICS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['metrics']['$key'] = $value
print(json.dumps(data, indent=2))
")
}

# Add a string metric value
# Usage: add_metric_string "status" "success"
add_metric_string() {
    local key=$1
    local value=$2
    METRICS_JSON=$(echo "$METRICS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['metrics']['$key'] = '$value'
print(json.dumps(data, indent=2))
")
}

# Add a nested metric object
# Usage: add_metric_object "ingest" '{"lines": 1000, "time_ms": 500}'
add_metric_object() {
    local key=$1
    local json_value=$2
    METRICS_JSON=$(echo "$METRICS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['metrics']['$key'] = $json_value
print(json.dumps(data, indent=2))
")
}

# Save metrics to file
save_metrics() {
    echo "$METRICS_JSON" > "$METRICS_FILE"
    echo "Metrics saved to: $METRICS_FILE"
}

# Get corpus stats from transcript directories
# Usage: get_corpus_stats
get_corpus_stats() {
    local claude_dir="$HOME/.claude/projects"
    local codex_dir="$HOME/.codex/sessions"

    local claude_projects=0
    local claude_transcripts=0
    local claude_lines=0
    local codex_sessions=0
    local codex_lines=0

    if [[ -d "$claude_dir" ]]; then
        claude_projects=$(find "$claude_dir" -maxdepth 1 -type d | wc -l | tr -d ' ')
        claude_projects=$((claude_projects - 1))  # Subtract parent dir
        claude_transcripts=$(find "$claude_dir" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        claude_lines=$(find "$claude_dir" -name "*.jsonl" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
    fi

    if [[ -d "$codex_dir" ]]; then
        codex_sessions=$(find "$codex_dir" -maxdepth 2 -type d -name "session_*" 2>/dev/null | wc -l | tr -d ' ')
        codex_lines=$(find "$codex_dir" -name "*.jsonl" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
    fi

    cat <<EOF
{
    "claude_projects": ${claude_projects:-0},
    "claude_transcripts": ${claude_transcripts:-0},
    "claude_lines": ${claude_lines:-0},
    "codex_sessions": ${codex_sessions:-0},
    "codex_lines": ${codex_lines:-0},
    "total_lines": $((${claude_lines:-0} + ${codex_lines:-0}))
}
EOF
}
