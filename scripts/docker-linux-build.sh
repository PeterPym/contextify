#!/bin/bash
# Build for Linux using Docker with Colima
# Uses separate .build-linux directory to avoid conflicts with macOS build
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
RUN_INSTALL_TEST=""
for arg in "$@"; do
  case "$arg" in
    --e2e)
      RUN_E2E="1"
      ;;
    --install-test)
      RUN_INSTALL_TEST="1"
      ;;
  esac
done

echo "=== Docker Linux Build ==="
echo "Project: $PROJECT_ROOT"
echo "Git root: $GIT_ROOT"
echo "SQLite version: $SQLITE_VERSION"
[ -n "$RUN_E2E" ] && echo "E2E test: enabled"
[ -n "$RUN_INSTALL_TEST" ] && echo "Install test: enabled"

docker run --rm \
  -v "$PROJECT_ROOT":/workspace:rw \
  -v "$GIT_ROOT/.git":"$GIT_ROOT/.git":ro \
  -e RUN_E2E="$RUN_E2E" \
  -e RUN_INSTALL_TEST="$RUN_INSTALL_TEST" \
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

    # Run install test if --install-test flag was passed
    if [ -n "$RUN_INSTALL_TEST" ]; then
      echo ""
      echo "=== Running Install Test ==="
      echo "This simulates what a user does after downloading the tarball"
      echo ""

      # Step 1: Create tarball from built binaries (like release workflow does)
      echo "--- Step 1: Creating tarball from built binaries ---"
      TARBALL_DIR="/tmp/install-test"
      rm -rf "$TARBALL_DIR"
      mkdir -p "$TARBALL_DIR/dist"

      cp /workspace/.build-linux/debug/contextify-query "$TARBALL_DIR/dist/"
      cp /workspace/.build-linux/debug/contextify-ingest "$TARBALL_DIR/dist/"
      cp -R /workspace/contextify-query/user-skill "$TARBALL_DIR/dist/"

      cd "$TARBALL_DIR/dist"
      tar -czvf "$TARBALL_DIR/contextify-linux-test.tar.gz" contextify-query contextify-ingest user-skill
      echo "Created tarball at $TARBALL_DIR/contextify-linux-test.tar.gz"

      # Step 2: Extract tarball like a user would
      echo ""
      echo "--- Step 2: Extracting tarball ---"
      EXTRACT_DIR="/tmp/install-test-extract"
      rm -rf "$EXTRACT_DIR"
      mkdir -p "$EXTRACT_DIR"
      cd "$EXTRACT_DIR"
      tar -xzf "$TARBALL_DIR/contextify-linux-test.tar.gz"
      echo "Extracted to $EXTRACT_DIR"
      ls -la "$EXTRACT_DIR"

      # Step 3: Move binaries to ~/.local/bin (standard Linux user install location)
      # The CLI looks for user-skill directory sibling to the binary
      echo ""
      echo "--- Step 3: Installing to ~/.local/bin ---"
      mkdir -p ~/.local/bin
      mv "$EXTRACT_DIR/contextify-query" ~/.local/bin/
      mv "$EXTRACT_DIR/contextify-ingest" ~/.local/bin/
      mv "$EXTRACT_DIR/user-skill" ~/.local/bin/

      echo "Installed binaries to ~/.local/bin/"
      ls -la ~/.local/bin/contextify-*
      ls -la ~/.local/bin/user-skill/

      # Step 4: Add to PATH
      echo ""
      echo "--- Step 4: Adding ~/.local/bin to PATH ---"
      export PATH="$HOME/.local/bin:$PATH"
      echo "PATH now includes: $HOME/.local/bin"

      # Step 5: Run contextify-query --version from PATH
      echo ""
      echo "--- Step 5: Running contextify-query --version ---"
      if contextify-query --version; then
        echo "PASS: contextify-query --version works"
      else
        echo "FAIL: contextify-query --version failed"
        exit 1
      fi

      # Step 6: Run install-plugin
      # The CLI finds user-skill sibling to the binary (resolved via PATH lookup)
      echo ""
      echo "--- Step 6: Running contextify-query install-plugin ---"
      if contextify-query install-plugin; then
        echo "PASS: install-plugin completed"
      else
        echo "FAIL: install-plugin failed"
        exit 1
      fi

      # Step 7: Verify skill files exist
      echo ""
      echo "--- Step 7: Verifying skill files ---"
      CLAUDE_SKILL="$HOME/.claude/skills/total-recall/SKILL.md"
      CODEX_SKILL="$HOME/.codex/skills/total-recall/SKILL.md"

      if [ -f "$CLAUDE_SKILL" ]; then
        echo "PASS: Claude skill exists at $CLAUDE_SKILL"
        echo "  Size: $(wc -c < "$CLAUDE_SKILL") bytes"
      else
        echo "FAIL: Claude skill missing at $CLAUDE_SKILL"
        exit 1
      fi

      if [ -f "$CODEX_SKILL" ]; then
        echo "PASS: Codex skill exists at $CODEX_SKILL"
        echo "  Size: $(wc -c < "$CODEX_SKILL") bytes"
      else
        echo "FAIL: Codex skill missing at $CODEX_SKILL"
        exit 1
      fi

      # Verify skill content is non-empty and looks valid
      if grep -q "total-recall" "$CLAUDE_SKILL"; then
        echo "PASS: Claude skill contains expected content"
      else
        echo "FAIL: Claude skill does not contain expected content"
        exit 1
      fi

      # Step 8: Run contextify-query doctor
      echo ""
      echo "--- Step 8: Running contextify-query doctor ---"
      contextify-query doctor || true  # Allow non-zero exit (degraded status expected without database)

      echo ""
      echo "=== Install Test PASSED ==="
      echo "All installation steps completed successfully:"
      echo "  - Tarball creation"
      echo "  - Extraction"
      echo "  - Binary installation to ~/.local/bin"
      echo "  - PATH configuration"
      echo "  - Version check"
      echo "  - Skill installation"
      echo "  - Skill file verification"
      echo "  - Doctor command"
    fi
  '

echo "=== Build Complete ==="
