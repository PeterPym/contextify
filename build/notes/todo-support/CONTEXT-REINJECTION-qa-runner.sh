#!/usr/bin/env bash
set -u

# Interactive QA runner for contextify-query.
# - Enter to continue
# - Esc to quit

bold() { printf "\033[1m%s\033[0m" "$*"; }

pause_or_quit() {
  printf "\n%s" "Press Enter to continue, or Esc to quit: "
  local key
  IFS= read -rsn1 key || true
  if [[ "$key" == $'\e' ]]; then
    echo
    echo "Exiting QA runner."
    exit 0
  fi
  echo
}

run_step() {
  local title="$1"
  local expected="$2"
  local cmd="$3"

  echo
  echo "============================================================"
  echo "$(bold "Step:") $title"
  echo "$(bold "Expect:") $expected"
  echo "$(bold "Cmd:") $cmd"
  pause_or_quit

  echo "$(bold "Running...")"
  set +e
  eval "$cmd"
  local status=$?
  set -e
  echo "$(bold "Exit:") $status"

  if [[ $status -ne 0 ]]; then
    echo
    echo "$(bold "Note:") Non-zero exit. Press Enter to continue anyway, or Esc to quit."
  fi
  pause_or_quit
}

require_repo_root() {
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Not in a git repo. Run this from the repo root." >&2
    exit 2
  fi
  local root
  root="$(git rev-parse --show-toplevel)"
  cd "$root" || exit 2
}

require_query_executable() {
  if ! swift package dump-package 2>/dev/null | rg -q '"name"\s*:\s*"contextify-query"'; then
    echo "SwiftPM product 'contextify-query' not found in this checkout." >&2
    echo "Hint: switch to the context reinjection branch, e.g.:" >&2
    echo "  git switch p1-context-reinjection-phase1-clean" >&2
    exit 2
  fi
}

main() {
  require_repo_root
  require_query_executable

  echo "$(bold "Contextify Query CLI — Manual QA Runner")"
  echo "Repo: $(git rev-parse --show-toplevel)"
  echo "Branch: $(git branch --show-current)"

  run_step \
    "Help" \
    "Prints usage text." \
    "swift run contextify-query --help"

  run_step \
    "Status (JSON)" \
    "Returns JSON envelope with db path + counts." \
    "swift run contextify-query status --json"

  run_step \
    "Projects (JSON)" \
    "Returns project list." \
    "swift run contextify-query projects --json"

  run_step \
    "Transcripts for current project (JSON)" \
    "Resolves --project . and lists a few transcripts." \
    "swift run contextify-query transcripts --project . --limit 5 --json"

  run_step \
    "Project not found (JSON)" \
    "Fails with dbProjectNotFound and includes structured details.suggestions." \
    "swift run contextify-query transcripts --project /definitely/not/a/project --json"

  run_step \
    "Search with -- terminator (JSON)" \
    "Treats '--help' as a query token (not a flag)." \
    "swift run contextify-query --json search -- --help"

  echo
  echo "$(bold "Interactive:") Choose a search query and entry id for the next steps."
  printf "Search query (default: unread count): "
  read -r query || query=""
  if [[ -z "$query" ]]; then query="unread count"; fi

  run_step \
    "Search (JSON)" \
    "Returns up to 5 ranked hits with entry ids." \
    "swift run contextify-query search \"$query\" --project . --limit 5 --json"

  echo
  echo "Paste an entry id from the search results (UUID, e.g. '5224db66-b1b1-4a10-ac13-dd0b2929f782')."
  printf "ENTRY_ID: "
  read -r entry_id || entry_id=""
  if [[ -z "$entry_id" ]]; then
    echo "No ENTRY_ID provided; skipping entry/context steps." >&2
  else
    run_step \
      "Entry (JSON)" \
      "Returns one entry (or entryNotFound)." \
      "swift run contextify-query entry \"$entry_id\" --json"

    run_step \
      "Context default window (JSON)" \
      "Returns before/anchor/after with deterministic ordering." \
      "swift run contextify-query context \"$entry_id\" --before 10 --after 20 --json"

    run_step \
      "Context metadata-only (JSON)" \
      "Returns content: null." \
      "swift run contextify-query context \"$entry_id\" --before 10 --after 20 --no-content --json"

    run_step \
      "Context larger window (JSON)" \
      "Works with --max-window 2000." \
      "swift run contextify-query context \"$entry_id\" --before 1000 --after 1000 --max-window 2000 --json"

    run_step \
      "Context over cap (JSON)" \
      "Fails with invalidArgs for --max-window > 2000." \
      "swift run contextify-query context \"$entry_id\" --max-window 2001 --json"
  fi

  run_step \
    "Activity last 7 days (JSON)" \
    "Returns recent entries; ids should be usable as context anchors." \
    "swift run contextify-query activity --project . --days 7 --limit 20 --json"

  run_step \
    "Search with --no-content warning (human mode)" \
    "Prints a warning that --no-content has no effect on search." \
    "swift run contextify-query search \"$query\" --project . --limit 3 --no-content"

  run_step \
    "Feedback record (JSON)" \
    "Writes a feedback file under ~/Library/Application Support/Contextify/feedback/." \
    "swift run contextify-query feedback \"qa runner feedback: $query\" --json"

  run_step \
    "Feedback list (JSON)" \
    "Shows pending feedback ids." \
    "swift run contextify-query feedback list --json"

  echo
  echo "Paste a feedback id from the list (e.g., fb_YYYYMMDD_001)."
  printf "FB_ID: "
  read -r fb_id || fb_id=""
  if [[ -n "$fb_id" ]]; then
    run_step \
      "Feedback show (JSON)" \
      "Loads the item." \
      "swift run contextify-query feedback show \"$fb_id\" --json"

    run_step \
      "Feedback export md (JSON)" \
      "Returns markdown content." \
      "swift run contextify-query feedback export \"$fb_id\" --format md --json"

    run_step \
      "Feedback dismiss (JSON)" \
      "Moves to archive/dismissed." \
      "swift run contextify-query feedback dismiss \"$fb_id\" --json"
  else
    echo "No FB_ID provided; skipping feedback show/export/dismiss steps." >&2
  fi

  run_step \
    "Feedback stdin JSON (JSON)" \
    "Records feedback via stdin." \
    "printf '{\"summary\":\"qa runner stdin feedback\"}' | swift run contextify-query feedback --json"

  echo
  echo "QA runner finished."
}

main "$@"
