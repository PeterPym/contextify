#!/bin/bash
#
# vm-bootstrap.sh - Seed test transcripts on a QA VM
#
# This script creates the expected folder structure and copies fixture
# transcripts so Contextify has projects to display during testing.
#
# Usage (on VM):
#   bash /Volumes/VMShare/vm-bootstrap.sh
#
# Or copy to VM and run:
#   bash ~/Downloads/vm-bootstrap.sh
#

set -e

echo "=== Contextify VM Bootstrap ==="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if fixtures directory exists (either in script dir or shared folder)
FIXTURES_DIR=""
if [ -d "$SCRIPT_DIR/fixtures/transcripts" ]; then
  FIXTURES_DIR="$SCRIPT_DIR/fixtures/transcripts"
elif [ -d "/Volumes/VMShare/fixtures/transcripts" ]; then
  FIXTURES_DIR="/Volumes/VMShare/fixtures/transcripts"
else
  echo "ERROR: Fixtures directory not found."
  echo ""
  echo "Make sure the fixtures are available at one of:"
  echo "  - $SCRIPT_DIR/fixtures/transcripts/"
  echo "  - /Volumes/VMShare/fixtures/transcripts/"
  echo ""
  echo "On host, copy fixtures to shared folder:"
  echo "  cp -R scripts/qa/fixtures ~/Public/VMShare/"
  exit 1
fi

echo "Using fixtures from: $FIXTURES_DIR"
echo ""

# Create test project directories
TEST_PROJECT_1="/tmp/contextify-test-project-1"
TEST_PROJECT_2="/tmp/contextify-test-project-2"
TEST_PROJECT_3="/tmp/contextify-test-project-3"

echo "Creating test project directories..."
mkdir -p "$TEST_PROJECT_1"
mkdir -p "$TEST_PROJECT_2"
mkdir -p "$TEST_PROJECT_3"

# Create placeholder files so they look like real projects
echo "# Test Project 1" > "$TEST_PROJECT_1/README.md"
echo "# Test Project 2" > "$TEST_PROJECT_2/README.md"
echo "# Test Project 3" > "$TEST_PROJECT_3/README.md"

# Create Claude Code transcript directories
# Claude uses hash-based directories: ~/.claude/projects/<hash>/
# We use a simplified hash (tr '/' '-') for testing
CLAUDE_BASE="$HOME/.claude/projects"
mkdir -p "$CLAUDE_BASE"

hash1=$(echo "$TEST_PROJECT_1" | tr '/' '-')
hash2=$(echo "$TEST_PROJECT_2" | tr '/' '-')
mkdir -p "$CLAUDE_BASE/$hash1"
mkdir -p "$CLAUDE_BASE/$hash2"

# Create Codex transcript directories
# Codex uses flat structure: ~/.codex/sessions/
CODEX_BASE="$HOME/.codex/sessions"
mkdir -p "$CODEX_BASE"

echo "Seeding Claude Code transcripts..."

# Seed Claude transcripts (update cwd field to match test projects)
if [ -f "$FIXTURES_DIR/claude/project1.jsonl" ]; then
  # Update cwd field to point to test project
  sed "s|/private/tmp/contextify-qa-fixture-gen-1|$TEST_PROJECT_1|g" \
    "$FIXTURES_DIR/claude/project1.jsonl" > "$CLAUDE_BASE/$hash1/$(uuidgen).jsonl"
  echo "  - Seeded project1.jsonl -> $TEST_PROJECT_1"
fi

if [ -f "$FIXTURES_DIR/claude/project2.jsonl" ]; then
  sed "s|/private/tmp/contextify-qa-fixture-gen-2|$TEST_PROJECT_2|g" \
    "$FIXTURES_DIR/claude/project2.jsonl" > "$CLAUDE_BASE/$hash2/$(uuidgen).jsonl"
  echo "  - Seeded project2.jsonl -> $TEST_PROJECT_2"
fi

echo ""
echo "Seeding Codex CLI transcripts..."

# Seed Codex transcripts
if [ -f "$FIXTURES_DIR/codex/project1.jsonl" ]; then
  sed "s|/private/tmp/contextify-qa-fixture-gen-1|$TEST_PROJECT_1|g" \
    "$FIXTURES_DIR/codex/project1.jsonl" > "$CODEX_BASE/$(uuidgen).jsonl"
  echo "  - Seeded project1.jsonl -> $TEST_PROJECT_1"
fi

if [ -f "$FIXTURES_DIR/codex/project3.jsonl" ]; then
  sed "s|/private/tmp/contextify-qa-fixture-gen-3|$TEST_PROJECT_3|g" \
    "$FIXTURES_DIR/codex/project3.jsonl" > "$CODEX_BASE/$(uuidgen).jsonl"
  echo "  - Seeded project3.jsonl -> $TEST_PROJECT_3"
fi

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Created directories:"
echo "  - $CLAUDE_BASE/"
echo "  - $CODEX_BASE/"
echo ""
echo "Test projects:"
echo "  - $TEST_PROJECT_1"
echo "  - $TEST_PROJECT_2"
echo "  - $TEST_PROJECT_3"
echo ""
echo "You can now launch Contextify. It should discover these projects automatically."
echo ""
echo "To clean up after testing:"
echo "  rm -rf ~/.claude/projects ~/.codex/sessions /tmp/contextify-test-project-*"
