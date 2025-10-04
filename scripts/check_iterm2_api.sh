#!/usr/bin/env bash
set -euo pipefail

echo "Checking iTerm2 Python API status..."
echo ""

ITERM_APP="/Applications/iTerm.app"
IT2RUN="$ITERM_APP/Contents/Resources/it2run"
PORT=1912

is_listening() { lsof -nP -i :"$PORT" >/dev/null 2>&1; }

# 0) Is iTerm2 running?
if ! pgrep -f "iTerm2" >/dev/null 2>&1; then
  echo "• iTerm2 is not running; launching…"
  open -ga "$ITERM_APP"
  # give it a moment to come up
  sleep 1
fi

# 1) Check listener
if is_listening; then
  echo "✅ iTerm2 Python API server is running (port $PORT)"
else
  echo "• Port $PORT not listening yet; attempting to wake API via it2run…"
  # Create a tiny throwaway script if needed
  TMPPY="$(mktemp -t it2ping.XXXXXX).py"
  cat >"$TMPPY" <<'PY'
import iterm2
async def main(c): pass  # minimal connect & exit
iterm2.run_until_complete(main, retry=False)
PY
  # Use it2run to launch it (avoids AppleScript permission nags)
  if [ -x "$IT2RUN" ]; then
    "$IT2RUN" "$TMPPY" || true
    # give server a moment to bind
    sleep 1
  else
    echo "⚠️ it2run not found at $IT2RUN. Continuing without wake."
  fi
  rm -f "$TMPPY"

  if is_listening; then
    echo "✅ iTerm2 Python API server started (port $PORT)"
  else
    echo "❌ iTerm2 Python API server is NOT running on port $PORT"
    echo ""
    echo "Hints:"
    echo "  - iTerm2 > Preferences > General > Magic > Enable Python API (and check Permissions)"
    echo "  - Scripts > Manage > Runtime… (install runtime)"
    echo "  - macOS Firewall: allow incoming connections for iTerm2 (localhost only)"
    echo "  - Try launching a script via Scripts menu to initialize the server"
    exit 1
  fi
fi

echo ""
echo "Testing connection with your script…"
# Activate your venv if present and run your probe
source .venv/bin/activate 2>/dev/null || true
python3 scripts/iterm2_reader.py
