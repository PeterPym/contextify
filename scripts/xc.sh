#!/usr/bin/env bash
set -euo pipefail

# Contextify Xcode helper
# Usage:
#   bash scripts/xc.sh build   [--release] [--scheme Contextify]
#   bash scripts/xc.sh test    [--scheme Contextify]
#
# Notes:
# - Prefers Xcode-beta if installed; otherwise falls back to default Xcode.
# - Writes DerivedData inside repo: build/DerivedData[-beta]
# - Disables code signing for local builds.

here_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here_dir/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-Contextify/Contextify.xcodeproj}"
SCHEME="Contextify"
CONFIG="Debug"
DEST="platform=macOS"

cmd="${1:-build}"; shift || true

# Parse simple flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) SCHEME="$2"; shift 2;;
    --release) CONFIG="Release"; shift;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# Resolve Developer dir: prefer Xcode-beta if present
DEV_DIR_DEFAULT="/Applications/Xcode.app/Contents/Developer"
DEV_DIR_BETA="/Applications/Xcode-beta.app/Contents/Developer"
DEV_DIR="${DEVELOPER_DIR:-}"
if [[ -z "${DEV_DIR}" ]]; then
  if [[ -d "$DEV_DIR_BETA" ]]; then
    DEV_DIR="$DEV_DIR_BETA"
  else
    DEV_DIR="$DEV_DIR_DEFAULT"
  fi
fi

export DEVELOPER_DIR="$DEV_DIR"

if [[ "$DEVELOPER_DIR" == *"Xcode-beta.app"* ]]; then
  DERIVED="$repo_root/build/DerivedData-beta"
else
  DERIVED="$repo_root/build/DerivedData"
fi

echo "Using DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -version

set -x
case "$cmd" in
  build)
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "$DEST" \
      -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      build
    ;;
  test)
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "$DEST" \
      -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      test
    ;;
  *)
    set +x
    echo "Unknown command: $cmd"
    echo "Usage: bash scripts/xc.sh [build|test] [--release] [--scheme NAME]"
    exit 2
    ;;
esac

