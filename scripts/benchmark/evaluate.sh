#!/usr/bin/env bash
# evaluate.sh - Total Recall benchmark evaluator
#
# FROZEN (ct-729, 2026-03-27). Calibrated against 36 labeled pairs (F1=0.900).
# Do not change scoring logic without re-running calibrate-fingerprint.py.
#
# Runs gold queries against a frozen DB snapshot and scores the results.
# Final score (0-100) is printed as the last line on stdout.
# All diagnostic output goes to stderr.
#
# Usage:
#   bash scripts/benchmark/evaluate.sh [--gold-queries PATH] [--snapshot PATH] [--mode cli|skill] [--verbose] [--trace] [--runs N]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

GOLD_QUERIES="${SCRIPT_DIR}/gold-queries.json"
SNAPSHOT=""
MODE="cli"
VERBOSE=false
TRACE=false
RUNS=1

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gold-queries)
      GOLD_QUERIES="$2"; shift 2 ;;
    --snapshot)
      SNAPSHOT="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --verbose)
      VERBOSE=true; shift ;;
    --trace)
      TRACE=true; shift ;;
    --runs)
      RUNS="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: evaluate.sh [--gold-queries PATH] [--snapshot PATH] [--mode cli|skill] [--verbose] [--trace] [--runs N]" >&2
      echo "" >&2
      echo "Options:" >&2
      echo "  --gold-queries PATH  Path to gold queries JSON (default: scripts/benchmark/gold-queries.json)" >&2
      echo "  --snapshot PATH      Path to frozen DB snapshot (default: from snapshot-manifest.json)" >&2
      echo "  --mode cli|skill     Execution mode (default: cli)" >&2
      echo "  --verbose            Show per-query results on stderr" >&2
      echo "  --trace              Write per-query trace files to /tmp/benchmark-traces/" >&2
      echo "  --runs N             Run benchmark N times and report median score (default: 1)" >&2
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Multi-run median mode (ct-727)
# ---------------------------------------------------------------------------
if [[ "$RUNS" -gt 1 ]]; then
  echo "Running $RUNS iterations for median scoring..." >&2
  SCORES=()
  ARGS=()
  [[ -n "$SNAPSHOT" ]] && ARGS+=(--snapshot "$SNAPSHOT")
  ARGS+=(--gold-queries "$GOLD_QUERIES" --mode "$MODE" --runs 1)
  [[ "$VERBOSE" == "true" ]] && ARGS+=(--verbose)
  [[ "$TRACE" == "true" ]] && ARGS+=(--trace)

  for i in $(seq 1 "$RUNS"); do
    echo "--- Run $i/$RUNS ---" >&2
    SCORE=$("${BASH_SOURCE[0]}" "${ARGS[@]}")
    SCORES+=("$SCORE")
    echo "  Score: $SCORE" >&2
  done

  # Compute median
  MEDIAN=$(python3 -c "
import sys
scores = sorted([float(s) for s in sys.argv[1:]])
n = len(scores)
if n % 2 == 1:
    print(f'{scores[n // 2]:.1f}')
else:
    print(f'{(scores[n // 2 - 1] + scores[n // 2]) / 2:.1f}')
" "${SCORES[@]}")

  echo "---" >&2
  echo "Scores: ${SCORES[*]}" >&2
  echo "Median: $MEDIAN" >&2
  echo "$MEDIAN"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode validation
# ---------------------------------------------------------------------------
if [[ "$MODE" != "cli" && "$MODE" != "skill" ]]; then
  echo "ERROR: Unknown mode '$MODE'. Use 'cli' or 'skill'." >&2
  exit 1
fi

if [[ "$MODE" == "skill" ]]; then
  # Verify claude CLI is available for headless execution
  if ! command -v claude &>/dev/null; then
    echo "ERROR: claude CLI not found in PATH (required for skill mode)" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Resolve snapshot path
# ---------------------------------------------------------------------------
if [[ -z "$SNAPSHOT" ]]; then
  MANIFEST="${SCRIPT_DIR}/snapshot-manifest.json"
  if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: No snapshot specified and snapshot-manifest.json not found at $MANIFEST" >&2
    exit 1
  fi
  # Extract path from manifest, resolve relative to HOME
  SNAPSHOT=$(python3 -c "
import json, os, sys
with open('$MANIFEST') as f:
    m = json.load(f)
# Support both old 'path' (with ~) and new 'path_relative_to_home' keys
if 'path_relative_to_home' in m:
    print(os.path.join(os.path.expanduser('~'), m['path_relative_to_home']))
else:
    print(os.path.expanduser(m['path']))
")
fi

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "ERROR: Snapshot not found at: $SNAPSHOT" >&2
  exit 1
fi

# Validate snapshot hash against manifest (if manifest exists)
if [[ -f "${SCRIPT_DIR}/snapshot-manifest.json" ]]; then
  EXPECTED_HASH=$(python3 -c "
import json
with open('${SCRIPT_DIR}/snapshot-manifest.json') as f:
    print(json.load(f).get('hash_prefix', ''))
")
  if [[ -n "$EXPECTED_HASH" ]]; then
    ACTUAL_HASH=$(shasum -a 256 "$SNAPSHOT" | awk '{print substr($1, 1, 16)}')
    if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
      echo "ERROR: Snapshot hash mismatch. Expected $EXPECTED_HASH, got $ACTUAL_HASH" >&2
      echo "Run scripts/benchmark/prepare-snapshot.sh to refresh." >&2
      exit 1
    fi
    echo "Snapshot hash verified: $ACTUAL_HASH" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Validate gold queries file
# ---------------------------------------------------------------------------
if [[ ! -f "$GOLD_QUERIES" ]]; then
  echo "ERROR: Gold queries file not found at: $GOLD_QUERIES" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Verify contextify CLI is available
# ---------------------------------------------------------------------------
if ! command -v contextify &>/dev/null; then
  echo "ERROR: contextify CLI not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Create temp DB copy (read-only protection for snapshot)
# ---------------------------------------------------------------------------
TEMP_DIR=$(mktemp -d -t tr-bench-XXXXXX)
TEMP_DB="${TEMP_DIR}/contextify-bench.db"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Copying snapshot to temp location..." >&2
cp "$SNAPSHOT" "$TEMP_DB"
chmod 644 "$TEMP_DB"

# Checkpoint WAL to ensure GRDB/DatabasePool can open cleanly
# (copied WAL-mode databases may have stale WAL state)
sqlite3 "$TEMP_DB" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true

echo "Temp DB ready at: $TEMP_DB" >&2

# ---------------------------------------------------------------------------
# Run queries
# ---------------------------------------------------------------------------
TOTAL_QUERIES=$(python3 -c "
import json, sys
with open('$GOLD_QUERIES') as f:
    q = json.load(f)
print(len(q['queries']))
")

echo "Running $TOTAL_QUERIES gold queries in $MODE mode..." >&2
echo "---" >&2

# Export variables for the Python subprocess
export GOLD_QUERIES_PATH="$GOLD_QUERIES"
export TEMP_DB_PATH="$TEMP_DB"
export VERBOSE="$VERBOSE"
export EVAL_MODE="$MODE"
export SKILL_RUNNER="${SCRIPT_DIR}/run-skill-query.sh"
export PARALLEL_WORKERS="${PARALLEL_WORKERS:-4}"
export TRACE="$TRACE"

# Set up trace directory if tracing enabled
TRACE_DIR="/tmp/benchmark-traces"
if [[ "$TRACE" == "true" ]]; then
  mkdir -p "$TRACE_DIR"
  echo "Trace output: $TRACE_DIR/" >&2
fi
export TRACE_DIR

# ---------------------------------------------------------------------------
# Compute expected SKILL.md hash (skill mode only)
# ---------------------------------------------------------------------------
SKILL_PATH="${REPO_DIR}/contextify-query/user-skill/total-recall/SKILL.md"
if [[ "$MODE" == "skill" ]]; then
  if [[ ! -f "$SKILL_PATH" ]]; then
    echo "ERROR: SKILL.md not found at $SKILL_PATH" >&2
    exit 1
  fi
  EXPECTED_SKILL_HASH=$(shasum -a 256 "$SKILL_PATH" | cut -c1-8)
  export EXPECTED_SKILL_HASH
  echo "SKILL.md hash: $EXPECTED_SKILL_HASH (from $SKILL_PATH)" >&2
fi

# Use Python to drive the evaluation loop for reliable JSON handling
python3 << 'PYEOF'
import json
import subprocess
import sys
import os
import re
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

gold_queries_path = os.environ.get("GOLD_QUERIES_PATH")
temp_db_path = os.environ.get("TEMP_DB_PATH")
verbose = os.environ.get("VERBOSE") == "true"
eval_mode = os.environ.get("EVAL_MODE", "cli")
skill_runner = os.environ.get("SKILL_RUNNER", "")
expected_skill_hash = os.environ.get("EXPECTED_SKILL_HASH", "")
# Parallel workers for skill mode (CLI mode is already fast)
parallel_workers = int(os.environ.get("PARALLEL_WORKERS", "4")) if eval_mode == "skill" else 1
# Track skill hash verification across queries
skill_hash_verified = 0
skill_hash_missing = 0
skill_hash_mismatch = 0
# Track behavioral compliance across queries
behavioral_days_365 = 0
behavioral_snippet_100 = 0
behavioral_db_path = 0
behavioral_total = 0
# Trace support (ct-728)
trace_enabled = os.environ.get("TRACE") == "true"
trace_dir = os.environ.get("TRACE_DIR", "/tmp/benchmark-traces")

stopwords = {"the", "that", "this", "with", "from", "have",
             "been", "were", "will", "does", "about", "into",
             "what", "when", "where", "which", "their", "there",
             "some", "more", "also", "than", "other", "each"}

def strip_markdown(text):
    """Remove bold, italic, and other markdown markers for clean text matching."""
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'__(.+?)__', r'\1', text)
    text = re.sub(r'_(.+?)_', r'\1', text)
    text = re.sub(r'`(.+?)`', r'\1', text)
    return text

# Negation signals that indicate the AI did NOT find the content.
# When present, word-level matches are held to a higher threshold
# to avoid false positives from topic-adjacent "not found" responses.
# Calibrated in ct-729 (2026-03-27). Do not change without re-calibration.
NEGATION_SIGNALS = [
    "not found", "no results", "no conversation", "no discussion",
    "no record", "couldn't find", "could not find", "zero results",
    "no matches", "no relevant", "no evidence", "no mention",
    "nothing about", "didn't find", "did not find", "no references",
    "unable to find", "no information",
    "nothing specifically",
]

# Fingerprint matching threshold. Calibrated in ct-729:
#   0.70 = best F1 (0.878) on 20 TP + 11 TN labeled pairs
#   Negation penalty +0.25 -> F1 0.900
# FROZEN: do not change without new calibration data.
FINGERPRINT_THRESHOLD = 0.70
NEGATION_PENALTY = 0.25

def check_fingerprint(fp_clean, clean_response):
    """Check if fingerprint content appears in response using word-level matching.

    Calibrated in ct-729 (2026-03-27). Changes require re-running
    calibrate-fingerprint.py with updated labeled pairs.

    Strategy:
    1. Exact substring match is authoritative (AI quoted the content)
    2. Word-level stem matching with 0.70 threshold
    3. Negation-aware: if response contains "not found" etc., threshold
       increases by 0.25 to reduce false positives from topic-adjacent responses
    4. Numeric tokens >= 3 chars qualify (catches issue IDs like "287")
    """
    if not fp_clean:
        return False
    if fp_clean in clean_response:
        return True
    # Include numeric tokens >= 3 chars (issue IDs like "287" are discriminating)
    words = [w for w in re.findall(r'[a-z0-9]+', fp_clean)
             if (len(w) >= 4 and w not in stopwords) or (w.isdigit() and len(w) >= 3)]
    if not words:
        return False
    # Extract all response words for stem matching
    response_words = set(re.findall(r'[a-z0-9]+', clean_response))
    def stem_match(fp_word):
        """Check if fingerprint word matches any response word by shared stem."""
        # Numeric tokens require exact word match (no stemming, no substring)
        if fp_word.isdigit():
            return fp_word in response_words
        if fp_word in clean_response:
            return True
        # Try stem matching: if fp_word[:n] matches any response word[:n]
        stem = fp_word[:min(len(fp_word), 5)] if len(fp_word) >= 5 else fp_word[:4]
        return any(rw.startswith(stem) for rw in response_words if len(rw) >= 4)
    matches = sum(1 for w in words if stem_match(w))
    ratio = matches / len(words)
    # Apply negation penalty when response contains "not found" signals
    has_negation = any(sig in clean_response for sig in NEGATION_SIGNALS)
    threshold = min(FINGERPRINT_THRESHOLD + NEGATION_PENALTY, 1.0) if has_negation else FINGERPRINT_THRESHOLD
    return ratio >= threshold

def fingerprint_details(fp_clean, clean_response):
    """Return diagnostic details for a fingerprint check (trace-only, no scoring impact)."""
    if not fp_clean:
        return {"status": "no_fingerprint"}
    if fp_clean in clean_response:
        return {"status": "exact_match", "threshold": FINGERPRINT_THRESHOLD, "match_ratio": 1.0}
    words = [w for w in re.findall(r'[a-z0-9]+', fp_clean)
             if (len(w) >= 4 and w not in stopwords) or (w.isdigit() and len(w) >= 3)]
    if not words:
        return {"status": "no_qualifying_words", "threshold": FINGERPRINT_THRESHOLD}
    response_words = set(re.findall(r'[a-z0-9]+', clean_response))
    def stem_match(fp_word):
        if fp_word.isdigit():
            return fp_word in response_words
        if fp_word in clean_response:
            return True
        stem = fp_word[:min(len(fp_word), 5)] if len(fp_word) >= 5 else fp_word[:4]
        return any(rw.startswith(stem) for rw in response_words if len(rw) >= 4)
    matched = [w for w in words if stem_match(w)]
    unmatched = [w for w in words if not stem_match(w)]
    ratio = len(matched) / len(words)
    has_negation = any(sig in clean_response for sig in NEGATION_SIGNALS)
    effective_threshold = min(FINGERPRINT_THRESHOLD + NEGATION_PENALTY, 1.0) if has_negation else FINGERPRINT_THRESHOLD
    return {
        "status": "word_match",
        "threshold": FINGERPRINT_THRESHOLD,
        "effective_threshold": effective_threshold,
        "negation_detected": has_negation,
        "match_ratio": round(ratio, 3),
        "matched_words": matched,
        "unmatched_words": unmatched,
        "total_words": len(words),
        "pass": ratio >= effective_threshold,
    }

def write_trace(qid, query_dict, result, response_text="", tool_commands=None, cli_command=None):
    """Write per-query trace file to trace_dir (ct-728)."""
    if not trace_enabled:
        return
    search_cmds = []
    context_cmds = []
    if tool_commands:
        for cmd in tool_commands:
            if "contextify" in cmd and "search" in cmd:
                search_cmds.append(cmd)
            elif "contextify" in cmd and "context" in cmd:
                context_cmds.append(cmd)
    if cli_command:
        search_cmds.append(cli_command)

    fp = query_dict.get("content_fingerprint", "")
    fp_clean = strip_markdown(fp).lower() if fp else ""
    clean_resp = strip_markdown(response_text).lower() if response_text else ""
    fp_details = fingerprint_details(fp_clean, clean_resp) if not result.get("is_negative") else {"status": "negative_query"}

    trace = {
        "query_id": qid,
        "natural_question": query_dict.get("natural_question", query_dict.get("search_terms", "")),
        "search_terms": query_dict.get("search_terms", ""),
        "mode": eval_mode,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "pass": result.get("found", False),
        "is_negative": result.get("is_negative", False),
        "search_commands": search_cmds,
        "context_commands": context_cmds,
        "result_count": result.get("total_results", 0),
        "response_excerpt": (response_text or "")[:500],
        "fingerprint": fp_details,
        "error": result.get("error") or result.get("infra_error"),
        "duration_s": result.get("duration_s", 0),
        "turns": result.get("searches_used", 0),
        "category": result.get("category", ""),
        "difficulty": result.get("difficulty", ""),
        "recall_at_k": result.get("recall_at_k"),
        "mrr": result.get("mrr"),
    }
    trace_path = os.path.join(trace_dir, f"{qid}.json")
    with open(trace_path, "w") as f:
        json.dump(trace, f, indent=2)

def evaluate_query(q):
    """Evaluate a single query. Returns a result dict."""
    qid = q["id"]
    search_terms = q["search_terms"]
    fingerprint = q.get("content_fingerprint")
    expected_result = q.get("expected_result")
    budget = q["efficiency_budget"]
    category = q["category"]
    difficulty = q["difficulty"]
    natural_q = q.get("natural_question", search_terms)
    is_negative = (fingerprint is None and expected_result == "zero_matches")

    try:
        if eval_mode == "skill":
            result = evaluate_skill_query(q, qid, natural_q, fingerprint, budget,
                                          category, difficulty, is_negative)
        else:
            result = evaluate_cli_query(q, qid, search_terms, fingerprint, budget,
                                        category, difficulty, is_negative)
    except subprocess.TimeoutExpired:
        result = {"id": qid, "found": False, "error": "Timeout", "searches_used": 1,
                  "total_results": 0, "category": category, "difficulty": difficulty,
                  "is_negative": is_negative, "duration_s": 0, "natural_q": natural_q}

    # Write per-query trace file (ct-728)
    write_trace(qid, q, result,
                response_text=result.get("_response", ""),
                tool_commands=result.get("_tool_commands"),
                cli_command=result.get("_cli_command"))
    return result

def evaluate_cli_query(q, qid, search_terms, fingerprint, budget, category, difficulty, is_negative):
    cmd = [
        "contextify", "search", search_terms,
        "--db-path", temp_db_path,
        "--json",
        "--full-content",
        "--snippet-tokens", "100",
        "--limit", "20"
    ]
    cli_cmd_str = " ".join(cmd)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

    if proc.returncode != 0:
        try:
            err = json.loads(proc.stdout)
            error_msg = err.get("message", proc.stderr.strip())
        except (json.JSONDecodeError, ValueError):
            error_msg = proc.stderr.strip() or proc.stdout.strip()
        return {"id": qid, "found": False, "error": error_msg,
                "searches_used": 1, "total_results": 0,
                "category": category, "difficulty": difficulty,
                "is_negative": is_negative, "_cli_command": cli_cmd_str}

    try:
        response = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"id": qid, "found": False, "error": "Failed to parse JSON",
                "searches_used": 1, "total_results": 0,
                "category": category, "difficulty": difficulty,
                "is_negative": is_negative, "_cli_command": cli_cmd_str}

    total_results = response.get("metadata", {}).get("totalCount", 0)
    data = response.get("data", [])

    if is_negative:
        query_found = (total_results == 0)
    else:
        raw_output = proc.stdout.lower()
        fp_lower = fingerprint.lower() if fingerprint else ""
        if fp_lower and fp_lower in raw_output:
            query_found = True
        else:
            query_found = False
            if fingerprint:
                for hit in data:
                    snippet = (hit.get("contentSnippet") or "").lower()
                    if fp_lower in snippet:
                        query_found = True
                        break

    # Compute ranked retrieval metrics if relevant_entry_ids are defined
    relevant_ids = set(q.get("relevant_entry_ids", []))
    result_ids = [hit.get("id", "") for hit in data]
    recall_at_k = None
    mrr = None
    if relevant_ids and not is_negative:
        # Recall@k: fraction of relevant entries found in top-k results
        found_relevant = sum(1 for rid in result_ids if rid in relevant_ids)
        recall_at_k = found_relevant / len(relevant_ids)
        # MRR: reciprocal rank of first relevant result (0 if none found)
        mrr = 0.0
        for rank, rid in enumerate(result_ids, start=1):
            if rid in relevant_ids:
                mrr = 1.0 / rank
                break

    return {"id": qid, "found": query_found, "searches_used": 1,
            "total_results": total_results, "category": category,
            "difficulty": difficulty, "is_negative": is_negative,
            "recall_at_k": recall_at_k, "mrr": mrr,
            "_cli_command": cli_cmd_str, "_response": proc.stdout[:500]}

def evaluate_skill_query(q, qid, natural_q, fingerprint, budget, category, difficulty, is_negative):
    cmd = ["bash", skill_runner, natural_q, temp_db_path, "180"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=210)

    if proc.returncode != 0:
        err = proc.stderr.strip() or "skill runner failed"
        return {"id": qid, "found": False, "searches_used": 0, "total_results": 0,
                "category": category, "difficulty": difficulty, "is_negative": is_negative,
                "duration_s": 0, "natural_q": natural_q, "infra_error": err[:200]}

    try:
        skill_output = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"id": qid, "found": False, "searches_used": 0, "total_results": 0,
                "category": category, "difficulty": difficulty, "is_negative": is_negative,
                "duration_s": 0, "natural_q": natural_q, "infra_error": "invalid JSON"}

    ai_response = skill_output.get("response", "")
    searches_used = skill_output.get("turns", 1)
    duration = skill_output.get("duration_s", 0)

    # Track behavioral compliance from tool calls
    global behavioral_days_365, behavioral_snippet_100, behavioral_db_path, behavioral_total
    behavioral = skill_output.get("behavioral", {})
    behavioral_total += 1
    if behavioral.get("used_days_365"):
        behavioral_days_365 += 1
    if behavioral.get("used_snippet_tokens_100"):
        behavioral_snippet_100 += 1
    if behavioral.get("used_db_path"):
        behavioral_db_path += 1

    # Verify skill hash in agent output
    global skill_hash_verified, skill_hash_missing, skill_hash_mismatch
    hash_match = re.search(r'skill:([a-f0-9]{8})', ai_response)
    if expected_skill_hash:
        if not hash_match:
            skill_hash_missing += 1
            return {"id": qid, "found": False, "searches_used": 0, "total_results": 0,
                    "category": category, "difficulty": difficulty, "is_negative": is_negative,
                    "duration_s": duration, "natural_q": natural_q,
                    "infra_error": f"skill hash missing from output (expected {expected_skill_hash})"}
        elif hash_match.group(1) != expected_skill_hash:
            skill_hash_mismatch += 1
            return {"id": qid, "found": False, "searches_used": 0, "total_results": 0,
                    "category": category, "difficulty": difficulty, "is_negative": is_negative,
                    "duration_s": duration, "natural_q": natural_q,
                    "infra_error": f"skill hash mismatch: expected {expected_skill_hash}, got {hash_match.group(1)}"}
        else:
            skill_hash_verified += 1

    clean_response = strip_markdown(ai_response).lower()

    if is_negative:
        negative_signals = ["not found", "no results", "no conversation", "no discussion",
                            "no record", "couldn't find", "could not find", "zero results",
                            "no matches", "no relevant", "no evidence", "no mention"]
        query_found = any(sig in clean_response for sig in negative_signals)
    else:
        fp_clean = strip_markdown(fingerprint).lower() if fingerprint else ""
        query_found = check_fingerprint(fp_clean, clean_response)

    tool_cmds = skill_output.get("tool_commands", [])
    return {"id": qid, "found": query_found, "searches_used": searches_used,
            "total_results": 0, "category": category, "difficulty": difficulty,
            "is_negative": is_negative, "duration_s": duration, "natural_q": natural_q,
            "_response": ai_response, "_tool_commands": tool_cmds}

with open(gold_queries_path) as f:
    gq = json.load(f)

queries = gq["queries"]
total = len(queries)
found_count = 0
total_scorable = 0
efficiency_sum = 0.0

results = []

if eval_mode == "skill" and parallel_workers > 1:
    # Parallel execution for skill mode
    future_to_q = {}
    with ThreadPoolExecutor(max_workers=parallel_workers) as executor:
        for q in queries:
            future = executor.submit(evaluate_query, q)
            future_to_q[future] = q

        for future in as_completed(future_to_q):
            result = future.result()
            results.append(result)
            qid = result["id"]
            natural_q = result.get("natural_q", "")

            if "infra_error" in result:
                total_scorable += 1
                if verbose:
                    print(f"  [{qid}] FAIL [infra] - {natural_q[:60]!r}", file=sys.stderr)
            else:
                total_scorable += 1
                if result["found"]:
                    found_count += 1
                budget = next(q["efficiency_budget"] for q in queries if q["id"] == qid)
                efficiency_sum += min(1.0, budget / max(result["searches_used"], 1))
                if verbose:
                    status = "PASS" if result["found"] else "FAIL"
                    dur = result.get("duration_s", 0)
                    turns = result.get("searches_used", 0)
                    print(f"  [{qid}] {status} (turns={turns}, {dur:.1f}s) - {natural_q[:60]!r}", file=sys.stderr)

    # Sort results by query ID for consistent output
    results.sort(key=lambda r: r["id"])
else:
    # Serial execution (CLI mode or parallel_workers=1)
    for q in queries:
        qid = q["id"]
        budget = q["efficiency_budget"]
        natural_q = q.get("natural_question", q["search_terms"])

        result = evaluate_query(q)

        results.append(result)
        total_scorable += 1
        if result.get("found"):
            found_count += 1
        efficiency_sum += min(1.0, budget / max(result.get("searches_used", 1), 1))

        if verbose:
            status = "PASS" if result.get("found") else "FAIL"
            if "error" in result:
                print(f"  [{qid}] {status} ERROR={result['error']}", file=sys.stderr)
            elif eval_mode == "skill":
                dur = result.get("duration_s", 0)
                turns = result.get("searches_used", 0)
                print(f"  [{qid}] {status} (turns={turns}, {dur:.1f}s) - {natural_q[:60]!r}", file=sys.stderr)
            else:
                tr = result.get("total_results", 0)
                r_at_k = result.get("recall_at_k")
                m = result.get("mrr")
                metrics = ""
                if r_at_k is not None:
                    metrics = f" R@k={r_at_k:.3f} MRR={m:.3f}"
                print(f"  [{qid}] {status} ({tr} results{metrics}) - {q['search_terms']!r}", file=sys.stderr)

# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------
if total_scorable > 0:
    found_rate = found_count / total_scorable
    efficiency_factor = efficiency_sum / total
    final_score = found_rate * efficiency_factor * 100
else:
    found_rate = 0.0
    efficiency_factor = 0.0
    final_score = 0.0

# Compute ranked retrieval metrics (Recall@k and MRR) across queries with qrels
recall_values = [r["recall_at_k"] for r in results if r.get("recall_at_k") is not None]
mrr_values = [r["mrr"] for r in results if r.get("mrr") is not None]
mean_recall = sum(recall_values) / len(recall_values) if recall_values else None
mean_mrr = sum(mrr_values) / len(mrr_values) if mrr_values else None

# Print summary to stderr
print("---", file=sys.stderr)
print(f"Queries total:      {total}", file=sys.stderr)
print(f"Queries scorable:   {total_scorable}", file=sys.stderr)
print(f"Queries found:      {found_count}", file=sys.stderr)
print(f"Found rate:         {found_rate:.3f}", file=sys.stderr)
print(f"Efficiency factor:  {efficiency_factor:.3f}", file=sys.stderr)
print(f"Final score:        {final_score:.1f}", file=sys.stderr)
if mean_recall is not None:
    print(f"", file=sys.stderr)
    print(f"Retrieval metrics (queries with qrels: {len(recall_values)}):", file=sys.stderr)
    print(f"  Mean Recall@k:    {mean_recall:.3f}", file=sys.stderr)
    print(f"  Mean MRR:         {mean_mrr:.3f}", file=sys.stderr)

if eval_mode == "skill":
    if expected_skill_hash:
        print(f"", file=sys.stderr)
        print(f"Skill verification: hash={expected_skill_hash}", file=sys.stderr)
        print(f"  Hash:     verified={skill_hash_verified}/{total}  missing={skill_hash_missing}  mismatch={skill_hash_mismatch}", file=sys.stderr)
    if behavioral_total > 0:
        print(f"  Behavior: --days 365={behavioral_days_365}/{behavioral_total}  --snippet-tokens 100={behavioral_snippet_100}/{behavioral_total}  --db-path={behavioral_db_path}/{behavioral_total}", file=sys.stderr)

    # Behavioral compliance hard gate: fail if any requirement missed by >20% of queries
    if behavioral_total > 0:
        compliance_threshold = 0.80
        behavioral_checks = [
            ("--days 365", behavioral_days_365, behavioral_total),
            ("--snippet-tokens 100", behavioral_snippet_100, behavioral_total),
            ("--db-path", behavioral_db_path, behavioral_total),
        ]
        gate_failed = False
        for name, passed, total_b in behavioral_checks:
            rate = passed / total_b
            if rate < compliance_threshold:
                print(f"ERROR: Behavioral gate failed: {name} compliance {passed}/{total_b} ({rate:.0%}) < {compliance_threshold:.0%}", file=sys.stderr)
                gate_failed = True
        if gate_failed:
            print("0.0")
            sys.exit(1)

if verbose:
    print("", file=sys.stderr)
    print("Per-query summary:", file=sys.stderr)
    for r in results:
        status = "PASS" if r["found"] else "FAIL"
        neg = " [negative]" if r.get("is_negative") else ""
        err = f" ERROR={r['error']}" if "error" in r else ""
        metrics = ""
        if r.get("recall_at_k") is not None:
            metrics = f" R@k={r['recall_at_k']:.3f} MRR={r['mrr']:.3f}"
        print(f"  {r['id']}: {status}{neg} (results={r['total_results']}{metrics}){err}", file=sys.stderr)

if trace_enabled:
    print(f"Traces written to: {trace_dir}/ ({len(results)} files)", file=sys.stderr)

# Print final score to stdout (the ONLY stdout output)
print(f"{final_score:.1f}")
PYEOF
