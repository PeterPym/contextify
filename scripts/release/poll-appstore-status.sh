#!/bin/bash
#
# poll-appstore-status.sh - Query App Store Connect for actual submission status
#
# Usage:
#   ./scripts/release/poll-appstore-status.sh [OPTIONS]
#
# Options:
#   --sync          Update local state files with Apple's state
#   --json          Output as JSON
#   --quiet         Only output if action needed
#   --help          Show this help
#
# Examples:
#   ./scripts/release/poll-appstore-status.sh
#   ./scripts/release/poll-appstore-status.sh --sync
#   ./scripts/release/poll-appstore-status.sh --json
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/releases/config.json"
MANIFEST_FILE="$REPO_ROOT/releases/manifest.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Options
SYNC=false
JSON_OUTPUT=false
QUIET=false

usage() {
  head -20 "$0" | tail -16 | sed 's/^# //' | sed 's/^#//'
  exit 0
}

error() {
  echo -e "${RED}Error:${NC} $1" >&2
  exit 1
}

info() {
  if [ "$QUIET" = false ]; then
    echo -e "${BLUE}$1${NC}"
  fi
}

success() {
  if [ "$QUIET" = false ]; then
    echo -e "${GREEN}$1${NC}"
  fi
}

# Map Apple state to category
get_category() {
  local state="$1"
  case "$state" in
    PREPARE_FOR_SUBMISSION|READY_FOR_REVIEW)
      echo "not_submitted" ;;
    WAITING_FOR_REVIEW|IN_REVIEW|WAITING_FOR_EXPORT_COMPLIANCE|PENDING_CONTRACT)
      echo "in_review" ;;
    PENDING_DEVELOPER_RELEASE|PENDING_APPLE_RELEASE|PROCESSING_FOR_APP_STORE|READY_FOR_SALE|PREORDER_READY_FOR_SALE|ACCEPTED)
      echo "approved" ;;
    METADATA_REJECTED|REJECTED|INVALID_BINARY)
      echo "rejected" ;;
    DEVELOPER_REJECTED|DEVELOPER_REMOVED_FROM_SALE|REMOVED_FROM_SALE)
      echo "removed" ;;
    *)
      echo "other" ;;
  esac
}

# Map Apple state to action
get_action() {
  local state="$1"
  case "$state" in
    PREPARE_FOR_SUBMISSION) echo "Complete metadata and submit for review" ;;
    READY_FOR_REVIEW) echo "Click 'Submit for Review' in App Store Connect" ;;
    WAITING_FOR_REVIEW) echo "Waiting - Apple will review soon" ;;
    IN_REVIEW) echo "Waiting - Under active review" ;;
    WAITING_FOR_EXPORT_COMPLIANCE) echo "Answer export compliance question in ASC" ;;
    PENDING_CONTRACT) echo "Resolve contract/legal issue in ASC" ;;
    PENDING_DEVELOPER_RELEASE) echo "Click 'Release This Version' in App Store Connect" ;;
    PENDING_APPLE_RELEASE) echo "Waiting for scheduled release date" ;;
    PROCESSING_FOR_APP_STORE) echo "Processing - will be live in minutes" ;;
    READY_FOR_SALE) echo "Live on App Store" ;;
    PREORDER_READY_FOR_SALE) echo "Pre-order available" ;;
    ACCEPTED) echo "Accepted" ;;
    METADATA_REJECTED) echo "Fix metadata in ASC, resubmit same build" ;;
    REJECTED) echo "Fix code, rebuild, re-upload" ;;
    INVALID_BINARY) echo "Rebuild and re-upload" ;;
    DEVELOPER_REJECTED) echo "Resubmit when ready" ;;
    DEVELOPER_REMOVED_FROM_SALE) echo "Re-enable in ASC if desired" ;;
    REMOVED_FROM_SALE) echo "Contact Apple" ;;
    REPLACED_WITH_NEW_VERSION) echo "Superseded by newer version" ;;
    *) echo "Unknown state" ;;
  esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --sync)
      SYNC=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
  error "Config file not found: $CONFIG_FILE"
fi

API_KEY_ID=$(jq -r '.app_store_connect.api_key_id' "$CONFIG_FILE")
ISSUER_ID=$(jq -r '.app_store_connect.issuer_id' "$CONFIG_FILE")
APP_ID=$(jq -r '.app_store_connect.app_id' "$CONFIG_FILE")

if [ -z "$API_KEY_ID" ] || [ "$API_KEY_ID" = "null" ]; then
  error "api_key_id not found in config.json"
fi

# Get current version from manifest
VERSION=""
if [ -f "$MANIFEST_FILE" ]; then
  VERSION=$(jq -r '.current_version' "$MANIFEST_FILE")
fi
if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
  VERSION="unknown"
fi

RELEASE_FILE="$REPO_ROOT/releases/v$VERSION/release.json"

# Query App Store Connect
if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
  info "Querying App Store Connect..."
fi

ALTOOL_OUTPUT=$(xcrun altool --list-apps \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$ISSUER_ID" 2>&1) || {
  error "Failed to query App Store Connect: $ALTOOL_OUTPUT"
}

# Parse the output for Contextify
APPLE_STATE=""
APPLE_VERSION=""
IN_CONTEXTIFY=false

while IFS= read -r line; do
  if [[ "$line" == *"Name: Contextify"* ]]; then
    IN_CONTEXTIFY=true
  elif [[ "$IN_CONTEXTIFY" == true ]] && [[ "$line" == *"Name:"* ]]; then
    break
  elif [[ "$IN_CONTEXTIFY" == true ]]; then
    if [[ "$line" == *"App Store State:"* ]]; then
      APPLE_STATE=$(echo "$line" | sed 's/.*App Store State: //' | tr -d ' ')
    elif [[ "$line" == *"Version String:"* ]]; then
      APPLE_VERSION=$(echo "$line" | sed 's/.*Version String: //' | tr -d ' ')
    fi
  fi
done <<< "$ALTOOL_OUTPUT"

if [ -z "$APPLE_STATE" ]; then
  error "Could not find Contextify in App Store Connect output"
fi

# Get category and action
CATEGORY=$(get_category "$APPLE_STATE")
ACTION=$(get_action "$APPLE_STATE")

# Get local state
LOCAL_STATUS="unknown"
LOCAL_APPLE_STATE=""
if [ -f "$MANIFEST_FILE" ] && [ "$VERSION" != "unknown" ]; then
  LOCAL_STATUS=$(jq -r ".releases[\"$VERSION\"].appstore.status // \"unknown\"" "$MANIFEST_FILE")
  LOCAL_APPLE_STATE=$(jq -r ".releases[\"$VERSION\"].appstore.apple_state // empty" "$MANIFEST_FILE")
fi

# Determine if there's a mismatch
MISMATCH=false
if [ -n "$LOCAL_APPLE_STATE" ] && [ "$LOCAL_APPLE_STATE" != "$APPLE_STATE" ]; then
  MISMATCH=true
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Output
if [ "$JSON_OUTPUT" = true ]; then
  cat <<EOF
{
  "version": "$VERSION",
  "apple_version": "$APPLE_VERSION",
  "apple_state": "$APPLE_STATE",
  "category": "$CATEGORY",
  "action": "$ACTION",
  "local_status": "$LOCAL_STATUS",
  "local_apple_state": "$LOCAL_APPLE_STATE",
  "mismatch": $MISMATCH,
  "checked_at": "$NOW"
}
EOF
else
  echo ""
  echo -e "${BOLD}App Store Connect Status${NC}"
  echo "========================"
  echo ""
  echo -e "  Version:      ${CYAN}$APPLE_VERSION${NC}"
  echo -e "  Apple State:  ${BOLD}$APPLE_STATE${NC}"
  echo -e "  Category:     $CATEGORY"
  echo ""

  # Color-code by category
  case "$CATEGORY" in
    not_submitted)
      echo -e "  ${YELLOW}Action Required:${NC} $ACTION"
      ;;
    in_review)
      echo -e "  ${BLUE}Status:${NC} $ACTION"
      ;;
    approved)
      if [ "$APPLE_STATE" = "READY_FOR_SALE" ]; then
        echo -e "  ${GREEN}Status:${NC} $ACTION"
      elif [ "$APPLE_STATE" = "PENDING_DEVELOPER_RELEASE" ]; then
        echo -e "  ${YELLOW}Action Required:${NC} $ACTION"
      else
        echo -e "  ${BLUE}Status:${NC} $ACTION"
      fi
      ;;
    rejected)
      echo -e "  ${RED}Action Required:${NC} $ACTION"
      ;;
    removed)
      echo -e "  ${RED}Status:${NC} $ACTION"
      ;;
    *)
      echo -e "  Status: $ACTION"
      ;;
  esac

  echo ""
  echo -e "${BOLD}Local Tracking (v$VERSION)${NC}"
  echo "-------------------------"
  echo "  Local status:       $LOCAL_STATUS"
  echo "  Local apple_state:  ${LOCAL_APPLE_STATE:-<not set>}"

  if [ "$MISMATCH" = true ]; then
    echo ""
    echo -e "  ${YELLOW}Mismatch detected!${NC} Local state differs from Apple."
    if [ "$SYNC" = false ]; then
      echo "  Run with --sync to update local state."
    fi
  elif [ -z "$LOCAL_APPLE_STATE" ]; then
    echo ""
    echo -e "  ${YELLOW}No apple_state recorded locally.${NC}"
    if [ "$SYNC" = false ]; then
      echo "  Run with --sync to record current state."
    fi
  else
    echo ""
    echo -e "  ${GREEN}Local state matches Apple.${NC}"
  fi
  echo ""
fi

# Sync if requested
if [ "$SYNC" = true ]; then
  info "Syncing local state..."

  # Update manifest.json
  if [ -f "$MANIFEST_FILE" ] && [ "$VERSION" != "unknown" ]; then
    TMP_MANIFEST=$(mktemp)
    jq --arg version "$VERSION" \
       --arg state "$APPLE_STATE" \
       --arg now "$NOW" \
       '.releases[$version].appstore.apple_state = $state |
        .releases[$version].appstore.apple_state_updated_at = $now' \
       "$MANIFEST_FILE" > "$TMP_MANIFEST"
    mv "$TMP_MANIFEST" "$MANIFEST_FILE"
    success "Updated manifest.json"
  fi

  # Update release.json if it exists
  if [ -f "$RELEASE_FILE" ]; then
    TMP_RELEASE=$(mktemp)
    TODAY=$(date +"%Y-%m-%d")

    # Add to history if state changed
    if [ -n "$LOCAL_APPLE_STATE" ] && [ "$LOCAL_APPLE_STATE" != "$APPLE_STATE" ]; then
      jq --arg state "$APPLE_STATE" \
         --arg now "$NOW" \
         --arg today "$TODAY" \
         '.phases.submission.apple_state = $state |
          .phases.submission.apple_state_history += [{"state": $state, "timestamp": $now}] |
          .updated = $today' \
         "$RELEASE_FILE" > "$TMP_RELEASE"
    else
      jq --arg state "$APPLE_STATE" \
         --arg now "$NOW" \
         --arg today "$TODAY" \
         '.phases.submission.apple_state = $state |
          .updated = $today' \
         "$RELEASE_FILE" > "$TMP_RELEASE"
    fi
    mv "$TMP_RELEASE" "$RELEASE_FILE"
    success "Updated release.json"
  fi

  # Helpful hints for significant states
  case "$APPLE_STATE" in
    READY_FOR_SALE)
      echo ""
      success "App is live! Run: ./scripts/release/mark-shipped.sh $VERSION --appstore"
      ;;
    REJECTED|METADATA_REJECTED|INVALID_BINARY)
      echo ""
      echo -e "${RED}App was rejected.${NC} Check App Store Connect Resolution Center for details."
      ;;
    PENDING_DEVELOPER_RELEASE)
      echo ""
      echo -e "${GREEN}App approved!${NC} Click 'Release This Version' in App Store Connect when ready."
      ;;
  esac
fi

# Exit codes: 0=good, 1=action needed, 2=rejected
case "$CATEGORY" in
  rejected) exit 2 ;;
  not_submitted) exit 1 ;;
  *) exit 0 ;;
esac
