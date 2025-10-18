# Contextify TODOs

This document tracks feature ideas, enhancements, and known issues for future development.

## Active Development

### P0 - In Progress
- Line number tracking for narrative composition

### P1 - Next Up
- Narrative composition from selected timeline entries

## Backlog

### Technical Debt / Optimizations

#### Phase 2: LLM Session Management & Safety Optimizations
**Status:** Deferred (Post-P0/P1 cleanup)
**Priority:** High (P1.5) - Should proceed before new features
**Effort:** Medium-Large (~3-5 sessions)
**Risk:** Medium (requires careful actor isolation)
**Documentation:** [`build/notes/archive/phase-2-llm-optimizations.md`](build/notes/archive/phase-2-llm-optimizations.md)

Following comprehensive P0/P1 fixes (commits `b375246`, `fbe78a9`, `4941bdf`), 12 additional optimizations were identified during ultrathink review. These address **session lifecycle management**, **resource bounds**, and **operational safety** for production LLM usage.

**Why prioritize this?**
1. **Resource Efficiency**: Current unbounded controller pool leaks memory in long-running sessions
2. **Privacy Compliance**: Raw prompts logged to console may contain user data
3. **Operational Safety**: No per-session limits; risks context pollution and rate exhaustion
4. **Production Resilience**: Missing circuit breakers, cancellation handling improvements needed

**Core issues addressed:**
- Actor-isolated LRU controller pool (eliminates race conditions, bounds memory)
- Session age/request limits (automatic resource recycling)
- Log sanitization (SHA256 hashing instead of raw prompts)
- Enhanced cancellation safety (prevents continuation leaks)
- Stable instruction templates (no per-message controller keys)

**Recommended phasing:**
- **Phase 2a** (High ROI, ~1 session): Session limits, log sanitization, sync simplification
- **Phase 2b** (Architectural, ~2-3 sessions): Controller pool, cancellation fixes, circuit breaker
- **Phase 2c** (Cleanup, ~1 session): Remove global counters, misc cleanup

**Why defer from Phase 1?**
Critical correctness bugs (index drift, memory leaks, retry paradoxes, error handling) are now resolved. These optimizations improve resource efficiency and resilience but don't fix observable production failures. They're important follow-up work that should happen before major new features.

**Next steps:**
1. Review detailed implementation plan in linked document
2. Schedule Phase 2a as next sprint (quick wins)
3. Plan Phase 2b for following sprint (larger refactor)

---

### Bugs

#### Horizontal Rule Alignment (UI Polish)
**Status:** Open
**Priority:** Low (visual nit)

The horizontal rule/divider in the right conversation log panel does not align vertically with the horizontal rule in the main left panel. The right panel divider sits slightly lower, creating a visual misalignment.

**To Fix:**
- Adjust padding/spacing in the conversation timeline view header
- Ensure both panels have matching vertical spacing from top
- Likely a margin or padding discrepancy in SwiftUI layout

**Files to Check:**
- `ConversationTimelineView.swift` - Timeline panel layout
- Main content view layout - Left panel divider position

#### Codex Icon Color Incorrect
**Status:** Completed (2025-10-10)
**Priority:** Medium (visual accuracy)

~~When Codex log messages are being created/displayed, the Codex icon appears in blue but should be white (or the correct theme color).~~

**Solution Implemented:**
Changed Codex CLI provider color from `.blue` to `.white` in `TimelineEntryRow.swift` `providerColor()` function. Claude Code icon remains orange.

#### Provider Name in Timeline Summaries
**Status:** Completed (2025-10-10)
**Priority:** Medium (accuracy)

~~Timeline entry summaries for Codex messages incorrectly say "Claude [did something]" when they should say "Codex [did something]" to accurately reflect which AI provider performed the action.~~

**Solution Implemented:**
- Added `provider` parameter throughout LLM summarization pipeline
- Updated LLM instructions in `instructionsForTimeline()` to dynamically use provider displayName
- Modified prefix policies, fast-path acknowledgements, and fallback summaries
- Marked `Provider.displayName` as `nonisolated` for cross-actor access
- Now correctly generates summaries like "Codex CLI proposes..." for Codex entries

**Files Modified:**
- `FoundationLLM.swift` - Added provider parameter to all summarization methods
- `ConversationMonitor.swift` - Pass provider from activeSession
- `TimelineCacheMissGenerator.swift` - Pass provider to LLM calls
- `TimelineModels.swift` - Made displayName nonisolated

#### System Message Provider Name
**Status:** Completed (2025-10-10)
**Priority:** Low (polish)

~~System messages like "Switched to a new conversation" should include the provider name: "Switched to a new Claude Code conversation" or "Switched to a new Codex conversation" for clarity.~~

**Solution Implemented:**
Updated `emitProviderSwitchEntry()` in `ConversationMonitor.swift` to include provider displayName in system messages. Now shows "Switched to a new Codex CLI conversation" etc.

#### Timeline Entry Tense Inconsistency
**Status:** Completed (2025-10-10)
**Priority:** Medium

~~Timeline entries are generated immediately when messages arrive, using present tense ("Claude proposes...", "Claude implements..."). This looks odd because they're historical log entries that should use past tense ("Claude proposed...", "Claude implemented...").~~

**Solution Implemented:**
Timeline cache now stores both present and past forms of each summary, generated by the LLM. Entries use `selectedForm` to toggle between tenses:
- Present continuous for active work: "Claude is implementing..."
- Past simple for completed work: "Claude implemented..."

The `flipTenseToPast()` method can convert entries to past tense without re-calling the LLM by simply toggling the `selectedForm` field. This enables natural progression from active → completed state.

**Implementation:**
- Dual-form generation in `summarizeTimelineWithForms()`
- Cache storage in `CachedTimelineEntry` with `presentForm` and `pastForm`
- Tense selection via `selectedForm` enum (`.presentContinuous` or `.pastSimple`)
- Fallback regex transformation for backward compatibility

### Performance

#### Timeline Summary Caching
**Status:** Completed (2025-10-10)
**Priority:** High
**Branch:** feature/timeline-cache

~~Timeline entries were re-generated from scratch on every app launch by re-parsing the entire JSONL transcript and calling the LLM for each message. This was slow and expensive.~~

**Implementation Completed:**
Persistent cache system with content-based invalidation and dual-form tense storage.

**Architecture:**
- **SQL-based storage**: Timeline cache in SQLite database via GRDB
- **LLM generation**: `TimelineCacheMissGenerator` with FoundationLLM integration
- **Database location**: `~/Library/Application Support/Contextify/transcripts.db`
- **Smart invalidation** - Content hash + context window hash + generator signature
- **Per-entry caching** - Cached summaries linked to timeline entries via foreign key

**Cache Entry Structure:**
```swift
struct CachedTimelineEntry {
  let contentHash: String           // SHA256 of message content
  let windowHash: String             // SHA256 of context UUIDs
  let generatorSignature: String     // Model + version + prompt
  let disposition: Disposition       // Entry classification
  let presentForm: String            // "Claude is implementing..."
  let pastForm: String               // "Claude implemented..."
  var selectedForm: Tense            // Which to display
  let verbLemma: String?             // For future conjugation
  let generatedAt: Date
  var userEdited: Bool               // Manual override flag
  var userText: String?              // User's edited text
}
```

**Key Features:**
- ✅ Cache HIT/MISS logging with hit rate tracking
- ✅ Debounced persistence (2s) to reduce disk writes
- ✅ Synchronous flush on app termination
- ✅ Content-aware invalidation (message + context changes)
- ✅ Dual-form tense storage (no regex mutations)
- ✅ User edit support for manual corrections
- ✅ Session epoch tracking prevents cross-session contamination

**Performance Impact:**
- **Before:** ~150ms per message × N messages = slow startup
- **After:** Cache HIT = instant, only new messages call LLM
- **Typical startup:** 1-2 LLM calls instead of 20-50

### Features

#### Agent Instructions Management View
**Status:** Backlog
**Priority:** Medium
**Related:** AGENTS.md / CLAUDE.md consolidation

Build an auxiliary view to help users maintain Agent Rules v1.0 compliance and avoid documentation drift between AGENTS.md and CLAUDE.md files.

**Functionality:**
1. **File Discovery**: Scan project directory and detect all `AGENTS.md` and `CLAUDE.md` files
2. **Symlink Detection**: Check if CLAUDE.md is a symlink to AGENTS.md (recommended setup)
3. **Diff Display**: Show side-by-side comparison if files exist as separate documents
4. **Warning System**: Visual indicator (⚠️) when files have diverged or are not symlinked
5. **One-Click Actions**:
   - "Create Symlink" - Convert CLAUDE.md to symlink → AGENTS.md
   - "Merge Files" - Interactive merge with conflict resolution
   - "View Diff" - Detailed line-by-line comparison

**Integration Points:**
- **Transcript Discovery Warning**: When ConversationMonitor discovers the first Codex session focused on the same project directory, if AGENTS.md and CLAUDE.md are not set up as symlinks, show a banner warning:
  ```
  ⚠️ Multiple agent instruction files detected
  AGENTS.md and CLAUDE.md are not linked. View comparison →
  ```
- Menu item: **Tools → Agent Instructions Setup**
- Status bar indicator when drift is detected

**UI Design:**
```
┌─────────────────────────────────────────────┐
│ Agent Instructions Setup                    │
├─────────────────────────────────────────────┤
│                                             │
│ Status: ⚠️ Files are separate              │
│                                             │
│ AGENTS.md          vs          CLAUDE.md   │
│ ┌──────────────┐              ┌──────────┐ │
│ │ 175 lines    │              │ 125 lines│ │
│ │ Modified: 2h │              │ Modified:│ │
│ │              │              │  1 week  │ │
│ └──────────────┘              └──────────┘ │
│                                             │
│ [Create Symlink]  [Merge Files]  [View Diff]│
└─────────────────────────────────────────────┘
```

**Technical Notes:**
- Use `FileManager` to detect symlinks (`FileManager.default.destinationOfSymbolicLink(atPath:)`)
- Leverage SwiftUI `TextEditor` for diff display
- Store user preference for "don't warn again" in UserDefaults
- Follow Agent Rules v1.0 spec (AGENTS.md as single source of truth)

#### Configurable Database Location with Cloud Sync & Encryption
**Status:** Backlog
**Priority:** Medium-High
**Related:** Database architecture, cloud storage, security

Allow users to configure where the SQLite database is stored, with support for cloud sync providers (Dropbox, iCloud Drive) and optional encryption for sensitive transcript data.

**Current Behavior:**
- Database location: `~/Library/Application Support/Contextify/transcripts.db` (fixed)
- No encryption (plain SQLite)
- No cloud sync support

**Proposed Functionality:**

1. **Custom Database Location**
   - Settings UI: "Database Location" preference pane
   - Options:
     - Default: `~/Library/Application Support/Contextify/` (current)
     - Dropbox: `~/Dropbox/Apps/Contextify/`
     - iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Contextify/`
     - Custom: User-selected folder (via NSOpenPanel)
   - Validation: Check write permissions, available space (>100MB)
   - Migration: Copy existing database to new location with progress indicator

2. **Cloud Sync Integration**
   - **Dropbox**: Direct folder path integration
     - Detect Dropbox folder: `~/.dropbox/info.json` or standard `~/Dropbox`
     - Sync status indicator (syncing/synced/error)
     - Conflict resolution: Last-write-wins with backup
   - **iCloud Drive**: Native CloudKit integration
     - Use `NSFileCoordinator` for iCloud document handling
     - Automatic conflict resolution via iOS/macOS file coordination
     - Status: "Uploading", "Downloading", "Up to Date"
   - **Custom Location**: Basic file monitoring, no special sync handling

3. **Database Encryption**
   - **SQLCipher integration**: Open-source SQLite encryption extension
   - **Options**:
     - None (default, plain SQLite)
     - Encrypted (AES-256 with user-provided passphrase)
   - **Passphrase Management**:
     - Store in macOS Keychain (secure, survives app reinstall)
     - Prompt on first launch if encrypted database detected
     - "Change Passphrase" option in settings
   - **Migration Path**:
     - Encrypt existing database: `ATTACH DATABASE 'encrypted.db' AS encrypted KEY 'passphrase'; SELECT sqlcipher_export('encrypted');`
     - Decrypt database: Reverse process
   - **Performance**: SQLCipher adds ~5-15% overhead (acceptable for transcript data)

**Technical Architecture:**

```swift
// DatabaseManager.swift enhancement
struct DatabaseConfig {
  enum Location {
    case appSupport  // Default
    case dropbox
    case iCloud
    case custom(URL)
  }

  enum Encryption {
    case none
    case sqlcipher(passphrase: String)
  }

  var location: Location
  var encryption: Encryption
}

class DatabaseManager {
  static let shared = DatabaseManager()

  private var config: DatabaseConfig

  func reconfigureDatabase(newConfig: DatabaseConfig) throws {
    // 1. Close current connection
    // 2. Migrate database to new location (if changed)
    // 3. Apply/remove encryption (if changed)
    // 4. Reopen with new config
    // 5. Notify observers (reload UI)
  }

  private func openWithEncryption(path: String, passphrase: String?) throws -> DatabasePool {
    if let pass = passphrase {
      // SQLCipher: PRAGMA key = 'passphrase';
      let config = Configuration()
      config.prepareDatabase { db in
        try db.execute(sql: "PRAGMA key = '\(pass)'")
      }
      return try DatabasePool(path: path, configuration: config)
    } else {
      return try DatabasePool(path: path)
    }
  }
}
```

**UI Design:**
```
┌───────────────────────────────────────────┐
│ Database Settings                         │
├───────────────────────────────────────────┤
│                                           │
│ Location:                                 │
│   ( ) Application Support (Default)       │
│   ( ) Dropbox                             │
│   (•) iCloud Drive                        │
│   ( ) Custom...                           │
│                                           │
│ Current: ~/Library/Mobile Documents/...  │
│ Status: ☁️ Synced (2 minutes ago)         │
│                                           │
│ [Change Location...]                      │
│                                           │
│ ─────────────────────────────────────────│
│                                           │
│ Encryption:                               │
│   [✓] Encrypt database                    │
│                                           │
│ Passphrase: **************                │
│                                           │
│ [Change Passphrase...]                    │
│                                           │
│ ⚠️ Warning: Encryption adds ~10% overhead│
│ and requires passphrase on every launch. │
│                                           │
└───────────────────────────────────────────┘
```

**Implementation Phases:**

**Phase 1: Custom Location (No Encryption)**
- Add location selector to preferences
- Implement database migration logic
- Handle file permissions and validation
- Update DatabaseManager to support configurable paths
- Effort: ~2-3 days

**Phase 2: Cloud Sync Support**
- Dropbox folder detection and monitoring
- iCloud Drive integration with NSFileCoordinator
- Sync status UI indicators
- Conflict resolution strategies
- Effort: ~3-5 days

**Phase 3: Encryption**
- Integrate SQLCipher library (SPM)
- Implement passphrase management (Keychain)
- Add encrypt/decrypt migration workflows
- Performance testing and optimization
- Effort: ~3-4 days

**Security Considerations:**
- **Passphrase Strength**: Require minimum 12 characters, suggest passphrase generator
- **Keychain Storage**: Use `kSecAttrAccessibleWhenUnlocked` (balance security/UX)
- **Backup Warning**: Encrypted databases cannot be recovered without passphrase
- **Cloud Sync + Encryption**: Warn users about syncing encrypted data (safe, but passphrase must match on all devices)

**Edge Cases:**
- **Dropbox/iCloud not installed**: Detect and disable option, show setup instructions
- **Migration failure**: Keep original database intact, rollback on error
- **Sync conflicts**: Last-write-wins with `.conflict` backup file
- **Encryption password forgotten**: No recovery (data loss), require explicit acknowledgement

**Related Work:**
- See `build/notes/technical-reference/sql-backend-architecture.md` for current database design
- SQLCipher documentation: https://www.zetetic.net/sqlcipher/

#### LLM Processing Status Bar
**Status:** Backlog
**Priority:** Medium
**Related:** Timeline cache, Apple Intelligence integration, user feedback

Add a status bar to the main window that shows real-time LLM processing status and Apple Intelligence availability.

**Current Behavior:**
- No visibility into LLM processing queue
- No indication whether Apple Intelligence is available
- Users don't know when summaries are being generated
- Cache miss generation happens silently in background

**Proposed Functionality:**

1. **LLM Processing Queue Indicator**
   - **Display**: Compact status in window footer or header
   - **Information shown**:
     - Queue depth: "Processing 12 summaries..." or "Queue empty"
     - Current batch: "Generating summaries (3/10)"
     - Completion estimate: "~6s remaining" (based on 2s/batch)
   - **Visual states**:
     - Idle: No indicator (or subtle "✓ Up to date")
     - Processing: Progress spinner + count
     - Error: Warning icon + "LLM unavailable"
   - **Interaction**: Click to show detailed queue viewer (optional)

2. **Apple Intelligence Availability Indicator**
   - **Status types**:
     - Online: Green dot + "Apple Intelligence: Available"
     - Offline: Gray dot + "Apple Intelligence: Unavailable (requires macOS 26+)"
     - Error: Red dot + "Apple Intelligence: Error" (with details in tooltip)
   - **Tooltip on hover**: Show model details
     - "Using FoundationLLM (on-device)"
     - "Model: GPT-4o equivalent"
     - "Session: Timeline summarization (user/assistant)"
   - **Placement**: Next to queue indicator or in separate section

**UI Design Options:**

**Option A: Footer Status Bar (Recommended)**
```
┌────────────────────────────────────────────────┐
│ [Timeline entries...]                          │
│                                                │
│                                                │
├────────────────────────────────────────────────┤
│ ● Apple Intelligence  │  Processing 12 items  │
│   Available           │  (~6s remaining)      │
└────────────────────────────────────────────────┘
```

**Option B: Header Compact**
```
┌────────────────────────────────────────────────┐
│ Project: Contextify    ●AI  ⚙️12  [Settings]  │
├────────────────────────────────────────────────┤
│ [Timeline entries...]                          │
```

**Option C: Hover Popover**
```
[Mouse over "⚙️12" icon]
┌─────────────────────────────┐
│ LLM Processing Queue        │
├─────────────────────────────┤
│ Pending: 12 summaries       │
│ Current batch: 3/10         │
│ Est. time: ~6 seconds       │
│                             │
│ Apple Intelligence: ●Online │
│ Model: FoundationLLM        │
└─────────────────────────────┘
```

**Technical Implementation:**

```swift
// StatusBarViewModel.swift (new)
@MainActor
@Observable
final class StatusBarViewModel {
  private let monitor: ConversationMonitor
  private let generator: TimelineCacheMissGenerator?

  // LLM Queue Status
  private(set) var queueDepth: Int = 0
  private(set) var isProcessing: Bool = false
  private(set) var estimatedSecondsRemaining: Int = 0

  // Apple Intelligence Status
  enum AIStatus {
    case available
    case unavailable(reason: String)
    case error(message: String)
  }
  private(set) var aiStatus: AIStatus = .unavailable(reason: "macOS 26+ required")

  init(monitor: ConversationMonitor, generator: TimelineCacheMissGenerator?) {
    self.monitor = monitor
    self.generator = generator

    // Poll generator for queue stats
    startPolling()

    // Check AI availability
    checkAppleIntelligenceAvailability()
  }

  private func startPolling() {
    Task { @MainActor in
      while true {
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        await updateQueueStatus()
      }
    }
  }

  private func updateQueueStatus() async {
    guard let gen = generator else { return }

    // Call actor method to get queue stats
    let stats = await gen.getQueueStats()

    self.queueDepth = stats.pending
    self.isProcessing = stats.isProcessing

    // Estimate time: pending items * 2s per batch / 10 items per batch
    let batchesRemaining = (stats.pending + 9) / 10
    self.estimatedSecondsRemaining = batchesRemaining * 2
  }

  private func checkAppleIntelligenceAvailability() {
    if #available(macOS 26.0, *) {
      #if canImport(FoundationModels)
      Task {
        do {
          // Try to create a test session to verify availability
          let testAvailable = await FoundationLLM.shared.checkAvailability()

          if testAvailable {
            aiStatus = .available
          } else {
            aiStatus = .unavailable(reason: "Model not loaded")
          }
        } catch {
          aiStatus = .error(message: error.localizedDescription)
        }
      }
      #else
      aiStatus = .unavailable(reason: "FoundationModels not available")
      #endif
    } else {
      aiStatus = .unavailable(reason: "Requires macOS 26+")
    }
  }
}

// Add to TimelineCacheMissGenerator.swift
actor TimelineCacheMissGenerator {
  // ... existing code ...

  struct QueueStats: Sendable {
    let pending: Int
    let isProcessing: Bool
    let currentBatchSize: Int
  }

  func getQueueStats() -> QueueStats {
    QueueStats(
      pending: pendingMisses.count,
      isProcessing: isProcessing,
      currentBatchSize: isProcessing ? maxBatchSize : 0
    )
  }
}

// Add to FoundationLLM.swift
@available(macOS 26.0, *)
actor FoundationLLM {
  // ... existing code ...

  func checkAvailability() async -> Bool {
    #if canImport(FoundationModels)
    do {
      // Try to create a minimal session
      let testInstructions = "You are a test assistant."
      let controller = SessionController(instructions: testInstructions)

      // Quick test prompt
      _ = try await controller.respond(to: "Test")

      return true
    } catch {
      return false
    }
    #else
    return false
    #endif
  }
}
```

**StatusBarView.swift (new SwiftUI component):**
```swift
struct StatusBarView: View {
  @Environment(StatusBarViewModel.self) private var viewModel

  var body: some View {
    HStack(spacing: 16) {
      // Apple Intelligence Status
      HStack(spacing: 6) {
        Circle()
          .fill(aiStatusColor)
          .frame(width: 8, height: 8)

        Text(aiStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .help(aiStatusTooltip)

      Divider()
        .frame(height: 12)

      // LLM Queue Status
      if viewModel.isProcessing {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)

          Text("Processing \(viewModel.queueDepth) \(viewModel.queueDepth == 1 ? "summary" : "summaries")")
            .font(.caption)
            .foregroundStyle(.secondary)

          if viewModel.estimatedSecondsRemaining > 0 {
            Text("(~\(viewModel.estimatedSecondsRemaining)s)")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
      } else if viewModel.queueDepth > 0 {
        Text("\(viewModel.queueDepth) pending")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.caption)
          Text("Up to date")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.background.secondary)
  }

  private var aiStatusColor: Color {
    switch viewModel.aiStatus {
    case .available: return .green
    case .unavailable: return .secondary
    case .error: return .red
    }
  }

  private var aiStatusText: String {
    switch viewModel.aiStatus {
    case .available: return "Apple Intelligence"
    case .unavailable: return "AI Unavailable"
    case .error: return "AI Error"
    }
  }

  private var aiStatusTooltip: String {
    switch viewModel.aiStatus {
    case .available:
      return "Apple Intelligence is available\nUsing FoundationLLM for on-device summaries"
    case .unavailable(let reason):
      return "Apple Intelligence unavailable\n\(reason)"
    case .error(let message):
      return "Apple Intelligence error\n\(message)"
    }
  }
}
```

**Integration in ContentView.swift:**
```swift
var body: some View {
  VStack(spacing: 0) {
    // Existing content
    header
    ConversationTimelineView()

    // NEW: Status bar
    StatusBarView()
      .environment(statusBarViewModel)
  }
}
```

**Implementation Phases:**

**Phase 1: Basic Queue Display** (~1 day)
- Add `getQueueStats()` to TimelineCacheMissGenerator
- Create StatusBarViewModel with polling
- Simple UI showing queue depth + processing state
- Footer placement

**Phase 2: Apple Intelligence Indicator** (~1 day)
- Add `checkAvailability()` to FoundationLLM
- AI status detection on macOS 26+
- Graceful fallback for older OS versions
- Tooltip with detailed info

**Phase 3: Polish & Interactivity** (~1 day)
- Animated transitions for state changes
- Click to show detailed queue viewer (optional)
- Time estimate refinement (track actual LLM latency)
- Preference to hide/show status bar

**User Benefits:**
- **Transparency**: Users know when LLM is working in background
- **Troubleshooting**: Immediately see if Apple Intelligence is unavailable
- **Expectations**: Time estimates help users understand when summaries will appear
- **Confidence**: "Up to date" indicator confirms all summaries are cached

**Edge Cases:**
- **macOS < 26**: Show "AI Unavailable (requires macOS 26+)"
- **FoundationModels unavailable**: Show "AI Unavailable (system requirement)"
- **Large queue (>100)**: Show "Processing many items..." instead of exact count
- **LLM error**: Show error state with tooltip explaining issue
- **Generator nil**: Hide status bar or show "Not monitoring"

**Performance Considerations:**
- Polling interval: 500ms (balance responsiveness vs CPU)
- Use actor isolation for thread-safe queue access
- No UI updates if values unchanged (SwiftUI auto-optimizes)

**Related Work:**
- See `build/notes/technical-reference/timeline-cache-llm-architecture.md` for LLM integration details
- See `build/notes/technical-reference/conversation-monitor-state-architecture.md` for state management

#### Conversation Log Enhancements

##### 1. Date Separator Between Messages
**Status:** Backlog
**Priority:** Medium (UX polish)

Add visual date separators when the timeline crosses into a new day, similar to macOS Messages app.

**Example:**
```
Claude proposes to implement caching
You requested Claude to proceed
─────── Tuesday, October 15 ───────
Claude implements the cache layer
You asked about performance
─────── Wednesday, October 16 ──────
Claude optimizes the query
```

**Implementation:**
- Check for date boundary between consecutive timeline entries
- Insert a visual separator with formatted date
- Use system date formatting (respects user's locale)
- Style: subtle divider with centered date text
- Consider: "Today", "Yesterday" for recent dates

**Files to modify:**
- `ConversationTimelineView.swift` - Add date separator logic
- Check timestamp difference between entries
- Insert Text/Divider view when date changes

##### 2. Reduce Assistant Entry Density
**Status:** Active Development
**Priority:** High
**Branch:** feature/timeline-completion-improvements

The conversation log shows too many assistant entries for a single directive/response cycle (e.g., 14 entries before a completion marker). This creates excessive noise and makes it hard to follow the conversation flow.

**Root cause:**
Claude Code generates many small text blocks as the assistant works, each becoming a timeline entry. This includes acknowledgements, progress updates, and intermediate thoughts.

**Proposed solutions:**
1. **Disposition-based filtering** (recommended): Use the LLM's `disposition` field to filter entries:
   - Always show: `completion`, `proposal`, `question`, `refusal`
   - Sometimes show: `analysis` (if >100 chars or first in sequence)
   - Suppress: `ack`, `wip` (work-in-progress)

2. **Time-based throttling**: Suppress assistant entries within N seconds of the previous one (unless completion)

3. **Content-based suppression**: Skip very short assistant messages (<50 chars) unless they're completions

**Implementation approach:**
Add filtering logic in `addAssistantTextEntry()` based on `disposition` from `GuidedTimelineSummary`.

##### 2. Avoid Sequential Completed Entries
**Status:** Completed (2025-10-10)
**Priority:** Medium

~~The conversation log currently can show multiple sequential "completed" entries, which creates redundancy and clutters the timeline.~~

**Example of redundancy:**
```
✓ Claude marks the final todo as completed.
---
Perfect! The build succeeded with no errors. Let me mark the final todo as completed.

✓ Claude successfully converted the Transcript Inventory to an independent window...
---
## Implementation Complete!
I've successfully converted the Transcript Inventory from a modal sheet to an independent window...
```

**Proposed Solution:**
When processing timeline entries marked as "completed":
1. Check if the previous entry is also marked as "completed"
2. If so, merge or suppress the second completion entry
3. Consider consolidating the summaries or only showing the more detailed one
4. Possibly use a different indicator (e.g., "Progress: ..." vs "✓ Completed")

**Implementation considerations:**
- May need to distinguish between "task completed" vs "subtask completed"
- Could use confidence scoring on completion detection
- Should preserve important context even when merging

##### 2. Timeline Verbosity Settings
**Status:** Backlog
**Priority:** Medium

Add user-configurable verbosity control for timeline entries to balance detail vs clarity.

**Proposed UI:**
- Settings panel with a slider control
- 4 verbosity levels from minimal to verbose
- Real-time preview showing what gets filtered at each level
- Persisted preference in UserDefaults

**Verbosity Levels:**

| Level | Name | Suppressed Dispositions | Kept Dispositions | Est. Entries/Cycle |
|-------|------|------------------------|-------------------|-------------------|
| 0 | Minimal | ack, wip, analysis, proposal | completion, question, refusal | 1-2 |
| 1 | Balanced (Default) | ack, wip, analysis | completion, proposal, question, refusal | 3-5 |
| 2 | Detailed | ack, wip | completion, analysis, proposal, question, refusal | 6-8 |
| 3 | Verbose | (none) | (all) | 10-14 |

**Implementation:**
- Add `TimelineVerbosity` enum with levels 0-3
- Store preference in `MonitorConfig` or `HUDPreferences`
- Update `addAssistantTextEntry()` to check verbosity level
- Add settings UI in ConversationTimelineView menu or separate preferences window

**Current Implementation:**
Level 1 (Balanced) is hard-coded in `ConversationMonitor.swift:630`

##### 3. Task Duration Tracking
**Status:** Completed (2025-10-10)
**Priority:** Medium
**Depends on:** Enhancement #1 (completed entry detection)

Once we can reliably identify completed entries, show the elapsed time from the user's request to completion.

**Proposed UI:**
- Show duration next to completed entries (e.g., "✓ Completed in 2m 34s")
- Add small arrow icon (↑) next to completed entries
- Clicking arrow scrolls to and highlights the original request in the log
- Hovering shows timestamp of request and completion

**Implementation considerations:**
- Need to track correlation between user requests and completion events
- Store request UUID with each task
- Calculate duration from first relevant assistant message to completion marker
- Handle cases where tasks span multiple timeline entries

##### 4. Activity Log (Git Events Integration)
**Status:** Backlog
**Priority:** Medium
**Category:** New Feature

Expand the conversation log into a unified "activity" log that includes git events alongside AI conversation entries, creating a complete project activity timeline.

**Concept:**
Instead of just showing what Claude/Codex did, show the full context of project activity:
- AI conversation entries (current)
- Git commits (with message, author, files changed)
- Git branch switches
- Git merges/rebases
- Other version control events

**Proposed Features:**
1. **Unified Timeline**: Interleave git events with conversation entries in chronological order
2. **Event Filtering**: Toggle visibility of different event types
   - Show/hide: Commits, Branches, AI messages, Tool calls, etc.
   - Filter by author (user, Claude, Codex, other collaborators)
   - Filter by file/directory affected
3. **Git Event Display**:
   - Commit entry: "📝 Committed: [message]" with hash, author, timestamp
   - Branch switch: "🔀 Switched to branch: [name]"
   - Merge: "🔗 Merged [branch] into [branch]"
4. **Correlation**:
   - Link AI "completed" entries to the commits they generated
   - Show which conversation led to which code changes
   - Highlight when AI suggestions were committed vs modified

**Implementation Considerations:**
- Monitor `.git/` directory for changes (already doing this for branch detection)
- Parse `git log` for commit history
- Use `git reflog` for branch switches
- Add event type system: `.conversation`, `.commit`, `.branch`, `.merge`
- Extend filtering UI to support multiple event types
- Consider performance impact of git log parsing

**UI Mockup:**
```
Timeline (Filters: ✓ AI  ✓ Commits  ✓ Branches)
┌──────────────────────────────────────────┐
│ 2:34 PM  User: Fix the logging levels   │
│ 2:35 PM  ✓ Claude moved logs to debug   │
│ 2:36 PM  📝 feat: move routine logs...   │  ← Git commit
│          (3 files changed)               │
│ 2:40 PM  🔀 Switched to main             │  ← Branch change
│ 2:41 PM  🔗 Merged feature/logging       │  ← Git merge
└──────────────────────────────────────────┘
```

**Benefits:**
- Complete project context in one view
- Better understanding of what AI changes made it to main
- Easier to review and correlate work
- More useful for project retrospectives

#### Transcript Migration UI
**Status:** Backlog
**Priority:** Super Low (manual script works fine, edge case)
**Related:** `scripts/migrate-transcripts.sh`

When users move their project to a new directory (e.g., `~/code/contextify` → `~/code/projects/contextify`), Claude Code creates a new transcript directory. Old transcripts remain at the old location with outdated paths in content.

**Current Solution:**
Manual script at `scripts/migrate-transcripts.sh` that:
- Backs up old transcripts
- Copies to new location
- Rewrites all path references to new location

**Future Enhancement:**
Wrap the script in UI:
- Detect when project path has changed
- Offer to migrate old transcripts
- Show preview of what will be migrated
- One-click migration with progress indicator
- Automatic backup before migration

#### SQL Backend for Comprehensive Transcript Analysis
**Status:** Backlog
**Priority:** High (Foundation for AI-driven project insights)
**Category:** Infrastructure / Intelligence

Store all transcript entries (user messages, assistant responses, tool calls, metadata) in a local SQLite database to enable deep project analysis and intelligent assistance features.

**Grand Theory:**
By analyzing the full project history stored in a relational database, Contextify can:
- Understand project direction and velocity
- Track progress toward stated goals
- Identify patterns (abandoned features, recurring issues)
- Help users remember where they left off
- Suggest next steps based on project trajectory
- Keep commits clean and atomic
- Detect documentation drift
- Correlate code changes with conversations

**Database Schema (preliminary):**
```sql
-- Core transcript entries
CREATE TABLE transcript_entries (
  id INTEGER PRIMARY KEY,
  uuid TEXT UNIQUE NOT NULL,           -- Original message UUID
  session_id TEXT NOT NULL,             -- Conversation session
  provider TEXT NOT NULL,               -- 'claude-code', 'codex', etc.
  kind TEXT NOT NULL,                   -- 'user', 'assistant', 'system'
  timestamp DATETIME NOT NULL,
  content TEXT NOT NULL,                -- Full message content
  summary TEXT,                         -- Timeline summary
  disposition TEXT,                     -- 'completion', 'question', etc.
  display_in_timeline BOOLEAN DEFAULT 1, -- Show in UI or not
  is_completion BOOLEAN DEFAULT 0,
  is_directive BOOLEAN DEFAULT 0,
  parent_uuid TEXT,                     -- For threading

  -- Analysis fields
  topics TEXT,                          -- JSON array of detected topics
  intent TEXT,                          -- Classified user intent
  entities TEXT,                        -- JSON: files, functions, features mentioned
  sentiment REAL,                       -- -1.0 to 1.0

  -- Correlation
  related_commit_hash TEXT,             -- Git commit this relates to
  request_id TEXT,                      -- Links completion to directive
  duration_seconds REAL,                -- Time from request to completion

  -- Metadata
  project_path TEXT NOT NULL,
  git_branch TEXT,
  git_commit TEXT,
  cwd TEXT,

  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tool invocations
CREATE TABLE tool_calls (
  id INTEGER PRIMARY KEY,
  entry_id INTEGER REFERENCES transcript_entries(id),
  tool_name TEXT NOT NULL,
  arguments TEXT,                       -- JSON
  result TEXT,                          -- stdout/stderr
  exit_code INTEGER,
  duration_seconds REAL,
  timestamp DATETIME NOT NULL
);

-- Project insights (cached analysis)
CREATE TABLE project_insights (
  id INTEGER PRIMARY KEY,
  project_path TEXT NOT NULL,
  insight_type TEXT NOT NULL,           -- 'goal', 'pattern', 'blocker', 'drift'
  title TEXT NOT NULL,
  description TEXT,
  confidence REAL,                      -- 0.0 to 1.0
  supporting_entries TEXT,              -- JSON array of entry UUIDs
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  acknowledged BOOLEAN DEFAULT 0        -- User saw/dismissed
);

-- Git commits (for correlation)
CREATE TABLE git_commits (
  id INTEGER PRIMARY KEY,
  project_path TEXT NOT NULL,
  commit_hash TEXT NOT NULL,
  author TEXT NOT NULL,
  message TEXT NOT NULL,
  timestamp DATETIME NOT NULL,
  files_changed TEXT,                   -- JSON array
  conversation_uuid TEXT,               -- Linked to transcript entry

  UNIQUE(project_path, commit_hash)
);
```

**Key Features:**
1. **Full History Import**: Parse all existing transcripts and backfill database
2. **Real-time Ingestion**: Write to DB as entries arrive in ConversationMonitor
3. **Display Filtering**: `display_in_timeline` flag controls UI visibility without losing data
4. **Semantic Search**: Full-text search across all conversation history
5. **Pattern Detection**: Identify recurring themes, blockers, abandoned work
6. **Progress Tracking**: Correlate stated goals with actual progress
7. **Commit Attribution**: Link AI suggestions to actual git commits
8. **Context Resurrection**: "What was I working on last Tuesday?" queries

**Use Cases:**
- "Show me all entries about authentication this month"
- "What features did we start but never finish?"
- "Find all commits where Claude suggested changes"
- "What were my goals in the last standup message?"
- "Show timeline entries related to this file"

**Implementation Phases:**
1. **Phase 1**: Basic schema + import existing transcripts
2. **Phase 2**: Real-time ingestion in ConversationMonitor
3. **Phase 3**: Analysis engine (pattern detection, insights)
4. **Phase 4**: Smart suggestions UI ("You might want to...")

**Integration Points:**
- `ConversationMonitor`: Write all entries to DB
- New `AnalysisEngine` actor: Run queries and generate insights
- New `InsightsPanel`: Display suggestions and patterns
- Transcript Inventory: Enhanced search powered by SQL

#### Git Commit Rewriting Assistance
**Status:** Backlog
**Priority:** High (Complements SQL backend)
**Category:** Developer Workflow

Intelligent assistance for rewriting git history with atomic, well-structured commits using interactive squash, soft reset, and commit message generation.

**The Problem:**
During development with AI assistance, commits can become messy:
- Many small "fix typo" or "oops" commits
- Commits with unclear or AI-generated messages
- Multiple unrelated changes bundled together
- Features split across too many commits
- No logical atomic structure

**The Solution:**
Guided UI for rewriting branch history into clean, atomic commits with well-written messages.

**Core Features:**

1. **Branch Analysis**
   - Parse all commits since branch diverged from main
   - Show file changes, message quality, logical groupings
   - Identify related changes that should be combined
   - Detect commits that should be split (multiple concerns)

2. **Smart Grouping**
   - Use SQL transcript backend to correlate commits with conversations
   - Group commits by feature/task based on Claude/Codex directives
   - Suggest logical atomic commits: "These 8 commits are all about auth"
   - Show conversation context for each commit group

3. **Interactive Rewrite UI**
   ```
   ┌─────────────────────────────────────────────────────┐
   │ Rewrite History: feature/timeline-improvements      │
   ├─────────────────────────────────────────────────────┤
   │ 23 commits since main │ Suggested: 5 atomic commits│
   │                                                      │
   │ Suggested Grouping:                                 │
   │                                                      │
   │ ☐ Atomic Commit 1: "Timeline cache infrastructure"  │
   │   • 8e9a0b2 Add cache store                         │
   │   • f2b1c4a Add orchestrator                        │
   │   • 9d5e3f0 Add cache models                        │
   │   • 4a7c2b1 Wire up cache loading                   │
   │   Conversation: "Help me cache timeline entries"    │
   │   [Edit Message] [Split] [Reorder]                  │
   │                                                      │
   │ ☐ Atomic Commit 2: "Implement dual-form tense..."   │
   │   • 3b8f1d9 Add present/past forms                  │
   │   • 6e2a9c4 Update cache schema                     │
   │   Conversation: "Timeline should show past tense"   │
   │   [Edit Message] [Split] [Reorder]                  │
   │                                                      │
   │ [Preview Rewrite] [Execute] [Cancel]                │
   └─────────────────────────────────────────────────────┘
   ```

4. **Commit Message Generation**
   - Analyze combined changes and conversation context
   - Generate conventional commit messages (feat/fix/refactor)
   - Include relevant details from conversation
   - Show diff of what changed in each atomic commit
   - User edits and approves before applying

5. **Safe Execution**
   - Create backup branch automatically
   - Show exact git commands that will run
   - Allow preview before execution
   - Dry-run mode: show result without changing history
   - Rollback option if user doesn't like result

**Workflow Example:**
1. User: "Help me clean up this feature branch"
2. App analyzes 23 commits + SQL transcript entries
3. Identifies 4 logical features worked on
4. Suggests 5 atomic commits with messages
5. User reviews, edits messages, reorders groups
6. App creates backup branch: `feature/timeline-improvements-backup`
7. App executes: `git reset --soft main` + `git commit` × 5
8. Shows before/after comparison
9. User pushes cleaned history

**Technical Implementation:**
- Use SQL backend to correlate commits with transcript entries
- Parse `git log` output and diff stats
- Use LLM to generate commit messages from conversation context
- Execute git commands via `Process` (git reset, git commit)
- Integration with ConversationMonitor to link commits to directives

**Git Commands Used:**
```bash
# Backup
git branch feature-backup

# Get commits to rewrite
git log main..HEAD --oneline

# Reset to base
git reset --soft main

# Stage and commit atomically
git add <files for commit 1>
git commit -m "Generated message 1"
...

# Verify
git log --oneline
```

**Safety Features:**
- Always create backup branch first
- Require user confirmation before rewriting
- Show warning if branch is pushed to remote
- Detect if branch is merged or has downstream branches
- Provide undo command if user regrets rewrite

**Advanced Features (Future):**
- Detect co-authored commits (Claude + User)
- Preserve commit signatures where appropriate
- Handle merge commits intelligently
- Support rebasing onto updated main
- "Squash all tiny commits" quick action

---

## Completed
- ✅ Timeline monitoring with JSONL parsing
- ✅ LLM-based timeline summarization
- ✅ Multi-source transcript providers (Claude Code)
- ✅ Git repository and worktree detection
- ✅ Security-scoped bookmarks for sandboxed access
- ✅ Real-time file watching with DispatchSource
- ✅ Transcript inventory with worktree support (2025-10-10)
- ✅ Session switching from transcript inventory UI (2025-10-10)
- ✅ Provider-specific icons in timeline (2025-10-10)
- ✅ Timeline entry persistence across session switches (2025-10-10)
- ✅ Reveal-in-inventory action for system messages (2025-10-10)
