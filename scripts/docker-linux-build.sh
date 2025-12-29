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

echo "=== Docker Linux Build ==="
echo "Project: $PROJECT_ROOT"
echo "Git root: $GIT_ROOT"
echo "SQLite version: $SQLITE_VERSION"

docker run --rm \
  -v "$PROJECT_ROOT":/workspace:rw \
  -v "$GIT_ROOT/.git":"$GIT_ROOT/.git":ro \
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
  '

echo "=== Build Complete ==="
