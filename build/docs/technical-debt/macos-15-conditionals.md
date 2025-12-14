# macOS 15 Conditional Code - Technical Debt Tracker

**Created:** 2025-12-13
**Purpose:** Track all `#available(macOS 26, *)` and `LLMAvailability` conditionals for future removal when macOS 15 support is deprecated.

---

## When to Remove

Remove these conditionals when:
1. macOS 15 market share drops below threshold (TBD)
2. We decide to require macOS 26 minimum
3. Apple drops security updates for macOS 15

---

## Files with macOS 15 Conditionals

| File | Count | Type | Notes |
|------|-------|------|-------|
| `LLMAvailability.swift` | 7 | Core detection | Central availability enum |
| `FoundationLLM.swift` | 27 | LLM API guards | `#if canImport(FoundationModels)` |
| `TranscriptMetadataOrchestrator.swift` | 9 | Queue guards | Lite mode queue bypass |
| `StatusBarViewModel.swift` | 4 | UI state | "Lite Mode" display |
| `TimelineCacheMissGenerator.swift` | 4 | Queue guards | Summary generation bypass |
| `InfoPopoverContent.swift` | 5 | Presentation sizing | `.presentationSizing()` unavailable |
| `LLMHealthCheck.swift` | 6 | Health monitoring | Skip on lite mode |
| `AppDelegate.swift` | 4 | Startup | Availability logging |
| `ContextifyApp.swift` | 3 | Keyboard shortcuts | macOS 26 keyboard APIs |
| `WelcomeModalView.swift` | 1 | Onboarding | Lite mode callout |
| `LiteModeInfoView.swift` | 1 | Dedicated view | Entire file is lite-mode-only |
| `LLMSchemas.swift` | 2 | Schema definitions | Guarded types |
| `SynthesisService.swift` | 4 | Synthesis | LLM synthesis guards |
| `TranscriptContextFitting.swift` | 4 | Context fitting | LLM context guards |
| `TranscriptMetadataPostProcessor.swift` | 3 | Post-processing | LLM output guards |

**Total files affected:** 15+
**Total conditional sites:** ~80+

---

## UI Workarounds (SwiftUI Quirks)

These are in addition to the LLM availability conditionals:

| Issue | File | Workaround | Documented |
|-------|------|------------|------------|
| Horizontal ScrollView clicks blocked | `ProjectSwitcherView.swift` | Button+ButtonStyle instead of onTapGesture | `swiftui-patterns.md` |
| `.onDrag()` fails | `ProjectSwitcherView.swift` | Context menu + keyboard shortcuts | `swiftui-patterns.md` |
| `.textSelection()` sizing | `InfoPopoverContent.swift` | Conditional application | `swiftui-patterns.md` |
| `.presentationSizing()` unavailable | `InfoPopoverContent.swift` | `#available` guard | `swiftui-patterns.md` |

---

## Key Components to Remove

When deprecating macOS 15 support, these are the primary removal targets:

### 1. LLMAvailability.swift (Delete Entirely)
- Remove the entire file
- Remove all `LLMAvailability.current.isLiteMode` checks throughout codebase
- Grep for: `isLiteMode`, `LLMAvailability`, `simulateLegacyMacOS`

### 2. LiteModeInfoView.swift (Delete Entirely)
- Remove the view file
- Remove references in `ContentView.swift` and `StatusBarView.swift`

### 3. #available Guards
- Remove all `#available(macOS 26, *)` guards
- Simplify code paths that have both branches

### 4. #if canImport(FoundationModels)
- Remove conditional compilation guards
- Keep only the macOS 26+ code path

### 5. Launch Argument Support
- Remove `-simulate-legacy-macos` handling
- Update documentation

### 6. Deployment Target
- Update `MACOSX_DEPLOYMENT_TARGET` from `15.0` to `26.0`
- In `Contextify.xcodeproj/project.pbxproj` (4 occurrences)

---

## Cleanup Checklist

When removing macOS 15 support:

- [ ] Remove `LLMAvailability.swift`
- [ ] Remove `LiteModeInfoView.swift`
- [ ] Remove all `#available(macOS 26, *)` guards
- [ ] Remove all `#if canImport(FoundationModels)` guards
- [ ] Remove `-simulate-legacy-macos` support from `LLMAvailability.swift`
- [ ] Update deployment target to macOS 26.0
- [ ] Remove this tracking document
- [ ] Update AGENTS.md target platform section
- [ ] Update `build/docs/architecture/llm-processing.md` Lite Mode section
- [ ] Remove `build/docs/testing/lite-mode-qa-checklist.md`
- [ ] Remove `build/docs/testing/macos-vm-setup.md`
- [ ] Remove `scripts/qa/vm-bootstrap.sh`
- [ ] Update `build/docs/design/swiftui-patterns.md` (remove macOS 15 quirks section)
- [ ] Remove Lite Mode references from DEVELOPMENT.md, TESTING-STRATEGY.md
- [ ] Run full test suite
- [ ] Verify clean build with zero warnings

---

## Related Documentation

- **Lite Mode Overview:** `build/docs/architecture/llm-processing.md#lite-mode-macos-15`
- **SwiftUI Quirks:** `build/docs/design/swiftui-patterns.md#macos-15-sequoia-quirks`
- **QA Checklist:** `build/docs/testing/lite-mode-qa-checklist.md`
- **VM Setup:** `build/docs/testing/macos-vm-setup.md`
- **Implementation Plan:** `build/docs/archive/completed-work/2025-12-13-legacy-macos-implementation-plan.md`
