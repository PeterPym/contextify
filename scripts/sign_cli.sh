#!/bin/bash
# ============================================================================
# sign_cli.sh - Build, sign, and notarize the standalone CLI for Homebrew
# ============================================================================
#
# Purpose:
#   Builds unified contextify CLI, signs with Developer ID, notarizes with Apple,
#   and packages for Homebrew distribution. Designed to be called as part of
#   the main app release process or standalone.
#
# Usage:
#   ./scripts/sign_cli.sh [OPTIONS]
#
# Options:
#   --force          Force rebuild even if no changes detected
#   --no-notarize    Skip notarization (faster for testing)
#   --check-only     Only check if rebuild is needed, don't build
#   --version VER    Override version string (default: reads from Xcode project)
#   --help           Show this help message
#
# Outputs:
#   build/cli-release/contextify                    Signed binary
#   build/cli-release/contextify-{arch}.tar.gz     Homebrew package
#   build/cli-release/sha256.txt                    SHA256 for formula
#   build/cli-release/.last-build-commit            Commit hash of last build
#
# Exit Codes:
#   0 - Success (or no rebuild needed with --check-only)
#   1 - Build failed
#   2 - Signing failed
#   3 - Notarization failed
#   4 - Packaging failed
#   5 - Prerequisites missing (certificate, notary profile)
#   10 - No rebuild needed (with --check-only when no changes)
#
# Integration:
#   This script is called by sign_and_notarize.py during DMG releases.
#   It can also be run standalone for CLI-only releases.
#
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Output locations
OUTPUT_DIR="$ROOT_DIR/build/cli-release"
BINARY_NAME="contextify"
LAST_BUILD_FILE="$OUTPUT_DIR/.last-build-commit"

# CLI source paths (for change detection)
CLI_SOURCES=(
  "Sources/ContextifyQueryCLI"
  "app/Sources/ContextifyCore/Database"
  "app/Sources/ContextifyCore/CLI"
  "Package.swift"
)

# Notarization profile (must match scripts/SIGNING-SETUP.md)
NOTARY_PROFILE="NotaryProfile"

# Parse arguments
FORCE_BUILD=false
SKIP_NOTARIZE=false
CHECK_ONLY=false
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE_BUILD=true
      shift
      ;;
    --no-notarize)
      SKIP_NOTARIZE=true
      shift
      ;;
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --help|-h)
      head -50 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      exit 1
      ;;
  esac
done

# ============================================================================
# Logging helpers
# ============================================================================

log_info() {
  echo -e "${BLUE}==>${NC} $1"
}

log_success() {
  echo -e "${GREEN}OK${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}Warning:${NC} $1"
}

log_error() {
  echo -e "${RED}Error:${NC} $1" >&2
}

# ============================================================================
# Prerequisites check
# ============================================================================

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check for Developer ID certificate
  CERT_ID=$(security find-identity -p codesigning -v 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')
  if [ -z "$CERT_ID" ]; then
    log_error "Developer ID Application certificate not found"
    log_error "See scripts/SIGNING-SETUP.md for setup instructions"
    exit 5
  fi
  log_success "Developer ID certificate: ${CERT_ID:0:8}..."

  # Check for notarization profile (unless skipping)
  if [ "$SKIP_NOTARIZE" = false ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      log_error "Notarization profile '$NOTARY_PROFILE' not configured"
      log_error "See scripts/SIGNING-SETUP.md for setup instructions"
      exit 5
    fi
    log_success "Notarization profile: $NOTARY_PROFILE"
  else
    log_warn "Notarization will be skipped"
  fi

  # Check for swift
  if ! command -v swift &>/dev/null; then
    log_error "Swift not found"
    exit 5
  fi
  log_success "Swift: $(swift --version 2>&1 | head -1)"
}

# ============================================================================
# Change detection
# ============================================================================

get_cli_sources_hash() {
  # Get hash of all CLI-related source files
  local hash=""
  for src in "${CLI_SOURCES[@]}"; do
    if [ -e "$ROOT_DIR/$src" ]; then
      hash+=$(find "$ROOT_DIR/$src" -type f -name "*.swift" -exec shasum {} \; 2>/dev/null | sort | shasum | cut -d' ' -f1)
    fi
  done
  echo "$hash" | shasum | cut -d' ' -f1
}

check_rebuild_needed() {
  if [ "$FORCE_BUILD" = true ]; then
    log_info "Force rebuild requested"
    return 0
  fi

  if [ ! -f "$LAST_BUILD_FILE" ]; then
    log_info "No previous build found"
    return 0
  fi

  if [ ! -f "$OUTPUT_DIR/$BINARY_NAME" ]; then
    log_info "Binary not found, rebuild needed"
    return 0
  fi

  local last_hash=$(cat "$LAST_BUILD_FILE" 2>/dev/null)
  local current_hash=$(get_cli_sources_hash)

  if [ "$last_hash" != "$current_hash" ]; then
    log_info "CLI sources changed, rebuild needed"
    return 0
  fi

  log_info "No CLI changes detected since last build"
  return 1
}

# ============================================================================
# Build
# ============================================================================

build_cli() {
  log_info "Building CLI..."

  cd "$ROOT_DIR"

  # Clean previous build
  rm -rf .build/release/$BINARY_NAME

  # Build release
  if ! swift build -c release --product "$BINARY_NAME" 2>&1; then
    log_error "Swift build failed"
    exit 1
  fi

  # Verify binary exists
  if [ ! -f ".build/release/$BINARY_NAME" ]; then
    log_error "Binary not found after build"
    exit 1
  fi

  log_success "Built: .build/release/$BINARY_NAME"
}

# ============================================================================
# Sign
# ============================================================================

sign_cli() {
  log_info "Signing CLI with Developer ID..."

  local binary="$ROOT_DIR/.build/release/$BINARY_NAME"

  # Sign with hardened runtime
  if ! codesign --force \
    --sign "$CERT_ID" \
    --options runtime \
    --timestamp \
    "$binary" 2>&1; then
    log_error "Code signing failed"
    exit 2
  fi

  # Verify signature
  if ! codesign --verify --deep --strict -vv "$binary" 2>&1; then
    log_error "Signature verification failed"
    exit 2
  fi

  log_success "Signed and verified: $BINARY_NAME"
}

# ============================================================================
# Notarize
# ============================================================================

notarize_cli() {
  if [ "$SKIP_NOTARIZE" = true ]; then
    log_warn "Skipping notarization (--no-notarize)"
    return 0
  fi

  log_info "Notarizing CLI (this may take a few minutes)..."

  local binary="$ROOT_DIR/.build/release/$BINARY_NAME"
  local zip_file="$OUTPUT_DIR/${BINARY_NAME}-notarize.zip"

  # Create zip for notarization
  mkdir -p "$OUTPUT_DIR"
  rm -f "$zip_file"
  ditto -c -k --keepParent "$binary" "$zip_file"

  # Submit for notarization
  if ! xcrun notarytool submit "$zip_file" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1; then
    log_error "Notarization failed"
    rm -f "$zip_file"
    exit 3
  fi

  # Clean up zip
  rm -f "$zip_file"

  log_success "Notarization complete"
}

# ============================================================================
# Package
# ============================================================================

package_cli() {
  log_info "Packaging for Homebrew..."

  local binary="$ROOT_DIR/.build/release/$BINARY_NAME"
  local arch=$(uname -m)
  local tarball="$OUTPUT_DIR/${BINARY_NAME}-${arch}.tar.gz"
  local staging="$OUTPUT_DIR/staging"

  # Create output directory
  mkdir -p "$OUTPUT_DIR"
  rm -rf "$staging"
  mkdir -p "$staging"

  # Copy binary to staging
  cp "$binary" "$staging/$BINARY_NAME"
  chmod +x "$staging/$BINARY_NAME"

  # Copy plugin files for install-plugin command
  local plugin_source="$ROOT_DIR/contextify-query/claude-plugin"
  if [ -d "$plugin_source" ]; then
    log_info "Including plugin files..."
    cp -R "$plugin_source" "$staging/claude-plugin"
  else
    log_warn "Plugin source not found at $plugin_source"
  fi

  # Copy user skill for Total Recall feature
  local user_skill_source="$ROOT_DIR/contextify-query/user-skill"
  if [ -d "$user_skill_source" ]; then
    log_info "Including user skill (Total Recall)..."
    cp -R "$user_skill_source" "$staging/user-skill"
  else
    log_warn "User skill source not found at $user_skill_source"
  fi

  # Create tarball with binary, plugin, and user skill
  rm -f "$tarball"
  tar -czvf "$tarball" -C "$staging" .

  # Clean up staging
  rm -rf "$staging"

  # Calculate SHA256
  local sha256=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
  echo "$sha256  ${BINARY_NAME}-${arch}.tar.gz" > "$OUTPUT_DIR/sha256.txt"

  # Record build hash for change detection
  get_cli_sources_hash > "$LAST_BUILD_FILE"

  log_success "Package: $tarball"
  log_success "SHA256: $sha256"

  # Print formula update instructions
  echo ""
  echo -e "${BLUE}To update Homebrew formula:${NC}"
  echo "  1. Upload $tarball to GitHub releases"
  echo "  2. Update homebrew-contextify Formula/contextify-query.rb:"
  echo "     sha256 \"$sha256\""
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Contextify CLI Sign & Notarize${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo ""

  # Get version
  if [ -n "$VERSION_OVERRIDE" ]; then
    VERSION="$VERSION_OVERRIDE"
  else
    VERSION=$(grep -m1 "MARKETING_VERSION" "$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' ')
  fi
  echo "  Version: $VERSION"
  echo "  Arch:    $(uname -m)"
  echo ""

  # Check if rebuild needed
  if ! check_rebuild_needed; then
    if [ "$CHECK_ONLY" = true ]; then
      echo ""
      log_success "No rebuild needed"
      exit 10
    fi
    log_success "Using cached build"
    return 0
  fi

  if [ "$CHECK_ONLY" = true ]; then
    echo ""
    log_info "Rebuild is needed"
    exit 0
  fi

  # Run build pipeline
  check_prerequisites
  build_cli
  sign_cli
  notarize_cli
  package_cli

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  CLI Build Complete${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Output: $OUTPUT_DIR/"
  ls -la "$OUTPUT_DIR/"
  echo ""
}

# Run main
main
