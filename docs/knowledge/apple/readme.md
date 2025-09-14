---
title: Apple macOS 26 + SwiftUI (Xcode 16) — Canonical Guide
summary: LLM‑oriented, up‑to‑date reference for building a macOS 26 (Tahoe) SwiftUI HUD with Swift 6, including style, availability, patterns, and sample‑driven starting points.
audience: agent-coders, contributors
tags: [swiftui, swift6, macos26, xcode16, core-ml, availability, concurrency, observation]
platforms: [macOS]
xcode_version: ">=16"
os_targets:
  base_sdk: macOS 26
  min_deployment: macOS 14
priorities:
  - Phase 1 HUD ingest + toast
  - Availability‑safe UI patterns
  - Testable flows (unit/UI)
  - Prepare Core ML seams (on‑device)
last_reviewed: 2025-09-13
sources:
  - https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/
  - https://developer.apple.com/macos/whats-new/
  - https://developer.apple.com/macos/get-started/
  - https://developer.apple.com/documentation/Xcode/writing-code-with-intelligence-in-xcode
  - https://developer.apple.com/documentation/SampleCode
  - https://developer.apple.com/documentation/swiftui/view/ondrop(of:isTargeted:perform:)
  - https://developer.apple.com/documentation/coretransferable/transferable
  - https://developer.apple.com/documentation/swiftui/menubarextra
  - https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml
  - https://developer.apple.com/documentation/swiftui/documentgroup
  - https://developer.apple.com/documentation/uniformtypeidentifiers
  - https://developer.apple.com/documentation/testing
  - https://developer.apple.com/documentation/xctest
  - https://github.com/apple/sample-food-truck
  - https://github.com/apple/ml-stable-diffusion
  - https://github.com/apple/coremltools
---

# Apple references for Contextify HUD

Comprehensive, LLM‑friendly reference for building a macOS 26 (Tahoe) SwiftUI HUD with Xcode 16+, Swift 6, and Apple‑recommended patterns. Use this as canonical context when your pretraining predates these platforms.

## Canonical Links (authoritative)
- macOS Tahoe 26 — Apple Newsroom: https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/
- What’s New — macOS (26): https://developer.apple.com/macos/whats-new/
- Get Started — macOS: https://developer.apple.com/macos/get-started/
- Xcode Intelligence (code completion, refactors, Previews): https://developer.apple.com/documentation/Xcode/writing-code-with-intelligence-in-xcode
- Apple Sample Code portal (filter by SwiftUI + macOS): https://developer.apple.com/documentation/SampleCode

## Target Environment Profile
- Xcode: 16+ (set Command Line Tools to this version).
- Base SDK: macOS 26; Minimum deployment: macOS 14 or 15 (project decision).
- Language: Swift 6 with strict concurrency; Frameworks: SwiftUI, Observation, SwiftData (optional), Core ML (future), AppIntents (optional).
- Availability: gate Tahoe‑only features with `@available(macOS 26, *)` and provide fallbacks.

## Style & Methodology (Apple‑aligned)
- Swift API Design Guidelines; 2‑space indent; explicit access control; prefer value types.
- Concurrency: async/await, structured tasks, `@MainActor` for UI, `Sendable` across threads; avoid detached tasks.
- State: use Observation (`@Observable`) or `@State`/`@StateObject` for MVVM‑style ViewModels; keep Views declarative and side‑effect‑free.
- Testing: Swift Testing (or XCTest) with fast, deterministic tests; UI tests for HUD flows.
- Availability: isolate new APIs behind small adapter types for clean fallbacks.

## Core HUD Patterns (copy/paste)

Drag & drop ingest to `outputs/`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct IngestDropZone: View {
    @State private var isTargeted = false
    var body: some View {
        ZStack { RoundedRectangle(cornerRadius: 8).stroke(isTargeted ? .accent : .secondary) }
            .frame(height: 120)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                Task { await saveProviders(providers) }
                return true
            }
    }
    @MainActor
    private func saveProviders(_ providers: [NSItemProvider]) async {
        let fm = FileManager.default
        let out = URL(fileURLWithPath: "outputs", isDirectory: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier), let src = item as? URL {
                let dest = out.appendingPathComponent("\(Int(Date().timeIntervalSince1970)).md")
                try? "Ingested: \(src.lastPathComponent)".write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }
}
```

Toast overlay:
```swift
@State private var showToast = false
.overlay(alignment: .top) {
    if showToast {
        Text("Saved to outputs/… ✓")
            .padding(8)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

Availability gate for Tahoe‑only UI niceties:
```swift
if #available(macOS 26, *) {
    // Use newest modifier/component
} else {
    // Fallback path for macOS 14/15
}
```

Swift Testing example (or use XCTest):
```swift
// import Testing
// @Test func createsOutputFile() async throws { /* arrange/act/assert */ }
// If project doesn’t use Testing, mirror with XCTest and expectations.
```

## Starter Projects (avoid blank slates)
- Xcode App template (SwiftUI, macOS). Add `IngestDropZone` + toast overlay; wire buttons (New Session, Checkpoint) as no‑ops that log.
- Apple Sample Code portal: filter SwiftUI + macOS, then look for samples demonstrating:
  - Drag & drop with `onDrop`/`DropDelegate`.
  - Overlays/animations for lightweight notifications.
  - Menu bar utilities (`MenuBarExtra`) if a companion is desired.
  - Document import/export if you prefer a document‑based approach.

Use the sample as a base and replace its core view with the HUD layout while keeping project settings, signing, and targets intact.

### Curated Apple samples (add exact links upon selection)
- SwiftUI macOS drag & drop: `.onDrop(of:isTargeted:perform:)` documentation and examples
  - Docs: https://developer.apple.com/documentation/swiftui/view/ondrop(of:isTargeted:perform:)
  - Modern data flow: Transferable — https://developer.apple.com/documentation/coretransferable/transferable
  - Uniform types: https://developer.apple.com/documentation/uniformtypeidentifiers
  - Tip: Start from a SwiftUI macOS app template, add `IngestDropZone` (snippet above), then evolve into a document‑based app if needed.

- SwiftUI Menu Bar Extra (HUD companion)
  - API: https://developer.apple.com/documentation/swiftui/menubarextra
  - Pattern: Provide a compact controls surface and link to the main HUD window.

- Core ML on macOS with SwiftUI (on‑device inference)
  - Tutorial: Classifying images with Vision and Core ML — https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml
  - Repo (advanced, Apple): https://github.com/apple/ml-stable-diffusion
  - Tools (Apple): https://github.com/apple/coremltools
  - Pattern: Load a compiled `.mlmodelc`, run inference in a background `Task`, surface results via `@MainActor` updates.

- Full SwiftUI sample app (Apple)
  - Food Truck (SwiftUI app patterns, accessibility, navigation): https://github.com/apple/sample-food-truck

How to locate and verify
- Portal: open https://developer.apple.com/documentation/SampleCode and filter Technology=SwiftUI, Platform=macOS, Language=Swift, (optional) Machine Learning.
- Confirm “Platforms” includes macOS and check “Availability” badges for macOS 26 or earlier.
- Prefer samples with recent “Updated” dates and WWDC sessions in Resources.

## AI & Foundation Models (priority context)
- Goal: on‑device, private summarization and simple transforms. Prefer Apple’s on‑device ML via Core ML; keep network off by default. If Apple foundation models are available on your device/Xcode channel, adopt via the official APIs and keep usage behind availability gates.
- Action: from the Sample Code portal, select macOS Swift/SwiftUI projects tagged Core ML or “machine learning”; study model loading, `MLModel` lifecycles, and background processing with structured concurrency.
- Seam design: keep UI (SwiftUI) on main; spawn analysis in background `Task`s; stream results back to UI via `@MainActor` updates.

## Checklists for Agents
- Verify tools: `xcodebuild -version`, `swift --version`, CLT set to Xcode 16.
- Create `outputs/` if missing; write timestamped `.md` files on ingest.
- Use Previews for HUD subviews; keep compile errors at zero before UI tests.
- Add availability gates for any Tahoe‑only API used.
- Prefer Swift Testing or XCTest with a smoke test: launch → submit URL → see toast → file exists.

## Notes for Future Updates
- Replace “Curated Apple samples” placeholders with exact Apple sample links after verification.
- If Apple publishes explicit “Foundation models” docs/APIs for macOS 26, add links, availability notes, and a minimal code snippet showing model load + inference on device.
