#!/usr/bin/env bash
set -euo pipefail

# Interactive manual QA runner for Context reinjection Phase 2 (skills + CLI install).
# Keys: Enter to continue, Esc to quit.

if [ -n "${CONTEXTIFY_REPO_ROOT:-}" ]; then
  REPO_ROOT="$CONTEXTIFY_REPO_ROOT"
else
  REPO_ROOT="$(pwd -P)"
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: REPO_ROOT is not a git repo: $REPO_ROOT"
  echo "Run from the repo root or set CONTEXTIFY_REPO_ROOT."
  exit 64
fi

DMG_APP_PATH="${DMG_APP_PATH:-$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app}"
APPSTORE_APP_PATH="${APPSTORE_APP_PATH:-$REPO_ROOT/.derived-appstore/Build/Products/Debug/Contextify.app}"

CLI_BUNDLED_PATH="$DMG_APP_PATH/Contents/MacOS/contextify-query"
SKILLS_BUNDLED_DIR="$DMG_APP_PATH/Contents/Resources/contextify-query/skills"
PLUGIN_BUNDLED_DIR="$DMG_APP_PATH/Contents/Resources/contextify-query/claude-plugin"
SHIM_BUNDLED_PATH="$DMG_APP_PATH/Contents/Resources/contextify-query/shim/contextify-query-shim"

DEFAULTS_DOMAIN="dev.contextify"
DMG_INSTALL_OVERRIDE_KEY="Contextify.QueryCLI.DMGInstallDirOverride"
SETTINGS_TAB_OVERRIDE_KEY="Contextify.Settings.SelectedTabOverride"

QA_INSTALL_DIR="${QA_INSTALL_DIR:-/tmp/contextify-qa-bin}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
hr() { printf "%s\n" "────────────────────────────────────────────────────────────"; }

wait_key() {
  printf "\nPress Enter to continue, Esc to quit: "
  IFS= read -r -s -n 1 key || true
  printf "\n"
  if [ "${key:-}" = $'\e' ]; then
    echo "Quit."
    exit 0
  fi
}

run_cmd() {
  local cmd="$*"
  hr
  bold "Command:"
  echo "  $cmd"
  hr
  eval "$cmd"
}

ui_step() {
  hr
  bold "Manual UI step:"
  printf "%s\n" "$1"
  if [ -n "${2:-}" ]; then
    printf "\nExpected:\n%s\n" "$2"
  fi
  hr
  wait_key
}

bold "Contextify Phase 2 QA (skills + CLI install)"
echo "Repo: $REPO_ROOT"
echo "DMG app path: $DMG_APP_PATH"
echo "App Store app path: $APPSTORE_APP_PATH"
echo "This script runs shell checks and pauses for manual UI steps."

wait_key

bold "0) Set QA-only overrides (deterministic, non-privileged install)"
echo "Will set:"
echo "- $DEFAULTS_DOMAIN $DMG_INSTALL_OVERRIDE_KEY = $QA_INSTALL_DIR"
echo "- $DEFAULTS_DOMAIN $SETTINGS_TAB_OVERRIDE_KEY = cli"
echo "Expected: DMG install uses $QA_INSTALL_DIR instead of /opt/homebrew/bin or /usr/local/bin."
wait_key
run_cmd "mkdir -p \"$QA_INSTALL_DIR\""
run_cmd "defaults write \"$DEFAULTS_DOMAIN\" \"$DMG_INSTALL_OVERRIDE_KEY\" -string \"$QA_INSTALL_DIR\""
run_cmd "defaults write \"$DEFAULTS_DOMAIN\" \"$SETTINGS_TAB_OVERRIDE_KEY\" -string \"cli\""

bold "1) Build DMG app"
echo "Will run: swift test, then bash scripts/xc.sh build"
echo "Expected: tests pass; build succeeds with 0 warnings."
wait_key
run_cmd "cd \"$REPO_ROOT\" && swift test"
run_cmd "cd \"$REPO_ROOT\" && bash scripts/xc.sh build 2>&1 | tee /tmp/contextify-phase2-build.log | (rg \"warning:\" -n && exit 1 || true)"

bold "2) Verify bundled artifacts exist (DMG)"
echo "Expected: bundled CLI + bundled skills + plugin skeleton + bundled shim exist."
wait_key
run_cmd "test -x \"$CLI_BUNDLED_PATH\" && echo \"OK: bundled CLI executable\""
run_cmd "test -d \"$SKILLS_BUNDLED_DIR\" && echo \"OK: bundled skills dir\""
run_cmd "test -f \"$SKILLS_BUNDLED_DIR/claude/contextify-reinject/SKILL.md\" && echo \"OK: claude reinject skill\""
run_cmd "test -f \"$SKILLS_BUNDLED_DIR/claude/contextify-query-debug/SKILL.md\" && echo \"OK: claude debug skill\""
run_cmd "test -f \"$PLUGIN_BUNDLED_DIR/.claude-plugin/plugin.json\" && echo \"OK: plugin.json\""
run_cmd "test -x \"$SHIM_BUNDLED_PATH\" && echo \"OK: bundled shim executable\""

bold "3) Verify bundled CLI runs directly (DMG)"
echo "Expected: exit 0 and JSON output."
wait_key
run_cmd "\"$CLI_BUNDLED_PATH\" status --json"

bold "4) Open app and install shim from UI (DMG)"
ui_step \
  "In Contextify (DMG build): open Settings (Cmd+,), go to the \"CLI\" tab (should open there with the override), and click \"Install/Repair (Recommended)\".\n\nIf a sudo snippet appears, stop and inspect why the override did not take effect." \
  "Expected: install succeeds without sudo, and the installed shim path is under $QA_INSTALL_DIR."

bold "5) Verify contextify-query runs via shim (prefer DMG app bundle)"
echo "Expected: command -v prints a path, and status returns JSON exit 0 (or dbNotFound exit 2 on first-run)."
echo "Note: If multiple Contextify installs exist on this machine, force the shim to use this DMG bundle via CONTEXTIFY_QUERY_APP_PATH."
wait_key
run_cmd "command -v contextify-query || true"
run_cmd "CONTEXTIFY_QUERY_APP_PATH=\"$DMG_APP_PATH\" contextify-query status --json || true"

bold "6) Verify uninstall from UI (DMG)"
ui_step \
  "In Settings → CLI tab, click \"Uninstall\" (only appears if a Contextify shim is detected)." \
  "Expected: removes the Contextify-installed shim and leaves unrelated PATH entries untouched."

bold "7) Claude Code plugin commands present (manual)"
ui_step \
  "In Settings → CLI tab, confirm the plugin install commands are visible:\n\n/plugin marketplace add PeterPym/contextify\n/plugin install query@contextify" \
  "Expected: commands shown exactly, with text selection enabled."

bold "8) Optional: verify new E2E log tags exist"
echo "Will stream Contextify logs and grep for [QUERYCLI-...] tags."
echo "Manual step: trigger actions in the CLI tab while this is running."
wait_key
run_cmd "/usr/bin/log stream --style syslog --level info --predicate 'subsystem == \"dev.contextify\" && category == \"QueryCLIInstall\"' --timeout 15 | rg \"\\[QUERYCLI-\" || true"

bold "Done."
echo "Build log: /tmp/contextify-phase2-build.log"

