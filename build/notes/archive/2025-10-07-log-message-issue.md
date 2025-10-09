Here’s a tight, root-cause analysis with concrete fixes.

# Findings (root causes → symptoms)

1. Prefix-forcing bug in `sanitize(...)`
   **Where:** `Contextify/Contextify/FoundationLLM.swift` → `sanitize(_:kind:)` + `prefix(for:)`.
   **What:** For `.user`, `prefix(for:)` returns `"You requested Claude"`. `sanitize(...)` then unconditionally preprends that prefix unless the generated text already starts with it.
   **Why it matters:** After you changed the **instructions** to allow `"You made"` / `"You asked"` / `"You requested Claude"`, the model correctly emits e.g. `"You made the change to the prompt."`, but `sanitize(...)` rewrites it to `"You requested Claude You made the change to the prompt."`
   **Symptom reproduced:** The duplicate-looking summary line

```
You requested Claude You made the change to the prompt.
```

appears (and will also cause different user messages to look overly similar).

2. Prompt contamination in assistant rules (tool bias)
   **Where:** `instructionsForTimeline(kind: .assistant)` examples.
   **What:** The examples include tool strings like `Bash('pytest -q')`. Even with `temperature: 0`, examples seed the decoder.
   **Why it matters:** The assistant summary `"Claude explains the bug and proposes using Bash('pytest -q') to fix it."` appears even though no such content exists in the actual assistant message. That’s classic example-bleed: the model copied the tool token from the instruction examples, not from the MESSAGE.

3. Over-broad `ACTION_HINT` usage (likely contributor)
   **Where:** Callers of `summarizeTimeline(kind:.user, text:, actionHint:)` (in `ConversationMonitor.swift` or the pipeline attaching action hints).
   **What:** The code path accepts any `actionHint` for user messages, but the instruction says hints are **only** for bare affirm/deny. If callers pass `ACTION_HINT` for a normal user message (e.g., “for FoundationLLM.swift:169 …”), the model can be nudged toward an “approve/execute” reading, increasing chances of emitting the “You requested Claude …” shape or echoing prior context.
   **Symptom risk:** User messages that aren’t approvals get framed as approvals (or end up reusing prior shape like “made the change”).

4. Race / attachment risk in the file-watch pipeline
   **Where:** `ConversationMonitor.swift` (watcher + async summarization + UI attach).
   **What (likely):** If you process multiple new lines concurrently and attach summaries by **index** rather than a stable key (e.g., the JSONL `uuid`), out-of-order returns can mismatch a summary to the wrong log row.
   **Symptom risk:** A later user row receives the previous row’s summary (“duplicate & incorrect” on the wrong entry). This fits the observed “same sentence applied twice” pattern during bursts around 19:33–19:36.

5. Event filtering (possible duplication source)
   **Where:** `ConversationMonitor.swift` ingestion.
   **What:** The JSONL shows `tool_use`, `tool_result`, and `file-history-snapshot` lines alongside user/assistant messages. If your monitor treats a tool result’s **embedded code block** (which literally contains your timeline instruction text) as another “user message”, it can:

* cause extra, confusing summaries, and
* inject prior-prompt content into the model input for the “next” summary (perceived as leak).

# Concrete fixes (patches + guardrails)

## A. Fix prefix enforcement to match the new spec

**File:** `Contextify/Contextify/FoundationLLM.swift`

Replace the hard-coded prefix forcing with an allow-list per kind.

```swift
private extension FoundationLLM {
    struct PrefixPolicy {
        let allowed: [String]
        let fallback: String
    }

    func policy(for kind: TimelineEntryKind) -> PrefixPolicy {
        switch kind {
        case .user:
            // Allow the three shapes introduced in your new instructions.
            return PrefixPolicy(
                allowed: ["You made", "You asked", "You requested Claude"],
                fallback: "You requested Claude"
            )
        case .assistant:
            return PrefixPolicy(allowed: ["Claude"], fallback: "Claude")
        case .system:
            return PrefixPolicy(allowed: ["System"], fallback: "System")
        }
    }

    func sanitize(_ summary: String, kind: TimelineEntryKind) -> String {
        var normalized = collapseWhitespace(summary)

        let p = policy(for: kind)
        let hasAllowedPrefix = p.allowed.contains { normalized.hasPrefix($0) }

        if normalized.isEmpty {
            normalized = p.fallback
        } else if !hasAllowedPrefix {
            normalized = "\(p.fallback) \(normalized)"
        }

        if normalized.count > 110 {
            normalized = String(normalized.prefix(110))
        }
        return normalized
    }

    // Remove the existing `prefix(for:)` helper, or keep it only for fallback.
}
```

**Effect:**

* Leaves `"You made …"` and `"You asked …"` intact.
* Keeps assistant & system lines correctly prefixed.
* Eliminates `"You requested Claude You made …"` duplication.

## B. Remove tool-specific examples from assistant instructions

**File:** `FoundationLLM.swift` → `instructionsForTimeline(kind: .assistant)`

Do two things:

1. **Delete** any examples with `Bash('pytest -q')`, `Edit(...)`, `Read(...)`, `Write(...)`.
2. **Add a strict anti-invention rule**:

```text
- Do NOT mention any tool names (e.g., Bash/Edit/Read/Write, or quoted commands)
  unless those exact tokens appear in MESSAGE.
- If MESSAGE lacks an explicit tool string, do not infer or propose tools.
```

Keep one or two **neutral** examples instead (no tool tokens): e.g.,

```text
Examples:
Input: "✅ Done. The build succeeded and the file was saved."
→ summary: "Claude confirmed the build succeeded and saved the file."
→ isCompletion: true

Input: "We should consider refactoring the view model."
→ summary: "Claude proposes refactoring the view model."
→ isCompletion: false
```

**Effect:** Removes the seed that produced the hallucinated `Bash('pytest -q')` line.

## C. Gate `ACTION_HINT` usage (caller side)

**File:** `Contextify/Contextify/ConversationMonitor.swift` (or wherever you call `summarizeTimeline`)

Only pass `actionHint:` when the **current** user message is a bare affirm/deny. Example:

```swift
@MainActor
func actionHintForUserMessage(_ text: String, lastAssistantProposal: String?) -> String? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let affirm = ["yes","ok","okay","sure","y","👍","go ahead","proceed","do it","please do","sgtm","roger"]
    let deny   = ["no","not now","hold off","stop","don't","do not","cancel","abort"]

    guard let hint = lastAssistantProposal,
          (affirm.contains(t) || deny.contains(t)) else {
        return nil  // do NOT pass actionHint for non-affirm/deny
    }
    return hint
}
```

**Effect:** Prevents ACTION_HINT from biasing ordinary user messages into “approve” summaries.

## D. Attach summaries by stable id; serialize per-session

**File:** `ConversationMonitor.swift`

* Parse each JSONL line; **skip** non-message events (see “E” below).
* Construct a stable key from the line’s `uuid` field (present in the transcript you showed).
* Store a `TimelineEntry` map: `Dictionary<String /*uuid*/, TimelineEntry>`
* When a summary completes, write it back to the entry **by uuid**, not by array index.
* Process a given sessionId in arrival order but tolerate out-of-order completions (the map makes this safe).

Sketch:

```swift
struct IngestedLine {
    let uuid: String
    let role: Role // user|assistant
    let content: String
    let ts: Date
}

actor TimelineIndexer {
    private var entries: [String: TimelineEntry] = [:] // keyed by uuid

    func upsert(line: IngestedLine) {
        var e = entries[line.uuid] ?? TimelineEntry(from: line)
        e.rawText = line.content
        entries[line.uuid] = e
    }

    func attachSummary(uuid: String, summary: String, isCompletion: Bool) {
        guard var e = entries[uuid] else { return }
        e.summary = summary
        e.isCompletion = isCompletion
        entries[uuid] = e
    }
}
```

**Effect:** Even if async tasks finish out of order, summaries land on the correct rows. This addresses the “same summary on a different line” symptom.

## E. Filter out non-message JSONL lines

**File:** `ConversationMonitor.swift`

Before summarizing, **discard** lines with:

* `type: "file-history-snapshot"`
* any `message.content` entries where `type` is `"tool_use"` or `"tool_result"` (these often embed source code and will look like user text if not filtered)
* any `isSidechain: true` (if you don’t want sidechains)

Guard example:

```swift
func shouldSummarize(_ json: [String: Any]) -> Bool {
    guard json["type"] as? String == "user" || json["type"] as? String == "assistant" else { return false }
    if let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] {
        // Claude-style structured content: reject tool_use/tool_result frames
        let hasTools = content.contains { ($0["type"] as? String).map { $0 == "tool_use" || $0 == "tool_result" } ?? false }
        if hasTools { return false }
    }
    return true
}
```

**Effect:** Eliminates bogus extra rows caused by tool frames and snapshots.

## F. Minor hardening in `FoundationLLM.summarizeTimeline(...)`

* Keep `temperature: 0.0` (already set).
* Consider dropping `maximumResponseTokens` from 48 → 32 to reduce drift.
* Clamp input (`clamped`) — already done. Good.

Optional extra guard just before returning:

```swift
let finalSummary = normalizedSummary
    .replacingOccurrences(of: #"Bash\('[^']+'\)"#, with: "Bash(...)", options: .regularExpression)
// Or better: if MESSAGE lacks tool tokens, strip any tool mentions entirely.
```

But prefer to fix the prompt (B) and filtering (E) instead of post-hoc stripping.

# Quick unit tests (sanitizer)

Add a tiny test target covering the critical prefix logic.

```swift
import XCTest
@testable import Contextify

final class TimelineSanitizeTests: XCTestCase {
    func testUser_Made_Preserved() {
        let s = FoundationLLM.shared
        let out = await s.test_sanitize("You made the change to the prompt.", kind: .user)
        XCTAssertEqual(out, "You made the change to the prompt.")
    }

    func testUser_Asked_Preserved() {
        let s = FoundationLLM.shared
        let out = await s.test_sanitize("You asked how this works.", kind: .user)
        XCTAssertEqual(out, "You asked how this works.")
    }

    func testUser_Unknown_PrependsFallback() {
        let s = FoundationLLM.shared
        let out = await s.test_sanitize("Fix the build warnings.", kind: .user)
        XCTAssertEqual(out, "You requested Claude Fix the build warnings.")
    }

    func testAssistant_Prefix() {
        let s = FoundationLLM.shared
        let out = await s.test_sanitize("explains the plan.", kind: .assistant)
        XCTAssertEqual(out, "Claude explains the plan.")
    }
}
```

Expose a `test_sanitize` wrapper in an `internal` testable extension if needed.

# Minimal repro mapping (your transcript)

From the JSONL (times in UTC, truncated to essentials):

* `19:33:52` user: “I’ve made the change to the prompt.”
  → Model outputs “You made …”; **sanitize** turns it into
  → “You requested Claude You made …”  (**RC1**)

* `19:33:57` assistant: “Good. That should prevent …”
  → Should be “Claude acknowledges.” (OK)

* `19:35:50` user: “for … FoundationLLM.swift:169 … recommend an updated prompt …”
  → If ACTION_HINT was incorrectly passed (**RC3**), or a summary from the previous call was attached (**RC4**), you see the **same** “You requested Claude You made …” line again.

* Assistant lines around `19:35:58` include editing the file; your assistant instruction examples contain `Bash('pytest -q')`; the next assistant summary hallucinated that token (**RC2**).

# Rollout order

1. Apply patch (A) and instruction edits (B).
2. Add caller-side gating (C) and event filtering (E).
3. Ensure summary attachment by `uuid` (D).
4. Re-run on the same JSONL tail; the duplicate “You requested Claude You made …” should disappear, and the pytest hallucination should be gone.

If you want, I can draft the exact diffs for `ConversationMonitor.swift` once you share that file’s message parsing and dispatch code.