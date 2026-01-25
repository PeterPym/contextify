#!/bin/bash
# ============================================================================
# v1.3.0 CLI Installation Automated Validation
# ============================================================================
#
# This script validates the unified CLI installation for v1.3.0.
# It tests BOTH installation methods with full isolation between tests.
#
# Tests:
#   1. Homebrew installation (fully automated)
#   2. DMG-installed CLI verification (after manual install)
#
# Usage:
#   ./scripts/qa/v1.3.0-cli-validation.sh [--homebrew-only] [--dmg-only] [--skip-cleanup]
#
# Output:
#   /tmp/v1.3.0-cli-validation-report.md
#
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT="/tmp/v1.3.0-cli-validation-report.md"

# Parse args
TEST_HOMEBREW=true
TEST_DMG=true
SKIP_CLEANUP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --homebrew-only) TEST_DMG=false; shift ;;
    --dmg-only) TEST_HOMEBREW=false; shift ;;
    --skip-cleanup) SKIP_CLEANUP=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ============================================================================
# Report helpers
# ============================================================================

init_report() {
  cat > "$REPORT" << 'EOF'
---
session_id: automated-validation
date: DATEPLACEHOLDER
project: contextify
branch: main-wb3
status: in-progress
---

# v1.3.0 CLI Installation Validation Report

## Summary

| Test | Status | Notes |
|------|--------|-------|
EOF
  sed -i '' "s/DATEPLACEHOLDER/$(date +%Y-%m-%d)/" "$REPORT"
}

add_summary_row() {
  local test="$1"
  local status="$2"
  local notes="$3"
  echo "| $test | $status | $notes |" >> "$REPORT"
}

add_section() {
  echo "" >> "$REPORT"
  echo "## $1" >> "$REPORT"
  echo "" >> "$REPORT"
}

add_evidence() {
  echo '```' >> "$REPORT"
  cat >> "$REPORT"
  echo '```' >> "$REPORT"
}

log_info() { echo -e "${BLUE}==>${NC} $1"; }
log_ok() { echo -e "${GREEN}OK${NC} $1"; }
log_fail() { echo -e "${RED}FAIL${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN${NC} $1"; }

# ============================================================================
# Sanitization
# ============================================================================

sanitize_environment() {
  add_section "Environment Sanitization"

  echo "### Pre-sanitization State" >> "$REPORT"
  echo "" >> "$REPORT"

  # Capture pre-state
  {
    echo "Date: $(date)"
    echo ""
    echo "CLI binaries found:"
    for cmd in contextify contextify-query contextify-ingest; do
      path=$(which "$cmd" 2>/dev/null || echo "not found")
      echo "  $cmd: $path"
    done
    echo ""
    echo "Homebrew status:"
    brew list contextify-query 2>/dev/null && echo "  contextify-query: installed" || echo "  contextify-query: not installed"
    brew tap 2>/dev/null | grep contextify || echo "  tap: not present"
    echo ""
    echo "App installed:"
    [[ -d "/Applications/Contextify.app" ]] && echo "  /Applications/Contextify.app: YES" || echo "  /Applications/Contextify.app: NO"
    echo ""
    echo "Database (PRESERVED):"
    DB_PATH="$HOME/Library/Application Support/Contextify"
    [[ -d "$DB_PATH" ]] && echo "  $DB_PATH: $(du -sh "$DB_PATH" 2>/dev/null | cut -f1)" || echo "  not present"
  } | add_evidence

  log_info "Sanitizing environment..."

  # Quit app
  osascript -e 'quit app "Contextify"' 2>/dev/null || true
  sleep 1

  # Remove app (but NOT database)
  if [[ -d "/Applications/Contextify.app" ]]; then
    rm -rf "/Applications/Contextify.app"
    log_ok "Removed /Applications/Contextify.app"
  fi

  # Remove CLI binaries
  LOCATIONS=(
    "/usr/local/bin/contextify"
    "/usr/local/bin/contextify-query"
    "/usr/local/bin/contextify-ingest"
    "$HOME/bin/contextify"
    "$HOME/bin/contextify-query"
    "$HOME/bin/contextify-ingest"
    "$HOME/.local/bin/contextify"
    "$HOME/.local/bin/contextify-query"
    "$HOME/.local/bin/contextify-ingest"
  )
  for loc in "${LOCATIONS[@]}"; do
    if [[ -e "$loc" || -L "$loc" ]]; then
      rm -f "$loc" 2>/dev/null || sudo rm -f "$loc" 2>/dev/null || true
      log_ok "Removed $loc"
    fi
  done

  # Uninstall Homebrew
  if brew list contextify-query &>/dev/null; then
    brew uninstall contextify-query
    log_ok "Uninstalled Homebrew formula"
  fi

  if brew tap 2>/dev/null | grep -q "peterpym/contextify"; then
    brew untap peterpym/contextify
    log_ok "Untapped peterpym/contextify"
  fi

  # Clear cache
  rm -rf "$(brew --cache)/downloads/"*contextify* 2>/dev/null || true

  # Remove skills
  rm -rf "$HOME/.claude/skills/total-recall" 2>/dev/null || true
  rm -rf "$HOME/.codex/skills/total-recall" 2>/dev/null || true

  # Verify clean
  echo "" >> "$REPORT"
  echo "### Post-sanitization State" >> "$REPORT"
  echo "" >> "$REPORT"

  CLEAN=true
  {
    for cmd in contextify contextify-query contextify-ingest; do
      if which "$cmd" &>/dev/null; then
        echo "WARNING: $cmd still at $(which $cmd)"
        CLEAN=false
      else
        echo "OK: $cmd not found"
      fi
    done
  } | add_evidence

  if $CLEAN; then
    log_ok "Environment is clean"
    return 0
  else
    log_fail "Environment not fully clean"
    return 1
  fi
}

# ============================================================================
# Homebrew Test
# ============================================================================

test_homebrew_installation() {
  add_section "Test: Homebrew Installation"

  log_info "Testing Homebrew installation..."

  echo "### Installation" >> "$REPORT"
  echo "" >> "$REPORT"

  # Install
  {
    echo "$ brew tap peterpym/contextify"
    brew tap peterpym/contextify 2>&1
    echo ""
    echo "$ brew install contextify-query"
    brew install contextify-query 2>&1
  } | add_evidence

  # Refresh PATH
  export PATH="$(brew --prefix)/bin:$PATH"
  hash -r

  echo "" >> "$REPORT"
  echo "### Verification" >> "$REPORT"
  echo "" >> "$REPORT"

  PASS=true

  # Check 1: Binary location
  BREW_BIN="$(brew --prefix)/bin"
  echo "**Binary location:**" >> "$REPORT"
  {
    echo "$ ls -la $BREW_BIN/contextify*"
    ls -la "$BREW_BIN"/contextify* 2>&1
  } | add_evidence

  if [[ -x "$BREW_BIN/contextify" ]]; then
    log_ok "contextify binary exists"
  else
    log_fail "contextify binary not found"
    PASS=false
  fi

  # Check 2: Version
  echo "" >> "$REPORT"
  echo "**Version check:**" >> "$REPORT"
  {
    echo "$ $BREW_BIN/contextify --version"
    "$BREW_BIN/contextify" --version 2>&1
  } | add_evidence

  VERSION=$("$BREW_BIN/contextify" --version 2>/dev/null)
  if [[ "$VERSION" == "contextify 1.3.0" ]]; then
    log_ok "Version: $VERSION"
  else
    log_fail "Version mismatch: $VERSION"
    PASS=false
  fi

  # Check 3: File types
  echo "" >> "$REPORT"
  echo "**File type verification:**" >> "$REPORT"
  {
    echo "$ file $BREW_BIN/contextify"
    file "$BREW_BIN/contextify"
    echo ""
    echo "$ file $BREW_BIN/contextify-query"
    file "$BREW_BIN/contextify-query"
    echo ""
    echo "$ file $BREW_BIN/contextify-ingest"
    file "$BREW_BIN/contextify-ingest"
  } | add_evidence

  # Check contextify is Mach-O, others are symlinks
  if file "$BREW_BIN/contextify" | grep -q "Mach-O"; then
    log_ok "contextify is Mach-O binary"
  else
    log_fail "contextify is not Mach-O binary"
    PASS=false
  fi

  if [[ -L "$BREW_BIN/contextify-query" ]]; then
    TARGET=$(readlink "$BREW_BIN/contextify-query")
    log_ok "contextify-query is symlink -> $TARGET"
  else
    log_fail "contextify-query is not a symlink"
    PASS=false
  fi

  if [[ -L "$BREW_BIN/contextify-ingest" ]]; then
    TARGET=$(readlink "$BREW_BIN/contextify-ingest")
    log_ok "contextify-ingest is symlink -> $TARGET"
  else
    log_fail "contextify-ingest is not a symlink"
    PASS=false
  fi

  # Check 4: Functional test
  echo "" >> "$REPORT"
  echo "**Functional test:**" >> "$REPORT"
  {
    echo "$ $BREW_BIN/contextify status"
    "$BREW_BIN/contextify" status 2>&1 || true
  } | add_evidence

  if "$BREW_BIN/contextify" status 2>&1 | grep -q "db_path:"; then
    log_ok "contextify status works"
  else
    log_fail "contextify status failed"
    PASS=false
  fi

  # Check 5: Plugin files (in Cellar share, not main share)
  echo "" >> "$REPORT"
  echo "**Plugin files:**" >> "$REPORT"
  CELLAR_SHARE="$(brew --cellar)/contextify-query/1.3.0/share"
  {
    echo "$ ls -la $CELLAR_SHARE/"
    ls -la "$CELLAR_SHARE/" 2>&1 || echo "Directory not found"
    echo ""
    echo "$ ls -la $CELLAR_SHARE/claude-plugin/ 2>/dev/null | head -5"
    ls -la "$CELLAR_SHARE/claude-plugin/" 2>/dev/null | head -5 || echo "Not found"
    echo ""
    echo "$ ls -la $CELLAR_SHARE/user-skill/total-recall/ 2>/dev/null"
    ls -la "$CELLAR_SHARE/user-skill/total-recall/" 2>/dev/null || echo "Not found"
  } | add_evidence

  if [[ -d "$CELLAR_SHARE/claude-plugin" ]]; then
    log_ok "Plugin files present"
  else
    log_fail "Plugin files missing"
    PASS=false
  fi

  if [[ -f "$CELLAR_SHARE/user-skill/total-recall/SKILL.md" ]]; then
    log_ok "Total Recall skill present"
  else
    log_fail "Total Recall skill missing"
    PASS=false
  fi

  # Check 6: install-plugin command
  echo "" >> "$REPORT"
  echo "**Install plugin test:**" >> "$REPORT"
  {
    echo "$ $BREW_BIN/contextify install-plugin"
    "$BREW_BIN/contextify" install-plugin 2>&1 || true
    echo ""
    echo "$ ls -la ~/.claude/skills/total-recall/"
    ls -la ~/.claude/skills/total-recall/ 2>&1 || echo "Not found"
    echo ""
    echo "$ grep 'contextify search' ~/.claude/skills/total-recall/SKILL.md | head -3"
    grep 'contextify search' ~/.claude/skills/total-recall/SKILL.md 2>/dev/null | head -3 || echo "Pattern not found"
  } | add_evidence

  if [[ -f "$HOME/.claude/skills/total-recall/SKILL.md" ]]; then
    if grep -q "contextify search" "$HOME/.claude/skills/total-recall/SKILL.md"; then
      log_ok "Skill uses 'contextify' command"
    else
      log_warn "Skill may use old command name"
    fi
  else
    log_fail "Skill not installed"
    PASS=false
  fi

  # Summary
  if $PASS; then
    add_summary_row "Homebrew" "PASS" "All checks passed"
    return 0
  else
    add_summary_row "Homebrew" "FAIL" "See details above"
    return 1
  fi
}

# ============================================================================
# DMG Test (verification only - install is manual)
# ============================================================================

test_dmg_verification() {
  add_section "Test: DMG Installation Verification"

  log_info "Verifying DMG-installed CLI..."

  # Check if DMG exists
  DMG_PATH="$ROOT_DIR/dist/Contextify.dmg"
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "DMG not found at $DMG_PATH" >> "$REPORT"
    add_summary_row "DMG" "SKIP" "DMG not found"
    return 1
  fi

  echo "### DMG Verification" >> "$REPORT"
  echo "" >> "$REPORT"
  {
    echo "$ ls -la $DMG_PATH"
    ls -la "$DMG_PATH"
    echo ""
    echo "$ shasum -a 256 $DMG_PATH"
    shasum -a 256 "$DMG_PATH"
    echo ""
    echo "$ spctl -a -t open --context context:primary-signature $DMG_PATH"
    spctl -a -t open --context context:primary-signature "$DMG_PATH" 2>&1 && echo "Gatekeeper: PASS" || echo "Gatekeeper: FAIL"
  } | add_evidence

  # Mount and inspect
  echo "" >> "$REPORT"
  echo "### DMG Contents" >> "$REPORT"
  echo "" >> "$REPORT"

  hdiutil attach "$DMG_PATH" -nobrowse -quiet
  sleep 2

  {
    echo "$ ls -la /Volumes/Contextify/"
    ls -la /Volumes/Contextify/
    echo ""
    echo "$ ls -la /Volumes/Contextify/Contextify.app/Contents/MacOS/"
    ls -la /Volumes/Contextify/Contextify.app/Contents/MacOS/
    echo ""
    echo "$ file /Volumes/Contextify/Contextify.app/Contents/MacOS/contextify-query"
    file /Volumes/Contextify/Contextify.app/Contents/MacOS/contextify-query 2>&1 || echo "Not found"
  } | add_evidence

  # Check bundled CLI version
  BUNDLED_CLI="/Volumes/Contextify/Contextify.app/Contents/MacOS/contextify-query"
  if [[ -x "$BUNDLED_CLI" ]]; then
    echo "" >> "$REPORT"
    echo "### Bundled CLI Version" >> "$REPORT"
    echo "" >> "$REPORT"
    {
      echo "$ $BUNDLED_CLI --version"
      "$BUNDLED_CLI" --version 2>&1
    } | add_evidence
  fi

  hdiutil detach /Volumes/Contextify -quiet 2>/dev/null || true

  # Check if app is installed and CLI is available
  echo "" >> "$REPORT"
  echo "### Installed CLI Check" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "*Note: DMG CLI installation requires manual 'Install CLI' action in app.*" >> "$REPORT"
  echo "" >> "$REPORT"

  # Check common install locations
  FOUND=false
  for loc in "/usr/local/bin/contextify" "$HOME/.local/bin/contextify" "$HOME/bin/contextify"; do
    if [[ -x "$loc" ]]; then
      FOUND=true
      {
        echo "Found CLI at: $loc"
        echo ""
        echo "$ ls -la $loc"
        ls -la "$loc"
        echo ""
        echo "$ file $loc"
        file "$loc"
        echo ""
        echo "$ $loc --version"
        "$loc" --version 2>&1
      } | add_evidence

      VERSION=$("$loc" --version 2>/dev/null)
      if [[ "$VERSION" == "contextify 1.3.0" ]]; then
        add_summary_row "DMG CLI" "PASS" "Version 1.3.0 at $loc"
        return 0
      else
        add_summary_row "DMG CLI" "FAIL" "Wrong version: $VERSION"
        return 1
      fi
    fi
  done

  if ! $FOUND; then
    echo "CLI not found in expected locations." >> "$REPORT"
    echo "Run 'Install CLI' from the Contextify app, then re-run this validation." >> "$REPORT"
    add_summary_row "DMG CLI" "PENDING" "Manual install required"
    return 2
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  v1.3.0 CLI Installation Validation${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo ""

  init_report

  OVERALL_PASS=true

  # Sanitize first (unless skipped)
  if [[ "$SKIP_CLEANUP" != "true" ]]; then
    sanitize_environment || OVERALL_PASS=false
  fi

  # Test Homebrew
  if [[ "$TEST_HOMEBREW" == "true" ]]; then
    echo ""
    test_homebrew_installation || OVERALL_PASS=false

    # Clean up after Homebrew test if also testing DMG
    if [[ "$TEST_DMG" == "true" && "$SKIP_CLEANUP" != "true" ]]; then
      log_info "Cleaning up Homebrew for DMG test isolation..."
      brew uninstall contextify-query 2>/dev/null || true
      brew untap peterpym/contextify 2>/dev/null || true
      rm -f /usr/local/bin/contextify /usr/local/bin/contextify-query /usr/local/bin/contextify-ingest 2>/dev/null || true
      rm -rf "$HOME/.claude/skills/total-recall" 2>/dev/null || true
    fi
  fi

  # Test DMG
  if [[ "$TEST_DMG" == "true" ]]; then
    echo ""
    test_dmg_verification
    # Don't fail overall if DMG test is pending (requires manual install)
  fi

  # Finalize report
  echo "" >> "$REPORT"
  echo "---" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "Generated: $(date)" >> "$REPORT"
  echo "Script: $0" >> "$REPORT"

  # Update status
  if $OVERALL_PASS; then
    sed -i '' 's/status: in-progress/status: ready-for-review/' "$REPORT"
  fi

  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Validation Complete${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Report: $REPORT"
  echo ""

  if $OVERALL_PASS; then
    echo -e "${GREEN}All automated tests PASSED${NC}"
  else
    echo -e "${RED}Some tests FAILED - see report${NC}"
  fi
}

main "$@"
