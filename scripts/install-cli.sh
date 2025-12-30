#!/bin/bash
# Install contextify-ingest CLI from GitHub releases
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/banagale/contextify/main/scripts/install-cli.sh | bash
#   curl -fsSL ... | bash -s -- 1.0.0    # Specific version
#
# Environment variables:
#   INSTALL_DIR - Installation directory (default: ~/.local/bin)
#   VERSION     - Version to install (default: latest)

set -e

# Configuration
REPO="banagale/contextify"
BINARY_NAME="contextify-ingest"
DEFAULT_INSTALL_DIR="${HOME}/.local/bin"

# Parse arguments
VERSION="${1:-${VERSION:-latest}}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)
    ARCH_SUFFIX="x86_64"
    ;;
  aarch64|arm64)
    ARCH_SUFFIX="arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $ARCH" >&2
    echo "Supported: x86_64, aarch64" >&2
    exit 1
    ;;
esac

# Detect OS
OS=$(uname -s)
case "$OS" in
  Linux)
    OS_SUFFIX="linux"
    ;;
  Darwin)
    echo "Error: macOS users should use the Contextify app instead" >&2
    echo "Download from: https://contextify.sh" >&2
    exit 1
    ;;
  *)
    echo "Error: Unsupported OS: $OS" >&2
    echo "This installer is for Linux only" >&2
    exit 1
    ;;
esac

# Resolve version
if [ "$VERSION" = "latest" ]; then
  echo "Fetching latest version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"cli-v([^"]+)".*/\1/')
  if [ -z "$VERSION" ]; then
    echo "Error: Could not determine latest version" >&2
    exit 1
  fi
fi

TAG="cli-v$VERSION"
TARBALL="${BINARY_NAME}-${OS_SUFFIX}-${ARCH_SUFFIX}.tar.gz"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$TARBALL"

echo "Installing $BINARY_NAME v$VERSION for $OS_SUFFIX/$ARCH_SUFFIX..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download and extract
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading from $DOWNLOAD_URL..."
if ! curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$TARBALL"; then
  echo "Error: Download failed" >&2
  echo "Check if version $VERSION exists: https://github.com/$REPO/releases" >&2
  exit 1
fi

echo "Extracting..."
tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"

# Install
echo "Installing to $INSTALL_DIR/$BINARY_NAME..."
mv "$TMP_DIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Verify installation
if "$INSTALL_DIR/$BINARY_NAME" --version > /dev/null 2>&1; then
  INSTALLED_VERSION=$("$INSTALL_DIR/$BINARY_NAME" --version 2>&1 | head -1)
  echo ""
  echo "Successfully installed: $INSTALLED_VERSION"
else
  echo ""
  echo "Warning: Binary installed but may not run correctly"
  echo "Try: $INSTALL_DIR/$BINARY_NAME --version"
fi

# Check if install dir is in PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  echo ""
  echo "Note: $INSTALL_DIR is not in your PATH"
  echo "Add this to your shell config (~/.bashrc, ~/.zshrc, etc.):"
  echo ""
  echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
  echo ""
fi

echo ""
echo "Usage:"
echo "  $BINARY_NAME discover              # Find transcripts"
echo "  $BINARY_NAME ingest --db ~/db.db   # Ingest transcripts"
echo "  $BINARY_NAME verify --db ~/db.db   # Verify database"
