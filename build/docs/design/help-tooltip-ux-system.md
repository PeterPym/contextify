# Help & Tooltip UX System
## Contextify macOS Application

**Status:** Design Proposal
**Date:** 2024-11-04
**Reference:** Apple HIG - Offering Help, Popovers, macOS Design Guidelines

---

## Executive Summary

This document establishes a comprehensive, tiered help system for Contextify that follows Apple's Human Interface Guidelines. The system uses three distinct interaction patterns based on content type and user needs, avoiding over-reliance on any single pattern.

### Key Principles

1. **Progressive Disclosure:** Show help only when needed, in order of increasing detail
2. **Visual Consistency:** Use established macOS patterns and conventions
3. **Non-Intrusive:** Help should be discoverable but not distracting
4. **Context-Appropriate:** Match the help type to the UI element and situation

---

## Three-Tier Help System

### Tier 1: Standard Tooltips (`.help()`)
**Apple Pattern:** System-standard hover tooltips
**Cursor:** Default pointer (no change)
**Timing:** Appears after ~0.5s hover delay (system-controlled)
**Styling:** System default (yellow background, system font, auto-sizing)

**When to Use:**
- Brief labels for icon-only buttons
- Clarification of terse UI elements
- Keyboard shortcuts
- Simple state descriptions

**When NOT to Use:**
- Complex multi-line explanations
- Error details or recovery instructions
- Interactive content
- Content that changes frequently

**Current Usage in Contextify:** 26 instances across the app

---

### Tier 2: Info Popovers (Explicit Trigger)
**Apple Pattern:** Click/tap to reveal detailed information
**Cursor:** Default pointer OR `NSCursor.contextualMenuCursor` (right-click menu cursor)
**Trigger:** Click on "info" button (ⓘ symbol)
**Styling:** Custom popover with Contextify design system

**When to Use:**
- Multi-line explanations
- Error details with recovery steps
- Feature discovery hints
- Configuration guidance
- "Why is this disabled?" explanations

**Visual Treatment:**
- **Icon:** SF Symbol `info.circle` or `info.circle.fill`
- **Size:** 14-16pt (caption to body size)
- **Color:** `.secondary` (default), `.blue` (interactive)
- **Hover State:** Scale to 1.1x, color change to `.blue`
- **Cursor:** `NSCursor.contextualMenuCursor` on hover (question mark style)

**Popover Styling:**
```swift
.popover(isPresented: $showInfo) {
    VStack(alignment: .leading, spacing: 12) {
        // Title (optional)
        Text("Title")
            .font(.headline)

        // Body content
        Text("Detailed explanation...")
            .font(.body)
            .foregroundStyle(.primary)

        // Actions (optional)
        HStack {
            Button("Learn More") { ... }
            Spacer()
            Button("Dismiss") { showInfo = false }
        }
    }
    .padding(16)
    .frame(maxWidth: 320)  // Constrain width
    .presentationCompactAdaptation(.popover)  // Always show as popover
}
```

**Popover Design:**
- **Max Width:** 320pt (readable line length)
- **Padding:** 16pt all sides
- **Background:** System window background with vibrancy
- **Border:** Subtle system border
- **Arrow:** Pointing to source element
- **Typography:** System fonts (headline for title, body for content)

---

### Tier 3: Rich Help Popovers (Automatic on Hover)
**Apple Pattern:** Hover-triggered rich content (TipKit-style)
**Cursor:** Default pointer (system handles hover)
**Timing:** Appears after ~1s hover delay (longer than Tier 1)
**Styling:** Custom popover matching Tier 2

**When to Use:**
- First-time user onboarding
- Complex status indicators (multi-dimensional state)
- Error states requiring user action
- Feature announcements

**Implementation:** Use `.popover()` with `isPresented` bound to hover state with delay

**Constraints:**
- **Use Sparingly:** Maximum 2-3 in any single view
- **Dismissible:** Always provide clear close affordance
- **Once Per Session:** For onboarding, show once per app launch
- **Escape Hatch:** Respect system preference to disable tips

---

## Cursor Behavior Guidelines

### Standard Approach (Recommended)
**Default pointer throughout** - Let the interaction pattern (button vs automatic hover) communicate affordance.

### Enhanced Approach (Optional)
Use `NSCursor.contextualMenuCursor` (question mark pointer) **only for Tier 2 info buttons**.

**Rationale:**
- Question mark cursor is typically associated with help/info buttons in macOS
- Using it consistently for Tier 2 creates learnable pattern
- Avoids confusion with system help cursor (macOS Help menu uses different pattern)

**Implementation:**
```swift
.onHover { isHovering in
    if isHovering {
        NSCursor.contextualMenuCursor.push()
    } else {
        NSCursor.pop()
    }
}
```

**Important:** Test cursor behavior with VoiceOver to ensure accessibility isn't compromised.

---

## UI Audit & Recommendations

### Current State Analysis

**Tier 1 (`.help()`) - 26 instances found:**

| Location | Element | Current Tooltip | Status | Recommendation |
|----------|---------|----------------|--------|----------------|
| **StatusBarView.swift** |
| Line 109 | AI Status Indicator | Multi-line error details | ⚠️ Too complex | **Upgrade to Tier 2** |
| Line 174 | "Not monitoring" label | "Start a project to enable..." | ✅ Good | Keep as-is |
| Line 189 | Error count badge | Multi-line error + recovery steps | ⚠️ Too complex | **Upgrade to Tier 2** |
| **ConversationTimelineView.swift** |
| Line 36 | Retry button | "Timeline fetch failed. Retry now." | ✅ Good | Keep as-is |
| Line 72 | Project manager button | "Manage Projects" | ✅ Good | Keep as-is |
| Line 83 | Transcript inventory | "Show All Transcripts (N)" | ✅ Good | Keep as-is |
| Line 112 | Collapse toggle | "Expand/Compact timeline" | ✅ Good | Keep as-is |
| **TimelineEntryRow.swift** |
| Line 96 | Pending summary icon | "Summary not yet generated" | ✅ Good | Keep as-is |
| Line 102 | No summary icon | "No summary available..." | 🤔 Could improve | Add info button for "why?" |
| Line 129 | Jump to request link | "Jump to original request" | ✅ Good | Keep as-is |
| Line 139 | Reveal in inventory | "Reveal in transcript inventory" | ✅ Good | Keep as-is |
| **ProjectRowView.swift** |
| Line 38 | Error indicator | "Ingestion error: [details]" | ⚠️ Could be complex | Review error messages |
| Line 74 | Follow mode chip | "Configure active session following" | 🤔 Terse | Add info button explaining modes |
| Line 154 | Stats button | "View Statistics" | ✅ Good | Keep as-is |
| **ProjectSwitcherView.swift** |
| Line 364 | Missing directory warning | "Project directory is missing" | 🤔 Could improve | Add info button with recovery steps |
| **TranscriptInventoryView.swift** |
| Line 118 | Developer cleanup button | "Delete cached metadata..." | ✅ Good | Keep as-is |
| Line 135 | Orphan cleanup button | "Delete transcript records..." | ✅ Good | Keep as-is |
| Line 339 | Active session indicator | "Active session" | ✅ Good | Keep as-is |
| Line 351 | Pinned badge | "This session is pinned..." | ✅ Good | Keep as-is |
| Line 1006 | Auto-follow button | "Switch to automatic follow mode" | ✅ Good | Keep as-is |
| Line 1044 | Reveal in Finder | "Reveal in Finder" | ✅ Good | Keep as-is |
| **ProjectBadgesView.swift** |
| Line 15 | Provider badges | Provider display name | ✅ Good | Keep as-is |
| **ContentView.swift** (Developer mode) |
| Lines 114, 144, 152, 160, 168 | Test buttons | Various test labels | ✅ Good | Keep as-is (dev only) |

---

### Elements Needing Help (Currently Missing)

| Location | Element | Priority | Recommendation |
|----------|---------|----------|----------------|
| **StatusBarView** |
| AI Status Dot | Apple Intelligence availability indicator | **P0** | **Tier 2 info button** - Explain what Apple Intelligence does, system requirements, how to enable |
| Error Badge | Error count with recovery actions | **P0** | **Tier 2 info button** - Replace complex tooltip with clickable info revealing full error details + recovery steps |
| Queue Status | Processing state details | **P1** | **Tier 1 tooltip** - Brief explanation of what's being processed |
| **ProjectSwitcherView** |
| Project Icons | Folder icons in project list | **P2** | **Tier 1 tooltip** - Show full path on hover (if not already visible) |
| Provider Badges | Claude Code, Codex, etc. badges | **P2** | **Tier 1 tooltip** - Already implemented, but verify icon meaning is clear |
| Tab Reordering | Draggable project tabs | **P1** | **Tier 3 onboarding** - First-time hint: "Drag tabs to reorder projects" |
| **TranscriptInventoryView** |
| Session Icons | Icon indicators for session state | **P2** | **Tier 1 tooltip** - Explain icon meanings |
| Last Activity Time | Relative timestamps | **P3** | **Tier 1 tooltip** - Show absolute timestamp on hover |
| Entry Count | Number of conversation entries | **P3** | **Tier 1 tooltip** - "N conversation entries" |
| **ConversationTimelineView** |
| Empty State | When no entries exist | **P1** | **Tier 3 rich content** - Explain what will appear here once monitoring starts |
| Session Filter | Filter controls | **P2** | **Tier 2 info button** - Explain filtering options |
| **TimelineEntryRow** |
| Role Icons | User/Assistant/System indicators | **P1** | **Tier 1 tooltip** - Already clear from icon, but ensure consistency |
| Disposition Icons | Success/Error/Warning states | **P1** | **Tier 1 tooltip** - Brief state explanation |
| **SettingsView** |
| Database Location | Custom database path setting | **P0** | **Tier 2 info button** - Explain multi-machine conflicts, backup recommendations |
| Advanced Settings | Any complex configuration | **P1** | **Tier 2 info buttons** - Explain implications of each setting |

---

## Priority Implementation Roadmap

### Phase 1: Critical Fixes (P0)
**Goal:** Fix broken or insufficient help for key features

1. **StatusBarView - Error Badge Popover**
   - Replace complex tooltip with Tier 2 info button
   - Show detailed error messages with recovery steps
   - Include "Check System Settings" action button
   - **File:** `StatusBarView.swift:177-191`

2. **StatusBarView - AI Status Popover**
   - Add Tier 2 info button next to AI status indicator
   - Explain Apple Intelligence requirements
   - Link to System Settings
   - Show current LLM model info
   - **File:** `StatusBarView.swift:96-111`

3. **SettingsView - Database Location Help**
   - Add Tier 2 info button for custom database location
   - Warn about multi-machine sync issues
   - Explain backup implications
   - **File:** `SettingsView.swift` (location TBD)

**Estimated Effort:** 4-6 hours

---

### Phase 2: Usability Improvements (P1)
**Goal:** Add missing help for discoverable features

1. **ProjectRowView - Follow Mode Explanation**
   - Add info button explaining "Auto" vs "Pinned" modes
   - Show keyboard shortcuts if applicable
   - **File:** `ProjectRowView.swift:42-75`

2. **ProjectSwitcherView - Tab Reordering Hint**
   - Add Tier 3 onboarding tip on first use
   - Show once per app launch
   - Dismiss on first drag action
   - **File:** `ProjectSwitcherView.swift`

3. **ConversationTimelineView - Empty State Help**
   - Add Tier 3 rich help to empty state
   - Explain what will appear when monitoring starts
   - Link to "Start Project" action
   - **File:** `ConversationTimelineView.swift:141-143`

4. **ProjectSwitcherView - Missing Directory Recovery**
   - Convert simple tooltip to Tier 2 info button
   - Show recovery steps (relocate, remove, etc.)
   - **File:** `ProjectSwitcherView.swift:364`

**Estimated Effort:** 6-8 hours

---

### Phase 3: Polish & Consistency (P2-P3)
**Goal:** Comprehensive help coverage

1. **Audit and standardize all Tier 1 tooltips**
   - Ensure consistent voice and formatting
   - Verify 50 character limit for single-line tooltips
   - Remove redundant tooltips (icon + text already clear)

2. **Add tooltips to all icon-only buttons**
   - Timeline controls
   - Session management buttons
   - Provider badges (verify current implementation)

3. **Session metadata tooltips**
   - Relative time → absolute timestamp
   - Entry counts with details
   - Provider information

**Estimated Effort:** 4-6 hours

---

## Implementation Guide

### Creating Tier 2 Info Popovers

**Step 1: Add state variable**
```swift
@State private var showInfoPopover = false
```

**Step 2: Create info button**
```swift
Button {
    showInfoPopover = true
} label: {
    Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
        .imageScale(.small)
}
.buttonStyle(.plain)
.onHover { isHovering in
    if isHovering {
        NSCursor.contextualMenuCursor.push()
    } else {
        NSCursor.pop()
    }
}
.popover(isPresented: $showInfoPopover) {
    InfoPopoverContent()
}
```

**Step 3: Create reusable popover component**
```swift
struct InfoPopoverContent: View {
    let title: String
    let message: String
    let action: (() -> Void)?
    let actionLabel: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let action, let actionLabel {
                Divider()
                HStack {
                    Spacer()
                    Button(actionLabel, action: action)
                        .buttonStyle(.link)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .presentationCompactAdaptation(.popover)
    }
}
```

---

### Creating Tier 3 Hover Popovers

**Step 1: Add hover tracking**
```swift
@State private var isHovering = false
@State private var hoverTask: Task<Void, Never>?
@State private var showHoverPopover = false
```

**Step 2: Implement delayed hover**
```swift
.onHover { hovering in
    if hovering {
        // Start delayed show
        hoverTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                await MainActor.run {
                    showHoverPopover = true
                }
            }
        }
    } else {
        // Cancel and hide
        hoverTask?.cancel()
        hoverTask = nil
        showHoverPopover = false
    }
}
.popover(isPresented: $showHoverPopover) {
    RichHelpContent()
}
```

**Step 3: Add dismissal tracking**
```swift
@AppStorage("hasSeenFeatureHint") private var hasSeenHint = false

// In popover:
.onAppear {
    hasSeenHint = true
}
```

---

## Design System Integration

### Color Scheme
Use Contextify's established color palette:

- **Info Icon (Default):** `.secondary` - non-intrusive
- **Info Icon (Hover):** `Contextify Blue` (#4A7BA7) - interactive
- **Success States:** `Contextify Green` (#51A86B)
- **Error States:** `Contextify Red` (#C74E4E)
- **Warning States:** `Contextify Yellow` (#D4A84E)

### Typography
- **Popover Title:** `.headline` - clear hierarchy
- **Popover Body:** `.body` - readable
- **Tooltip Text:** System default - maintains OS consistency

### Spacing
- **Popover Padding:** 16pt all sides
- **Popover Max Width:** 320pt (62 characters at body size)
- **Info Button Spacing:** 4-6pt from adjacent elements
- **Info Button Size:** 44pt minimum tap target

### Animation
- **Popover Appearance:** System default (fade + scale)
- **Info Button Hover:** Scale 1.0 → 1.1 over 0.2s ease
- **Color Transition:** 0.2s ease for all color changes

---

## Accessibility Considerations

### VoiceOver Support
1. **All info buttons MUST have accessibility labels**
   ```swift
   .accessibilityLabel("More information about Apple Intelligence status")
   ```

2. **Popovers MUST be keyboard accessible**
   - Tab to info button, Space/Enter to open
   - Esc to dismiss
   - Focus trapping within popover

3. **Tooltips automatically support VoiceOver** - system handles it

### Keyboard Navigation
1. **All Tier 2 info buttons must be keyboard-accessible**
2. **Popover content must support keyboard navigation**
3. **Provide keyboard shortcuts for common help actions**

### Reduced Motion
1. **Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`**
2. **Disable scale animations for info buttons when reduced motion is on**
3. **Use simple fade transitions instead**

### Dynamic Type
1. **All popover text must support Dynamic Type**
2. **Test at largest accessibility sizes**
3. **Ensure popover width adapts to larger text**

---

## Testing Checklist

### Functional Testing
- [ ] All Tier 1 tooltips appear after ~0.5s hover
- [ ] All Tier 2 info buttons trigger popovers on click
- [ ] All Tier 3 hover popovers appear after ~1s hover
- [ ] Popovers dismiss on outside click, Esc key, and explicit close
- [ ] Cursor changes to question mark on Tier 2 info button hover
- [ ] All popovers constrained to screen bounds
- [ ] Popover arrows point to correct source element

### Accessibility Testing
- [ ] All info buttons have accessibility labels
- [ ] VoiceOver announces all tooltip content
- [ ] Keyboard navigation works for all popovers
- [ ] Focus is trapped within popovers
- [ ] Reduced motion preference respected
- [ ] Dynamic Type supported in all popovers

### Visual Testing
- [ ] Info icons use correct color (secondary → blue transition)
- [ ] Popovers use Contextify color scheme
- [ ] Typography hierarchy is clear
- [ ] Spacing follows design system
- [ ] Animations are smooth and purposeful

### Content Testing
- [ ] All help text uses plain language
- [ ] Error messages include recovery steps
- [ ] Technical jargon is explained or avoided
- [ ] Onboarding hints show once per session
- [ ] All help content is accurate and up-to-date

---

## Open Questions & Decisions Needed

1. **Cursor Behavior:** Use question mark cursor for Tier 2 info buttons, or keep default throughout?
   - **Recommendation:** Start with default, add question mark cursor only if user testing shows confusion

2. **Onboarding Tips:** Should Tier 3 onboarding tips use TipKit framework (macOS 13+) or custom implementation?
   - **Recommendation:** Custom implementation for consistency and control

3. **Help Center:** Should there be a centralized "Help" window or menu item that aggregates all help content?
   - **Recommendation:** Defer to Phase 4 - focus on contextual help first

4. **First-Time User Experience:** Should there be a guided tour or tutorial on first launch?
   - **Recommendation:** No - rely on contextual help and empty states

5. **Error Recovery:** Should error popovers include "Try Again" or "Report Bug" actions?
   - **Recommendation:** Yes - include actionable buttons where appropriate

---

## Success Metrics

### Qualitative
- Users can understand all interface elements without external documentation
- Error states provide clear recovery paths
- New users can complete core workflows without assistance

### Quantitative (Future)
- Reduction in support requests related to UI confusion
- Increase in feature discovery (measured by usage analytics)
- Decrease in time-to-first-success for new users

---

## References

### Apple Human Interface Guidelines
- **Offering Help:** https://developer.apple.com/design/human-interface-guidelines/offering-help
- **Popovers:** https://developer.apple.com/design/human-interface-guidelines/popovers
- **macOS Design Themes:** https://developer.apple.com/design/human-interface-guidelines/designing-for-macos

### SwiftUI Documentation
- **`.help()` Modifier:** System tooltips
- **`.popover()` Modifier:** Custom popovers
- **TipKit Framework:** Feature discovery (macOS 13+)

### WWDC Sessions (Recommended)
- **WWDC 2024:** "What's new in the Human Interface Guidelines"
- **WWDC 2023:** "Design with SwiftUI"
- **WWDC 2022:** "What's new in UIKit"

### Internal Documentation
- **Color Scheme:** `build/docs/design/color-scheme.md`
- **Component Library:** (TBD)

---

## Appendix A: Current Tooltip Inventory (Full List)

```
StatusBarView.swift:109 - AI Status indicator
StatusBarView.swift:174 - Not monitoring state
StatusBarView.swift:189 - Error badge
ConversationTimelineView.swift:36 - Retry button
ConversationTimelineView.swift:72 - Project manager button
ConversationTimelineView.swift:83 - Transcript inventory button
ConversationTimelineView.swift:112 - Collapse toggle
TimelineEntryRow.swift:96 - Pending summary
TimelineEntryRow.swift:102 - No summary available
TimelineEntryRow.swift:129 - Jump to request
TimelineEntryRow.swift:139 - Reveal in inventory
ProjectRowView.swift:38 - Ingestion error
ProjectRowView.swift:74 - Follow mode configuration
ProjectRowView.swift:154 - View statistics
ProjectSwitcherView.swift:364 - Missing directory
ContentView.swift:114 - Open project (dev mode)
ContentView.swift:144 - Test embedding service (dev mode)
ContentView.swift:152 - Test embedding database (dev mode)
ContentView.swift:160 - Batch embedding (dev mode)
ContentView.swift:168 - Semantic search (dev mode)
TranscriptInventoryView.swift:118 - Delete cached metadata (dev mode)
TranscriptInventoryView.swift:135 - Delete orphaned transcripts (dev mode)
TranscriptInventoryView.swift:339 - Active session indicator
TranscriptInventoryView.swift:351 - Pinned session badge
TranscriptInventoryView.swift:1006 - Auto-follow mode
TranscriptInventoryView.swift:1044 - Reveal in Finder
ProjectBadgesView.swift:15 - Provider badge names
```

**Total: 27 tooltips** (26 user-facing + 1 developer-only)

---

## Appendix B: Example Implementations

### Example 1: Status Bar Error Popover (P0)

**Before:**
```swift
.help(errorTooltip(count: viewModel.recentErrorCount, reason: viewModel.topErrorReason))
```

**After:**
```swift
HStack(spacing: 4) {
    Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color.contextifyYellow)
        .font(.caption)

    Text("\(viewModel.recentErrorCount) error\(viewModel.recentErrorCount == 1 ? "" : "s")")
        .font(.caption)
        .foregroundStyle(.secondary)

    Button {
        showErrorPopover = true
    } label: {
        Image(systemName: "info.circle")
            .foregroundStyle(hoveringErrorInfo ? .blue : .secondary)
            .font(.caption)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
        hoveringErrorInfo = hovering
        if hovering {
            NSCursor.contextualMenuCursor.push()
        } else {
            NSCursor.pop()
        }
    }
    .popover(isPresented: $showErrorPopover) {
        ErrorDetailsPopover(
            errorCount: viewModel.recentErrorCount,
            topError: viewModel.topErrorReason
        )
    }
}
.help("LLM generation errors occurred. Click info for details.")
```

### Example 2: AI Status Info Popover (P0)

**Before:**
```swift
aiStatusIndicator
    .help(aiStatusTooltip)  // Multi-line, complex
```

**After:**
```swift
HStack(spacing: 4) {
    aiStatusIndicator
        .help(aiStatusText)  // Simple one-liner

    Button {
        showAIInfoPopover = true
    } label: {
        Image(systemName: "info.circle")
            .foregroundStyle(hoveringAIInfo ? .blue : .secondary)
            .font(.caption)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
        hoveringAIInfo = hovering
        if hovering {
            NSCursor.contextualMenuCursor.push()
        } else {
            NSCursor.pop()
        }
    }
    .popover(isPresented: $showAIInfoPopover) {
        AIStatusInfoPopover(status: viewModel.aiStatus)
    }
}
```

### Example 3: Reusable InfoPopover Component

```swift
/// Reusable info popover component following Contextify design system
struct InfoPopover: View {
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            // Message
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Optional action button
            if let actionLabel, let action {
                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Spacer()
                    Button(actionLabel) {
                        action()
                        dismiss()
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.regularMaterial)
        .presentationCompactAdaptation(.popover)
    }
}

// Usage:
.popover(isPresented: $showInfo) {
    InfoPopover(
        title: "Apple Intelligence",
        message: "Contextify uses Apple's on-device language models to generate conversation summaries. Apple Intelligence must be enabled in System Settings > Apple Intelligence & Siri.",
        actionLabel: "Open System Settings",
        action: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
        }
    )
}
```

### Example 4: Hover Tooltip with Delay (Tier 3)

```swift
struct FeatureHintModifier: ViewModifier {
    let message: String
    let delay: TimeInterval
    @AppStorage var hasSeenHint: Bool

    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

    init(message: String, delay: TimeInterval = 1.0, storageKey: String) {
        self.message = message
        self.delay = delay
        self._hasSeenHint = AppStorage(wrappedValue: false, storageKey)
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering && !hasSeenHint {
                    hoverTask = Task {
                        try? await Task.sleep(for: .seconds(delay))
                        if !Task.isCancelled {
                            await MainActor.run {
                                showPopover = true
                            }
                        }
                    }
                } else {
                    hoverTask?.cancel()
                    hoverTask = nil
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Tip")
                            .font(.headline)
                        Spacer()
                        Button {
                            showPopover = false
                            hasSeenHint = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
                .onAppear {
                    hasSeenHint = true
                }
            }
    }
}

extension View {
    func featureHint(_ message: String, storageKey: String, delay: TimeInterval = 1.0) -> some View {
        modifier(FeatureHintModifier(message: message, delay: delay, storageKey: storageKey))
    }
}

// Usage:
ProjectTabView()
    .featureHint(
        "Drag tabs to reorder your projects",
        storageKey: "hasSeenProjectTabReorderHint"
    )
```

---

## Appendix C: Glossary

**Tooltip** - System-standard hover text (Tier 1), appears after brief delay
**Popover** - Floating window anchored to source element, manually or automatically triggered
**Info Button** - Clickable ⓘ icon that reveals detailed help in a popover
**Hover Popover** - Automatically triggered popover after longer hover delay (Tier 3)
**TipKit** - Apple's framework for feature discovery hints (macOS 13+)
**Progressive Disclosure** - Design pattern showing information in layers of increasing detail
**Affordance** - Visual cue that suggests how an element can be interacted with
**Hit Target** - Minimum touchable/clickable area (44pt × 44pt for accessibility)

---

**End of Document**
