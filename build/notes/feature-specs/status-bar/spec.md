# LLM Processing Status Bar

**Status:** Backlog
**Priority:** Medium
**Related:** Timeline cache, Apple Intelligence integration, user feedback

Add a status bar to the main window that shows real-time LLM processing status and Apple Intelligence availability.

## Current Behavior

- No visibility into LLM processing queue
- No indication whether Apple Intelligence is available
- Users don't know when summaries are being generated
- Cache miss generation happens silently in background

## Proposed Functionality

### 1. LLM Processing Queue Indicator

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

### 2. Apple Intelligence Availability Indicator

- **Status types**:
  - Online: Green dot + "Apple Intelligence: Available"
  - Offline: Gray dot + "Apple Intelligence: Unavailable (requires macOS 26+)"
  - Error: Red dot + "Apple Intelligence: Error" (with details in tooltip)
- **Tooltip on hover**: Show model details
  - "Using FoundationLLM (on-device)"
  - "Model: GPT-4o equivalent"
  - "Session: Timeline summarization (user/assistant)"
- **Placement**: Next to queue indicator or in separate section

## UI Design Options

### Option A: Footer Status Bar (Recommended)

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

### Option B: Header Compact

```
┌────────────────────────────────────────────────┐
│ Project: Contextify    ●AI  ⚙️12  [Settings]  │
├────────────────────────────────────────────────┤
│ [Timeline entries...]                          │
```

### Option C: Hover Popover

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

## Known LLM Failure Modes

**IMPORTANT:** Apple Intelligence availability checking requires a "belt and suspenders" approach:

### 1. Belt (Official API)

`SystemLanguageModel.default.availability`

- Returns: `.available`, `.unavailable(reason)`
- Reasons: `.appleIntelligenceNotEnabled`, `.deviceNotEligible`, `.modelNotReady`
- **Limitation:** Can return `.available` even when runtime failures occur

### 2. Suspenders (Runtime Test Call)

Actual LLM call to detect system errors

- **Why needed:** The official API doesn't detect all failure modes
- **Example:** macOS 26 beta bug where system file is missing

### Discovered Error Patterns

| Error Type | Symptoms | Detection | User-Facing Message | Workaround |
|------------|----------|-----------|---------------------|------------|
| **Guardrail System Error** | ALL LLM calls fail with `guardrailViolation`, missing `/System/Library/AssetsV2/.../metadata.json` | Error contains "metadata.json" + "No such file" | "Apple Intelligence system error detected. Try: Settings → Apple Intelligence → Toggle off/on, then restart Mac." | Toggle AI off/on in System Settings + restart |
| **Model Not Ready** | Official API returns `.modelNotReady` | `SystemLanguageModel.default.availability` | "Language model is not ready. Please wait a few moments and try again." | Wait a few minutes, model may be downloading |
| **AI Not Enabled** | Official API returns `.appleIntelligenceNotEnabled` | `SystemLanguageModel.default.availability` | "Apple Intelligence is not enabled. Please enable it in System Settings." | Settings → Apple Intelligence → Enable |
| **Device Not Eligible** | Official API returns `.deviceNotEligible` | `SystemLanguageModel.default.availability` | "This Mac is not eligible for Apple Intelligence." | Upgrade to supported Mac hardware |

### Reference Implementation

- `Contextify/Contextify/LLMHealthCheck.swift` - Comprehensive health checker with both approaches
- Uses cached status (30s TTL) to avoid hammering the system
- Detects specific error patterns in `GenerationError.guardrailViolation`

### Community Reports

- Missing metadata.json error: https://www.reddit.com/r/iOSProgramming/comments/1la7o9r/comment/n41eh7d/
- Common on macOS 26 beta builds
- Workaround: Toggle Apple Intelligence off/on + restart

## Technical Implementation

### Usage Pattern

```swift
// Use LLMHealthCheck for comprehensive checking
let status = await LLMHealthCheck.shared.checkHealth()

switch status {
case .healthy:
  // LLM is fully functional
case .unavailable(let reason):
  // Show user-facing message: reason.userFacingMessage
}
```

### StatusBarViewModel.swift (new)

```swift
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
```

### TimelineCacheMissGenerator.swift Extension

```swift
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
```

### FoundationLLM.swift Extension

```swift
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

### StatusBarView.swift (new SwiftUI component)

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

### Integration in ContentView.swift

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

## Implementation Phases

### Phase 1: Basic Queue Display (~1 day)

- Add `getQueueStats()` to TimelineCacheMissGenerator
- Create StatusBarViewModel with polling
- Simple UI showing queue depth + processing state
- Footer placement

### Phase 2: Apple Intelligence Indicator (~1 day)

- Add `checkAvailability()` to FoundationLLM
- AI status detection on macOS 26+
- Graceful fallback for older OS versions
- Tooltip with detailed info

### Phase 3: Polish & Interactivity (~1 day)

- Animated transitions for state changes
- Click to show detailed queue viewer (optional)
- Time estimate refinement (track actual LLM latency)
- Preference to hide/show status bar

## User Benefits

- **Transparency**: Users know when LLM is working in background
- **Troubleshooting**: Immediately see if Apple Intelligence is unavailable
- **Expectations**: Time estimates help users understand when summaries will appear
- **Confidence**: "Up to date" indicator confirms all summaries are cached

## Edge Cases

- **macOS < 26**: Show "AI Unavailable (requires macOS 26+)"
- **FoundationModels unavailable**: Show "AI Unavailable (system requirement)"
- **Large queue (>100)**: Show "Processing many items..." instead of exact count
- **LLM error**: Show error state with tooltip explaining issue
- **Generator nil**: Hide status bar or show "Not monitoring"

## Performance Considerations

- Polling interval: 500ms (balance responsiveness vs CPU)
- Use actor isolation for thread-safe queue access
- No UI updates if values unchanged (SwiftUI auto-optimizes)

## Related Work

- See `build/notes/technical-reference/timeline-cache-llm-architecture.md` for LLM integration details
- See `build/notes/technical-reference/conversation-monitor-state-architecture.md` for state management
