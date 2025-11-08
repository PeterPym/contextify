# Feature Flags

**For:** Contextify macOS HUD
**Scope:** Developer-facing UI only
**Location:** `Contextify/Contextify/DeveloperMode.swift`

## Policy: Developer UI Only

Feature flags in Contextify are **strictly limited to developer-facing debug tools and test UIs**.

### ✅ Allowed Use Cases

- Hiding/showing debug test UIs (e.g., embedding service tests)
- Exposing developer-only diagnostic tools
- Gating experimental debug features during development
- Temporary test interfaces before migration to Settings

### ❌ NOT Allowed

- **Backward compatibility** - Handle via proper versioning and migration
- **A/B testing** - Not applicable to this product
- **Progressive rollout** - Single-user app, no rollout needed
- **Production feature toggling** - Use Settings UI for user-facing features
- **Runtime configuration** - Use Settings or preferences instead

**Rationale:** Feature flags create complexity, technical debt, and maintenance burden. The only justified use is temporarily gating developer tools that shouldn't be visible in production builds but are useful during active development.

---

## Current Feature Flags

### Developer Mode

**Flag:** `DeveloperModeEnabled`
**Default:** `false` (disabled)
**Type:** Boolean (UserDefaults)

Enables developer-only test UIs and debug tools.

#### Enabling Developer Mode

**Option 1: Using Build Script (Recommended)**

```bash
# Build and launch with developer mode enabled
bash scripts/xc.sh --dev build

# Works with any build configuration
bash scripts/xc.sh --dev Release build
```

The `--dev` flag automatically enables developer mode before launching the app. When omitted, developer mode is disabled by default.

**Option 2: Manual UserDefaults**

```bash
# Enable developer mode
defaults write dev.contextify.Contextify DeveloperModeEnabled -bool true

# Disable developer mode
defaults write dev.contextify.Contextify DeveloperModeEnabled -bool false

# Check current status
defaults read dev.contextify.Contextify DeveloperModeEnabled
```

**Note:** When using manual defaults, restart Contextify after changing this setting.

#### What It Enables

When enabled, developer mode reveals:
- **Embedding Service Test UI** (testtube icon) - Test NLContextualEmbedding directly
- **Database Test UI** (cylinder icon) - End-to-end embedding database verification
- **Future debug tools** - Additional developer features as they're added

#### Implementation

**File:** `Contextify/Contextify/DeveloperMode.swift`
```swift
@MainActor
@Observable
final class DeveloperMode {
  static let shared = DeveloperMode()

  private let userDefaultsKey = "DeveloperModeEnabled"

  var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
    set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
  }

  private init() {}
}
```

**Usage in UI:**
```swift
@Environment(DeveloperMode.self) private var devMode

var body: some View {
  VStack {
    // ... production UI ...

    if devMode.isEnabled {
      // Developer-only test buttons
      Button("Test Embeddings") { /* ... */ }
    }
  }
}
```

**Environment Setup:** `ContextifyApp.swift`
```swift
Window("Contextify", id: "main") {
  ContentView()
    .environment(DeveloperMode.shared)
}
```

---

## Best Practices

### 1. Keep Disabled by Default
Developer tools should **never** be visible in production builds without explicit activation.

### 2. Use for Temporary Test UIs Only
Features destined for end users should migrate to Settings UI (see RAG batch embedding migration plan in `TODOS.md`).

Example migration path:
- **Phase 1**: Test feature behind developer flag
- **Phase 2**: Build proper Settings UI
- **Phase 3**: Remove developer flag, expose via Settings
- **Phase 4**: Delete temporary test UI code

### 3. Document New Features
When adding developer tools, update the "What It Enables" list above.

### 4. Runtime Toggle
UserDefaults allows enabling without rebuilding the app. Good for quick testing.

### 5. No Sensitive Data
Don't gate security features, privacy controls, or data access behind developer flags.

### 6. No Production Logic
Developer mode should only affect UI visibility, never core business logic.

**Bad:**
```swift
if devMode.isEnabled {
  // Different algorithm - creates unpredictable behavior!
  return fastButUnsafeImplementation()
}
```

**Good:**
```swift
if devMode.isEnabled {
  // Just shows extra debug UI
  debugPanel.isHidden = false
}
```

---

## Adding a New Developer Feature

If you need to add a new developer-only UI:

1. **Check if it should be in Settings instead**
   - If users will need it long-term → Settings
   - If it's a temporary test UI → Developer Mode

2. **Add UI gated by `devMode.isEnabled`**
   ```swift
   if devMode.isEnabled {
     Button("New Test Tool") { /* ... */ }
   }
   ```

3. **Update documentation** - Add to "What It Enables" list above

4. **Set migration timeline** - If this will move to Settings, note it in TODOS.md

---

## Related Files

- `Contextify/Contextify/DeveloperMode.swift` - Feature flag implementation
- `Contextify/Contextify/ContentView.swift` - Test button visibility gated by flag
- `Contextify/Contextify/ContextifyApp.swift` - DeveloperMode added to environment

---

**See also:**
- `logging-preferences.md` - Logging guidelines and console output filtering
- `TODOS.md` - RAG embedding UI migration plan (moving test modal to Settings)
