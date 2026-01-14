#!/bin/sh
set -e

# Contextify Linux Installer
# Usage: curl -fsSL https://contextify.sh/install.sh | sh
#    or: curl -fsSL https://contextify.sh/install.sh | sh -s -- --no-skill

REPO="PeterPym/contextify"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SKIP_SKILL=0
TMPDIR=""

# Cleanup on exit (success or failure)
cleanup() {
    if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    echo "Contextify Linux Installer"
    echo ""
    echo "Usage: curl -fsSL https://contextify.sh/install.sh | sh"
    echo "   or: curl -fsSL https://contextify.sh/install.sh | sh -s -- [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --no-skill    Skip Total Recall skill installation"
    echo "  --help        Show this help"
    echo ""
    echo "Environment:"
    echo "  VERSION       Use specific version (default: latest)"
    echo "  INSTALL_DIR   Install location (default: ~/.local/bin)"
    exit 0
}

main() {
    parse_args "$@"
    check_dependencies
    detect_arch
    detect_version
    download_and_extract
    verify_installation
    if [ "$SKIP_SKILL" -eq 0 ]; then
        install_skill
    fi
    print_success
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-skill) SKIP_SKILL=1 ;;
            --help|-h) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
        shift
    done
}

check_dependencies() {
    # Required commands (all standard on Linux, but check anyway)
    for cmd in curl tar mktemp sha256sum awk sed uname chmod mkdir; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: '$cmd' is required but not found."
            echo "Install it with your package manager and retry."
            exit 1
        fi
    done
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="x86_64" ;;
        aarch64) ARCH="arm64" ;;
        arm64)   ARCH="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $ARCH"
            echo "Contextify supports x86_64 and arm64."
            exit 1
            ;;
    esac
    echo "Detected architecture: $ARCH"
}

detect_version() {
    # Allow override via environment
    if [ -n "$VERSION" ]; then
        echo "Using VERSION from environment: $VERSION"
        return
    fi

    # Try GitHub API first (use -f to fail on HTTP errors)
    VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
              grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/' || true)

    # Fallback to hosted version file if API fails (rate limit, etc.)
    if [ -z "$VERSION" ]; then
        echo "GitHub API unavailable, trying fallback..."
        VERSION=$(curl -fsSL "https://contextify.sh/cli-version.txt" 2>/dev/null || true)
    fi

    if [ -z "$VERSION" ]; then
        echo "Error: Could not detect latest version"
        echo "Try: VERSION=1.1.0 curl -fsSL https://contextify.sh/install.sh | sh"
        exit 1
    fi
    echo "Latest version: $VERSION"
}

download_and_extract() {
    BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"
    TARBALL="contextify-linux-$ARCH.tar.gz"
    URL="$BASE_URL/$TARBALL"
    CHECKSUM_URL="$BASE_URL/$TARBALL.sha256"

    echo ""
    echo "Installing Contextify v$VERSION"
    echo "  From: $URL"
    echo "  To:   $INSTALL_DIR/contextify"
    echo ""
    mkdir -p "$INSTALL_DIR"

    # Create temp dir for download (cleaned up by trap)
    TMPDIR=$(mktemp -d)

    # Download tarball (-f fails on HTTP errors like 404)
    if ! curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"; then
        echo "Error: Failed to download $URL"
        echo "Check that version $VERSION exists and your network connection."
        exit 1
    fi

    # Download and verify checksum
    echo "Verifying checksum..."
    if ! EXPECTED=$(curl -fsSL "$CHECKSUM_URL" | awk '{print $1}'); then
        echo "Error: Failed to download checksum file"
        echo "Release may be incomplete. Try a different VERSION."
        exit 1
    fi

    if [ -z "$EXPECTED" ]; then
        echo "Error: Checksum file is empty or malformed"
        exit 1
    fi

    ACTUAL=$(sha256sum "$TMPDIR/$TARBALL" | awk '{print $1}')
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Error: Checksum verification failed!"
        echo "Expected: $EXPECTED"
        echo "Actual:   $ACTUAL"
        echo ""
        echo "This could indicate a corrupted download or tampered file."
        exit 1
    fi
    echo "Checksum verified."

    # Extract (tarball contains: contextify, contextify-ingest, contextify-query symlinks)
    tar -xzf "$TMPDIR/$TARBALL" -C "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/contextify"

    # Verify tarball layout contract
    if [ ! -x "$INSTALL_DIR/contextify" ]; then
        echo "Error: missing contextify in tarball root (bad tarball layout?)"
        exit 1
    fi
    # Symlinks are optional for functionality but expected in v1
    [ -L "$INSTALL_DIR/contextify-ingest" ] || echo "Warning: missing contextify-ingest symlink"
    [ -L "$INSTALL_DIR/contextify-query" ]  || echo "Warning: missing contextify-query symlink"
}

verify_installation() {
    if ! "$INSTALL_DIR/contextify" --version >/dev/null 2>&1; then
        echo "Error: Installation verification failed"
        echo ""
        echo "The binary was installed but won't execute. Possible causes:"
        echo "  - Missing shared libraries (run: ldd $INSTALL_DIR/contextify)"
        echo "  - glibc version too old (need glibc 2.35+, Ubuntu 22.04+)"
        echo ""
        echo "Report issues: https://github.com/PeterPym/contextify/issues"
        exit 1
    fi
}

install_skill() {
    echo "Installing Total Recall skill..."
    "$INSTALL_DIR/contextify" install-skill
}

check_path() {
    # Check if install dir is in PATH
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) return 0 ;;
        *) return 1 ;;
    esac
}

print_success() {
    echo ""
    echo "Contextify installed successfully!"
    echo ""
    echo "Binary: $INSTALL_DIR/contextify"
    echo ""

    if ! check_path; then
        echo "WARNING: $INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add it to your shell configuration:"
        echo ""
        # Detect shell and provide appropriate advice
        SHELL_NAME=$(basename "$SHELL")
        case "$SHELL_NAME" in
            bash)
                echo "  # For bash, add to ~/.bashrc:"
                echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
                echo "  source ~/.bashrc"
                ;;
            zsh)
                echo "  # For zsh, add to ~/.zshrc:"
                echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
                echo "  source ~/.zshrc"
                ;;
            fish)
                echo "  # For fish, run:"
                echo "  fish_add_path ~/.local/bin"
                ;;
            *)
                echo "  # Add this to your shell config:"
                echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                ;;
        esac
        echo ""
    fi

    echo "NEXT STEPS:"
    echo ""
    echo "  1. Set up automatic ingestion:"
    echo "     contextify install-service"
    echo ""
    echo "  2. Use Total Recall in Claude Code or Codex:"
    echo "     /total-recall"
    echo ""
    echo "Documentation: https://contextify.sh/docs/"
}

main "$@"
