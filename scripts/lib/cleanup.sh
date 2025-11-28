#!/usr/bin/env bash
#
# Shared cleanup functions for Contextify scripts
# Source this file: source "$(dirname "$0")/../lib/cleanup.sh"
#
# Functions:
#   clean_userdefaults_for_bid <bundle_id>  - Clear UserDefaults domains
#   clean_caches_for_bid <bundle_id>        - Clear app caches
#   clean_all_prefs_for_bid <bundle_id>     - Clear prefs + caches (no DB)
#

# Shared preferences suite name (used across both DMG and App Store builds)
CONTEXTIFY_SUITE="dev.contextify"

# Clean UserDefaults for a bundle ID (both global and sandbox container)
# Usage: clean_userdefaults_for_bid "sh.contextify.Contextify"
clean_userdefaults_for_bid() {
  local bid="$1"

  # Clear via defaults command (clears non-sandboxed domain)
  defaults delete "$bid" >/dev/null 2>&1 || true
  defaults delete "$CONTEXTIFY_SUITE" >/dev/null 2>&1 || true

  # Remove plist files (both global and sandbox container)
  # Global domain
  rm -f "$HOME/Library/Preferences/$bid.plist" 2>/dev/null || true
  rm -f "$HOME/Library/Preferences/$CONTEXTIFY_SUITE.plist" 2>/dev/null || true

  # Sandbox container domain (critical for App Store builds)
  local container="$HOME/Library/Containers/$bid/Data/Library/Preferences"
  rm -f "$container/$bid.plist" 2>/dev/null || true
  rm -f "$container/$CONTEXTIFY_SUITE.plist" 2>/dev/null || true
}

# Clean caches for a bundle ID
# Usage: clean_caches_for_bid "sh.contextify.Contextify"
clean_caches_for_bid() {
  local bid="$1"

  # Global caches
  rm -rf "$HOME/Library/Caches/$bid" 2>/dev/null || true

  # Sandbox container caches
  rm -rf "$HOME/Library/Containers/$bid/Data/Library/Caches" 2>/dev/null || true
}

# Clean all preferences and caches (but NOT database/Application Support)
# Usage: clean_all_prefs_for_bid "sh.contextify.Contextify"
clean_all_prefs_for_bid() {
  local bid="$1"
  clean_userdefaults_for_bid "$bid"
  clean_caches_for_bid "$bid"
}

# Get sandbox container base path for a bundle ID
# Usage: container_path=$(sandbox_container_for_bid "sh.contextify.Contextify")
sandbox_container_for_bid() {
  local bid="$1"
  echo "$HOME/Library/Containers/$bid"
}

# Get Application Support path for a bundle ID (sandbox-aware)
# Usage: app_support=$(app_support_for_bid "sh.contextify.Contextify")
app_support_for_bid() {
  local bid="$1"
  local container="$HOME/Library/Containers/$bid/Data/Library/Application Support/Contextify"
  if [[ -d "$container" ]]; then
    echo "$container"
  else
    echo "$HOME/Library/Application Support/Contextify"
  fi
}
