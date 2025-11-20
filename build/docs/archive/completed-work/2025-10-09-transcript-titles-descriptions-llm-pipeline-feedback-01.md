# Reviewer 1:
* **LLM path is never executed → all metadata falls back to heuristics**

  * **Root cause:** `@available(macOS 26, *)` on `TranscriptMetadataLLM.singlePass` and guided types + `#if canImport(FoundationModels)` gating cause `.unexpectedEnvironment` and the orchestrator to use `HeuristicMetadata` (“Developer Chat”, “Started with…/Ended with…”).
  * **Fix:** Target current OS availability and provide a provider abstraction with a runtime check; do not throw for lack of local model—fallback to remote provider before heuristics.

  ```swift
  // 1) Provider protocol
  protocol TranscriptMetadataProvider: Sendable {
    func generate(context: String, sampledCount: Int, totalCount: Int) async throws -> Generated
  }
  struct Generated: Sendable { let title: String; let description: String; let topics: [String]; let confidence: Double; let hallucinations: Bool }

  // 2) Local provider (macOS 15+)
  #if canImport(FoundationModels)
  @available(macOS 15, *)
  struct LocalFoundationProvider: TranscriptMetadataProvider {
    func generate(context: String, sampledCount: Int, totalCount: Int) async throws -> Generated {
      let session = LanguageModelSession(instructions: Prompts.singlePass(sampledCount: sampledCount, totalCount: totalCount))
      let opts = GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 220)
      let resp = try await session.respond(to: context, generating: GuidedTranscriptMetadata.self, includeSchemaInPrompt: true, options: opts)
      let g = resp.content
      return Generated(title: g.title, description: g.description, topics: g.topics, confidence: g.confidence, hallucinations: g.mayContainHallucinations)
    }
  }
  #endif

  // 3) Remote provider (fallback)
  struct RemoteHTTPProvider: TranscriptMetadataProvider {
    func generate(context: String, sampledCount: Int, totalCount: Int) async throws -> Generated {
      // Call your existing LLM service (redacted); map response to Generated
    }
  }

  // 4) Orchestrator composition
  actor TranscriptMetadataOrchestrator {
    private let providers: [TranscriptMetadataProvider] = {
      var p: [TranscriptMetadataProvider] = []
      #if canImport(FoundationModels)
      if #available(macOS 15, *) { p.append(LocalFoundationProvider()) }
      #endif
      p.append(RemoteHTTPProvider())
      return p
    }()

    private func callLLM(context: BuiltContext, exchanges: Int) async throws -> TranscriptMetadata {
      for provider in providers {
        do {
          let g = try await provider.generate(context: context.text, sampledCount: context.sampledCount, totalCount: exchanges)
          return postProcess(generated: g, context: context.text, exchanges: exchanges, strategy: "singlePass:\(strategy.rawValue)")
        } catch { continue }
      }
      throw OrchestratorError.noProviderAvailable
    }
  }
  ```

* **Codex transcripts are not parsed → zero exchanges → “Brief Session / Empty transcript”**

  * **Root cause:** `TranscriptParser` only handles `type == "user"` and `type == "assistant"`. Codex uses `type: "response_item"` with `payload.type == "message"` and a `payload.content` array (`input_text`/`output_text`/`markdown`).
  * **Fix:** Parse `response_item` and extract message role + text segments; ignore `event_msg`, `reasoning`, `function_call[_output]`.

  ```swift
  // in parseExchanges(url:)
  switch type {
    case "user": /* existing */ 
    case "assistant": /* existing */
    case "response_item":
      if let exchange = parseCodexResponseItem(json, timestamp: timestamp) { exchanges.append(exchange) }
    default: break
  }

  private func parseCodexResponseItem(_ json: [String: Any], timestamp: Date) -> Exchange? {
    guard let payload = json["payload"] as? [String: Any],
          (payload["type"] as? String) == "message",
          let roleStr = payload["role"] as? String,
          let role = Exchange.Role(rawValue: roleStr),
          let content = payload["content"] as? [[String: Any]] else { return nil }

    let text = content.compactMap { part -> String? in
      guard let t = part["type"] as? String else { return nil }
      switch t {
        case "input_text", "output_text", "markdown": return part["text"] as? String
        default: return nil
      }
    }.joined(separator: "\n")

    let sanitized = sanitizeText(text)
    return sanitized.isEmpty ? nil : Exchange(role: role, text: sanitized, timestamp: timestamp)
  }
  ```

* **Detail header ignores metadata title/description**

  * **Fix:** Replace file-name header with metadata-driven header and fallback.

  ```swift
  struct TranscriptDetailView: View {
    // ...
    @State private var metadata: TranscriptMetadata?

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(metadata?.title ?? session.identifier)
                .font(.title2).fontWeight(.semibold)
              if let desc = metadata?.description, !desc.isEmpty {
                Text(desc).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
              } else {
                Text(providerName).font(.subheadline).foregroundStyle(.secondary)
              }
            }
            Spacer()
            // Active badge remains
          }
          // ...
        }
      }
      .task(id: session.fileURL) { await loadMetadata() }
    }
  }
  ```

* **Filename grounding removal corrupts strings**

  * **Root cause:** `MetadataPostProcessor.stripUnseenFilenames` converts `NSRange` to `String.Index` using `offsetBy:` on the Swift string, which is invalid for UTF-16–based `NSRange`.
  * **Fix:** Use `Range(nsRange, in: text)` for safe conversion.

  ```swift
  if let swiftRange = Range(range, in: cleanedText) {
    cleanedText.removeSubrange(swiftRange)
  }
  ```

* **Heavy file I/O done on MainActor**

  * **Files:** `TranscriptMetadataOrchestrator.generateMetadata`, `SidecarMetadataStore.load`, `SidecarMetadataStore.sha256`, `TranscriptParser.parseExchanges`
  * **Fix:** Move file reads/hashing/parsing off-main; keep only state mutation on main/actor.

  ```swift
  // Orchestrator
  let exchanges = try await Task.detached(priority: .utility) {
    try TranscriptParser().parseExchanges(url: session.fileURL)
  }.value

  // Sidecar load/hash off-main
  private func loadCachedIfFresh(_ url: URL) async -> TranscriptMetadata? {
    await Task.detached {
      let store = SidecarMetadataStore()
      guard let cached = try? store.load(for: url) else { return nil }
      return store.isFresh(cached, for: url, promptVersion: currentPromptVersion, generatorVersion: currentGeneratorVersion) ? cached : nil
    }.value
  }
  ```

* **Atomic write is not reliable**

  * **Root cause:** `SidecarMetadataStore.save` writes to a temp and then uses `replaceItemAt` ignoring errors; `.atomic` on the temp write is redundant; temp file may be orphaned.
  * **Fix:** Use `FileManager.replaceItemAt` with proper error handling OR write to `sidecarPath` with `.atomic` (which already writes via a temp + rename).

  ```swift
  func save(_ metadata: TranscriptMetadata, for url: URL) async throws {
    let sidecar = sidecarURL(for: url)
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(metadata)
    try data.write(to: sidecar, options: .atomic) // single-step atomic replace
  }
  ```

* **Spin-wait concurrency limiter**

  * **Root cause:** `waitForLLMSlot` busy-waits with sleep; imprecise and wastes cycles.
  * **Fix:** Use an async semaphore.

  ```swift
  actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ value: Int) { self.value = value }
    func acquire() async { if value > 0 { value -= 1; return }
      await withCheckedContinuation { waiters.append($0) } }
    func release() { if let c = waiters.first { waiters.removeFirst(); c.resume() } else { value += 1 } }
  }

  // in Orchestrator
  private let llmSem = AsyncSemaphore(2)
  // usage
  await llmSem.acquire()
  defer { llmSem.release() }
  ```

* **Actor task cleanup uses detached `Task` inside the actor**

  * **Root cause:** `defer { Task { self.removeTask(for:) } }` crosses isolation unnecessarily.
  * **Fix:** Modify actor state directly in `defer`.

  ```swift
  let task = Task<TranscriptMetadata, Error> {
    defer { self.activeTasks[session.fileURL] = nil }
    return try await self.generateMetadata(for: session, forceRegenerate: forceRegenerate)
  }
  ```

* **Progress label promises duration**

  * **Fix:** Remove `(~3s)` estimate; reflect true state only.

  ```swift
  HStack(spacing: 4) {
    ProgressView().controlSize(.mini).scaleEffect(0.7)
    Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
  }
  ```

* **Search does not include metadata fields**

  * **Fix:** Include `meta.title`/`meta.description` in `filteredSessions`.

  ```swift
  private var filteredSessions: [TranscriptSession] {
    let sessions = monitor.allSessions
    guard !searchText.isEmpty else { return sessions }
    let q = searchText.lowercased()
    return sessions.filter { s in
      if s.identifier.lowercased().contains(q) || s.fileURL.path.lowercased().contains(q) { return true }
      if let m = metadata[s.fileURL] {
        return m.title.lowercased().contains(q) || m.description.lowercased().contains(q) || m.topics.contains { $0.contains(q) }
      }
      return false
    }
  }
  ```

* **Row-triggered metadata fetch to avoid thundering herd**

  * **Fix:** Request generation when a row becomes visible instead of bulk-loading on `.task` for entire list.

  ```swift
  private func sessionRow(_ session: TranscriptSession) -> some View {
    VStack { /* existing row */ }
      .task(id: session.fileURL) { await ensureMetadata(session) } // per-row
  }

  private func ensureMetadata(_ session: TranscriptSession) async {
    if metadata[session.fileURL] == nil, !loadingMetadata.contains(session.fileURL) {
      loadingMetadata.insert(session.fileURL)
      defer { loadingMetadata.remove(session.fileURL) }
      if let cached = try? SidecarMetadataStore().load(for: session.fileURL) {
        metadata[session.fileURL] = cached; return
      }
      if let gen = try? await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session) {
        metadata[session.fileURL] = gen
      }
    }
  }
  ```

* **Hash computation is O(file) each time**

  * **Fix:** Short-circuit freshness check via file size + modDate; only compute SHA256 if those have changed since `generatedAt`.

  ```swift
  func isFresh(_ metadata: TranscriptMetadata, for url: URL, promptVersion: Int, generatorVersion: Int) -> Bool {
    guard promptVersion == metadata.promptVersion, generatorVersion == metadata.generatorVersion else { return false }
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
       let mod = attrs[.modificationDate] as? Date, mod <= metadata.generatedAt {
      return true
    }
    guard let currentHash = try? sha256(url: url) else { return false }
    return metadata.transcriptSHA256 == currentHash
  }
  ```

* **Parser/formatter hot allocation**

  * **Fix:** Reuse formatters; avoid re-allocating `ISO8601DateFormatter`/`RelativeDateTimeFormatter`.

  ```swift
  enum Fmts {
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
  }
  // use Fmts.iso for parse/format
  ```

* **UI: replace duplicate refresh affordances**

  * **Fix:** Remove sidebar Refresh button; keep toolbar `.primaryAction`. If kept, wire to `await monitor.refresh()`.

* **Thread safety in `SessionRecorder.saveReports`**

  * **Fix:** Isolate `pendingReportsSave` on main or an actor; compute JSON in detached task; avoid referencing `SessionRecorder.shared` inside detached task.

  ```swift
  @MainActor final class SessionRecorder { /* ... */ }
  @MainActor private func saveReports() {
    guard !pendingReportsSave else { return }
    pendingReportsSave = true
    let snapshot = RecorderReportsFile(/* ... */)
    let url = reportsURL; let logger = log
    Task.detached(priority: .utility) {
      do {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
      } catch { await MainActor.run { logger.error("Failed to save reports: \(error.localizedDescription)") } }
      await MainActor.run { pendingReportsSave = false }
    }
  }
  ```

* **ConversationMonitor.refresh isolation**

  * **Fix:** Remove `nonisolated` and nested `Task`; make it `@MainActor` `async` that forwards to the real method.

  ```swift
  @MainActor func refresh() async { await refreshActiveConversation(force: true) }
  ```

* **Window behavior polish**

  * **Fix:** Center default position; persist frame; focus existing instance when opened from menu.

  ```swift
  Window("Transcripts", id: "transcript-inventory") { TranscriptInventoryWindow() }
    .defaultSize(width: 1000, height: 700)
    .defaultPosition(.center)

  struct TranscriptInventoryCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
      CommandGroup(after: .windowArrangement) {
        Button("Show Transcripts") {
          openWindow(id: "transcript-inventory")
          NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut("i", modifiers: [.command, .control])
      }
    }
  }
  ```

* **Tests required**

  * Parser: Codex `response_item` → 1 exchange; `event_msg`/`reasoning` ignored; assistant `markdown` parsed.
  * Orchestrator: Circuit breaker triggers after 5 failures; next call uses heuristic; on success, breaker resets.
  * UI: Row `.task` triggers exactly once per visible row; avoid spawning > `allSessions.count` tasks when list reloads.
  * Post-processor: `stripUnseenFilenames` removes unseen names using `Range(_, in:)` without crashing on extended grapheme clusters.

* **Migration note**

  * Backfill metadata sidecars asynchronously for existing sessions on idle (throttled), then refresh list once per batch to avoid UI churn.


# Reviewer 2:

## Required Fixes

### CRITICAL: Codex transcript parsing not implemented

**Problem:** Parser only handles Claude Code format. Codex transcripts use `response_item` with nested `payload.type: "message"` structure.

```swift
// TranscriptParser.swift - Add Codex support
private func parseResponseItem(_ json: [String: Any], timestamp: Date) -> [Exchange]? {
  guard let payload = json["payload"] as? [String: Any],
        let message = payload["message"] as? [String: Any],
        let role = message["role"] as? String,
        let contentArray = message["content"] as? [[String: Any]] else {
    return nil
  }
  
  var exchanges: [Exchange] = []
  for block in contentArray {
    guard let blockType = block["type"] as? String else { continue }
    
    if blockType == "input_text",
       let text = block["text"] as? String {
      let sanitized = sanitizeText(text)
      if !sanitized.isEmpty {
        let exchangeRole: Exchange.Role = (role == "user") ? .user : .assistant
        exchanges.append(Exchange(role: exchangeRole, text: sanitized, timestamp: timestamp))
      }
    }
  }
  
  return exchanges.isEmpty ? nil : exchanges
}

// Update parseExchanges switch statement
switch type {
case "user":
  if let exchange = parseUserMessage(json, timestamp: timestamp) {
    exchanges.append(exchange)
  }
case "assistant":
  if let parsedExchanges = parseAssistantMessage(json, timestamp: timestamp) {
    exchanges.append(contentsOf: parsedExchanges)
  }
case "response_item":  // ADD THIS
  if let parsedExchanges = parseResponseItem(json, timestamp: timestamp) {
    exchanges.append(contentsOf: parsedExchanges)
  }
default:
  continue
}
```

---

### CRITICAL: Detail view shows filename instead of title

**Problem:** Header displays `session.fileURL.lastPathComponent` even when metadata exists.

```swift
// TranscriptInventoryView.swift - Fix detail header
// Replace existing header section (lines ~238-261) with:
HStack {
  VStack(alignment: .leading, spacing: 4) {
    if let meta = metadata {
      Text(meta.title)
        .font(.title2)
        .fontWeight(.semibold)
    } else {
      Text(session.identifier)
        .font(.title2)
        .fontWeight(.semibold)
    }
    
    Text(session.fileURL.lastPathComponent)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
  
  Spacer()
  
  if isActive {
    HStack(spacing: 4) {
      Image(systemName: "circle.fill")
        .foregroundStyle(.green)
        .font(.caption)
      Text("Active")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
```

---

### CRITICAL: Circuit breaker too aggressive

**Problem:** After 5 failures in 5 minutes, all metadata defaults to "Developer Chat" heuristic. First LLM errors cascade to permanent degradation.

```swift
// TranscriptMetadataOrchestrator.swift - Per-session circuit breaker
private struct CircuitBreakerState {
  var consecutiveFailures = 0
  var lastFailureTime: Date?
  var isOpen = false
}

private var circuitStates: [URL: CircuitBreakerState] = [:]
private let circuitBreakerThreshold = 3  // Reduce from 5
private let circuitBreakerWindow: TimeInterval = 120  // 2min instead of 5min

private func shouldUseCircuitBreaker(for url: URL) -> Bool {
  guard let state = circuitStates[url],
        let lastFailure = state.lastFailureTime else {
    return false
  }
  
  let elapsed = Date().timeIntervalSince(lastFailure)
  if elapsed > circuitBreakerWindow {
    circuitStates[url] = nil  // Reset
    return false
  }
  
  return state.consecutiveFailures >= circuitBreakerThreshold
}

private func recordSuccess(for url: URL) {
  circuitStates[url] = nil
}

private func recordFailure(for url: URL) {
  var state = circuitStates[url] ?? CircuitBreakerState()
  state.consecutiveFailures += 1
  state.lastFailureTime = Date()
  circuitStates[url] = state
  
  if state.consecutiveFailures >= circuitBreakerThreshold {
    log.warning("Circuit breaker triggered for \(url.lastPathComponent)")
  }
}

// Update all recordSuccess()/recordFailure() calls to pass session.fileURL
```

---

### HIGH: Heuristic threshold too strict

**Problem:** Sessions with 4 exchanges skip LLM entirely. Meaningful conversations get generic titles.

```swift
// TranscriptMetadataOrchestrator.swift
// Change line ~103:
if exchanges.count < 3 {  // Was: < 5
  log.info("Very short transcript (\(exchanges.count) exchanges), using heuristic")
  let metadata = HeuristicMetadata.generate(exchanges: exchanges)
  try await store.save(metadata, for: session.fileURL)
  return metadata
}
```

---

### HIGH: Missing error visibility in UI

**Problem:** Silent failures leave users confused about missing metadata.

```swift
// TranscriptInventoryView.swift - Add error state
@State private var metadataErrors: [URL: String] = [:]

// Update loadMetadataForSessions
Task {
  do {
    let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
    await MainActor.run {
      metadata[session.fileURL] = generated
      loadingMetadata.remove(session.fileURL)
      metadataErrors.removeValue(forKey: session.fileURL)
    }
  } catch {
    await MainActor.run {
      loadingMetadata.remove(session.fileURL)
      metadataErrors[session.fileURL] = error.localizedDescription
    }
  }
}

// Update row view to show errors
if let error = metadataErrors[session.fileURL] {
  HStack(spacing: 4) {
    Image(systemName: "exclamationmark.triangle")
      .font(.caption)
      .foregroundStyle(.orange)
    Text("Failed to generate")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
  .help(error)
}
```

---

### HIGH: Prompt token budget insufficient

**Problem:** maximumResponseTokens of 220 is tight for JSON output with long descriptions.

```swift
// TranscriptMetadataLLM.swift line ~49
let options = GenerationOptions(
  sampling: .greedy,
  temperature: 0,
  maximumResponseTokens: 300  // Increase from 220
)
```

---

### MEDIUM: Concurrent LLM calls too conservative

**Problem:** Only 2 concurrent calls means inventory loading is slow with many sessions.

```swift
// TranscriptMetadataOrchestrator.swift
private let maxConcurrentLLMCalls = 4  // Increase from 2
```

---

### MEDIUM: Race condition in task deduplication

**Problem:** Task removal happens async, creating window for duplicate tasks.

```swift
// TranscriptMetadataOrchestrator.swift
let task = Task<TranscriptMetadata, Error> {
  defer {
    // Remove synchronously within actor context
    activeTasks.removeValue(forKey: session.fileURL)
  }
  return try await self.generateMetadata(for: session, forceRegenerate: forceRegenerate)
}
```

---

### MEDIUM: Command filtering too broad

**Problem:** Skipping all messages with "command-name" may filter legitimate discussions.

```swift
// TranscriptParser.swift - Be more specific
// Replace line ~114:
if text.hasPrefix("<command-name>") || text.hasPrefix("<local-command-stdout>") {
  return nil
}
```

---

### LOW: Store method should be nonisolated

**Problem:** Inconsistent isolation for pure functions.

```swift
// TranscriptMetadataStore.swift
nonisolated func isFresh(
  _ metadata: TranscriptMetadata,
  for url: URL,
  promptVersion: Int,
  generatorVersion: Int
) -> Bool {
  // ... existing implementation
}
```

---

### LOW: Unnecessary @preconcurrency

**Problem:** TranscriptMetadata is already Sendable, decorator is redundant.

```swift
// TranscriptMetadata.swift - Remove line 18
struct TranscriptMetadata: Codable, Sendable, Equatable {
```

---

### LOW: Token estimation hardcoded

**Problem:** 1.3x multiplier is crude approximation.

```swift
// TranscriptContextBuilder.swift
private static func estimateTokens(for exchanges: [Exchange]) -> Int {
  exchanges.reduce(0) { acc, exchange in
    let charCount = exchange.text.utf8.count
    // ~4 chars per token for code/technical text
    return acc + (charCount / 4) + 10 // overhead per message
  }
}
```

---

### LOW: Filename stripping may break coherence

**Suggestion:** Flag but don't strip filenames - let description keep context.

```swift
// TranscriptMetadataPostProcessor.swift - Only detect, don't remove
func stripUnseenFilenames(in text: String, from context: String) -> (String, Bool) {
  // ... existing detection logic ...
  
  // Don't modify cleanedText, just return hasUnseenFilenames flag
  return (text, hasUnseenFilenames)
}
```