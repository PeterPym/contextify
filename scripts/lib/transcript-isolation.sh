#!/bin/bash
# Transcript Isolation Library
# Purpose: Unified backup/restore for QA and demo transcript isolation
# Usage: Source this file or run as standalone CLI
#
# Lessons from Dec 2025 recovery:
# - Post-restore cleanup for leaked QA fixtures
# - Remove empty .rsync-backups directories
# - Verify results after operations
# - Comprehensive exclude patterns

set -euo pipefail

# Exit codes (globally unique)
EXIT_SUCCESS=0
EXIT_BACKUP_EXISTS=1        # backup: backup already exists
EXIT_NOTHING_TO_BACKUP=2    # backup: nothing to backup
EXIT_MERGE_FAILED=3         # restore: rsync merge error
EXIT_QUIESCE_FAILED=4       # restore: active writes detected
EXIT_INSUFFICIENT_SPACE=5   # backup: disk space check failed
EXIT_NO_BACKUP=6            # restore: no backup to restore
EXIT_NOT_ISOLATED=7         # status: not isolated
EXIT_STALE_LOCK=8           # common: stale lock detected
EXIT_INVALID_ARGS=9         # common: invalid arguments

# Locations
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
CODEX_SESSIONS_DIR="$HOME/.codex/sessions"
CLAUDE_BACKUP_DIR="$HOME/.claude/projects-ISOLATED-BACKUP"
CODEX_BACKUP_DIR="$HOME/.codex/sessions-ISOLATED-BACKUP"
ISOLATION_MARKER="$HOME/.claude/.isolation-marker"

# Logging
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# Safe marker file parser (no source, whitelist only)
read_marker() {
  local marker_file="$1"

  [[ -f "$marker_file" ]] || return 1

  # Whitelist of allowed keys
  local allowed_keys="^(isolation_start_timestamp|calling_script|caller_pid|backup_location|claude_backed_up|codex_backed_up)$"

  while IFS='=' read -r key value; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^# ]] && continue

    # Validate key format
    [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
      log_warn "Invalid marker key: $key (skipped)"
      continue
    }

    # Check if key is allowed
    [[ "$key" =~ $allowed_keys ]] || {
      log_warn "Unknown marker key: $key (skipped)"
      continue
    }

    # Strip quotes
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"

    # Export as environment variable (safe - we control key names)
    export "$key=$value"
  done < "$marker_file"

  # Validate required fields
  [[ -n "${isolation_start_timestamp:-}" ]] || {
    log_error "Marker missing required field: isolation_start_timestamp"
    return 1
  }

  return 0
}

# BSD-safe quiesce check (no -mtime -10s)
quiesce_check() {
  local dir="$1"
  local threshold_seconds="${2:-10}"

  [[ -d "$dir" ]] || return 0

  # Create reference file touched to N seconds ago
  local ref
  ref="$(mktemp)"

  # Try BSD touch syntax first
  if ! touch -t "$(date -v-${threshold_seconds}S +%Y%m%d%H%M.%S 2>/dev/null)" "$ref" 2>/dev/null; then
    # Fallback to -A syntax
    if ! touch -A "-00${threshold_seconds}" "$ref" 2>/dev/null; then
      rm -f "$ref"
      log_warn "Cannot perform quiesce check (touch/date limitations)"
      return 0
    fi
  fi

  # Find files newer than reference
  local recent_count
  recent_count=$(find "$dir" -type f -name '*.jsonl' -newer "$ref" 2>/dev/null | wc -l | tr -d ' ')
  rm -f "$ref"

  if [[ "$recent_count" -gt 0 ]]; then
    if [[ "${YES_MODE:-0}" == "1" ]]; then
      log_error "❌ $recent_count transcripts modified in last ${threshold_seconds}s"
      log_error "Active writes detected. Cannot proceed in non-interactive mode."
      return 1
    else
      log_warn "⚠️  $recent_count transcripts modified in last ${threshold_seconds}s"
      log_warn "Claude/Codex may be actively writing. Continue? (y/N)"
      read -r confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] || return 1
    fi
  fi

  return 0
}

# Rollback partial backup on failure
rollback_partial_backup() {
  local claude_backed_up="$1"
  local codex_backed_up="$2"

  log_error "Partial backup detected - rolling back..."

  if [[ "$claude_backed_up" == "1" ]]; then
    log_info "Restoring Claude projects..."
    rm -rf "$CLAUDE_PROJECTS_DIR"
    mv "$CLAUDE_BACKUP_DIR" "$CLAUDE_PROJECTS_DIR"
  fi

  if [[ "$codex_backed_up" == "1" ]]; then
    log_info "Restoring Codex sessions..."
    rm -rf "$CODEX_SESSIONS_DIR"
    mv "$CODEX_BACKUP_DIR" "$CODEX_SESSIONS_DIR"
  fi

  rm -f "$ISOLATION_MARKER"
  log_error "Rollback complete. System returned to pre-backup state."
}

# LESSON LEARNED: Post-restore cleanup for leaked QA fixtures
cleanup_qa_fixtures() {
  local dir="$1"
  local label="$2"

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Comprehensive QA fixture patterns
  local qa_count=0
  qa_count=$(find "$dir" \( \
    -name "*qa-fixture*" -o \
    -name "*-tmp-contextify-qa-test*" -o \
    -name "*-tmp-contextify-qa-fixture*" -o \
    -name "*-private-tmp-contextify-qa-*" \
  \) 2>/dev/null | wc -l | tr -d ' ')

  if [[ $qa_count -gt 0 ]]; then
    log_warn "Found $qa_count QA fixture(s) in $label, removing..."
    find "$dir" \( \
      -name "*qa-fixture*" -o \
      -name "*-tmp-contextify-qa-test*" -o \
      -name "*-tmp-contextify-qa-fixture*" -o \
      -name "*-private-tmp-contextify-qa-*" \
    \) -delete 2>/dev/null || true
    log_success "✅ QA fixtures removed from $label"
  fi

  # LESSON LEARNED: Clean up empty .rsync-backups directories
  find "$dir" -name ".rsync-backups" -type d -empty -delete 2>/dev/null || true
}

# Backup transcripts
backup_transcripts() {
  local force_mode=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force_mode="--force"; shift ;;
      *) log_error "Unknown argument: $1"; exit $EXIT_INVALID_ARGS ;;
    esac
  done

  log_info "Backing up production transcripts..."

  # Check for existing isolation
  if [[ -f "$ISOLATION_MARKER" ]]; then
    read_marker "$ISOLATION_MARKER" || {
      log_error "Invalid marker file"
      exit $EXIT_STALE_LOCK
    }

    # Check if process still running
    if kill -0 "${caller_pid:-0}" 2>/dev/null; then
      log_error "❌ Isolation already active!"
      log_error "   Started by: ${calling_script:-unknown} (PID ${caller_pid:-unknown})"
      log_error "   Duration: $(($(date +%s) - ${isolation_start_timestamp:-0}))s"
      log_error ""
      log_error "Cannot start new isolation while another is active."
      log_error "Restore first: ./scripts/lib/transcript-isolation.sh restore"
      exit $EXIT_BACKUP_EXISTS
    else
      if [[ "${YES_MODE:-0}" == "1" ]]; then
        log_info "Stale isolation detected (PID ${caller_pid:-unknown} dead), taking over..."
      else
        log_warn "⚠️  Stale isolation detected"
        log_warn "   Started by: ${calling_script:-unknown} (PID ${caller_pid:-unknown})"
        log_warn "   PID ${caller_pid:-unknown} is no longer running"
        log_warn ""
        log_warn "Continue and take over stale lock? (Y/n)"
        read -r confirm
        [[ "$confirm" == "n" || "$confirm" == "N" ]] && exit $EXIT_STALE_LOCK
      fi
    fi
  fi

  # Check disk space (require 2x current size)
  if [[ -d "$CLAUDE_PROJECTS_DIR" ]]; then
    local required_kb
    required_kb=$(($(du -sk "$CLAUDE_PROJECTS_DIR" 2>/dev/null | cut -f1) * 2))
    local available_kb
    available_kb=$(df -k "$HOME" | tail -1 | awk '{print $4}')

    if [[ "$available_kb" -lt "$required_kb" ]]; then
      log_error "❌ Insufficient disk space"
      log_error "   Required: $((required_kb / 1024)) MB"
      log_error "   Available: $((available_kb / 1024)) MB"
      exit $EXIT_INSUFFICIENT_SPACE
    fi
  fi

  # Track per-provider success
  local claude_backed_up=0
  local codex_backed_up=0

  # Backup Claude projects
  if [[ -d "$CLAUDE_PROJECTS_DIR" ]]; then
    if [[ -d "$CLAUDE_BACKUP_DIR" ]]; then
      if [[ "$force_mode" == "--force" ]]; then
        log_warn "Removing existing Claude backup..."
        rm -rf "$CLAUDE_BACKUP_DIR"
      else
        log_error "Claude backup already exists: $CLAUDE_BACKUP_DIR"
        exit $EXIT_BACKUP_EXISTS
      fi
    fi

    mv "$CLAUDE_PROJECTS_DIR" "$CLAUDE_BACKUP_DIR" || {
      log_error "Failed to backup Claude projects"
      exit 1
    }
    mkdir -p "$CLAUDE_PROJECTS_DIR"
    claude_backed_up=1
    log_success "✅ Claude projects backed up"
  else
    log_info "No Claude projects to backup"
  fi

  # Backup Codex sessions
  if [[ -d "$CODEX_SESSIONS_DIR" ]]; then
    if [[ -d "$CODEX_BACKUP_DIR" ]]; then
      if [[ "$force_mode" == "--force" ]]; then
        log_warn "Removing existing Codex backup..."
        rm -rf "$CODEX_BACKUP_DIR"
      else
        log_error "Codex backup already exists: $CODEX_BACKUP_DIR"
        rollback_partial_backup "$claude_backed_up" "$codex_backed_up"
        exit $EXIT_BACKUP_EXISTS
      fi
    fi

    mv "$CODEX_SESSIONS_DIR" "$CODEX_BACKUP_DIR" || {
      log_error "Failed to backup Codex sessions"
      rollback_partial_backup "$claude_backed_up" "$codex_backed_up"
      exit 1
    }
    mkdir -p "$CODEX_SESSIONS_DIR"
    codex_backed_up=1
    log_success "✅ Codex sessions backed up"
  else
    log_info "No Codex sessions to backup"
  fi

  # Nothing was backed up
  if [[ "$claude_backed_up" == "0" && "$codex_backed_up" == "0" ]]; then
    log_error "Nothing to backup"
    exit $EXIT_NOTHING_TO_BACKUP
  fi

  # Write marker with per-provider state
  mkdir -p "$(dirname "$ISOLATION_MARKER")"
  cat > "$ISOLATION_MARKER" << EOF
isolation_start_timestamp=$(date +%s)
calling_script=${BASH_SOURCE[1]:-unknown}
caller_pid=$$
backup_location=$CLAUDE_BACKUP_DIR
claude_backed_up=$claude_backed_up
codex_backed_up=$codex_backed_up
EOF

  log_success "Backup complete!"
  log_info "Backed up: Claude=$claude_backed_up Codex=$codex_backed_up"

  return 0
}

# Restore transcripts (with intelligent merge)
restore_transcripts() {
  local dry_run=0
  local no_merge=0
  local exclude_patterns=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --no-merge)
        no_merge=1
        shift
        ;;
      --exclude)
        exclude_patterns+=("$2")
        shift 2
        ;;
      --yes|--non-interactive)
        export YES_MODE=1
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        exit $EXIT_INVALID_ARGS
        ;;
    esac
  done

  log_info "Restoring production transcripts..."

  # Check if backup exists
  if [[ ! -d "$CLAUDE_BACKUP_DIR" && ! -d "$CODEX_BACKUP_DIR" ]]; then
    log_error "No backup to restore"
    log_error "Run 'status' to check isolation state"
    exit $EXIT_NO_BACKUP
  fi

  # Read marker
  read_marker "$ISOLATION_MARKER" || {
    log_error "Backup exists but marker is invalid"
    exit $EXIT_STALE_LOCK
  }

  # Dry-run mode
  if [[ "$dry_run" == "1" ]]; then
    log_info "DRY RUN - no changes will be made"
    echo ""

    if [[ "$no_merge" == "0" ]]; then
      echo "Would merge new work from current → backup"
      echo "  Exclude patterns: ${exclude_patterns[*]:-<defaults>}"
    else
      echo "⚠️  Would SKIP merge (--no-merge)"
    fi

    echo ""
    echo "Would restore:"
    [[ "${claude_backed_up:-0}" == "1" ]] && echo "  ~/.claude/projects.PREMERGE-<timestamp> ← current"
    [[ "${claude_backed_up:-0}" == "1" ]] && echo "  ~/.claude/projects ← backup"
    [[ "${codex_backed_up:-0}" == "1" ]] && echo "  ~/.codex/sessions.PREMERGE-<timestamp> ← current"
    [[ "${codex_backed_up:-0}" == "1" ]] && echo "  ~/.codex/sessions ← backup"
    echo ""
    echo "Would remove: $ISOLATION_MARKER"

    return 0
  fi

  # Quiesce check (warn if active writes)
  [[ -d "$CLAUDE_PROJECTS_DIR" ]] && { quiesce_check "$CLAUDE_PROJECTS_DIR" 10 || exit $EXIT_QUIESCE_FAILED; }
  [[ -d "$CODEX_SESSIONS_DIR" ]] && { quiesce_check "$CODEX_SESSIONS_DIR" 10 || exit $EXIT_QUIESCE_FAILED; }

  # LESSON LEARNED: More comprehensive exclude patterns
  local default_excludes=(
    "*qa-fixture*"
    "*-tmp-contextify-qa-test*"
    "*-tmp-contextify-qa-fixture*"
    "*-private-tmp-contextify-qa-*"
  )

  # Merge new work (unless --no-merge)
  if [[ "$no_merge" == "0" ]]; then
    if [[ "${claude_backed_up:-0}" == "1" && -d "$CLAUDE_PROJECTS_DIR" ]]; then
      log_info "Merging Claude work: current → backup"

      # Build rsync exclude args
      local rsync_excludes=()
      for pattern in "${default_excludes[@]}" "${exclude_patterns[@]}"; do
        rsync_excludes+=(--exclude="$pattern")
      done

      # Create backup directory for rsync overwrites
      local rsync_backup_dir="$CLAUDE_BACKUP_DIR/.rsync-backups/$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$rsync_backup_dir"

      # Merge with rsync
      rsync -rlptD --no-owner --no-group \
        --update \
        --backup \
        --backup-dir="$rsync_backup_dir" \
        "${rsync_excludes[@]}" \
        "$CLAUDE_PROJECTS_DIR/" \
        "$CLAUDE_BACKUP_DIR/" || {
        log_error "Merge failed (rsync error)"
        exit $EXIT_MERGE_FAILED
      }

      # Report conflicts
      if [[ -n "$(ls -A "$rsync_backup_dir" 2>/dev/null)" ]]; then
        log_warn "⚠️  Some backup files were replaced during merge"
        log_warn "Original backup versions saved to: $rsync_backup_dir"
      else
        rmdir "$rsync_backup_dir" 2>/dev/null || true
      fi

      log_success "Merge complete"
    fi

    # Same for Codex
    if [[ "${codex_backed_up:-0}" == "1" && -d "$CODEX_SESSIONS_DIR" ]]; then
      log_info "Merging Codex work: current → backup"

      local rsync_excludes=()
      for pattern in "${default_excludes[@]}" "${exclude_patterns[@]}"; do
        rsync_excludes+=(--exclude="$pattern")
      done

      local rsync_backup_dir="$CODEX_BACKUP_DIR/.rsync-backups/$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$rsync_backup_dir"

      rsync -rlptD --no-owner --no-group \
        --update \
        --backup \
        --backup-dir="$rsync_backup_dir" \
        "${rsync_excludes[@]}" \
        "$CODEX_SESSIONS_DIR/" \
        "$CODEX_BACKUP_DIR/" || {
        log_error "Merge failed (rsync error)"
        exit $EXIT_MERGE_FAILED
      }

      if [[ -n "$(ls -A "$rsync_backup_dir" 2>/dev/null)" ]]; then
        log_warn "⚠️  Some backup files were replaced during merge"
        log_warn "Original backup versions saved to: $rsync_backup_dir"
      else
        rmdir "$rsync_backup_dir" 2>/dev/null || true
      fi

      log_success "Merge complete"
    fi
  else
    log_warn "⚠️  Skipping merge (--no-merge) - current work will be LOST!"
  fi

  # Atomic restore via rename swap
  local timestamp
  timestamp=$(date +%s)

  if [[ "${claude_backed_up:-0}" == "1" ]]; then
    log_info "Restoring Claude projects..."
    if [[ -d "$CLAUDE_PROJECTS_DIR" ]]; then
      mv "$CLAUDE_PROJECTS_DIR" "$CLAUDE_PROJECTS_DIR.PREMERGE-$timestamp"
    fi
    mv "$CLAUDE_BACKUP_DIR" "$CLAUDE_PROJECTS_DIR"
    log_success "✅ Claude projects restored"

    # LESSON LEARNED: Post-restore cleanup
    cleanup_qa_fixtures "$CLAUDE_PROJECTS_DIR" "Claude"
  fi

  if [[ "${codex_backed_up:-0}" == "1" ]]; then
    log_info "Restoring Codex sessions..."
    if [[ -d "$CODEX_SESSIONS_DIR" ]]; then
      mv "$CODEX_SESSIONS_DIR" "$CODEX_SESSIONS_DIR.PREMERGE-$timestamp"
    fi
    mv "$CODEX_BACKUP_DIR" "$CODEX_SESSIONS_DIR"
    log_success "✅ Codex sessions restored"

    # LESSON LEARNED: Post-restore cleanup
    cleanup_qa_fixtures "$CODEX_SESSIONS_DIR" "Codex"
  fi

  # Remove marker
  rm -f "$ISOLATION_MARKER"

  # Cleanup old PREMERGE directories (older than 7 days)
  find ~/.claude -maxdepth 1 -name "projects.PREMERGE-*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
  find ~/.codex -maxdepth 1 -name "sessions.PREMERGE-*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

  log_success "Restore complete!"
  [[ -d "$CLAUDE_PROJECTS_DIR.PREMERGE-$timestamp" ]] && log_info "Rollback available: $CLAUDE_PROJECTS_DIR.PREMERGE-$timestamp (auto-cleanup in 7 days)"

  return 0
}

# Check isolation status (read-only)
check_isolation_status() {
  local quiet_mode=0

  [[ "${1:-}" == "--quiet" ]] && quiet_mode=1

  # Check for new-style backup
  if [[ -d "$CLAUDE_BACKUP_DIR" || -d "$CODEX_BACKUP_DIR" ]]; then
    [[ "$quiet_mode" == "1" ]] && exit 0

    read_marker "$ISOLATION_MARKER" || {
      log_error "Backup exists but marker is invalid"
      exit $EXIT_STALE_LOCK
    }

    echo "Transcript Isolation Status"
    echo "============================"
    echo ""
    echo "State:              ISOLATED"
    echo "Duration:           $(( ($(date +%s) - ${isolation_start_timestamp:-0}) / 3600 )) hours"
    echo "Isolation started:  $(date -r "${isolation_start_timestamp:-0}" 2>/dev/null || echo 'unknown')"
    echo "Initiated by:       ${calling_script:-unknown} (PID ${caller_pid:-unknown})"

    if kill -0 "${caller_pid:-0}" 2>/dev/null; then
      echo "Process status:     RUNNING"
    else
      echo "Process status:     DEAD (stale lock)"
    fi

    echo ""
    [[ -d "$CLAUDE_BACKUP_DIR" ]] && echo "Claude backup:      $CLAUDE_BACKUP_DIR ($(ls "$CLAUDE_BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ') projects)"
    [[ -d "$CODEX_BACKUP_DIR" ]] && echo "Codex backup:       $CODEX_BACKUP_DIR"
    echo ""
    [[ -d "$CLAUDE_PROJECTS_DIR" ]] && echo "Claude current:     $CLAUDE_PROJECTS_DIR ($(ls "$CLAUDE_PROJECTS_DIR" 2>/dev/null | wc -l | tr -d ' ') projects)"
    [[ -d "$CODEX_SESSIONS_DIR" ]] && echo "Codex current:      $CODEX_SESSIONS_DIR"
    echo ""
    echo "Restore command:    ./scripts/lib/transcript-isolation.sh restore"
    echo "Dry-run command:    ./scripts/lib/transcript-isolation.sh restore --dry-run"

    exit 0
  fi

  # Check for old-style backups (READ-ONLY)
  if [[ -d ~/.claude/projects-QA-BACKUP || -d ~/.claude/projects-REAL-BACKUP ]]; then
    [[ "$quiet_mode" == "1" ]] && exit $EXIT_NOT_ISOLATED

    echo "⚠️  Found old backup format:"
    [[ -d ~/.claude/projects-QA-BACKUP ]] && echo "    ~/.claude/projects-QA-BACKUP"
    [[ -d ~/.claude/projects-REAL-BACKUP ]] && echo "    ~/.claude/projects-REAL-BACKUP"
    echo ""
    echo "Migrate to new format:"
    echo "  ./scripts/lib/transcript-isolation.sh migrate"

    exit $EXIT_NOT_ISOLATED
  fi

  # Not isolated
  [[ "$quiet_mode" == "1" ]] && exit $EXIT_NOT_ISOLATED

  echo "Not isolated (no backup found)"
  exit $EXIT_NOT_ISOLATED
}

# Migrate old backup format (separate command, not in status)
migrate_old_backup() {
  local old_backup=""
  local old_path=""

  if [[ -d ~/.claude/projects-QA-BACKUP ]]; then
    old_backup="~/.claude/projects-QA-BACKUP"
    old_path=~/.claude/projects-QA-BACKUP
  elif [[ -d ~/.claude/projects-REAL-BACKUP ]]; then
    old_backup="~/.claude/projects-REAL-BACKUP"
    old_path=~/.claude/projects-REAL-BACKUP
  else
    log_error "No old backup found to migrate"
    exit 1
  fi

  if [[ -d "$CLAUDE_BACKUP_DIR" ]]; then
    log_error "New backup already exists: $CLAUDE_BACKUP_DIR"
    log_error "Cannot migrate (would overwrite)"
    exit 1
  fi

  log_info "Migrating old backup format..."
  log_info "  From: $old_backup"
  log_info "  To:   $CLAUDE_BACKUP_DIR"
  echo ""

  if [[ "${YES_MODE:-0}" != "1" ]]; then
    log_warn "This will rename the backup directory. Continue? (Y/n)"
    read -r confirm
    [[ "$confirm" == "n" || "$confirm" == "N" ]] && exit 0
  fi

  mv "$old_path" "$CLAUDE_BACKUP_DIR" || {
    log_error "Migration failed"
    exit 1
  }

  # Create marker
  local backup_mtime
  backup_mtime=$(stat -f "%m" "$CLAUDE_BACKUP_DIR" 2>/dev/null || echo "0")
  cat > "$ISOLATION_MARKER" << EOF
isolation_start_timestamp=$backup_mtime
calling_script=migrated-from-old-backup
caller_pid=0
backup_location=$CLAUDE_BACKUP_DIR
claude_backed_up=1
codex_backed_up=0
EOF

  log_success "✅ Migration complete!"
  log_info "Run 'status' to verify"
}

# CLI entry point
main() {
  local command="${1:-}"
  shift || true

  case "$command" in
    backup)
      backup_transcripts "$@"
      ;;
    restore)
      restore_transcripts "$@"
      ;;
    status)
      check_isolation_status "$@"
      ;;
    migrate)
      migrate_old_backup "$@"
      ;;
    --help|-h|help|"")
      cat << 'HELP'
Usage: transcript-isolation.sh <command> [options]

Commands:
  backup              Backup production transcripts
  restore             Restore production transcripts (with merge)
  status              Show isolation status (read-only)
  migrate             Migrate old backup format to new format

Backup Options:
  --force             Overwrite existing backup (DANGEROUS)

Restore Options:
  --dry-run           Show what would happen
  --no-merge          Skip merge (DANGEROUS - loses current work)
  --exclude PATTERN   Exclude pattern from merge (repeatable)
  --yes               Non-interactive mode (fail on prompts)
  --non-interactive   Alias for --yes

Status Options:
  --quiet             Exit code only (0=isolated, 7=not)

Exit Codes:
  0  Success
  1  Backup already exists
  2  Nothing to backup
  3  Merge failed
  4  Quiesce check failed (active writes)
  5  Insufficient disk space
  6  No backup to restore
  7  Not isolated
  8  Stale lock detected
  9  Invalid arguments

Examples:
  # Backup
  transcript-isolation.sh backup

  # Status
  transcript-isolation.sh status

  # Restore (interactive)
  transcript-isolation.sh restore

  # Restore (non-interactive for automation)
  transcript-isolation.sh restore --yes

  # Restore with exclusions
  transcript-isolation.sh restore --exclude '*test*'

  # Migrate old backup
  transcript-isolation.sh migrate
HELP
      exit 0
      ;;
    *)
      log_error "Unknown command: $command"
      echo "Run with --help for usage"
      exit $EXIT_INVALID_ARGS
      ;;
  esac
}

# If executed (not sourced), run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
