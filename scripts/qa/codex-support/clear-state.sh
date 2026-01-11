#!/bin/bash
# scripts/qa/codex-support/clear-state.sh
#
# Safely clears validation state for Total Recall Codex testing.
# Use --force to skip confirmation prompts.

set -e

FORCE=false
if [ "$1" = "--force" ]; then
  FORCE=true
fi

echo "=== Clearing validation state ==="

# Safety: validate we're removing expected paths only
CLAUDE_SKILL="$HOME/.claude/skills/total-recall"
CODEX_SKILL="$HOME/.codex/skills/total-recall"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/contextify"

validate_path() {
  local path="$1"
  local expected_parent="$2"
  if [[ "$path" != "$expected_parent"* ]]; then
    echo "ERROR: Path $path is not under $expected_parent - aborting"
    exit 1
  fi
}

validate_path "$CLAUDE_SKILL" "$HOME/.claude/"
validate_path "$CODEX_SKILL" "$HOME/.codex/"
validate_path "$PLUGIN_CACHE" "$HOME/.claude/"

echo "Will remove:"
[ -d "$CLAUDE_SKILL" ] && echo "  - $CLAUDE_SKILL"
[ -d "$CODEX_SKILL" ] && echo "  - $CODEX_SKILL"
[ -d "$PLUGIN_CACHE" ] && echo "  - $PLUGIN_CACHE"

if [ "$FORCE" != "true" ]; then
  read -p "Proceed with removal? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

[ -d "$CLAUDE_SKILL" ] && rm -rf "$CLAUDE_SKILL"
[ -d "$CODEX_SKILL" ] && rm -rf "$CODEX_SKILL"
[ -d "$PLUGIN_CACHE" ] && rm -rf "$PLUGIN_CACHE"

MANIFEST="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$MANIFEST" ]; then
  cp "$MANIFEST" "$MANIFEST.backup.$(date +%Y%m%d-%H%M%S)"
  jq 'del(.plugins["query@contextify"])' "$MANIFEST" > /tmp/manifest.tmp
  mv /tmp/manifest.tmp "$MANIFEST"
  echo "Manifest updated (backup created)"
fi

echo "State cleared successfully"
