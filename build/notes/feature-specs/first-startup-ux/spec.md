# First Startup Experience Improvement

**Status:** Specification Phase
**Priority:** High
**Related:** Database hoovering, project discovery, transcript ingestion, UX feedback

---

## Problem Statement

On first application launch (or when database is empty), users experience a confusing and seemingly broken UX:

**Current Behavior:**
1. App launches with empty project list
2. Projects appear slowly, one at a time, with no explanation
3. Clicking a project shows empty conversation log initially
4. After several seconds/minutes, conversation log suddenly populates
5. No feedback about what's happening or progress
6. No estimate of completion time

**User Impact:**
- Appears broken or frozen
- Users don't know if they need to wait or if something failed
- No visibility into background transcript discovery and ingestion
- Poor first impression of application reliability

---

## Proposed Solution

### 1. Welcome Modal on First Startup

**Trigger:** Show when `transcripts.count == 0` AND `firstLaunchCompleted` preference is not set

**Content:**
```
┌─────────────────────────────────────────────────┐
│  Welcome to Contextify                          │
│                                                  │
│  Discovering your AI conversation history...    │
│                                                  │
│  ⏱️  Estimated time: ~2-5 minutes               │
│  📂 Scanning: ~/.claude/ and ~/.codex/          │
│  🔍 Found: 12 projects, 47 transcripts          │
│                                                  │
│  [████████░░░░░░░░] 45% (21/47 transcripts)     │
│                                                  │
│  Current: contextify - session A31F3D0A         │
│                                                  │
│  ✓ You can continue using the app               │
│    Projects will appear as they're processed    │
│                                                  │
│  [Minimize] [View Details]                      │
└─────────────────────────────────────────────────┘
```

**Features:**
- Real-time progress updates from HooverEngine
- Dismiss/minimize to background
- "View Details" expands to show per-transcript progress
- Persists `firstLaunchCompleted` preference when closed

### 2. Project Tab Progressive Population

**Current:** Projects appear instantly but are empty

**Proposed:** Show loading state with metadata
```
┌────────────────────────────┐
│ 📁 contextify              │
│ ⏳ Loading conversation... │
│ 47 transcripts found       │
│ Processing...              │
└────────────────────────────┘
```

**Transition:** Fade to normal state when first entries arrive

### 3. Conversation Log Placeholder States

**State 1: No transcripts discovered yet**
```
No Activity Yet
Use Claude Code or Codex to populate the timeline.
```

**State 2: Transcripts discovered but ingestion pending**
```
Loading Conversation...
Indexing 47 transcript files
⏱️ About 2 minutes remaining
```

**State 3: Transcripts ingested but no messages**
```
No Activity Yet
This conversation has not started yet.
```

### 4. Background Process Indicator

**Location:** Window footer (next to LLM status bar)

**States:**
- `🔍 Discovering: 12 projects found`
- `⚙️ Indexing: 21/47 transcripts (45%)`
- `✓ Ready: 12 projects, 47 transcripts`

**Behavior:**
- Auto-dismisses after 5 seconds of "Ready" state
- Clickable to re-show welcome modal
- Persists across app launches until complete

---

## Technical Implementation

### Phase 1: Progress Infrastructure

**1. Extend HooverEngine with Progress Events**

```swift
// Add to HooverEngine.swift
actor HooverEngine {
  // Progress callback for UI updates
  var onProgress: ((HooverProgress) -> Void)?

  struct HooverProgress: Sendable {
    let transcriptId: String
    let transcriptPath: String
    let linesProcessed: Int
    let totalLines: Int?
    let entriesInserted: Int
  }

  func hooverTranscript(...) async throws {
    // Emit progress every 1000 lines
    if linesProcessed % 1000 == 0 {
      onProgress?(HooverProgress(...))
    }
  }
}
```

**2. Create FirstStartupOrchestrator**

```swift
@MainActor
@Observable
final class FirstStartupOrchestrator {
  var phase: StartupPhase = .discovering
  var projectsFound: Int = 0
  var transcriptsFound: Int = 0
  var transcriptsProcessed: Int = 0
  var currentTranscript: String?
  var estimatedCompletion: Date?

  enum StartupPhase {
    case discovering
    case indexing(progress: Double)
    case ready
  }

  func startDiscovery() async {
    // Coordinate TranscriptOrchestrator discovery
    // Update progress in real-time
    // Calculate ETA based on avg lines/sec
  }
}
```

**3. WelcomeModalView**

```swift
struct WelcomeModalView: View {
  @Environment(FirstStartupOrchestrator.self) private var orchestrator
  @State private var isExpanded = false

  var body: some View {
    VStack(spacing: 16) {
      header
      if isExpanded {
        detailedProgress
      } else {
        compactProgress
      }
      actions
    }
    .frame(width: 500, height: isExpanded ? 600 : 300)
    .background(.ultraThinMaterial)
  }
}
```

### Phase 2: Project Tab Loading States

**Modify ConversationMonitor to expose loading state:**

```swift
@MainActor
@Observable
final class ConversationMonitor {
  enum LoadingState {
    case notStarted
    case discovering
    case loading(transcriptCount: Int)
    case ready
  }

  private(set) var loadingState: LoadingState = .notStarted

  func startMonitoring(for projectId: String) async {
    loadingState = .loading(transcriptCount: allSessions.count)
    // ... existing hoover logic ...
    loadingState = .ready
  }
}
```

**Update ConversationTimelineView empty state:**

```swift
private var emptyState: some View {
  switch monitor.loadingState {
  case .notStarted:
    noActivityPlaceholder
  case .discovering, .loading(let count):
    loadingPlaceholder(count: count)
  case .ready:
    if monitor.allSessions.isEmpty {
      noTranscriptsPlaceholder
    } else {
      noMessagesPlaceholder
    }
  }
}
```

### Phase 3: Footer Status Indicator

**Add to ContentView footer:**

```swift
HStack {
  Spacer()
  if let startup = firstStartupOrchestrator {
    StartupProgressBadge(orchestrator: startup)
  }
  LLMProcessingStatusBar(...)
}
.padding(.horizontal, 16)
.padding(.vertical, 8)
```

**StartupProgressBadge component:**

```swift
struct StartupProgressBadge: View {
  @Environment(FirstStartupOrchestrator.self) private var orchestrator
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 6) {
      progressIcon
      Text(statusMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule()
        .fill(isHovered ? .secondary.opacity(0.1) : .clear)
    )
    .onHover { isHovered = $0 }
    .onTapGesture {
      // Re-show welcome modal
    }
  }
}
```

---

## User Preferences

**New Preferences:**
- `firstLaunchCompleted: Bool` - Set when welcome modal dismissed
- `showStartupProgress: Bool` - Toggle footer indicator (default: true)
- `lastCompletedDiscovery: Date?` - Track when discovery last finished

**Store in:** UserDefaults suite `dev.contextify.preferences`

---

## Edge Cases

### 1. Discovery Fails Partway
- Show error in welcome modal
- Allow retry
- Continue with partial results

### 2. Very Large Database (1000+ transcripts)
- Show warning about estimated time (>10 min)
- Offer to skip ingestion and discover on-demand
- Cache transcript metadata separately from entries

### 3. No Transcripts Found
- Show helpful message with instructions
- Link to Claude Code / Codex CLI installation guides
- Don't persist `firstLaunchCompleted` (try again next launch)

### 4. App Quit During Discovery
- Resume from checkpoint on next launch
- Welcome modal shows "Resuming discovery..." state
- Progress picks up where it left off (using `last_processed_line`)

---

## Success Metrics

**Before (Current State):**
- No feedback for 0-5 minutes
- Users think app is broken
- Mystery empty states

**After (Target State):**
- < 3 seconds to show welcome modal
- Real-time progress updates every 1 second
- Clear ETA and cancel option
- Smooth project/conversation appearance

---

## Implementation Phases

### Phase 1: Infrastructure (1-2 days)
- [ ] Add progress events to HooverEngine
- [ ] Create FirstStartupOrchestrator
- [ ] Add loading states to ConversationMonitor
- [ ] Create preference keys

### Phase 2: UI Components (1-2 days)
- [ ] Build WelcomeModalView
- [ ] Add loading states to ConversationTimelineView
- [ ] Create StartupProgressBadge footer
- [ ] Update project tab UI

### Phase 3: Integration (1 day)
- [ ] Wire up FirstStartupOrchestrator to discovery flow
- [ ] Connect progress events end-to-end
- [ ] Add welcome modal trigger on first launch
- [ ] Test with clean database

### Phase 4: Polish (1 day)
- [ ] ETA calculation tuning
- [ ] Smooth animations and transitions
- [ ] Error handling and edge cases
- [ ] Accessibility review

**Total Estimated Time:** 4-6 days

---

## Dependencies

- HooverEngine (existing)
- TranscriptOrchestrator (existing)
- ConversationMonitor (existing)
- UserDefaults for preferences

**No breaking changes** - All additions are backwards compatible

---

## Future Enhancements

### Optional Features (Not in Scope)
1. **Selective Discovery:** Let users choose which projects to index
2. **Background Indexing:** Index new transcripts while app is closed
3. **Re-index Command:** Manual trigger to re-discover all transcripts
4. **Performance Mode:** Skip timeline cache generation on first startup

---

## Related Issues

- Initial database population confusion (user feedback)
- Empty project tabs mystery
- Slow first startup perception
- No feedback during long operations

---

## Notes

- This spec addresses concerns raised during feature/db-schema-collapse testing
- Welcome modal design inspired by Xcode project indexing UX
- Footer badge similar to LLM status bar (consistent design language)
- All strings should be localizable for future i18n
