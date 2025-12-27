# Project Misattribution Investigation: Technical Brief

**Date:** 2025-12-27
**Status:** Root cause identified
**Priority:** P1 (affects user-visible data integrity)

## Executive Summary

Transcript entries from `/Users/rob/code/projects/contextify-worker-bee` are appearing in the timeline for `/Users/rob/code/projects/contextify`. The root cause is a **session ID collision** when Claude Code resumes sessions across different working directories, combined with Contextify's file path lookup logic.

## Evidence of Misattribution

### Database Evidence

Entry `0316e978-0b74-4530-aef1-c719cfc0c48a`:
- **Content:** `<bash-stdout>/Users/rob/code/projects/contextify-worker-bee</bash-stdout>`
- **Assigned project:** `contextify` (root: `/Users/rob/code/projects/contextify`)
- **Transcript file path in DB:** `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/84f46bc9-5b47-4df8-bc50-7098d1a7aea2.jsonl`
- **Entry timestamp:** 2025-12-27 08:22:18

### File System Evidence

The same session ID `84f46bc9-5b47-4df8-bc50-7098d1a7aea2` exists in TWO locations:

| Location | Size | Last Modified | Content |
|----------|------|---------------|---------|
| `-Users-rob-code-projects-contextify/84f46bc9...` | 1.3 MB | Dec 27 00:17 | Original session in main project |
| `-Users-rob-code-projects-contextify-worker-bee/84f46bc9...` | 4.0 MB | Dec 27 08:36 | Resumed session in worker-bee |

### Database Transcript Record

The transcript record `322BB90E-CFDF-4EF2-B65A-B93C3F5B5E32` shows:
- **file_path:** Points to the contextify (main) location
- **file_size:** `4094334` - Matches the worker-bee file (4MB), NOT the main file (1.3MB)
- **line_count:** `812` - More lines than exist in the main file
- **last_modified:** `1766853408` (08:36) - Matches worker-bee modification time

**Conclusion:** The database record has the WRONG file path but file stats (size, mtime, line_count) match the file in a DIFFERENT location.

## Root Cause Analysis

### Claude Code Session Resume Behavior

When a user resumes a Claude Code session (e.g., via `/handoff`) from a different working directory:

1. Claude Code reuses the same session ID (`84f46bc9-5b47-4df8-bc50-7098d1a7aea2`)
2. New transcript entries are written to the CURRENT working directory's project folder
3. This creates a file with the same name in a different project folder
4. The first few entries may still show the ORIGINAL cwd in their JSON

### Contextify's Handling

1. Discovery finds the transcript file in `-Users-rob-code-projects-contextify/`
2. Creates a transcript record with that file path
3. Later, when the file is "updated" (actually a different file with same name in worker-bee), the watcher or hoover reads from the WRONG file
4. The session_id matches, so entries get ingested into the existing transcript record
5. These entries have content from worker-bee but are associated with the main project

### The Specific Bug Flow

```
1. User runs Claude in /contextify -> transcript 84f46bc9... created in -Users-...-contextify/
2. Contextify discovers transcript, creates DB record pointing to -contextify/84f46bc9...
3. User resumes session from /contextify-worker-bee with /handoff
4. Claude writes to NEW file: -Users-...-contextify-worker-bee/84f46bc9...
5. File watcher sees "update" to 84f46bc9... (by session ID match?)
6. Hoover reads from worker-bee file but associates with contextify project
7. Entries appear in wrong project timeline
```

## Related Code Paths

### File Lookup Chain

1. **LightweightDiscoveryService.swift** (lines 260-280)
   - `resolveClaudeProjectPath()` uses hash folder name to find transcripts
   - No handling for same session ID across different projects

2. **FastPathIngestionCoordinator.swift** (lines 464-520)
   - `ingestProjectJIT()` uses `project.transcriptFiles` from discovery
   - Calls `orchestrator.upsertTranscripts()` with discovered file paths

3. **TranscriptWatcher.swift** (lines 253+)
   - `processFileChange()` triggered by FSEvents on transcript files
   - Uses transcript ID to lookup, may not verify file path matches

4. **HooverEngine.swift** (lines 305-400)
   - `hooverTranscript()` receives `Transcript` model and `fileURL`
   - Trusts that fileURL matches transcript.filePath

### Project Identity Logic

**ProjectIdentity.swift** (lines 58-113):
- `reverseManglePath()` extracts CWD from transcript JSONL
- Handles Claude Code mangled directory names
- Does NOT handle session ID collisions across projects

## Known Issue Tracking

This bug was already identified as P1-WORKTREE in TODOS.md (commit `38cc6b88`):

```markdown
- [ ] #P1-WORKTREE: Investigate bug where conversations from git worktrees may not display properly
```

However, the root cause is different than suspected:
- Original hypothesis: Worktree `.git` file handling
- Actual cause: Session ID collision during `/handoff` resume across directories

## Missing Test Coverage

### No tests for:
1. Same session ID appearing in multiple project folders
2. Session resume across different working directories
3. File path mismatch between discovery and actual file content
4. CWD changes mid-session in transcript entries

### Relevant test files that exist:
- `ProjectDiscoveryServiceTests.swift` - Tests path resolution but not collisions
- `AppStateOrchestratorTests.swift` - Tests canonicalRootPath but not session ID handling
- `LightweightDiscoveryMergeTests.swift` - Tests project merging but not this scenario

## Recommended Fix Approach

### Option A: Session ID Scoping (Recommended)

Make session IDs project-scoped by including project hash in the ID:
```swift
// Instead of just session ID:
"84f46bc9-5b47-4df8-bc50-7098d1a7aea2"

// Use compound key:
"-Users-rob-code-projects-contextify-worker-bee:84f46bc9-5b47-4df8-bc50-7098d1a7aea2"
```

**Pros:**
- Clean separation of session continuations across projects
- No database migration needed if stored as new transcripts

**Cons:**
- May create duplicate entries if same session was already ingested
- Need to handle legacy data

### Option B: File Path Verification

Before hoovering a transcript, verify the file path in the database matches the actual file being read:
```swift
func hooverTranscript(_ transcript: Transcript, fileURL: URL, ...) throws -> HooverOutcome {
  guard transcript.filePath == fileURL.path else {
    log.warning("[HOOVER] File path mismatch: DB=\(transcript.filePath) actual=\(fileURL.path)")
    throw HooverError.filePathMismatch
  }
  // ... continue
}
```

**Pros:**
- Catches mismatches early
- Simple to implement

**Cons:**
- Doesn't fix the underlying discovery issue
- May miss legitimate file moves

### Option C: CWD-Based Project Assignment

When ingesting entries, use the `cwd` field from each entry to determine project assignment:
```swift
// For each entry in the transcript:
if let entryCwd = entry.cwd, entryCwd != currentProject.rootPath {
  // This entry belongs to a different project
  let correctProjectId = try orchestrator.getOrCreateProject(rootPath: entryCwd).projectId
  entry.projectId = correctProjectId
}
```

**Pros:**
- Most accurate - uses the actual working directory at time of entry
- Handles mid-session cwd changes correctly

**Cons:**
- More complex
- Could fragment sessions across projects (user intent may be to keep session together)

### Option D: Duplicate Detection

During discovery, detect when the same session ID file exists in multiple project folders:
```swift
// In LightweightDiscoveryService
let allSessionIds = collectAllSessionIds()
let duplicates = findDuplicates(allSessionIds)
for dup in duplicates {
  log.warning("[DISCOVERY] Session \(dup.sessionId) found in multiple projects: \(dup.paths)")
  // Create separate transcript records for each, or merge with CWD-based sorting
}
```

**Pros:**
- Explicit handling of the edge case
- Can warn users about potential confusion

**Cons:**
- Detection logic adds complexity
- Still need to decide how to handle the duplicates

## Immediate Mitigation

Until a fix is implemented, the misattributed entries can be identified and corrected:

```sql
-- Find entries where cwd doesn't match project root_path
SELECT
    te.id,
    te.cwd as entry_cwd,
    p.root_path as project_root,
    t.file_path
FROM transcript_entries te
JOIN projects p ON te.project_id = p.id
JOIN transcripts t ON te.transcript_id = t.id
WHERE te.cwd IS NOT NULL
AND te.cwd != p.root_path
AND te.cwd != '';
```

## Related Commits

| Commit | Date | Description |
|--------|------|-------------|
| `38cc6b88` | 2025-11-19 | docs(todos): add P1 item to investigate git worktree bug |
| `b8b748a2` | Recent | chore: add worktree registry and tooling awareness |
| `a9ed7d0b` | Recent | fix(codex): add fallback bucket for CWD extraction failures |
| `b7f91000` | Recent | fix(codex): integrate longest-prefix remapping |
| `5f6b18e2` | Recent | fix(ingestion): harden FastPath cancel/notify semantics |

## Files to Review

1. `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`
2. `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`
3. `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`
4. `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/ProjectIdentity.swift`
5. `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Database/HooverEngine.swift`

## Acceptance Criteria for Fix

1. Session resume across working directories creates separate transcript records per project
2. Entries are attributed to the project matching their `cwd` field
3. Timeline shows correct conversations for each project
4. Existing misattributed entries are corrected (migration or cleanup script)
5. Add test coverage for session ID collision scenarios
