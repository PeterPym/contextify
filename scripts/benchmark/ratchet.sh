#!/usr/bin/env bash
# ratchet.sh - Total Recall benchmark ratchet loop wrapper
#
# Thin wrapper around the generic ratchet-loop.sh framework with
# TR-specific defaults: evaluates the Total Recall SKILL.md against
# the gold query benchmark using the contextify CLI.
#
# Ratchet policy (ct-779):
# - CLI ratchet: uses Recall@k/MRR metrics (non-saturated). Enabled when
#   retriever lane metrics are available.
# - Skill ratchet: ADVISORY ONLY. Prints results but does not auto-accept/reject.
#   Skill changes require a confirmatory blocked experiment.
#
# Usage:
#   bash scripts/benchmark/ratchet.sh [--iterations N] [--demo] [--mode cli|skill]
#
# All additional arguments are forwarded to ratchet-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# TR-specific defaults
# ---------------------------------------------------------------------------
EVALUATOR="${SCRIPT_DIR}/evaluate.sh"
ARTIFACT="${HOME}/.claude/skills/total-recall/SKILL.md"
LOG_DIR="${SCRIPT_DIR}/runs"
MODE="cli"

# Generic ratchet loop location
RATCHET_LOOP="${HOME}/code/projects/cli-ai-setup/utils/benchmark/ratchet-loop.sh"

# ---------------------------------------------------------------------------
# Verify dependencies
# ---------------------------------------------------------------------------
if [[ ! -x "$RATCHET_LOOP" ]]; then
  echo "ERROR: Generic ratchet loop not found at: $RATCHET_LOOP" >&2
  echo "Install cli-ai-setup or adjust RATCHET_LOOP path." >&2
  exit 1
fi

if [[ ! -f "$EVALUATOR" ]]; then
  echo "ERROR: Evaluator not found at: $EVALUATOR" >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "ERROR: SKILL.md not found at: $ARTIFACT" >&2
  echo "Is the Total Recall skill installed?" >&2
  exit 1
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Parse TR-specific args, forward the rest
# ---------------------------------------------------------------------------
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"; shift 2 ;;
    --artifact)
      ARTIFACT="$2"; shift 2 ;;
    *)
      EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Mode-specific policy (ct-779)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "skill" ]]; then
  echo "ADVISORY: Skill mode ratchet is advisory-only (ct-779)." >&2
  echo "Running evaluation for informational purposes. Artifact will NOT be modified." >&2
  echo "For merge decisions, use: evaluate.sh --mode skill --compare <A> <B> --runs 5" >&2
  echo "" >&2

  # Run evaluation only, no artifact modification loop
  ITERATIONS=1
  for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "$arg" == "--iterations" ]]; then
      # Next arg is the count - capture from EXTRA_ARGS
      :
    fi
  done
  # Parse --iterations from EXTRA_ARGS for reporting
  ITER_COUNT=1
  for i in "${!EXTRA_ARGS[@]}"; do
    if [[ "${EXTRA_ARGS[$i]}" == "--iterations" ]]; then
      ITER_COUNT="${EXTRA_ARGS[$((i+1))]:-1}"
      break
    fi
  done

  echo "Running $ITER_COUNT advisory evaluation(s)..." >&2
  for run in $(seq 1 "$ITER_COUNT"); do
    echo "--- Advisory run $run/$ITER_COUNT ---" >&2
    SCORE=$(bash "$EVALUATOR" --mode "$MODE" --verbose 2>&1 | tee /dev/stderr | tail -1)
    echo "  Score: $SCORE (advisory, no artifact change)" >&2
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)	$SCORE	advisory	$MODE" >> "$LOG_DIR/advisory.tsv"
  done
  echo "" >&2
  echo "Advisory evaluation complete. See $LOG_DIR/advisory.tsv for results." >&2
  echo "To make SKILL.md changes, edit manually and re-evaluate." >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Run the ratchet loop (CLI mode only)
# ---------------------------------------------------------------------------
# CLI mode uses Recall@k/MRR metrics (non-saturated) via --verbose output.
exec bash "$RATCHET_LOOP" \
  --evaluator "$EVALUATOR" \
  --artifact "$ARTIFACT" \
  --log "$LOG_DIR" \
  --eval-args "--mode $MODE --verbose" \
  "${EXTRA_ARGS[@]}"
