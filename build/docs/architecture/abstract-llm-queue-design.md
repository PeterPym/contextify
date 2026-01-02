# Abstract LLM Work Queue - Design Document

**Status:** UNIMPLEMENTED - Historical Design Proposal
**Date:** 2025-11-09
**Author:** Transcript Window Refactoring (Phase 0)

> **Note (2025-12):** This design was never implemented. The abstract `LLMWorkQueue` infrastructure does not exist. Both `TimelineCacheMissGenerator` and `TranscriptMetadataOrchestrator` remain independent implementations with their own queue logic. See `llm-processing.md` for current architecture.
>
> This document is preserved as a reference for potential future refactoring but does not reflect the actual codebase.

---

## Executive Summary

This document describes the design of a **reusable, generic LLM work queue** that captures the common patterns from `TimelineCacheMissGenerator` and `TranscriptMetadataOrchestrator`, while allowing specialization through configuration and protocol-based customization.

**Goals:**
1. Eliminate code duplication between timeline and transcript LLM queues
2. Provide clean abstraction that supports both FIFO batched and concurrent processing
3. Enable future LLM features to reuse the same infrastructure
4. Maintain backwards compatibility with existing status bar integration

**Non-Goals:**
1. Merging timeline and transcript into a single queue (they serve different purposes)
2. Changing the QueueStatsProvider protocol (it's already well-designed)
3. Modifying ConversationMonitor or TimelineCacheMissGenerator in Phase 1

---

## Current Architecture Analysis

### Common Patterns (Can Be Abstracted)

Both `TimelineCacheMissGenerator` and `TranscriptMetadataOrchestrator` share:

1. **Actor-based concurrency** for thread-safe queue management
2. **QueueStatsProvider conformance** for status bar integration
3. **AsyncStream observers** for real-time queue state updates
4. **FoundationLLM integration** for on-device LLM calls
5. **SQL caching** to avoid redundant LLM work
6. **Error tracking** with sliding time windows
7. **Task lifecycle management** (start, process, cancel, shutdown)
8. **Deduplication** to prevent processing the same work twice
9. **Notification on queue changes** to update observers

### Key Differences (Require Configuration)

| Aspect | TimelineCacheMissGenerator | TranscriptMetadataOrchestrator |
|--------|---------------------------|-------------------------------|
| **Processing Model** | LIFO sequential (one item at a time) | LIFO sequential (one item at a time) |
| **Batch Size** | 1 (sequential only) | 1 (sequential only) |
| **Inter-batch Delay** | 0ms | 0ms |
| **Deduplication Key** | `CacheKey` (content+window hash) | `String` (transcript ID) |
| **Pruning** | Viewport-aware + project-based | Viewport-aware (500ms debounce) |
| **Error Handling** | Per-item retry (3 attempts) | Circuit breaker fallback |
| **Rate Limiting** | Stabilization delay (750ms) | Circuit breaker |
| **LLM Session Strategy** | Per kind+provider pair | Per transcript ID |
| **FK Safety** | Pre-flight check via `existingEntryIds()` | Throws on FK error |
| **Queue Order** | LIFO (newest first, via `insert(at: 0)`) | LIFO (newest first, via `insert(at: 0)` + reverse) |

---

## Design Principles

### 1. Protocol-Oriented Architecture

Use **protocols for customization points** rather than complex generics or inheritance:

```swift
/// Defines how work items are processed
protocol LLMWorkProcessor: Sendable {
    associatedtype WorkItem: Sendable & Hashable
    associatedtype WorkResult: Sendable

    /// Process a single work item (may throw)
    func process(_ item: WorkItem) async throws -> WorkResult

    /// Cache the result (may throw)
    func cache(_ result: WorkResult, for item: WorkItem) async throws

    /// Generate deduplication key
    func deduplicationKey(for item: WorkItem) -> AnyHashable

    /// Optional: Check if item should be kept (for pruning)
    func shouldKeep(_ item: WorkItem, context: PruningContext) -> Bool
}
```

### 2. Configuration Over Code

Use **struct-based configuration** for processing behavior:

```swift
struct LLMQueueConfiguration: Sendable {
    enum ProcessingMode: Sendable {
        case fifo(batchSize: Int, delayBetweenBatchesMs: Int)
        case concurrent(maxConcurrent: Int)
    }

    enum ErrorStrategy: Sendable {
        case retry(maxAttempts: Int)
        case circuitBreaker(CircuitBreaker)
        case hybrid(retries: Int, then: CircuitBreaker)
    }

    let processingMode: ProcessingMode
    let errorStrategy: ErrorStrategy
    let maxQueueSize: Int
    let stabilizationDelayMs: Int  // Wait before processing (allows pruning)
    let enableViewportPruning: Bool
    let enableProjectPruning: Bool
}
```

### 3. Observer Pattern (Already Proven)

Keep the existing `QueueStatsProvider` protocol - it's clean and works well:

```swift
protocol QueueStatsProvider: Sendable {
    func observeQueue() -> AsyncStream<QueueStats>
}

struct QueueStats: Sendable, Equatable {
    let pending: Int
    let isProcessing: Bool
    let currentBatchSize: Int
    let estimatedSecondsRemaining: Int
    let recentErrorCount: Int
    let topErrorReason: String?
}
```

### 4. Type Safety via Generics

Use generics for type-safe work items, but keep the API simple:

```swift
actor LLMWorkQueue<Processor: LLMWorkProcessor>: QueueStatsProvider {
    typealias WorkItem = Processor.WorkItem
    typealias WorkResult = Processor.WorkResult

    let processor: Processor
    let config: LLMQueueConfiguration

    // Public API
    func enqueue(_ items: [WorkItem]) async
    func pruneQueue(keepOnly visibleIDs: Set<String>) async
    func clearPending(exceptProjectId: String?) async
    func shutdown() async

    // QueueStatsProvider
    func observeQueue() -> AsyncStream<QueueStats>
}
```

---

## Implementation Plan

### Phase 1A: Core Infrastructure

**File:** `Contextify/Contextify/LLM/LLMWorkQueue.swift`

1. Define `LLMWorkProcessor` protocol
2. Define `LLMQueueConfiguration` struct
3. Define `PruningContext` struct (for viewport/project pruning)
4. Implement basic `LLMWorkQueue` actor:
   - Queue storage (array + deduplication set)
   - Enqueue with deduplication
   - QueueStatsProvider conformance
   - Observer management (UUID-keyed dictionary)

### Phase 1B: Processing Modes

Implement both processing modes:

1. **FIFO Batched Processing:**
   ```swift
   private func processFIFO() async {
       while !pending.isEmpty {
           let batch = Array(pending.prefix(config.batchSize))
           pending.removeFirst(batch.count)

           for item in batch {
               await processItem(item)
           }

           if config.delayMs > 0 {
               try? await Task.sleep(for: .milliseconds(config.delayMs))
           }
       }
   }
   ```

2. **Concurrent Processing:**
   ```swift
   private func processConcurrent() async {
       await withTaskGroup(of: Void.self) { group in
           for item in pending {
               group.addTask {
                   await self.processItem(item)
               }

               if group.count >= config.maxConcurrent {
                   await group.next()
               }
           }
       }
   }
   ```

### Phase 1C: Error Handling

Implement error strategies:

1. **Retry Strategy:**
   ```swift
   private func processWithRetry(_ item: WorkItem, maxAttempts: Int) async {
       for attempt in 1...maxAttempts {
           do {
               let result = try await processor.process(item)
               try await processor.cache(result, for: item)
               await recordSuccess()
               return
           } catch {
               if attempt == maxAttempts {
                   await recordError(error, for: item)
                   throw error
               }
               // Exponential backoff
               let delayMs = min(1000 * (1 << (attempt - 1)), 8000)
               try? await Task.sleep(for: .milliseconds(delayMs))
           }
       }
   }
   ```

2. **Circuit Breaker Strategy:**
   ```swift
   private func processWithCircuitBreaker(_ item: WorkItem) async throws {
       guard await circuitBreaker.allow() else {
           // Use fallback (processor must handle this)
           let result = try await processor.processFallback(item)
           try await processor.cache(result, for: item)
           return
       }

       do {
           let result = try await processor.process(item)
           try await processor.cache(result, for: item)
           await circuitBreaker.recordSuccess()
       } catch {
           await circuitBreaker.recordFailure()
           throw error
       }
   }
   ```

### Phase 1D: Pruning Support

Implement pruning mechanisms:

```swift
func pruneQueue(keepOnly visibleIDs: Set<String>) async {
    guard config.enableViewportPruning else { return }

    let context = PruningContext(
        visibleIDs: visibleIDs,
        activeItemKey: currentlyProcessing
    )

    let beforeCount = pending.count
    pending.removeAll { item in
        !processor.shouldKeep(item, context: context)
    }

    if pending.count < beforeCount {
        notifyQueueChanged()
    }
}

func clearPending(exceptProjectId: String?) async {
    guard config.enableProjectPruning else { return }

    let context = PruningContext(
        activeProjectId: exceptProjectId,
        activeItemKey: currentlyProcessing
    )

    let beforeCount = pending.count
    pending.removeAll { item in
        !processor.shouldKeep(item, context: context)
    }

    if pending.count < beforeCount {
        notifyQueueChanged()
    }
}
```

---

## Migration Strategy (Not Executed)

> **Note:** This migration was never executed. Steps 1-3 were not completed.

### Step 1: Implement Abstract Queue (This PR)

1. Create `LLMWorkQueue` infrastructure
2. Write unit tests for both processing modes
3. Write unit tests for error strategies
4. Document usage patterns

### Step 2: Migrate TranscriptMetadataOrchestrator (This PR)

Create a processor implementation:

```swift
struct TranscriptMetadataProcessor: LLMWorkProcessor {
    typealias WorkItem = TranscriptSession
    typealias WorkResult = TranscriptMetadata

    let orchestrator: TranscriptOrchestrator
    let builder: ContextBuilder
    let postProcessor: MetadataPostProcessor

    func process(_ item: TranscriptSession) async throws -> TranscriptMetadata {
        // Existing generateMetadata() logic
        let entries = try orchestrator.getEntries(forTranscript: item.identifier)
        let exchanges = convertEntriesToExchanges(entries)

        // Check cache first
        if let cached = try orchestrator.getMetadata(forTranscript: item.identifier) {
            if try await isFresh(cached, fileURL: item.fileURL) {
                return cached.toUIModel()
            }
        }

        // Build context and call LLM
        let context = try builder.build(exchanges: exchanges, strategy: .adaptive)
        let guided = try await FoundationLLM.shared.generateGuided(...)
        return postProcessor.apply(to: guided, context: context.text)
    }

    func cache(_ result: TranscriptMetadata, for item: TranscriptSession) async throws {
        try await saveToSQL(result, transcriptId: item.identifier, orchestrator: orchestrator)
    }

    func deduplicationKey(for item: TranscriptSession) -> AnyHashable {
        AnyHashable(item.fileURL)
    }

    func shouldKeep(_ item: TranscriptSession, context: PruningContext) -> Bool {
        // Transcripts don't use viewport pruning
        return true
    }
}
```

Then replace `TranscriptMetadataOrchestrator` with:

```swift
actor TranscriptMetadataOrchestrator: QueueStatsProvider {
    static let shared = TranscriptMetadataOrchestrator()

    private let queue: LLMWorkQueue<TranscriptMetadataProcessor>

    private init() {
        let config = LLMQueueConfiguration(
            processingMode: .concurrent(maxConcurrent: 5),
            errorStrategy: .circuitBreaker(CircuitBreaker(...)),
            maxQueueSize: 1000,
            stabilizationDelayMs: 0,
            enableViewportPruning: false,
            enableProjectPruning: false
        )

        self.queue = LLMWorkQueue(
            processor: TranscriptMetadataProcessor(...),
            config: config
        )
    }

    func ensureMetadata(for session: TranscriptSession) async throws -> TranscriptMetadata {
        await queue.enqueue([session])
        // Wait for result (queue returns via cache or throws)
    }

    func observeQueue() -> AsyncStream<QueueStats> {
        queue.observeQueue()
    }
}
```

### Step 3: Validate (This PR)

1. Build and run app
2. Open transcripts
3. Verify metadata generation works
4. Check status bar integration
5. Test error handling (circuit breaker)
6. Test concurrent processing

### Step 4: Migrate TimelineCacheMissGenerator (Future PR)

**DO NOT DO IN THIS PR** - this is future work to avoid destabilizing the proven conversation log.

Create a processor implementation:

```swift
struct TimelineCacheProcessor: LLMWorkProcessor {
    typealias WorkItem = CacheMiss
    typealias WorkResult = (present: String, past: String, disposition: String)

    func process(_ item: CacheMiss) async throws -> WorkResult {
        // Existing LLM call logic
        let summary = try await FoundationLLM.shared.generateSummary(...)
        return (summary.present, summary.past, summary.disposition)
    }

    func cache(_ result: WorkResult, for item: CacheMiss) async throws {
        try orchestrator.cacheTimelineEntry(...)
    }

    func deduplicationKey(for item: CacheMiss) -> AnyHashable {
        AnyHashable(item.cacheKey)
    }

    func shouldKeep(_ item: CacheMiss, context: PruningContext) -> Bool {
        // Check visibility and project
        context.visibleIDs.contains(item.entryId) ||
        item.entryId == context.activeItemKey ||
        item.projectId == context.activeProjectId
    }
}
```

---

## Benefits of This Design

### 1. Code Reuse
- Eliminates ~400 lines of duplicated queue management logic
- Shared error tracking, observer management, stats calculation
- Shared pruning algorithms

### 2. Type Safety
- Generics ensure work items and results match processor expectations
- Protocol constraints prevent misuse
- Compiler catches configuration errors

### 3. Testability
- Mock processors for unit testing queue behavior
- Configuration-based testing (test FIFO vs concurrent separately)
- No need to mock FoundationLLM for queue tests

### 4. Extensibility
- New LLM features just implement `LLMWorkProcessor`
- No need to duplicate queue infrastructure
- Mix and match processing modes and error strategies

### 5. Observability
- Unified QueueStatsProvider conformance
- Status bar "just works" with any LLMWorkQueue instance
- Easy to add new observability metrics

---

## Risks & Mitigations

### Risk: Over-abstraction

**Symptom:** Generic code becomes hard to understand or maintain
**Mitigation:**
- Keep protocols simple (4-5 methods max)
- Document each processor implementation thoroughly
- Provide example implementations (Timeline, Transcript)

### Risk: Performance Regression

**Symptom:** Abstract queue slower than specialized implementations
**Mitigation:**
- Profile both before and after migration
- Keep hot paths simple (no excessive indirection)
- Use `@inlinable` for critical methods if needed

### Risk: Breaking Existing Code

**Symptom:** Status bar stops updating, queue stops processing
**Mitigation:**
- Migrate one queue at a time (Transcript first, Timeline later)
- Keep existing code until migration proven
- Extensive testing before removing old implementations

---

## File Structure (Proposed, Not Implemented)

> **Note:** These files were never created. The directory `Contextify/Contextify/LLM/` does not exist.

```
Contextify/Contextify/LLM/
├── LLMWorkQueue.swift           # Core queue infrastructure
├── LLMWorkProcessor.swift       # Protocol definitions
├── LLMQueueConfiguration.swift  # Configuration types
├── TimelineCacheProcessor.swift # Timeline implementation (future)
└── TranscriptMetadataProcessor.swift  # Transcript implementation
```

**Actual current files:**
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - Timeline queue (independent implementation)
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` - Metadata queue (independent implementation)
- `Contextify/Contextify/QueueStatsProvider.swift` - Protocol for status bar integration

---

## Success Criteria

> **Status:** None of these criteria were achieved - this design was not implemented.

- [ ] `LLMWorkQueue` actor implemented with both processing modes
- [ ] `TranscriptMetadataProcessor` implemented and tested
- [ ] `TranscriptMetadataOrchestrator` migrated to use `LLMWorkQueue`
- [ ] Status bar integration working (QueueStatsProvider conformance)
- [ ] Error handling working (circuit breaker + fallback)
- [ ] No regressions in transcript metadata generation
- [ ] Code size reduction: ~300 lines saved via abstraction
- [ ] Documentation complete (this doc + inline comments)

---

## Related Documentation

- **LLM Architecture:** `build/docs/architecture/llm-processing.md`
- **Timeline Cache:** `build/docs/components/timeline-cache.md`
- **Status Bar:** `build/docs/archive/feature-specs/status-bar.md`
- **Intent Document:** `build/notes/transcript-window-refactor-intent-v2.md`
- **Current Implementations:**
  - `Contextify/Contextify/TimelineCacheMissGenerator.swift`
  - `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`
  - `Contextify/Contextify/QueueStatsProvider.swift`

---

## Conclusion

> **Historical Note (2025-12):** This design was not implemented. The abstract queue infrastructure was proposed but development proceeded with the existing independent implementations. Both `TimelineCacheMissGenerator` and `TranscriptMetadataOrchestrator` continue to work well as standalone actors.

This abstract queue design proposed a **clean, type-safe, and extensible foundation** for all LLM work in Contextify. The intended benefits were:

1. **Reduce duplication** (~300 lines saved)
2. **Improve maintainability** (one place to fix queue bugs)
3. **Enable future features** (easy to add new LLM work types)
4. **Maintain compatibility** (QueueStatsProvider unchanged)

**Why it wasn't implemented:** The existing implementations work well and the refactoring effort was deprioritized in favor of other features. The code duplication between the two queues is manageable, and both share the `QueueStatsProvider` protocol for status bar integration which provides the key shared abstraction.

**For current architecture:** See `llm-processing.md` which documents the actual implementation.
