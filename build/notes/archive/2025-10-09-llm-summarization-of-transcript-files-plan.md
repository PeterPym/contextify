Here’s my take: your colleague’s advice to **ship a single-pass MVP** is solid. I’m adopting their best upgrades (adaptive sampling, stronger grounding, atomic sidecar storage, fallbacks, and simple strategy rules) and I’m **pushing back** only on two items:

* **Pushback 1: “Cut multi-pass entirely.”** I agree we shouldn’t build it now, but I’m keeping **a clean extension seam** (interfaces, types, and metrics) so we can add multi-pass later without refactoring. This costs almost nothing today and prevents architectural debt.
* **Pushback 2: “Always show ETA.”** I’ll display a **coarse** estimate (“~3s”), but only when we’re doing a single LLM call; we won’t imply precision.

Everything else from the review is accepted and integrated below.

---

# Final Implementation Plan (ship-ready)

## Goals

* Generate high-quality **title (≤60 chars)** and **description (≤200 chars)** for conversation transcripts.
* Handle **50–10,000+ lines**.
* Favor **speed + reliability**: **single LLM call** with **adaptive sampling**; robust fallbacks.
* Integrate with **Swift 6**, **SwiftUI**, and **FoundationModels (macOS 26)**.
* Store results in **sidecar JSON**, with **hash-based invalidation** and **one-click regeneration**.

---

# Architecture

```
TranscriptParser  ─┐
                   ├─> ContextBuilder (AdaptiveSampler) ──> LLMClient (FoundationModels)
Sanitizers/Grounding┘                                         │
                                                              v
                              TranscriptMetadataStore (Sidecar JSON, atomic)
                                                              │
                                                              v
                                    Orchestrator (actor, retries, metrics)
                                                              │
                                                              v
                                   SwiftUI (Inventory + Detail + Regenerate)
```

* **Single-pass pipeline** only for MVP.
* **Extension seam**: Orchestrator keeps a strategy enum and metrics so a multi-pass/topic pipeline can be added later without changing callers.

---

# Detailed Design

## 1) Parsing & Exchange Model

* **Stream-read JSONL**; accept Claude Code & Codex CLI shapes.
* Build `Exchange` in chronological order. One “exchange” is `(user, assistant?)` when adjacent, otherwise a single message with its role.

```swift
struct Exchange: Sendable {
    enum Role { case user, assistant }
    let role: Role
    let text: String
    let timestamp: Date
}
```

Parsing rules:

* Include only `user` and `assistant` content; ignore `file-history-snapshot`, `session_meta`, `tool_use` blocks unless they contain **clear human-readable text**.
* Collapse whitespace; strip control characters; clamp each block to **2,000 chars** to avoid pathological messages.
* Count corrupted lines; if >10% of parsed lines fail, abort parsing with a descriptive error (UI will show Retry).

## 2) Context Building (Adaptive Sampling)

**Why:** Bookends alone miss the middle; full-context doesn’t scale. Adaptive sampling guarantees head/tail continuity and keeps the best middle messages.

Parameters (shippable defaults):

* Always include **first 10** and **last 10** exchanges.
* Window importance scoring over the middle:

  * +2.0 for cue phrases indicating shifts (`"now let's"`, `"next"`, `"switching to"`, `"new bug"`, `"docs"`, `"tests"`, `"refactor"`).
  * +1.5 for completion tokens (`"✅"`, `"done"`, `"fixed"`, `"merged"`, `"completed"`).
  * +0.5 per `'?'` in user messages (cap at +1.0).
  * +min(length / 200, 1.0) to favor substantive messages.
* Target input budget: **~3,500 tokens** (rough estimate). Leave room for instructions and schema, so set **context budget ≈ 3,000 tokens**.
* Token estimate: `approxTokens = Int(Double(wordCount) * 1.3)`.

Algorithm:

1. Take `head = first 10`, `tail = last 10`.
2. Rank middle exchanges by `importanceScore`.
3. Greedily add from highest score until budget reached.
4. **Reorder** sampled middle chronologically and build the final context: `head + sampled + tail`.
5. If `exchangeCount ≤ 60`, skip sampling and use **full** exchanges (still truncated per-message to 2,000 chars).

**Formatting for LLM (compact, grounded):**

```
U [2025-10-03 05:48]: Fix the bug in FoundationLLM summarizeTimeline.
A [2025-10-03 05:49]: I’ll check grounding and confidence thresholds…
U [2025-10-03 06:01]: Now switch to docs for Timeline rules.
A [2025-10-03 06:03]: Added README notes on allowed prefixes…
```

* Single-line per message; preserve author (`U`/`A`) and timestamp; collapse code blocks to an indicative one-liner (e.g., “code block omitted (WebSocketManager.swift)”) **only if** the filename is explicitly present.

## 3) LLM Call (FoundationModels)

We keep the call **single-pass** and **schema-guided**.

### Prompt (final text)

```swift
let prompt = """
You are analyzing a developer’s AI-assisted coding session.

OUTPUT RULES
- Only include specific details that appear in the messages below.
- Do NOT invent filenames, APIs, bugs, or tools.
- Title: ≤60 chars, imperative or concise noun phrase. Focus on the MOST discussed activity.
- Description: ≤200 chars. 2–3 key activities in chronological order. Past tense. Prefer concrete nouns (modules, features) that appear in the text.
- Topics: 2–5 items chosen only from:
  feature-work, bug-fix, refactoring, testing, documentation,
  code-review, performance, security, architecture, deployment, general.

CONFIDENCE
- Set confidence 0.0–1.0 based on clarity/specificity of the sampled messages.
- Set mayContainHallucinations=true if any filenames or entities you used are not present in the messages verbatim.

CONTEXT
This excerpt shows \(sampledCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle was selected for importance (topic shifts, completions, questions).

MESSAGES
<BEGIN>
\(formattedContext)
<END>
"""
```

### Guided schema

```swift
@available(macOS 26, *)
@Generable(description: "Transcript metadata")
struct GuidedTranscriptMetadata {
    @Guide(description: "Title ≤60 chars; imperative or concise noun phrase.")
    var title: String

    @Guide(description: "Description ≤200 chars; 2–3 activities in chronological order; past tense.")
    var description: String

    @Guide(description: "2–5 topics from the fixed list; lowercase hyphenated.")
    var topics: [String]

    @Guide(description: "Confidence 0.0–1.0")
    var confidence: Double

    @Guide(description: "True if any referenced filename/module/API not in messages.")
    var mayContainHallucinations: Bool
}
```

### Options

* `sampling: .greedy`, `temperature: 0`, `maximumResponseTokens: 220`.

### Fallbacks

* If schema decoding fails once, retry same input with `temperature: 0.1`.
* If still failing, request **plain JSON** (no schema) and decode defensively.
* Final fallback (no LLM): heuristic title `"Brief Session"` or `"Developer Chat"`, description from first/last user lines, topics `["general"]`. Flag `needsReview=true`.

## 4) Grounding & Post-processing

After decoding:

* **Clamp lengths** safely at grapheme boundaries (60/200).
* **Topic allow-list** only; if out-of-vocabulary, map `"development"` to `"general"`; drop unknowns.
* **Filename grounding check:** extract candidate filenames from description via regex `([A-Za-z0-9_./-]+\\.(swift|md|ts|js|kt|py|rb))`; if any not found in the sampled context, remove them and set `mayContainHallucinations=true`.
* If `confidence < 0.6` **or** `mayContainHallucinations == true`, set `needsReview=true` (stored in sidecar).

Utilities:

```swift
struct PostProcess {
    static func clamp(_ s: String, limit: Int) -> String { /* word-boundary clamp, add … if truncated */ }
    static func normalizeTopics(_ t: [String]) -> [String] { /* lowercased, deduped, allow-list filtered */ }
    static func stripUnseenFilenames(in text: String, from context: String) -> (String, Bool) { /* returns text, flagged */ }
}
```

## 5) Strategy & Orchestration

**Strategy (simple & predictable):**

* `exchangeCount ≤ 60` → **Full context** (single-pass).
* `exchangeCount 61…∞` → **Adaptive sampling** (single-pass).
* If adaptive call fails → fallback to **Bookends(20,20)** once.
* Concurrency cap: **2 concurrent LLM calls** app-wide.

**Orchestrator actor** (single public entry):

```swift
actor MetadataOrchestrator {
    func ensureMetadata(for session: TranscriptSession) async throws -> TranscriptMetadata
}
```

Responsibilities:

* Load cached sidecar, compute transcript SHA256, decide freshness.
* Choose strategy, build context, call LLM, post-process.
* Save sidecar atomically.
* Emit `GenerationMetrics` (parse/sampling/llm/storage times).

Circuit breaker:

* After **5 consecutive failures** within **5 minutes**, temporarily switch to **heuristic** generation until the window passes.

## 6) Storage & Cache Invalidation

**Sidecar JSON** next to each transcript:

`<file>.jsonl`
`<file>.metadata.json`

Schema:

```json
{
  "version": 1,
  "title": "Fix grounding in timeline summaries",
  "description": "Tightened grounding checks, removed topic leakage, added completion icon logic.",
  "topics": ["bug-fix","testing","refactoring"],
  "confidence": 0.83,
  "mayContainHallucinations": false,
  "needsReview": false,
  "generatedAt": "2025-10-09T20:15:00Z",
  "model": "SystemLanguageModel@local",
  "promptVersion": 2,
  "generatorVersion": 1,
  "transcriptSHA256": "sha256:eb3f…",
  "messageCount": 392,
  "strategy": "singlePass:adaptive",
  "llmCalls": 1,
  "latencyMs": 3100
}
```

**Freshness check** triggers regeneration if:

* `transcriptSHA256` changes, **or**
* `promptVersion` or `generatorVersion` changes, **or**
* Feature gate toggles (store as integers in the sidecar if needed), **or**
* Sidecar missing/invalid.

**Atomic write**:

* Encode to `*.tmp`, then `FileManager.replaceItemAt(_:withItemAt:options:.usingNewMetadataOnly)`.

SQLite: not implemented in MVP; we’ll reconsider when **>500 transcripts** exist or list loading becomes slow.

## 7) SwiftUI Integration

### Inventory list row

* If metadata exists: show **title** and **description** (2 lines).
* If missing or stale: show spinner with `"Analyzing… (~\(etaSeconds) s)"`.
* Show up to **2 topic chips** on the right of the timestamp.

### Detail view

* Present full metadata (title, description, topics).
* Show `generatedAt`, `promptVersion`, `confidence`, and `needsReview` badge if true.
* “**Regenerate Metadata**” button → calls `orchestrator.ensureMetadata` bypassing cache.
* If promptVersion in sidecar < `CurrentPromptVersion`, show “Stale metadata” banner with **Regenerate**.

ETA: `etaSeconds = 3` for single-pass; `etaSeconds = 2` if `exchangeCount ≤ 60`. Display only during active generation.

## 8) Error Handling & Edge Cases

* **Very short transcripts (<5 exchanges):** skip LLM; title `"Brief Session"`, description `"Short conversation under five exchanges."`, topics `["general"]`, `confidence=0.3`, `needsReview=true`.
* **Corrupted JSON:** skip line, count; if >10% corrupted, present error in UI and allow Retry. If user continues, we can still run on the parsed subset.
* **Huge transcripts (>10k lines):** streaming parse + adaptive sampling guarantees bounded context. Memory use limited to the Exchange array (strings clamped).
* **Non-English:** do nothing special; LLM returns same language.
* **Prompt injection:** sanitize known injection phrases (`"ignore previous instructions"`, `"system:"` → `"system_"`), cap any single message to 2,000 chars; strip trailing “Output:” directives in messages.
* **LLM unavailable:** circuit breaker flips to heuristic generation; UI shows “Generated heuristically” badge.

## 9) Metrics & Telemetry (local only)

`GenerationMetrics { parse, sampling, llm, storage, total, exchangeCount, strategy, success, needsReview }`

* Log to `OSLog` with subsystem `dev.contextify.metadata`.
* Aggregate simple rolling averages in memory; **no PII** persisted.

## 10) Concrete Swift Pieces

### 10.1 Orchestrator (core)

```swift
@MainActor
enum GenerationStrategy: String { case full, adaptive, bookends }

actor MetadataOrchestrator {
    static let shared = MetadataOrchestrator()
    private let store = SidecarMetadataStore.shared
    private let parser = TranscriptParser()
    private let builder = ContextBuilder()
    private let llm = LLMClient.shared
    private let semaphore = AsyncSemaphore(value: 2)
    private let currentPromptVersion = 2
    private let currentGeneratorVersion = 1
    private let breaker = FoundationLLMCircuitBreaker()

    func ensureMetadata(for session: TranscriptSession) async throws -> TranscriptMetadata {
        if let cached = try? store.load(for: session.fileURL),
           store.isFresh(cached, for: session.fileURL,
                         promptVersion: currentPromptVersion,
                         generatorVersion: currentGeneratorVersion) {
            return cached
        }

        let t0 = ContinuousClock.now
        let exchanges = try parser.parseExchanges(url: session.fileURL)
        let strategy: GenerationStrategy = exchanges.count <= 60 ? .full : .adaptive

        if !breaker.shouldAllowRequest() {
            let heuristic = Heuristics.fallbackMetadata(exchanges: exchanges)
            try await store.save(heuristic, for: session.fileURL)
            return heuristic
        }

        let context = try builder.build(exchanges: exchanges, strategy: strategy)
        let result: GuidedTranscriptMetadata
        do {
            try await semaphore.wait()
            defer { semaphore.signal() }
            result = try await llm.singlePass(context: context.text,
                                              sampledCount: context.sampledCount,
                                              totalCount: exchanges.count)
        } catch {
            breaker.recordFailure()
            if strategy != .bookends {
                // single fallback attempt
                let book = try builder.build(exchanges: exchanges, strategy: .bookends)
                try await semaphore.wait()
                defer { semaphore.signal() }
                result = try await llm.singlePass(context: book.text,
                                                  sampledCount: book.sampledCount,
                                                  totalCount: exchanges.count)
            } else {
                throw error
            }
        }

        let grounded = PostProcess.apply(to: result, context: context.text)
        var meta = SidecarFactory.from(guided: grounded,
                                       exchanges: exchanges,
                                       strategy: strategy,
                                       model: llm.modelSignature,
                                       promptVersion: currentPromptVersion,
                                       generatorVersion: currentGeneratorVersion)
        meta.transcriptSHA256 = try store.sha256(url: session.fileURL)
        let elapsed = Duration.now - t0
        meta.latencyMs = Int(elapsed.components.seconds * 1000)
        try await store.save(meta, for: session.fileURL)
        return meta
    }
}
```

### 10.2 Context Builder

```swift
struct BuiltContext { let text: String; let sampledCount: Int }

struct ContextBuilder {
    func build(exchanges: [Exchange], strategy: GenerationStrategy) throws -> BuiltContext {
        switch strategy {
        case .full:
            let formatted = exchanges.map(Self.format).joined(separator: "\n")
            return .init(text: header(sampled: exchanges.count, total: exchanges.count) + formatted,
                         sampledCount: exchanges.count)
        case .bookends:
            let head = Array(exchanges.prefix(20))
            let tail = Array(exchanges.suffix(20))
            let seq = (head + tail).sorted { $0.timestamp < $1.timestamp }
            let formatted = seq.map(Self.format).joined(separator: "\n")
            return .init(text: header(sampled: seq.count, total: exchanges.count) + formatted,
                         sampledCount: seq.count)
        case .adaptive:
            let seq = AdaptiveSampler.sample(exchanges: exchanges, budgetTokens: 3000)
            let formatted = seq.map(Self.format).joined(separator: "\n")
            return .init(text: header(sampled: seq.count, total: exchanges.count) + formatted,
                         sampledCount: seq.count)
        }
    }

    private func header(sampled: Int, total: Int) -> String {
        "SAMPLED \(sampled) OF \(total)\n"
    }

    private static func format(_ e: Exchange) -> String {
        let role = (e.role == .user) ? "U" : "A"
        let stamp = ISO8601DateFormatter().string(from: e.timestamp)
        let oneLine = Sanitizers.collapse(e.text, hardLimit: 2000)
        return "\(role) [\(stamp)]: \(oneLine)"
    }
}

enum AdaptiveSampler {
    static func sample(exchanges: [Exchange], budgetTokens: Int) -> [Exchange] {
        guard exchanges.count > 20 else { return exchanges }
        let head = Array(exchanges.prefix(10))
        let tail = Array(exchanges.suffix(10))
        let middle = Array(exchanges.dropFirst(10).dropLast(10))

        struct Scored { let ex: Exchange; let score: Double }
        let ranked: [Scored] = middle.map { .init(ex: $0, score: importance(of: $0)) }
            .sorted { $0.score > $1.score }

        var chosen: [Exchange] = []
        var usedTokens = estimateTokens(for: head + tail)

        for item in ranked {
            let t = estimateTokens(for: [item.ex])
            if usedTokens + t > budgetTokens { continue }
            chosen.append(item.ex)
            usedTokens += t
            if usedTokens >= budgetTokens { break }
        }

        let seq = (head + chosen.sorted { $0.timestamp < $1.timestamp } + tail)
        return seq
    }

    private static func importance(of e: Exchange) -> Double {
        var s = 0.0
        let text = e.text.lowercased()
        if text.contains("now let's") || text.contains("next") || text.contains("switching to")
           || text.contains("new bug") || text.contains("docs") || text.contains("tests")
           || text.contains("refactor") { s += 2.0 }
        if text.contains("✅") || text.contains("done") || text.contains("fixed")
           || text.contains("merged") || text.contains("completed") { s += 1.5 }
        if e.role == .user {
            let q = text.filter { $0 == "?" }.count
            s += min(Double(q) * 0.5, 1.0)
        }
        s += min(Double(text.split(whereSeparator: \.isWhitespace).count) / 200.0, 1.0)
        return s
    }

    private static func estimateTokens(for seq: [Exchange]) -> Int {
        seq.reduce(0) { acc, e in acc + Int(Double(e.text.split(whereSeparator: \.isWhitespace).count) * 1.3) + 8 }
    }
}
```

### 10.3 LLM Client

```swift
@available(macOS 26, *)
actor LLMClient {
    static let shared = LLMClient()
    let modelSignature = "SystemLanguageModel@local"

    func singlePass(context: String, sampledCount: Int, totalCount: Int) async throws -> GuidedTranscriptMetadata {
        let session = LanguageModelSession(instructions: Prompts.singlePass(sampledCount: sampledCount, totalCount: totalCount))
        let options = GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 220)
        return try await session.respond(to: context,
                                         generating: GuidedTranscriptMetadata.self,
                                         includeSchemaInPrompt: true,
                                         options: options).content
    }
}

enum Prompts {
    static func singlePass(sampledCount: Int, totalCount: Int) -> String {
"""
You are analyzing a developer’s AI-assisted coding session.

OUTPUT RULES
- Only include details explicitly present in the messages.
- Do NOT invent filenames, APIs, bugs, or tools.
- Title: ≤60 chars; imperative or concise noun phrase; focus on the most discussed activity.
- Description: ≤200 chars; 2–3 key activities in chronological order; past tense; prefer concrete nouns from the text.
- Topics: 2–5 from {feature-work, bug-fix, refactoring, testing, documentation, code-review, performance, security, architecture, deployment, general}.
- Confidence: 0.0–1.0 based on clarity/specificity.
- mayContainHallucinations: true if any referenced filename/module/API is not present verbatim in the messages.

CONTEXT
This excerpt shows \(sampledCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle is selected for importance.

Return ONLY the JSON object for the schema.
"""
    }
}
```

### 10.4 Sidecar Store

```swift
final class SidecarMetadataStore {
    static let shared = SidecarMetadataStore()
    private init() {}

    func sidecarURL(for transcriptURL: URL) -> URL {
        transcriptURL.deletingPathExtension().appendingPathExtension("metadata.json")
    }

    func load(for url: URL) throws -> TranscriptMetadata? {
        let m = sidecarURL(for: url)
        guard FileManager.default.fileExists(atPath: m.path) else { return nil }
        let data = try Data(contentsOf: m)
        return try JSONDecoder().decode(TranscriptMetadata.self, from: data)
    }

    func save(_ meta: TranscriptMetadata, for url: URL) async throws {
        let m = sidecarURL(for: url)
        let tmp = m.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        let data = try JSONEncoder().encode(meta)
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.replaceItemAt(m, withItemAt: tmp, backupItemName: nil, options: .usingNewMetadataOnly)
    }

    func isFresh(_ meta: TranscriptMetadata, for url: URL, promptVersion: Int, generatorVersion: Int) -> Bool {
        guard let currentHash = try? sha256(url: url) else { return false }
        return meta.transcriptSHA256 == currentHash
            && meta.promptVersion == promptVersion
            && meta.generatorVersion == generatorVersion
    }

    func sha256(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        #if canImport(CryptoKit)
        import CryptoKit
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        // Minimal inline hasher (acceptable for MVP if CryptoKit unavailable)
        var h: UInt64 = 1469598103934665603
        for b in data { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "sha256:\(String(h, radix:16))"
        #endif
    }
}
```

### 10.5 SwiftUI hooks

* **List row**: replace filename with `metadata.title ?? identifier`. Second line: `metadata.description` (2 lines, secondary). Right-aligned small chips for up to 2 topics. While generating: `ProgressView()` + “Analyzing… (~3s)”.
* **Detail view**: add a **Regenerate** button that calls `await orchestrator.ensureMetadata(for:)`, updates local model, and reloads.

### 10.6 Data Models

```swift
struct TranscriptMetadata: Codable, Sendable {
    var version: Int = 1
    var title: String
    var description: String
    var topics: [String]
    var confidence: Double
    var mayContainHallucinations: Bool
    var needsReview: Bool
    var generatedAt: Date
    var model: String
    var promptVersion: Int
    var generatorVersion: Int
    var transcriptSHA256: String
    var messageCount: Int
    var strategy: String
    var llmCalls: Int
    var latencyMs: Int
}
```

---

# Rollout Plan

## Week 1 (Foundation)

* Parser (streamed), Exchange model, corruption tolerance.
* ContextBuilder with adaptive sampler and token estimator.
* Sidecar store (atomic), hash, freshness checks.
* Orchestrator actor + simple strategy + retries + circuit breaker.

## Week 2 (LLM + UI)

* Guided schema + prompt exactly as above.
* Post-processing + grounding checks + heuristics fallback.
* SwiftUI list and detail changes; regenerate button; “Analyzing…” state.
* Metrics logging via `OSLog`.

**Definition of Done**

* ≥95% transcripts produce valid JSON on first attempt.
* Title ≤60, description ≤200 enforced post-decode.
* Median latency ≤3.5s for ≤150 exchanges; ≤5s for >150 exchanges (single pass).
* No UI jank with 1k+ transcripts present (metadata loaded lazily).

---

# Future (only if needed)

* **SQLite** when >500 transcripts or list search needs indexing.
* **Multi-pass Topic View** behind a feature flag (reduce risk).
* **User edits** with “lock metadata” to avoid overwrite.
* **Background batch**: opt-in when plugged in and >50 missing sidecars.

---

# Why this is the right cut

* Matches the reviewer’s “start simple, measure, iterate” while preserving an extension seam.
* Strong grounding + post-checks directly attack hallucinations.
* Atomic sidecars + hash invalidation keep storage simple and reliable.
* Adaptive sampling raises quality without the latency bomb of multi-pass.

If you want, I can supply a small PR that adds `MetadataOrchestrator`, `ContextBuilder`, `SidecarMetadataStore`, and patches your `TranscriptInventoryView` to surface titles, descriptions, topics, and the regenerate control.
