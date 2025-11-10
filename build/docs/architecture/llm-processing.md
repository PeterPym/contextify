# LLM Processing Architecture

**Status:** Production (macOS 26+ Apple Intelligence)
**Platform:** FoundationLLM (on-device)
**Minimum:** macOS 26.0 (Tahoe) for LLM features; older systems use fallbacks

---

## Executive Summary

Contextify uses **two independent LLM processing queues** for different content generation tasks:

1. **Timeline Summary Generation** (TimelineCacheMissGenerator)
   - Generates present/past form summaries for conversation entries
   - Triggered: When displaying timeline entries without cached summaries
   - Queue: LIFO with viewport-aware pruning (sequential processing, newest first)

2. **Transcript Metadata Generation** (TranscriptMetadataOrchestrator)
   - Generates titles, descriptions, and topics for entire transcripts
   - Triggered: When viewing transcript inventory
   - Queue: LIFO with viewport-aware pruning (sequential processing, newest first)

Both systems use **FoundationLLM** (Apple Intelligence) and operate independently with their own rate limiting, error handling, and circuit breakers.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Contextify Application                      │
└─────────────────────────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
          ┌─────────▼────────┐     ┌─────────▼────────────┐
          │  Timeline View   │     │ Inventory View       │
          │  (Main Window)   │     │ (Transcript Browser) │
          └─────────┬────────┘     └─────────┬────────────┘
                    │                        │
        ┌───────────▼──────────┐  ┌─────────▼────────────────┐
        │ ConversationMonitor  │  │ TranscriptInventoryView  │
        │  - Loads feed        │  │  - Loads sessions        │
        │  - Detects misses    │  │  - Requests metadata     │
        └───────────┬──────────┘  └─────────┬────────────────┘
                    │                       │
        ┌───────────▼──────────────┐ ┌─────▼────────────────────┐
        │ TimelineCacheMissGenerator│ │TranscriptMetadataOrchestrator│
        │                           │ │                          │
        │ • Queue: LIFO priority    │ │ • Queue: LIFO priority   │
        │ • Mode: Sequential only   │ │ • Mode: Sequential only  │
        │ • Pruning: Viewport-aware │ │ • Pruning: Viewport-aware│
        │ • Cache: SQL keyed by     │ │ • Cache: SQL by hash     │
        │   content+window hash     │ │                          │
        └───────────┬──────────────┘ └─────┬────────────────────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼──────────┐
                    │    FoundationLLM     │
                    │  (Apple Intelligence)│
                    │                      │
                    │ • On-device          │
                    │ • Session-based      │
                    │ • macOS 26+ only     │
                    └──────────────────────┘
```

---

## LLM Queue #1: Timeline Summary Generation

**Purpose:** Generate human-readable summaries for timeline entries (e.g., "Claude proposes to implement...", "User asks about...").

**Location:** `Contextify/Contextify/TimelineCacheMissGenerator.swift`

**Triggered By:**
- Timeline entry display in ConversationMonitor
- Cache miss detected (no cached summary for content+window hash)
- Real-time during conversation monitoring

**Processing Model:**
- **Queue Type:** LIFO (newest entries processed first)
- **Processing Mode:** Sequential (one request at a time, FoundationLLM limitation)
- **Viewport-Aware:** Prunes invisible entries before LLM call
- **Stabilization Delay:** 750ms before LLM call (allows pruning to cancel stale work)
- **Deduplication:** Content+window hash key
- **Error Handling:** Per-item retry (3 attempts with exponential backoff)
- **Cache:** SQL `timeline_cache` table

**Why LIFO?** Prioritizes what user is looking at NOW. Newest entries (current viewport) jump to front of queue and get processed first. Older entries from previous scroll positions sit at back and are more likely to be pruned when user scrolls.

**Output:**
- `presentForm`: "Claude proposes to implement..."
- `pastForm`: "Claude proposed to implement..."
- `selectedForm`: Which form to display
- `disposition`: "directive" | "question" | "response"

**Detailed Documentation:** [`../components/timeline-cache.md`](../components/timeline-cache.md)

---

## LLM Queue #2: Transcript Metadata Generation

**Purpose:** Generate titles, descriptions, and topic tags for entire transcripts.

**Location:** `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Triggered By:**
- Opening transcript inventory view
- Viewing transcript details
- Manual refresh/regeneration

**Processing Model:**
- **Queue Type:** LIFO (newest first) with viewport-aware pruning
- **Concurrency:** Sequential (one at a time) with backpressure protection
- **Viewport-Aware:** ✅ Prunes queue to visible sessions on scroll (500ms debounce)
- **Deduplication:** Remove-and-reinsert to maintain LIFO order
- **Error Handling:** Circuit breaker (60% failure threshold, 5-minute window)
- **Cache:** SQL `transcript_metadata` table with hash verification

**Note:** Matches timeline queue architecture (LIFO, viewport pruning, sequential processing).

**Output:**
- `title`: "Implement Dark Mode Toggle" (1-8 words)
- `description`: Brief summary (1-2 sentences)
- `topics`: ["SwiftUI", "Settings", "UI/UX"] (3-7 tags)
- `confidence`: "high" | "medium" | "low"

**Context Strategy:**
- **Full Strategy:** Transcripts ≤150 exchanges (all content)
- **Adaptive Strategy:** Transcripts >150 exchanges (smart sampling)

**Detailed Documentation:** *(To be created: `transcript-metadata-llm-architecture.md`)*

---

## Error Handling: Tombstone Mechanism

**Problem:** Permanent failures (context overflow, decoding errors) left entries in perpetual "generating" state, creating infinite retry loops when user scrolled them in/out of viewport.

**Solution:** Error tombstones - cache entries marking permanent failure.

### How Tombstones Work

When LLM generation fails with a **non-retryable error**, the system writes a cache entry with:
- **Disposition:** `"error-{errorType}"` (e.g., `"error-overflow"`, `"error-decoding"`)
- **Fallback summary:** Truncated content preview (first 100 chars)
- **Same cache key:** contentSha256 + windowSha256

**Effect:** Entry is now "cached" (with error marker). Viewport changes won't re-queue it.

### Disposition Semantics

The `disposition` field evolved from binary (cached/not cached) to **ternary state machine**:

| Disposition | Meaning | Retry? |
|-------------|---------|--------|
| `"directive"`, `"question"`, `"response"`, `"report"` | Successful generation | No (cached) |
| `"error-overflow"` | Content > 4096 tokens | No (permanent) |
| `"error-decoding"` | LLM output malformed | No (permanent) |
| `"error-unexpected"` | Unknown error | No (permanent) |
| `"error-database"` | SQL write failed | No (permanent) |
| `"guardrail-violation"` | Content filtered (handled) | No (cached) |
| `null` | Not yet attempted | Yes (queue) |

### Error Classification

**Permanent failures** (write tombstone):
- contextOverflow, decodingFailure, unexpected, databaseError

**Transient failures** (retry with exponential backoff, up to 3 attempts):
- llmTimeout, llmUnavailable

**Implementation:** `TimelineCacheMissGenerator.swift` lines 502-545, 811-844

---

## Status Bar Integration

The status bar (bottom of main window) **aggregates both queues** to show unified LLM processing status.

**Implementation:** `Contextify/Contextify/StatusBarView.swift`, `StatusBarViewModel.swift`

**Observed Queues:**
1. `timeline.cacheMissGenerator` (TimelineCacheMissGenerator)
2. `TranscriptMetadataOrchestrator.shared` (singleton)

**Protocol:** Both conform to `QueueStatsProvider` protocol:
```swift
protocol QueueStatsProvider: Sendable {
    func observeQueue() -> AsyncStream<QueueStats>
}
```

**Aggregation Strategy:**
- StatusBarViewModel monitors multiple providers concurrently
- Each provider yields `QueueStats` updates via AsyncStream
- ViewModel applies latest stats from any provider (last-write-wins)
- UI shows combined state: pending count, processing status, ETA, errors

**Display States:**
- **Not monitoring:** No providers available (before timeline starts)
- **Processing N items:** Active LLM generation (shows count + ETA)
- **N pending:** Items queued but not yet processing
- **Up to date:** All queues empty, no errors
- **N errors:** Recent failures (shows error count + tooltip)

**Event Flow:**
```
TimelineCacheMissGenerator                TranscriptMetadataOrchestrator
         │                                            │
         ├─ notifyQueueChanged() ────────────┐       │
         │                                   │       │
         │                        ┌──────────▼───────▼──────┐
         │                        │   StatusBarViewModel     │
         │                        │   aggregateStats()       │
         │                        └──────────┬───────────────┘
         │                                   │
         ├─ observeQueue() ──────────────────┤
         │   AsyncStream                     │
         │                                   ▼
         │                        ┌──────────────────────────┐
         │                        │     StatusBarView        │
         │                        │  (UI updates on change)  │
         │                        └──────────────────────────┘
```

---

## Common Infrastructure

### FoundationLLM Integration

Both systems use the shared `FoundationLLM` singleton for LLM calls.

**Location:** `Contextify/Contextify/FoundationLLM.swift`

**Key Features:**
- **Session Management:** Isolated sessions per kind/provider/transcript
- **Availability Check:** `LLMHealthCheck.shared.checkHealth()` with 30s TTL
- **Fallback Behavior:** Heuristic generation on macOS < 26.0 or LLM unavailable
- **Retry Logic:** Exponential backoff on transient failures
- **Fast Paths:** Slash command detection, affirmative/negative detection, acknowledgement detection

**Session Keys:**
- Timeline: Per `(kind, provider)` tuple (e.g., "assistant/claude-code")
- Metadata: Per transcript ID (isolated context)

### Slash Command Handling

Slash commands (e.g., `/clear`, `/compact`) use a **fast path** that skips LLM calls for instant response.

**Detection** (`FoundationLLM.swift:1013-1053`):
- `<command-name>/command</command-name>` tags (Claude Code format)
- Messages starting with `/command`
- Supports 30+ commands from Claude Code and Codex CLI

**Prefix Policy** (`FoundationLLM.swift:1320-1362`):
User summaries require allowed prefixes. Command-specific verbs (e.g., "You cleared", "You compacted") prevent fallback prefix prepending that would create malformed summaries like "You requested Claude Code You cleared..."

### SQL Caching

Both systems cache results in SQL to avoid duplicate LLM calls:

**Timeline Cache:**
- Table: `timeline_cache`
- Key: `SHA256(content + window)`
- Fields: `present_form`, `past_form`, `selected_form`, `disposition`

**Metadata Cache:**
- Table: `transcript_metadata`
- Key: `transcript_id`
- Freshness: Verified by `SHA256(transcript_content)` and version numbers
- Fields: `title`, `description`, `topics` (JSON), `confidence`, etc.

### Error Handling Patterns

**Timeline (Per-Item Retry):**
```swift
retry: for attempt in 1...3 {
    do {
        return try await generateSummary()
    } catch {
        if attempt < 3 { continue retry }
        trackError(reason)  // Status bar sees this
        throw error
    }
}
```

**Metadata (Circuit Breaker):**
```swift
guard await circuitBreaker.allow() else {
    return HeuristicMetadata.generate()  // Fallback
}
do {
    return try await generateWithLLM()
} catch {
    await circuitBreaker.recordFailure()
    throw error
}
```

---

## Performance Characteristics

### Timeline Summary Generation

- **Latency:** ~200ms per item (on-device LLM)
- **Throughput:** ~5 items/second (10-item batches with 2s delays)
- **Peak Queue:** Unbounded (capped at 5,000 items)
- **Memory:** ~50KB per pending item (content + window)

### Transcript Metadata Generation

- **Latency:** 2-8 seconds per transcript (depends on size)
- **Throughput:** Concurrent (limited by circuit breaker)
- **Context Building:** 100-500ms (sampling for large transcripts)
- **Memory:** ~1MB per active task (full transcript content)

---

## Monitoring & Observability

### Logs

Both systems use OSLog with subsystem `dev.contextify`:

**Timeline:**
- Category: `Timeline.CacheMissGenerator`
- Key events: Batch processing, cache hits/misses, errors

**Metadata:**
- Category: `dev.contextify.metadata`
- Key events: Generation start/complete, circuit breaker state

**Status Bar:**
- Category: `StatusBar`
- Key events: Provider changes, aggregation updates

### Status Bar Real-Time Monitoring

The status bar provides **unified visibility** into both LLM queues:

```
[●] Apple Intelligence  |  Processing 12 items (~6s)
```

- Green dot: FoundationLLM available
- Gray dot: LLM unavailable (macOS < 26 or disabled)
- Red dot: LLM error (need to toggle in System Settings)

**Developer Logs:**
```bash
# Watch status bar activity
log stream --predicate 'subsystem == "dev.contextify" AND category == "StatusBar"' --level info

# Watch timeline generation
log stream --predicate 'subsystem == "dev.contextify" AND category CONTAINS "Timeline"' --level info

# Watch metadata generation
log stream --predicate 'subsystem == "dev.contextify.metadata"' --level info
```

---

## Fallback Behavior (macOS < 26.0)

When FoundationLLM is unavailable:

**Timeline:**
- Falls back to basic text: "Claude sent a message", "User asked a question"
- No LLM calls, no cache writes
- Instant display (no latency)

**Metadata:**
- Uses heuristic generation based on message patterns
- Title: "Brief Session" or "Developer Chat"
- Description: Extracted from first/last user messages
- Topics: Empty array
- Confidence: "low"

---

## Future Considerations

### Potential Enhancements

1. **True Aggregation:** Sum pending counts from both queues instead of last-write-wins
2. **Queue Priority:** Allow urgent metadata generation to preempt timeline generation
3. **Batch Metadata:** Group multiple transcript metadata requests into batches
4. **ETA Calculation:** Add ETA support for metadata generation (currently 0)
5. **Error Details:** Surface specific error types in status bar tooltip
6. **Offline Mode:** Cache-only operation when LLM unavailable

### Scalability Notes

- Timeline queue can handle thousands of pending items
- Metadata circuit breaker prevents runaway failures
- Both systems designed for single-user desktop use (not server-scale)

---

## FoundationLLM Sequential Processing Limitation

**Apple's LanguageModelSession enforces sequential processing** - only one request can be in flight at a time per session.

### Technical Details

From Apple's FoundationModels framework documentation:
- Each `LanguageModelSession` has an `isResponding` property
- Sending a prompt while `isResponding == true` triggers a `rateLimited` error
- You must either:
  1. Wait for current request to complete, OR
  2. Create multiple session instances for parallel processing

### Implications for Contextify

**Timeline Queue (TimelineCacheMissGenerator):**
- Uses single shared `FoundationLLM.shared` instance
- Processes one entry at a time sequentially
- Cannot process batches concurrently
- `maxBatchSize = 1` reflects this constraint (not a tunable parameter)

**Transcript Metadata (TranscriptMetadataOrchestrator):**
- Uses LIFO queue with sequential processing (same as timeline)
- Viewport-aware pruning removes invisible items
- Batch enqueuing with remove-and-reinsert deduplication

**Why "batch" terminology persists in code:**
Historical artifact. Code structure supports batching (`Array(pendingMisses.prefix(batchSize))`) but `maxBatchSize` is always 1 due to FoundationLLM limitation. The term "batch" is misleading - it's actually sequential single-item processing.

### Testing Evidence

WebSearch results confirm:
```swift
struct ChatView: View {
    @State private var session = LanguageModelSession()

    var body: some View {
        Button("Send") {
            Task { await sendMessage() }
        }
        .disabled(session.isResponding) // Gate interactions to prevent rateLimited error
    }
}
```

**Conclusion:** True concurrent LLM processing is not possible with FoundationLLM's current architecture. All queues must use sequential processing.

---

## Related Documentation

- **Timeline Cache + LLM:** [`../components/timeline-cache.md`](../components/timeline-cache.md)
- **Conversation Monitor State:** [`conversation-monitor-state.md`](./conversation-monitor-state.md)
- **Status Bar Implementation:** `build/docs/archive/feature-specs/status-bar.md` (original spec)
- **SQL Backend:** [`sql-backend.md`](./sql-backend.md)
- **Logging Guidelines:** [`../guides/logging-best-practices.md`](../guides/logging-best-practices.md)

---

## Quick Reference

| Aspect | Timeline Summaries | Transcript Metadata |
|--------|-------------------|---------------------|
| **Purpose** | Entry-level summaries | Document-level titles/topics |
| **Trigger** | Timeline display | Inventory view |
| **Queue** | LIFO sequential | LIFO sequential |
| **Pruning** | Viewport-aware | Viewport-aware |
| **Rate Limit** | Overload protection | Circuit breaker |
| **Latency** | ~200ms/item | 2-8s/transcript |
| **Cache Key** | content+window hash | transcript_id + SHA256 |
| **Error Strategy** | Per-item retry | Circuit breaker |
| **Fallback** | Basic text | Heuristic generation |
| **Observability** | `Timeline.CacheMissGenerator` | `dev.contextify.metadata` |
| **Implementation** | TimelineCacheMissGenerator.swift | TranscriptMetadataOrchestrator.swift |
