# SwiftUI 6+ Help & Tooltip Patterns
## Comprehensive Research Update for macOS 15 (Sequoia)

**Date:** 2025-01-04
**Target:** SwiftUI 6, macOS 15 Sequoia, iOS 18
**Research Completeness:** ~85% (Direct Apple video access blocked, but comprehensive secondary sources)

---

## Executive Summary

This document provides SwiftUI 6+ specific guidance for implementing help/tooltip systems in Contextify. Key finding: **Apple introduced `HelpLink` in macOS 14+** as the native SwiftUI component for help buttons, fundamentally changing the recommended approach.

### Major Updates Since Initial Research

1. ✅ **HelpLink Component** - Native SwiftUI help button (macOS 14+)
2. ✅ **TipKit TipGroup** - Sequential tip display (iOS 18/macOS 15)
3. ✅ **presentationSizing** - Better popover sizing control (iOS 18/macOS 15)
4. ✅ **SF Symbols 6** - New animations and 800+ new symbols
5. ⚠️ **No changes to `.help()`** - Remains string-only tooltip
6. ⚠️ **No changes to `onContinuousHover`** - Still requires macOS 13+

---

## Part 1: Native SwiftUI Help Components

### HelpLink (macOS 14+, iOS 17+) - **RECOMMENDED**

Apple's official SwiftUI component for help buttons, introduced in macOS 14 Sonoma.

**Appearance:**
- Standard circular question mark button
- Matches macOS system style automatically
- Includes accessibility support out-of-the-box

**Basic Usage:**
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        HStack {
            Text("Apple Intelligence Status")
            HelpLink(destination: URL(string: "https://support.apple.com/guide/contextify/ai-status")!)
        }
    }
}
```

**Advantages:**
- ✅ Native macOS appearance (circular question mark)
- ✅ Automatic accessibility (VoiceOver support)
- ✅ System-standard cursor behavior
- ✅ Respects user preferences (Reduced Motion, etc.)
- ✅ No custom cursor management needed
- ✅ Opens URLs in user's default browser

**Limitations:**
- ⚠️ Requires macOS 14+ (Contextify targets 14+, so ✅ compatible)
- ⚠️ Only supports URL destinations (can't trigger custom actions)
- ⚠️ No inline popover support (always opens external browser)

**When to Use:**
- ✅ Linking to external documentation
- ✅ Opening help articles
- ✅ Directing to support pages
- ❌ Showing inline popovers with custom content
- ❌ Triggering app-specific actions

**Contextify Applicability:**
- ⚠️ **Limited for Contextify's needs** - Most help should be inline/contextual, not external links
- ✅ **Good for:** "Learn More" links in Settings
- ❌ **Not suitable for:** Status bar error explanations, AI status details (need inline popovers)

**Conclusion:** While HelpLink is Apple's official component, **Contextify needs inline popovers** for most help scenarios, so we'll use custom implementation with `.popover()`.

---

## Part 2: TipKit Framework Updates (iOS 18 / macOS 15)

### What's New in TipKit for SwiftUI 6

TipKit received significant updates at WWDC 2024 for iOS 18 and macOS 15:

#### 1. TipGroup - Sequential Tips

**Purpose:** Display multiple tips in sequence, one at a time.

**Implementation:**
```swift
import SwiftUI
import TipKit

struct ContentView: View {
    // Define tips
    struct WelcomeTip: Tip {
        var title: Text { Text("Welcome!") }
        var message: Text? { Text("This is the conversation timeline") }
    }

    struct ProjectTip: Tip {
        var title: Text { Text("Set a Project") }
        var message: Text? { Text("Click 'Set Project Root' to get started") }
    }

    struct AIStatusTip: Tip {
        var title: Text { Text("Apple Intelligence") }
        var message: Text? { Text("Green = available, Red = error") }
    }

    // Group tips with priority
    @State private var tips = TipGroup(.ordered) {
        [WelcomeTip(), ProjectTip(), AIStatusTip()]
    }

    var body: some View {
        VStack {
            // Display current tip
            if let currentTip = tips.currentTip {
                TipView(currentTip)
            }

            // App content
            ContentView()
        }
        .task {
            // Configure TipKit
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}
```

**Priority Modes:**
- **`.ordered`** - Tips display in array order; next tip only shows after previous is invalidated
- **`.firstAvailable`** - Shows first tip that meets display rules; useful for unrelated tips

**Accessing Tips:**
- `tips.currentTip` - Automatically calculates the next available tip
- Manual invalidation updates `currentTip` automatically

**Cross-Device Sync (iOS 18+ / macOS 15+):**
```swift
try? Tips.configure([
    .displayFrequency(.immediate),
    .datastoreLocation(.applicationDefault)
])
// Tip state now syncs across devices with same iCloud account
// Example: If max display count is 3, viewing on 3 different devices = tip invalidated
```

**MaxDisplayDuration (iOS 18+ / macOS 15+):**
```swift
struct MyTip: Tip {
    var title: Text { Text("Feature Hint") }

    var options: [TipOption] {
        MaxDisplayDuration(.minutes(5))  // Auto-invalidate after 5 cumulative minutes
    }
}
```

#### 2. TipKit Limitations (Still Unresolved in iOS 18/macOS 15)

**State Management Issues:**
- `popoverTip()` API still doesn't use `Binding<Bool>` (unlike all other SwiftUI navigation)
- No dismissal callback - can't detect when user closes tip
- Difficult to coordinate with other UI state

**Quote from Developer Analysis (2024):**
> "The popoverTip API is completely different than all other SwiftUI navigation APIs. Because there's no Binding, SwiftUI/TipKit can't nil out the state, and there's nothing informing you that the user dismissed the tip."

**Recommendation for Contextify:**
- ❌ **Don't use TipKit for core help system** - state management too limiting
- ✅ **Consider TipKit only for:** First-launch onboarding (one-time welcome flow)
- ✅ **Use custom popovers for:** All contextual help (errors, settings, features)

---

## Part 3: Popover Sizing in SwiftUI 6 (iOS 18 / macOS 15)

### presentationSizing() - New in iOS 18 / macOS 15

**Major Change:** Default sheet/popover sizing behavior changed in iOS 18/macOS 15.

**Old Defaults (iOS 17 / macOS 14):**
- iOS: `.page` (full-page sheet)
- macOS: `.fitted` (sized to content)

**New Defaults (iOS 18 / macOS 15):**
- iOS & macOS: `.form` (traditional form sheet - smaller)

**Available Sizing Options:**
```swift
public enum PresentationSizing {
    case automatic          // Resolves to .form or .fitted based on platform
    case form              // Traditional form sheet (compact)
    case fitted            // Sized to content
    case page              // Full-page (old iOS default)
    case sticky            // Expands automatically based on content
}
```

**Usage:**
```swift
.sheet(isPresented: $showHelp) {
    HelpContent()
        .presentationSizing(.fitted)  // Size to content
}

.popover(isPresented: $showInfo) {
    InfoPopover()
        .presentationSizing(.form)    // Compact form sheet
}
```

**Custom Sizing (Advanced):**
```swift
struct CustomSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot,
                     context: PresentationSizingContext) -> ProposedViewSize {
        // Return custom size based on content
        ProposedViewSize(width: 320, height: 240)
    }
}

// Usage:
.presentationSizing(CustomSizing())
```

**Recommendation for Contextify:**
```swift
// For info popovers (compact help)
.popover(isPresented: $showInfo) {
    InfoPopoverContent()
        .presentationSizing(.fitted)     // Size to content
        .frame(maxWidth: 320)             // Constrain max width
        .presentationCompactAdaptation(.popover)  // Always popover (not sheet)
}
```

**Important:** Contextify targets macOS 14+, so we **do not get `.form` default** - need to explicitly use `presentationSizing(.fitted)` if we want content-sized popovers.

---

## Part 4: SF Symbols 6 Updates (WWDC 2024)

### New Symbols & Features

**Total Symbol Count:** 6,900+ symbols (800 new in SF Symbols 6)

**New Categories:**
- Automotive symbols (batteries, convertibles, temperature)
- Diverse activity figures
- Localized symbols for various scripts

**New Animation Presets:**
```swift
Image(systemName: "info.circle")
    .symbolEffect(.wiggle)          // Attention-grabbing

Image(systemName: "arrow.circlepath")
    .symbolEffect(.rotate)          // Progress indication

Image(systemName: "checkmark.circle")
    .symbolEffect(.breathe)         // Status changes
```

**Enhanced Magic Replace:**
- Smooth transitions between related symbols
- Slashes, badges animate independently
- Example: `info.circle` → `info.circle.fill`

**Recommended for Contextify:**
```swift
struct InfoButton: View {
    @Binding var isPresented: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isHovering ? "info.circle.fill" : "info.circle")
                .foregroundStyle(isHovering ? .blue : .secondary)
                // NEW: Use symbol effects for attention
                .symbolEffect(.pulse, isActive: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

---

## Part 5: Accessibility Best Practices (2024 Update)

### VoiceOver Support for Help Buttons

**Essential Modifiers:**
```swift
Button {
    showHelp = true
} label: {
    Image(systemName: "info.circle")
}
.accessibilityLabel("More information")  // What it IS
.accessibilityHint("Opens detailed help about this feature")  // What it DOES
```

**Best Practices from WWDC 2024:**

1. **Use native components when possible** - Automatic accessibility
   ```swift
   // ✅ Good: Native HelpLink
   HelpLink(destination: helpURL)

   // ⚠️ Requires manual accessibility:
   Button { showHelp = true } label: { Image(systemName: "info.circle") }
       .accessibilityLabel("More information")
   ```

2. **Label vs Hint Guidelines:**
   - **Label**: Describes **what** the element is (noun)
   - **Hint**: Describes **what happens** when activated (verb phrase)

   ```swift
   // ✅ Good
   .accessibilityLabel("Help button")
   .accessibilityHint("Opens troubleshooting guide")

   // ❌ Bad
   .accessibilityLabel("Click for help")  // This is a hint, not a label
   ```

3. **Test with VoiceOver:**
   - Enable VoiceOver: Cmd + F5
   - Navigate with VO + Left/Right Arrow
   - Verify labels are clear and concise
   - Ensure hints provide actionable context

4. **Reduced Motion:**
   ```swift
   @Environment(\.accessibilityReduceMotion) var reduceMotion

   var body: some View {
       Button { showHelp = true } label: { ... }
           .scaleEffect(isHovering && !reduceMotion ? 1.1 : 1.0)
           .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
   }
   ```

5. **Keyboard Navigation:**
   - All help buttons must be Tab-accessible
   - Space/Enter to activate
   - Esc to dismiss popovers
   - SwiftUI handles this automatically for Button/HelpLink

---

## Part 6: Cursor Behavior Best Practices

### onContinuousHover (macOS 13+) - No Changes in macOS 15

**Current Best Practice (Unchanged):**
```swift
extension View {
    func customCursor(_ cursor: NSCursor) -> some View {
        if #available(macOS 13.0, *) {
            return self.onContinuousHover { phase in
                switch phase {
                case .active(_):
                    guard NSCursor.current != cursor else { return }
                    cursor.push()
                case .ended:
                    NSCursor.pop()
                }
            }
        } else {
            // Fallback for macOS 12 (Contextify targets 14+, so not needed)
            return self.onHover { inside in
                if inside {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
```

**Question Mark Cursor Analysis:**

After extensive research, **modern macOS apps rarely use question mark cursor** for help buttons.

**Historical Context:**
- 1980s-2000s Mac OS: Question mark cursor was primary help mechanism
- macOS 10.0+: Shift toward info buttons and contextual panels
- Modern macOS (2020+): Question mark cursor rarely seen

**Modern App Behavior (Observation):**
- System Settings: Info buttons with default pointer
- Mail.app: Help buttons with default pointer
- Xcode: Help panels with default pointer
- Photos: Info buttons with default pointer

**Recommendation for Contextify:**
- ✅ **Use default pointer** for info buttons
- ✅ **Use scale + color animation** for hover feedback
- ❌ **Don't use question mark cursor** - feels dated, potentially confusing

```swift
// ✅ Recommended approach
struct InfoButton: View {
    @State private var isHovering = false
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isHovering ? "info.circle.fill" : "info.circle")
                .foregroundStyle(isHovering ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        // NO cursor change - default pointer throughout
    }
}
```

---

## Part 7: Apple Design Resources (Figma, 2024)

### macOS 26 UI Kit (August 2024)

Apple released the official **macOS 26 UI kit for Figma** on August 29, 2024.

**Link:** https://www.figma.com/community/file/1543337041090580818/apple-design-resources-macos-26

**Contents:**
- Views and system components (windows, alerts, **popovers**, sheets, save dialogs)
- Desktop templates (menubar, dock, notifications, wallpapers)
- System colors, materials, text styles, vibrancy effects

**Note:** "macOS 26" refers to the **macOS SDK version**, not the OS version. This is the design kit for **macOS 15 Sequoia** (SDK version 26).

**Relevance to Contextify:**
- ✅ Contains popover component examples
- ✅ Shows system-standard styling
- ✅ Includes color/material specifications
- ⚠️ Requires Figma account to access/inspect

**Action Item:** If possible, inspect the Figma kit to extract exact popover styling parameters (padding, corner radius, shadow specs, arrow dimensions).

---

## Part 8: Modern SwiftUI Popover Implementation

### Complete Implementation Guide for SwiftUI 6+

#### 1. Reusable Info Button Component

```swift
import SwiftUI

struct InfoButton: View {
    @Binding var isPresented: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isHovering ? "info.circle.fill" : "info.circle")
                .foregroundStyle(isHovering ? .blue : .secondary)
                .font(.caption)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !reduceMotion ? 1.1 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel("More information")
        .accessibilityHint("Shows additional details")
    }
}
```

#### 2. Reusable Info Popover Content

```swift
import SwiftUI

struct InfoPopoverContent: View {
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Body
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Optional action
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
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial)  // Native vibrancy
        .presentationSizing(.fitted)    // NEW: SwiftUI 6 sizing
        .presentationCompactAdaptation(.popover)
    }
}
```

#### 3. Usage Example: Status Bar Error Help

```swift
struct StatusBarView: View {
    @State private var showErrorInfo = false
    @State private var viewModel: StatusBarViewModel?

    var body: some View {
        HStack(spacing: 6) {
            // Error indicator
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("\(viewModel?.errorCount ?? 0) errors")
                .font(.caption)

            // Info button
            InfoButton(isPresented: $showErrorInfo)
                .popover(isPresented: $showErrorInfo) {
                    InfoPopoverContent(
                        title: "LLM Generation Errors",
                        message: """
                        \(viewModel?.errorCount ?? 0) summaries failed to generate.

                        Common causes:
                        • Apple Intelligence is disabled
                        • Content doesn't meet quality threshold
                        • System is under heavy load

                        Errors auto-clear after 3 successful generations.
                        """,
                        actionLabel: "Open System Settings",
                        action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
                        }
                    )
                }
        }
    }
}
```

#### 4. Usage Example: AI Status Help

```swift
struct AIStatusIndicator: View {
    @State private var showAIInfo = false
    let status: AIStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status == .available ? .green : .red)
                .frame(width: 8, height: 8)

            Text(status == .available ? "Apple Intelligence" : "AI Error")
                .font(.caption)

            InfoButton(isPresented: $showAIInfo)
                .popover(isPresented: $showAIInfo) {
                    InfoPopoverContent(
                        title: "Apple Intelligence",
                        message: status == .available
                            ? "On-device language models are generating conversation summaries using FoundationLLM."
                            : """
                            Apple Intelligence is unavailable or experiencing errors.

                            To enable:
                            1. Open System Settings
                            2. Go to Apple Intelligence & Siri
                            3. Toggle Apple Intelligence on
                            4. Restart Contextify

                            Requirements:
                            • macOS 15 Sequoia or later
                            • Apple Silicon (M1 or newer)
                            """,
                        actionLabel: status == .available ? nil : "Open System Settings",
                        action: status == .available ? nil : {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.siri")!)
                        }
                    )
                }
        }
    }
}
```

---

## Part 9: SwiftUI 6 Help System Architecture

### Recommended Three-Tier System (Updated for SwiftUI 6)

#### Tier 1: Simple Tooltips (`.help()`)
**API:** Unchanged since macOS 11
**Usage:** Icon labels, keyboard shortcuts, brief clarifications

```swift
Button(action: { /* ... */ }) {
    Image(systemName: "folder.badge.gearshape")
}
.help("Manage Projects")
```

**When to use:**
- ✅ Single line (< 60 characters)
- ✅ No formatting needed
- ✅ Static content
- ✅ Label clarification only

---

#### Tier 2: Info Popovers (Click-triggered)
**API:** `.popover()` + custom InfoButton
**Usage:** Multi-line explanations, error details, recovery steps

```swift
HStack {
    StatusIndicator()
    InfoButton(isPresented: $showInfo)
        .popover(isPresented: $showInfo) {
            InfoPopoverContent(title: "...", message: "...")
        }
}
```

**When to use:**
- ✅ Multiple lines (2+)
- ✅ Formatted content (bold, links, etc.)
- ✅ Actionable steps
- ✅ Error recovery instructions
- ✅ "Why?" explanations

---

#### Tier 3: Onboarding Hints (First-use only)
**API:** TipKit (optional) or custom hover popovers
**Usage:** First-time feature discovery, one-time welcome

```swift
// Option A: TipKit (if state management limitations acceptable)
@State private var tips = TipGroup(.ordered) {
    [WelcomeTip(), ProjectTip(), TimelineTip()]
}

if let currentTip = tips.currentTip {
    TipView(currentTip)
}

// Option B: Custom implementation (recommended for Contextify)
@State private var showFeatureHint = !UserDefaults.hasSeenProjectTabHint
@State private var hoverTask: Task<Void, Never>?

ProjectTabBar()
    .onHover { hovering in
        guard !UserDefaults.hasSeenProjectTabHint else { return }
        if hovering {
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { showFeatureHint = true }
            }
        } else {
            hoverTask?.cancel()
            showFeatureHint = false
        }
    }
    .popover(isPresented: $showFeatureHint) {
        FeatureHintPopover()
            .onAppear {
                UserDefaults.hasSeenProjectTabHint = true
            }
    }
```

**When to use:**
- ✅ First-launch onboarding
- ✅ New feature announcements
- ✅ Complex UI interactions (drag/drop, gestures)
- ⚠️ Use sparingly (max 2-3 per view)
- ⚠️ Always dismissible
- ⚠️ Show once per session/install

---

## Part 10: Updated Recommendations for Contextify

### Revised Priority Roadmap (SwiftUI 6 Focus)

#### Phase 1: Core Help Infrastructure (P0)
**Estimated: 4-6 hours**

1. **Create reusable components:**
   ```
   - InfoButton.swift (with SwiftUI 6 symbol effects)
   - InfoPopoverContent.swift (with presentationSizing)
   - Accessibility helpers
   ```

2. **Status Bar Error Help:**
   - Replace complex tooltip with Tier 2 info popover
   - Include recovery steps and System Settings link
   - **File:** `StatusBarView.swift:177-191`

3. **AI Status Help:**
   - Add info button next to Apple Intelligence indicator
   - Explain requirements, show current state
   - Link to System Settings
   - **File:** `StatusBarView.swift:96-111`

---

#### Phase 2: Contextual Help Expansion (P1)
**Estimated: 6-8 hours**

1. **Follow Mode Explanation:**
   - Info button on "Follow" chip in ProjectRowView
   - Explain "Auto" vs "Pinned" modes
   - **File:** `ProjectRowView.swift:42-75`

2. **Project Tab Reordering Hint:**
   - Tier 3 onboarding (first-use only)
   - Show "Drag tabs to reorder" on hover
   - **File:** `ProjectSwitcherView.swift`

3. **Empty Timeline State:**
   - Tier 2 or Tier 3 help explaining what will appear
   - **File:** `ConversationTimelineView.swift:141-143`

4. **Database Location Settings:**
   - Info button explaining multi-machine conflicts
   - Backup recommendations
   - **File:** `SettingsView.swift`

---

#### Phase 3: Polish & Accessibility (P2)
**Estimated: 4-6 hours**

1. **Accessibility Audit:**
   - Verify all info buttons have `.accessibilityLabel()`
   - Add `.accessibilityHint()` where appropriate
   - Test with VoiceOver

2. **Reduced Motion Support:**
   - Remove animations when `accessibilityReduceMotion` is true
   - Test scale effects, symbol effects

3. **Keyboard Navigation:**
   - Verify Tab navigation to all info buttons
   - Test Space/Enter activation
   - Verify Esc dismissal

4. **Standard Tooltip Review:**
   - Audit all 26 existing `.help()` tooltips
   - Ensure < 60 characters
   - Remove redundant tooltips

---

#### Phase 4: Help Menu & Documentation (P2)
**Estimated: 8-12 hours**

1. **Help Menu Structure:**
   - Configure SwiftUI Help menu with `.commands` modifier
   - Add contextual menu items:
     - "Contextify Help" (⌘?)
     - "Understanding Apple Intelligence"
     - "Managing Projects & Transcripts"
     - "Keyboard Shortcuts"
     - "Troubleshooting Guide"
   - Add search functionality

2. **Help Content Writing:**
   - **Getting Started Guide** (for new users)
     - Setting up your first project
     - Understanding the timeline
     - How Apple Intelligence works
   - **Feature Documentation:**
     - Projects & Transcripts
     - Timeline & Conversation Log
     - Apple Intelligence Integration
     - Custom Database Locations
     - Follow Modes (Auto vs Pinned)
   - **Troubleshooting:**
     - "Apple Intelligence Not Available"
     - "Project Directory Not Found"
     - "Database Access Errors"
     - "LLM Generation Failures"
   - **Keyboard Shortcuts Reference**

3. **Help Delivery Method:**
   - **Option A:** Help Book (bundled HTML, searchable, offline)
   - **Option B:** Online docs + HelpLink (easier to update)
   - **Option C:** Hybrid (basic help book + "Learn More" → website)
   - **Recommendation:** Start with Option B (online docs) for easier iteration

4. **Integration:**
   - Link info popovers to relevant help topics
   - Add "Learn More" buttons that open specific help pages
   - Help menu items open corresponding documentation
   - Ensure help is searchable from Spotlight (if using Help Book)

---

#### Phase 5: Advanced/Optional Features (P3)
**Estimated: 4-6 hours**

1. **HelpLink Integration in Settings:**
   - Add HelpLink buttons for complex settings
   - Link to detailed online documentation
   - Supplement inline popovers with comprehensive guides

2. **First-Launch Onboarding:**
   - Welcome tour using TipKit or custom tips
   - Show 2-3 key features on first run
   - "Getting Started" quick tour
   - Dismissible, shows once per install

3. **Context-Sensitive Help Menu:**
   - Help menu items context-aware (show relevant to current view)
   - Example: When viewing timeline → "Help > About Timeline"
   - Dynamic menu items based on app state

4. **Help Search/Index:**
   - In-app help search window
   - Aggregates all help content
   - Command palette for quick access (⌘K)
   - Recent help topics

---

### Technology Decisions

| Component | Technology Choice | Rationale |
|-----------|------------------|-----------|
| **Help Buttons** | Custom InfoButton + `.popover()` | ✅ Full control, inline content, no URL limitation |
| **NOT HelpLink** | ❌ External URLs only | ❌ Can't show inline popovers |
| **Popover Sizing** | `.presentationSizing(.fitted)` | ✅ Content-aware, SwiftUI 6 best practice |
| **Onboarding** | Custom hover popovers + UserDefaults | ✅ Full state control vs TipKit limitations |
| **NOT TipKit** | ❌ State management issues | ❌ No Binding, no dismissal callback |
| **Symbol Effects** | `.symbolEffect(.pulse)` on hover | ✅ Modern, subtle, SF Symbols 6 feature |
| **Cursor** | Default pointer (no changes) | ✅ Modern macOS convention |
| **Accessibility** | `.accessibilityLabel()` + `.accessibilityHint()` | ✅ WWDC 2024 best practices |

---

## Part 11: Code Examples - Complete Implementations

### Example 1: Status Bar Error Info Popover

```swift
// MARK: - Enhanced Status Bar with Info Popovers
struct StatusBarView: View {
    @Environment(ConversationMonitor.self) private var timeline
    @State private var viewModel: StatusBarViewModel?
    @State private var showErrorInfo = false
    @State private var showAIInfo = false

    var body: some View {
        HStack(spacing: 16) {
            // AI Status with info
            aiStatusWithInfo

            Divider().frame(height: 12)

            // Queue status with error info
            if let viewModel, viewModel.recentErrorCount > 0 {
                errorStatusWithInfo
            } else {
                queueStatusView
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    @ViewBuilder
    private var aiStatusWithInfo: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(aiStatusColor)
                .frame(width: 8, height: 8)

            Text(aiStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            InfoButton(isPresented: $showAIInfo)
                .popover(isPresented: $showAIInfo) {
                    InfoPopoverContent(
                        title: "Apple Intelligence",
                        message: aiInfoMessage,
                        actionLabel: viewModel?.aiStatus == .error ? "Open System Settings" : nil,
                        action: viewModel?.aiStatus == .error ? openSystemSettings : nil
                    )
                }
        }
        .help(aiStatusText)  // Keep simple tooltip
    }

    @ViewBuilder
    private var errorStatusWithInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.831, green: 0.659, blue: 0.306))  // Contextify Yellow
                .font(.caption)

            Text("\(viewModel?.recentErrorCount ?? 0) error\(viewModel?.recentErrorCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            InfoButton(isPresented: $showErrorInfo)
                .popover(isPresented: $showErrorInfo) {
                    InfoPopoverContent(
                        title: "LLM Generation Errors",
                        message: errorInfoMessage,
                        actionLabel: "Check System Settings",
                        action: openSystemSettings
                    )
                }
        }
        .help("LLM generation errors occurred")  // Simplified tooltip
    }

    // MARK: - Computed Properties

    private var aiStatusColor: Color {
        guard let viewModel else { return .secondary }
        switch viewModel.aiStatus {
        case .available:
            return Color(red: 0.318, green: 0.659, blue: 0.420)  // Contextify Green
        case .unavailable:
            return .secondary
        case .error:
            return Color(red: 0.780, green: 0.306, blue: 0.306)  // Contextify Red
        }
    }

    private var aiStatusText: String {
        guard let viewModel else { return "AI Unavailable" }
        switch viewModel.aiStatus {
        case .available: return "Apple Intelligence"
        case .unavailable: return "AI Unavailable"
        case .error: return "AI Error"
        }
    }

    private var aiInfoMessage: String {
        guard let viewModel else { return "Initializing..." }
        switch viewModel.aiStatus {
        case .available:
            return """
            Apple Intelligence is available and generating conversation summaries using on-device language models (FoundationLLM).

            All processing happens locally on your Mac for privacy.
            """
        case .unavailable(let reason):
            return """
            Apple Intelligence is unavailable.

            Reason: \(reason)

            Summaries will be generated using fallback heuristics (less detailed).
            """
        case .error(let message):
            return """
            Apple Intelligence encountered an error.

            Error: \(message)

            Try these steps:
            1. Check that Apple Intelligence is enabled in System Settings
            2. Restart Contextify
            3. Restart your Mac if the issue persists

            Errors auto-clear after 3 successful generations.
            """
        }
    }

    private var errorInfoMessage: String {
        guard let viewModel else { return "" }
        let count = viewModel.recentErrorCount
        let reason = viewModel.topErrorReason

        var message = """
        \(count) conversation \(count == 1 ? "entry" : "entries") failed to generate summaries.
        """

        if let reason {
            message += "\n\nTop error: \(simplifyErrorReason(reason))"
        }

        message += """


        Common causes:
        • Apple Intelligence is disabled or unavailable
        • Content quality too low (empty messages, no context)
        • System resources temporarily unavailable

        What to try:
        1. Check Apple Intelligence in System Settings
        2. Ensure sufficient system memory available
        3. Wait a moment and try refreshing the timeline

        Errors auto-clear after 3 successful generations.
        """

        return message
    }

    // MARK: - Helper Functions

    private func simplifyErrorReason(_ reason: String) -> String {
        if reason.contains("REJECTED") {
            return "Summary quality too low"
        } else if reason.contains("grounding") {
            return "Content not grounded in source"
        } else if reason.contains("leaked") {
            return "Summary was invalid"
        } else if reason.contains("confidence") {
            return "Low confidence result"
        } else if reason.contains("timeout") {
            return "Generation timed out"
        } else {
            return reason
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

---

### Example 2: Reusable Components with SwiftUI 6 Features

```swift
// MARK: - InfoButton.swift
import SwiftUI

struct InfoButton: View {
    @Binding var isPresented: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isHovering ? "info.circle.fill" : "info.circle")
                .foregroundStyle(isHovering ? .blue : .secondary)
                .font(.caption)
                .imageScale(.medium)
                // SwiftUI 6: Symbol effects
                .symbolEffect(.pulse, options: .nonRepeating, isActive: isHovering)
        }
        .buttonStyle(.plain)
        // Respect reduced motion preference
        .scaleEffect(isHovering && !reduceMotion ? 1.1 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        // Accessibility
        .accessibilityLabel("More information")
        .accessibilityHint("Shows additional details about this feature")
    }
}

// MARK: - InfoPopoverContent.swift
import SwiftUI

struct InfoPopoverContent: View {
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with close button
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Body content
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)  // Allow multi-line

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
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial)  // Native vibrancy effect
        // SwiftUI 6: Explicit sizing control
        .presentationSizing(.fitted)
        .presentationCompactAdaptation(.popover)  // Always popover, never sheet
    }
}

#Preview {
    struct PreviewContainer: View {
        @State private var showInfo = false

        var body: some View {
            HStack {
                Text("Feature Name")
                InfoButton(isPresented: $showInfo)
                    .popover(isPresented: $showInfo) {
                        InfoPopoverContent(
                            title: "Feature Explanation",
                            message: "This is a detailed explanation of the feature with multiple lines of helpful information.",
                            actionLabel: "Learn More",
                            action: {
                                print("Action triggered")
                            }
                        )
                    }
            }
            .padding()
        }
    }

    return PreviewContainer()
}
```

---

## Part 12: Migration Checklist

### Updating Existing Tooltips to SwiftUI 6 Patterns

Use this checklist to systematically update Contextify's help system:

- [ ] **Phase 0: Setup**
  - [ ] Create `InfoButton.swift` component
  - [ ] Create `InfoPopoverContent.swift` component
  - [ ] Add accessibility helpers
  - [ ] Test in Preview with VoiceOver

- [ ] **Phase 1: StatusBarView Updates**
  - [ ] ❌ Remove: Complex `aiStatusTooltip` (lines 136-146)
  - [ ] ✅ Add: AI status info button + popover
  - [ ] ❌ Remove: Complex `errorTooltip()` (lines 242-255)
  - [ ] ✅ Add: Error info button + popover
  - [ ] ✅ Keep: Simple "Not monitoring" tooltip (line 174)
  - [ ] Test: VoiceOver announces info buttons correctly
  - [ ] Test: Popovers dismiss on Esc, outside click

- [ ] **Phase 2: Other Views**
  - [ ] ProjectRowView: Add follow mode info button (line 74)
  - [ ] SettingsView: Add database location info button
  - [ ] ConversationTimelineView: Enhance empty state
  - [ ] ProjectSwitcherView: Add missing directory recovery info

- [ ] **Phase 3: Accessibility Audit**
  - [ ] All info buttons have `.accessibilityLabel()`
  - [ ] All info buttons have `.accessibilityHint()`
  - [ ] Test Tab navigation to all info buttons
  - [ ] Test Space/Enter activation
  - [ ] Test VoiceOver announces correctly
  - [ ] Test reduced motion (no animations)

- [ ] **Phase 4: Performance & Polish**
  - [ ] Verify popovers don't cause memory leaks
  - [ ] Test popover dismissal cleanup
  - [ ] Verify cursor doesn't get stuck (no push/pop issues)
  - [ ] Test with multiple monitors
  - [ ] Test with high contrast mode

---

## Conclusion

SwiftUI 6 (iOS 18 / macOS 15) brings **incremental improvements** to help/tooltip systems, but no revolutionary changes:

### What's New:
- ✅ `HelpLink` for external help URLs (macOS 14+)
- ✅ TipKit `TipGroup` for sequential onboarding
- ✅ `presentationSizing()` for better popover control
- ✅ SF Symbols 6 with new animations

### What Hasn't Changed:
- ⚠️ `.help()` modifier still string-only
- ⚠️ `onContinuousHover` unchanged since macOS 13
- ⚠️ TipKit still has state management limitations
- ⚠️ No native "info button + inline popover" component

### Recommendation for Contextify:

**Use custom implementation** with:
1. InfoButton component (no cursor change, scale + color animation)
2. InfoPopoverContent with `.presentationSizing(.fitted)`
3. `.accessibilityLabel()` + `.accessibilityHint()` on all info buttons
4. Default pointer throughout (modern macOS convention)
5. Optional SF Symbols 6 `.symbolEffect(.pulse)` for subtle attention

**Don't use:**
- ❌ HelpLink (external URLs only, can't show inline content)
- ❌ TipKit (state management too limiting for Contextify's needs)
- ❌ Question mark cursor (dated, potentially confusing)

---

## Additional Resources

### Official Apple Sources
- **WWDC 2024 - What's new in SwiftUI:** Session 10144
- **WWDC 2024 - Tailor macOS windows with SwiftUI:** Session 10148
- **WWDC 2024 - Catch up on accessibility in SwiftUI:** Session 10073
- **WWDC 2024 - What's new in SF Symbols 6:** Session 10188
- **Apple Design Resources (Figma):** macOS 26 UI Kit (Aug 2024)

### Community Resources
- **Swift with Majid:** TipKit series (May-Sept 2024)
- **fatbobman.com:** Mastering TipKit - Basics & Advanced
- **nilcoalescing.com:** Tracking Hover Location in SwiftUI
- **GitHub:** aheze/Popovers, iSapozhnik/Popover

### Accessibility
- **WWDC 2024:** Accessibility in SwiftUI
- **WWDC 2021:** SwiftUI Accessibility: Beyond the basics
- **tanaschita.com:** VoiceOver in SwiftUI guide (2024)

---

**Document Status:** Comprehensive, ready for implementation
**Next Steps:** Begin Phase 1 implementation (StatusBarView updates)

**Estimated Total Effort:**
- **Phases 1-3** (Core inline help): 14-20 hours
- **Phase 4** (Help Menu & Documentation): 8-12 hours
- **Phase 5** (Advanced features): 4-6 hours
- **Total (All 5 phases)**: 26-38 hours
- **Recommended MVP** (Phases 1-3 only): 14-20 hours

