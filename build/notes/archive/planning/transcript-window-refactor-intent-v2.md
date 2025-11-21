# Transcript Window Refactoring - Intent Document v2

**Date:** 2025-11-09
**Status:** Research Complete, Ready for Implementation Planning

---

## Problem Statement

TranscriptInventoryView.swift is currently **1516 lines** (target: ~300 lines). The file contains:
- TranscriptInventoryView (lines 24-942): ~918 lines
- **TranscriptDetailView embedded as nested struct** (lines 943-1498): ~555 lines
- Scattered metadata loading logic
- Complex error handling that fails silently
- No clear separation of concerns

This refactoring aims to:
1. Reduce file size via component extraction
2. Align summarization behavior with the proven conversation log UX
3. Fix silent failures that leave UUID titles
4. Improve status bar integration for better observability

---

## Research Findings

### Current Architecture (TranscriptInventoryView)

**File Structure:**
```
TranscriptInventoryView (1516 lines total)
├── TranscriptInventoryView struct (24-942)
│   ├── Session list UI
│   ├── Search/filter logic
│   ├── Metadata orchestration (scattered)
│   ├── Context menus
│   ├── Export functions
│   └── Developer tools
└── TranscriptDetailView struct (943-1498) ← EMBEDDED NESTED STRUCT
    ├── Detail panel UI
    ├── Metadata display
    ├── File info panels
    ├── System events
    ├── Usage stats
    └── Helper functions
```

**Immediate Win:** Extracting TranscriptDetailView to its own file would reduce TranscriptInventoryView to ~960 lines (−555 lines, 36% reduction).

### Current Metadata Generation Flow

```
User opens Inventory → loadMetadataForSessions()
                            ↓
                 TranscriptMetadataOrchestrator.ensureMetadata()
                            ↓
                    Check SQL cache (by transcript_id)
                            ↓
                    ┌───────┴───────┐
                Hit │               │ Miss
                    ↓               ↓
            Return cached     Check circuit breaker
                                    ↓
                            ┌───────┴────────┐
                       Open │                │ Closed
                            ↓                ↓
                  HeuristicMetadata    Call FoundationLLM
                                            ↓
                                    ┌───────┴───────┐
                              Success │             │ Failure
                                      ↓             ↓
                              LLM metadata   HeuristicMetadata
                                      ↓             ↓
                              saveToSQL (may throw FK error)
                                      ↓
                         Return TranscriptMetadata OR throw error
```

**Key Finding:** Generation never returns null - it always falls back to HeuristicMetadata. But FK errors throw, causing UI to catch and leave metadata state nil.

### UUID Title Problem - Root Causes

**Identified failure modes that leave UUID titles:**

1. **FK Constraint Errors (Orphaned Transcripts):**
   - Database doesn't have transcript record yet
   - `saveToSQL()` throws FK constraint error
   - UI catches error (line 933), logs it, but doesn't update metadata state
   - Session row displays `session.identifier` (UUID) as fallback

2. **Stuck Loading State:**
   - `loadingMetadata.contains(id)` is true
   - Task never completes (crash, cancellation, etc.)
   - Row shows "Analyzing..." forever

3. **Silent Heuristic Fallbacks:**
   - Very short transcripts (<3 exchanges) → HeuristicMetadata
   - Circuit breaker open → HeuristicMetadata
   - LLM unavailable → HeuristicMetadata
   - **BUT:** Heuristic titles may still be generic/UUID-like if transcript has no user messages

4. **Race Conditions:**
   - Session discovered but not yet persisted to DB
   - Metadata generation starts before `persistDiscoveredSessions()` completes
   - FK error thrown

### Current Status Bar Integration

**Two Independent LLM Queues:**

1. **TimelineCacheMissGenerator** (Timeline/Conversation Log)
   - Entry-level summaries (present/past forms)
   - FIFO queue with batching (10 items/batch)
   - Rate limit: 2s between batches
   - Error handling: Per-item retry (3 attempts)
   - Reports via `observeQueue() -> AsyncStream<QueueStats>`

2. **TranscriptMetadataOrchestrator** (Transcripts)
   - Document-level titles/descriptions/topics
   - Concurrent task-per-transcript
   - Circuit breaker (60% failure threshold, 5-minute window)
   - Reports via `observeQueue() -> AsyncStream<QueueStats>`

**StatusBarViewModel Aggregation:**
- Monitors both providers concurrently
- **Last-write-wins** aggregation (NOT true sum)
- Shows unified state: pending count, processing status, ETA, errors
- Located in main window only

**Problem:** Last-write-wins means if Timeline has 10 items and Transcript has 5 items, status bar shows whichever provider updated most recently (not 15 total).

### Conversation Log UX (Reference Implementation)

**ConversationTimelineView** (proven, working):
- Minimal (~250 lines)
- Clean separation: UI in View, logic in ConversationMonitor
- Timeline entries with cache-backed summaries
- Viewport-driven pruning
- Error states clearly surfaced
- Real-time updates via NotificationCenter

**TimelineCacheMissGenerator** (proven queue management):
- FIFO queue with deduplication
- Viewport-aware pruning (removes invisible items)
- Overload protection (max 5000 items)
- Stabilization delay (750ms) to prevent wasted LLM calls
- Clear error tracking with sliding window
- Status bar integration via QueueStats

**Key UX Patterns to Adopt:**
1. **Loading states:** "Analyzing..." with hourglass icon
2. **Error states:** Clear error UI with retry option
3. **Fallback display:** Heuristic titles clearly marked (e.g., with info icon)
4. **Viewport pruning:** Cancel generation for off-screen items
5. **Status reporting:** Aggregate queue stats properly

---

## Goals & Constraints

### Primary Goals

1. **Code Size Reduction (1516 → ~300 lines)**
   - Extract TranscriptDetailView to own file (immediate ~560 line reduction)
   - Factor out metadata loading logic to separate view model
   - Extract export/cleanup functions to utilities
   - Simplify session row rendering

2. **Fix UUID Title Failures**
   - Handle FK errors gracefully (show error state in UI)
   - Clear loading state on task completion/cancellation
   - Mark heuristic-generated titles with info icon
   - Ensure persistDiscoveredSessions completes before metadata generation

3. **Align Summarization UX with Conversation Log**
   - Visual presentation: Adopt loading/error/fallback patterns
   - Error handling: Surface failures with retry options
   - Viewport awareness: Cancel off-screen generation (future enhancement)

4. **Improve Status Bar Integration**
   - Near-term: Keep existing TranscriptMetadataOrchestrator queue
   - Document unified queue architecture as follow-up work
   - Add heavy comments explaining queue reuse rationale
   - Consider true aggregation (sum counts) vs. last-write-wins

### Key Constraints

**CRITICAL: Don't Break Conversation Log**
- ConversationTimelineView is **stable and working**
- ConversationMonitor is **proven and tested**
- TimelineCacheMissGenerator is **production-ready**
- **Strategy:** Refactor Transcript window first, validate thoroughly, then integrate Conversation log IF beneficial

**Code Duplication is Acceptable (Temporarily)**
- Prioritize stability over DRY principle
- Duplicate code from Conversation log where needed
- Factor out common components AFTER both windows validated
- Document duplication clearly with TODO comments

---

## Success Criteria

### Must Have (v1)
- [ ] TranscriptInventoryView reduced to ~300 lines (via extraction)
- [ ] TranscriptDetailView extracted to own file
- [ ] No sessions with UUID titles (proper error recovery)
- [ ] Clear visual distinction for:
  - [ ] Loading state ("Analyzing..." with icon)
  - [ ] Error state (with retry button)
  - [ ] Heuristic fallback (with info icon)
- [ ] FK errors handled gracefully (don't crash, show error UI)
- [ ] Conversation log remains stable (no regressions)

### Should Have (v2)
- [ ] Metadata loading logic extracted to view model/orchestrator
- [ ] Status bar shows true aggregated count (Timeline + Transcript)
- [ ] Export/cleanup functions extracted to utilities
- [ ] Session row complexity reduced (extract to component)
- [ ] Clear error attribution in status bar ("3 timeline, 2 transcript errors")

### Nice to Have (Future)
- [ ] Viewport-aware pruning for transcript metadata generation
- [ ] Unified queue architecture (designed and documented)
- [ ] Common components factored out (after validation)
- [ ] Conversation log integrated with refactored components

---

## Implementation Strategy

### Phase 1: File Extraction (Low Risk, High Impact)

**Goal:** Reduce TranscriptInventoryView from 1516 → ~960 lines

1. Extract TranscriptDetailView to `TranscriptDetailView.swift`
2. Update imports and references
3. Validate no regressions
4. **Expected outcome:** Immediate 36% size reduction

### Phase 2: Error Handling + Concurrency Control (HIGH PRIORITY - Prevents Apple Intelligence Overload)

**Goal:** Eliminate UUID title failures AND prevent Apple Intelligence overload

**CRITICAL:** Must implement viewport-aware loading with concurrency limits to prevent overwhelming Apple Intelligence with hundreds of concurrent LLM requests.

1. Add error state to TranscriptInventoryView:
   ```swift
   @State private var metadataErrors: [String: String] = [:]  // transcript_id -> error
   ```

2. Update sessionRow to show error state:
   ```swift
   if let error = metadataErrors[session.identifier] {
       // Show error with info icon + tooltip
   } else if let meta = metadata[session.identifier] {
       // Show title (with info icon if confidence == "low")
   } else if loadingMetadata.contains(session.identifier) {
       // Show "Analyzing..." with hourglass
   } else {
       // Trigger load if not loaded yet
   }
   ```

3. **CRITICAL: Add concurrency limit to loadMetadataForSessions** to prevent Apple Intelligence overload:
   ```swift
   let maxConcurrentMetadata = 3  // Limit concurrent LLM requests

   for session in missingSessions {
       // Wait if too many tasks running (backpressure)
       while metadataTasks.count >= maxConcurrentMetadata {
           await Task.yield()
           try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
       }

       // Spawn task with concurrency control
       let task = Task { @MainActor in
           // ... metadata generation
       }
       metadataTasks[id] = task
   }
   ```

4. **CRITICAL: Remove bulk loading in .task modifier** (causes Apple Intelligence overload):
   ```swift
   .task {
       await persistDiscoveredSessions(monitor.allSessions)
       // DO NOT call loadMetadataForSessions(monitor.allSessions) here!
       // This loads ALL sessions at once, overwhelming Apple Intelligence
       // Instead, rely on .onChange(of: sessions) debounced loading
   }
   ```

5. Update loadMetadataForSessions to capture errors:
   ```swift
   do {
       let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
       metadata[id] = generated
       loadingMetadata.remove(id)
       metadataErrors.removeValue(forKey: id)
   } catch {
       loadingMetadata.remove(id)
       metadataErrors[id] = error.localizedDescription
       log.error("Failed to generate metadata: \(error)")
   }
   ```

6. Ensure persistDiscoveredSessions completes before loadMetadataForSessions:
   - Already sequenced in onChange handler (lines 231-238)
   - Validate this ordering is preserved

7. Add retry mechanism:
   - Tapping error icon clears error and retriggers load
   - Or add "Regenerate" button in context menu

**Why Concurrency Control is Critical:**
- Without limits: Opening inventory with 500 transcripts → 500 concurrent LLM requests → Apple Intelligence overload error
- With limit of 3: Max 3 concurrent requests → Apple Intelligence stays responsive
- Follows proven pattern from TimelineCacheMissGenerator (processes 1 at a time)
- Metadata generation is slower (~2-5s per session) so can handle slightly higher concurrency than timeline (3 vs 1)

### Phase 3: Visual Alignment (Low Risk, UX Improvement)

**Goal:** Match conversation log UX patterns

1. Adopt TimelineEntryRow loading state:
   ```swift
   HStack(spacing: 4) {
       Image(systemName: "hourglass")
           .font(.caption2)
           .symbolRenderingMode(.monochrome)
           .foregroundStyle(.tertiary)
       Text("Analyzing…")
           .font(.caption)
           .foregroundStyle(.secondary)
   }
   ```

2. Add heuristic indicator for low-confidence metadata:
   ```swift
   if meta.confidence == "low" {
       Image(systemName: "info.circle")
           .foregroundStyle(.secondary)
           .help("Generated from limited context")
   }
   ```

3. Add error state with retry:
   ```swift
   HStack(spacing: 4) {
       Image(systemName: "exclamationmark.triangle")
           .foregroundStyle(.orange)
       Text("Failed to analyze")
           .font(.caption)
       Button("Retry") {
           retryMetadata(for: session)
       }
   }
   ```

### Phase 4: Status Bar Integration (Medium Risk, Observability)

**Goal:** Better status reporting for transcript metadata generation

**Near-term (Keep existing queue):**

1. Document current architecture:
   - TranscriptMetadataOrchestrator already conforms to QueueStatsProvider
   - StatusBarViewModel already observes it
   - Add comments explaining why transcript metadata uses separate queue

2. Fix aggregation in StatusBarViewModel:
   ```swift
   // Current: last-write-wins
   private func aggregateStats(from stats: QueueStats) {
       self.queueDepth = stats.pendingCount
       // ...
   }

   // Proposed: true aggregation
   private var providerStats: [ObjectIdentifier: QueueStats] = [:]

   private func aggregateStats(from stats: QueueStats, provider: ObjectIdentifier) {
       providerStats[provider] = stats
       self.queueDepth = providerStats.values.reduce(0) { $0 + $1.pendingCount }
       // ...
   }
   ```

3. Add error attribution:
   - Track which provider errors came from
   - Show in status bar tooltip: "3 timeline errors, 2 transcript errors"

**Long-term (Unified queue - DOCUMENT ONLY):**

1. Write design doc: `build/docs/future-features/unified-llm-queue.md`
2. Outline architecture:
   - Single queue for all LLM work (timeline + transcript + future)
   - Priority levels (urgent/normal/background)
   - Unified status reporting
   - Shared circuit breaker
3. Benefits and trade-offs
4. Migration plan
5. **DO NOT IMPLEMENT** - this is follow-up work

### Phase 5: Further Extraction (Low Risk, Continued Reduction)

**Goal:** Continue reducing TranscriptInventoryView complexity

1. Extract metadata loading to view model:
   ```swift
   @Observable
   class TranscriptInventoryViewModel {
       private(set) var metadata: [String: TranscriptMetadata] = [:]
       private(set) var loadingMetadata: Set<String> = []
       private(set) var metadataErrors: [String: String] = [:]

       func loadMetadata(for sessions: [TranscriptSession]) async { ... }
       func retryMetadata(for session: TranscriptSession) async { ... }
   }
   ```

2. Extract export functions to utility:
   ```swift
   actor TranscriptExporter {
       func exportToCodex(session: TranscriptSession) async throws { ... }
       func exportToClaudeCode(session: TranscriptSession) async throws { ... }
   }
   ```

3. Extract session row to component:
   ```swift
   struct TranscriptSessionRow: View {
       let session: TranscriptSession
       let metadata: TranscriptMetadata?
       let isLoading: Bool
       let error: String?
       let isActive: Bool
       let isPinned: Bool
   }
   ```

---

## Risks & Mitigations

### Risk: Breaking Conversation Log

**Mitigation:**
- **DO NOT** modify ConversationMonitor, TimelineCacheMissGenerator, or ConversationTimelineView
- Only extract patterns, don't refactor shared code
- Run full test suite after each phase
- Manual testing of conversation log after each commit

### Risk: Introducing New Bugs in Error Handling

**Mitigation:**
- Add comprehensive error state testing
- Test FK error scenario explicitly
- Test circuit breaker scenario
- Test loading state cancellation

### Risk: Status Bar Aggregation Breaks

**Mitigation:**
- Keep last-write-wins initially
- Test true aggregation in isolation
- Add feature flag if needed
- Fall back to current behavior if issues

---

## Open Questions (For User Approval)

1. **Phase Ordering:**
   - Should we do Phase 1 (extraction) first for quick win?
   - Or Phase 2 (error handling) to fix UUID titles ASAP?

2. **Scope of v1:**
   - Should Phase 4 (status bar) be in v1 or deferred?
   - Should Phase 5 (view model extraction) be in v1?

3. **Status Bar Aggregation:**
   - True sum (Timeline 10 + Transcript 5 = 15 total)?
   - Or separate display ("Timeline: 10, Transcript: 5")?
   - Or keep last-write-wins?

4. **Error Display:**
   - Show error inline in session row?
   - Or show error indicator with popover/tooltip?
   - Or show errors in a separate panel?

5. **Heuristic Title Marking:**
   - Always show info icon for confidence == "low"?
   - Or only show for empty/generic titles?
   - Or don't distinguish at all?

---

## Next Steps

1. ✅ Write intent document v2 (this document)
2. ⏸️ **PAUSE FOR USER APPROVAL**
3. User clarifies open questions
4. Write detailed technical implementation plan
5. Begin implementation (Phase 1 or Phase 2 based on user preference)
6. Commit atomically with clear messages
7. Test thoroughly
8. Iterate

---

## Related Documentation

- **LLM Architecture:** `build/docs/architecture/llm-processing.md`
- **Timeline Cache:** `build/docs/components/timeline-cache.md`
- **Conversation Monitor State:** `build/docs/architecture/conversation-monitor-state.md`
- **Status Bar (Original Spec):** `build/docs/archive/feature-specs/status-bar.md`
- **SQL Backend:** `build/docs/architecture/sql-backend.md`
- **Current Implementation:**
  - `Contextify/Contextify/TranscriptInventoryView.swift` (1516 lines)
  - `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`
  - `Contextify/Contextify/TimelineCacheMissGenerator.swift`
  - `Contextify/Contextify/StatusBarViewModel.swift`
  - `Contextify/Contextify/ConversationTimelineView.swift` (reference)

---

## Appendix: File Size Projection

**Current:** 1516 lines

**After Phase 1 (TranscriptDetailView extraction):**
- TranscriptInventoryView: ~960 lines
- TranscriptDetailView.swift: ~555 lines (new file)

**After Phase 5 (View model + utilities extraction):**
- TranscriptInventoryView: ~300 lines (target achieved)
- TranscriptInventoryViewModel.swift: ~200 lines (new file)
- TranscriptExporter.swift: ~150 lines (new file)
- TranscriptSessionRow.swift: ~100 lines (new file)
- TranscriptDetailView.swift: ~555 lines
- **Total:** ~1305 lines (well-organized across 5 files)

**Reduction:** 1516 → 1305 lines (−211 lines, 14% reduction) but with far better organization and maintainability.
