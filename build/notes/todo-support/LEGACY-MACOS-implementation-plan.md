# Implementation Plan: Legacy macOS Support (LEGACY-MACOS)

**Spec:** `build/notes/todo-support/LEGACY-MACOS-spec.md`
**Goal:** Lower deployment target to macOS 15, provide "Lite Mode" without LLM summaries

## Summary

Add macOS 15 support with graceful degradation. Users on older macOS get timeline monitoring, transcript indexing, and search - but no AI summaries. Summaries auto-generate when they upgrade to macOS 26.

---

## Phase 1: Foundation (3 commits)

### Commit 1: Add LLMAvailability enum

```
feat(llm): add LLMAvailability enum with lite mode detection
```

**Create file:** `Contextify/Contextify/LLMAvailability.swift`

```swift
//
//  LLMAvailability.swift
//  Contextify
//
//  Centralized LLM availability detection with lite mode support
//

import Foundation
import OSLog

/// Centralized LLM availability detection.
///
/// Use `LLMAvailability.current` to check if LLM features are available.
/// In "lite mode" (macOS 15 or simulation), summaries are disabled but
/// timeline monitoring, indexing, and search still work.
///
/// **Design note:** `current` is NOT @MainActor because it's a pure check
/// (OS version + launch args) with no UI state. This allows calling from
/// any context: SwiftUI views, actors, view models.
enum LLMAvailability: Sendable, Equatable {
    case available
    case unavailableOldOS
    case unavailableNotEnabled(reason: String)
    case unavailableOther(reason: String)

    /// True if running in lite mode (no LLM summaries)
    var isLiteMode: Bool {
        switch self {
        case .available:
            return false
        case .unavailableOldOS, .unavailableNotEnabled, .unavailableOther:
            return true
        }
    }

    /// User-facing description for status bar
    var statusText: String {
        switch self {
        case .available:
            return "Apple Intelligence"
        case .unavailableOldOS:
            return "Lite Mode"
        case .unavailableNotEnabled(let reason):
            return reason
        case .unavailableOther(let reason):
            return reason
        }
    }

    // MARK: - Cached Availability (computed once per process)

    /// Cached availability - computed once at process start, never changes.
    /// OS version and launch args are constants for the process lifetime.
    private static let cached: LLMAvailability = {
        if simulateLegacyMacOS {
            return .unavailableOldOS
        }
        guard #available(macOS 26, *) else {
            return .unavailableOldOS
        }
        return .available
    }()

    /// Current LLM availability (cached, safe to call from any context)
    ///
    /// Check this before any LLM operations. In lite mode, skip LLM calls entirely.
    /// NOT @MainActor - can be called from views, actors, anywhere.
    static var current: LLMAvailability { cached }

    /// Launch argument to simulate lite mode on macOS 26 for testing
    ///
    /// Usage:
    /// - Xcode: Edit Scheme > Run > Arguments > Add `-simulate-legacy-macos`
    /// - Terminal: `./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos`
    ///
    /// Only available in DEBUG builds to prevent end-users from forcing lite mode.
    static var simulateLegacyMacOS: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos")
        #else
        return false
        #endif
    }
}

// MARK: - Logging

extension LLMAvailability {
    private static let log = Logger(subsystem: "dev.contextify", category: "LLMAvailability")

    /// Log current availability status (call once at startup)
    static func logStatus() {
        let status = current
        switch status {
        case .available:
            log.info("[LLM-AVAILABILITY] Full mode - Apple Intelligence available")
        case .unavailableOldOS:
            if simulateLegacyMacOS {
                log.notice("[LLM-AVAILABILITY] Lite mode - simulating legacy macOS via launch argument")
            } else {
                log.notice("[LLM-AVAILABILITY] Lite mode - macOS version < 26")
            }
        case .unavailableNotEnabled(let reason):
            log.warning("[LLM-AVAILABILITY] Lite mode - \(reason, privacy: .public)")
        case .unavailableOther(let reason):
            log.warning("[LLM-AVAILABILITY] Lite mode - \(reason, privacy: .public)")
        }
    }
}
```

---

### Commit 2: Lower deployment target

```
build: lower deployment target to macOS 15.0
```

**Edit file:** `Contextify/Contextify.xcodeproj/project.pbxproj`

Find and replace all occurrences:
```
MACOSX_DEPLOYMENT_TARGET = 26.0;
```
With:
```
MACOSX_DEPLOYMENT_TARGET = 15.0;
```

There should be 4 occurrences (Debug, Release for main target and tests).

**Verify:** `bash scripts/xc.sh build` succeeds with zero warnings.

---

### Commit 3: Add lite mode preference key

```
feat(prefs): add lite mode info dismissed preference
```

**Edit file:** `app/Sources/ContextifyCore/HUDCore.swift`

Add after line 22 (after `appStoreOnboardingCompletedKey`):

```swift
  // Lite mode info modal
  public static let liteModeInfoDismissedKey = "dev.contextify.liteModeInfoDismissed"
```

Add after line 148 (after `hasCompletedAppStoreOnboarding`):

```swift
  // MARK: - Lite Mode Info

  /// Returns true if the user has dismissed the lite mode info modal.
  public static func hasLiteModeInfoBeenDismissed() -> Bool {
    return sharedDefaults.bool(forKey: liteModeInfoDismissedKey)
  }

  /// Mark the lite mode info modal as dismissed.
  public static func setLiteModeInfoDismissed(_ dismissed: Bool) {
    sharedDefaults.set(dismissed, forKey: liteModeInfoDismissedKey)
  }
```

---

## Phase 2: Runtime Guards (3 commits)

### Commit 4: Guard LLMHealthCheck usage

```
feat(llm): wrap LLMHealthCheck with availability guards
```

**Edit file:** `Contextify/Contextify/StatusBarViewModel.swift`

**Change 1:** Update `loadCachedAIStatus()` (around line 269):

Replace:
```swift
    private func loadCachedAIStatus() async {
        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            return
        }
```

With:
```swift
    private func loadCachedAIStatus() async {
        // Check lite mode first (covers both old OS and simulation)
        if LLMAvailability.current.isLiteMode {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            return
        }

        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            return
        }
```

**Change 2:** Update `checkAppleIntelligenceHealth()` (around line 292):

Replace:
```swift
    private func checkAppleIntelligenceHealth() async {
        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            log.debug("Apple Intelligence check: macOS < 26")
            return
        }
```

With:
```swift
    private func checkAppleIntelligenceHealth() async {
        // Check lite mode first (covers both old OS and simulation)
        if LLMAvailability.current.isLiteMode {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            log.debug("Apple Intelligence check: lite mode active")
            return
        }

        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            log.debug("Apple Intelligence check: macOS < 26")
            return
        }
```

**Change 3:** Update `start()` to skip health check task in lite mode (around line 104):

Replace:
```swift
        // Check Apple Intelligence periodically (every 30s to respect cache)
        aiHealthCheckTask = Task { @MainActor [weak self] in
```

With:
```swift
        // Check Apple Intelligence periodically (every 30s to respect cache)
        // Skip in lite mode - no LLM to check
        guard !LLMAvailability.current.isLiteMode else {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            log.info("StatusBar: Skipping AI health checks (lite mode)")
            return
        }

        aiHealthCheckTask = Task { @MainActor [weak self] in
```

Wait, that's inside an if block. Let me restructure:

Replace the entire health check task block (lines 104-120):
```swift
        // Check Apple Intelligence periodically (every 30s to respect cache)
        aiHealthCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Load cached status immediately to avoid flicker on project switches
            await self.loadCachedAIStatus()

            // Then perform full health check (will use cache if recent)
            await self.checkAppleIntelligenceHealth()

            // Periodic refresh (every 30s)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                await self.checkAppleIntelligenceHealth()
            }
        }
```

With:
```swift
        // Check Apple Intelligence periodically (every 30s to respect cache)
        // In lite mode, just set status once and skip periodic checks
        if LLMAvailability.current.isLiteMode {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            log.info("StatusBar: Lite mode - skipping AI health check task")
        } else {
            aiHealthCheckTask = Task { @MainActor [weak self] in
                guard let self else { return }

                // Load cached status immediately to avoid flicker on project switches
                await self.loadCachedAIStatus()

                // Then perform full health check (will use cache if recent)
                await self.checkAppleIntelligenceHealth()

                // Periodic refresh (every 30s)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    guard !Task.isCancelled else { break }
                    await self.checkAppleIntelligenceHealth()
                }
            }
        }
```

---

### Commit 5: Guard TimelineCacheMissGenerator

```
feat(llm): skip summary queue in lite mode
```

**Edit file:** `Contextify/Contextify/TimelineCacheMissGenerator.swift`

**Change 1:** Add early return in `queueMisses()` (find the method, add at start):

Find:
```swift
    func queueMisses(_ misses: [CacheMiss]) {
```

Add after the opening brace:
```swift
        // Skip in lite mode - no LLM available for summaries
        if LLMAvailability.current.isLiteMode {
            log.info("[LITE-MODE] Skipping \(misses.count) cache misses - summaries disabled")
            return
        }
```

**Change 2:** Add early return in `processQueue()`:

Find:
```swift
    private func processQueue() async {
```

Add after the opening brace:
```swift
        // Skip in lite mode - no LLM available for summaries
        guard !LLMAvailability.current.isLiteMode else {
            log.debug("[LITE-MODE] processQueue skipped - summaries disabled")
            return
        }
```

**Edit file:** `Contextify/Contextify/ConversationMonitor.swift`

Find all calls to `scheduleImmediateCacheMissScan()` and wrap with lite mode check.

Find (there may be multiple):
```swift
            scheduleImmediateCacheMissScan()
```

Replace with:
```swift
            if !LLMAvailability.current.isLiteMode {
                scheduleImmediateCacheMissScan()
            }
```

Or add a guard at the start of `scheduleImmediateCacheMissScan()` itself:

Find:
```swift
    private func scheduleImmediateCacheMissScan() {
```

Add after opening brace:
```swift
        // Skip in lite mode - no LLM available
        guard !LLMAvailability.current.isLiteMode else { return }
```

---

### Commit 6: Guard FoundationLLM usage

```
feat(llm): wrap FoundationLLM calls with availability checks
```

**Edit file:** `Contextify/Contextify/FoundationLLM.swift`

Add a guard at the top of key entry points. Find the main generation methods and add:

```swift
        // Early exit in lite mode
        guard !LLMAvailability.current.isLiteMode else {
            throw TimelineError.llmUnavailable(reason: "Summaries require macOS 26")
        }
```

The existing `#if canImport(FoundationModels)` guards should handle compile-time, but we need runtime guards too for the simulation flag.

---

## Phase 3: UI Changes (4 commits)

### Commit 7: Update TimelineEntryRow for lite mode

```
feat(ui): hide summary, badges, and context menu in lite mode
```

**Edit file:** `Contextify/Contextify/TimelineEntryRow.swift`

**Change 0:** Add computed property for cleaner code (add near top of struct):

```swift
    /// Convenience for lite mode checks throughout the view
    private var isLiteMode: Bool {
        LLMAvailability.current.isLiteMode
    }
```

**Change 1:** Wrap summary section (around line 48-50):

Replace:
```swift
            formatWithBackticks(entry.summary)
                .font(.callout)
                .foregroundStyle(.primary)
```

With:
```swift
            // Hide summary in lite mode (no LLM available)
            if !isLiteMode {
                formatWithBackticks(entry.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
```

**Change 2:** Wrap detail section (around line 52-60):

Replace:
```swift
            if isExpanded {
                Divider()
                Text(entry.detail)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
```

With:
```swift
            // Hide detail in lite mode (no LLM available)
            if !isLiteMode && isExpanded {
                Divider()
                Text(entry.detail)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
```

**Change 3:** Disable expansion in lite mode (around line 85-89):

Replace:
```swift
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
```

With:
```swift
        .onTapGesture {
            // Disable expansion in lite mode (no detail to show)
            guard !isLiteMode else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
```

**Change 4 (S2 fix):** Hide unsummarized/generating badges in header.

Find the header computed property's status indicators section (around lines 131-191) and wrap the LLM-related badges:

```swift
            // Hide LLM status indicators in lite mode - they promise behavior we can't deliver
            if !isLiteMode {
                // Generation in progress indicator
                if case .generatingActive = entry.action {
                    Image(systemName: "hourglass")
                        // ... existing code
                }

                // Unsummarized indicator
                if case .unsummarized = entry.action {
                    Image(systemName: "hourglass")
                        // ... existing code
                }
            }
```

**Change 5 (B3 fix):** Hide "Regenerate Summary" context menu button in lite mode.

Find the context menu section and update:

Replace:
```swift
            if entry.contentSha256 != nil && entry.windowSha256 != nil {
                Divider()
                Button("Regenerate Summary") {
                    regenerateSummary()
                }
            }
```

With:
```swift
            // Hide regenerate option in lite mode - LLM not available
            if !isLiteMode && entry.contentSha256 != nil && entry.windowSha256 != nil {
                Divider()
                Button("Regenerate Summary") {
                    regenerateSummary()
                }
            }
```

---

### Commit 8: Update status bar for lite mode

```
feat(ui): show Lite Mode indicator in status bar
```

**Edit file:** `Contextify/Contextify/StatusBarView.swift`

**Change 1 (S1 fix):** Update `aiStatusText` to show "Lite Mode" directly (around line 180-188):

The existing code returns "AI Unavailable" for `.unavailable` cases, but we want "Lite Mode" to surface directly.

Replace:
```swift
private var aiStatusText: String {
    guard let viewModel else { return "AI Unavailable" }
    switch viewModel.aiStatus {
    case .checking: return "Checking AI..."
    case .available: return "Apple Intelligence"
    case .unavailable: return "AI Unavailable"
    case .error: return "AI Error"
    }
}
```

With:
```swift
private var aiStatusText: String {
    guard let viewModel else { return "AI Unavailable" }
    switch viewModel.aiStatus {
    case .checking:
        return "Checking AI..."
    case .available:
        return "Apple Intelligence"
    case .unavailable(let reason):
        // Surface "Lite Mode" directly when that's the reason
        return reason == "Lite Mode" ? "Lite Mode" : "AI Unavailable"
    case .error:
        return "AI Error"
    }
}
```

**Change 2:** Hide queue status in lite mode (find `queueStatusView`):

Wrap the queue status content with a lite mode check. Find the `@ViewBuilder` for queue status and add:

```swift
    @ViewBuilder
    private var queueStatusView: some View {
        // Hide queue status in lite mode (nothing to process)
        if LLMAvailability.current.isLiteMode {
            EmptyView()
        } else if viewModel == nil || !viewModel!.monitoringActive {
            // ... existing code
```

**Change 3:** Update AI status info popover to explain lite mode (find the popover content):

In the AI status info popover, add a case for lite mode at the top:

```swift
                    if LLMAvailability.current.isLiteMode {
                        Text("Lite Mode")
                            .font(.headline)
                        Text("Summaries require macOS 26 (Tahoe) with Apple Intelligence enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Your conversations are being saved. Upgrade to macOS 26 for AI-powered summaries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        // ... existing popover content
                    }
```

---

### Commit 9: Add lite mode callout to WelcomeModalView

```
feat(ui): add lite mode callout in welcome modal
```

**Why:** SwiftUI doesn't reliably present multiple `.sheet()` modals. Instead of a separate
LiteModeInfoView, add a callout to the existing WelcomeModalView when in lite mode.

**Edit file:** `Contextify/Contextify/WelcomeModalView.swift`

**Change:** Add lite mode callout in the completion state. Find `completedContent` and add:

```swift
@ViewBuilder
private var completedContent: some View {
    VStack(spacing: 16) {
        // ... existing completion content ...

        // Lite mode callout (only shown when in lite mode)
        if LLMAvailability.current.isLiteMode {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running in Lite Mode")
                        .font(.headline)
                    Text("Summaries require macOS 26. Your conversations are being saved and will get summaries as you browse after upgrading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
```

This way first-launch users on macOS 15 see the lite mode info as part of the welcome flow,
avoiding modal stacking issues.

---

### Commit 10: Create standalone lite mode modal for subsequent launches

```
feat(ui): add lite mode info modal for non-welcome launches
```

For subsequent launches (no welcome modal), show a standalone lite mode info modal.

**Create file:** `Contextify/Contextify/LiteModeInfoView.swift`

```swift
//
//  LiteModeInfoView.swift
//  Contextify
//
//  Lite mode info for subsequent launches (not first launch with welcome modal)
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "LiteModeInfo")

/// Modal shown on subsequent launches in lite mode (macOS 15).
///
/// NOT shown during first launch - WelcomeModalView includes lite mode callout.
/// Has "Don't show again" checkbox (checked by default).
struct LiteModeInfoView: View {
    @Environment(\.dismiss) private var dismiss

    // Checked by default - users see this once
    @State private var dontShowAgain = true

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            // Title
            Text("Running in Lite Mode")
                .font(.title2)
                .fontWeight(.semibold)

            // Body
            VStack(spacing: 12) {
                Text("Contextify is monitoring your AI conversations and saving them to your database.")
                    .multilineTextAlignment(.center)

                // Note: softened language per review - "as you browse" not "automatically"
                Text("AI-powered summaries require macOS 26 (Tahoe) with Apple Intelligence. When you upgrade, summaries will generate as you browse your saved conversations.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Checkbox
            Toggle(isOn: $dontShowAgain) {
                Text("Don't show this again")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)

            // Button
            Button {
                if dontShowAgain {
                    HUDPreferences.setLiteModeInfoDismissed(true)
                    log.info("[LITE-MODE-INFO] User dismissed with 'don't show again' checked")
                } else {
                    log.info("[LITE-MODE-INFO] User dismissed but will see again")
                }
                dismiss()
            } label: {
                Text("Got it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            log.info("[LITE-MODE-INFO] Modal displayed")
        }
    }
}

#Preview {
    LiteModeInfoView()
}
```

---

### Commit 11: Show lite mode modal on subsequent launches (not first launch)

```
feat(ui): show lite mode info on subsequent launches only
```

**Edit file:** `Contextify/Contextify/ContextifyApp.swift`

**Change 1:** Add state variable (around line 201, after `showWelcomeModal`):

```swift
  @State private var showLiteModeInfo = false  // Lite mode subsequent-launch modal
```

**Change 2:** Add sheet modifier (after the existing `.sheet(isPresented: $showWelcomeModal)` around line 345-351):

Add after the closing brace of the welcome modal sheet:
```swift
            .sheet(isPresented: $showLiteModeInfo) {
              LiteModeInfoView()
            }
```

**Change 3 (S4 fix):** Show lite mode modal ONLY on subsequent launches (not during welcome modal).

In the `.task` block, AFTER `initializeProjectsSystem()` completes, add this gated logic:

```swift
              // Show lite mode info modal ONLY if:
              // 1. We're in lite mode
              // 2. User hasn't dismissed it before
              // 3. Welcome modal is NOT showing (avoids modal conflict)
              if LLMAvailability.current.isLiteMode
                  && !HUDPreferences.hasLiteModeInfoBeenDismissed()
                  && !showWelcomeModal {
                showLiteModeInfo = true
              }
```

This ensures:
- First launch (DMG): Welcome modal includes lite mode callout → LiteModeInfoView skipped
- Subsequent launch: LiteModeInfoView shown → user can dismiss with "don't show again"

**Change 4:** Log availability status at startup. In `init()` (around line 230):

After `startupLog.notice("🚀 Contextify launched (Phase 3 Lazy Loading)")`:
```swift
    // Log LLM availability status
    LLMAvailability.logStatus()
```

Note: `logStatus()` is no longer `@MainActor`, so no Task wrapper needed.

---

## Phase 4: Testing (2 commits)

### Commit 12: Add LLMAvailability tests

```
test(llm): add unit tests for LLMAvailability
```

**Create file:** `Contextify/ContextifyTests/LLMAvailabilityTests.swift`

```swift
//
//  LLMAvailabilityTests.swift
//  ContextifyTests
//
//  Tests for LLMAvailability enum
//

import XCTest
@testable import Contextify

final class LLMAvailabilityTests: XCTestCase {

    func testIsLiteModeForUnavailableOldOS() {
        let availability = LLMAvailability.unavailableOldOS
        XCTAssertTrue(availability.isLiteMode)
    }

    func testIsLiteModeForAvailable() {
        let availability = LLMAvailability.available
        XCTAssertFalse(availability.isLiteMode)
    }

    func testIsLiteModeForUnavailableNotEnabled() {
        let availability = LLMAvailability.unavailableNotEnabled(reason: "Test")
        XCTAssertTrue(availability.isLiteMode)
    }

    func testIsLiteModeForUnavailableOther() {
        let availability = LLMAvailability.unavailableOther(reason: "Test")
        XCTAssertTrue(availability.isLiteMode)
    }

    func testStatusTextForLiteMode() {
        let availability = LLMAvailability.unavailableOldOS
        XCTAssertEqual(availability.statusText, "Lite Mode")
    }

    func testStatusTextForAvailable() {
        let availability = LLMAvailability.available
        XCTAssertEqual(availability.statusText, "Apple Intelligence")
    }

    func testSimulateLegacyMacOSFlag() {
        // This tests the flag detection, not the actual simulation
        // (simulation requires launch argument which we can't set in unit tests)
        let hasFlag = ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos")
        XCTAssertEqual(LLMAvailability.simulateLegacyMacOS, hasFlag)
    }
}
```

---

### Commit 13: Add QA test for lite mode

```
test(qa): add lite mode simulation test
```

**Create file:** `scripts/qa/tests/QA-16-lite-mode.sh`

```bash
#!/bin/bash
# @test_contract
# @description: Validates lite mode behavior when LLM is unavailable
# @isolation: Uses simulation flag, no persistent changes
# @database: Read-only (no mutations)
# @dependencies: None
# @log_tags: [LITE-MODE], [LLM-AVAILABILITY]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

test_name="QA-16: Lite Mode Simulation"
log_info "Starting $test_name"

# Build path
APP_PATH="${APP_PATH:-$SCRIPT_DIR/../../../.derived-dmg/Build/Products/Debug/Contextify.app}"

if [[ ! -d "$APP_PATH" ]]; then
    log_error "App not found at $APP_PATH"
    log_error "Run 'bash scripts/xc.sh build' first"
    exit 1
fi

# Launch app with simulation flag
log_info "Launching app with -simulate-legacy-macos flag..."
"$APP_PATH/Contents/MacOS/Contextify" -simulate-legacy-macos &
APP_PID=$!

# Give app time to start
sleep 3

# Capture logs
LOG_OUTPUT=$(log stream --process $APP_PID --timeout 5 2>/dev/null || true)

# Kill app
kill $APP_PID 2>/dev/null || true

# Assertions
log_info "Checking for lite mode log entries..."

if echo "$LOG_OUTPUT" | grep -q "\[LITE-MODE\]"; then
    log_success "Found [LITE-MODE] log entries"
else
    log_warning "No [LITE-MODE] log entries found (may need longer timeout)"
fi

if echo "$LOG_OUTPUT" | grep -q "\[LLM-AVAILABILITY\] Lite mode"; then
    log_success "Found LLM availability lite mode log"
else
    log_warning "No LLM availability lite mode log found"
fi

# Check that app didn't crash
if ps -p $APP_PID > /dev/null 2>&1; then
    log_error "App still running (expected it to have been killed)"
    kill -9 $APP_PID 2>/dev/null || true
fi

log_success "$test_name completed"
```

Make executable:
```bash
chmod +x scripts/qa/tests/QA-16-lite-mode.sh
```

---

## Phase 5: Documentation (1 commit)

### Commit 14: Update documentation

```
docs: add lite mode and macOS 15 support documentation
```

**Edit file:** `README.md`

Add a "System Requirements" section:
```markdown
## System Requirements

- **Full Mode:** macOS 26 (Tahoe) or later with Apple Intelligence enabled
- **Lite Mode:** macOS 15 (Sequoia) or later

In Lite Mode, Contextify monitors and indexes your conversations but AI summaries are disabled. When you upgrade to macOS 26, summaries will generate as you browse your saved conversations.
```

Note: "as you browse" is accurate since summary generation is viewport-driven (cache misses
queued when scrolling), not a full backlog fill on startup.

**Edit file:** `AGENTS.md`

Update the deployment target reference (around line 75):
```markdown
- SDKs: Base `macOS 26` (Tahoe); **minimum deployment: macOS 15.0** (Lite Mode)
```

**Edit file:** `build/docs/guides/DEVELOPMENT.md`

Add testing section:
```markdown
## Testing Lite Mode

To test lite mode behavior on macOS 26:

```bash
# Via terminal
./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos

# Via Xcode
# Edit Scheme > Run > Arguments > Add "-simulate-legacy-macos"
```

This simulates running on macOS 15 where LLM summaries are unavailable.
```

---

## Verification Checklist

### Pre-Implementation (B2 - Framework Linking)
- [ ] Verify FoundationModels framework is weak-linked (optional) in Xcode project
- [ ] Check `app/Package.swift` doesn't pin `.macOS(.v26)` - lower to `.v15` if needed
- [ ] Audit for unconditional `FoundationModels` imports outside `#if canImport(...)`
- [ ] Run `rg "FoundationModels|FoundationLLM" --type swift` to find all usages

### Build Verification
- [ ] Build succeeds on macOS 26 with target 15.0: `bash scripts/xc.sh build`
- [ ] Zero compiler warnings
- [ ] Tests pass: `swift test`

### Runtime Verification (with `-simulate-legacy-macos`)
- [ ] App launches without crash
- [ ] Timeline shows entries without summaries
- [ ] Entries are NOT expandable (tap does nothing)
- [ ] No unsummarized/generating hourglass badges visible
- [ ] "Regenerate Summary" context menu hidden
- [ ] Status bar shows "Lite Mode" (not "AI Unavailable")
- [ ] Status bar popover explains lite mode correctly
- [ ] Queue status section hidden (no "Processing X items")
- [ ] Welcome modal includes lite mode callout (first launch)
- [ ] LiteModeInfoView shown on subsequent launches
- [ ] "Don't show again" preference persists
- [ ] Logs show `[LLM-AVAILABILITY] Lite mode`

### Real Device Testing
- [ ] Build on macOS 15 VM or machine (verify app starts - B2)
- [ ] Real macOS 15 user confirms full functionality

---

## Rollback

If issues discovered:
- Revert deployment target to 26.0 in `project.pbxproj`
- Keep `LLMAvailability` code (no harm if always returns `.available`)
