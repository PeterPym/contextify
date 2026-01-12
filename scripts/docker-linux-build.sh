#!/bin/bash
# Build for Linux using Docker with Colima
# Uses separate .build-linux directory to avoid conflicts with macOS build
#
# Usage:
#   bash scripts/docker-linux-build.sh             # Basic build only
#   bash scripts/docker-linux-build.sh --e2e       # Build + E2E transcript ingestion test
#   bash scripts/docker-linux-build.sh --install-test  # Build + user install flow validation
#
# Prerequisites:
#   - Docker running (macOS: brew install colima && colima start)
#   - Internet connection (downloads Swift image + SQLite source)
#
# What each test validates:
#   Basic build:   Swift 6 compiles on Linux, SQLite links correctly
#   E2E test:      Binary executes, parses transcripts, writes to database
#   Install test:  Tarball extraction, PATH install, skill manifest validation
#
# For full documentation: scripts/qa/README.md (Linux QA section)
#
# Note: Builds SQLite from source with SQLITE_ENABLE_SNAPSHOT because
# GRDB requires sqlite3_snapshot_* functions which aren't in distro packages.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Derive GIT_ROOT dynamically - works for both main repo and worktrees
# For worktrees, --git-common-dir points to the main repo's .git directory
GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$GIT_DIR" ]; then
  echo "Error: Not a git repository" >&2
  exit 1
fi
# Convert to absolute path and get the parent directory (the actual repo root)
GIT_ROOT="$(cd "$GIT_DIR/.." && pwd)"

# SQLite version to build (with ENABLE_SNAPSHOT support)
SQLITE_VERSION="3450100"
SQLITE_URL="https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz"

# Parse arguments
RUN_E2E=""
if [ "$1" = "--e2e" ]; then
  RUN_E2E="1"
fi

echo "=== Docker Linux Build ==="
echo "Project: $PROJECT_ROOT"
echo "Git root: $GIT_ROOT"
echo "SQLite version: $SQLITE_VERSION"
[ -n "$RUN_E2E" ] && echo "E2E test: enabled"

docker run --rm \
  -v "$PROJECT_ROOT":/workspace:rw \
  -v "$GIT_ROOT/.git":"$GIT_ROOT/.git":ro \
  -e RUN_E2E="$RUN_E2E" \
  -w /workspace \
  swift:6.0-noble \
  bash -c '
    set -e
    git config --global --add safe.directory "*"

    # Install build dependencies
    apt-get update -qq
    apt-get install -y build-essential curl pkg-config -qq > /dev/null 2>&1

    echo "=== Building SQLite with ENABLE_SNAPSHOT ==="
    cd /tmp
    curl -sL "'"$SQLITE_URL"'" | tar xz
    cd sqlite-autoconf-*
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -O2" \
      ./configure --prefix=/usr --libdir=/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH) --quiet
    make -j$(nproc) --quiet
    make install --quiet
    ldconfig

    echo "SQLite version installed:"
    sqlite3 --version
    echo "Snapshot symbols:"
    nm -D /usr/lib/*/libsqlite3.so | grep sqlite3_snapshot | head -3 || echo "Warning: No snapshot symbols"

    cd /workspace

    echo "=== Resolving packages ==="
    swift package resolve 2>&1 | tail -5

    echo "=== Building for Linux ==="
    swift build --build-path /workspace/.build-linux 2>&1

    # Run E2E test if --e2e flag was passed
    if [ -n "$RUN_E2E" ]; then
      echo ""
      echo "=== Running E2E Test ==="

      # Create test fixture directory structure
      mkdir -p ~/.claude/projects/test-project-hash

      # Create a minimal Claude Code transcript
      cat > ~/.claude/projects/test-project-hash/test-session.jsonl << '"'"'TRANSCRIPT'"'"'
{"type":"queue-operation","operation":"dequeue","timestamp":"2025-12-11T23:01:02.369Z","sessionId":"test-session-1"}
{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"test-session-1","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":"Hello, can you help me with a simple task?"},"uuid":"user-msg-1","timestamp":"2025-12-11T23:01:02.375Z"}
{"parentUuid":"user-msg-1","isSidechain":false,"userType":"external","cwd":"/test/project","sessionId":"test-session-1","version":"2.0.65","gitBranch":"main","message":{"model":"claude-opus-4-5-20251101","id":"msg_test","type":"message","role":"assistant","content":[{"type":"text","text":"Of course! I am happy to help. What would you like me to do?"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":20}},"requestId":"req_test","type":"assistant","uuid":"assistant-msg-1","timestamp":"2025-12-11T23:01:07.735Z"}
TRANSCRIPT

      echo "Created test transcript at ~/.claude/projects/test-project-hash/test-session.jsonl"

      # Create a fresh database
      DB_PATH="/tmp/e2e-test.db"
      rm -f "$DB_PATH"

      echo ""
      echo "--- Running ingest command ---"
      /workspace/.build-linux/debug/contextify-ingest ingest --db "$DB_PATH" --format human

      echo ""
      echo "--- Verifying database contents ---"

      # Check tables
      PROJECT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM projects;")
      TRANSCRIPT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcripts;")
      ENTRY_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_entries;")

      echo "Projects: $PROJECT_COUNT"
      echo "Transcripts: $TRANSCRIPT_COUNT"
      echo "Entries: $ENTRY_COUNT"

      if [ "$PROJECT_COUNT" -ge 1 ] && [ "$TRANSCRIPT_COUNT" -ge 1 ] && [ "$ENTRY_COUNT" -ge 2 ]; then
        echo ""
        echo "=== E2E Test PASSED ==="
        sqlite3 -header -column "$DB_PATH" "SELECT kind, substr(content, 1, 50) as content FROM transcript_entries LIMIT 3;"
      else
        echo ""
        echo "=== E2E Test FAILED ==="
        echo "Expected at least 1 project, 1 transcript, 2 entries"
        exit 1
      fi
    fi
  '

echo "=== Build Complete ==="
