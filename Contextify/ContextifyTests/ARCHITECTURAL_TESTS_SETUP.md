# Architectural Tests Setup

This directory contains architectural boundary tests that enforce layer discipline in the Contextify codebase.

## What These Tests Do

The `ArchitecturalTests.swift` file uses SwiftSyntax to parse Swift source files and verify:

1. **UI Layer Isolation**: UI files do not import GRDB directly
2. **ViewModel Isolation**: ViewModel files do not import GRDB directly
3. **Core Layer Purity**: Core/Database files do not import UI frameworks (SwiftUI/AppKit)
4. **Service Layer Separation**: Orchestrator files do not import UI frameworks

## Architecture Rules

```
UI → ViewModel → Orchestrator → Repository → Database
```

**Never skip layers.** Each layer should only depend on the layer below it.

## Setup Instructions for Xcode

### 1. Add SwiftSyntax to Test Target

In Xcode:

1. Open `Contextify.xcodeproj`
2. Select the project in the navigator
3. Select the **ContextifyTests** target
4. Go to **Build Phases** → **Link Binary With Libraries**
5. Click **+** and add these Swift Package dependencies:
   - **SwiftSyntax** (from Package.swift)
   - **SwiftParser** (from Package.swift)

### 2. Verify Package Dependencies

The `Package.swift` already includes SwiftSyntax:

```swift
.package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0")
```

Xcode should automatically resolve this dependency when you open the project.

### 3. Run Tests

```bash
# Run all tests including architectural tests
xcodebuild test -scheme Contextify -destination 'platform=macOS'

# Or use the build script
bash scripts/xc.sh test
```

### 4. Integration with Pre-commit Hook

To run architectural tests before every commit, add to `.githooks/pre-commit`:

```bash
#!/bin/bash

# Run architectural tests before commit
echo "Running architectural boundary tests..."
xcodebuild test -scheme Contextify -only-testing:ContextifyTests/ArchitecturalTests -destination 'platform=macOS' -quiet

if [ $? -ne 0 ]; then
  echo "❌ Architectural tests failed. Fix layer violations before committing."
  echo "See ContextifyTests/ArchitecturalTests.swift for details."
  exit 1
fi

echo "✅ Architectural tests passed"
```

## Test Details

### `testUILayerDoesNotImportGRDB()`

Scans all Swift files in `Contextify/Contextify/` and fails if any import GRDB.

**Fix**: Remove GRDB import and use `TranscriptOrchestrator` methods instead.

### `testViewModelLayerDoesNotImportGRDB()`

Scans all `*ViewModel.swift` files and fails if any import GRDB.

**Fix**: ViewModels should interact with the orchestrator layer, not the database directly.

### `testCoreModelsDoNotImportUIKit()`

Scans all files in `app/Sources/ContextifyCore/Database/` and fails if any import UI frameworks.

**Fix**: Core models should be UI-agnostic. Move UI-specific code to the presentation layer.

### `testOrchestratorLayerDoesNotImportSwiftUI()`

Scans all `*Orchestrator.swift` files and fails if any import SwiftUI or AppKit.

**Fix**: Orchestrators are service layer and should not depend on UI frameworks. Use async callbacks or notifications to communicate with UI.

## Benefits

- **Prevents regression**: Catches layer violations before they reach production
- **Clear architecture**: Enforces clean separation of concerns
- **Easier testing**: Each layer can be tested independently
- **Better reusability**: Core logic works without UI dependencies

## Troubleshooting

### SwiftSyntax not found

If you get "No such module 'SwiftSyntax'":

1. Verify Package.swift includes the SwiftSyntax dependency
2. In Xcode: File → Packages → Update to Latest Package Versions
3. Clean build folder: Product → Clean Build Folder
4. Restart Xcode

### Tests skip with "Could not find directory"

The tests use `#file` to locate source directories. If they can't find the directories:

1. Verify you're running from the correct location
2. Check that directory structure matches expectations:
   - `Contextify/Contextify/` (UI layer)
   - `app/Sources/ContextifyCore/` (Core layer)

### False positives

If you have legitimate exceptions to the architecture rules:

1. Document why the exception is necessary
2. Add special case handling to the test
3. Use `// swiftlint:disable` comments to mark intentional violations

## Related Documentation

- `build/notes/todo-support/P1-CODE-QUALITY-spec.md` - Full code quality improvement plan
- `build/docs/architecture/COMPONENTS.md` - Architecture overview
- `.githooks/pre-commit` - Pre-commit hook configuration

## References

- Related task: #P1-ARCHITECTURAL-TESTS
- Commit: [architectural tests implementation]
- Spec: Phase 2 of Code Quality Improvements
