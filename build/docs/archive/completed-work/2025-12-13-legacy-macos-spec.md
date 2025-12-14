---
todo_id: LEGACY-MACOS
title: Legacy macOS Support Spec
type: spec
date: 2025-12-12
status: draft
description: Lite-mode approach for macOS 15+ without Apple Intelligence summaries
---

# Feature: Legacy macOS Support (macOS 14/15)

## Problem Statement

Current app requires macOS 26 (Tahoe) because Apple Intelligence powers LLM summaries. This excludes users on older macOS who could benefit from:
- Timeline monitoring
- Transcript indexing
- Project organization
- Search (when implemented)

**User validation:** u/quinncom (r/MacApps, 2025-12-10): "I would be fine without summarization. My main use case would be to search for previous coding sessions by keyword, tag, or directory path."

**Growth strategy:** Let users on older macOS "bank" conversation history now. When they upgrade to Tahoe, summaries auto-generate for existing transcripts.

## Proposed Solution

**Lite Mode:** Lower deployment target to macOS 15, detect Apple Intelligence availability at runtime, show timeline without summaries on older macOS, display one-time upgrade info.

This approach:
- Maximizes user reach with minimal code changes
- Leverages existing `#if canImport(FoundationModels)` guards
- Provides clear upgrade path messaging
- Summaries auto-generate when user upgrades (existing queue picks up unsummarized entries)

## User Experience

### On macOS 26+ (Full Mode)
No change from current behavior.

### On macOS 15 (Lite Mode)

1. **Timeline view:**
   - Shows entries without summaries - no summary area at all
   - Entries show: timestamp, kind icon, source info
   - Entries are not expandable (no detail to show)
   - Cleaner/simpler UI since summaries don't exist in this mode

2. **Status bar:**
   - Shows "Lite Mode" instead of LLM health status
   - No queue progress (nothing to process)

3. **Settings:**
   - LLM-related settings hidden or disabled with explanation
   - Database settings, project selection, appearance all work normally

4. **First launch:**
   - One-time modal explaining Lite Mode
   - "Your conversations are being saved. Upgrade to macOS 26 for AI-powered summaries."
   - Checkbox: "Don't show again" - **checked by default** (users see modal once unless they uncheck)

### Keyboard Shortcuts
No changes - all existing shortcuts work.

## Technical Design

### Components Affected

**Must modify:**
- [ ] `Contextify.xcodeproj` - Lower MACOSX_DEPLOYMENT_TARGET from 26.0 to 15.0
- [ ] New: `LLMAvailability.swift` - Centralized availability enum with simulation support
- [ ] `LLMHealthCheck.swift` - Already has `@available(macOS 26, *)`, wrap with LLMAvailability
- [ ] `FoundationLLM.swift` - Already has guards, wrap with LLMAvailability
- [ ] `TimelineEntryRow.swift` - Hide summary area and disable expansion in lite mode
- [ ] `TimelineCacheMissGenerator.swift` - Skip queue entirely in lite mode
- [ ] `ConversationMonitor.swift` - Skip LLM triggers in lite mode
- [ ] `HUDStatusBar.swift` or `StatusBarViewModel.swift` - Show "Lite Mode" indicator
- [ ] `SettingsView.swift` - Hide/disable LLM settings
- [ ] New: `LiteModeInfoView.swift` - First-launch modal

**May need review:**
- [ ] `TranscriptMetadataOrchestrator.swift` - Ensure non-LLM paths work
- [ ] `AppDelegate.swift` - Availability checks at startup
- [ ] `SynthesisService.swift` - Availability guards if used directly

**No changes expected:**
- Database layer (GRDB is pure Swift, no macOS 26 dependencies)
- Transcript parsing (file I/O only)
- Project discovery/switching
- Search functionality (when implemented)

### Data Model Changes

**Schema:** No changes. Current schema (v28) uses standard SQLite features.

**Behavior:**
- `summary` and `detail` columns remain nullable (already are)
- Entries on older macOS saved with NULL summaries
- When user upgrades, existing queue logic processes unsummarized entries

### Architecture Decisions

**Q: Why macOS 14 vs 15 as minimum?**
- macOS 14 (Sonoma): Broader reach, but may require more availability guards
- macOS 15 (Sequoia): Narrower reach, but Swift 6 async/await more stable
- **Recommendation:** Start with macOS 15, expand to 14 if low effort

**Q: Why not alternative LLM support (Ollama, OpenAI)?**
- Significant additional complexity (API keys, model selection, cost)
- User validation suggests core value is search/indexing, not summaries
- Can add later as separate feature (P4/P5)

**Q: Feature flag or build variant?**
- **Recommendation:** Single build with runtime detection
- Simpler distribution (one DMG, one App Store listing)
- No build matrix complexity

### Runtime Availability Pattern

```swift
// Wrapper for LLM availability check
enum LLMAvailability {
    case available
    case unavailableOldOS
    case unavailableNotEnabled
    case unavailableOther(String)

    static var current: LLMAvailability {
        guard #available(macOS 26, *) else {
            return .unavailableOldOS
        }
        // Existing LLMHealthCheck logic
        ...
    }

    var isLiteMode: Bool {
        if case .unavailableOldOS = self { return true }
        return false
    }
}
```

### UI Conditional Rendering

```swift
// TimelineEntryRow - hide summary entirely in lite mode
var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        header
        if !LLMAvailability.current.isLiteMode {
            // Only show summary in full mode
            formatWithBackticks(entry.summary)
                .font(.callout)
                .foregroundStyle(.primary)

            if isExpanded {
                Divider()
                Text(entry.detail)
                // ...
            }
        }
    }
    // ...
    .onTapGesture {
        // Only allow expansion in full mode
        guard !LLMAvailability.current.isLiteMode else { return }
        withAnimation { isExpanded.toggle() }
    }
}
```

## Test Requirements

### Unit Tests

- [ ] `LLMAvailabilityTests.swift` - Test availability detection logic
- [ ] `TimelineEntryTests.swift` - Verify entries work with NULL summaries
- [ ] `DatabaseSchemaTests.swift` - Confirm schema works on older SQLite (if different)

### E2E Tests

- [ ] New QA test: `QA-XX-lite-mode.sh`
  - Simulates older macOS (may require build flag or mock)
  - Verifies timeline displays without summaries
  - Verifies status bar shows lite mode indicator
  - Verifies settings disable LLM options

- [ ] Update existing QA tests:
  - Ensure tests don't assume summaries always exist
  - Add assertions for graceful degradation

**Log tags needed:**
- `[LITE-MODE-ACTIVE]` - Logged at startup if running in lite mode
- `[LLM-SKIPPED-OLD-OS]` - When LLM operations skipped due to OS version

### Manual Testing

- [ ] Build and run on macOS 15 VM/partition
- [ ] Build and run on macOS 14 VM/partition (if targeting)
- [ ] Verify project switching works
- [ ] Verify transcript monitoring works
- [ ] Verify database operations work
- [ ] Verify search works (when implemented)
- [ ] Verify upgrade messaging is clear

## Rollout Considerations

### Feature Flag
Not needed - runtime detection handles this.

### Migration Path
None required - existing users unaffected, new users on older macOS get lite mode automatically.

### Documentation Updates
- [ ] Update README with system requirements section
- [ ] Add "Lite Mode" section to help documentation
- [ ] Update website with requirements
- [ ] Update App Store description

### App Store Considerations
- Single listing supports both modes
- Update "What's New" to mention expanded OS support
- May need updated screenshots showing lite mode (optional)

## Testing Infrastructure

### Simulation Flag for Development

Add launch argument to simulate lite mode on macOS 26 for testing:

```swift
// In AppEnvironment or similar
enum AppEnvironment {
    /// Launch with: -simulate-legacy-macos
    static var simulateLegacyMacOS: Bool {
        ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos")
    }
}

// In LLMAvailability
static var current: LLMAvailability {
    if AppEnvironment.simulateLegacyMacOS {
        return .unavailableOldOS
    }
    guard #available(macOS 26, *) else {
        return .unavailableOldOS
    }
    // ... existing checks
}
```

**Usage:**
- Xcode: Edit Scheme > Run > Arguments > Add `-simulate-legacy-macos`
- Terminal: `./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos`
- QA tests: Pass flag in test harness

### Real Device Testing

Two users (u/quinncom and one other) have expressed interest and are on macOS 15. They can test the actual release build on real hardware.

## Open Questions

- [x] **macOS 14 vs 15 minimum?** → macOS 15
- [x] **Lite mode first-launch modal?** → Yes, with "Don't show again" checked by default
- [x] **Summary placeholder?** → No placeholder, no summary area at all
- [x] **Test infrastructure?** → Simulation flag + real user testing

## Implementation Plan

### Phase 1: Foundation (2-3 commits)
- [ ] Lower deployment target to macOS 15.0 in Xcode project
- [ ] Add `LLMAvailability` enum with `.isLiteMode` property
- [ ] Add `-simulate-legacy-macos` launch argument support
- [ ] Verify build succeeds with new target

### Phase 2: Runtime Guards (2-3 commits)
- [ ] Wrap `LLMHealthCheck` usage with availability checks
- [ ] Wrap `FoundationLLM` usage with availability checks
- [ ] Wrap `TimelineCacheMissGenerator` - skip queue entirely in lite mode
- [ ] Wrap synthesis/summarization triggers

### Phase 3: UI Changes (3-4 commits)
- [ ] Update `TimelineEntryRow` - hide summary area, disable expansion in lite mode
- [ ] Update status bar - show "Lite Mode" indicator
- [ ] Update settings - hide/disable LLM options
- [ ] Add first-launch modal with "Don't show again" (checked by default)

### Phase 4: Testing (1-2 commits)
- [ ] Add unit tests for `LLMAvailability` detection
- [ ] Test with `-simulate-legacy-macos` flag
- [ ] Coordinate testing with macOS 15 users

### Phase 5: Documentation (1 commit)
- [ ] Update README with system requirements
- [ ] Update website requirements
- [ ] Update App Store description
