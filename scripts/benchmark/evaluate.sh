#!/usr/bin/env bash
# evaluate.sh - Total Recall benchmark evaluator
#
# Runs gold queries against a frozen DB snapshot and scores the results.
# Final score (0-100) is printed as the last line on stdout.
# All diagnostic output goes to stderr.
#
# Usage:
#   bash scripts/benchmark/evaluate.sh [--gold-queries PATH] [--snapshot PATH] [--mode cli|skill] [--verbose]

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
    --help|-h)
      echo "Usage: evaluate.sh [--gold-queries PATH] [--snapshot PATH] [--mode cli|skill] [--verbose]" >&2
      echo "" >&2
      echo "Options:" >&2
      echo "  --gold-queries PATH  Path to gold queries JSON (default: scripts/benchmark/gold-queries.json)" >&2
      echo "  --snapshot PATH      Path to frozen DB snapshot (default: from snapshot-manifest.json)" >&2
      echo "  --mode cli|skill     Execution mode (default: cli)" >&2
      echo "  --verbose            Show per-query results on stderr" >&2
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

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

# Use Python to drive the evaluation loop for reliable JSON handling
python3 << 'PYEOF'
import json
import subprocess
import sys
import os

gold_queries_path = os.environ.get("GOLD_QUERIES_PATH")
temp_db_path = os.environ.get("TEMP_DB_PATH")
verbose = os.environ.get("VERBOSE") == "true"
eval_mode = os.environ.get("EVAL_MODE", "cli")
skill_runner = os.environ.get("SKILL_RUNNER", "")

with open(gold_queries_path) as f:
    gq = json.load(f)

queries = gq["queries"]
total = len(queries)
found_count = 0
total_scorable = 0  # queries that count toward found_rate
efficiency_sum = 0.0

results = []

for q in queries:
    qid = q["id"]
    search_terms = q["search_terms"]
    fingerprint = q.get("content_fingerprint")
    expected_result = q.get("expected_result")
    budget = q["efficiency_budget"]
    category = q["category"]
    difficulty = q["difficulty"]

    is_negative = (fingerprint is None and expected_result == "zero_matches")

    try:
        if eval_mode == "skill":
            # Skill mode: run headless Claude Code via run-skill-query.sh
            natural_q = q.get("natural_question", search_terms)
            cmd = ["bash", skill_runner, natural_q, temp_db_path, "120"]

            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=150
            )

            if proc.returncode != 0:
                result = {
                    "id": qid,
                    "found": False,
                    "error": proc.stderr.strip()[:200] or "skill runner failed",
                    "searches_used": 0,
                    "total_results": 0
                }
                results.append(result)
                total_scorable += 1
                efficiency_sum += 0
                if verbose:
                    print(f"  [{qid}] ERROR: skill runner failed", file=sys.stderr)
                continue

            # Parse structured output from run-skill-query.sh
            try:
                skill_output = json.loads(proc.stdout)
            except json.JSONDecodeError:
                skill_output = {"response": proc.stdout, "turns": 0, "cost_usd": 0, "duration_s": 0}

            ai_response = skill_output.get("response", "")
            searches_used = skill_output.get("turns", 1)  # turns approximates searches
            duration = skill_output.get("duration_s", 0)

            # Strip markdown formatting for fingerprint comparison
            import re
            def strip_markdown(text):
                """Remove bold, italic, and other markdown markers for clean text matching."""
                text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)  # bold
                text = re.sub(r'\*(.+?)\*', r'\1', text)  # italic
                text = re.sub(r'__(.+?)__', r'\1', text)  # bold alt
                text = re.sub(r'_(.+?)_', r'\1', text)  # italic alt
                text = re.sub(r'`(.+?)`', r'\1', text)  # code
                return text

            clean_response = strip_markdown(ai_response).lower()

            if is_negative:
                # For negative proof in skill mode: the AI should report "not found" or similar
                negative_signals = ["not found", "no results", "no conversation", "no discussion",
                                    "no record", "couldn't find", "could not find", "zero results",
                                    "no matches", "no relevant", "no evidence", "no mention",
                                    "don't have any", "do not have any"]
                query_found = any(sig in clean_response for sig in negative_signals)
                total_scorable += 1
                if query_found:
                    found_count += 1
            else:
                # Check if fingerprint appears in the cleaned AI response
                # Strip markdown from fingerprint too (it may contain * for italics)
                fp_clean = strip_markdown(fingerprint).lower() if fingerprint else ""
                query_found = bool(fp_clean and fp_clean in clean_response)

                total_scorable += 1
                if query_found:
                    found_count += 1

            efficiency_sum += min(1.0, budget / max(searches_used, 1))

            result = {
                "id": qid,
                "found": query_found,
                "searches_used": searches_used,
                "total_results": 0,
                "category": category,
                "difficulty": difficulty,
                "is_negative": is_negative,
                "duration_s": duration
            }
            results.append(result)

            if verbose:
                status = "PASS" if query_found else "FAIL"
                neg_label = " [negative]" if is_negative else ""
                print(f"  [{qid}] {status}{neg_label} (turns={searches_used}, {duration:.1f}s) - {natural_q[:60]!r}", file=sys.stderr)

        else:
            # CLI mode: run contextify search directly
            cmd = [
                "contextify", "search", search_terms,
                "--db-path", temp_db_path,
                "--json",
                "--full-content",
                "--snippet-tokens", "100",
                "--limit", "20"
            ]

            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60
            )

            if proc.returncode != 0:
                try:
                    err = json.loads(proc.stdout)
                    error_msg = err.get("message", proc.stderr.strip())
                except (json.JSONDecodeError, ValueError):
                    error_msg = proc.stderr.strip() or proc.stdout.strip()

                result = {
                    "id": qid,
                    "found": False,
                    "error": error_msg,
                    "searches_used": 1,
                    "total_results": 0
                }
                results.append(result)
                total_scorable += 1
                efficiency_sum += min(1.0, budget / 1.0)

                if verbose:
                    print(f"  [{qid}] ERROR: {error_msg}", file=sys.stderr)
                continue

            try:
                response = json.loads(proc.stdout)
            except json.JSONDecodeError:
                result = {
                    "id": qid,
                    "found": False,
                    "error": "Failed to parse JSON response",
                    "searches_used": 1,
                    "total_results": 0
                }
                results.append(result)
                total_scorable += 1
                efficiency_sum += min(1.0, budget / 1.0)
                if verbose:
                    print(f"  [{qid}] ERROR: Failed to parse JSON", file=sys.stderr)
                continue

            total_results = response.get("metadata", {}).get("totalCount", 0)
            data = response.get("data", [])

            if is_negative:
                query_found = (total_results == 0)
                total_scorable += 1
                if query_found:
                    found_count += 1
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

                total_scorable += 1
                if query_found:
                    found_count += 1

            searches_used = 1
            efficiency_sum += min(1.0, budget / searches_used)

            result = {
                "id": qid,
                "found": query_found,
                "searches_used": searches_used,
                "total_results": total_results,
                "category": category,
                "difficulty": difficulty,
                "is_negative": is_negative
            }
            results.append(result)

            if verbose:
                status = "PASS" if query_found else "FAIL"
                neg_label = " [negative]" if is_negative else ""
                print(f"  [{qid}] {status}{neg_label} ({total_results} results) - {search_terms!r}", file=sys.stderr)

    except subprocess.TimeoutExpired:
        result = {
            "id": qid,
            "found": False,
            "error": "Timeout",
            "searches_used": 1,
            "total_results": 0
        }
        results.append(result)
        total_scorable += 1
        efficiency_sum += min(1.0, budget / 1.0)
        if verbose:
            print(f"  [{qid}] TIMEOUT", file=sys.stderr)

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

# Print summary to stderr
print("---", file=sys.stderr)
print(f"Queries total:      {total}", file=sys.stderr)
print(f"Queries scorable:   {total_scorable}", file=sys.stderr)
print(f"Queries found:      {found_count}", file=sys.stderr)
print(f"Found rate:         {found_rate:.3f}", file=sys.stderr)
print(f"Efficiency factor:  {efficiency_factor:.3f}", file=sys.stderr)
print(f"Final score:        {final_score:.1f}", file=sys.stderr)

if verbose:
    print("", file=sys.stderr)
    print("Per-query summary:", file=sys.stderr)
    for r in results:
        status = "PASS" if r["found"] else "FAIL"
        neg = " [negative]" if r.get("is_negative") else ""
        err = f" ERROR={r['error']}" if "error" in r else ""
        print(f"  {r['id']}: {status}{neg} (results={r['total_results']}){err}", file=sys.stderr)

# Print final score to stdout (the ONLY stdout output)
print(f"{final_score:.1f}")
PYEOF
