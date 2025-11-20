# Technical Brief: Transcripts + Codex Migration Support

**Date:** 2025-10-09
**Branch:** `feature/transcript-inventory`
**Status:** Claude Code support complete, Codex support needed
**Context:** Continuation prompt for fresh LLM conversation

---

## Executive Summary

Contextify now has a **Transcripts** feature that discovers and displays all Claude Code transcripts for a project, including those in git worktrees. A **migration script** exists to rewrite transcript paths when projects move. Both features currently support **Claude Code only**.

**Next goal:** Extend both to support **Codex/AI CLI** transcripts.

---

## Current State (What's Been Built)

### 1. Transcripts UI ✅
**Location:** `Contextify/Contextify/TranscriptInventoryView.swift`

**Features:**
- HSplitView with sidebar (session list) + detail pane
- URL-based selection (proven working pattern from TimelineQualityDebugView)
- Shows: provider icon, filename, last modified, file size, line count
- Active transcript badge (green dot)
- "Select for Monitoring" button
- Search functionality
- Done button + ESC key dismissal
- Opens from Timeline menu: "Show All Transcripts"

**Data Flow:**
```
ProjectContext.allProjectPaths()
  → ClaudeTranscriptProvider.sessions(for: ProjectContext)
  → ConversationMonitor.allSessions
  → TranscriptInventoryView (displays list)
```

### 2. ProjectContext with Worktree Discovery ✅
**Location:** `Contextify/Contextify/ProjectContext.swift`

**Capabilities:**
- Discovers git repository root from working directory
- Parses `.git/worktrees/` metadata to find all worktrees
- Returns `allProjectPaths()` - all locations to check for transcripts

**Example:**
```swift
let context = ProjectContext.current()
// Returns: [
//   /Users/rob/code/projects/contextify,
//   /Users/rob/code/projects/contextify-worktree-test
// ]
```

### 3. Multi-Source Provider Architecture ✅
**Location:** `Contextify/Contextify/ConversationSources.swift`

**Pattern:**
```swift
protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
    func sessions(for context: ProjectContext) -> [TranscriptSession]
}

// Currently implemented:
struct ClaudeTranscriptProvider: ConversationTranscriptProvider

// TODO: Implement
struct CodexTranscriptProvider: ConversationTranscriptProvider
```

### 4. Migration Script ✅ (Claude Code only)
**Location:** `scripts/migrate-transcripts.sh`

**What it does:**
- Takes old path + new path as arguments
- Finds Claude transcripts at: `~/.claude/projects/<old-path-encoded>/`
- Creates timestamped backup
- Copies to new location: `~/.claude/projects/<new-path-encoded>/`
- Replaces all instances of old path with new path in JSONL content
- Uses `sed` for safe find-replace

**Example:**
```bash
./scripts/migrate-transcripts.sh \
  /Users/rob/code/contextify \
  /Users/rob/code/projects/contextify
```

**Currently rewrites:**
- `"cwd": "/old/path"` → `"cwd": "/new/path"`
- File tool uses: `/old/path/File.swift` → `/new/path/File.swift`
- Message content: All path references updated

---

## The Codex Challenge

### Claude Code Storage (Current)
```
~/.claude/projects/-Users-rob-code-contextify/
  ├── ce6e090b-603e-484a-977e-546214573964.jsonl
  ├── 029815f5-695b-442e-9e3d-a1d0b2ed3892.jsonl
  └── ...
```

**Key:** Directory name encodes project path (`/` → `-`)
**Easy discovery:** Just convert path to directory name

### Codex/AI CLI Storage (Unknown location, date-based)
**Problem:** Codex doesn't organize by project path

**Per technical-briefing-local-history-claude-code-codex.md:**
- Sessions are per-run JSONL files
- Path is **implementation/config dependent** (not per-project)
- Likely locations: CLI data/home directory, possibly date-organized
- Session metadata stored in `session_meta` record with `payload.cwd`

**Discovery strategy:**
```jsonl
{
  "timestamp": "2025-10-06T16:42:01.644Z",
  "type": "session_meta",
  "payload": {
    "id": "uuid-here",
    "cwd": "/Users/rob/code/contextify",  ← Project path!
    "git": {
      "commit_hash": "abc123",
      "branch": "main",
      "repository_url": "..."
    }
  }
}
```

**Must:**
1. Find Codex storage location (search common paths)
2. Parse every JSONL file to find `session_meta` records
3. Match `payload.cwd` against project paths
4. Return matching sessions

---

## Required Work

### Task 1: Locate Codex Transcripts on This Machine

**Approach:**
```bash
# Common locations to check:
~/.codex/sessions/
~/.local/share/codex/
~/Library/Application Support/codex/
~/.config/codex/

# Or search entire home dir (slow):
find ~ -name "*.jsonl" -exec grep -l "session_meta" {} \; 2>/dev/null
```

**Deliverable:** Absolute path(s) where Codex stores JSONL files

### Task 2: Implement CodexTranscriptProvider

**Location:** Add to `Contextify/Contextify/ConversationSources.swift`

**Skeleton:**
```swift
struct CodexTranscriptProvider: ConversationTranscriptProvider {
    private let fileManager = FileManager.default

    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Check each project path (including worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        return Array(Set(allSessions)) // Dedupe by fileURL
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        // 1. Find Codex storage directory
        let codexDirs = findCodexStorageLocations()

        // 2. Find all JSONL files
        var sessions: [TranscriptSession] = []
        for dir in codexDirs {
            let jsonlFiles = findJSONLFiles(in: dir)

            // 3. Parse each file looking for session_meta with matching cwd
            for fileURL in jsonlFiles {
                if let session = parseCodexSession(fileURL, matchingPath: projectPath) {
                    sessions.append(session)
                }
            }
        }

        return sessions
    }

    private func parseCodexSession(_ fileURL: URL, matchingPath: String) -> TranscriptSession? {
        // Read file line-by-line (JSONL)
        // Find line with type: "session_meta"
        // Parse payload.cwd
        // If matches projectPath, return TranscriptSession
        // Provider: .codexCLI
        // Identifier: filename
        // fileURL: fileURL
        // lastActivity: file modification date
    }

    private func findCodexStorageLocations() -> [URL] {
        // Return list of directories where Codex stores sessions
        // TODO: Implement discovery
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        // Recursively find all .jsonl files
    }
}
```

**Register provider:**
```swift
// In ConversationMonitor.swift:
private let conversationResolver = ActiveConversationResolver(providers: [
    ClaudeTranscriptProvider(),
    CodexTranscriptProvider()  // ← Add this
])
```

### Task 3: Extend Migration Script for Codex

**Location:** `scripts/migrate-transcripts.sh`

**Changes needed:**

1. **Add Codex session discovery:**
```bash
migrate_codex_transcripts() {
    local old_path="$1"
    local new_path="$2"

    # Find Codex storage location
    codex_dirs=$(find_codex_storage)

    for dir in $codex_dirs; do
        # Find JSONL files with matching cwd
        while IFS= read -r file; do
            if grep -q "\"cwd\":\"$old_path\"" "$file"; then
                echo "  Found Codex session: $(basename "$file")"

                # Replace paths in place (or copy to backup first)
                sed -i.bak "s|$old_path|$new_path|g" "$file"
            fi
        done < <(find "$dir" -name "*.jsonl")
    done
}
```

2. **Add to main migration flow:**
```bash
# After Claude Code migration:
log "Migrating Claude Code transcripts..."
migrate_claude_transcripts "$OLD_PATH" "$NEW_PATH"

log "Migrating Codex/AI CLI transcripts..."
migrate_codex_transcripts "$OLD_PATH" "$NEW_PATH"
```

3. **Update summary to show both:**
```
Migration Summary:
  ✓ Claude Code: 33 files
  ✓ Codex/AI CLI: 12 files
  📦 Backup: ~/transcript-backup-...
```

---

## Data Structures Reference

### TranscriptSession (already exists)
```swift
struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider  // .claudeCode or .codexCLI
    let identifier: String      // Filename
    let fileURL: URL           // Full path to JSONL
    let lastActivity: Date     // File modification date
}
```

### TimelineSourceContext.Provider (already exists)
```swift
enum Provider: String, Sendable {
    case claudeCode = "claude.code"
    case codexCLI = "codex.cli"    // ← Already defined!
    case other
}
```

---

## File References

**Implementation files:**
- `Contextify/Contextify/ConversationSources.swift` - Add CodexTranscriptProvider
- `Contextify/Contextify/ConversationMonitor.swift` - Register provider (line 13)
- `scripts/migrate-transcripts.sh` - Add Codex support
- `TODOS.md` - Update after completion

**Documentation:**
- `build/notes/archive/technical-briefing-local-history-claude-code-codex.md` - Codex format specs
- `scripts/README.md` - Document Codex migration support

**Test data:**
- Old Claude transcripts: `~/.claude/projects/-Users-rob-code-contextify/` (33 files)
- New Claude transcripts: `~/.claude/projects/-Users-rob-code-projects-contextify/` (33 files)
- Codex transcripts: **Location TBD** (Task 1)

---

## Testing Plan

### Phase 1: Discovery
1. Find Codex storage location on this machine
2. Count how many Codex sessions exist for contextify project
3. Verify `session_meta.payload.cwd` contains project path

### Phase 2: Provider Implementation
1. Implement `CodexTranscriptProvider`
2. Register in `ConversationMonitor`
3. Build and run app
4. Open Transcripts → should show Claude + Codex transcripts
5. Verify counts match discovery phase

### Phase 3: Migration Script
1. Create test Codex session with old path
2. Run migration script
3. Verify `payload.cwd` updated to new path
4. Verify backup created
5. Test with real data

---

## Git State

**Branch:** `feature/transcript-inventory`

**Recent commits:**
```
7cd39f4 feat(scripts): add transcript migration utility
305b907 fix(ui): replace NavigationSplitView with HSplitView
bee7f6c fix(ui): resolve Swift 6 ForEach type inference issues
af828ae feat(ui): integrate transcripts into timeline view
b65aa3c feat(monitor): use ProjectContext for worktree-aware session
23d0aea feat(timeline): add line number tracking to timeline entries
b07d9d5 feat(ui): add TranscriptInventoryView with NavigationSplitView
2e179a5 feat(sources): add ProjectContext support for multi-worktree
deb4315 feat(core): add ProjectContext with git worktree discovery
```

**Build status:** ✅ Compiles cleanly (Swift 6 strict concurrency)

---

## Success Criteria

**Transcripts:**
- [ ] Shows Codex transcripts alongside Claude Code transcripts
- [ ] Correct provider icon for Codex (different from Claude)
- [ ] Clicking Codex transcript shows detail view with metadata
- [ ] Search works across both providers

**Migration Script:**
- [ ] Finds Codex transcripts matching old path
- [ ] Rewrites `payload.cwd` to new path
- [ ] Creates backup before modifying
- [ ] Summary shows Codex file count separately

**Integration:**
- [ ] No breaking changes to existing Claude Code functionality
- [ ] All 33 migrated Claude transcripts still work
- [ ] App can monitor Codex transcripts (if already supported)

---

## Continuation Prompt for Next LLM

```
I'm working on Contextify, a macOS SwiftUI app that monitors AI coding assistant
transcripts. I've just built a Transcripts feature that discovers all
transcripts for a project, including git worktrees.

Current state:
- ✅ Claude Code transcripts fully supported (discovery + migration)
- ❌ Codex/AI CLI transcripts not yet supported

Please read:
1. build/notes/archive/technical-brief-transcript-inventory-codex-support.md
   (this file - full context on what's built and what's needed)

2. build/notes/archive/technical-briefing-local-history-claude-code-codex.md
   (Codex JSONL format specification)

Tasks:
1. Find where Codex stores transcripts on this machine
2. Implement CodexTranscriptProvider following the existing ClaudeTranscriptProvider pattern
3. Extend scripts/migrate-transcripts.sh to handle Codex sessions
4. Test with real data

The codebase compiles cleanly with Swift 6 strict concurrency. Follow existing
patterns, make atomic commits, and test thoroughly.

Start by locating Codex transcripts on this machine.
```

---

## Additional Notes

### Why This Matters

Users often work with both Claude Code and Codex on the same project. The Transcripts should show **all** AI assistant activity, not just one tool. This provides:

1. **Complete history** - See every AI session across tools
2. **Better context** - Understand work done in different tools
3. **Migration support** - Don't lose Codex history when moving projects
4. **Future-proofing** - Easy to add more providers (Cursor, Aider, etc.)

### Known Constraints

- Codex storage location is config-dependent (not documented publicly)
- Codex sessions may not have explicit project markers beyond `cwd`
- Performance: Parsing all JSONL files to find `session_meta` could be slow
  - Consider: Caching discovered sessions
  - Consider: Indexing Codex sessions on first run

### Open Questions

1. **Does Codex organize sessions by date/time folders?**
   - Affects discovery strategy

2. **Can Codex sessions span multiple working directories?**
   - If yes, need to track directory changes within session

3. **Does the migration script need to update git fields in Codex?**
   - `payload.git.repository_url` might also reference old path

4. **Should we cache Codex session discovery?**
   - Parsing many JSONL files on every refresh could be slow
   - Consider: Store discovered sessions in UserDefaults with timestamps
