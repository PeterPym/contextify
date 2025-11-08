# Timeline Cache + LLM Integration Architecture

**Status:** Production (macOS 26+ Apple Intelligence)
**LLM:** FoundationLLM (on-device)
**Generator:** Timeline​Cache​Miss​Generator (actor-based)
**Requirement:** macOS 26.0+ for LLM features; older systems show fallback summaries (no LLM)

---

## System Overview

Timeline entries display LLM-generated summaries (e.g., "Claude proposes to implement..."). Summaries are cached in SQL by content+window hash. Cache misses trigger background LLM generation with batching, rate limiting, and retry logic.

**Fallback Behavior:** On macOS < 26.0, `FoundationLLM` is unavailable. The system skips LLM calls and displays basic fallback text (e.g., "Claude sent a message"). Cache remains empty; no errors thrown.

**Key Design Principles:**
- Content-aware caching (same content + context = cache hit)
- Background generation (UI never blocks on LLM)
- Deduplication (identical content+window → single LLM call)
- Session management (per kind/provider controllers)
- Graceful degradation (LLM unavailable → fallback text)

---

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                   ConversationMonitor                    │
│                  (Main Actor, UI Layer)                  │
└───────────────────────┬─────────────────────────────────┘
                        ↓
                  Load Feed (SQL)
                        ↓
        ┌───────────────────────────────┐
        │   TranscriptOrchestrator      │
        │ .getRecentFeed(limit: 50)     │
        │   → Single query with         │
        │     LEFT JOIN timeline_cache  │
        └───────────────┬───────────────┘
                        ↓
        ┌───────────────────────────────┐
        │    Result: [(Entry, Cache?)]  │
        │                               │
        │  Cache Hit  → Display cached  │
        │               summary         │
        │                               │
        │  Cache Miss → Queue for LLM   │
        │               generation      │
        └───────────────┬───────────────┘
                        ↓
           ┌────────────────────────────┐
           │ TimelineCacheMissGenerator │
           │        (Actor)             │
           │ .queueMisses([miss...])    │
           └────────┬───────────────────┘
                    ↓
          ┌─────────────────────┐
          │  Deduplication by   │
          │  CacheKey (struct)  │
          │  content + window   │
          └─────────┬───────────┘
                    ↓
          ┌─────────────────────┐
          │   Batch (10 max)    │
          │   Rate limit (2s)   │
          └─────────┬───────────┘
                    ↓
          ┌─────────────────────┐
          │   FoundationLLM     │
          │  .generateSummary() │
          │   (per-session)     │
          └─────────┬───────────┘
                    ↓
          ┌─────────────────────┐
          │  Save to SQL cache  │
          │  Post notification  │
          └─────────┬───────────┘
                    ↓
          ┌─────────────────────┐
          │ ConversationMonitor │
          │   refreshes cache   │
          │   updates UI        │
          └─────────────────────┘
```

---

## Cache Key Design

### CacheKey Struct

```swift
struct CacheKey: Hashable, Sendable {
  let content: String   // SHA256 of entry content
  let window: String    // SHA256 of [prev2_id, prev1_id]

  var composite: String { "\(content)|\(window)" }  // Pipe delimiter
}

// Helper in CacheMiss
extension CacheMiss {
  var cacheKey: CacheKey { CacheKey(content: contentSha256, window: windowSha256) }
}
```

**Rationale:**
- **Content hash:** Same message text → same summary
- **Window hash:** Different context (prev entries) → different summary
- **Composite key:** Deduplication in dictionaries, SQL primary key

**Example:**
```
Entry A: "Fix the bug"
  prev1 = "User asked about performance"
  → Summary: "Claude proposes to fix the performance bug"

Entry B: "Fix the bug"
  prev1 = "User reported a crash"
  → Summary: "Claude proposes to fix the crash"
```

**Same content, different window → different cache entries.**

---

## Cache Miss Detection

### Single Query with LEFT JOIN

```sql
SELECT
  e.*,
  c.present_form, c.past_form, c.disposition
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256
  AND c.window_sha256 = e.window_sha256
  AND c.generator_signature = ?
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC
LIMIT 50
```

**Performance:** <5ms (covering index `idx_entries_feed_cover`).

**Cache Miss:** `c.present_form IS NULL` → Entry lacks cached summary.

---

## Schema Architecture: Denormalization Removal

**Prior to v6 (removed):**
- `transcript_entries.summary` (TEXT) - Always NULL
- `transcript_entries.disposition` (TEXT) - Always NULL
- `transcript_entries.is_completion` (INTEGER) - Denormalized flag
- `transcript_entries.is_directive` (INTEGER) - Denormalized flag

**Post-v6 (current):**
- ALL classification and summary data lives in `timeline_cache` table
- UI flags (`isCompletion`, `isDirective`) derived at runtime from `timeline_cache.disposition`
- `transcript_entries` contains only canonical source data from transcript files

**Derivation Logic (ConversationMonitor.swift:513-517):**
```swift
let cached = try? orchestrator.getCachedTimeline(
  contentSha256: entry.contentSha256,
  windowSha256: entry.windowSha256 ?? ""
)

let isCompletion = cached?.disposition == "completion"
let isDirective: Bool = {
  guard let disp = cached?.disposition else { return false }
  return ["directive", "affirmative", "negative"].contains(disp)
}()
```

**Rationale:**
- Single source of truth (disposition in `timeline_cache`)
- Immutable canonical data (transcript entries never change)
- LLM classifications can be regenerated without touching source data
- No update anomalies (flags always consistent with disposition)

---

## TimelineCacheMissGenerator (Actor)

### Queue Management

**Properties:**
```swift
actor TimelineCacheMissGenerator {
  private var pendingMisses: [CacheKey: CacheMiss] = [:]
  private let maxQueueSize = 5000
  private let maxBatchSize = 10  // Matches code
  private let batchDelayNs: UInt64 = 2_000_000_000  // ~2s rate limit between batches
}
```

**Deduplication:** Dictionary keyed by CacheKey → multiple identical requests collapse to one.

**Capacity:** 5000 max pending → oldest dropped if exceeded.

**Session Resets:** Targeted per `(kind, provider)` pair before each batch to prevent context contamination.

### Processing Loop

```swift
func queueMisses(_ misses: [CacheMiss]) {
  // Add to dictionary (auto-dedup by key)
  for miss in misses {
    pendingMisses[miss.cacheKey] = miss
  }

  // Start processing if not running
  if generationTask == nil {
    generationTask = Task { await processQueue() }
  }
}

func processQueue() async {
  while !pendingMisses.isEmpty {
    // 1. Take batch of 10
    let batch = Array(pendingMisses.values.prefix(10))
    for key in batch.map(\.cacheKey) {
      pendingMisses.removeValue(forKey: key)
    }

    // 2. Reset LLM sessions (per kind/provider)
    resetSessionsForBatch(batch)

    // 3. Generate summaries
    await processBatch(batch)

    // 4. Rate limit
    try? await Task.sleep(nanoseconds: 2_000_000_000)
  }
}
```

### Batch Processing

**Per-entry workflow:**
```swift
func processBatch(_ batch: [CacheMiss]) async {
  for miss in batch {
    // 1. Call LLM (with retry)
    let result = await withRetry(maxAttempts: 3) {
      try await FoundationLLM.shared.generateSummary(
        content: miss.content,
        context: miss.context,
        kind: miss.kind,
        provider: miss.provider
      )
    }

    // 2. Save to SQL cache ONLY (not to transcript_entries)
    let cache = TimelineCache(
      contentSha256: miss.contentSha256,
      windowSha256: miss.windowSha256,
      entryId: miss.entryId,
      disposition: result.disposition,  // Source of truth for isDirective/isCompletion
      presentForm: result.present,
      pastForm: result.past,
      selectedForm: result.selectedForm,
      verbLemma: result.verbLemma,
      ...
    )
    try orchestrator.saveCachedTimeline(cache)
    // Note: No longer writes to transcript_entries (post-v6 schema)

    // 3. Post notification
    NotificationCenter.default.post(
      name: .timelineCacheUpdated,
      object: miss.cacheKey
    )
  }
}
```

**Circuit Breaker:** Per-batch threshold: stop current batch after repeated failures; next batch proceeds after the normal ~2s delay. Per-session threshold: 15 requests or 3 consecutive errors → session reset.

---

## FoundationLLM (Actor)

### Session Management

**Controller Cache:**
```swift
actor FoundationLLM {
  // Per-kind/provider sessions
  private var controllers: [String: ControllerEntry] = [:]

  struct ControllerEntry {
    var controller: SessionController
    var lastUsed: Date
  }

  func getOrCreateController(kind: TimelineEntryKind, provider: Provider)
    -> SessionController {
    let key = instructionsForTimeline(kind: kind, provider: provider)

    if let entry = controllers[key] {
      controllers[key]?.lastUsed = Date()
      return entry.controller
    }

    // Create new session with instructions
    let instructions = """
      You are summarizing \(provider.displayName) \(kind) messages.
      Generate present tense: "\(provider.displayName) proposes..."
      Generate past tense: "\(provider.displayName) proposed..."
      """

    let controller = SessionController(instructions: instructions)
    controllers[key] = ControllerEntry(controller: controller, lastUsed: Date())
    return controller
  }
}
```

**Idle Eviction:** Sessions unused for 5 minutes → reset and removed.

**Why per-kind/provider sessions?**
- User messages → "You asked..."
- Assistant messages → "Claude proposes..." or "Codex implemented..."
- Different prompting strategies per message type

### SessionController Concurrency (FIFO + Cancellation-Safe)

**Design:** SessionController enforces FIFO access with ordered queue and cancellation-safe token handoff.

```swift
actor SessionController {
  private var waitOrder: [UUID] = []  // FIFO queue
  private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
  private var currentHolder: UUID?

  // Request token (FIFO)
  func acquireToken() async -> Token {
    let id = UUID()
    waitOrder.append(id)

    if currentHolder != nil {
      await withCheckedContinuation { continuation in
        continuations[id] = continuation
      }
    }

    currentHolder = id
    return Token(id: id, release: { [weak self] in
      await self?.releaseToken(id)
    })
  }

  // Release token and resume next waiter
  private func releaseToken(_ id: UUID) {
    guard currentHolder == id else { return }

    waitOrder.removeAll { $0 == id }
    continuations.removeValue(forKey: id)

    // Resume next in queue
    if let next = waitOrder.first, let cont = continuations[next] {
      cont.resume()
    } else {
      currentHolder = nil
    }
  }

  // Cancel waiter (doesn't call release)
  func cancelWaiter(_ id: UUID) {
    waitOrder.removeAll { $0 == id }
    continuations.removeValue(forKey: id)
  }
}
```

**Key Properties:**
- **FIFO ordering:** `waitOrder` preserves request order
- **Cancellation-safe:** Cancelled waiters removed without calling `release()`
- **Token ownership:** Only current holder can `release()`; resumed waiter receives token when `release()` runs

### Generation API

```swift
@available(macOS 26.0, *)
func generateSummary(
  content: String,
  context: String,
  kind: TimelineEntryKind,
  provider: Provider
) async throws -> (present: String, past: String, disposition: Disposition) {

  let controller = getOrCreateController(kind: kind, provider: provider)

  let prompt = """
    Content: \(content)
    Context: \(context)

    Generate JSON:
    {
      "present": "...",
      "past": "...",
      "disposition": "proposes" | "implements" | "asks" | ...
    }
    """

  let response = try await controller.respond(to: prompt)
  let parsed = try parseJSON(response)

  return (parsed.present, parsed.past, parsed.disposition)
}
```

**Timeout:** LanguageModelSession has built-in timeout (~30s).

**Token Overflow:** If content > 4096 tokens, throw `.contextOverflow` (non-retryable).

---

## Error Handling

### Retry Strategy

```swift
func withRetry<T>(maxAttempts: Int, operation: () async throws -> T)
  async throws -> T {
  var lastError: Error?

  for attempt in 1...maxAttempts {
    do {
      return try await operation()
    } catch let error as TimelineError where !error.isRetryable {
      throw error  // Don't retry guardrail violations, token overflows
    } catch {
      lastError = error
      if attempt < maxAttempts {
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1s backoff
      }
    }
  }

  throw lastError!
}
```

**Retryable Errors:**
- `.llmTimeout` (30s timeout)
- `.databaseError` (SQL write failure)
- `.unexpected` (unknown error)

**Non-Retryable Errors:**
- `.contextOverflow` (content too long)
- `.guardrailViolation` (safety filters)
- `.decodingFailure` (invalid JSON response)
- `.llmUnavailable` (macOS < 26.0 or FoundationModels not available)

### TimelineError Enum

```swift
enum TimelineError: Swift.Error {
  case llmTimeout
  case contextOverflow(tokens: Int, limit: Int)
  case guardrailViolation(reason: String)
  case decodingFailure(reason: String)
  case databaseError(String)
  case unexpected(String)
  case cancelled
  case llmUnavailable(reason: String)

  var isRetryable: Bool {
    switch self {
    case .llmTimeout, .databaseError, .unexpected: return true
    case .contextOverflow, .guardrailViolation, .decodingFailure, .cancelled, .llmUnavailable: return false
    }
  }

  var userMessage: String {
    switch self {
    case .llmTimeout:
      return "Summary generation timed out. Please try again."
    case .contextOverflow(let tokens, let limit):
      return "Message too long (\(tokens) tokens, limit \(limit))."
    case .guardrailViolation(let reason):
      return "Content could not be summarized due to safety filters: \(reason)"
    case .decodingFailure(let reason):
      return "Summary format was invalid: \(reason)"
    case .databaseError(let msg):
      return "A database error occurred: \(msg)"
    case .unexpected(let msg):
      return "An unexpected error occurred: \(msg)"
    case .cancelled:
      return "Operation was cancelled."
    case .llmUnavailable(let reason):
      return reason
    }
  }
}
```

### Fallback Behavior

```swift
// If LLM unavailable or all retries fail
let fallback = generateFallbackSummary(content: content, kind: kind)
// → "Claude sent a message" or "You asked a question"
```

**Never block UI:** Cache miss → show fallback → async LLM → update UI.

---

## LLM Health Checking

### Problem: SystemLanguageModel.availability is Insufficient

`SystemLanguageModel.default.availability` returns `.available` even when LLM is broken by runtime errors.

**What it detects:**
- `.appleIntelligenceNotEnabled`, `.deviceNotEligible`, `.modelNotReady`

**What it misses:**
- System file errors (missing metadata.json)
- Runtime guardrail system failures

### Solution: "Belt and Suspenders" Approach

```swift
// 1. Check official API (.available?)
// 2. Perform actual test LLM call
// 3. Inspect error patterns for system failures
```

**Implementation:** `LLMHealthCheck.swift` (actor, 30s cache)

### Known Error Pattern: Missing metadata.json

**Symptom:** macOS 26 system bug (observed in 26.0.1 production) causes ALL LLM calls to fail with `guardrailViolation`.

**Detection:**
```swift
catch let error as LanguageModelSession.GenerationError {
  if case .guardrailViolation(let context) = error {
    if String(describing: context).contains("metadata.json") {
      // System error, not content issue
    }
  }
}
```

**Reference:** https://www.reddit.com/r/iOSProgramming/comments/1la7o9r/comment/n41eh7d/

### Integration

App launch performs health check; notifies user if LLM unavailable. Circuit breaker still protects against transient failures during operation.

**Future:** Status bar indicator (see TODOS.md:404-603)

---

## Performance Characteristics

| Metric | Target | Measured |
|--------|--------|----------|
| Cache hit latency | <5ms | ~3ms (SQL query) |
| Cache miss (LLM) | <2s | ~1.5s (FoundationLLM) |
| Batch processing | 10 entries/2s | ~5 entries/s |
| Queue capacity | 5000 | No drops observed |

**Optimization:** Batch size (10) and rate limit (2s) tuned to balance:
- LLM load (avoid overwhelming on-device model)
- UI responsiveness (summaries appear within ~2s)
- Background CPU usage (<10% sustained)

---

## Cache Invalidation

### When Cache Misses Occur

1. **New entry:** Content never seen before
2. **Context change:** Same content, different window (prev1/prev2 changed)
3. **Generator update:** `generator_signature` changed (new prompt version)

**Example:** Prompt tuning → bump `generator_signature` → all entries miss → regenerate.

### Regeneration Strategy

**Manual:** Admin can delete from `timeline_cache` → misses on next load.

**Automatic:** Not implemented (cache never expires).

---

## Integration with ConversationMonitor

See: `technical-reference/conversation-monitor-state-architecture.md`

**Lifecycle:**
```swift
// 1. Initialize
let generator = TimelineCacheMissGenerator(orchestrator: orchestrator)

// 2. Load feed with cache
let feed = try orchestrator.getRecentFeed(forProject: projectId, limit: 50)

// 3. Detect misses
let misses: [CacheMiss] = feed.compactMap { (entry, cache) in
  guard cache == nil else { return nil }
  return CacheMiss(from: entry)
}

// 4. Queue for background generation
generator.queueMisses(misses)

// 5. Listen for cache updates
NotificationCenter.default.addObserver(
  forName: .timelineCacheUpdated,
  object: nil,
  queue: .main
) { notification in
  // Refresh UI with newly cached entry
  self.updateCacheForKey(notification.object as! CacheKey)
}
```

---

## Testing

**Unit Tests:** `TimelineCacheMissGeneratorTests` (if implemented)
- Deduplication correctness (same key → one LLM call)
- Queue capacity (overflow handling)
- Retry logic (retryable vs non-retryable errors)

**Integration Tests:** `IntegrationTests.swift`
- Full flow: load feed → detect misses → generate → cache → reload
- Circuit breaker activation (simulate 5+ failures)

**Manual Testing:**
- Delete `timeline_cache` table → observe regeneration
- Monitor LLM latency in Console (filter: "CacheMissGenerator")

---

## Cross-References

- **SQL Backend:** `build/notes/technical-reference/sql-backend-architecture.md`
- **State Management:** `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Database Schema:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- **LLM Implementation:** `Contextify/Contextify/FoundationLLM.swift`
- **LLM Health Check:** `Contextify/Contextify/LLMHealthCheck.swift`
