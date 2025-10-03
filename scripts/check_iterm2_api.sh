#!/bin/bash
# Check if iTerm2 Python API is enabled

echo "Checking iTerm2 Python API status..."
echo ""

# Check if port 1912 is listening
if lsof -i :1912 >/dev/null 2>&1; then
    echo "✅ iTerm2 Python API server is running (port 1912)"
    echo ""
    echo "Testing connection..."
    source .venv/bin/activate 2>/dev/null || true
    python3 scripts/iterm2_reader.py
else
    echo "❌ iTerm2 Python API server is NOT running"
    echo ""
    echo "To enable:"
    echo "1. Open iTerm2 Preferences (Cmd+,)"
    echo "2. General → Magic"
    echo "3. Check 'Enable Python API'"
    echo "4. Close preferences (API starts immediately)"
    echo ""
    echo "Then run this script again to verify."
fi
