#!/bin/sh
set -e

# Contextify Linux Installer
# Script version: 1.2.0 (anchored to CLI v1.2.0 release)
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
    check_os
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

check_os() {
    OS=$(uname -s 2>/dev/null || echo unknown)
    case "$OS" in
        Linux) ;;
        Darwin)
            echo "Error: This installer is for Linux only."
            echo ""
            echo "For macOS, download from: https://contextify.sh/download/"
            echo "Or see documentation: https://contextify.sh/docs/"
            exit 1
            ;;
        *)
            echo "Error: Unsupported operating system: $OS"
            echo "This installer supports Linux only."
            exit 1
            ;;
    esac
}

check_dependencies() {
    # Required commands (all standard on Linux, but check anyway)
    for cmd in curl tar mktemp sha256sum awk grep sed uname chmod mkdir tr rm mv; do
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

    # Try GitHub API first - POSIX-friendly JSON parsing with awk (no sed -E)
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
          awk -F'"' '/"tag_name"/ { print $4; exit }' || true)

    # Strip tag prefix to get bare version number (handles cli-v1.0.0, v1.0.0, or bare 1.0.0)
    case "$TAG" in
        cli-v*) VERSION=${TAG#cli-v} ;;
        cli-*)  VERSION=${TAG#cli-} ;;
        v*)     VERSION=${TAG#v} ;;
        *)      VERSION=$TAG ;;
    esac

    if [ -z "$VERSION" ]; then
        echo "Error: Could not detect latest version from GitHub API"
        echo "This may be due to rate limiting. Try specifying VERSION manually:"
        echo "  VERSION=1.2.0 curl -fsSL https://contextify.sh/install.sh | sh"
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
    # Use portable mktemp invocation
    TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t contextify.XXXXXX)
    STAGEDIR="$TMPDIR/stage"
    mkdir -p "$STAGEDIR"

    # Download tarball (-f fails on HTTP errors like 404)
    if ! curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"; then
        echo "Error: Failed to download $URL"
        echo "Check that version $VERSION exists and your network connection."
        exit 1
    fi

    # Download and verify checksum
    echo "Verifying checksum..."
    EXPECTED=$(curl -fsSL "$CHECKSUM_URL" | awk '{print $1}' | tr -d '\r' || true)

    # Validate checksum is a 64-char hex string
    if [ -z "$EXPECTED" ]; then
        echo "Error: Failed to download checksum file"
        echo "Release may be incomplete. Try a different VERSION."
        exit 1
    fi

    # Verify checksum format (exactly 64 hex chars, nothing else)
    case "$EXPECTED" in
        *[!0-9a-fA-F]*|'')
            echo "Error: Checksum file is malformed (contains non-hex characters)"
            exit 1
            ;;
    esac
    if [ ${#EXPECTED} -ne 64 ]; then
        echo "Error: Checksum file is malformed (expected 64 hex chars, got ${#EXPECTED})"
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

    # Validate tarball contents before extraction (security: prevent path traversal attacks)
    LIST=$(tar -tzf "$TMPDIR/$TARBALL") || { echo "Error: Failed to list tarball contents"; exit 1; }

    # Normalize ./ prefix entries (tar creation style varies)
    NORM_LIST=$(echo "$LIST" | sed 's|^\./||')

    # Reject unsafe paths using awk (POSIX-friendly)
    echo "$NORM_LIST" | awk '
        $0 == "" { bad=1 }                          # empty lines
        $0 ~ /^\// { bad=1 }                        # absolute paths
        $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 }           # .. path segments
        END { exit (bad ? 1 : 0) }
    ' || { echo "Error: Tarball contains unsafe paths (absolute or traversal)"; exit 1; }

    # Verify expected layout (contextify binary required, others optional)
    if ! echo "$NORM_LIST" | grep -qx 'contextify'; then
        echo "Error: Tarball missing 'contextify' binary"
        exit 1
    fi

    # Extract to staging directory
    tar -xzf "$TMPDIR/$TARBALL" -C "$STAGEDIR"

    # Double-check extraction result
    if [ ! -f "$STAGEDIR/contextify" ]; then
        echo "Error: missing contextify in tarball root (bad tarball layout?)"
        exit 1
    fi

    # Move files from staging to install directory
    mv -f "$STAGEDIR/contextify" "$INSTALL_DIR/contextify"
    chmod +x "$INSTALL_DIR/contextify"

    # Move symlinks if present, remove stale ones if not (backwards compatibility)
    if [ -L "$STAGEDIR/contextify-ingest" ]; then
        mv -f "$STAGEDIR/contextify-ingest" "$INSTALL_DIR/contextify-ingest"
    else
        rm -f "$INSTALL_DIR/contextify-ingest" 2>/dev/null || true
    fi
    if [ -L "$STAGEDIR/contextify-query" ]; then
        mv -f "$STAGEDIR/contextify-query" "$INSTALL_DIR/contextify-query"
    else
        rm -f "$INSTALL_DIR/contextify-query" 2>/dev/null || true
    fi

    # Move user-skill directory if present
    if [ -d "$STAGEDIR/user-skill" ]; then
        rm -rf "$INSTALL_DIR/user-skill"
        mv -f "$STAGEDIR/user-skill" "$INSTALL_DIR/user-skill"
    fi
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
        # Detect shell using POSIX parameter expansion (no basename dependency)
        SHELL_NAME="${SHELL##*/}"
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
        echo "NEXT STEPS (use full path until PATH is updated):"
        echo ""
        echo "  1. Set up automatic ingestion:"
        echo "     $INSTALL_DIR/contextify install-service"
    else
        echo "NEXT STEPS:"
        echo ""
        echo "  1. Set up automatic ingestion:"
        echo "     contextify install-service"
    fi

    echo ""
    echo "  2. Use Total Recall in Claude Code or Codex:"
    echo "     /total-recall"
    echo ""
    echo "Documentation: https://contextify.sh/docs/"
}

main "$@"
