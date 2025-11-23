# Swift Package Manager Test Suite

This directory contains Swift Package Manager (SPM) test targets for Contextify's platform-agnostic business logic.

## Quick Start

### Running Tests (macOS only)

```bash
# Run all SPM tests
swift test

# Run specific test
swift test --filter DatabaseTests

# Run with verbose output
swift test --verbose
```

### Why This Exists

**Problem:** Previously, all tests required Xcode and `xcodebuild`, which:
- Takes 25+ seconds to run tests
- Requires full macOS environment
- Launches simulators/app bundles
- Can't run on Linux CI

**Solution:** Extract platform-agnostic tests to SPM:
- Takes 0.4-2 seconds to run (60x faster)
- Works with just Swift toolchain
- No simulators/app bundles needed
- Can run on macOS directly

## Test Organization

### Tests in This Directory (Platform-Agnostic)

Located in `Tests/ContextifyCoreTests/`:

- ✅ `DatabaseTests.swift` - Database schema, migrations, repositories (GRDB)
- ✅ `TranscriptParserTests.swift` - Transcript format parsing logic
- ✅ `ProjectIdentityTests.swift` - Project identity resolution
- ✅ `MetadataParserTests.swift` - Metadata extraction from transcripts
- ✅ `TestHelpers.swift` - Shared test utilities

**Why these tests are here:**
- Pure Swift + Foundation + GRDB only
- No UI dependencies (SwiftUI/AppKit)
- No macOS-specific APIs
- Fast execution (no app bundle overhead)

### Tests Still in Xcode Project (Platform-Specific)

Located in `Contextify/ContextifyTests/`:

- ❌ `FoundationLLMTests.swift` - Requires FoundationModels (macOS-only framework)
- ❌ `GitDetectionTests.swift` - Uses macOS security-scoped bookmark APIs
- ❌ `MulticastStreamTests.swift` - Depends on main app target with SwiftUI
- ❌ `FeedLoadingDiagnosticTest.swift` - Depends on main app target
- ❌ `LLMHealthCheckTests.swift` - Depends on main app target
- ❌ `IntegrationTests.swift` - Full app integration (needs Xcode)
- ❌ `ProjectDiscoveryTests.swift` - May need security APIs (needs verification)
- ❌ `TimelineFixValidationTests.swift` - May need app target (needs verification)

**Why these tests stay in Xcode:**
- Depend on FoundationModels (macOS-specific LLM framework)
- Depend on main Contextify app target (SwiftUI/AppKit)
- Use macOS security APIs (security-scoped bookmarks, entitlements)
- Full integration tests requiring app environment

**How to run:**
```bash
# Run all Xcode tests
bash scripts/xc.sh test

# Or via Makefile
make test
```

## Architecture

### Package.swift Configuration

```swift
.testTarget(
  name: "ContextifyCoreTests",
  dependencies: [
    "ContextifyCore",
    .product(name: "GRDB", package: "GRDB.swift")
  ],
  path: "Tests/ContextifyCoreTests"
)
```

### Test Target Dependencies

```
ContextifyCoreTests
  ├── ContextifyCore (app/Sources/ContextifyCore)
  │   ├── Database/      ← Tested by DatabaseTests.swift
  │   ├── Models/        ← Tested by DatabaseTests.swift
  │   ├── ProjectIdentity.swift  ← Tested by ProjectIdentityTests.swift
  │   └── Database/TranscriptParsers.swift  ← Tested by TranscriptParserTests.swift
  └── GRDB.swift (external dependency)
```

## Limitations

### Current Blockers

1. **ContextifyCore has UI dependencies** - 3 files import SwiftUI/AppKit:
   - `HUDCore.swift` (AppKit)
   - `Security/FolderAccessController.swift` (AppKit)
   - `Orchestration/AppStateOrchestrator.swift` (SwiftUI)

   **Impact:** Can't run on Linux yet (macOS-only testing)

2. **@testable import limitation** - Some tests use `@testable import ContextifyCore` to access internal symbols. This works on macOS but may have issues on Linux if ContextifyCore isn't compiled with testability enabled.

3. **Swift toolchain required** - Need Swift 6.0+ toolchain installed (Xcode provides this on macOS)

### Future Improvements

To enable true cross-platform testing (including Linux):

**Option A: Extract pure logic to ContextifyPureCore**
```
app/Sources/
  ├── ContextifyPureCore/    # Zero UI dependencies
  │   ├── Database/          # Pure GRDB code
  │   ├── Parsers/          # Pure parsing logic
  │   └── Models/           # Data models only
  └── ContextifyCore/        # macOS-specific
      ├── HUDCore.swift
      ├── Security/
      └── Orchestration/
```

**Option B: Remove UI dependencies from ContextifyCore**
- Extract HUD logic to separate module
- Move security APIs to platform-specific wrapper
- Keep ContextifyCore as pure business logic

See `build/notes/swift-test-blockers-analysis.md` for detailed analysis.

## Performance Comparison

| Test Suite | Environment | Duration | Notes |
|------------|-------------|----------|-------|
| `swift test` | macOS, SPM | 0.4-2s | ⚡ 60x faster |
| `xcodebuild test` | macOS, Xcode | 25-40s | Full app bundle + simulator |
| Platform-specific tests | macOS, Xcode | 15-20s | Subset of all tests |

## CI Integration

### GitHub Actions (Current)

```yaml
# .github/workflows/test.yml
- name: Run SPM tests
  run: swift test --parallel
  # Only runs on macOS runners currently
```

### Future: Linux Support

Once ContextifyCore is fully platform-agnostic:

```yaml
strategy:
  matrix:
    os: [macos-latest, ubuntu-latest]

- name: Run cross-platform tests
  run: swift test
```

## Migration Guide

### Adding New Tests

**For platform-agnostic code** (pure Swift, Foundation, GRDB):
1. Create test file in `Tests/ContextifyCoreTests/`
2. Import only: `XCTest`, `Foundation`, `GRDB`, `@testable import ContextifyCore`
3. Run with `swift test`

**For macOS-specific code** (SwiftUI, AppKit, FoundationModels):
1. Create test file in `Contextify/ContextifyTests/`
2. Import as needed: `Contextify`, `FoundationModels`, etc.
3. Run with `bash scripts/xc.sh test`

### Moving Tests from Xcode to SPM

**Before moving a test:**

1. ✅ Check imports - only Foundation/GRDB/OSLog allowed
2. ✅ Verify no main app target dependency (`import Contextify`)
3. ✅ Confirm no macOS-specific APIs (security bookmarks, etc.)
4. ✅ Test in isolation with `swift test --filter TestName`

**Steps:**

```bash
# 1. Copy test to SPM
cp Contextify/ContextifyTests/YourTest.swift Tests/ContextifyCoreTests/

# 2. Verify it works
swift test --filter YourTest

# 3. If successful, remove from Xcode project
# (Keep original in Xcode project until verified in CI)
```

## Troubleshooting

### "Module 'ContextifyCore' not found"

```bash
# Clean and rebuild
swift package clean
swift build
swift test
```

### "Module was not compiled for testing"

This means `@testable import` failed. Check:
1. Is ContextifyCore built in Debug mode?
2. Is Enable Testability set? (should be automatic with SPM)

```bash
# Force Debug build
swift build -c debug
swift test
```

### "Cannot find type 'X' in scope"

Type `X` might be in the main app target, not ContextifyCore. Either:
1. Move the type to ContextifyCore
2. Keep the test in Xcode project (`Contextify/ContextifyTests/`)

### Tests pass with `swift test` but fail in CI

Likely a dependency issue. Check:
1. Are all test files added to git? (`git status Tests/`)
2. Is Package.swift committed? (`git diff Package.swift`)
3. Does CI have Swift toolchain? (macOS runners have it by default)

## References

- [Swift Test Blockers Analysis](../build/notes/swift-test-blockers-analysis.md)
- [Swift Package Manager Documentation](https://swift.org/package-manager/)
- [Swift Testing Best Practices](https://www.swiftbysundell.com/articles/writing-testable-code-when-using-swiftui/)
- [I made Xcode's tests 60x faster](https://justin.searls.co/posts/i-made-xcodes-tests-60-times-faster/)

## Status

**Current state:** ✅ SPM tests work on macOS
**Next milestone:** 🚧 Remove UI dependencies from ContextifyCore for Linux support
**Future:** 🎯 Full CI integration with Linux runners

Last updated: 2025-11-23
