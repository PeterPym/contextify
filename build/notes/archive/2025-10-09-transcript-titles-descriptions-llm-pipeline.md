# SYSTEM PROMPT FOR LLM EXECUTION

You are a senior software architect tasked with designing a system to generate rich metadata (titles and descriptions) for conversational AI transcripts. Your goal is to propose one or more practical, production-ready solutions that:

1. **Handle scale gracefully**: Transcripts can range from 50 to 10,000+ lines
2. **Address multi-topic conversations**: Many transcripts explore 3-8 unrelated topics (refactoring, then bug fixes, then documentation, then feature work)
3. **Produce high-quality output**: Titles should be concise (≤60 chars), descriptions informative (≤200 chars)
4. **Enable iterative refinement**: Prompt engineering will evolve; easy regeneration is critical
5. **Balance performance and quality**: Local LLM (FoundationModels on macOS 26) has ~2-3 second latency per call
6. **Integrate cleanly**: Must fit into existing Swift 6 codebase with SwiftUI UI

Your proposals should cite specific LLM pipeline patterns (Map-Reduce, Hierarchical, Chain-of-Thought, Progressive Refinement, etc.) and explain how they apply to this domain. Consider the tradeoffs between accuracy, latency, storage complexity, and UX.

Be specific about:
- Chunking strategies for long transcripts
- How to detect topic boundaries
- When to use single-pass vs multi-pass approaches
- Storage format and cache invalidation
- UI for forcing regeneration
- Handling edge cases (very short transcripts, corrupted JSON, etc.)

---

# Technical Brief: LLM-Generated Transcript Titles and Descriptions

**Date:** 2025-10-09
**Author:** System (via ultrathinking mode)
**Status:** Proposal / Design Phase
**Related Feature:** Transcript Inventory Enhancement

## 1. Problem Statement

### Current State
The Transcript Inventory View (`TranscriptInventoryView.swift`) displays a list of AI conversation transcripts with minimal metadata:

- **Identifier**: Filename (UUID-based, e.g., `16093e60-2cf4-4501-b841-ee7a6d072e88.jsonl`)
- **Provider**: "Claude Code" or "Codex CLI" with icon
- **Last Activity**: Relative timestamp ("2 hours ago")

This provides no insight into conversation content. Users must:
1. Click on each transcript
2. Read raw file or infer from filename
3. Remember what they discussed in each session

### Desired State
Each transcript should display:

- **Title**: Concise summary (≤60 chars) like "Transcript Inventory Window Migration"
- **Description**: Brief overview (≤200 chars) like "Converted modal sheet to independent window. Fixed Swift 6 Sendable violations. Added public APIs for session management."

These should be:
- **Automatically generated** by local LLM (FoundationModels)
- **Persistently stored** (survive app restarts)
- **Regenerable** (prompt engineering iteration, user-requested refresh)
- **Fast to retrieve** (no LLM call on inventory view load)

### Scale Characteristics

Real-world transcript analysis:
```
Sample: 395 lines (16093e60-2cf4-4501-b841-ee7a6d072e88.jsonl)
Size: ~500 KB (typical: 100-2000 KB)
Structure: JSONL (one JSON object per line)
Content types: user messages, assistant messages, file-history-snapshot, system events
Typical session: 30-100 exchanges (60-200 messages)
Long session: 200+ exchanges (400+ messages)
```

## 2. Research: LLM Pipeline Patterns

### 2.1 Map-Reduce Summarization

**Pattern**: Break text into chunks → summarize each chunk (map) → combine summaries (reduce)

**Source**: LangChain, Google Cloud Workflows
**Advantages**:
- Parallelizable (map phase can run concurrently)
- Handles arbitrary length documents
- Good for documents where sections are independent

**Disadvantages**:
- Context loss between chunks
- Not ideal for conversations with evolving topics
- Multiple LLM calls increase latency

**Application to Transcripts**:
Could chunk by message count (e.g., 50 messages per chunk), summarize each, then synthesize. However, conversation context matters—a bug fix in message 150 might relate to code written in message 20.

### 2.2 Hierarchical Summarization

**Pattern**: Summarize at increasing levels of abstraction (message → exchange → topic → conversation)

**Source**: Novel summarization research, document workflows
**Advantages**:
- Preserves narrative flow
- Natural alignment with conversation structure
- Can identify topic boundaries

**Disadvantages**:
- Requires N LLM calls for N levels
- More complex to implement
- Still context-limited at each level

**Application to Transcripts**:
Could group messages into "exchanges" (user request + assistant response), summarize exchanges, then group related exchanges into "topics," and finally synthesize conversation-level metadata.

### 2.3 Progressive Refinement

**Pattern**: Generate initial summary → iteratively refine with additional context

**Source**: Multi-stage LLM workflows
**Advantages**:
- Can improve quality over multiple passes
- Allows for specialized prompts at each stage
- Good for complex reasoning tasks

**Disadvantages**:
- High latency (multiple sequential LLM calls)
- Diminishing returns after 2-3 passes
- Complexity in orchestration

**Application to Transcripts**:
Pass 1: Extract main topics. Pass 2: Generate title based on primary topic. Pass 3: Generate description covering all topics.

### 2.4 Sliding Window with Attention

**Pattern**: Process chunks with overlap, use attention mechanism to identify salient sections

**Source**: Transformer-based summarization research
**Advantages**:
- Can handle very long documents
- Preserves local context
- Identifies key moments

**Disadvantages**:
- Requires sophisticated prompt engineering
- May miss global structure
- Overlap increases compute

**Application to Transcripts**:
Process transcript in 100-message windows with 20-message overlap. Use "attention" prompt to identify pivotal exchanges.

### 2.5 Topic Segmentation + Summarization

**Pattern**: First pass identifies topic boundaries → Second pass summarizes each topic → Third pass synthesizes

**Source**: Conversational AI research (IBM, TopicTag papers)
**Advantages**:
- Explicitly handles multi-topic conversations
- Can generate per-topic metadata
- Aligns with how humans understand conversations

**Disadvantages**:
- Three-pass process (high latency)
- Topic boundary detection is itself a hard problem
- Requires careful prompt design

**Application to Transcripts**:
**Most promising for our use case.** Conversations naturally have topic shifts ("Now let's work on the bug in FoundationLLM" → "Let's commit these changes" → "Can you document the new API?").

## 3. Current Architecture Analysis

### 3.1 Existing LLM Integration: FoundationLLM

**File**: `Contextify/Contextify/FoundationLLM.swift` (519 lines)

**Current Usage**: Timeline entry summarization
- Input: Single message (user or assistant, ≤1200 chars)
- Output: One-sentence summary (≤140 chars), completion flag, confidence score
- Pattern: Single-pass synchronous call with retry logic
- Latency: ~150ms throttle + 0.5-3s LLM call
- Structured output: Uses `@Generable` macro for type-safe JSON Schema

**Key Patterns to Reuse**:

```swift
actor FoundationLLM {
    // Throttle to prevent overwhelming LLM
    private let minRequestInterval: TimeInterval = 0.15

    // Retry with exponential backoff
    func summarizeTimeline(
        kind: TimelineEntryKind,
        text: String,
        actionHint: String? = nil,
        retryCount: Int = 0
    ) async throws -> TimelineSummaryResult {
        // ... retry logic with 0.5s, 1s, 2s backoff
    }

    // Structured output via @Generable
    @Generable(description: "Timeline summary metadata")
    struct GuidedTimelineSummary {
        @Guide(description: "One sentence (≤140 chars)")
        var summary: String

        @Guide(description: "Confidence value between 0.0 and 1.0")
        var confidence: Double
    }
}
```

**Limitations for Transcript Summarization**:
- Designed for **short, single messages** (≤1200 chars)
- **No multi-pass capability** (one call per message)
- **No chunking logic** (assumes input fits in context window)
- **No caching** (every timeline entry gets fresh LLM call)

### 3.2 Transcript Data Model

**File**: `Contextify/Contextify/ConversationSources.swift` (235 lines)

```swift
struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider  // .claudeCode or .codexCLI
    let identifier: String                         // filename
    let fileURL: URL                               // full path to .jsonl
    let lastActivity: Date                         // file modification time
}
```

**Current Metadata**: None beyond what's shown above.

**Proposed Extension**:
```swift
struct TranscriptSession: Hashable, Sendable {
    // ... existing fields ...

    // NEW: LLM-generated metadata
    var metadata: TranscriptMetadata?
}

struct TranscriptMetadata: Codable, Sendable {
    let title: String                // ≤60 chars: "Implement Feature X"
    let description: String           // ≤200 chars: "Added API, fixed bugs, wrote tests"
    let topics: [String]              // ["refactoring", "bug-fix", "documentation"]
    let generatedAt: Date             // when LLM generated this
    let llmModelVersion: String       // "SystemLanguageModel-v1.0" (for cache invalidation)
    let promptVersion: String         // "v2" (for regeneration tracking)
}
```

### 3.3 Transcript File Format

**Claude Code** (`~/.claude/projects/-Users-rob-code-contextify/*.jsonl`):
```json
{"type":"file-history-snapshot","messageId":"...","snapshot":{...},"timestamp":"2025-10-03T05:47:29.418Z"}
{"type":"user","uuid":"...","message":{"content":"Can you fix the bug in FoundationLLM?"},"timestamp":"2025-10-03T05:48:00.123Z"}
{"type":"assistant","uuid":"...","message":{"content":[{"type":"text","text":"I'll fix that bug..."}]},"timestamp":"2025-10-03T05:48:15.456Z"}
```

**Codex CLI** (`~/.codex/sessions/2025/10/03/*.jsonl`):
```json
{"timestamp":"2025-10-03T22:05:03.374Z","type":"session_meta","payload":{"id":"...","cwd":"/Users/rob/code/contextify","git":{...}}}
{"timestamp":"2025-10-03T22:05:03.374Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"..."}]}}
{"timestamp":"2025-10-03T22:05:05.123Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"text","text":"..."}]}}
```

**Parsing Requirements**:
- Filter by message type (`type=="user"` or `type=="assistant"`)
- Extract text content (handle both string and array-of-objects formats)
- Skip system metadata (file-history-snapshot, session_meta, etc.)
- Preserve message order and timestamps

### 3.4 Current UI: TranscriptInventoryView

**File**: `Contextify/Contextify/TranscriptInventoryView.swift` (383 lines)

**Sidebar Display** (line 144-178):
```swift
private func sessionRow(_ session: TranscriptSession) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    HStack {
      Image(systemName: providerIcon(session.provider))
      Text(session.identifier)  // UUID filename - not helpful!
      if session.fileURL == monitor.activeSession?.fileURL {
        Image(systemName: "circle.fill")  // Active indicator
      }
    }
    HStack(spacing: 4) {
      Text(providerName(session.provider))  // "Claude Code"
      Text("•")
      Text(relativeTime(session.lastActivity))  // "2 hours ago"
    }
  }
}
```

**Proposed Display**:
```swift
private func sessionRow(_ session: TranscriptSession) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    HStack {
      Image(systemName: providerIcon(session.provider))
      Text(session.metadata?.title ?? session.identifier)  // Title or fallback
        .font(.callout)
        .fontWeight(.medium)
      if session.fileURL == monitor.activeSession?.fileURL {
        Image(systemName: "circle.fill")
      }
    }
    if let desc = session.metadata?.description {
      Text(desc)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    HStack(spacing: 4) {
      Text(providerName(session.provider))
      Text("•")
      Text(relativeTime(session.lastActivity))
      // Show topics as tags?
      if let topics = session.metadata?.topics {
        ForEach(topics.prefix(2), id: \.self) { topic in
          Text(topic)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(4)
        }
      }
    }
  }
}
```

**Detail View** (line 229-370):
Currently shows: file path, size, line count, actions (Reveal, Open, Copy).

**Proposed Addition**:
- Display full metadata with all topics
- "Regenerate Metadata" button (forces LLM re-run)
- Show generation timestamp and prompt version
- Preview first 5-10 exchanges

## 4. Proposed Solutions

### Solution 1: Single-Pass Full-Context (Simple, Fast)

**Pattern**: Load entire transcript → truncate/sample if too large → single LLM call

**Architecture**:
```swift
actor TranscriptSummarizer {
    private let llm = FoundationLLM.shared

    func generateMetadata(for session: TranscriptSession) async throws -> TranscriptMetadata {
        // 1. Parse JSONL, extract user/assistant messages
        let messages = try parseTranscript(session.fileURL)

        // 2. Build context (first 30 + last 30 messages, or all if < 60)
        let context = buildContext(from: messages, strategy: .bookends)

        // 3. Single LLM call with structured output
        let result = try await llm.generateTranscriptSummary(context: context)

        return TranscriptMetadata(
            title: result.title,
            description: result.description,
            topics: result.topics,
            generatedAt: Date(),
            llmModelVersion: "SystemLanguageModel-v1.0",
            promptVersion: "v1"
        )
    }

    private func buildContext(from messages: [Message], strategy: ContextStrategy) -> String {
        switch strategy {
        case .bookends:
            // First 30 + last 30 messages (captures start and resolution)
            let head = messages.prefix(30)
            let tail = messages.suffix(30)
            return formatMessages(Array(head) + Array(tail))
        case .sampling:
            // Evenly sample across conversation (every Nth message)
            let sample = stride(from: 0, to: messages.count, by: max(1, messages.count / 50))
                .map { messages[$0] }
            return formatMessages(sample)
        case .full:
            // All messages (only works for short transcripts)
            return formatMessages(messages)
        }
    }
}

enum ContextStrategy {
    case bookends  // First N + Last N
    case sampling  // Every Nth message
    case full      // All messages (up to context limit)
}
```

**Prompt Design**:
```
You are analyzing a developer's conversation transcript with an AI coding assistant.

The conversation may span multiple topics (refactoring, bug fixes, documentation, new features, etc.).

Based on the messages below, generate:

1. **Title** (≤60 chars): A concise summary of the primary activity
   - Good: "Implement WebSocket Reconnection"
   - Good: "Fix Memory Leak in Parser"
   - Bad: "Conversation about code" (too vague)
   - Bad: "Developer asked Claude to help with..." (too wordy)

2. **Description** (≤200 chars): An overview covering main topics
   - Mention 2-3 key activities in order
   - Use past tense ("Implemented X, fixed Y, documented Z")
   - Be specific about what was done

3. **Topics** (array of 2-5 keywords): Main themes discussed
   - Examples: "refactoring", "bug-fix", "testing", "documentation", "feature-work"
   - Use hyphenated lowercase

Messages:
<<<
{context}
>>>
```

**Advantages**:
- ✅ Simplest to implement
- ✅ Single LLM call (~2-3 seconds)
- ✅ Good for conversations with clear start/end
- ✅ Reuses existing FoundationLLM patterns

**Disadvantages**:
- ❌ May miss middle content (bookends strategy)
- ❌ Less effective for multi-topic conversations
- ❌ Sampling strategy may miss critical exchanges
- ❌ No per-topic granularity

**Best For**: Short to medium transcripts (≤200 exchanges), single-topic conversations

---

### Solution 2: Topic-Segmented Multi-Pass (Accurate, Slower)

**Pattern**: Pass 1: Identify topic boundaries → Pass 2: Summarize each topic → Pass 3: Synthesize metadata

**Architecture**:
```swift
actor TranscriptSummarizer {
    private let llm = FoundationLLM.shared

    func generateMetadata(for session: TranscriptSession) async throws -> TranscriptMetadata {
        let messages = try parseTranscript(session.fileURL)

        // PASS 1: Identify topic boundaries (3-8 topics expected)
        let segments = try await identifyTopicSegments(messages)

        // PASS 2: Summarize each topic (parallelizable)
        let topicSummaries = try await withThrowingTaskGroup(of: TopicSummary.self) { group in
            for segment in segments {
                group.addTask {
                    try await self.summarizeTopic(segment)
                }
            }
            var results: [TopicSummary] = []
            for try await summary in group {
                results.append(summary)
            }
            return results
        }

        // PASS 3: Synthesize conversation-level metadata
        let metadata = try await synthesizeMetadata(topicSummaries)

        return metadata
    }

    private func identifyTopicSegments(_ messages: [Message]) async throws -> [MessageSegment] {
        // Build sliding window context (every 50 messages)
        let checkpoints = stride(from: 0, to: messages.count, by: 50)
        var segments: [MessageSegment] = []
        var currentStart = 0

        for checkpoint in checkpoints {
            let window = messages[max(0, checkpoint - 10)..<min(messages.count, checkpoint + 10)]
            let prompt = """
            Based on these messages, has the conversation shifted to a new topic?
            Previous topic: \(segments.last?.topic ?? "unknown")

            Messages:
            \(formatMessages(Array(window)))

            Answer: yes/no and provide new topic name if yes.
            """

            let response = try await llm.detectTopicShift(prompt: prompt)
            if response.shifted {
                // Close previous segment
                if currentStart < checkpoint {
                    segments.append(MessageSegment(
                        start: currentStart,
                        end: checkpoint,
                        messages: Array(messages[currentStart..<checkpoint]),
                        topic: segments.last?.topic ?? "initialization"
                    ))
                }
                currentStart = checkpoint
            }
        }

        // Close final segment
        segments.append(MessageSegment(
            start: currentStart,
            end: messages.count,
            messages: Array(messages[currentStart..<messages.count]),
            topic: "unknown"
        ))

        return segments
    }

    private func summarizeTopic(_ segment: MessageSegment) async throws -> TopicSummary {
        let context = buildContext(from: segment.messages, strategy: .full)
        let prompt = """
        Summarize this portion of the conversation in 1-2 sentences.
        Focus on what was accomplished or discussed.

        Messages:
        \(context)
        """

        let summary = try await llm.summarize(prompt: prompt)
        return TopicSummary(
            topic: segment.topic,
            summary: summary,
            messageRange: segment.start..<segment.end
        )
    }

    private func synthesizeMetadata(_ topics: [TopicSummary]) async throws -> TranscriptMetadata {
        let topicDescriptions = topics.map { "\($0.topic): \($0.summary)" }.joined(separator: "\n")
        let prompt = """
        Based on these topic summaries, generate:
        1. A concise title (≤60 chars) for the overall conversation
        2. A description (≤200 chars) mentioning 2-3 main activities

        Topics:
        \(topicDescriptions)
        """

        let result = try await llm.synthesize(prompt: prompt)
        return TranscriptMetadata(
            title: result.title,
            description: result.description,
            topics: topics.map { $0.topic },
            generatedAt: Date(),
            llmModelVersion: "SystemLanguageModel-v1.0",
            promptVersion: "v1"
        )
    }
}

struct MessageSegment {
    let start: Int
    let end: Int
    let messages: [Message]
    var topic: String
}

struct TopicSummary {
    let topic: String
    let summary: String
    let messageRange: Range<Int>
}
```

**Advantages**:
- ✅ Handles multi-topic conversations well
- ✅ Parallel topic summarization (Pass 2)
- ✅ Per-topic granularity (can show in UI)
- ✅ More accurate overall summary

**Disadvantages**:
- ❌ 3+ LLM calls (latency: 6-9 seconds minimum)
- ❌ More complex to implement and debug
- ❌ Topic boundary detection is imperfect
- ❌ Higher risk of LLM failures cascading

**Best For**: Long transcripts (200+ exchanges), multi-topic conversations, when accuracy matters more than speed

---

### Solution 3: Hybrid Adaptive Strategy (Pragmatic)

**Pattern**: Choose strategy based on transcript characteristics

**Decision Tree**:
```swift
func chooseStrategy(for transcript: TranscriptSession) -> GenerationStrategy {
    let messages = quickParse(transcript.fileURL)
    let exchangeCount = messages.filter { $0.role == .user }.count

    switch exchangeCount {
    case 0..<20:
        // Very short: single-pass full context
        return .singlePass(contextStrategy: .full)

    case 20..<50:
        // Short-medium: single-pass bookends
        return .singlePass(contextStrategy: .bookends)

    case 50..<150:
        // Medium-long: check for topic diversity
        let topicDiversity = estimateTopicDiversity(messages)
        if topicDiversity > 0.6 {
            // Multi-topic: use segmented approach
            return .multiPass(segmentation: .dynamic)
        } else {
            // Single-topic: bookends sufficient
            return .singlePass(contextStrategy: .bookends)
        }

    case 150...:
        // Very long: always use segmented approach
        return .multiPass(segmentation: .dynamic)

    default:
        return .singlePass(contextStrategy: .bookends)
    }
}

func estimateTopicDiversity(_ messages: [Message]) -> Double {
    // Quick heuristic: count distinct keywords in user messages
    let userMessages = messages.filter { $0.role == .user }
    let keywords = Set(userMessages.flatMap { extractKeywords($0.text) })
    return Double(keywords.count) / Double(max(1, userMessages.count))
}
```

**Advantages**:
- ✅ Best of both worlds: fast for simple cases, thorough for complex ones
- ✅ User experience adapts to content
- ✅ Can add more strategies over time
- ✅ Metrics-driven (can tune thresholds)

**Disadvantages**:
- ❌ More code to maintain
- ❌ Heuristics may misclassify some transcripts
- ❌ Inconsistent latency (confusing UX?)

**Best For**: Production system with diverse transcript types

---

## 5. Storage Strategy

### 5.1 Sidecar JSON Files (Recommended)

Store metadata alongside transcripts:

```
~/.claude/projects/-Users-rob-code-contextify/
  16093e60-2cf4-4501-b841-ee7a6d072e88.jsonl          # Original transcript
  16093e60-2cf4-4501-b841-ee7a6d072e88.metadata.json  # LLM-generated metadata
```

**Format**:
```json
{
  "version": "v1",
  "title": "Implement WebSocket Reconnection",
  "description": "Added reconnection logic with exponential backoff. Fixed race condition in message queue. Updated tests.",
  "topics": ["feature-work", "bug-fix", "testing"],
  "generatedAt": "2025-10-09T10:30:00Z",
  "llmModelVersion": "SystemLanguageModel-v1.0",
  "promptVersion": "v2",
  "transcriptHash": "sha256:abc123...",  // Detect if transcript changed
  "generationMetrics": {
    "strategy": "multiPass",
    "llmCalls": 4,
    "totalLatency": 8.2,
    "messageCount": 312
  }
}
```

**Advantages**:
- ✅ Simple to implement (standard file I/O)
- ✅ No database required
- ✅ Easy to inspect/debug (plain JSON)
- ✅ Easy to version control (optional)
- ✅ Easy to delete/regenerate

**Disadvantages**:
- ❌ Requires file system writes (sandboxing concerns?)
- ❌ No atomic updates (race conditions possible)
- ❌ Must scan all files to build index

**Cache Invalidation**:
```swift
func needsRegeneration(transcript: URL, metadata: TranscriptMetadata) -> Bool {
    let transcriptHash = sha256(transcript)
    return transcriptHash != metadata.transcriptHash ||
           metadata.promptVersion != currentPromptVersion ||
           metadata.llmModelVersion != currentModelVersion
}
```

### 5.2 SQLite Database (Alternative)

```sql
CREATE TABLE transcript_metadata (
    transcript_url TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    topics_json TEXT NOT NULL,  -- JSON array
    generated_at INTEGER NOT NULL,
    llm_model_version TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    transcript_hash TEXT NOT NULL,
    generation_strategy TEXT,
    generation_latency REAL,
    message_count INTEGER
);

CREATE INDEX idx_generated_at ON transcript_metadata(generated_at);
CREATE INDEX idx_prompt_version ON transcript_metadata(prompt_version);
```

**Advantages**:
- ✅ Fast queries (indexed lookups)
- ✅ Atomic updates (ACID guarantees)
- ✅ Can store generation metrics easily
- ✅ Migration-friendly (ALTER TABLE)

**Disadvantages**:
- ❌ Adds dependency (SQLite.swift or GRDB)
- ❌ More complex setup
- ❌ Harder to inspect/debug
- ❌ Migration complexity

**Recommendation**: Start with sidecar JSON, migrate to SQLite if performance becomes an issue (>1000 transcripts).

### 5.3 Extended Attributes (macOS-Specific, Experimental)

```swift
import Foundation

func storeMetadata(_ metadata: TranscriptMetadata, for url: URL) throws {
    let data = try JSONEncoder().encode(metadata)
    let attrName = "dev.contextify.metadata"
    try url.setExtendedAttribute(data: data, forName: attrName)
}

func loadMetadata(for url: URL) throws -> TranscriptMetadata? {
    let attrName = "dev.contextify.metadata"
    guard let data = try url.extendedAttribute(forName: attrName) else {
        return nil
    }
    return try JSONDecoder().decode(TranscriptMetadata.self, from: data)
}
```

**Advantages**:
- ✅ No extra files
- ✅ Follows file on move/rename
- ✅ Atomic with file operations

**Disadvantages**:
- ❌ Lost on network drives / external volumes
- ❌ Size limit (~3.8 KB on APFS)
- ❌ Not cross-platform
- ❌ Harder to debug

**Recommendation**: Experimental only, not for production.

---

## 6. UI/UX Design

### 6.1 Generation Timing

**When to generate metadata?**

1. **Lazy on-demand** (Recommended for MVP):
   - Generate when user first views transcript detail
   - Show loading state in UI
   - Cache result to sidecar file
   - **Pro**: No upfront cost, only generate what's viewed
   - **Con**: First view is slow (2-9 seconds)

2. **Background batch on app launch**:
   - Scan all transcripts without metadata
   - Generate in background thread (limit concurrency to 2-3)
   - Update UI as results arrive
   - **Pro**: Amortized cost, pre-populated when user browses
   - **Con**: Can overwhelm LLM, burns CPU/battery on launch

3. **Incremental on file modification**:
   - Watch transcript files for changes
   - Regenerate metadata when file is modified
   - **Pro**: Always up-to-date
   - **Con**: Complex, may re-generate unnecessarily

**Recommendation**: Start with lazy on-demand (#1), add background batch (#2) later if needed.

### 6.2 Loading States

**Sidebar Row** (while generating):
```swift
private func sessionRow(_ session: TranscriptSession) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    HStack {
      Image(systemName: providerIcon(session.provider))
      if let title = session.metadata?.title {
        Text(title)
      } else if session.isGeneratingMetadata {
        HStack {
          ProgressView().controlSize(.small)
          Text("Analyzing conversation...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Text(session.identifier)  // Fallback to filename
      }
    }
    // ...
  }
}
```

**Detail View** (force regenerate button):
```swift
VStack(spacing: 8) {
  // ... existing actions ...

  Button {
    Task {
      await regenerateMetadata(for: session)
    }
  } label: {
    Label("Regenerate Metadata", systemImage: "arrow.clockwise.circle")
      .frame(maxWidth: .infinity)
  }
  .buttonStyle(.bordered)
  .disabled(session.isGeneratingMetadata)
}
```

### 6.3 Error States

**Generation Failed**:
```swift
if let error = session.metadataError {
  VStack(spacing: 8) {
    Image(systemName: "exclamationmark.triangle")
    Text("Metadata generation failed")
    Text(error.localizedDescription)
      .font(.caption)
      .foregroundStyle(.secondary)
    Button("Retry") {
      Task { await regenerateMetadata(for: session) }
    }
  }
}
```

### 6.4 Prompt Version Indicator

Show when metadata is stale:
```swift
if let metadata = session.metadata,
   metadata.promptVersion != TranscriptSummarizer.currentPromptVersion {
  HStack {
    Image(systemName: "info.circle")
    Text("Metadata generated with older prompt version")
      .font(.caption2)
    Button("Regenerate") {
      Task { await regenerateMetadata(for: session) }
    }
    .font(.caption2)
  }
  .padding(8)
  .background(Color.yellow.opacity(0.1))
  .cornerRadius(6)
}
```

---

## 7. Implementation Plan

### Phase 1: Foundation (Week 1)
- [ ] Extend `TranscriptSession` with `metadata: TranscriptMetadata?`
- [ ] Implement sidecar JSON storage (`TranscriptMetadataStore`)
- [ ] Add transcript parsing utilities (`TranscriptParser`)
- [ ] Create basic `TranscriptSummarizer` actor with single-pass strategy

### Phase 2: LLM Integration (Week 1-2)
- [ ] Design and test prompts for title/description/topics
- [ ] Implement structured output schema (`@Generable`)
- [ ] Add retry logic and error handling
- [ ] Add throttling (reuse FoundationLLM patterns)

### Phase 3: UI Integration (Week 2)
- [ ] Update `sessionRow` to display metadata
- [ ] Add loading states (ProgressView, "Analyzing...")
- [ ] Add "Regenerate" button in detail view
- [ ] Add error states and retry UI

### Phase 4: Performance & Refinement (Week 3)
- [ ] Implement lazy generation (on-demand)
- [ ] Add background batch generation (optional)
- [ ] Implement cache invalidation (transcript hash, prompt version)
- [ ] Add metrics logging (latency, strategy used, success rate)

### Phase 5: Multi-Pass Strategy (Week 3-4)
- [ ] Implement topic segmentation (Pass 1)
- [ ] Implement parallel topic summarization (Pass 2)
- [ ] Implement synthesis (Pass 3)
- [ ] Add adaptive strategy selection

### Phase 6: Testing & Polish (Week 4)
- [ ] Unit tests for parser, storage, summarizer
- [ ] Integration tests with real transcripts
- [ ] UI tests for loading/error states
- [ ] Performance testing (1000+ transcripts)

---

## 8. Example Prompts

### Single-Pass Prompt (Solution 1)

```
You are analyzing a developer's conversation with an AI coding assistant (Claude Code or Codex CLI).

Based on the messages below, generate metadata for this conversation transcript:

1. **title** (string, ≤60 chars):
   - Concise summary of primary activity
   - Start with imperative verb: "Implement", "Fix", "Refactor", "Document"
   - Examples: "Implement WebSocket Reconnection", "Fix Memory Leak in Parser"

2. **description** (string, ≤200 chars):
   - Overview covering 2-3 main activities in chronological order
   - Use past tense: "Implemented X, fixed Y, documented Z"
   - Be specific: mention file names, feature names, bug types

3. **topics** (array of strings, 2-5 items):
   - Main themes from this list: "feature-work", "bug-fix", "refactoring", "testing", "documentation", "code-review", "performance", "security", "ui-ux", "architecture"
   - Ordered by prominence (most time spent first)

Messages (showing first 30 and last 30 exchanges):
<<<
{context}
>>>

Output as JSON:
{
  "title": "...",
  "description": "...",
  "topics": ["...", "..."]
}
```

### Topic Segmentation Prompt (Solution 2, Pass 1)

```
You are analyzing a portion of a conversation between a developer and an AI assistant.

The previous segment was about: {previous_topic}

Based on these messages, has the conversation shifted to a NEW topic?

Messages:
<<<
{context}
>>>

Answer:
- **shifted**: true/false (did the topic change?)
- **new_topic**: string (if shifted, what is the new topic? Use keywords like "bug-fix", "refactoring", "feature-work", "documentation", "testing")
- **confidence**: number 0.0-1.0 (how confident are you?)

Output as JSON:
{
  "shifted": true/false,
  "new_topic": "...",
  "confidence": 0.85
}
```

### Topic Summary Prompt (Solution 2, Pass 2)

```
Summarize this segment of a conversation in 1-2 sentences.

Focus on:
- What was accomplished or discussed
- Key decisions made
- Problems solved or created

Messages:
<<<
{segment_context}
>>>

Output as JSON:
{
  "summary": "Developer implemented WebSocket reconnection logic with exponential backoff. Fixed race condition in message queue.",
  "key_files": ["WebSocketManager.swift", "MessageQueue.swift"],
  "outcome": "completed"  // or "in-progress", "blocked", "decided-not-to"
}
```

### Synthesis Prompt (Solution 2, Pass 3)

```
You are summarizing a multi-topic developer conversation.

Topic summaries (in chronological order):
<<<
1. bug-fix: Developer implemented WebSocket reconnection logic with exponential backoff. Fixed race condition in message queue.
2. testing: Wrote unit tests for reconnection logic. Added integration tests for message ordering.
3. documentation: Updated README with WebSocket behavior. Added inline comments to complex retry logic.
>>>

Generate overall conversation metadata:

1. **title** (≤60 chars): Focus on the PRIMARY topic (the one with most exchanges or highest impact)
2. **description** (≤200 chars): Mention 2-3 key activities across topics, in order
3. **topics** (array): List all topic keywords from above

Output as JSON:
{
  "title": "Implement WebSocket Reconnection",
  "description": "Added reconnection logic with exponential backoff and fixed race condition. Wrote tests and updated documentation.",
  "topics": ["feature-work", "bug-fix", "testing", "documentation"]
}
```

---

## 9. Risk Analysis

### Technical Risks

**R1: LLM Hallucination**
- **Risk**: LLM invents file names, features, or activities not in transcript
- **Mitigation**:
  - Use grounding checks (like timeline summarization)
  - Store raw message context with metadata for manual review
  - Add "report incorrect metadata" button in UI

**R2: Prompt Brittleness**
- **Risk**: Small prompt changes drastically change output quality
- **Mitigation**:
  - Version prompts (`promptVersion: "v2"`)
  - A/B test prompt changes on sample transcripts
  - Store generation metrics (confidence, grounding)

**R3: Context Window Limits**
- **Risk**: Very long transcripts exceed LLM context window (~10-20K tokens)
- **Mitigation**:
  - Always use chunking/sampling strategies
  - Test with 10,000+ line transcripts
  - Graceful degradation (show partial metadata)

**R4: File System Race Conditions**
- **Risk**: Multiple processes writing metadata simultaneously
- **Mitigation**:
  - Use atomic file writes (write to temp, rename)
  - Add file locking (flock)
  - Or use SQLite (ACID guarantees)

### Product Risks

**R5: Slow First Impression**
- **Risk**: Lazy generation means first view is slow (2-9 seconds)
- **Impact**: User frustration
- **Mitigation**:
  - Show loading state clearly ("Analyzing conversation...")
  - Add progress indicator
  - Consider background batch on launch

**R6: Prompt Evolution Invalidates Cache**
- **Risk**: Improved prompts mean all old metadata is "stale"
- **Impact**: Users see inconsistent quality
- **Mitigation**:
  - Show indicator when metadata is from old prompt
  - Add "Regenerate All" button (batch operation)
  - Limit prompt changes to major versions

**R7: Storage Growth**
- **Risk**: 1 metadata file per transcript = 1000+ extra files
- **Impact**: Slower file enumeration, clutter
- **Mitigation**:
  - Monitor metadata directory size
  - Add cleanup for old transcripts
  - Migrate to SQLite if >1000 transcripts

---

## 10. Success Metrics

**Quantitative**:
- Metadata generation success rate: >95%
- Average generation latency: <5 seconds (single-pass), <10 seconds (multi-pass)
- User satisfaction (survey): "Metadata is accurate and helpful" >4/5
- Cache hit rate: >80% (metadata already exists when user views transcript)

**Qualitative**:
- Users can quickly identify transcripts without reading content
- Multi-topic conversations are clearly described
- Regeneration after prompt improvements is seamless

---

## 11. Open Questions

1. **Should we support manual editing of metadata?**
   - Pro: Users can fix hallucinations
   - Con: Adds complexity (merge conflicts with regeneration)

2. **Should we expose per-topic metadata in UI?**
   - Pro: Rich detail for power users
   - Con: Cluttered UI for simple use case

3. **Should we version the LLM model itself?**
   - Pro: Can track quality improvements
   - Con: FoundationModels doesn't expose version API

4. **Should we support custom prompts (power user feature)?**
   - Pro: Advanced users can tune for their workflow
   - Con: Increases support burden, risk of bad outputs

5. **How to handle transcripts with no meaningful content?**
   - Example: "yes", "ok", "lgtm" (2-line conversation)
   - Should we skip generation? Show "No metadata needed"?

---

# APPENDIX A: Related Files

The following files are appended below for reference:

1. `Contextify/Contextify/FoundationLLM.swift` - Current LLM integration
2. `Contextify/Contextify/ConversationSources.swift` - Transcript data model
3. `Contextify/Contextify/TranscriptInventoryView.swift` - Current UI
4. `Contextify/Contextify/ConversationMonitor.swift` - Transcript processing logic

---

## File: Contextify/Contextify/FoundationLLM.swift


```swift
import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

actor FoundationLLM {
    static let shared = FoundationLLM()

    private let log = Logger(subsystem: "dev.contextify", category: "FoundationLLM")
    private var requestCount = 0
    private var failureCount = 0
    private var lastRequestTime: Date?

    // Throttle to prevent overwhelming the LLM
    private let minRequestInterval: TimeInterval = 0.15 // 150ms between requests

    enum Error: Swift.Error {
        case unavailable
        case unexpectedEnvironment
        case retryExhausted
    }

    struct TimelineSummaryResult: Sendable {
        let summary: String
        let isCompletion: Bool
        let icon: String?  // Optional emoji prefix (✅, 👉, ❓, etc.)
    }

    func summarizeTimeline(
        kind: TimelineEntryKind,
        text: String,
        actionHint: String? = nil,
        retryCount: Int = 0
    ) async throws -> TimelineSummaryResult {
        let maxRetries = 3
        let message = collapseWhitespace(text)

        // Throttle requests to prevent overwhelming the LLM
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                let delay = minRequestInterval - elapsed
                log.info("Throttling: sleeping \(Int(delay * 1000))ms before next request")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestTime = Date()

        requestCount += 1
        let reqNum = requestCount

        guard !message.isEmpty else {
            log.info("[\(reqNum)] timeline: empty message, using fallback")
            return fallbackSummary(kind: kind, text: text)
        }

        // Check for simple acks - these can skip LLM
        if kind == .assistant, isAck(message) {
            log.info("[\(reqNum)] timeline: ack detected, skipping LLM")
            return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, icon: nil)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                if retryCount == 0 {
                    log.info("[\(reqNum)] timeline: SystemLanguageModel available")
                }
                break
            case .unavailable:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unavailable")
                throw Error.unavailable
            @unknown default:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unknown availability")
                throw Error.unavailable
            }

            let instructions = instructionsForTimeline(kind: kind)
            let session = LanguageModelSession(instructions: instructions)

            // Use slight temperature on retries to help unstick from bad states
            let temperature = retryCount > 0 ? 0.1 : 0.0
            let options = GenerationOptions(
                sampling: .greedy,
                temperature: temperature,
                maximumResponseTokens: 150  // Need space for JSON structure + 140 char summary
            )

            let clamped = String(message.prefix(1200))
            let payloadInput: String
            if kind == .user,
               let hint = actionHint?.trimmingCharacters(in: .whitespacesAndNewlines),
               !hint.isEmpty {
                let safeHint = String(hint.prefix(300))
                payloadInput = "MESSAGE:\n<<<\(clamped)>>>\nACTION_HINT:\n<<<\(safeHint)>>>"
            } else {
                payloadInput = "MESSAGE:\n<<<\(clamped)>>>"
            }

            do {
                log.info("[\(reqNum)] timeline: requesting LLM summary (retry \(retryCount)/\(maxRetries))")
                log.info("[\(reqNum)] input: \(payloadInput, privacy: .public)")

                let response = try await session.respond(
                    to: payloadInput,
                    generating: GuidedTimelineSummary.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                let payload = response.content
                log.info("[\(reqNum)] timeline: LLM SUCCESS - grounding=\(payload.grounding), confidence=\(String(format: "%.2f", payload.confidence)), disposition=\(payload.disposition), isCompletion=\(payload.isCompletion)")
                log.info("[\(reqNum)] timeline: raw summary from LLM: '\(payload.summary, privacy: .public)'")
                do {
                    var result = try postProcess(kind: kind, payload: payload, message: clamped)

                    // Detect completion and add icon
                    if result.isCompletion {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: true, icon: "✅")
                        log.info("[\(reqNum)] timeline: completion detected, adding ✅ icon")
                    } else if kind == .user, isDirective(message) {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: false, icon: "👉")
                        log.info("[\(reqNum)] timeline: user directive detected, adding 👉 icon")
                    }

                    log.info("[\(reqNum)] timeline: FINAL summary after postProcess: '\(result.summary, privacy: .public)'")
                    // Reset failure count on success
                    failureCount = 0
                    return result
                } catch Error.retryExhausted {
                    // postProcess rejected - don't retry, just propagate up
                    failureCount += 1
                    log.error("[\(reqNum)] postProcess rejection - propagating failure without retry")
                    throw Error.retryExhausted
                } catch {
                    // Other postProcess errors
                    failureCount += 1
                    log.error("[\(reqNum)] postProcess unexpected error: \(error)")
                    throw Error.retryExhausted
                }
            } catch Error.retryExhausted {
                // Already exhausted from postProcess - just propagate
                throw Error.retryExhausted
            } catch let guarded as LanguageModelSession.GenerationError {
                failureCount += 1
                log.error("[\(reqNum)] timeline summarize guardrail triggered: \(String(describing: guarded), privacy: .public)")

                // Log the actual error context for debugging
                switch guarded {
                case .decodingFailure(let context):
                    log.error("[\(reqNum)] DECODING FAILURE: \(context.debugDescription, privacy: .public)")
                    log.error("[\(reqNum)] We sent this input: \(payloadInput, privacy: .public)")
                    log.error("[\(reqNum)] Expected schema: {summary: String, isCompletion: Bool, disposition: String, grounding: String, confidence: Double}")

                    // Try to get raw response for debugging (makes second LLM call but only on failure)
                    do {
                        let rawResponse = try await session.respond(to: payloadInput, options: options)
                        log.error("[\(reqNum)] LLM actually returned (raw): \(rawResponse.content, privacy: .public)")
                    } catch {
                        log.error("[\(reqNum)] Could not fetch raw response: \(error.localizedDescription, privacy: .public)")
                    }
                default:
                    log.error("[\(reqNum)] Other generation error: \(String(describing: guarded), privacy: .public)")
                }

                // Check if we're hitting too many failures in a row
                if failureCount >= 10 {
                    log.error("[\(reqNum)] Too many consecutive failures (\(self.failureCount)), LLM may be overloaded. Backing off longer...")
                    // Longer backoff when system is struggling
                    if retryCount < maxRetries {
                        let backoff = UInt64(pow(2.0, Double(retryCount + 2)) * 500_000_000) // 2s, 4s, 8s
                        log.warning("[\(reqNum)] Extended retry after \(backoff / 1_000_000)ms backoff...")
                        try await Task.sleep(nanoseconds: backoff)
                        return try await summarizeTimeline(kind: kind, text: text, actionHint: actionHint, retryCount: retryCount + 1)
                    }
                } else if retryCount < maxRetries {
                    let backoff = UInt64(pow(2.0, Double(retryCount)) * 500_000_000) // 0.5s, 1s, 2s
                    log.warning("[\(reqNum)] Retrying after \(backoff / 1_000_000)ms backoff...")
                    try await Task.sleep(nanoseconds: backoff)
                    return try await summarizeTimeline(kind: kind, text: text, actionHint: actionHint, retryCount: retryCount + 1)
                }

                log.error("[\(reqNum)] Retry exhausted after \(maxRetries) attempts, failing (total failures: \(self.failureCount))")
                throw Error.retryExhausted
            } catch {
                log.error("[\(reqNum)] timeline summarize unexpected error: \(error.localizedDescription, privacy: .public)")
                throw Error.retryExhausted
            }
        }
        #endif

        log.error("[\(reqNum)] timeline: FoundationModels not available (macOS < 26)")
        throw Error.unexpectedEnvironment
    }

    func fallbackSummary(kind: TimelineEntryKind, text: String) -> TimelineSummaryResult {
        let summary = sanitize(fallback(for: kind, text: text), kind: kind)
        return TimelineSummaryResult(summary: summary, isCompletion: false, icon: nil)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@Generable(description: "Timeline summary metadata for HUD entries")
struct GuidedTimelineSummary {
    @Guide(description: "One sentence (≤140 chars) starting with an allowed prefix. Use only MESSAGE content.")
    var summary: String

    @Guide(description: "true only if the MESSAGE explicitly reports completion (done/fixed/completed/merged/wrote/saved/✅).")
    var isCompletion: Bool

    @Guide(description: "Assistant disposition: ack, completion, wip, analysis, proposal, question, refusal.")
    var disposition: String

    @Guide(description: "Grounding: grounded, ungrounded, insufficient.")
    var grounding: String

    @Guide(description: "Confidence value between 0.0 and 1.0", .range(0...1))
    var confidence: Double
}
#endif

private extension FoundationLLM {
    struct PrefixPolicy {
        let allowed: [String]
        let fallback: String
    }

    func fallback(for kind: TimelineEntryKind, text: String) -> String {
        let normalized = collapseWhitespace(text)
        let policy = prefixPolicy(for: kind)
        guard !normalized.isEmpty else { return policy.fallback }
        if hasAllowedPrefix(normalized, policy: policy) {
            return normalized
        }
        return "\(policy.fallback) \(normalized)"
    }

    func sanitize(_ summary: String, kind: TimelineEntryKind) -> String {
        var output = collapseWhitespace(summary)
        let policy = prefixPolicy(for: kind)
        if output.isEmpty {
            output = policy.fallback
        } else if !hasAllowedPrefix(output, policy: policy) {
            output = "\(policy.fallback) \(output)"
        }
        if output.count > 140 {
            output = truncateAtWordBoundary(output, limit: 140)
        }
        return output
    }

    /// Truncates text at the last complete word before the character limit
    /// to avoid cutting mid-word. Adds ellipsis if truncated.
    func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        // Try to find last space before the limit
        let truncated = String(text.prefix(limit))

        // Find the last word boundary (space, punctuation, etc.)
        if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace || $0.isPunctuation }) {
            let result = String(truncated[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Only add ellipsis if we actually truncated meaningful content
            if !result.isEmpty && text.count > result.count + 5 {
                return result + "…"
            }
            return result
        }

        // No word boundary found - fall back to hard truncation but with ellipsis
        return String(text.prefix(limit - 1)) + "…"
    }

    func prefixPolicy(for kind: TimelineEntryKind) -> PrefixPolicy {
        switch kind {
        case .assistant:
            return PrefixPolicy(allowed: ["Claude"], fallback: "Claude")
        case .user:
            return PrefixPolicy(
                allowed: ["You made", "You asked", "You requested Claude"],
                fallback: "You requested Claude"
            )
        case .system:
            return PrefixPolicy(allowed: ["System"], fallback: "System")
        }
    }

    func hasAllowedPrefix(_ text: String, policy: PrefixPolicy) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:;,."))
        let lower = text.lowercased()
        for prefix in policy.allowed {
            let candidate = prefix.lowercased()
            guard lower.hasPrefix(candidate) else { continue }
            let boundary = lower.index(lower.startIndex, offsetBy: candidate.count)
            if boundary == lower.endIndex { return true }
            let scalar = lower[boundary]
            if String(scalar).rangeOfCharacter(from: separators) != nil {
                return true
            }
        }
        return false
    }


    func instructionsForTimeline(kind: TimelineEntryKind) -> String {
        switch kind {
        case .assistant:
            return """
            You fill a TimelineSummary for an AI assistant response.

            Rules:
            - Output ONE sentence starting with "Claude", ≤140 chars.
            - Use only MESSAGE content; do not introduce topics absent from MESSAGE.
            - Tense:
              * Past when completion is explicitly reported (done/✅/completed/fixed/resolved/merged/wrote/saved).
              * Present continuous ONLY for clear in-progress execution (e.g., “is running the test suite”).
              * Otherwise simple present (“explains/clarifies/confirms/proposes/asks/acknowledges”).
            - Mention tools (Write/Edit/Read/Bash/etc.) ONLY if MESSAGE explicitly says they were executed.

            Fields:
            - summary: one sentence following the rules.
            - isCompletion: true only if MESSAGE explicitly indicates completion.
            - disposition: one of ack, completion, wip, analysis, proposal, question, refusal.
            - grounding: grounded | ungrounded | insufficient.
            - confidence: 0.0–1.0 (lower for short or ungrounded inputs).

            Input format:
            MESSAGE:
            <<<assistant text>>>
            """
        case .user:
            return """
            You fill a TimelineSummary for a developer’s message.

            summary rules:
            - ONE sentence, ≤140 chars, past tense.
            - Allowed prefixes:
              • “You made …” — user reports a completed action (e.g., “I updated the file”).
              • “You asked …” — user asks a question (e.g., “Can you explain?”).
              • “You requested Claude …” — user asks Claude to act (e.g., “Fix this”, “Run tests”).
            - Special cases:
              • Bare affirmative (yes/ok/sure/y/👍/go ahead/proceed/do it/please do/sgtm/roger):
                → “You requested Claude to proceed as proposed.”
              • Bare negative (no/not now/hold off/stop/don’t):
                → “You requested Claude not to proceed.”
            - If ACTION_HINT is present, treat it as the action being approved or rejected.

            Fields:
            - summary: one sentence following the rules.
            - isCompletion: false.

            Input format:
            MESSAGE:
            <<<user text>>>
            Optional ACTION_HINT:
            <<<assistant proposal>>>
            """
        case .system:
            return """
            You fill a TimelineSummary for a neutral system event.
            - summary: one concise sentence under 140 characters.
            - isCompletion: false.
            """
        }
    }

    func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizePhrase(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.trimmingCharacters(in: .punctuationCharacters.union(CharacterSet(charactersIn: "…“”\"'")))
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized.lowercased()
    }

    func introducedTopics(message: String, summary: String) -> [String] {
        func tokens(_ source: String) -> Set<String> {
            let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._- "))
            let filtered = String(source.unicodeScalars.filter { keep.contains($0) })
            return Set(filtered.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 })
        }
        let summaryTokens = tokens(summary)
        let messageTokens = tokens(message)
        let diff = summaryTokens.subtracting(messageTokens).subtracting(bridgingLexicon)
        return Array(diff)
    }

    var bridgingLexicon: Set<String> {
        [
            "claude", "explains", "explained", "explaining", "clarifies", "clarified", "clarifying",
            "states", "stated", "says", "said", "notes", "noted", "acknowledges", "acknowledged",
            "confirms", "confirmed", "reports", "reported", "outlines", "outlined", "highlights",
            "highlighted", "advises", "advised", "suggests", "suggested", "proposes", "proposed",
            "asks", "asked", "observes", "observed", "mentions", "mentioned", "reminds", "reminded",
            "recommends", "recommended", "describes", "described", "details", "detailed", "responds",
            "responded", "summarizes", "summarized", "states", "reports", "notes", "acknowledges"
        ]
    }

    func hasCompletionToken(_ text: String) -> Bool {
        let lower = text.lowercased()
        return completionLexicon.contains { lower.contains($0) }
    }

    func isAck(_ text: String) -> Bool {
        let normalized = normalizePhrase(text)
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ")
        guard tokens.count <= 3 else { return false }
        return tokens.allSatisfy { acknowledgementLexicon.contains(String($0)) }
    }

    func isDirective(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Detect command/directive patterns
        return directiveLexicon.contains { lower.contains($0) }
    }

    var acknowledgementLexicon: Set<String> {
        ["ack", "ok", "okay", "k", "👍", "roger", "thanks", "thx", "ty", "got", "it", "understood", "noted", "sure"]
    }

    var directiveLexicon: [Substring] {
        [
            "please", "can you", "could you", "would you", "go ahead",
            "proceed", "continue", "commit", "fix", "update", "add",
            "create", "make", "build", "run", "test", "deploy",
            "implement", "refactor", "change", "modify", "remove", "delete",
            "we should", "we need to", "we could", "let's", "i want",
            "i need", "help me"
        ]
    }

    var completionLexicon: [Substring] {
        [
            "✅", "done", "completed", "finished", "fixed", "resolved", "ready",
            "build succeeded", "wrote", "saved", "applied", "merged", "shipped", "implemented"
        ]
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
private extension FoundationLLM {
    func postProcess(
        kind: TimelineEntryKind,
        payload: GuidedTimelineSummary,
        message: String
    ) throws -> TimelineSummaryResult {
        let summary = sanitize(payload.summary, kind: kind)

        if kind == .assistant {
            let leaked = introducedTopics(message: message, summary: summary)
            let grounding = payload.grounding.lowercased()
            let isGrounded = grounding == "grounded"

            // Multi-factor acceptance decision:
            // Accept if ANY of:
            // 1. Confidence ≥0.6 - trust the model when it's reasonably confident
            // 2. Low leakage (<8 tokens) with OK confidence (≥0.5)
            // 3. Grounded with any confidence ≥0.4
            // This is VERY permissive because the LLM is generally good
            let goodConfidence = payload.confidence >= 0.6
            let okConfidence = payload.confidence >= 0.5
            let minimalConfidence = payload.confidence >= 0.4
            let excessiveLeakage = leaked.count >= 8

            let shouldAccept = goodConfidence ||
                               (okConfidence && !excessiveLeakage) ||
                               (isGrounded && minimalConfidence)
            let shouldReject = !shouldAccept

            if shouldReject {
                log.warning("timeline summary REJECTED (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public)): \(leaked.joined(separator: ", "), privacy: .public)")
                // Special case: if it's just an ack, accept the generic ack message
                if isAck(message) {
                    return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, icon: nil)
                }
                // Reject but DON'T retry - it won't help since input doesn't change
                log.error("NOT retrying - postProcess rejection won't change with same input")
                throw Error.retryExhausted  // Skip straight to exhausted
            }

            if !isGrounded && leaked.count > 0 {
                log.info("timeline summary ACCEPTED despite leakage (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public))")
            }
        }

        let completion = kind == .assistant
            ? (payload.isCompletion && hasCompletionToken(summary))
            : false

        return TimelineSummaryResult(summary: summary, isCompletion: completion, icon: nil)
    }
}
#endif

#if DEBUG
extension FoundationLLM {
    func _testSanitize(_ summary: String, kind: TimelineEntryKind) async -> String {
        sanitize(summary, kind: kind)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func _testPostProcess(kind: TimelineEntryKind, payload: GuidedTimelineSummary, message: String) throws -> TimelineSummaryResult {
        try postProcess(kind: kind, payload: payload, message: message)
    }
    #endif
}
#endif
```

---

## File: Contextify/Contextify/ConversationSources.swift

```swift
import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
    func sessions(for context: ProjectContext) -> [TranscriptSession]
}

extension ConversationTranscriptProvider {
    // Default implementation for backward compatibility
    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        return sessions(for: context.workingDirectory.path)
    }
}

struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectDir = projectsDir.appendingPathComponent(projectDirName)

        guard fm.fileExists(atPath: projectDir.path) else { return [] }

        do {
            let files = try fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "jsonl" }

            return files.compactMap { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let lastMod = values?.contentModificationDate ?? .distantPast
                return TranscriptSession(
                    provider: .claudeCode,
                    identifier: fileURL.lastPathComponent,
                    fileURL: fileURL,
                    lastActivity: lastMod
                )
            }
        } catch {
            return []
        }
    }
}

struct CodexTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let codexSessionsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        guard fm.fileExists(atPath: codexSessionsDir.path) else { return [] }

        // Get git repository URL for this path (if available)
        let gitRepoURL = getGitRepositoryURL(for: projectPath)

        // Find all JSONL files in sessions directory (including subdirectories)
        let jsonlFiles = findJSONLFiles(in: codexSessionsDir)

        // Parse each file looking for session_meta with matching cwd or git repo
        return jsonlFiles.compactMap { fileURL in
            parseCodexSession(fileURL, matchingPath: projectPath, gitRepoURL: gitRepoURL)
        }
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var jsonlFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
        return jsonlFiles
    }

    private func parseCodexSession(_ fileURL: URL, matchingPath: String, gitRepoURL: String?) -> TranscriptSession? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // Read file line by line looking for session_meta
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["type"] as? String == "session_meta",
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }

            // Check if this session matches our project by cwd or git repo URL
            let sessionCwd = payload["cwd"] as? String
            let sessionGitInfo = payload["git"] as? [String: Any]
            let sessionRepoURL = sessionGitInfo?["repository_url"] as? String

            let isMatch = sessionCwd == matchingPath ||
                          (gitRepoURL != nil && sessionRepoURL == gitRepoURL)

            guard isMatch else { continue }

            // Found a matching session_meta
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let lastMod = values?.contentModificationDate ?? .distantPast

            return TranscriptSession(
                provider: .codexCLI,
                identifier: fileURL.lastPathComponent,
                fileURL: fileURL,
                lastActivity: lastMod
            )
        }

        return nil
    }

    private func getGitRepositoryURL(for path: String) -> String? {
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        let configFile = gitDir.appendingPathComponent("config")

        guard let configData = try? String(contentsOf: configFile, encoding: .utf8) else {
            return nil
        }

        // Parse git config to find remote origin URL
        let lines = configData.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }

            if trimmed.hasPrefix("[") && inOriginSection {
                inOriginSection = false
            }

            if inOriginSection && trimmed.hasPrefix("url = ") {
                return String(trimmed.dropFirst("url = ".count))
            }
        }

        return nil
    }
}

struct ActiveConversationResolver: Sendable {
    private let providers: [any ConversationTranscriptProvider]

    init(providers: [any ConversationTranscriptProvider]) {
        self.providers = providers
    }

    func resolveActiveSession(for projectPath: String) -> TranscriptSession? {
        providers
            .flatMap { $0.sessions(for: projectPath) }
            .max(by: { $0.lastActivity < $1.lastActivity })
    }

    func resolveAllSessions(for context: ProjectContext) -> [TranscriptSession] {
        providers
            .flatMap { $0.sessions(for: context) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func resolveActiveSession(for context: ProjectContext) -> TranscriptSession? {
        resolveAllSessions(for: context).first
    }
}
```

---

## File: Contextify/Contextify/TranscriptInventoryView.swift

```swift
import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedSessionURL: URL?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    Group {
      if let error = monitor.lastError, monitor.allSessions.isEmpty {
        // Show error when no transcripts found
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("Unable to Load Transcripts")
            .font(.headline)
          Text(error)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HSplitView {
          // Session list
          sessionListView
            .frame(minWidth: 250)

          // Detail view
          detailView
            .frame(minWidth: 500)
        }
      }
    }
  }

  private var selectedSession: TranscriptSession? {
    guard let url = selectedSessionURL else { return nil }
    return monitor.allSessions.first(where: { $0.fileURL == url })
  }

  @ViewBuilder
  private var sessionListView: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Transcript Inventory")
          .font(.headline)
        Spacer()
        Button {
          refreshSessions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
      }
      .padding()

      // Toolbar with grouping
      HStack {
        Picker("Group by", selection: $groupingMode) {
          ForEach(GroupingMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        Text("\(filteredSessions.count) transcripts")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with URL-based selection
      List(monitor.allSessions, id: \.fileURL, selection: $selectedSessionURL) { session in
        sessionRow(session)
          .tag(session.fileURL)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: monitor.allSessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedURL = selectedSessionURL,
           !newSessions.contains(where: { $0.fileURL == selectedURL }) {
          selectedSessionURL = nil
        }
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.fileURL == monitor.activeSession?.fileURL,
        onSelect: {
          onSelectSession(session)
        }
      )
    } else {
      emptyDetailView
    }
  }

  private var emptyDetailView: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.text")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No Transcript Selected")
        .font(.headline)
      Text("Select a transcript from the sidebar to view details")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Session Row

  @ViewBuilder
  private func sessionRow(_ session: TranscriptSession) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: providerIcon(session.provider))
          .foregroundStyle(providerColor(session.provider))
          .frame(width: 16)

        Text(session.identifier)
          .font(.callout)
          .lineLimit(1)

        if session.fileURL == monitor.activeSession?.fileURL {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      HStack(spacing: 4) {
        Label(providerName(session.provider), systemImage: providerIcon(session.provider))
          .font(.caption)
          .foregroundStyle(.secondary)
          .labelStyle(.titleOnly)

        Text("•")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(relativeTime(session.lastActivity))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var filteredSessions: [TranscriptSession] {
    let sessions = monitor.allSessions
    if searchText.isEmpty {
      return sessions
    }
    return sessions.filter { session in
      session.identifier.localizedCaseInsensitiveContains(searchText)
        || session.fileURL.path.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func providerName(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func providerIcon(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "terminal.fill"
    case .codexCLI: return "chevron.left.forwardslash.chevron.right"
    case .other: return "doc.text"
    }
  }

  private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .blue
    case .other: return .gray
    }
  }

  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func refreshSessions() {
    // Refresh handled by window wrapper via monitor.refresh()
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            Text(providerName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }
        }

        Divider()

        // Metadata
        VStack(alignment: .leading, spacing: 12) {
          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))
          metadataRow(label: "File Path", value: session.fileURL.path)
          metadataRow(label: "File Name", value: session.fileURL.lastPathComponent)
          metadataRow(label: "Provider", value: providerName)

          if let fileSize = fileSize() {
            metadataRow(label: "File Size", value: fileSize)
          }

          if let lineCount = lineCount() {
            metadataRow(label: "Lines", value: "\(lineCount)")
          }
        }

        Divider()

        // Actions
        VStack(spacing: 8) {
          if !isActive {
            Button {
              onSelect()
            } label: {
              Label("Select for Monitoring", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }

          Button {
            NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSWorkspace.shared.open(session.fileURL)
          } label: {
            Label("Open in Default Editor", systemImage: "doc.text")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.fileURL.path, forType: .string)
          } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func metadataRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.subheadline)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var providerName: String {
    switch session.provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func fileSize() -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: session.fileURL.path),
          let size = attrs[.size] as? Int64 else {
      return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func lineCount() -> Int? {
    guard let content = try? String(contentsOf: session.fileURL, encoding: .utf8) else {
      return nil
    }
    return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
  }
}

// MARK: - Previews

#if DEBUG
struct TranscriptInventoryView_Previews: PreviewProvider {
  static var previews: some View {
    TranscriptInventoryView { _ in
      // Session selection handler
    }
    .environment(ConversationMonitor.shared)
  }
}
#endif
```

---

## File: Contextify/Contextify/ConversationMonitor.swift

```swift
import Foundation
import Observation
import OSLog
import ContextifyCore

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
    private let config = MonitorConfig()
    private let conversationResolver = ActiveConversationResolver(providers: [
        ClaudeTranscriptProvider(),
        CodexTranscriptProvider()
    ])
    private let affirmativeLexicon: Set<String> = [
        "yes", "y", "ok", "okay", "sure", "👍", "yep", "yup", "sounds", "good", "go", "ahead",
        "proceed", "do", "it", "please", "sgtm", "roger", "affirmative", "yeah", "yah", "make", "so"
    ]
    private let negativeLexicon: Set<String> = [
        "no", "nope", "nah", "not", "now", "yet", "hold", "off", "stop", "don't", "do", "cancel", "abort"
    ]
    private let actionHintCues: [String] = [
        "would you like me to", "shall i", "i can ", "i will ",
        "proceed", "change it to", "ensure ", "run ", "fix ", "update ", "refactor ", "implement "
    ]

    private(set) var entries: [TimelineEntry] = []
    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var conversationFileDescriptor: CInt = -1
    @ObservationIgnored private var lastProcessedLine: Int = 0
    @ObservationIgnored private var currentLineNumber: Int = 0
    @ObservationIgnored private var seenMessageUUIDs: Set<String> = []
    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private var currentConversationFile: URL?
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
    @ObservationIgnored private var conversationResolverTask: Task<Void, Never>?
    @ObservationIgnored private(set) var allSessions: [TranscriptSession] = []

    private init() {}

    func startMonitoring() {
        guard fileWatcher == nil else { return }
        log.info("Starting conversation timeline monitoring via project conversation files")
        log.info("HUDViewModel projectRootURL: \(String(describing: HUDViewModel.shared.projectRootURL?.path), privacy: .public)")
        isMonitoring = true

        // Find and watch the current project's conversation file
        Task { [weak self] in
            await self?.refreshActiveConversation(force: true)
        }
        startConversationResolverLoop()
    }

    func stopMonitoring() {
        tearDownFileWatcher()
        isMonitoring = false
        currentConversationFile = nil
        activeSession = nil
        conversationResolverTask?.cancel()
        conversationResolverTask = nil
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    func clearEntries() {
        entries.removeAll()
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        didEmitSessionStart = false
        ensureSessionStartEntry()
    }

    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task {
            await processConversationFile()
        }
    }

    /// Public method for user-initiated session switch from transcript inventory
    func switchToSessionFromUser(_ session: TranscriptSession) async {
        await switchToSession(session, reason: .userSelection)
    }

    /// Public refresh method for manual refresh requests
    nonisolated func refresh() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshActiveConversation(force: true)
            }
        }
    }

    // MARK: - File Discovery & Watching

    private func refreshActiveConversation(force: Bool = false) async {
        guard let projectURL = HUDViewModel.shared.projectRootURL else {
            if activeSession != nil {
                log.info("No project root set; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            allSessions = []
            lastError = "No project root set"
            log.error("Timeline: No project root URL available from HUDViewModel")
            return
        }

        log.info("Timeline: Resolving conversations for project: \(projectURL.path, privacy: .public)")

        // Use ProjectContext for worktree-aware session discovery
        guard let context = ProjectContext.current() else {
            log.error("Timeline: Failed to create ProjectContext")
            lastError = "Failed to create project context"
            return
        }

        let sessions = conversationResolver.resolveAllSessions(for: context)
        allSessions = sessions

        log.info("Timeline: Found \(sessions.count) total sessions for project (including worktrees)")

        guard let session = sessions.first else {
            if activeSession != nil {
                log.info("No active conversation sessions found; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            lastError = "No conversation file found for this project"
            log.error("Timeline: No sessions found for project")
            return
        }

        log.info("Timeline: Active session at \(session.fileURL.path, privacy: .public)")

        if !force, let current = activeSession, current.fileURL == session.fileURL {
            activeSession = session
            return
        }

        await switchToSession(session, reason: force ? .initial : .providerChange)
    }

    private enum SessionSwitchReason {
        case initial
        case providerChange
        case userSelection
    }

    private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
        tearDownFileWatcher()

        activeSession = session
        currentConversationFile = session.fileURL
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        lastError = nil

        configureFileWatcher(for: session.fileURL)

        if reason == .initial {
            ensureSessionStartEntry()
        } else if reason == .providerChange {
            emitProviderSwitchEntry(for: session)
        }

        await processConversationFile()
    }

    private func configureFileWatcher(for fileURL: URL) {
        let path = fileURL.path
        conversationFileDescriptor = open(path, O_EVTONLY)
        guard conversationFileDescriptor >= 0 else {
            log.error("Failed to open conversation file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: conversationFileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.processConversationFile()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.conversationFileDescriptor >= 0 {
                close(self.conversationFileDescriptor)
                self.conversationFileDescriptor = -1
            }
        }

        source.resume()
        fileWatcher = source
        log.info("Watching transcript: \(fileURL.lastPathComponent, privacy: .public)")
    }

    private func tearDownFileWatcher() {
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        } else if conversationFileDescriptor >= 0 {
            close(conversationFileDescriptor)
        }

        conversationFileDescriptor = -1
    }

    private func emitProviderSwitchEntry(for session: TranscriptSession) {
        let providerName: String
        switch session.provider {
        case .claudeCode: providerName = "Claude Code"
        case .codexCLI: providerName = "Codex CLI"
        case .other: providerName = "AI Source"
        }

        let summary = "Switched to \(providerName) conversation"
        let detail = """
        Timeline switched to \(providerName) conversation

        Monitoring: \(session.fileURL.lastPathComponent)
        Path: \(session.fileURL.path)
        """
        let context = TimelineSourceContext(
            provider: session.provider,
            identifier: session.identifier,
            filePath: session.fileURL.path
        )

        let entry = TimelineEntry(
            kind: .system,
            timestamp: Date(),
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: context,
            sourceIdentifier: "provider-switch-\(session.identifier)"
        )

        entries.append(entry)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    private func startConversationResolverLoop() {
        conversationResolverTask?.cancel()
        conversationResolverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let interval = self.config.pollInterval
            let delay = UInt64(max(interval, 1) * 1_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                await self.refreshActiveConversation()
            }
        }
    }

    private func makeSourceContext(identifier: String, line: Int? = nil) -> TimelineSourceContext {
        let provider = activeSession?.provider ?? .other
        let filePath = activeSession?.fileURL.path
        return TimelineSourceContext(provider: provider, identifier: identifier, filePath: filePath, line: line)
    }

    // MARK: - Processing

    private func processConversationFile() async {
        guard isMonitoring else {
            log.error("🔴 processConversationFile: not monitoring")
            return
        }
        guard !isProcessing else {
            log.error("🔴 processConversationFile: already processing")
            return
        }
        guard let fileURL = currentConversationFile else {
            log.error("🔴 processConversationFile: no conversation file")
            return
        }

        log.info("🟢 processConversationFile: starting, file=\(fileURL.lastPathComponent, privacy: .public)")

        isProcessing = true
        defer {
            isProcessing = false
            lastUpdate = Date()
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

            log.info("🟢 processConversationFile: read \(lines.count) lines, lastProcessedLine=\(self.lastProcessedLine)")

            // Only process new lines since last check
            guard lines.count > lastProcessedLine else {
                log.info("🟡 processConversationFile: no new lines to process")
                return
            }

            let newLines: ArraySlice<String>
            let shouldBackfillLimitedEntries: Bool
            if lastProcessedLine == 0 {
                // Initial load: Check if timeline is effectively empty (only system messages)
                let hasNonSystemMessages = entries.contains { $0.kind != .system }

                if !hasNonSystemMessages {
                    // Timeline is empty, backfill last 5 displayable entries
                    newLines = lines[...]
                    shouldBackfillLimitedEntries = true
                    log.info("🟢 processConversationFile: Initial load (empty timeline), will backfill last 5 displayable entries from \(lines.count) total lines")
                } else {
                    // Timeline already has content, don't backfill old messages
                    newLines = []
                    shouldBackfillLimitedEntries = false
                    log.info("🟢 processConversationFile: Initial load (existing timeline), skipping backfill")
                }
                lastProcessedLine = lines.count
            } else {
                // Incremental update: process all new lines
                newLines = lines[lastProcessedLine...]
                shouldBackfillLimitedEntries = false
                lastProcessedLine = lines.count
                log.info("🟢 processConversationFile: Incremental update, processing \(newLines.count) new lines")
            }

            var processedCount = 0
            var skippedCount = 0
            let entriesBeforeProcessing = entries.count

            for (index, line) in newLines.reversed().enumerated() {
                // Calculate actual line number in file
                let lineNumber = shouldBackfillLimitedEntries
                    ? lastProcessedLine - newLines.count + index + 1
                    : lastProcessedLine - newLines.count + index + 1

                // If backfilling with limit, stop once we have 5 new displayable entries
                if shouldBackfillLimitedEntries {
                    let newDisplayableEntries = entries.count - entriesBeforeProcessing
                    if newDisplayableEntries >= 20 {
                        log.info("🟢 processConversationFile: Reached displayable entries limit, (newDisplayableEntries) stopping backfill")
                        break
                    }
                }

                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedCount += 1
                    continue
                }

                currentLineNumber = lineNumber
                await processConversationEntry(json)
                processedCount += 1
            }

            // Reverse entries if we were backfilling (since we processed in reverse)
            if shouldBackfillLimitedEntries, entries.count > entriesBeforeProcessing {
                let backfilledEntries = entries[entriesBeforeProcessing...]
                entries.removeLast(backfilledEntries.count)
                entries.append(contentsOf: backfilledEntries.reversed())
            }

            log.info("🟢 processConversationFile: processed \(processedCount) entries, skipped \(skippedCount), total timeline entries now: \(self.entries.count)")

            lastError = nil
        } catch {
            lastError = "Failed to read conversation: \(error.localizedDescription)"
            log.error("🔴 processConversationFile: Failed to process conversation file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processConversationEntry(_ json: [String: Any]) async {
        guard let uuid = json["uuid"] as? String else {
            log.error("🔴 processConversationEntry: no uuid")
            return
        }
        guard !seenMessageUUIDs.contains(uuid) else {
            log.info("🟡 processConversationEntry: already seen uuid=\(uuid, privacy: .public)")
            return
        }
        seenMessageUUIDs.insert(uuid)

        if (json["isSidechain"] as? Bool) == true {
            log.info("🟡 processConversationEntry: skipping sidechain message")
            return
        }

        guard let type = json["type"] as? String else {
            log.error("🔴 processConversationEntry: no type for uuid=\(uuid, privacy: .public)")
            return
        }
        guard let timestampStr = json["timestamp"] as? String else {
            log.error("🔴 processConversationEntry: no timestamp for uuid=\(uuid, privacy: .public)")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = formatter.date(from: timestampStr) else {
            log.error("🔴 processConversationEntry: invalid timestamp '\(timestampStr, privacy: .public)' for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processConversationEntry: type=\(type, privacy: .public), uuid=\(uuid, privacy: .public)")

        switch type {
        case "user":
            await processUserMessage(json, timestamp: timestamp, uuid: uuid)
        case "assistant":
            await processAssistantMessage(json, timestamp: timestamp, uuid: uuid)
        default:
            log.info("🟡 processConversationEntry: skipping unknown type=\(type, privacy: .public)")
            break
        }
    }

    private func processUserMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processUserMessage: uuid=\(uuid, privacy: .public)")

        guard let message = json["message"] as? [String: Any] else {
            log.error("🔴 processUserMessage: no message dict for uuid=\(uuid, privacy: .public)")
            return
        }

        let toolUseStdout = (json["toolUseResult"] as? [String: Any])?["stdout"] as? String
        let fallbackToolText = (toolUseStdout?.isEmpty == false) ? toolUseStdout : nil

        if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockTypes = contentBlocks.compactMap { $0["type"] as? String }
            if !blockTypes.isEmpty, blockTypes.allSatisfy({ $0 == "tool_result" }) {
                log.info("🟡 processUserMessage: skipping assistant tool_result relay for uuid=\(uuid, privacy: .public)")
                return
            }
        }

        let text: String
        if let directContent = message["content"] as? String {
            text = directContent
        } else if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockText = contentBlocks.compactMap { block -> String? in
                guard let blockType = block["type"] as? String else { return nil }

                switch blockType {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                    if let text = block["content"] as? String, !text.isEmpty { return text }
                    return nil
                case "tool_result":
                    if let text = block["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                default:
                    return nil
                }
            }.first

            if let blockText {
                text = blockText
            } else if let stdout = fallbackToolText {
                // Prefer inline block content when available; fall back to tool output if the array omits it.
                text = stdout
            } else {
                let contentType = type(of: message["content"] as Any)
                log.error("🔴 processUserMessage: no usable content in array for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
                return
            }
        } else if let stringArray = message["content"] as? [String],
                  let first = stringArray.first(where: { !$0.isEmpty }) {
            text = first
        } else if let stdout = fallbackToolText {
            // Prefer inline block content when available; fall back to tool output if the array omits it.
            text = stdout
        } else {
            let contentType = type(of: message["content"] as Any)
            log.error("🔴 processUserMessage: content not a string for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
            return
        }

        let isMeta = json["isMeta"] as? Bool ?? false
        log.info("🟢 processUserMessage: text length=\(text.count), isMeta=\(isMeta)")

        // Skip meta messages and command wrappers
        guard !text.isEmpty,
              !(json["isMeta"] as? Bool ?? false),
              !text.contains("<command-name>"),
              !text.contains("<local-command-stdout>") else {
            log.info("🟡 processUserMessage: skipping (empty/meta/command) for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processUserMessage: creating timeline entry for uuid=\(uuid, privacy: .public)")

        let actionHint = shouldUseActionHint(for: text) ? latestAssistantActionHint() : nil
        let summaryResult: FoundationLLM.TimelineSummaryResult
        do {
            summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .user, text: text, actionHint: actionHint)
        } catch {
            log.error("🔴 processUserMessage: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
            return
        }
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .user,
            timestamp: timestamp,
            summary: summaryResult.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: "msg-\(uuid)",
            isCompletion: false
        )

        entries.append(entry)

        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }

        log.info("✅ processUserMessage: Added user entry, summary=\(summaryResult.summary, privacy: .private), total entries=\(self.entries.count)")
    }

    private func processAssistantMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processAssistantMessage: uuid=\(uuid, privacy: .public)")

        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            log.error("🔴 processAssistantMessage: no message or content array for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processAssistantMessage: content blocks count=\(content.count)")

        // Process each content block (skip tool invokes, only surface text)
        for (index, block) in content.enumerated() {
            guard let blockType = block["type"] as? String else {
                log.error("🔴 processAssistantMessage: no type in block \(index) for uuid=\(uuid, privacy: .public)")
                continue
            }

            log.info("🟢 processAssistantMessage: block \(index) type=\(blockType, privacy: .public)")

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    await addAssistantTextEntry(text: text, timestamp: timestamp, uuid: uuid)
                } else {
                    log.error("🔴 processAssistantMessage: text block has no text field")
                }
            case "tool_use":
                log.info("🟡 processAssistantMessage: skipping tool_use block for uuid=\(uuid, privacy: .public)")
            default:
                log.info("🟡 processAssistantMessage: skipping unknown block type=\(blockType, privacy: .public)")
                break
            }
        }
    }

    private func addAssistantTextEntry(text: String, timestamp: Date, uuid: String) async {
        log.info("🟢 addAssistantTextEntry: text length=\(text.count), uuid=\(uuid, privacy: .public)")

        let summaryResult: FoundationLLM.TimelineSummaryResult
        do {
            summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .assistant, text: text)
        } catch {
            log.error("🔴 addAssistantTextEntry: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
            return
        }
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .assistant,
            timestamp: timestamp,
            summary: summaryResult.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: "msg-\(uuid)-text",
            isCompletion: summaryResult.isCompletion
        )

        entries.append(entry)
        log.info("✅ addAssistantTextEntry: Added assistant text entry, summary=\(summaryResult.summary, privacy: .private), completion=\(summaryResult.isCompletion), uuid=\(uuid, privacy: .public), total entries=\(self.entries.count)")
    }

    private func latestAssistantActionHint() -> String? {
        guard let lastAssistant = entries.reversed().first(where: { $0.kind == .assistant }) else {
            return nil
        }
        let raw = lastAssistant.sourceContent?.isEmpty == false
            ? lastAssistant.sourceContent
            : lastAssistant.detail
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return distilledActionHint(from: raw)
    }

    private func distilledActionHint(from text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let candidate = lines.first { line in
            let lower = line.lowercased()
            return actionHintCues.contains { lower.contains($0) }
        } ?? lines.first

        guard var hint = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty else {
            return nil
        }

        hint = hint.replacingOccurrences(
            of: "^(yes|no|ok|okay|sure|please)[\\s,:-]*",
            with: "",
            options: .regularExpression
        )
        hint = hint.replacingOccurrences(
            of: "[?.!…]+$",
            with: "",
            options: .regularExpression
        )

        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    private func shouldUseActionHint(for text: String) -> Bool {
        let normalized = normalizeForActionHint(text)
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ")
        guard tokens.count <= 3 else { return false }
        let allAffirmative = tokens.allSatisfy { affirmativeLexicon.contains(String($0)) }
        let allNegative = tokens.allSatisfy { negativeLexicon.contains(String($0)) }
        return allAffirmative || allNegative
    }

    private func normalizeForActionHint(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "…“”\"'"))
        normalized = normalized.trimmingCharacters(in: punctuation)
        normalized = normalized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return normalized.lowercased()
    }

    private func ensureSessionStartEntry() {
        guard !didEmitSessionStart else { return }
        didEmitSessionStart = true
        let summary = "Timeline monitoring started"
        let detail: String
        if let fileURL = currentConversationFile {
            detail = """
            Timeline monitoring started

            Monitoring: \(fileURL.lastPathComponent)
            Path: \(fileURL.path)
            """
        } else {
            detail = "Timeline monitoring started (no conversation file found yet)"
        }
        let entry = TimelineEntry(
            kind: .system,
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: makeSourceContext(identifier: "system-start"),
            sourceIdentifier: "system-start"
        )
        entries.append(entry)
    }
}

#if DEBUG
extension ConversationMonitor {
    func _testShouldUseActionHint(_ text: String) -> Bool {
        shouldUseActionHint(for: text)
    }

    func _testDistilledActionHint(from text: String) -> String? {
        distilledActionHint(from: text)
    }
}
#endif
```

---

## APPENDIX B: Sample Transcript Excerpts

### Claude Code Transcript Structure
File: `~/.claude/projects/-Users-rob-code-contextify/16093e60-2cf4-4501-b841-ee7a6d072e88.jsonl`
Total Lines: 395

Sample entries (first 5 lines):
```jsonl
{"type":"file-history-snapshot","messageId":"7c1639c1-52cf-4952-8f12-fbb474841e75","snapshot":{"messageId":"7c1639c1-52cf-4952-8f12-fbb474841e75","trackedFileBackups":{},"timestamp":"2025-10-03T05:47:29.418Z"},"isSnapshotUpdate":false}
{"type":"file-history-snapshot","messageId":"ab8a2b4c-8d24-444b-8957-542c17e05a1e","snapshot":{"messageId":"ab8a2b4c-8d24-444b-8957-542c17e05a1e","trackedFileBackups":{"CLAUDE.md":{"backupFileName":null,"version":1,"backupTime":"2025-10-03T05:48:47.538Z"}},"timestamp":"2025-10-03T05:47:38.054Z"},"isSnapshotUpdate":false}
{"type":"file-history-snapshot","messageId":"072eee4e-5514-46fe-a091-02f3aa0215d3","snapshot":{"messageId":"072eee4e-5514-46fe-a091-02f3aa0215d3","trackedFileBackups":{"CLAUDE.md":{"backupFileName":"177ca68b554a7a56@v2","version":2,"backupTime":"2025-10-03T05:49:45.805Z"}},"timestamp":"2025-10-03T05:49:45.793Z"},"isSnapshotUpdate":false}
{"type":"file-history-snapshot","messageId":"c1f65451-2d02-4da5-b06e-d531502e54a2","snapshot":{"messageId":"c1f65451-2d02-4da5-b06e-d531502e54a2","trackedFileBackups":{"CLAUDE.md":{"backupFileName":"177ca68b554a7a56@v2","version":2,"backupTime":"2025-10-03T05:49:45.805Z"}},"timestamp":"2025-10-03T05:50:17.246Z"},"isSnapshotUpdate":false}
{"type":"file-history-snapshot","messageId":"1234b244-d234-41d8-95bc-75b0971fef4e","snapshot":{"messageId":"1234b244-d234-41d8-95bc-75b0971fef4e","trackedFileBackups":{"CLAUDE.md":{"backupFileName":"177ca68b554a7a56@v2","version":2,"backupTime":"2025-10-03T05:49:45.805Z"}},"timestamp":"2025-10-03T05:52:44.546Z"},"isSnapshotUpdate":false}
```

### Codex CLI Transcript Structure
File: `~/.codex/sessions/2025/10/03/rollout-2025-10-03T15-05-03-0199ac1b-7000-7591-b8c5-cac459196d35.jsonl`

Sample entries (first 3 lines, heavily truncated for brevity):
```jsonl
{"timestamp":"2025-10-03T22:05:03.374Z","type":"session_meta","payload":{"id":"0199ac1b-7000-7591-b8c5-cac459196d35","cwd":"/Users/rob/code/contextify","originator":"codex_cli_rs","cli_version":"0.40.0","git":{"commit_hash":"0e3659e...","branch":"feature/inline-compose","repository_url":"git@github.com:banagale/contextify.git"}}}
{"timestamp":"2025-10-03T22:05:03.374Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<user_instructions>\n# Repository Guidelines\n...(truncated)...\n</user_instructions>"}]}}
{"timestamp":"2025-10-03T22:05:03.374Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>...(truncated)...</environment_context>"}]}}
```

**Key Observations:**
1. Claude Code transcripts mix system events (file-history-snapshot) with user/assistant messages
2. Codex CLI transcripts include rich session_meta with git context
3. Content can be nested arrays or simple strings
4. Timestamps enable chronological reconstruction
5. Very long conversations (395+ lines) require intelligent chunking

---

## APPENDIX C: Recommended Reading

**LLM Summarization Research**:
- Google Cloud: "Summarization techniques with Gemini models" (map-reduce, iterative refinement)
- LangChain Docs: "Summarize Text" tutorial (practical patterns)
- ArXiv: "TopicTag: Automatic Annotation of NMF Topic Models" (topic modeling with LLMs)

**Conversational AI**:
- IBM: "What is chain of thought prompting?"
- Medium: "The Impact of Summarization by LLMs on Conversational Data"
- ArXiv: "Tell me what I need to know: Personalized Multi-Source Meeting Summarization"

**Implementation Guides**:
- Neo4j: "Multi-Hop Reasoning With Knowledge Graphs and LLMs"
- Arize AI: "LLM Summarization: Getting To Production" (metrics, evaluation)
- PickPros: "Summarizing Long Texts with LLMs: Advanced Techniques"

---

**END OF TECHNICAL BRIEF**

Generated: 2025-10-09
Total Length: ~12,000 words
Appendices: 4 complete Swift files + transcript samples
Next Steps: Review system prompt, choose solution (1, 2, or 3), begin Phase 1 implementation

