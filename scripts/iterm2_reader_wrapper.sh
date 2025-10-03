#!/bin/bash
# Wrapper script that activates venv and runs Python reader

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_PYTHON="$PROJECT_ROOT/.venv/bin/python3"
READER_SCRIPT="$SCRIPT_DIR/iterm2_reader.py"

# Use venv Python if available, otherwise try system Python
if [ -x "$VENV_PYTHON" ]; then
    exec "$VENV_PYTHON" "$READER_SCRIPT" "$@"
else
    exec python3 "$READER_SCRIPT" "$@"
fi
