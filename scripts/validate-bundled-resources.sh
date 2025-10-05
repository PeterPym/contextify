#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-.derived/Build/Products/Debug/Contextify.app}"
RESOURCES="$APP_PATH/Contents/Resources"

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ App bundle not found at: $APP_PATH" >&2
  exit 1
fi

echo "🔍 Validating bundled resources in: $APP_PATH"

if [[ ! -f "$RESOURCES/iterm2_daemon.py" ]]; then
  echo "❌ FAIL: iterm2_daemon.py not bundled" >&2
  exit 1
fi
printf '✅ iterm2_daemon.py bundled (%s bytes)\n' "$(stat -f%z "$RESOURCES/iterm2_daemon.py")"

if [[ ! -d "$RESOURCES/PythonVenv" ]]; then
  echo "❌ FAIL: PythonVenv directory not bundled" >&2
  exit 1
fi
echo "✅ PythonVenv directory bundled"

PYTHON="$RESOURCES/PythonVenv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  echo "❌ FAIL: Python binary not executable at $PYTHON" >&2
  exit 1
fi
PYVER="$($PYTHON --version 2>&1)"
echo "✅ Python executable: $PYVER"

if ! "$PYTHON" -c "import iterm2" >/dev/null 2>&1; then
  echo "❌ FAIL: iterm2 package not installed in bundled venv" >&2
  exit 1
fi
ITERM_VER="$($PYTHON -c 'import iterm2; print(iterm2.__version__)')"
echo "✅ iterm2 package: v$ITERM_VER"

if [[ ! -f "$RESOURCES/iterm2_reader.py" ]]; then
  echo "⚠️  WARN: iterm2_reader.py not bundled (legacy fallback)"
fi

echo
echo "🎉 All bundled resources validated successfully!"
