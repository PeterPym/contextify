#!/usr/bin/env bash
set -euo pipefail

PROJ_FILE="Contextify/Contextify.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJ_FILE" ]]; then
  echo "❌ project.pbxproj not found at $PROJ_FILE" >&2
  exit 1
fi

echo "🔍 Validating Xcode project structure..."

check_file_reference() {
  local file=$1
  local expected=${2:-1}
  local count
  count=$(grep -c "$file" "$PROJ_FILE")
  if (( count < expected )); then
    echo "❌ FAIL: $file not present in project (found $count references, need ≥$expected)" >&2
    exit 1
  fi
  echo "✅ $file present in project file ($count references)"
}

check_file_reference "LaunchAgentManager.swift"
check_file_reference "ITerm2DaemonClient.swift"
check_file_reference "PythonVenv"

echo
printf '🎉 Xcode project structure validated!\n'
