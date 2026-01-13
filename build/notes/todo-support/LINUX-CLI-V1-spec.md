---
todo_id: LINUX-CLI-V1
title: Linux CLI v1 - Complete Release Specification
type: spec
date: 2026-01-12
status: draft
description: Comprehensive spec for Linux CLI v1 release - from Beta to production-ready
---

# Linux CLI v1 - Complete Release Specification

## Executive Summary

### Where We Are

Contextify has working Linux binaries (`contextify-ingest` and `contextify-query`) that successfully:
- Ingest Claude Code and Codex CLI transcripts into a searchable SQLite database
- Provide the Total Recall skill for searching past conversations
- Support the contextify-researcher agent for complex multi-query searches

The core functionality works. We're near a release. The binaries build in CI, the database schema is stable, and the skill integration is solid.

### The Problem

Upon closer inspection, what we have is a macOS CLI that happens to compile on Linux - not a Linux-native tool. A Linux user downloading this today would encounter:
- Manual tarball extraction with no install script
- No automatic ingestion (must remember to run it manually)
- Data stored in macOS-style paths instead of XDG-compliant locations
- Missing quality-of-life features Linux users expect (completions, proper exit codes, quiet mode)

This is why we labeled it "Beta" on the landing page. It works, but it doesn't feel like a product made by someone who uses Linux.

### What This Spec Covers

This document defines everything needed to ship a v1 that Linux users would recognize as first-class support - not an afterthought port. The goal is to remove the Beta label and ship something we'd be proud to have Linux developers use daily.

**Scope:** ~15-20 hours of implementation work.

---

## Linux Compatibility Baseline

**This section is critical.** A binary that doesn't run out of the box is a "mass-close" moment.

### Target Platforms

| Distribution | Minimum Version | glibc | Status |
|--------------|-----------------|-------|--------|
| Ubuntu | 22.04 LTS | 2.35 | Primary target |
| Debian | 12 (Bookworm) | 2.36 | Supported |
| Fedora | 38+ | 2.37 | Supported |
| Arch | Rolling | Latest | Supported |
| RHEL/Rocky | 9+ | 2.34 | Best effort* |

*RHEL/Rocky 9 has glibc 2.34, which is below our 2.35 floor. May work if no 2.35-specific symbols are used, but not guaranteed.

**Build strategy:** Build on Ubuntu 22.04 (glibc 2.35) to maximize compatibility. Binaries built on newer glibc won't run on older systems. Our glibc floor is **2.35**.

### Swift Runtime

**Decision:** Statically link Swift stdlib.

Swift binaries require the Swift runtime. Options:
1. **Static linking** (recommended) - Larger binary (~50MB), but works everywhere
2. **Dynamic linking** - Smaller binary, but requires Swift runtime installed
3. **Bundle libs** - Ship .so files alongside binary

For v1, we statically link to eliminate "library not found" issues. The binary size tradeoff is acceptable for a CLI tool.

**CI requirement:** GitHub Actions workflow must:
- Build on `ubuntu-22.04` runner (not `ubuntu-latest` which may be newer)
- Use `-static-stdlib` flag (or Swift's default static linking on Linux)
- Test binary execution on target before release

### Runtime Dependency Contract (Test-Based)

**Critical:** "Static Swift stdlib" doesn't mean "no runtime deps". Swift + Foundation can pull in ICU, curl, etc. We define the contract by **tests that must pass**, not a strict dependency list.

**Required tests (all must pass before release):**

```bash
# 1. Check glibc floor
objdump -T contextify | grep GLIBC | sort -V | tail -1
# Must show GLIBC_2.35 or lower

# 2. No Swift runtime .so files (these would require Swift installed)
ldd contextify | grep -E 'libswift|Swift'
# Must return empty (exit 1)

# 3. All subcommands run in minimal container
docker run --rm -v $(pwd):/app ubuntu:22.04 sh -c '
  /app/contextify --version &&
  /app/contextify ingest --help &&
  /app/contextify search --help &&
  /app/contextify status --help
'
# Must succeed WITHOUT installing additional packages

# 4. Older-than-target check (informational, NOT a gate)
docker run --rm -v $(pwd):/app ubuntu:20.04 /app/contextify --version
# Expected to FAIL due to glibc 2.31 < 2.35
# If it succeeds: that's fine (more compatible than promised)
# Do NOT fail CI if this passes - being more compatible is not harmful
```

**If ICU is required:** Swift + Foundation may pull in ICU for locale/regex/formatting. If the minimal container test fails due to ICU:
- Option A: Document ICU as a requirement (`apt install libicu70`)
- Option B: Statically link or bundle ICU (larger binary)
- Option C: Avoid ICU-dependent APIs in the code

**What we're really testing:** "A user with Ubuntu 22.04 minimal can download and run the binary without `apt install` anything."

**CI requirement:** Add these tests to the release workflow. Binary that fails any test does not ship.

---

## Current State Assessment

### What We Have

| Component | Status | Quality |
|-----------|--------|---------|
| `contextify-ingest` binary | Works | Basic |
| `contextify-query` binary | Works | Good |
| `install-skill` command | Works | Good |
| `doctor` command | Works | Good |
| GitHub releases (tarball) | Works | Basic |
| Basic CLI argument parsing | Works | Needs polish |

### What's Missing (Why It's Beta)

| Feature | Impact | Priority |
|---------|--------|----------|
| Install script (curl \| sh) | Users can't easily install | Must Have |
| systemd service setup | Manual cron = amateur hour | Must Have |
| XDG-compliant paths | Data in wrong places | Must Have |
| `--quiet` mode | Noisy in cron/systemd | Must Have |
| Proper exit codes | Scripts can't check success | Must Have |
| Shell completions | Tab completion expected | Should Have |
| Config file support | Power users need this | Should Have |
| `status` command | "What's indexed?" | Should Have |
| `--version` with build info | Basic hygiene | Should Have |
| Good `--help` text | Self-documenting | Should Have |

---

## Design

### 0. Unified Command Structure

**Decision:** Ship a single `contextify` command with subcommands instead of separate binaries.

**Rationale:** Two binaries (`contextify-ingest`, `contextify-query`) create documentation friction. Every instruction has to specify which binary. A unified command is much cleaner:

```bash
# Instead of:
contextify-ingest ingest --quiet
contextify-query search "authentication"
contextify-ingest install-service

# Ship:
contextify ingest --quiet
contextify search "authentication"
contextify install-service
```

**Command structure:**

```
contextify
├── ingest              # Index new transcripts
├── search              # Query past conversations (alias: query)
├── status              # Show database and service status
├── install-skill       # Install Total Recall skill
├── install-service     # Set up systemd timer
├── uninstall-service   # Remove systemd timer
├── service-status      # Check service status
├── migrate-db          # Move database to XDG location
├── doctor              # Diagnose issues
└── --version, --help   # Standard flags
```

**Updating:** Re-run the install script. No built-in update command needed for v1.
```bash
curl -fsSL https://contextify.sh/install.sh | sh
```

**Implementation options:**

1. **Single binary** (recommended) - One Swift executable with subcommands via Argument Parser
2. **Thin wrapper** - Shell script that dispatches to underlying binaries
3. **Symlinks** - `contextify` symlinks to `contextify-ingest`, detects invocation name

For v1, option 1 (single binary) is cleanest. The current `contextify-query` and `contextify-ingest` can be merged into one `contextify` binary.

**Migration from Beta:**
- Keep old binary names as symlinks for backwards compatibility
- **argv[0] dispatch:** When invoked as `contextify-ingest`, automatically route to `ingest` subcommand. When invoked as `contextify-query`, route to `search` subcommand. This preserves muscle memory and existing scripts.
- Remove old symlinks in v1.1

**Deprecation warnings (critical for not breaking scripts):**
```swift
// Deprecation warnings MUST:
// 1. Go to stderr (not stdout - stdout is for output that scripts parse)
// 2. Only show when STDERR is a TTY (not stdin - user might pipe input but still want warnings)
// 3. Be suppressible with CONTEXTIFY_NO_DEPRECATIONS=1

#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

func isStderrTTY() -> Bool {
    return isatty(STDERR_FILENO) != 0
}

func warnDeprecated(_ message: String) {
    // Gate on stderr TTY, not stdin - handles `echo foo | contextify` case
    guard isStderrTTY() ||
          ProcessInfo.processInfo.environment["CONTEXTIFY_SHOW_DEPRECATIONS"] == "1" else {
        return
    }
    guard ProcessInfo.processInfo.environment["CONTEXTIFY_NO_DEPRECATIONS"] != "1" else {
        return
    }
    fputs("Warning: \(message)\n", stderr)
}

// Usage when invoked via old binary name:
warnDeprecated("contextify-ingest is deprecated, use 'contextify ingest'")
```

**Why stderr TTY (not stdin):** With `echo foo | contextify`, stdin is not a TTY but the user is still in a terminal and might want warnings. Gate on stderr to detect "is a human looking at this."

**Why this matters:** If deprecation warnings go to stdout, they'll poison pipelines (`contextify-query ... | jq`) and break completion scripts. Linux users will be furious.

---

### 1. XDG Base Directory Compliance

**Specification:** [XDG Base Directory Spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)

**Required paths (v1 scope):**

```
$XDG_DATA_HOME/contextify/          # Default: ~/.local/share/contextify/
└── contextify.db                   # Main database (0600 permissions)

$XDG_CONFIG_HOME/contextify/        # Default: ~/.config/contextify/
└── config.toml                     # User configuration (0600 permissions)
```

**Deferred to v1.1:** `XDG_STATE_HOME` (logs) and `XDG_CACHE_HOME` (temp files). Not needed for core functionality.

### Security: File Permissions

**Critical:** Transcripts contain sensitive data (tokens, internal code, secrets). Permissive umask on shared machines = data leak.

| Path | Permissions | Rationale |
|------|-------------|-----------|
| `~/.local/share/contextify/` | `0700` | Directory not world-readable |
| `contextify.db` | `0600` | Database contains conversation history |
| `~/.config/contextify/` | `0700` | Config may contain paths to sensitive data |
| `config.toml` | `0600` | May contain custom paths |

**Implementation:** Always set permissions explicitly, don't rely on umask. Tighten existing insecure files/dirs, but **warn and continue** if chmod fails (NFS, weird mounts, corporate lockdown).

```swift
/// Ensure directory exists with secure permissions (0700)
/// Tightens existing insecure perms; warns but continues on chmod failure
public static func ensureSecureDirectory(_ url: URL) {
    let fm = FileManager.default
    var isDir: ObjCBool = false

    do {
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                // Check current permissions
                let attrs = try fm.attributesOfItem(atPath: url.path)
                if let perms = attrs[.posixPermissions] as? Int, perms & 0o077 != 0 {
                    // Directory is world/group accessible - try to tighten
                    fputs("Warning: Attempting to tighten permissions on \(url.path) (was \(String(perms, radix: 8)))\n", stderr)
                    do {
                        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                    } catch {
                        // chmod failed (NFS, weird mount, corporate lockdown)
                        fputs("Warning: Could not tighten permissions on \(url.path): \(error.localizedDescription)\n", stderr)
                        fputs("Warning: Directory may be accessible to other users\n", stderr)
                        // Continue anyway - don't block the user
                    }
                }
            } else {
                fputs("Error: \(url.path) exists but is not a directory\n", stderr)
                // This IS fatal - can't continue with wrong path type
                exit(1)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    } catch {
        // Creation failure IS fatal if we need to write data
        fputs("Error: Could not create \(url.path): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

/// Set secure file permissions (0600), tightening if needed
/// Warns but continues on chmod failure
public static func setSecureFilePermissions(_ url: URL) {
    let fm = FileManager.default
    do {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        if let perms = attrs[.posixPermissions] as? Int, perms & 0o077 != 0 {
            fputs("Warning: Attempting to tighten permissions on \(url.path) (was \(String(perms, radix: 8)))\n", stderr)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
        fputs("Warning: Could not set permissions on \(url.path): \(error.localizedDescription)\n", stderr)
        fputs("Warning: File may be accessible to other users\n", stderr)
        // Continue - file was written, just not with ideal perms
    }
}
```

**Failure modes:**
- Directory creation fails → **Fatal** (can't proceed without storage)
- Path exists but is file not dir → **Fatal** (configuration error)
- chmod fails on existing dir → **Warn and continue** (NFS, corporate lockdown)
- chmod fails on new file → **Warn and continue** (data was written)

**Additional security note:** Keep `--systemd` output minimal. Never log transcript content, file paths, or anything that could leak sensitive data into journald. The summary line should only show counts:
```
Ingested 3 entries from 2 transcripts (0 errors)
```

### XDG Implementation

Both `contextify-ingest` and `contextify-query` share a common `XDGPaths` module in `ContextifyIngestionCore`. This ensures both binaries resolve paths identically.

```swift
// Sources/ContextifyIngestionCore/XDGPaths.swift
// Shared by both contextify-ingest and contextify-query

public struct XDGPaths {
    /// Validates XDG path is absolute. Returns fallback with warning if relative.
    private static func validatedXDGPath(_ envVar: String, fallback: URL) -> URL {
        guard let xdg = ProcessInfo.processInfo.environment[envVar] else {
            return fallback
        }
        // XDG spec requires absolute paths
        guard xdg.hasPrefix("/") else {
            fputs("Warning: \(envVar)='\(xdg)' is not absolute, using default\n", stderr)
            return fallback
        }
        return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
    }

    public static var dataHome: URL {
        validatedXDGPath("XDG_DATA_HOME",
            fallback: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/contextify"))
    }

    public static var configHome: URL {
        validatedXDGPath("XDG_CONFIG_HOME",
            fallback: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/contextify"))
    }

    public static var databasePath: URL {
        // CONTEXTIFY_DB_PATH env var takes precedence (power user override)
        if let dbPath = ProcessInfo.processInfo.environment["CONTEXTIFY_DB_PATH"],
           dbPath.hasPrefix("/") {
            return URL(fileURLWithPath: dbPath)
        }
        return dataHome.appendingPathComponent("contextify.db")
    }

    public static var configPath: URL {
        configHome.appendingPathComponent("config.toml")
    }

    // Note: ensureSecureDirectory() and setSecureFilePermissions() helpers
    // are defined in the Security section above with warn-and-continue behavior.
    // Do not use simple throwing versions - chmod can fail on NFS/corporate lockdown.
}
```

**Precedence order (standard Linux convention):**
1. `--db` flag - CLI argument (highest priority)
2. `CONTEXTIFY_DB_PATH` - Environment variable
3. Config file `database.path` - User configuration
4. `XDG_DATA_HOME/contextify/contextify.db` - XDG compliant default
5. `~/.local/share/contextify/contextify.db` - Fallback default

**Migration behavior:**

When database doesn't exist at XDG location, check for legacy locations:
1. `~/.contextify/contextify.db` (hypothetical old path)
2. `~/Library/Application Support/Contextify/contextify.db` (macOS path, if somehow present)

**Key principle:** Never prompt unless **both stdin AND stderr are TTYs**. Write prompts to stderr. Otherwise require `--yes` flag.

**Default behavior (non-interactive):**
- Use existing database in-place (don't move it)
- Log a warning: `Using legacy database location: ~/.contextify/contextify.db`
- Suggest: `Run 'contextify migrate-db' to move to XDG location`

**Explicit migration command (v1):**
```bash
contextify migrate-db [--from PATH] [--to PATH] [--delete-old] [--dry-run] [--yes]
```

**Flags:**
- `--from PATH` - Source database (default: auto-detect legacy location)
- `--to PATH` - Destination (default: XDG location)
- `--delete-old` - Remove old database after successful migration
- `--dry-run` - Show what would happen without making changes
- `--yes` - Skip confirmation prompt (required in non-interactive mode)

**Concurrency-safe migration steps:**

**Critical:** Simple file copy of SQLite while another process might write is unsafe. Can produce corrupt or inconsistent copy. Must use SQLite's safe mechanisms.

1. Find legacy database (or use `--from`)
2. Confirm destination (or use `--to`)
3. **Only prompt if both stdin AND stderr are TTYs** - otherwise require `--yes` flag
4. **Stop systemd timer if running:**
   ```bash
   systemctl --user stop contextify.timer 2>/dev/null || true
   ```
5. Create target directory with `0700` permissions
6. **Safe copy using SQLite backup API:**
   ```swift
   // Use GRDB's backup or raw sqlite3_backup_* API
   let source = try DatabaseQueue(path: sourcePath)
   let dest = try DatabaseQueue(path: destPath)
   try source.backup(to: dest)
   ```
   Alternative: `VACUUM INTO` if SQLite version supports it (3.27+)
7. Set `0600` permissions on new file
8. **Verify:** Open new DB, check schema version, run sanity query
9. If verification fails: delete the new copy, report error, **re-enable timer**, exit 1
10. If verification passes: print success message
11. **Re-enable timer:**
    ```bash
    systemctl --user start contextify.timer 2>/dev/null || true
    ```
12. If `--delete-old`: remove source database

**Why SQLite backup API:** A file copy during concurrent writes can produce subtly inconsistent state that passes basic verification but loses recent writes. SQLite's backup API handles this safely.

**Success output:**
```
Migration complete.
  New database: ~/.local/share/contextify/contextify.db (42.3 MB)
  Verified: schema v33, 12 projects, 156 transcripts
  Old database: ~/.contextify/contextify.db (retained)

To remove old database: contextify migrate-db --delete-old
```

**Post-migration behavior:**
After successful migration, the XDG location becomes the default. The system does NOT "sometimes choose legacy" based on existence. If both exist, XDG wins unless explicitly overridden with `--db` or `CONTEXTIFY_DB_PATH`.

**Why this approach:**
- Scripts and systemd services never see surprise prompts
- Transactional: verification ensures no corrupted migrations
- Copy-not-move by default preserves rollback option
- `--delete-old` available for cleanup when ready

---

### 2. Install Script

**URL:** `https://contextify.sh/install.sh`

**Usage:**
```bash
# Standard (non-interactive, prints next steps)
curl -fsSL https://contextify.sh/install.sh | sh

# With flags (use sh -s --)
curl -fsSL https://contextify.sh/install.sh | sh -s -- --no-skill

# Alternative that preserves TTY (if interactive features added later)
sh -c "$(curl -fsSL https://contextify.sh/install.sh)"
```

**Critical:** The script is **fully non-interactive by default**. With `curl | sh`, stdin is the script itself, so `read`-based prompting is broken. Don't add prompts without explicit `/dev/tty` handling.

**Release artifact contract:** The tarball MUST extract files directly into the target directory (no top-level subdirectory). Contents:
```
contextify           # Main binary (executable)
contextify-ingest    # Symlink → contextify (backwards compatibility)
contextify-query     # Symlink → contextify (backwards compatibility)
```
This contract is enforced by the installer's `tar -C $INSTALL_DIR` extraction. If the tarball layout changes (e.g., adds a subdirectory), the installer will break.

**Script behavior:**

1. Detect architecture (`uname -m` → x86_64 or aarch64)
2. Detect latest version (from `VERSION` env var, or GitHub API, or fallback URL)
3. Download appropriate tarball (fail hard on HTTP errors)
4. **Verify SHA256 checksum** (download `.sha256` file, fail on mismatch or missing)
5. Extract to `$INSTALL_DIR` (default: `~/.local/bin/`)
6. Verify binary executes (`contextify --version`)
7. Run `contextify install-skill` (skip with `--no-skill`)
8. Print success message with clear next steps (no prompts)

**Environment variables:**
- `VERSION` - Skip API call, use this version
- `INSTALL_DIR` - Install location (default: `~/.local/bin`)

**Flags (via `sh -s --`):**
- `--no-skill` - Skip skill installation
- `--help` - Show usage

**Script template:**

```bash
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
```

**Hosting:** Deploy to `website/install.sh`, rsync with website.

---

### 3. systemd Service Setup

**Commands:**

```bash
contextify install-service [--interval 15min]
contextify uninstall-service
contextify service-status
```

**Interval format:** Use systemd time span format (e.g., `15min`, `1h`, `30s`). See `man systemd.time`.

**Service file:** `~/.config/systemd/user/contextify.service`
```ini
[Unit]
Description=Contextify transcript ingestion
Documentation=https://contextify.sh/docs/

[Service]
Type=oneshot
# BINARY_PATH and DB_PATH are replaced at install time with actual absolute paths
# e.g., BINARY_PATH=/home/user/.local/bin/contextify
#       DB_PATH=/home/user/.local/share/contextify/contextify.db
ExecStart=BINARY_PATH ingest --systemd --db DB_PATH
# Exit code 2 = "nothing to do" (not an error)
SuccessExitStatus=2
StandardOutput=journal
StandardError=journal
# Note: We embed --db explicitly because systemd user units do NOT inherit shell environment.
# Without this, $CONTEXTIFY_DB_PATH or $XDG_DATA_HOME overrides would be ignored.
```

**Note on paths:** The `install-service` command resolves both the binary location AND the database path at install time using the same resolution logic as interactive commands (flags/env/config/defaults). This prevents "split-brain" scenarios where the timer writes to a different database than the user's interactive shell.

**Critical:** systemd user units do NOT inherit your interactive shell environment. If a user has `CONTEXTIFY_DB_PATH` set in `.bashrc`, systemd won't see it. By embedding `--db /absolute/path` at install time, we make behavior deterministic.

If users change their DB location, they must re-run `contextify install-service` to update the unit.

**Important:** No `[Install]` section on the service. For timer-driven oneshots, only the timer needs an Install section.

**Note on --systemd flag:** This is similar to `--quiet` but still logs a summary line to stdout for journald:
```
Ingested 3 entries from 2 transcripts (0 errors)
```
This ensures `journalctl --user -u contextify` shows meaningful output.

**Note on exit code 2:** systemd treats non-zero exit as failure by default. The `SuccessExitStatus=2` directive tells systemd that exit code 2 ("nothing to do") is a success, not a failure. Without this, users would see constant "failed" runs in `systemctl --user status`.

**Timer file:** `~/.config/systemd/user/contextify.timer`
```ini
[Unit]
Description=Run Contextify ingestion periodically
Documentation=https://contextify.sh/docs/

[Timer]
OnBootSec=2min
OnUnitActiveSec=INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
```

**install-service implementation:**

1. **Detect binary location:** Use `which contextify` or `readlink -f "$0"`
2. **Check systemd user session availability:**
   ```bash
   # Try to connect to user bus
   if ! systemctl --user status >/dev/null 2>&1; then
       ERROR=$(systemctl --user status 2>&1)
       # Parse actual error for specific guidance
   fi
   ```

   **Error-specific guidance:**

   | Error | Likely cause | Guidance |
   |-------|--------------|----------|
   | "Failed to connect to bus" | No user session | `loginctl enable-linger $USER` (may need sudo on some distros) |
   | "No such file or directory" | systemd not running | WSL1, container, or non-systemd distro |
   | Other | Misconfigured | Show raw error, suggest manual debug |

   **Fallback message:**
   ```
   systemd user session not available.
   Error: {actual error message}

   Possible fixes:
     1. Enable user lingering (may require sudo):
        sudo loginctl enable-linger $USER

     2. If on WSL, enable systemd:
        # Edit /etc/wsl.conf, add [boot] systemd=true, restart WSL

     3. Use cron instead (if available):
        crontab -e
        Add: */15 * * * * /path/to/contextify ingest --quiet

     4. Run manually when needed:
        contextify ingest
   ```

   **Cron fallback check:**
   ```bash
   if ! command -v crontab >/dev/null 2>&1; then
       echo "Note: cron is not installed. Install cronie/vixie-cron for scheduled runs."
   fi
   ```

3. Create `~/.config/systemd/user/` if needed (with 0700 permissions)
4. Write service file with binary path from step 1
   - Use absolute path resolved at install time
   - If user upgrades to new location, re-run `install-service` to update
5. Write timer file with configured interval
6. Run `systemctl --user daemon-reload`
7. Run `systemctl --user enable --now contextify.timer`
8. Print status and next-run time

**Upgrade handling:** If service already exists, `install-service` overwrites the unit files with current binary path. This handles the "user moved binary" case.

**service-status output:**
```
Contextify Ingestion Service
============================
Status: active (waiting)
Timer: contextify.timer
Next run: 2026-01-12 22:15:00 PST (in 12 minutes)
Last run: 2026-01-12 22:00:00 PST (success)

Recent logs (last 5 runs):
  Jan 12 22:00:00 - Ingested 3 new entries
  Jan 12 21:45:00 - No new transcripts
  Jan 12 21:30:00 - Ingested 15 new entries

View full logs: journalctl --user -u contextify
```

**Fallback for non-systemd:**
```
systemd not detected. To run ingestion periodically, add to crontab:

  crontab -e

Then add:
  */15 * * * * ~/.local/bin/contextify ingest --quiet
```

---

### 4. CLI Polish

#### Exit Codes

| Code | Meaning | When |
|------|---------|------|
| 0 | Success | Operation completed |
| 1 | Error | Something failed |
| 2 | No-op | Nothing to do (useful for scripts) |

```swift
enum ExitCode: Int32 {
    case success = 0
    case error = 1
    case noop = 2  // e.g., "ingest" with no new transcripts
}
```

#### Quiet Mode

```bash
contextify ingest --quiet  # Only errors to stderr
contextify ingest -q       # Short form
```

Suppress:
- Progress messages
- "Ingested N entries" success messages
- Informational output

Keep:
- Errors (to stderr)
- Warnings (to stderr)

#### Verbose Mode

```bash
contextify ingest --verbose  # Debug output
contextify ingest -v         # Short form
```

#### Version Output

```bash
$ contextify --version
contextify 1.1.0 (abc1234)
  Built: 2026-01-12
  Swift: 6.0
  Platform: linux-x86_64
```

Implementation: Embed git commit hash and build date at compile time.

#### Help Text Quality

Each command should have:
- One-line description
- Usage example
- All options documented
- Related commands mentioned

```bash
$ contextify --help
Contextify CLI - Search your AI coding conversations

USAGE: contextify <command> [options]

COMMANDS:
  ingest            Index new transcripts into the database
  search            Search past conversations
  status            Show database and service status
  install-skill     Install Total Recall skill for Claude/Codex
  install-service   Set up automatic background ingestion
  uninstall-service Remove background ingestion service
  service-status    Check background service status
  migrate-db        Move database to XDG-compliant location
  doctor            Diagnose common issues

OPTIONS:
  --db <path>       Database location (default: ~/.local/share/contextify/contextify.db)
  --quiet, -q       Suppress non-error output
  --verbose, -v     Enable debug output
  --version         Show version information
  --help, -h        Show this help

EXAMPLES:
  contextify ingest                    # Index new transcripts
  contextify ingest --quiet            # Silent mode for cron/systemd
  contextify search "authentication"   # Search conversations
  contextify status                    # What's indexed?
  contextify install-service           # Set up auto-ingestion

DOCUMENTATION: https://contextify.sh/docs/
```

---

### 5. Status Command

```bash
$ contextify status
Contextify Database Status
==========================
Database: ~/.local/share/contextify/contextify.db
Size: 42.3 MB
Schema: v33

Indexed Content:
  Projects: 12
  Transcripts: 156
  Entries: 4,892

Providers:
  Claude Code: 134 transcripts (last: 2 hours ago)
  Codex CLI: 22 transcripts (last: 3 days ago)

Background Service: active (next run in 8 minutes)

Last ingestion: 2026-01-12 21:45:00 (3 new entries)
```

**JSON output:**
```bash
$ contextify status --json
{
  "format_version": 1,
  "cli_version": "1.1.0",
  "database": {
    "path": "/home/user/.local/share/contextify/contextify.db",
    "size_bytes": 44347392,
    "schema_version": 33
  },
  "stats": {
    "projects": 12,
    "transcripts": 156,
    "entries": 4892
  },
  "providers": {
    "claude": { "transcripts": 134, "last_activity": "2026-01-12T19:45:00Z" },
    "codex": { "transcripts": 22, "last_activity": "2026-01-09T14:30:00Z" }
  },
  "service": {
    "active": true,
    "next_run": "2026-01-12T22:00:00Z"
  }
}
```

**Note:** `format_version` allows future changes to the JSON schema without breaking existing parsers. Increment when adding/removing fields.

---

### 6. Shell Completions

Swift Argument Parser can generate completions automatically.

**Installation commands:**
```bash
# Bash
contextify --generate-completion-script bash > ~/.local/share/bash-completion/completions/contextify

# Zsh
contextify --generate-completion-script zsh > ~/.zfunc/_contextify

# Fish
contextify --generate-completion-script fish > ~/.config/fish/completions/contextify.fish
```

**v1 approach:** Install script prints these instructions. Automatic completion installation deferred to v1.1 (see Future Considerations).

---

### 7. Config File (Optional)

**Location:** `$XDG_CONFIG_HOME/contextify/config.toml` (default: `~/.config/contextify/config.toml`)

```toml
# Contextify Configuration

[database]
# path = "~/.local/share/contextify/contextify.db"  # Default

[ingestion]
interval = "15min"    # Service timer interval (systemd time span format)
quiet = true          # Suppress output in background runs

[providers]
claude_path = "~/.claude/projects"
codex_path = "~/.codex/sessions"

# Future: custom provider paths, exclusions, etc.
```

**Precedence:** CLI flags > Environment variables > Config file > Defaults

**Path expansion rules:**
- `~` expands to `$HOME`
- `$VAR` or `${VAR}` expands to environment variable
- Relative paths are relative to current working directory (not recommended)
- Invalid paths (non-existent, not a directory) trigger a warning at startup, not an error

**Validation:**
- Unknown keys: warn but don't fail (forward compatibility)
- Invalid interval format: error with example of valid formats
- Invalid path: warn at startup, skip that provider

**Example error output:**
```
Config error in ~/.config/contextify/config.toml:
  [ingestion] interval = "15" is invalid
  Expected systemd time span format, e.g., "15min", "1h", "30s"
```

**Implementation:** Use a simple TOML parser or hand-roll for minimal dependencies.

---

## Implementation Plan

### Phase 0: Unified Command Structure (2-3 hours)

0. **Merge binaries into single `contextify` command** (2-3 hr)
   - Restructure Package.swift to produce single `contextify` binary
   - Create subcommand structure via Swift Argument Parser
   - Add backwards-compatible symlinks (`contextify-ingest`, `contextify-query`) with deprecation warnings
   - Update tarball build to include main binary + symlinks

### Phase 1: Foundation (5-7 hours)

1. **XDG paths + secure permissions** (1.5 hr)
   - Create `XDGPaths` helper with validation (absolute paths only)
   - Add `CONTEXTIFY_DB_PATH` env var support
   - Ensure directories created with 0700, files with 0600
   - Update database default location

2. **migrate-db command** (1 hr)
   - Find legacy databases
   - Copy (not move) to XDG location
   - Only prompt if both stdin AND stderr are TTYs, else require `--yes`
   - Print verification steps

3. **Exit codes + quiet mode** (1 hr)
   - Define `ExitCode` enum (0=success, 1=error, 2=noop)
   - Add `--quiet` and `--systemd` flags
   - Ensure all commands return appropriate codes

4. **Version info** (30 min)
   - Embed git hash at build time
   - Format version output properly

5. **Help text audit** (1 hr)
   - Review all command help strings
   - Add examples where missing
   - Ensure consistency

6. **Status command** (1.5 hr)
   - Query database for stats
   - Format human-readable output
   - Add `--json` flag with `format_version`

### Phase 2: Service Setup (3-4 hours)

7. **install-service command** (1.5 hr)
   - Detect systemd with proper error handling
   - Generate service + timer files (with SuccessExitStatus=2)
   - Run systemctl commands
   - Provide specific guidance for common errors (WSL, linger, etc.)
   - Check for cron availability in fallback

8. **uninstall-service command** (30 min)
   - Stop and disable timer
   - Remove files
   - Confirm removal

9. **service-status command** (1 hr)
   - Query systemctl status
   - Parse next run time
   - Point to journalctl for logs (no log parsing in v1)

### Phase 3: Distribution (3-4 hours)

10. **Install script** (1.5 hr)
    - Write install.sh (non-interactive, with cleanup trap)
    - Test on Ubuntu 22.04, Fedora, Arch
    - Verify checksum handling, error messages
    - Deploy to website

11. **Shell completions** (30 min)
    - Verify Swift Argument Parser generates them
    - Document manual installation only (defer automation to v1.1)

12. **Documentation** (1 hr)
    - Update /docs/ page
    - Add troubleshooting section (glibc, permissions, systemd)
    - Update README

### Phase 4: Polish (2-3 hours)

13. **CI verification** (1 hr)
    - Confirm builds on ubuntu-22.04 runner
    - Verify static linking / glibc requirements
    - Add binary verification to release workflow

14. **Config file support** (1 hr) [Optional for v1]
    - TOML parsing
    - Merge with CLI flags and env vars

15. **Testing + QA** (1 hr)
    - Docker-based E2E test on target distro
    - Fresh install walkthrough
    - Verify all commands work

---

## Required CI/CD Infrastructure

The following must be added to the GitHub Actions release workflow **before v1 ships**.

### Automated Validation Tests

Add to `.github/workflows/linux-release.yml`:

```yaml
validate-linux-binary:
  needs: build
  runs-on: ubuntu-22.04
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: contextify-linux-x86_64

    - name: Verify glibc floor (<= 2.35)
      run: |
        MAX=$(objdump -T contextify | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1 || true)
        if [ -z "$MAX" ]; then
          echo "FAIL: could not determine glibc requirement (missing objdump/binutils or unexpected binary format)"
          exit 1
        fi
        echo "Max glibc required: $MAX"
        if [ "$(printf '%s\n' "$MAX" "GLIBC_2.35" | sort -V | tail -1)" != "GLIBC_2.35" ]; then
          echo "FAIL: binary requires $MAX (must be <= GLIBC_2.35)"
          exit 1
        fi
        echo "OK: glibc requirement is within bounds"

    - name: Verify no Swift runtime deps
      run: |
        ldd contextify | grep -E 'libswift|Swift' && exit 1 || echo "No Swift runtime deps"

    - name: Test in ubuntu:22.04 minimal
      run: |
        docker run --rm -v $(pwd):/app ubuntu:22.04 sh -c '
          /app/contextify --version &&
          /app/contextify ingest --help &&
          /app/contextify search --help &&
          /app/contextify status --help
        '

    - name: Check ubuntu:20.04 compatibility (informational)
      continue-on-error: true  # Do NOT fail CI if this passes
      run: |
        if docker run --rm -v $(pwd):/app ubuntu:20.04 /app/contextify --version 2>&1; then
          echo "INFO: Binary works on ubuntu:20.04 (more compatible than required)"
        else
          echo "INFO: Binary requires glibc 2.35+ as expected"
        fi
```

### Multi-Distro Validation Matrix

Optional but recommended - add parallel jobs for:

| Distribution | Container Image | Purpose |
|--------------|-----------------|---------|
| Ubuntu 22.04 | `ubuntu:22.04` | Primary target, minimal |
| Debian 12 | `debian:12-slim` | Second major distro |
| Fedora 38 | `fedora:38` | RPM-based, newer glibc |
| Arch | `archlinux:latest` | Rolling release |

### Local Validation Script

Create `scripts/linux/validate-binary.sh` for local dev testing:

```bash
#!/bin/bash
set -e

BINARY="${1:-./contextify}"

echo "=== Linux Binary Validation ==="

# 1. glibc version (portable grep, no -P flag)
echo "Checking glibc requirement..."
GLIBC=$(objdump -T "$BINARY" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1 || true)
if [ -z "$GLIBC" ]; then
  echo "  FAIL: could not determine glibc requirement"
  exit 1
fi
echo "  Max required: $GLIBC"
if [ "$(printf '%s\n' "$GLIBC" "GLIBC_2.35" | sort -V | tail -1)" != "GLIBC_2.35" ]; then
  echo "  FAIL: binary requires $GLIBC (must be <= GLIBC_2.35)"
  exit 1
fi
echo "  OK: glibc requirement is within bounds"

# 2. Swift runtime
echo "Checking for Swift runtime deps..."
if ldd "$BINARY" | grep -qE 'libswift|Swift'; then
  echo "  FAIL: Found Swift runtime dependencies"
  exit 1
fi
echo "  OK: No Swift runtime deps"

# 3. Minimal container test
echo "Testing in ubuntu:22.04 minimal..."
docker run --rm -v "$(dirname "$BINARY"):/app" ubuntu:22.04 sh -c "
  /app/$(basename "$BINARY") --version &&
  /app/$(basename "$BINARY") ingest --help
"
echo "  OK: Runs in minimal container"

# 4. glibc floor check (informational)
echo "Checking ubuntu:20.04 compatibility (informational)..."
if docker run --rm -v "$(dirname "$BINARY"):/app" ubuntu:20.04 /app/$(basename "$BINARY") --version 2>/dev/null; then
  echo "  INFO: Works on ubuntu:20.04 (more compatible than required)"
else
  echo "  INFO: Requires glibc 2.35+ as expected"
fi

echo ""
echo "=== Validation Complete ==="
```

### Current State

**What exists:**
- GitHub Actions builds both x86_64 and arm64 on `swift:6.0-noble`
- Basic E2E test with fixture-based transcript ingestion
- Binary execution verification (`--help`, `--version`, `doctor`)

**What's missing (add before v1):**
- Minimal container validation tests
- glibc floor verification
- Multi-distro matrix
- Local validation script

---

## Validation Checklist

### Installation
- [ ] `curl -sSL contextify.sh/install.sh | sh` works on fresh Ubuntu
- [ ] `curl -sSL contextify.sh/install.sh | sh` works on fresh Fedora
- [ ] Binaries land in `~/.local/bin/`
- [ ] Skill is auto-installed
- [ ] Clear instructions printed

### XDG Compliance
- [ ] Database created in `~/.local/share/contextify/`
- [ ] Respects `$XDG_DATA_HOME` override
- [ ] No files created directly in `$HOME`

### Service Setup
- [ ] `install-service` creates valid systemd files
- [ ] Timer activates and runs on schedule
- [ ] `service-status` shows correct information
- [ ] `uninstall-service` cleanly removes everything
- [ ] Non-systemd fallback message is helpful

### CLI UX
- [ ] `--version` shows version, commit, platform
- [ ] `--help` is comprehensive and has examples
- [ ] `--quiet` suppresses all non-error output
- [ ] Exit code 0 on success, 1 on error, 2 on no-op
- [ ] `status` command shows useful information

### Shell Completions
- [ ] Tab completion works in bash
- [ ] Tab completion works in zsh
- [ ] Tab completion works in fish

### End-to-End
- [ ] Fresh user can go from zero to working in <5 minutes
- [ ] `/total-recall` works in Claude Code after install
- [ ] Automatic ingestion runs without intervention

---

## Files to Create/Modify

### New Files
- `website/install.sh` - Install script
- `Sources/ContextifyIngestionCLI/Commands/InstallServiceCommand.swift`
- `Sources/ContextifyIngestionCLI/Commands/UninstallServiceCommand.swift`
- `Sources/ContextifyIngestionCLI/Commands/ServiceStatusCommand.swift`
- `Sources/ContextifyIngestionCLI/Commands/StatusCommand.swift`
- `Sources/ContextifyIngestionCLI/XDGPaths.swift`
- `website/docs/linux.html` (or section in existing docs)

### Modified Files
- `Sources/ContextifyIngestionCLI/main.swift` - Add new commands, exit codes
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift` - Add --quiet
- `Package.swift` - Build-time version embedding

### Website Updates (when v1 ships)
- `website/platforms/linux/index.html`:
  - Remove "Beta" badge from hero section
  - Update installation instructions to use curl | sh install script
  - Add "Set up automatic ingestion" step with `install-service`
  - Update "Help and Support" to link to Linux-specific docs section
- `website/docs/index.html`:
  - Add Linux section with installation, service setup, troubleshooting
- `website/install.sh`:
  - New file, deploy with website

---

## Effort Summary

| Phase | Work | Hours |
|-------|------|-------|
| Foundation | XDG, exit codes, version, help, status | 5-6 |
| Service Setup | install/uninstall/status service | 3-4 |
| Distribution | Install script, completions, docs | 3-4 |
| Polish | Config file, testing, QA | 2-3 |
| **Total** | | **13-17** |

---

## References

- [XDG Base Directory Spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [systemd User Units](https://wiki.archlinux.org/title/Systemd/User)
- [systemd Timers](https://wiki.archlinux.org/title/Systemd/Timers)
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- Cross-platform investigation: `build/notes/todo-support/CROSS-PLATFORM-INGESTION-investigation.md`

---

## Existing Homebrew Situation

**IMPORTANT:** There is already a Homebrew formula for `contextify-query`:

```
brew install PeterPym/contextify/contextify-query
```

This formula exists specifically for **App Store users on macOS**. The App Store build is sandboxed and cannot install the CLI shim itself, so users install via Homebrew to get Total Recall functionality.

### The Problem

If we add a Linux Homebrew tap (Linuxbrew), we need to be **very careful** about naming and messaging:

| Formula | Platform | Purpose |
|---------|----------|---------|
| `contextify-query` | macOS | CLI for App Store users (query only) |
| `contextify` (proposed) | Linux | Full CLI suite (ingest + query + service) |

### Risks

1. **User confusion:** Linux user installs `contextify-query` thinking it's the full CLI
2. **Wrong binary:** `contextify-query` alone doesn't do ingestion
3. **Documentation mismatch:** Install instructions could point to wrong formula

### Recommendations

1. **For v1:** Use curl | sh installer, skip Homebrew on Linux entirely
2. **If we add Linux Homebrew later:**
   - Formula name: `contextify` (matches the binary name)
   - Formula installs the single `contextify` binary
   - Clear description: "Contextify CLI for Linux - transcript ingestion and search"
3. **Documentation must clearly distinguish:**
   - "macOS App Store users: `brew install PeterPym/contextify/contextify-query`"
   - "Linux users: `curl -fsSL https://contextify.sh/install.sh | sh`"

---

## Open Questions

1. **Config file in v1?** Could defer to v1.1 if time is tight. However, `CONTEXTIFY_DB_PATH` env var provides the most critical power-user need (custom db location).
2. **Homebrew tap for Linux?** Skip for v1, use curl installer. Revisit for v1.1+ (see above).
3. ~~**Migration from Beta?**~~ RESOLVED: `migrate-db` command in v1, copy-not-move approach.
4. **--json everywhere?** Useful for scripting, but adds work. Prioritize `status --json`.

---

## Future Considerations (v1.1+)

### Man Pages

Linux users expect `man contextify`. Not a P0, but a legitimacy marker.

**Options:**
- Generate from Swift Argument Parser help (automatic but basic)
- Write proper man pages (more work, better quality)
- Skip for v1, add in v1.1

### Shell Completions Automation

The spec includes manual completion installation. Auto-installing completions in the install script is nice-to-have but adds complexity:
- Must detect user's shell
- Must find correct completion directory
- May need shell reload

**v1 approach:** Document manual installation, defer automation to v1.1.

### Service Status Log Parsing

The `service-status` command could parse journald logs to show "last 5 runs". This is nice-to-have. For v1, simpler output with pointers to `journalctl` commands is sufficient:

```
Status: active
Timer: contextify.timer
Next run: in 12 minutes

View logs: journalctl --user -u contextify -n 20
```
