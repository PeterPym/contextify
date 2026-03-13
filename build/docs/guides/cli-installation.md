# CLI Installation Guide

The `contextify` CLI enables Contextify skills in Claude Code and Codex CLI, providing deterministic search and context reinjection capabilities.

## Installation by Build Type

### DMG Build (contextify.sh/download)

**Automatic** - CLI and plugin are installed automatically on first launch.

1. Download and install Contextify from contextify.sh/download
2. Launch Contextify
3. CLI auto-installs to `/opt/homebrew/bin/` (or `/usr/local/bin/`)
4. Plugin auto-installs to `~/.claude/plugins/`

To verify:
```bash
contextify --version
contextify status
```

### App Store Build

**Manual via Homebrew** - Due to sandbox restrictions, App Store builds cannot install the CLI automatically.

1. Install the CLI via Homebrew:
   ```bash
   brew install PeterPym/contextify/contextify-query
   ```

2. Install the Total Recall skill:
   ```bash
   contextify install-plugin
   ```

3. Restart Claude Code or Codex CLI

4. Verify installation:
   ```bash
   contextify status
   ```

## CLI Commands

### Database Commands

```bash
# Check database status and connection
contextify status

# Search entries by text
contextify search "error handling" --limit 10

# List all projects
contextify projects

# List transcripts for a project
contextify transcripts --project myproject

# Get a specific entry by UUID
contextify entry <uuid>

# Get context around an entry
contextify context <uuid>
```

### Skill Commands

```bash
# Install/update Total Recall skill for Claude Code and Codex CLI
contextify install-plugin

# Remove Total Recall skill from Claude Code and Codex CLI
contextify uninstall-plugin
```

On macOS, `install-plugin` is the canonical command because it also repairs the plugin/manifest install surface used by the app integration. The Linux unified CLI uses `install-skill` for the same end state because it installs the skill directly without the macOS plugin cache flow.

### Health Check Commands

```bash
# Verify CLI installation health
contextify doctor

# Machine-readable health check
contextify doctor --json
```

Local development via Claude Code:

```bash
claude plugin marketplace add /Users/rob/code/projects/contextify
claude plugin install query@contextify
```

## Local Development Skill Testing

When you run `contextify install-plugin` from the repository root, the installer prefers the repo-local skill source at `contextify-query/user-skill/total-recall/SKILL.md`.

Use this flow to test local skill edits deliberately:

```bash
# From the repository root
swift run contextify-query install-plugin
contextify doctor
```

`contextify doctor` reports the installed skill provenance, including whether it came from a repo-local source, app bundle, or Homebrew Cellar payload, and whether the installed copy is stale or modified.

To return to the shipped skill, re-run `install-plugin` from the installed CLI context instead of the repository root.

### Other Commands

```bash
# Show version
contextify --version

# Show help
contextify --help

# Output as JSON (for scripting)
contextify status --json
```

## Backwards Compatibility

The legacy `contextify-query` command still works via symlink:

```bash
# These are equivalent:
contextify search "query"
contextify-query search "query"  # Deprecated, shows warning
```

## Plugin and Skill Locations

The Claude Code plugin is installed to:
```
~/.claude/plugins/cache/contextify/query/{version}/
```

The Total Recall user skill is installed to:
```
~/.claude/skills/total-recall/
```

The Codex CLI skill is installed to:
```
~/.codex/skills/total-recall/
```

Plugin registration is stored in:
```
~/.claude/plugins/installed_plugins.json
```

## Codex CLI Notes

- Codex CLI requires `--enable-skills` to load skills.
- The `contextify-researcher` agent is only available in Claude Code (Codex has no Task tool).

## App Store Permission Requirements

App Store builds require explicit folder access grants due to macOS sandbox restrictions.

### Status Bar Permission Indicator

When no CLI transcript folder access is granted, the status bar shows a **"No CLI Access"** warning:

```
⚠️ No CLI Access | Lite Mode | Up to date
```

**Clicking the indicator** opens Settings > Permissions, where you can grant access.

### Required Permissions

Grant access to at least one transcript folder:

| CLI Tool | Folder Location | Purpose |
|----------|-----------------|---------|
| Claude Code | `~/.claude/projects/` | Session transcripts |
| Codex CLI | `~/.codex/sessions/` | Session transcripts |

### Granting Access

1. Open Contextify Settings (⌘,)
2. Go to **Permissions** tab
3. Click **Grant Access** for Claude Code or Codex CLI
4. Select the appropriate folder in the file picker
5. The status bar indicator disappears once access is granted

**Note:** DMG builds have unrestricted filesystem access and don't require these permission grants.

---

## Troubleshooting

### "database not found" error

The CLI cannot find the Contextify database.

1. Ensure Contextify.app is installed
2. Open Contextify at least once to initialize the database
3. Check database location: `~/Library/Application Support/Contextify/contextify.db`

### Plugin not appearing in Claude Code

1. Run `contextify install-plugin`
2. Completely quit and restart Claude Code (not just close window)
3. Verify plugin registration:
   ```bash
   cat ~/.claude/plugins/installed_plugins.json | grep contextify
   ```

### CLI health check reports degraded

1. Run `contextify doctor` to see missing components
2. Run `contextify install-plugin`
3. Re-run `contextify doctor` to confirm healthy status

### CLI not found after Homebrew install

Ensure Homebrew bin is in your PATH:
```bash
echo $PATH | grep -o '/opt/homebrew/bin'
```

If missing, add to your shell profile (~/.zshrc or ~/.bashrc):
```bash
export PATH="/opt/homebrew/bin:$PATH"
```

### Upgrading

**DMG:** Updates automatically with app updates.

**Homebrew:**
```bash
brew upgrade contextify-query
contextify install-plugin  # Re-run to update skill
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      DMG Build                               │
├─────────────────────────────────────────────────────────────┤
│ CLI: Embedded in app bundle, installed to system path       │
│   - Primary binary: contextify                              │
│   - Symlinks: contextify-query, contextify-ingest           │
│ Plugin: Auto-installed to ~/.claude/plugins/                │
│ Permissions: Unrestricted filesystem access                 │
│ Database: ~/Library/Application Support/Contextify/         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    App Store Build                           │
├─────────────────────────────────────────────────────────────┤
│ CLI: Installed via Homebrew to /opt/homebrew/bin/           │
│ Plugin: User runs `contextify install-plugin`               │
│ Permissions: Requires security-scoped bookmark grants       │
│   - Status bar shows "No CLI Access" if none granted        │
│ Database: ~/Library/Application Support/Contextify/         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   Claude Code Integration                    │
├─────────────────────────────────────────────────────────────┤
│ User skill (discoverable):                                   │
│   - /total-recall: Search past conversations & decisions    │
│ Plugin provides background agents and session hooks         │
│ Skills call contextify CLI for database access              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Codex CLI Integration                     │
├─────────────────────────────────────────────────────────────┤
│ User skill (discoverable):                                   │
│   - /total-recall: Search past conversations & decisions    │
│ Skill runs contextify CLI for database access               │
│ No agent delegation (Codex lacks Task tool)                 │
└─────────────────────────────────────────────────────────────┘
```

## Related Documentation

- [App Store Sandbox Constraints](../../.claude/skills/appstore-sandbox-constraints.md)
- [Claude Plugin Auto-Install Spec](../specifications/claude-plugin-auto-install.md)
- [Homebrew Tap README](https://github.com/PeterPym/homebrew-contextify)
