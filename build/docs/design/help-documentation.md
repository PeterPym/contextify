# Contextify Help Documentation

Comprehensive user-facing help content for the Contextify macOS application. This documentation serves as the source for the Help menu and future help delivery systems (online docs, Help Book, in-app viewer).

---

## Getting Started with Contextify

### Overview

Contextify is a macOS app that monitors your Claude Code and Codex CLI sessions in real-time, providing:
- Live timeline of conversation activity
- AI-powered summaries of each interaction
- Multi-project support with automatic discovery
- Searchable transcript inventory
- Cross-machine database sync (optional)

### Quick Setup

1. **Launch Contextify**
   - The app runs in your menu bar
   - Main window shows the conversation timeline

2. **Projects Are Auto-Discovered**
   - Contextify automatically finds all Claude Code and Codex projects
   - Click the "Manage Projects" button (folder with gear icon) to view all projects
   - Click "Set as Current" on any project to start monitoring it

3. **Start Using Claude Code or Codex**
   - Open a terminal in your project directory
   - Run `claude` or `codex` as usual
   - Contextify's timeline will populate automatically

### First-Time Tips

- **Empty Timeline?** The timeline shows activity from your current Claude session. Start a new Claude Code or Codex session to see entries appear.
- **Info Buttons (ⓘ):** Click the info circle next to features for detailed explanations.
- **Follow Modes:** Contextify can follow the newest session automatically (Auto mode) or stay locked to a specific session (Pinned mode).

---

## Feature Guides

### Projects & Discovery

#### What Are Projects?

Contextify organizes your work by project. Each project corresponds to a directory where you've used Claude Code or Codex CLI. Projects contain:
- Transcript files (conversation history)
- Timeline entries (individual requests/responses)
- Metadata (titles, descriptions, topics)

#### Auto-Discovery

Contextify automatically discovers projects by scanning:
- **Claude Code:** `~/.claude/projects/`
- **Codex CLI:** `~/.codex/sessions/`

New projects appear automatically when you start a Claude session in a new directory.

#### Managing Projects

Open the Projects window (⌘⇧P) to:
- View all discovered projects
- Switch between projects
- See project statistics (transcript count, last activity)
- Reveal project directories in Finder
- Set a project as current for timeline monitoring

#### Project Switching

**Keyboard Shortcuts:**
- ⌘⇧[ — Previous project
- ⌘⇧] — Next project
- ⌘⇧P — Open Projects window

**Project Tabs:**
- Drag and drop project tabs to reorder them
- Your preferred order is saved automatically

#### Current Project

The "current" project is what Contextify monitors for timeline updates. Only one project can be current at a time. Switch projects to see different conversation timelines.

---

### Timeline Monitoring

#### What Is the Timeline?

The conversation timeline displays real-time activity from your active Claude Code or Codex session:
- **User directives:** What you ask Claude to do
- **Assistant responses:** Claude's actions and output
- **Tool usage:** File operations, commands, searches
- **Request/response status:** Success, errors, timing

#### Follow Modes

Contextify can follow sessions in two ways:

**Auto Mode (Follow Newest):**
- Automatically switches to the newest transcript session
- Timeline updates when you start a new Claude session
- Best for active development with multiple sessions

**Pinned Mode (Follow Specific):**
- Stays locked to a specific transcript session
- Timeline doesn't switch even if newer sessions exist
- Best for reviewing or analyzing a particular conversation

**Switching Modes:**
- Click the Follow chip in the Projects window
- Select "Follow Newest (Auto)" or "Pin Current Session"

#### Timeline Features

**Auto-Scroll:**
- Enabled by default
- Automatically scrolls to newest entries
- Toggle in the timeline menu (⋯)

**Summaries:**
- Each entry shows an AI-generated summary
- Summaries describe what happened in plain language
- Generated locally with Apple Intelligence (macOS 15+)

**Navigation:**
- Click entry badges to jump between related requests/responses
- Use "Reveal in transcript inventory" to see full session context
- Scroll freely — auto-scroll won't interrupt you

**Manual Refresh:**
- Press ⌘R to refresh timeline immediately
- Useful if entries seem delayed

---

### AI Integration

#### Apple Intelligence

Contextify uses Apple's on-device Language Model API (macOS 15 Sequoia+) to generate summaries of conversation entries. This provides:
- **Privacy:** All processing happens locally on your Mac
- **Speed:** No network latency
- **Cost:** No additional API charges

#### AI Status Indicator

The status bar shows your AI availability:
- **🟢 Apple Intelligence** — AI summaries are working
- **🔴 AI Unavailable** — Running on older macOS or AI disabled
- **🟠 AI Error** — Temporary issue, summaries may be delayed

Click the info button (ⓘ) next to the status for details and troubleshooting.

#### Fallback Behavior

If Apple Intelligence is unavailable:
- Contextify uses heuristic summaries (rule-based, no AI)
- Existing cached summaries are preserved
- Upgrade to macOS 15+ to enable AI summaries

#### Summary Generation

**Timeline Summaries:**
- Generated in real-time as entries arrive
- Show in two forms: "present" (ongoing) and "past" (completed)
- Example: "Reading file..." → "Read file main.swift"

**Transcript Metadata:**
- Titles, descriptions, and topics for each session
- Generated in background (doesn't block timeline)
- Cached in database and sidecar JSON files

#### Privacy & Data

All AI processing is on-device. No conversation content is sent to external servers for summary generation. Your Claude Code/Codex sessions already send content to Anthropic's API — Contextify only processes that data locally.

---

### Database & Sync

#### Database Location

Contextify stores all data in a single SQLite database file:
- **Default:** `~/Library/Application Support/Contextify/contextify.db`
- **Custom:** Any folder you choose (Dropbox, iCloud Drive, external drive)

#### Why Custom Location?

**Benefits:**
- Sync database across multiple Macs via cloud storage
- Centralized backups
- Control over storage location

**Use Cases:**
- Work on multiple Macs and want unified timeline history
- Store database on external drive for portability
- Keep database in cloud folder for automatic backup

#### Changing Database Location

1. Open Settings (⌘,)
2. Go to Database tab
3. Select "Custom Location"
4. Click "Choose Custom Location..."
5. Select your desired folder

**Migration:**
- Contextify copies the database and all related files
- Old database is kept as backup
- You can delete the old location after verifying sync works

#### Multi-Machine Warning

⚠️ **Important:** If syncing via Dropbox or iCloud Drive, do NOT open Contextify on multiple Macs simultaneously. Concurrent writes can corrupt the database.

Contextify will warn you if it detects recent access from another machine.

#### Database Backup

**Automatic:**
- Database uses Write-Ahead Log (WAL) mode for crash safety
- Cloud sync (if configured) provides automatic backup

**Manual:**
- Use `scripts/db_manager.sh backup` to create timestamped backups
- Backups stored in `build/db-backups/`

---

## Troubleshooting

### AI Unavailable

**Symptoms:**
- Status bar shows "AI Unavailable"
- Timeline entries show generic descriptions instead of summaries
- No AI-generated transcript titles

**Common Causes & Solutions:**

**1. Running macOS 14 or earlier**
- Apple Intelligence requires macOS 15 Sequoia or later
- Solution: Upgrade to macOS 15+ to enable AI features
- Contextify will continue to work with heuristic summaries on older macOS

**2. Apple Intelligence disabled in System Settings**
- Check: System Settings → Apple Intelligence & Siri
- Ensure Apple Intelligence is enabled for your region/device
- Some regions may not have Apple Intelligence available yet

**3. macOS 15 but Language Model API not responding**
- Rare system-level issue
- Solution: Restart Contextify
- If persists: Restart your Mac
- Check Console.app for "LanguageModel" errors

**4. Device not compatible with Apple Intelligence**
- Apple Intelligence requires Apple Silicon (M1 or later)
- Intel Macs are not supported
- Solution: Use Contextify's heuristic summaries, or upgrade hardware

**Verification:**
- Click the AI status indicator in the status bar
- Click the info button (ⓘ) for detailed status
- Check "AI Integration" section for current state

---

### Project Not Found

**Symptoms:**
- Projects window shows "No projects found"
- Can't set a project as current
- Timeline remains empty

**Common Causes & Solutions:**

**1. Haven't used Claude Code or Codex yet**
- Contextify discovers projects by finding transcript files
- Solution: Run `claude` or `codex` in any directory to create your first project
- Refresh projects after creating a session

**2. Non-standard Claude/Codex installation**
- Contextify scans `~/.claude/projects/` and `~/.codex/sessions/`
- If your installation uses different paths, projects won't be found
- Solution: Check your Claude Code / Codex configuration
- Use standard installation paths for auto-discovery

**3. Projects directory permissions issue**
- Contextify needs read access to `~/.claude/` and `~/.codex/`
- Solution: Check directory permissions in Terminal:
  ```bash
  ls -ld ~/.claude ~/.codex
  ```
- Should show your user as owner with read permissions

**4. Transcript files are corrupted or incomplete**
- Contextify validates transcript JSON structure
- Invalid files are skipped during discovery
- Solution: Check logs for parsing errors
- Re-run Claude session to generate new valid transcript

**Manual Refresh:**
- Click "Manage Projects" button
- Projects window auto-refreshes every 30 seconds
- Or close/reopen the window to force refresh

---

### Database Issues

**Symptoms:**
- "Database error" alerts
- Timeline not updating
- Project changes not saving
- Settings not persisting

**Common Causes & Solutions:**

**1. Database file is locked or inaccessible**
- Another instance of Contextify might be running
- Cloud sync (Dropbox/iCloud) might be in progress
- Solution: Quit all instances of Contextify, wait for sync, relaunch

**2. Concurrent access from multiple Macs**
- Contextify detects when another Mac accessed the database recently
- Warning appears in Settings → Database tab
- Solution: Close Contextify on one Mac before opening on another
- Wait 1-2 minutes between switches for cloud sync to complete

**3. Database file corruption**
- Rare, usually caused by force-quit during write operation
- Solution: Restore from backup:
  ```bash
  cd /path/to/contextify/repo
  ./scripts/db_manager.sh restore latest
  ```
- If no backup: delete database and let Contextify re-ingest transcripts

**4. Disk space full**
- Database migration fails if target location has insufficient space
- Solution: Free up disk space or choose different location
- Contextify checks available space before migration

**5. Custom database location unreachable**
- External drive unmounted
- Network share disconnected
- Cloud folder not synced
- Solution: Reconnect drive/network, wait for sync
- Or switch back to default location in Settings

**Verification:**
- Open Settings (⌘,) → Database tab
- Check current location path
- Click "Reveal in Finder" to verify file exists
- Check for conflict warnings

**Recovery:**
```bash
# List available backups
./scripts/db_manager.sh list

# Restore from specific backup
./scripts/db_manager.sh restore contextify-backup-YYYYMMDD-HHMMSS.db

# Create manual backup before troubleshooting
./scripts/db_manager.sh backup
```

---

### LLM Generation Failures

**Symptoms:**
- Status bar shows error badge (🔴)
- Timeline entries missing summaries
- "Summary not yet generated" tooltips persist
- Transcript titles show "Developer Chat" or "Brief Session" placeholders

**Common Causes & Solutions:**

**1. Temporary Language Model API error**
- macOS's Language Model service occasionally fails
- Usually self-recovers within seconds
- Solution: Wait 30 seconds, summaries will resume automatically
- Contextify retries failed generations automatically

**2. Rate limiting or system load**
- High CPU usage may delay summary generation
- Many rapid entries can queue up
- Solution: Let Contextify catch up, check status bar for pending count
- Queue processes in order, older entries first

**3. Invalid or malformed entry content**
- Some transcript entries have unusual structure
- LLM may reject or fail on these
- Solution: These entries will show heuristic summaries instead
- No action needed — not all content is summarizable

**4. Persistent LLM errors**
- Status bar shows "X errors" for extended period
- Error count keeps increasing
- Solution:
  1. Click error badge info button (ⓘ) for details
  2. Click "Retry Failed Generations" action button
  3. If persists: Restart Contextify
  4. If still failing: Restart Mac (Language Model service issue)

**Monitoring LLM Status:**
- Status bar shows: "AI: X pending" or "AI: X errors"
- Hover over status bar for full breakdown
- Click info button (ⓘ) for detailed status and actions
- "Retry Failed Generations" button clears error queue

**Impact:**
- Timeline remains functional with heuristic summaries
- No data loss — entries are fully stored in database
- Summaries can be regenerated later when LLM recovers
- Cached summaries are preserved and reused

**Prevention:**
- Keep macOS updated for latest Language Model improvements
- Avoid force-quitting Contextify during active summary generation
- If using custom database location, ensure reliable storage (not slow network)

---

## Keyboard Shortcuts

### Window Management

| Shortcut | Action |
|----------|--------|
| ⌘⇧I | Show Transcript Inventory |
| ⌘⇧P | Show Projects Window |
| ⌘, | Open Settings |

### Project Navigation

| Shortcut | Action |
|----------|--------|
| ⌘⇧[ | Switch to Previous Project |
| ⌘⇧] | Switch to Next Project |

### Timeline Actions

| Shortcut | Action |
|----------|--------|
| ⌘R | Refresh Timeline |
| Tab | Navigate between UI elements |
| Space/Enter | Activate button or open info popover |
| Esc | Close popover or dismiss alert |

### General

| Shortcut | Action |
|----------|--------|
| ⌘Q | Quit Contextify |
| ⌘W | Close Window |
| ⌘H | Hide Contextify |
| ⌘M | Minimize Window |

### Tips

- Most UI elements support keyboard navigation via Tab
- Info buttons (ⓘ) can be activated with Space or Enter
- Press Esc to close popovers without clicking the close button

---

## Additional Resources

### Contact Support

For bugs, feature requests, or questions:
- **Email:** Use Help → Contact Support to open pre-filled email
- **GitHub Issues:** [contextify/issues](https://github.com/banagale/contextify/issues)

### Developer Documentation

For contributing or advanced use:
- **Architecture Docs:** `build/docs/architecture/`
- **Design System:** `build/docs/design/`
- **Database Schema:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

### Version & System Info

Check your Contextify version:
- Contextify → About Contextify

Check your system requirements:
- **Minimum:** macOS 14 Sonoma
- **Recommended:** macOS 15 Sequoia (for AI features)
- **Hardware:** Apple Silicon (M1+) for Apple Intelligence

---

## Quick Reference Card

**Setting Up:**
1. Launch Contextify
2. Projects auto-discover when you use Claude/Codex
3. Timeline populates automatically

**Switching Projects:**
- ⌘⇧P → Projects window → Set as Current
- Or use ⌘⇧[ / ⌘⇧] to cycle

**Understanding Follow Modes:**
- **Auto:** Follows newest session (default)
- **Pinned:** Stays on specific session

**AI Summaries:**
- Require macOS 15+, Apple Silicon
- Generated locally, no network needed
- Status shown in status bar

**Database Sync:**
- Default: local only
- Optional: Dropbox, iCloud, etc.
- ⚠️ Don't open on 2 Macs at once

**Getting Help:**
- Look for info buttons (ⓘ) throughout the app
- Help → Feature Guides for detailed docs
- Help → Contact Support for assistance
