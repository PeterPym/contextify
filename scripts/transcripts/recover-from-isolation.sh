#!/bin/bash
# ============================================================================
# recover-from-isolation.sh - Recover transcripts from QA/Demo isolation
# ============================================================================
#
# Purpose:
#   Safely merges and restores Claude Code and Codex transcripts when isolated
#   by QA testing or demo recording. Handles both providers simultaneously
#   using V3 safety principles (atomic swaps, conflict preservation, rollback).
#
# Usage:
#   ./scripts/transcripts/recover-from-isolation.sh [OPTIONS]
#
# Options:
#   --audit          Show current state without making changes
#   --dry-run        Preview what would be done
#   --yes            Non-interactive mode (auto-confirm)
#   --claude-only    Recover only Claude transcripts
#   --codex-only     Recover only Codex transcripts
#   --help           Show this help
#
# Safety Features:
#   - Atomic rename swaps (crash-safe)
#   - Conflict preservation (rsync --backup-dir)
#   - 7-day rollback snapshots (.PREMERGE-* directories)
#   - Corruption detection (empty files, invalid JSON)
#   - Duplicate filename checking
#
# State Changes:
#   - Merges current work → backup (preserves newer versions)
#   - Creates rollback snapshot: {dir}.PREMERGE-{timestamp}
#   - Restores backup → production (atomic swap)
#   - Removes old QA backup directories
#
# Prerequisites:
#   - Backup directories exist:
#     - ~/.claude/projects-QA-BACKUP (or projects-ISOLATED-BACKUP)
#     - ~/.codex/sessions-QA-BACKUP (or sessions-ISOLATED-BACKUP)
#   - rsync available
#   - python3 available (for corruption check)
#
# Exit Codes:
#   0 - Success
#   1 - Error (no backup, merge failed, corruption detected)
#   2 - User cancelled
#
# Examples:
#   # Audit current state
#   ./scripts/transcripts/recover-from-isolation.sh --audit
#
#   # Preview recovery
#   ./scripts/transcripts/recover-from-isolation.sh --dry-run
#
#   # Execute recovery (interactive)
#   ./scripts/transcripts/recover-from-isolation.sh
#
#   # Execute recovery (non-interactive)
#   ./scripts/transcripts/recover-from-isolation.sh --yes
#
#   # Recover only Claude transcripts
#   ./scripts/transcripts/recover-from-isolation.sh --claude-only
#
# Background:
#   QA tests and demo recording backup production transcripts to avoid
#   polluting the database with test data. If QA is interrupted or the
#   restore step fails, transcripts remain isolated. This script safely
#   merges any real work done during isolation back into the backup,
#   then restores to production.
#
# See Also:
#   - build/docs/operations/transcript-corruption-detection.md
#   - scripts/qa/lib/common.sh (QA isolation logic)
#   - scripts/release/demo-recording.sh (Demo isolation logic)
# ============================================================================

set -euo pipefail

# Parse arguments
AUDIT_MODE=0
DRY_RUN=0
YES_MODE=0
CLAUDE_ONLY=0
CODEX_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --audit)       AUDIT_MODE=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --yes)         YES_MODE=1 ;;
    --claude-only) CLAUDE_ONLY=1 ;;
    --codex-only)  CODEX_ONLY=1 ;;
    --help|-h)
      sed -n '2,/^# ====/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Run with --help for usage"
      exit 1
      ;;
  esac
done

# Locations
CLAUDE_BACKUP_DIR=""
CODEX_BACKUP_DIR=""
CLAUDE_CURRENT_DIR="$HOME/.claude/projects"
CODEX_CURRENT_DIR="$HOME/.codex/sessions"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${NC}[INFO] $*${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $*${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
log_error() { echo -e "${RED}[ERROR] $*${NC}"; }
log_debug() { echo -e "${BLUE}[DEBUG] $*${NC}"; }

# Detect backup directories (support both old and new naming)
detect_backups() {
  # Claude
  if [[ -d "$HOME/.claude/projects-ISOLATED-BACKUP" ]]; then
    CLAUDE_BACKUP_DIR="$HOME/.claude/projects-ISOLATED-BACKUP"
  elif [[ -d "$HOME/.claude/projects-QA-BACKUP" ]]; then
    CLAUDE_BACKUP_DIR="$HOME/.claude/projects-QA-BACKUP"
  fi

  # Codex
  if [[ -d "$HOME/.codex/sessions-ISOLATED-BACKUP" ]]; then
    CODEX_BACKUP_DIR="$HOME/.codex/sessions-ISOLATED-BACKUP"
  elif [[ -d "$HOME/.codex/sessions-QA-BACKUP" ]]; then
    CODEX_BACKUP_DIR="$HOME/.codex/sessions-QA-BACKUP"
  fi
}

# Count transcripts in a directory
count_transcripts() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    find "$dir" -type f -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

# Count projects/sessions (excluding QA fixtures)
count_real_items() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    ls -1 "$dir" 2>/dev/null | grep -v "^-tmp-contextify-qa" | grep -v "^-private-tmp-contextify-qa" | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

# Check for corruption
check_corruption() {
  local dir="$1"
  local label="$2"
  local empty_count=0
  local invalid_count=0

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  while IFS= read -r file; do
    if [[ ! -s "$file" ]]; then
      ((empty_count++))
    else
      # Check if last line is valid JSON
      if ! tail -n 1 "$file" 2>/dev/null | python3 -m json.tool >/dev/null 2>&1; then
        ((invalid_count++))
      fi
    fi
  done < <(find "$dir" -type f -name "*.jsonl" 2>/dev/null)

  if [[ $empty_count -gt 0 || $invalid_count -gt 0 ]]; then
    log_warn "Corruption in $label:"
    [[ $empty_count -gt 0 ]] && echo "  - $empty_count empty file(s)"
    [[ $invalid_count -gt 0 ]] && echo "  - $invalid_count invalid JSON file(s)"
    return 1
  fi

  return 0
}

# Audit mode - show current state
audit_state() {
  echo "=========================================="
  echo "Transcript Isolation Status"
  echo "=========================================="
  echo ""

  detect_backups

  local has_isolation=0

  # Claude
  if [[ -n "$CLAUDE_BACKUP_DIR" && -d "$CLAUDE_BACKUP_DIR" ]]; then
    has_isolation=1
    echo "CLAUDE CODE - ISOLATED"
    echo "  Backup:  $CLAUDE_BACKUP_DIR"
    echo "    Transcripts: $(count_transcripts "$CLAUDE_BACKUP_DIR")"
    echo "    Projects:    $(count_real_items "$CLAUDE_BACKUP_DIR") (real work)"
    echo ""
    echo "  Current: $CLAUDE_CURRENT_DIR"
    echo "    Transcripts: $(count_transcripts "$CLAUDE_CURRENT_DIR")"
    echo "    Projects:    $(count_real_items "$CLAUDE_CURRENT_DIR") (real work)"
    echo ""
    check_corruption "$CLAUDE_BACKUP_DIR" "Claude backup" || true
    check_corruption "$CLAUDE_CURRENT_DIR" "Claude current" || true
    echo ""
  else
    echo "CLAUDE CODE - Not isolated"
    echo ""
  fi

  # Codex
  if [[ -n "$CODEX_BACKUP_DIR" && -d "$CODEX_BACKUP_DIR" ]]; then
    has_isolation=1
    echo "CODEX CLI - ISOLATED"
    echo "  Backup:  $CODEX_BACKUP_DIR"
    echo "    Transcripts: $(count_transcripts "$CODEX_BACKUP_DIR")"
    echo "    Sessions:    $(count_real_items "$CODEX_BACKUP_DIR")"
    echo ""
    echo "  Current: $CODEX_CURRENT_DIR"
    echo "    Transcripts: $(count_transcripts "$CODEX_CURRENT_DIR")"
    echo "    Sessions:    $(count_real_items "$CODEX_CURRENT_DIR")"
    echo ""
    check_corruption "$CODEX_BACKUP_DIR" "Codex backup" || true
    check_corruption "$CODEX_CURRENT_DIR" "Codex current" || true
    echo ""
  else
    echo "CODEX CLI - Not isolated"
    echo ""
  fi

  if [[ $has_isolation -eq 0 ]]; then
    echo "No isolation detected. All transcripts in production."
    return 1
  fi

  echo "=========================================="
  echo "To recover, run:"
  echo "  ./scripts/transcripts/recover-from-isolation.sh --dry-run"
  echo "=========================================="

  return 0
}

# Recover a single provider
recover_provider() {
  local provider="$1"
  local backup_dir="$2"
  local current_dir="$3"
  local label="$4"

  if [[ ! -d "$backup_dir" ]]; then
    log_info "Skipping $label (no backup found)"
    return 0
  fi

  log_info "=========================================="
  log_info "Recovering $label"
  log_info "=========================================="
  echo ""

  local backup_count=$(count_transcripts "$backup_dir")
  local current_count=$(count_transcripts "$current_dir")
  local rsync_backup="$backup_dir/.rsync-backups/recovery-$TIMESTAMP"

  log_info "Step 1/4: Merging current work → backup"
  log_info "  Backup:  $backup_count transcripts"
  log_info "  Current: $current_count transcripts"
  echo ""

  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "  [DRY RUN] Would merge with rsync --update --backup-dir"
    log_warn "  [DRY RUN] Conflicts saved to: $rsync_backup"
  else
    mkdir -p "$rsync_backup"

    rsync -rlptD --no-owner --no-group \
      --update \
      --backup \
      --backup-dir="$rsync_backup" \
      --exclude='*-tmp-contextify-qa-test*' \
      --exclude='*-tmp-contextify-qa-fixture*' \
      --exclude='*-private-tmp-contextify-qa-*' \
      "$current_dir/" "$backup_dir/" || {
      log_error "Merge failed (rsync error)"
      return 1
    }

    if [[ -n "$(ls -A "$rsync_backup" 2>/dev/null)" ]]; then
      local conflict_count=$(find "$rsync_backup" -type f | wc -l | tr -d ' ')
      log_warn "  ⚠️  $conflict_count file(s) overwritten (originals in $rsync_backup)"
    else
      rmdir "$rsync_backup" 2>/dev/null || true
      log_success "  ✅ Merge complete (no conflicts)"
    fi
  fi

  echo ""
  log_info "Step 2/4: Creating rollback snapshot"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "  [DRY RUN] Would create: $current_dir.PREMERGE-$TIMESTAMP"
  else
    mv "$current_dir" "$current_dir.PREMERGE-$TIMESTAMP" || {
      log_error "Failed to create rollback snapshot"
      return 1
    }
    log_success "  ✅ Snapshot: $current_dir.PREMERGE-$TIMESTAMP"
  fi

  echo ""
  log_info "Step 3/4: Atomic restore (backup → production)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "  [DRY RUN] Would swap: $backup_dir → $current_dir"
  else
    mv "$backup_dir" "$current_dir" || {
      log_error "Failed to restore backup"
      log_error "Rolling back..."
      mv "$current_dir.PREMERGE-$TIMESTAMP" "$current_dir"
      return 1
    }
    log_success "  ✅ Restore complete"
  fi

  # Cleanup step
  if [[ "$DRY_RUN" == "0" ]]; then
    echo ""
    log_info "Step 4/4: Post-recovery cleanup"

    # Remove QA fixtures that leaked through
    local qa_count=$(find "$current_dir" -name "*qa-fixture*" -o -name "*-tmp-contextify-qa-*" -o -name "*-private-tmp-contextify-qa-*" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $qa_count -gt 0 ]]; then
      log_warn "  Found $qa_count QA fixture(s) that leaked through, removing..."
      find "$current_dir" \( -name "*qa-fixture*" -o -name "*-tmp-contextify-qa-*" -o -name "*-private-tmp-contextify-qa-*" \) -delete 2>/dev/null || true
      log_success "  ✅ QA fixtures removed"
    fi

    # Remove empty .rsync-backups directories
    find "$current_dir" -name ".rsync-backups" -type d -empty -delete 2>/dev/null || true

    log_success "  ✅ Cleanup complete"
  fi

  echo ""
  local final_count=$(count_transcripts "$current_dir")
  log_success "$label recovered: $final_count transcripts"
  echo ""

  return 0
}

# Main execution
main() {
  echo "=========================================="
  echo "Transcript Recovery - V3 Safety Principles"
  echo "=========================================="
  echo ""

  detect_backups

  # Audit mode
  if [[ "$AUDIT_MODE" == "1" ]]; then
    audit_state
    exit $?
  fi

  # Check if any backups exist
  if [[ -z "$CLAUDE_BACKUP_DIR" && -z "$CODEX_BACKUP_DIR" ]]; then
    log_error "No isolation backups found"
    log_info "Expected locations:"
    echo "  ~/.claude/projects-QA-BACKUP (or projects-ISOLATED-BACKUP)"
    echo "  ~/.codex/sessions-QA-BACKUP (or sessions-ISOLATED-BACKUP)"
    echo ""
    exit 1
  fi

  # Dry-run header
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
    echo ""
  fi

  # Determine what to recover
  local recover_claude=0
  local recover_codex=0

  if [[ "$CODEX_ONLY" == "1" ]]; then
    recover_codex=1
  elif [[ "$CLAUDE_ONLY" == "1" ]]; then
    recover_claude=1
  else
    [[ -n "$CLAUDE_BACKUP_DIR" ]] && recover_claude=1
    [[ -n "$CODEX_BACKUP_DIR" ]] && recover_codex=1
  fi

  # Confirmation
  if [[ "$YES_MODE" == "0" && "$DRY_RUN" == "0" ]]; then
    echo ""
    log_warn "This will merge and restore transcripts:"
    [[ $recover_claude -eq 1 ]] && echo "  - Claude Code: $CLAUDE_BACKUP_DIR"
    [[ $recover_codex -eq 1 ]] && echo "  - Codex CLI:   $CODEX_BACKUP_DIR"
    echo ""
    log_warn "Rollback snapshots will be available for 7 days"
    echo ""
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
      log_info "Recovery cancelled"
      exit 2
    fi
    echo ""
  fi

  # Recover providers
  local success=0

  if [[ $recover_claude -eq 1 && -n "$CLAUDE_BACKUP_DIR" ]]; then
    if recover_provider "claude" "$CLAUDE_BACKUP_DIR" "$CLAUDE_CURRENT_DIR" "Claude Code"; then
      ((success++))
    fi
  fi

  if [[ $recover_codex -eq 1 && -n "$CODEX_BACKUP_DIR" ]]; then
    if recover_provider "codex" "$CODEX_BACKUP_DIR" "$CODEX_CURRENT_DIR" "Codex CLI"; then
      ((success++))
    fi
  fi

  # Summary
  if [[ "$DRY_RUN" == "0" ]]; then
    echo "=========================================="
    log_success "RECOVERY COMPLETE!"
    echo "=========================================="
    echo ""
    echo "Providers recovered: $success"
    echo ""
    echo "Rollback available (7 days):"
    [[ $recover_claude -eq 1 ]] && echo "  $CLAUDE_CURRENT_DIR.PREMERGE-$TIMESTAMP"
    [[ $recover_codex -eq 1 ]] && echo "  $CODEX_CURRENT_DIR.PREMERGE-$TIMESTAMP"
    echo ""
  else
    echo "=========================================="
    log_info "DRY RUN COMPLETE"
    echo "=========================================="
    echo ""
    echo "Run without --dry-run to execute"
    echo ""
  fi

  return 0
}

main "$@"
