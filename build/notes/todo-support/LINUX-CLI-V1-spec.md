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

### 1. XDG Base Directory Compliance

**Specification:** [XDG Base Directory Spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)

**Required paths:**

```
$XDG_DATA_HOME/contextify/          # Default: ~/.local/share/contextify/
├── contextify.db                   # Main database
└── backups/                        # Optional backup location

$XDG_CONFIG_HOME/contextify/        # Default: ~/.config/contextify/
└── config.toml                     # User configuration

$XDG_STATE_HOME/contextify/         # Default: ~/.local/state/contextify/
└── logs/                           # Ingestion logs (optional)

$XDG_CACHE_HOME/contextify/         # Default: ~/.cache/contextify/
└── (temporary files if needed)
```

**Implementation:**

```swift
struct XDGPaths {
    static var dataHome: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/contextify")
    }

    static var configHome: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/contextify")
    }

    static var databasePath: URL {
        dataHome.appendingPathComponent("contextify.db")
    }
}
```

**Migration:** On first run, if database exists at old location, offer to migrate or use `--db` flag.

---

### 2. Install Script

**URL:** `https://contextify.sh/install.sh`

**Usage:**
```bash
curl -sSL https://contextify.sh/install.sh | sh
```

**Script behavior:**

1. Detect architecture (`uname -m` → x86_64 or aarch64)
2. Detect latest version from GitHub releases API
3. Download appropriate tarball
4. Extract to `~/.local/bin/`
5. Verify binaries execute (`contextify-query --version`)
6. Run `contextify-query install-skill`
7. Prompt to run `contextify-ingest install-service`
8. Print success message with next steps

**Script template:**

```bash
#!/bin/sh
set -e

# Contextify Linux Installer
# Usage: curl -sSL https://contextify.sh/install.sh | sh

REPO="PeterPym/contextify"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

main() {
    check_dependencies
    detect_arch
    detect_version
    download_and_extract
    verify_installation
    install_skill
    print_success
}

check_dependencies() {
    for cmd in curl tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: $cmd is required but not installed."
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
            exit 1
            ;;
    esac
    echo "Detected architecture: $ARCH"
}

detect_version() {
    VERSION=$(curl -sSL "https://api.github.com/repos/$REPO/releases/latest" |
              grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "Error: Could not detect latest version"
        exit 1
    fi
    echo "Latest version: $VERSION"
}

download_and_extract() {
    URL="https://github.com/$REPO/releases/download/v$VERSION/contextify-linux-$ARCH.tar.gz"
    echo "Downloading from $URL..."

    mkdir -p "$INSTALL_DIR"
    curl -sSL "$URL" | tar -xz -C "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/contextify-query" "$INSTALL_DIR/contextify-ingest"
}

verify_installation() {
    if ! "$INSTALL_DIR/contextify-query" --version >/dev/null 2>&1; then
        echo "Error: Installation verification failed"
        exit 1
    fi
}

install_skill() {
    echo "Installing Total Recall skill..."
    "$INSTALL_DIR/contextify-query" install-skill
}

print_success() {
    echo ""
    echo "✓ Contextify installed successfully!"
    echo ""
    echo "Binaries installed to: $INSTALL_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure $INSTALL_DIR is in your PATH"
    echo "  2. Run: contextify-ingest install-service"
    echo "  3. Use /total-recall in Claude Code or Codex"
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
contextify-ingest install-service [--interval 15m]
contextify-ingest uninstall-service
contextify-ingest service-status
```

**Service file:** `~/.config/systemd/user/contextify-ingest.service`
```ini
[Unit]
Description=Contextify transcript ingestion
Documentation=https://contextify.sh/docs/

[Service]
Type=oneshot
ExecStart=%h/.local/bin/contextify-ingest ingest --quiet
Environment="XDG_DATA_HOME=%h/.local/share"

[Install]
WantedBy=default.target
```

**Timer file:** `~/.config/systemd/user/contextify-ingest.timer`
```ini
[Unit]
Description=Run Contextify ingestion periodically
Documentation=https://contextify.sh/docs/

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
```

**install-service implementation:**

1. Check systemd availability (`systemctl --user status` succeeds)
2. Create `~/.config/systemd/user/` if needed
3. Write service file (with correct binary path)
4. Write timer file (with configured interval)
5. Run `systemctl --user daemon-reload`
6. Run `systemctl --user enable --now contextify-ingest.timer`
7. Print status and next-run time

**service-status output:**
```
Contextify Ingestion Service
============================
Status: active (waiting)
Timer: contextify-ingest.timer
Next run: 2026-01-12 22:15:00 PST (in 12 minutes)
Last run: 2026-01-12 22:00:00 PST (success)

Recent logs (last 5 runs):
  Jan 12 22:00:00 - Ingested 3 new entries
  Jan 12 21:45:00 - No new transcripts
  Jan 12 21:30:00 - Ingested 15 new entries

View full logs: journalctl --user -u contextify-ingest
```

**Fallback for non-systemd:**
```
systemd not detected. To run ingestion periodically, add to crontab:

  crontab -e

Then add:
  */15 * * * * ~/.local/bin/contextify-ingest ingest --quiet
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
contextify-ingest ingest --quiet  # Only errors to stderr
contextify-ingest ingest -q       # Short form
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
contextify-ingest ingest --verbose  # Debug output
contextify-ingest ingest -v         # Short form
```

#### Version Output

```bash
$ contextify-query --version
contextify-query 1.1.0 (abc1234)
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
$ contextify-ingest --help
Contextify Ingestion CLI - Index your AI coding conversations

USAGE: contextify-ingest <command> [options]

COMMANDS:
  ingest            Ingest transcripts into the database
  status            Show database and indexing status
  install-service   Set up automatic background ingestion
  uninstall-service Remove background ingestion service
  service-status    Check background service status

OPTIONS:
  --db <path>       Database location (default: ~/.local/share/contextify/contextify.db)
  --quiet, -q       Suppress non-error output
  --verbose, -v     Enable debug output
  --version         Show version information
  --help, -h        Show this help

EXAMPLES:
  contextify-ingest ingest                    # Index new transcripts
  contextify-ingest ingest --quiet            # Silent mode for cron
  contextify-ingest status                    # What's indexed?
  contextify-ingest install-service           # Set up auto-ingestion

DOCUMENTATION: https://contextify.sh/docs/
```

---

### 5. Status Command

```bash
$ contextify-ingest status
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
$ contextify-ingest status --json
{
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

---

### 6. Shell Completions

Swift Argument Parser can generate completions automatically.

**Installation commands:**
```bash
# Bash
contextify-query --generate-completion-script bash > ~/.local/share/bash-completion/completions/contextify-query
contextify-ingest --generate-completion-script bash > ~/.local/share/bash-completion/completions/contextify-ingest

# Zsh
contextify-query --generate-completion-script zsh > ~/.zfunc/_contextify-query
contextify-ingest --generate-completion-script zsh > ~/.zfunc/_contextify-ingest

# Fish
contextify-query --generate-completion-script fish > ~/.config/fish/completions/contextify-query.fish
contextify-ingest --generate-completion-script fish > ~/.config/fish/completions/contextify-ingest.fish
```

**Install script integration:** Offer to install completions for detected shell.

---

### 7. Config File (Optional)

**Location:** `~/.config/contextify/config.toml`

```toml
# Contextify Configuration

[database]
# path = "~/.local/share/contextify/contextify.db"  # Default

[ingestion]
interval = "15m"      # Service timer interval
quiet = true          # Suppress output in background runs

[providers]
claude_path = "~/.claude/projects"
codex_path = "~/.codex/sessions"

# Future: custom provider paths, exclusions, etc.
```

**Precedence:** CLI flags > Environment variables > Config file > Defaults

**Implementation:** Use a simple TOML parser or hand-roll for minimal dependencies.

---

## Implementation Plan

### Phase 1: Foundation (4-6 hours)

1. **XDG paths** (1 hr)
   - Create `XDGPaths` helper
   - Update database default location
   - Add migration prompt for existing databases

2. **Exit codes + quiet mode** (1 hr)
   - Define `ExitCode` enum
   - Add `--quiet` flag to ingest command
   - Ensure all commands return appropriate codes

3. **Version info** (30 min)
   - Embed git hash at build time
   - Format version output properly

4. **Help text audit** (1 hr)
   - Review all command help strings
   - Add examples where missing
   - Ensure consistency

5. **Status command** (1.5 hr)
   - Query database for stats
   - Format human-readable output
   - Add `--json` flag

### Phase 2: Service Setup (3-4 hours)

6. **install-service command** (1.5 hr)
   - Detect systemd
   - Generate service + timer files
   - Run systemctl commands
   - Handle errors gracefully

7. **uninstall-service command** (30 min)
   - Stop and disable timer
   - Remove files
   - Confirm removal

8. **service-status command** (1 hr)
   - Query systemctl status
   - Parse next run time
   - Show recent log entries

### Phase 3: Distribution (3-4 hours)

9. **Install script** (1.5 hr)
   - Write install.sh
   - Test on Ubuntu, Fedora, Arch
   - Deploy to website

10. **Shell completions** (1 hr)
    - Verify Swift Argument Parser generates them
    - Add to install script
    - Document manual installation

11. **Documentation** (1 hr)
    - Update /docs/ page
    - Add troubleshooting section
    - Update README

### Phase 4: Polish (2-3 hours)

12. **Config file support** (1.5 hr) [Optional for v1]
    - TOML parsing
    - Merge with CLI flags

13. **Testing** (1 hr)
    - Docker-based E2E test
    - Test on multiple distros

14. **Final QA** (30 min)
    - Fresh install walkthrough
    - Verify all commands work

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

## Open Questions

1. **Config file in v1?** Could defer to v1.1 if time is tight.
2. **Homebrew tap?** Nice to have but not blocking v1.
3. **Migration from Beta?** Users with databases in old locations need migration path.
4. **--json everywhere?** Useful for scripting, but adds work. Prioritize `status --json`.
