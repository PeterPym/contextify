#!/usr/bin/env bash
set -euo pipefail

proj="Contextify/Contextify.xcodeproj"
scheme="Contextify"
dd=".derived"

default_config="Debug"
default_action="build"

config="$default_config"
action="$default_action"

parse_arg() {
  local value="$1"
  case "$value" in
    Debug|Release)
      config="$value"
      ;;
    build|test|clean)
      action="$value"
      ;;
    *)
      echo "usage: $0 [Debug|Release] [build|test|clean]" >&2
      exit 2
      ;;
  esac
}

if [[ $# -ge 1 ]]; then
  parse_arg "$1"
fi
if [[ $# -ge 2 ]]; then
  parse_arg "$2"
fi
if [[ $# -gt 2 ]]; then
  echo "usage: $0 [Debug|Release] [build|test|clean]" >&2
  exit 2
fi

have_xcpretty=0
if command -v xcpretty >/dev/null 2>&1; then
  have_xcpretty=1
fi

run_xcodebuild() {
  if [[ $have_xcpretty -eq 1 ]]; then
    xcodebuild "$@" | xcpretty
  else
    xcodebuild "$@"
  fi
}

case "$action" in
  clean)
    rm -rf "$dd"
    ;;
  build|test)
    run_xcodebuild -project "$proj" -scheme "$scheme" \
      -configuration "$config" -destination "platform=macOS" \
      -derivedDataPath "$dd" "$action"
    app_path="$dd/Build/Products/$config/Contextify.app"
    echo "Built: $app_path"
    ;;
  *)
    echo "usage: $0 [Debug|Release] [build|test|clean]" >&2
    exit 2
    ;;
esac
