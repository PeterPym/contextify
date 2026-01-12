---
branch: main
worktree: /Users/rob/code/projects/contextify-wb2
repo: banagale/contextify
date: 2026-01-11
status: ready-for-review
---

# Contextify v1.1.0 External Release Notes

## 5.1 Highlights (Customer-Facing)

### All Platforms
- **Linux CLI Support** - Total Recall now works on Linux systems running Claude Code or Codex CLI
- **Codex CLI Integration** - Full skill support for OpenAI's Codex CLI alongside Claude Code
- **CLI Health Checker** - New `contextify-query doctor` command diagnoses installation issues
- **2.5x Faster Bulk Ingest** - Performance optimizations dramatically speed up first-run and large history imports

### macOS App
- **Inline Image Rendering** - Images in timeline entries now render inline with Quick Look preview
- **Status Bar Permissions** - Visual indicator shows permission state at a glance
- **Project Attribution Fix** - Entries are now correctly attributed to projects based on working directory
- **Sidechain Visibility** - Agent sub-conversations and tool calls are now captured and searchable

---

## 5.2 Full Release Notes (Per Channel)

### DMG (v1.0.7 -> v1.1.0)

#### New
- **Linux CLI**: `contextify-query` now builds and runs on Linux
- **CLI Doctor Command**: Run `contextify-query doctor` to diagnose installation health
- **Codex CLI Support**: Total Recall skill installs for Codex CLI automatically
- **Inline Images**: Timeline shows images with Quick Look support
- **Status Bar Indicator**: See permission status in the status bar
- **Worktree Grouping**: Projects visually grouped by git worktree

#### Improved
- **Bulk Ingest Performance**: ~2.5x faster via PRAGMA tuning and observation-free ingest
- **Project Attribution**: Entries reassigned based on CWD for accuracy
- **CLI Installation**: Unified manifest format, auto-repair for partial installs
- **Sidechain Capture**: Agent sidechains and tool invocations now stored and searchable
- **ConversationMonitor**: Internal refactor improves state management

#### Fixed
- Project misattribution from session ID collisions
- Skill directory cleanup when disabling CLI integration
- PATH warning during CLI installation
- Sidechain filter now independent of "show hidden" setting

#### Developer/Advanced
- Benchmark infrastructure for performance profiling
- EntryFilter type system for query composition
- Cross-platform abstractions (logger, lock, crypto)

---

### App Store (v1.0.5 -> v1.1.0)

*Includes all DMG changes plus:*

#### New
- **Total Recall Branding**: Skill renamed to `/total-recall`
- **User Skill Auto-Install**: Skill automatically installed on first launch
- **Agent Badges**: Visual decorations for Contextify agent calls in timeline
- **v1.0.6 Blog Post**: Announcement content for lite mode support

#### Improved
- **Decoration Query Infrastructure**: Foundation for timeline entry decorations
- **Entry Filter Architecture**: Decoupled sidechain filtering from hidden entries

#### Fixed
- v1.0.6 release metadata corrections
- Old skill location cleanup during migration

---

### Linux CLI (First Release)

#### New
- **contextify-query CLI**: Search your Claude Code/Codex conversation history
- **Total Recall Skill**: Install via `contextify-query install-plugin`
- **Doctor Command**: Diagnose installation with `contextify-query doctor`
- **Cross-Platform Support**: Works on Linux systems with Swift runtime

#### Requirements
- Linux system with Swift runtime
- Claude Code or Codex CLI installed
- GitHub release artifacts or build from source

---

## 5.3 App Store "What's New" (3-6 bullets)

### Version 1.1.0

- **Linux Support**: Total Recall skill now works on Linux
- **Codex CLI**: Full integration with OpenAI's Codex CLI
- **Faster Imports**: 2.5x faster bulk transcript ingestion
- **Inline Images**: Images now render directly in the timeline
- **Improved Accuracy**: Fixed project attribution for cross-directory sessions
- **Health Checks**: New doctor command diagnoses installation issues

---

## Channel Matrix

| Feature | App Store | DMG | Linux CLI |
|---------|:---------:|:---:|:---------:|
| Linux CLI Support | - | - | **NEW** |
| Codex CLI Integration | Yes | Yes | Yes |
| CLI Doctor Command | Yes | Yes | Yes |
| Performance Optimizations | Yes | Yes | - |
| Inline Image Rendering | Yes | Yes | - |
| Status Bar Permissions | Yes | Yes | - |
| Project Misattribution Fix | Yes | Yes | - |
| Sidechain Ingestion | Yes | Yes | - |
| Total Recall Branding | Yes | Yes | Yes |
| User Skill Auto-Install | Yes | Yes | Yes |
| Agent Badges | Yes | Yes | - |
| Worktree Grouping | Yes | Yes | - |

---

## Breaking Changes / Migration Notes

### CLI Manifest Migration
The CLI installation manifest has been unified to `installed_plugins.json`. Old manifest formats are automatically migrated on first read. No user action required.

### Project Attribution
Entries may be reassigned to different projects after upgrading if they were previously misattributed due to session ID collisions. This improves accuracy but may cause entries to appear under different projects than before.

### Sidechain Filter
The sidechain filter is now independent of the "show hidden entries" setting. Users who relied on hiding sidechains via the hidden filter may need to adjust their preferences.

---

## Upgrade Steps

### DMG Users
1. Download v1.1.0 from GitHub releases or use Sparkle auto-update
2. Launch the app - CLI manifest migrates automatically
3. Verify CLI health: `contextify-query doctor`

### App Store Users
1. Update via the App Store
2. Launch the app - all migrations are automatic
3. Verify CLI health in Settings > CLI Integration

### Linux Users (New)
1. Download `contextify-query` from GitHub releases
2. Make executable: `chmod +x contextify-query`
3. Install skill: `./contextify-query install-plugin`
4. Verify: `./contextify-query doctor`
