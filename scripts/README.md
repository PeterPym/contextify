# iTerm2 Python API Integration

## Overview

Contextify uses iTerm2's Python API to reliably read terminal content when the global hotkey (Cmd+Shift+K+K) is pressed.

## Prerequisites

1. **iTerm2 3.3.0+** with Python API enabled
2. **Python 3.7+** (system Python is fine)
3. **iterm2 Python module** (installed in project venv)

## Setup Instructions

### 1. Enable iTerm2 Python API

```bash
# Open iTerm2 Preferences
Cmd+,

# Navigate to: General → Magic
# Check: ☑ Enable Python API
# Close preferences (API starts automatically)
```

### 2. Verify Setup

```bash
# Check if API is running
bash scripts/check_iterm2_api.sh

# Test Python reader directly
bash scripts/iterm2_reader_wrapper.sh
```

Expected output:
```json
{
  "success": true,
  "content": "... terminal content ...",
  "line_count": 123
}
```

### 3. Build and Test

```bash
# Rebuild Contextify
bash scripts/xc.sh build

# Launch app
open .derived/Build/Products/Debug/Contextify.app

# Try hotkey: Cmd+Shift+K+K
```

## Architecture

```
GlobalHotkeyManager (Swift)
  ↓ detects Cmd+Shift+K+K
TerminalContentReader (Swift)
  ↓ checks if iTerm2
ITerm2PythonReader (Swift)
  ↓ executes subprocess
iterm2_reader_wrapper.sh (Bash)
  ↓ activates venv
.venv/bin/python3
  ↓ runs with iterm2 module
iterm2_reader.py (Python)
  ↓ connects to iTerm2 API
iTerm2 Python API Server (port 1912)
  ↓ returns session content
JSON output → Swift → ClaudeCodeParser → Contextify compose window
```

## Files

- `iterm2_reader.py` - Python script using iTerm2 API
- `iterm2_reader_wrapper.sh` - Bash wrapper to activate venv
- `check_iterm2_api.sh` - Diagnostic script
- `../.venv/` - Python virtual environment with iterm2 module

## Troubleshooting

### Error: "connection_refused"

**Problem:** iTerm2 Python API is not enabled

**Solution:**
```bash
# Enable in: iTerm2 Preferences → General → Magic → Enable Python API
# Then verify:
lsof -i :1912  # Should show iTerm2 listening
```

### Error: "scriptNotFound"

**Problem:** Swift can't find the Python script

**Solution:**
```bash
# Verify script exists:
ls -la scripts/iterm2_reader_wrapper.sh
ls -la scripts/iterm2_reader.py

# Make sure they're executable:
chmod +x scripts/*.sh scripts/*.py
```

### Error: "ModuleNotFoundError: No module named 'iterm2'"

**Problem:** iterm2 module not installed in venv

**Solution:**
```bash
# Recreate venv and install module:
rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install iterm2
```

### Python API not returning content

**Problem:** May be reading from wrong session

**Solution:**
```bash
# The API reads from current_terminal_window.current_tab.current_session
# Make sure the iTerm2 window/tab you want is active
```

## Fallback Behavior

If Python API fails, Contextify falls back to:
1. AppleScript (for iTerm2 and Terminal.app)
2. Accessibility API (for other terminals)

This ensures the hotkey continues to work even if Python API has issues.

## Development

### Testing Python script in isolation

```bash
# Activate venv
source .venv/bin/activate

# Run directly
python3 scripts/iterm2_reader.py | jq .

# Or use wrapper
bash scripts/iterm2_reader_wrapper.sh | jq .
```

### Adding debug output

Edit `iterm2_reader.py` and add logging:
```python
import sys
print("DEBUG: Connecting to iTerm2...", file=sys.stderr)
```

### Updating iterm2 module

```bash
source .venv/bin/activate
pip install --upgrade iterm2
```

## References

- [iTerm2 Python API Documentation](https://iterm2.com/python-api/)
- [iTerm2 Python API Examples](https://github.com/gnachman/iTerm2/tree/master/api/examples)
