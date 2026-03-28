#!/usr/bin/env bash
# ratchet.sh - Total Recall benchmark ratchet loop wrapper
#
# Thin wrapper around the generic ratchet-loop.sh framework with
# TR-specific defaults: evaluates the Total Recall SKILL.md against
# the gold query benchmark using the contextify CLI.
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
# Run the ratchet loop
# ---------------------------------------------------------------------------
exec bash "$RATCHET_LOOP" \
  --evaluator "$EVALUATOR" \
  --artifact "$ARTIFACT" \
  --log "$LOG_DIR" \
  --eval-args "--mode $MODE" \
  "${EXTRA_ARGS[@]}"
