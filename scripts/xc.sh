#!/usr/bin/env bash
set -euo pipefail

proj="Contextify/Contextify.xcodeproj"
scheme="Contextify"
dd=".derived"

default_config="Debug"
default_action="build"

config="$default_config"
action="$default_action"
dev_mode=0

parse_arg() {
  local value="$1"
  case "$value" in
    --dev|--developer-mode)
      dev_mode=1
      ;;
    Debug|Release)
      config="$value"
      ;;
    build|test|clean)
      action="$value"
      ;;
    *)
      echo "usage: $0 [--dev] [Debug|Release] [build|test|clean]" >&2
      echo "  --dev: Enable developer mode (shows test buttons)" >&2
      exit 2
      ;;
  esac
}

# Parse all arguments (supports --dev flag + config + action)
for arg in "$@"; do
  parse_arg "$arg"
done

have_xcpretty=0
if command -v xcpretty >/dev/null 2>&1; then
  have_xcpretty=1
fi

quit_running_app() {
  osascript -e 'tell application "Contextify" to quit' >/dev/null 2>&1 || true
  pkill -x Contextify >/dev/null 2>&1 || true
}

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
    if [[ ! -x dist/PythonVenv/bin/python3 ]]; then
      echo "❌ Missing bundled Python venv at dist/PythonVenv" >&2
      echo "   Run: python3 -m venv dist/PythonVenv && dist/PythonVenv/bin/python -m pip install --upgrade pip" >&2
      echo "   Then: dist/PythonVenv/bin/python -m pip install 'iterm2==2.7'" >&2
      exit 1
    fi
    quit_running_app
    run_xcodebuild -project "$proj" -scheme "$scheme" \
      -configuration "$config" -destination "platform=macOS" \
      -derivedDataPath "$dd" "$action"
    app_path="$dd/Build/Products/$config/Contextify.app"
    echo "Built: $app_path"
    if [[ "$action" == "build" && -z "${CTX_NO_RUN:-}" ]]; then
      # Set developer mode if --dev flag was provided
      if [[ $dev_mode -eq 1 ]]; then
        echo "Enabling developer mode..."
        defaults write dev.contextify.Contextify DeveloperModeEnabled -bool true
      else
        # Ensure developer mode is disabled by default
        defaults write dev.contextify.Contextify DeveloperModeEnabled -bool false
      fi
      echo "Launching $app_path"
      open "$app_path"
    fi
    ;;
  *)
    echo "usage: $0 [--dev] [Debug|Release] [build|test|clean]" >&2
    echo "  --dev: Enable developer mode (shows test buttons)" >&2
    exit 2
    ;;
esac
