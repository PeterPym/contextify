#!/usr/bin/env bash
#
# Shared database location discovery for Contextify scripts.
# Source this file: source "$(dirname "$0")/../lib/db_location.sh"
#
# Discovery order:
#   1. Canonical preference `dev.contextify.customDatabaseLocation`
#   2. Legacy mirror `dev.contextify.database_location`
#   3. DMG default `~/Library/Application Support/Contextify`
#
# Returns the directory containing `contextify.db`.
#

CONTEXTIFY_SUITE="dev.contextify"
CANONICAL_DB_DIR_KEY="dev.contextify.customDatabaseLocation"
LEGACY_DB_DIR_KEY="dev.contextify.database_location"

get_contextify_db_dir() {
  local canonical
  canonical=$(defaults read "$CONTEXTIFY_SUITE" "$CANONICAL_DB_DIR_KEY" 2>/dev/null || true)
  if [[ -n "$canonical" && -d "$canonical" ]]; then
    echo "$canonical"
    return 0
  fi

  local legacy
  legacy=$(defaults read "$CONTEXTIFY_SUITE" "$LEGACY_DB_DIR_KEY" 2>/dev/null || true)
  if [[ -n "$legacy" && -d "$legacy" ]]; then
    echo "$legacy"
    return 0
  fi

  local default_dir="$HOME/Library/Application Support/Contextify"
  if [[ -d "$default_dir" ]]; then
    echo "$default_dir"
    return 0
  fi

  return 1
}

