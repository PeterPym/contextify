#!/bin/sh
set -e

# Contextify Installer (Linux + macOS)
# Usage: curl -fsSL https://contextify.sh/install.sh | sh
#    or: curl -fsSL https://contextify.sh/install.sh | sh -s -- --install-service

REPO="PeterPym/contextify"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SKIP_SKILL=0
INSTALL_SERVICE=0
INSTALL_CRON=0
SKIP_INGEST=0
KEEP_TMPDIR=0
NON_INTERACTIVE=0
HAS_TRANSCRIPTS=0
HAS_PROVIDER=0
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
        CROSS="${RED}✗${RESET}"
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
        CROSS="[x]"
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

# Cleanup and error handling on exit
CLEANUP_DONE=0
cleanup() {
    [ "$CLEANUP_DONE" -eq 1 ] && return
    CLEANUP_DONE=1
    exit_code=$?
    if [ "$KEEP_TMPDIR" -eq 0 ] && [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
        rm -rf "$TMPDIR"
    fi
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Need help? Email rob@contextify.sh"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    OS_NAME=$(uname -s 2>/dev/null || echo unknown)
    case "$OS_NAME" in
        Linux)  echo "Contextify Linux Installer" ;;
        Darwin) echo "Contextify macOS Installer" ;;
        *)      echo "Contextify Installer" ;;
    esac
    echo ""
    echo "Usage: curl -fsSL https://contextify.sh/install.sh | sh"
    echo "   or: curl -fsSL https://contextify.sh/install.sh | sh -s -- [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --no-ingest         Skip initial transcript indexing"
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

    # Remove cron job if present (match our exact install pattern)
    if has_cron && crontab -l 2>/dev/null | grep -q "contextify ingest --quiet"; then
        printf "  ${ARROW} Removing cron job..."
        crontab -l 2>/dev/null | grep -v "contextify ingest --quiet" | crontab - 2>/dev/null || true
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

# Check for transcripts and display status
# Sets CLAUDE_TRANSCRIPTS, CODEX_TRANSCRIPTS, HAS_TRANSCRIPTS, HAS_PROVIDER
check_transcripts() {
    printf "  ${ARROW} Looking for your existing transcripts...\n"

    CLAUDE_TRANSCRIPTS=0
    CODEX_TRANSCRIPTS=0
    CLAUDE_INSTALLED=0
    CODEX_INSTALLED=0

    # Claude Code - check if installed, then count transcripts
    if [ -d "$HOME/.claude" ]; then
        CLAUDE_INSTALLED=1
        if [ -d "$HOME/.claude/projects" ]; then
            CLAUDE_TRANSCRIPTS=$(find "$HOME/.claude/projects" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        fi
    fi
    if [ "$CLAUDE_TRANSCRIPTS" -gt 0 ]; then
        printf "     ${CHECK} Claude Code: transcripts found\n"
    else
        printf "     ${CROSS} Claude Code: no transcripts found ${DIM}(~/.claude/projects/)${RESET}\n"
    fi

    # Codex CLI - check if installed, then count transcripts
    if [ -d "$HOME/.codex" ]; then
        CODEX_INSTALLED=1
        if [ -d "$HOME/.codex/sessions" ]; then
            CODEX_TRANSCRIPTS=$(find "$HOME/.codex/sessions" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        fi
    fi
    if [ "$CODEX_TRANSCRIPTS" -gt 0 ]; then
        printf "     ${CHECK} Codex: transcripts found\n"
    else
        printf "     ${CROSS} Codex: no transcripts found ${DIM}(~/.codex/sessions/)${RESET}\n"
    fi

    # Set global flags
    if [ "$CLAUDE_INSTALLED" -eq 1 ] || [ "$CODEX_INSTALLED" -eq 1 ]; then
        HAS_PROVIDER=1
    fi
    if [ "$CLAUDE_TRANSCRIPTS" -gt 0 ] || [ "$CODEX_TRANSCRIPTS" -gt 0 ]; then
        HAS_TRANSCRIPTS=1
    fi
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

    # macOS: native DMG install (Finder drag-drop)
    if [ "$OS" = "Darwin" ]; then
        detect_version
        install_macos_dmg
        exit 0
    fi

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
    # (silently skip if neither available - user will run ingest manually)
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

    # Check for transcripts (sets HAS_TRANSCRIPTS and HAS_PROVIDER)
    check_transcripts

    # Execute based on flags (set by args or prompts)
    if [ "$INSTALL_SERVICE" -eq 1 ]; then
        try_install_service
    fi
    if [ "$INSTALL_CRON" -eq 1 ]; then
        try_install_cron
    fi

    # Auto-ingest if transcripts found (unless --no-ingest)
    if [ "$HAS_TRANSCRIPTS" -eq 1 ] && [ "$SKIP_INGEST" -eq 0 ]; then
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
            --no-ingest) SKIP_INGEST=1 ;;
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
        Darwin) ;;  # supported via DMG flow
        *)
            echo "Error: Unsupported operating system: $OS"
            echo "This installer supports Linux and macOS."
            exit 1
            ;;
    esac
}

install_macos_dmg() {
    echo ""
    printf "${BOLD}Installing Contextify v$VERSION (macOS)${RESET}\n"

    DMG_NAME="Contextify-${VERSION}.dmg"
    DMG_URL="https://github.com/$REPO/releases/download/v${VERSION}/${DMG_NAME}"

    # Create a temp directory for the DMG
    TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t contextify.XXXXXX)
    DMG_PATH="$TMPDIR/$DMG_NAME"

    printf "  ${ARROW} Downloading DMG...\n"
    if ! curl -fsSL "$DMG_URL" -o "$DMG_PATH"; then
        printf "${RED}Error:${RESET} Failed to download:\n"
        printf "  %s\n" "$DMG_URL"
        exit 1
    fi

    printf "  ${ARROW} Mounting DMG...\n"
    set +e
    ATTACH_OUTPUT=$(hdiutil attach -nobrowse -noautoopen "$DMG_PATH" 2>&1)
    ATTACH_STATUS=$?
    set -e
    if [ "$ATTACH_STATUS" -ne 0 ]; then
        printf "${RED}Error:${RESET} Failed to mount DMG.\n"
        printf "${DIM}%s${RESET}\n" "$ATTACH_OUTPUT"
        exit 1
    fi

    # Extract mount point from hdiutil output (handles spaces in volume names)
    MOUNT_POINT=$(printf "%s\n" "$ATTACH_OUTPUT" | awk 'match($0,/\/Volumes\/.*/){print substr($0,RSTART,RLENGTH); exit}')
    if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
        printf "${RED}Error:${RESET} Could not determine DMG mount point.\n"
        printf "${DIM}%s${RESET}\n" "$ATTACH_OUTPUT"
        exit 1
    fi

    # Leave DMG + tmpdir in place so the mounted volume remains usable
    KEEP_TMPDIR=1

    echo ""
    printf "${CHECK} DMG mounted at: ${BOLD}%s${RESET}\n" "$MOUNT_POINT"

    # Open in Finder (print manual command if it fails in headless env)
    if command -v open >/dev/null 2>&1; then
        if ! open "$MOUNT_POINT" >/dev/null 2>&1; then
            printf "${YELLOW}Note:${RESET} Could not open Finder automatically.\n"
            printf "  Open manually: open \"%s\"\n" "$MOUNT_POINT"
        fi
    else
        printf "  Open manually: open \"%s\"\n" "$MOUNT_POINT"
    fi

    echo ""
    printf "${BOLD}Next steps:${RESET}\n"
    printf "  1) Drag ${BOLD}Contextify.app${RESET} into ${BOLD}Applications${RESET}\n"
    printf "  2) Eject the disk image when done\n"
    printf "     Finder: click the eject icon next to \"Contextify\"\n"
    printf "     Or run: ${BOLD}hdiutil detach \"%s\"${RESET}\n" "$MOUNT_POINT"
    echo ""
    printf "${DIM}(After ejecting, you may delete: %s)${RESET}\n" "$DMG_PATH"
    echo ""
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
        # Show result for each provider
        if [ -d "$HOME/.claude/skills/total-recall" ]; then
            printf "     ${CHECK} Claude Code ${DIM}(~/.claude/skills/total-recall)${RESET}\n"
        else
            printf "     ${CROSS} Claude Code ${DIM}(~/.claude/skills/total-recall)${RESET}\n"
        fi
        if [ -d "$HOME/.codex/skills/total-recall" ]; then
            printf "     ${CHECK} Codex ${DIM}(~/.codex/skills/total-recall)${RESET}\n"
        else
            printf "     ${CROSS} Codex ${DIM}(~/.codex/skills/total-recall)${RESET}\n"
        fi
    else
        printf "  ${YELLOW}(skipped)${RESET}\n"
    fi
}

try_install_service() {
    printf "  ${ARROW} Enabling background ingestion (systemd)...\n"
    if "$INSTALL_DIR/contextify" install-service >/dev/null 2>&1; then
        printf "     ${DIM}Timer: contextify-ingest.timer${RESET}\n"
        printf "     ${DIM}Check: systemctl --user status contextify-ingest.timer${RESET}\n"
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
    printf "  ${ARROW} Indexing your transcripts...\n"
    printf "     ${DIM}(one-time database setup)${RESET}\n"

    START_TIME=$(date +%s)
    PROGRESS_FILE="$(mktemp /tmp/contextify-ingest-progress.XXXXXX)"
    LOG_FILE="$(mktemp /tmp/contextify-ingest.XXXXXX.log)"
    export CONTEXTIFY_INGEST_PROGRESS_FILE="$PROGRESS_FILE"

    "$INSTALL_DIR/contextify" ingest --quiet >"$LOG_FILE" 2>&1 &
    INGEST_PID=$!

    # Forward signals to ingest process (prevents orphaned DB locks)
    # Escalation ladder: INT -> TERM (2s) -> KILL (5s)
    # NOTE: Do NOT wait inside the trap (double-reap bug + set -e abort)
    CANCELLED=0
    trap '
        CANCELLED=1
        kill -INT "$INGEST_PID" 2>/dev/null || true
        (
          sleep 2
          kill -0 "$INGEST_PID" 2>/dev/null && kill -TERM "$INGEST_PID" 2>/dev/null || true
          sleep 3
          kill -0 "$INGEST_PID" 2>/dev/null && kill -9 "$INGEST_PID" 2>/dev/null || true
        ) &
    ' INT TERM

    # Progress display loop
    while kill -0 "$INGEST_PID" 2>/dev/null; do
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ "$ELAPSED" -ge 60 ]; then
            TIME_STR="$((ELAPSED / 60))m $((ELAPSED % 60))s"
        else
            TIME_STR="${ELAPSED}s"
        fi
        PROGRESS=""
        IFS= read -r PROGRESS < "$PROGRESS_FILE" 2>/dev/null || true
        if [ -n "$PROGRESS" ]; then
            case "$PROGRESS" in
                done:*) printf "\r     ${DIM}Finalizing... (${TIME_STR})${RESET}          "; break ;;
                *) printf "\r     ${DIM}Indexing ${PROGRESS} transcripts (${TIME_STR})${RESET}          " ;;
            esac
        else
            printf "\r     ${DIM}Indexing... (${TIME_STR})${RESET}          "
        fi
        sleep 0.5
    done

    # Guard wait: set -e would abort on non-zero exit (130/143 from signals)
    set +e
    wait "$INGEST_PID"
    INGEST_STATUS=$?
    set -e

    # Clear the progress line (after wait so "Finalizing..." stays visible)
    printf "\r                                                    \r"

    # Restore top-level signal handler (trap - would remove cleanup entirely)
    trap cleanup INT TERM
    unset CONTEXTIFY_INGEST_PROGRESS_FILE

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    # Handle exit codes (CANCELLED flag takes priority)
    if [ "$CANCELLED" -eq 1 ] || [ "$INGEST_STATUS" -eq 130 ] || [ "$INGEST_STATUS" -eq 143 ]; then
        printf "  ${YELLOW}Cancelled indexing. Contextify is installed.${RESET}\n"
        printf "     ${DIM}Run 'contextify ingest' later to finish indexing.${RESET}\n"
    elif [ "$INGEST_STATUS" -eq 0 ]; then
        # Read final count from progress file (CLI leaves it for us)
        FINAL=""
        IFS= read -r FINAL < "$PROGRESS_FILE" 2>/dev/null || true
        case "$FINAL" in
            done:*)
                COUNT="${FINAL#done:}"
                if [ "$ELAPSED" -gt 5 ]; then
                    printf "  ${CHECK} ${COUNT} transcripts indexed ${DIM}(${ELAPSED}s)${RESET}\n"
                else
                    printf "  ${CHECK} ${COUNT} transcripts indexed\n"
                fi
                ;;
            *)
                if [ "$ELAPSED" -gt 60 ]; then
                    MINS=$((ELAPSED / 60))
                    SECS=$((ELAPSED % 60))
                    printf "  ${CHECK} Transcripts indexed ${DIM}(${MINS}m ${SECS}s)${RESET}\n"
                elif [ "$ELAPSED" -gt 5 ]; then
                    printf "  ${CHECK} Transcripts indexed ${DIM}(${ELAPSED}s)${RESET}\n"
                else
                    printf "  ${CHECK} Transcripts indexed\n"
                fi
                ;;
        esac
    else
        printf "  ${YELLOW}Indexing had issues:${RESET}\n"
        tail -n 10 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
            printf "     ${DIM}%s${RESET}\n" "$line"
        done
        printf "     ${DIM}Full log: $LOG_FILE${RESET}\n"
        printf "     ${DIM}Run 'contextify ingest' manually to retry.${RESET}\n"
    fi

    # Installer owns progress file cleanup
    rm -f "$PROGRESS_FILE"
    # Keep log file on error, clean on success/cancel
    if [ "$INGEST_STATUS" -eq 0 ] || [ "$CANCELLED" -eq 1 ]; then
        rm -f "$LOG_FILE"
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

    STEP=1

    # If no provider installed, tell user to install one first
    if [ "$HAS_PROVIDER" -eq 0 ]; then
        printf "  ${STEP}. Install Claude Code or Codex\n"
        STEP=$((STEP + 1))
        printf "  ${STEP}. Have some conversations to generate transcripts\n"
        STEP=$((STEP + 1))
        printf "  ${STEP}. Index your transcripts: ${BOLD}contextify ingest${RESET}\n"
        STEP=$((STEP + 1))
    elif [ "$HAS_TRANSCRIPTS" -eq 0 ]; then
        # Provider installed but no transcripts yet
        printf "  ${STEP}. Use Claude Code or Codex to have some conversations\n"
        STEP=$((STEP + 1))
        printf "  ${STEP}. Index your transcripts: ${BOLD}contextify ingest${RESET}\n"
        STEP=$((STEP + 1))
    fi
    # If transcripts existed, we already auto-ingested them - no need to mention ingest

    # Recommend setting up automatic ingestion if not already done
    if [ "$INSTALL_SERVICE" -eq 0 ] && [ "$INSTALL_CRON" -eq 0 ]; then
        if has_systemd_user || has_cron; then
            printf "  ${STEP}. Set up automatic ingestion: ${BOLD}contextify install-service${RESET}\n"
            printf "     ${DIM}(Runs ingest periodically in the background via systemd/cron)${RESET}\n"
            STEP=$((STEP + 1))
        fi
    fi

    printf "  ${STEP}. Search with Total Recall:\n"
    echo "     In Claude Code or Codex, run: /total-recall \"what did we decide about...\""
    echo ""

    printf "Docs: ${CYAN}https://contextify.sh/docs/${RESET}\n"

    # Thank you and contact - two blank lines after for spacing from next prompt
    echo ""
    printf "Thanks for installing! Questions or feedback: ${CYAN}rob@contextify.sh${RESET}\n"
    echo ""
    echo ""
}

main "$@"
