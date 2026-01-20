#!/bin/sh
set -e

# Contextify Linux Installer
# Usage: curl -fsSL https://contextify.sh/install.sh | sh
#    or: curl -fsSL https://contextify.sh/install.sh | sh -s -- --install-service

REPO="PeterPym/contextify"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SKIP_SKILL=0
INSTALL_SERVICE=0
INSTALL_CRON=0
RUN_INGEST=0
NON_INTERACTIVE=0
TMPDIR=""

# Colors (disabled if not a terminal or NO_COLOR is set)
setup_colors() {
    if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
        BOLD='\033[1m'
        DIM='\033[2m'
        GREEN='\033[0;32m'
        CYAN='\033[0;36m'
        YELLOW='\033[0;33m'
        RED='\033[0;31m'
        RESET='\033[0m'
        CHECK="${GREEN}✓${RESET}"
        ARROW="${CYAN}→${RESET}"
    else
        BOLD=''
        DIM=''
        GREEN=''
        CYAN=''
        YELLOW=''
        RED=''
        RESET=''
        CHECK="[ok]"
        ARROW="->"
    fi
}

print_logo() {
    printf "${CYAN}"
    cat << 'EOF'
   ___          _            _   _  __
  / __\___  _ _| |_ _____  _| |_(_)/ _|_   _
 / /  / _ \| ' \  _/ _ \ \/ /  _| |  _| | | |
/ /__| (_) | | | ||  __/>  <| | | | | | |_| |
\____/\___/|_| |_| \___/_/\_\_| |_|_|  \__, |
                                       |___/
EOF
    printf "${RESET}"
    echo ""
}

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
    echo "  --ingest            Run initial ingestion after install"
    echo "  --install-service   Enable automatic background ingestion (systemd)"
    echo "  --install-cron      Enable automatic background ingestion (cron)"
    echo "  --uninstall         Remove Contextify and related files"
    echo "  --no-skill          Skip Total Recall skill installation"
    echo "  --non-interactive   Skip all prompts (for scripting)"
    echo "  --help              Show this help"
    echo ""
    echo "Environment:"
    echo "  VERSION       Use specific version (default: latest)"
    echo "  INSTALL_DIR   Install location (default: ~/.local/bin)"
    exit 0
}

do_uninstall() {
    setup_colors
    echo ""
    printf "${BOLD}Uninstalling Contextify...${RESET}\n"
    echo ""

    # Stop and disable systemd service if present
    if has_systemd_user; then
        if systemctl --user is-enabled contextify-ingest.timer >/dev/null 2>&1; then
            printf "  ${ARROW} Stopping systemd timer..."
            systemctl --user stop contextify-ingest.timer 2>/dev/null || true
            systemctl --user disable contextify-ingest.timer 2>/dev/null || true
            printf " ${CHECK}\n"
        fi
        # Remove service files
        rm -f "$HOME/.config/systemd/user/contextify-ingest.service" 2>/dev/null
        rm -f "$HOME/.config/systemd/user/contextify-ingest.timer" 2>/dev/null
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # Remove cron job if present
    if has_cron && crontab -l 2>/dev/null | grep -q "contextify ingest"; then
        printf "  ${ARROW} Removing cron job..."
        crontab -l 2>/dev/null | grep -v "contextify ingest" | crontab - 2>/dev/null || true
        printf " ${CHECK}\n"
    fi

    # Remove binaries
    if [ -f "$INSTALL_DIR/contextify" ]; then
        printf "  ${ARROW} Removing binary..."
        rm -f "$INSTALL_DIR/contextify"
        rm -f "$INSTALL_DIR/contextify-query" 2>/dev/null
        rm -f "$INSTALL_DIR/contextify-ingest" 2>/dev/null
        printf " ${CHECK}\n"
    fi

    # Remove skills
    if [ -d "$HOME/.claude/skills/total-recall" ]; then
        printf "  ${ARROW} Removing Claude Code skill..."
        rm -rf "$HOME/.claude/skills/total-recall"
        printf " ${CHECK}\n"
    fi
    if [ -d "$HOME/.codex/skills/total-recall" ]; then
        printf "  ${ARROW} Removing Codex skill..."
        rm -rf "$HOME/.codex/skills/total-recall"
        printf " ${CHECK}\n"
    fi

    echo ""
    printf "${GREEN}Contextify uninstalled.${RESET}\n"
    echo ""
    printf "${DIM}Optional: Remove data directory manually:${RESET}\n"
    echo "  rm -rf ~/.local/share/contextify/"
    echo ""
    exit 0
}

# Check if we can prompt the user (can access /dev/tty and not non-interactive mode)
# Note: We check /dev/tty (not stdin) because stdin is a pipe in curl | sh
can_prompt() {
    [ "$NON_INTERACTIVE" -eq 0 ] && [ -r /dev/tty ] && [ -w /dev/tty ]
}

# Prompt user with default Y (returns 0 for yes, 1 for no)
prompt_yes() {
    prompt_msg="$1"
    if ! can_prompt; then
        return 1  # Default to no when non-interactive
    fi
    printf "${prompt_msg} [Y/n] "
    read -r answer </dev/tty
    case "$answer" in
        [nN]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Check if systemd user services are available
has_systemd_user() {
    command -v systemctl >/dev/null 2>&1 && \
    systemctl --user status >/dev/null 2>&1
}

# Check if cron is available
has_cron() {
    command -v crontab >/dev/null 2>&1
}

warn_if_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo ""
        printf "${YELLOW}Warning:${RESET} Running as root. This will install to ${BOLD}/root/.local/bin${RESET}\n"
        echo "and systemd user services may not work correctly."
        echo ""
        echo "For normal use, run as a regular user instead:"
        echo "  curl -fsSL https://contextify.sh/install.sh | sh"
        echo ""
        echo "For system-wide install, set INSTALL_DIR:"
        echo "  INSTALL_DIR=/usr/local/bin curl -fsSL https://contextify.sh/install.sh | sh"
        echo ""
    fi
}

main() {
    setup_colors
    print_logo
    parse_args "$@"
    warn_if_root
    check_os
    check_dependencies
    detect_arch
    detect_version
    download_and_extract
    verify_installation
    if [ "$SKIP_SKILL" -eq 0 ]; then
        install_skill
    fi

    # Interactive prompts (if TTY and not --non-interactive)
    echo ""

    # Background ingestion: prefer systemd, fallback to cron
    if [ "$INSTALL_SERVICE" -eq 0 ] && [ "$INSTALL_CRON" -eq 0 ]; then
        if has_systemd_user; then
            if prompt_yes "Enable automatic background ingestion (systemd)?"; then
                INSTALL_SERVICE=1
            fi
        elif has_cron; then
            if prompt_yes "Enable automatic background ingestion (cron)?"; then
                INSTALL_CRON=1
            fi
        fi
    fi

    if [ "$RUN_INGEST" -eq 0 ]; then
        if prompt_yes "Index your existing transcripts now?"; then
            RUN_INGEST=1
        fi
    fi

    # Execute based on flags (set by args or prompts)
    if [ "$INSTALL_SERVICE" -eq 1 ]; then
        try_install_service
    fi
    if [ "$INSTALL_CRON" -eq 1 ]; then
        try_install_cron
    fi
    if [ "$RUN_INGEST" -eq 1 ]; then
        run_initial_ingest
    fi
    print_success
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-skill) SKIP_SKILL=1 ;;
            --install-service) INSTALL_SERVICE=1 ;;
            --install-cron) INSTALL_CRON=1 ;;
            --ingest) RUN_INGEST=1 ;;
            --non-interactive|-y) NON_INTERACTIVE=1 ;;
            --uninstall) do_uninstall ;;
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
            printf "${RED}Error:${RESET} Unsupported architecture: $ARCH\n"
            echo "Contextify supports x86_64 and arm64."
            exit 1
            ;;
    esac
    printf "  ${CHECK} Detected architecture: ${BOLD}$ARCH${RESET}\n"
}

detect_version() {
    # Allow override via environment
    if [ -n "$VERSION" ]; then
        printf "  ${CHECK} Using version: ${BOLD}$VERSION${RESET} (from environment)\n"
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

    # Fallback to hosted version file if API fails (rate limit, etc.)
    if [ -z "$VERSION" ]; then
        VERSION=$(curl -fsSL "https://contextify.sh/cli-version.txt" 2>/dev/null | tr -d '\r\n' || true)
    fi

    if [ -z "$VERSION" ]; then
        printf "${RED}Error:${RESET} Could not detect latest version\n"
        echo "Try: VERSION=1.1.0 curl -fsSL https://contextify.sh/install.sh | sh"
        exit 1
    fi
    printf "  ${CHECK} Latest version: ${BOLD}$VERSION${RESET}\n"
}

download_and_extract() {
    BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"
    TARBALL="contextify-linux-$ARCH.tar.gz"
    URL="$BASE_URL/$TARBALL"
    CHECKSUM_URL="$BASE_URL/$TARBALL.sha256"

    echo ""
    printf "${BOLD}Installing Contextify v$VERSION${RESET}\n"
    printf "  ${DIM}From: $URL${RESET}\n"
    printf "  ${DIM}To:   $INSTALL_DIR/contextify${RESET}\n"
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
    printf "  ${ARROW} Verifying checksum..."
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
    printf " ${CHECK}\n"

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
    printf "  ${ARROW} Installing Total Recall skill...\n"
    if "$INSTALL_DIR/contextify" install-skill >/dev/null 2>&1; then
        # Show where skills were installed
        if [ -d "$HOME/.claude/skills/total-recall" ]; then
            printf "     ${DIM}Installed to: ~/.claude/skills/total-recall${RESET}\n"
        fi
        if [ -d "$HOME/.codex/skills/total-recall" ]; then
            printf "     ${DIM}Installed to: ~/.codex/skills/total-recall${RESET}\n"
        fi
        printf "  ${CHECK} Skill installed\n"
    else
        printf "  ${YELLOW}(skipped)${RESET}\n"
    fi
}

try_install_service() {
    printf "  ${ARROW} Enabling background ingestion (systemd)...\n"
    if "$INSTALL_DIR/contextify" install-service >/dev/null 2>&1; then
        printf "     ${DIM}Timer: contextify-ingest.timer (runs every 15 minutes)${RESET}\n"
        printf "     ${DIM}Check status: systemctl --user status contextify-ingest.timer${RESET}\n"
        printf "  ${CHECK} Service enabled\n"
    else
        printf "  ${YELLOW}(failed - run manually)${RESET}\n"
    fi
}

try_install_cron() {
    printf "  ${ARROW} Enabling background ingestion (cron)...\n"
    # Add cron job to run ingest every 15 minutes
    CRON_CMD="*/15 * * * * $INSTALL_DIR/contextify ingest --quiet"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -q "contextify ingest"; then
        printf "     ${DIM}Cron job already configured (runs every 15 minutes)${RESET}\n"
        printf "  ${CHECK} Cron enabled\n"
        return 0
    fi

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
    if [ $? -eq 0 ]; then
        printf "     ${DIM}Cron job: runs every 15 minutes${RESET}\n"
        printf "     ${DIM}Check status: crontab -l | grep contextify${RESET}\n"
        printf "  ${CHECK} Cron enabled\n"
    else
        printf "  ${YELLOW}(failed - add manually)${RESET}\n"
    fi
}

run_initial_ingest() {
    echo ""
    printf "${BOLD}Indexing your transcripts...${RESET}\n"
    echo ""
    # Run ingest and show output (it has its own progress indicators)
    if "$INSTALL_DIR/contextify" ingest 2>&1; then
        echo ""
        printf "  ${CHECK} Ingestion complete\n"
    else
        printf "  ${YELLOW}Ingestion had issues - check 'contextify ingest' for details${RESET}\n"
    fi
}

check_path() {
    # Check if install dir is in PATH
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) return 0 ;;
        *) return 1 ;;
    esac
}

add_to_path() {
    # Auto-add ~/.local/bin to PATH in shell config (like rustup, nvm do)
    # Sets PATH_NEEDS_RESTART=1 if user needs to restart shell
    SHELL_NAME="${SHELL##*/}"
    PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
    PATH_NEEDS_RESTART=0

    case "$SHELL_NAME" in
        bash)
            RC_FILE="$HOME/.bashrc"
            ;;
        zsh)
            RC_FILE="$HOME/.zshrc"
            ;;
        fish)
            # fish uses fish_add_path which is persistent and immediate
            if command -v fish >/dev/null 2>&1; then
                fish -c "fish_add_path $HOME/.local/bin" 2>/dev/null || true
                printf "  ${CHECK} Added to fish PATH\n"
            fi
            return 0
            ;;
        *)
            RC_FILE="$HOME/.profile"
            ;;
    esac

    # Check if already present in config
    if [ -f "$RC_FILE" ] && grep -q '\.local/bin' "$RC_FILE" 2>/dev/null; then
        printf "  ${CHECK} PATH configured in $RC_FILE\n"
    else
        printf "  ${ARROW} Adding ~/.local/bin to your PATH in $RC_FILE\n"
        echo "" >> "$RC_FILE"
        echo "# Added by Contextify installer" >> "$RC_FILE"
        echo "$PATH_LINE" >> "$RC_FILE"
        printf "  ${CHECK} Added to $RC_FILE\n"
        printf "  ${DIM}To undo: remove the 'Added by Contextify installer' block from $RC_FILE${RESET}\n"
    fi

    # Either way, if not in current PATH, user needs to restart
    PATH_NEEDS_RESTART=1
}

print_success() {
    PATH_NEEDS_RESTART=0

    echo ""
    printf "${GREEN}${BOLD}Installation complete!${RESET}\n"
    echo ""

    # Verify it works
    printf "  ${CHECK} contextify --version ${DIM}→${RESET} "
    "$INSTALL_DIR/contextify" --version 2>/dev/null || echo "(installed)"

    if ! check_path; then
        add_to_path
    fi

    # Prominent restart message if needed
    if [ "$PATH_NEEDS_RESTART" -eq 1 ]; then
        echo ""
        printf "${YELLOW}${BOLD}>>> Restart your shell or run:${RESET}\n"
        printf "    ${BOLD}source ~/${RC_FILE##*/}${RESET}\n"
    fi

    echo ""
    printf "${BOLD}Next steps:${RESET}\n"
    echo ""

    printf "  ${ARROW} Search your past conversations with Total Recall:\n"
    echo "     /total-recall \"what did we decide about...\""
    echo ""

    printf "${DIM}Docs: https://contextify.sh/docs/${RESET}\n"
    echo ""

    # Thank you and contact
    printf "Thanks for installing! Questions or feedback: ${CYAN}rob@contextify.sh${RESET}\n"
}

main "$@"
