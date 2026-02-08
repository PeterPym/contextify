# Contextify 1.2.0 Release Notes

## What's New

### Linux CLI (contextify-query)

Total Recall now works on Linux. The `contextify-query` CLI tool enables searching your AI conversation history from any Linux system with access to your Contextify database.

**Installation:**
```bash
curl -fsSL https://contextify.sh/install-linux.sh | bash
```

Features:
- Search conversations by keyword, project, or date range
- Retrieve context around specific entries
- JSON output for scripting and automation
- Works with databases synced via Dropbox, iCloud Drive, or other cloud storage

### Bug Fixes

- **Tab persistence**: Hidden project tabs now persist across app restart. Previously, manually hidden tabs would reappear after relaunching Contextify.

## Technical Notes

- Build 20
- Requires macOS 15 (Sequoia) or later
- macOS 26 (Tahoe) recommended for full Apple Intelligence summaries
