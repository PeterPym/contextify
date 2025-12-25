# CLI Installation Guide

The `contextify-query` CLI enables Contextify skills in Claude Code, providing deterministic search and context reinjection capabilities.

## Installation by Build Type

### DMG Build (contextify.sh/download)

**Automatic** - CLI and plugin are installed automatically on first launch.

1. Download and install Contextify from contextify.sh/download
2. Launch Contextify
3. CLI auto-installs to `/opt/homebrew/bin/` (or `/usr/local/bin/`)
4. Plugin auto-installs to `~/.claude/plugins/`

To verify:
```bash
contextify-query --version
contextify-query status
```

### App Store Build

**Manual via Homebrew** - Due to sandbox restrictions, App Store builds cannot install the CLI automatically.

1. Install the CLI via Homebrew:
   ```bash
   brew install PeterPym/contextify/contextify-query
   ```

2. Install the Claude Code plugin:
   ```bash
   contextify-query install-plugin
   ```

3. Restart Claude Code

4. Verify installation:
   ```bash
   contextify-query status
   ```

## CLI Commands

### Database Commands

```bash
# Check database status and connection
contextify-query status

# Search entries by text
contextify-query search "error handling" --limit 10

# List all projects
contextify-query projects

# List transcripts for a project
contextify-query transcripts --project myproject

# Get a specific entry by UUID
contextify-query entry <uuid>

# Get context around an entry
contextify-query context <uuid>
```

### Plugin Commands

```bash
# Install/update Claude Code plugin
contextify-query install-plugin

# Remove Claude Code plugin
contextify-query uninstall-plugin
```

Local development via Claude Code:

```bash
claude plugin marketplace add /Users/rob/code/projects/contextify
claude plugin install query@contextify
```

### Other Commands

```bash
# Show version
contextify-query --version

# Show help
contextify-query --help

# Output as JSON (for scripting)
contextify-query status --json
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

Plugin registration is stored in:
```
~/.claude/plugins/installed_plugins.json
```

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

1. Run `contextify-query install-plugin`
2. Completely quit and restart Claude Code (not just close window)
3. Verify plugin registration:
   ```bash
   cat ~/.claude/plugins/installed_plugins.json | grep contextify
   ```

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
contextify-query install-plugin  # Re-run to update plugin
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      DMG Build                               │
├─────────────────────────────────────────────────────────────┤
│ CLI: Embedded in app bundle, shim installed to system path  │
│ Plugin: Auto-installed to ~/.claude/plugins/                │
│ Permissions: Unrestricted filesystem access                 │
│ Database: ~/Library/Application Support/Contextify/         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    App Store Build                           │
├─────────────────────────────────────────────────────────────┤
│ CLI: Installed via Homebrew to /opt/homebrew/bin/           │
│ Plugin: User runs `contextify-query install-plugin`         │
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
│ Skills call contextify-query CLI for database access        │
└─────────────────────────────────────────────────────────────┘
```

## Related Documentation

- [App Store Sandbox Constraints](../../.claude/skills/appstore-sandbox-constraints.md)
- [Claude Plugin Auto-Install Spec](../specifications/claude-plugin-auto-install.md)
- [Homebrew Tap README](https://github.com/PeterPym/homebrew-contextify)
