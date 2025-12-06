# Testing Strategy - AI Agent Guidelines

**Purpose:** Clear testing rules for automated agents working on Contextify
**Audience:** Claude Code, Cursor, other AI coding assistants
**Last Updated:** 2025-11-23

---

## Core Principle

**ONE canonical test suite: Swift Package Manager (SPM)**

All test validation uses `swift test`. Period.

---

## Quick Reference for AI Agents

### Before ANY Merge/PR

```bash
# Required validation (run sequentially):
swift test                    # All tests must pass (currently 46 tests)
bash scripts/xc.sh build      # Build must succeed with 0 warnings
```

**Both must pass.** No exceptions.

### When Writing New Tests

**Always use SPM test directory:**
```
Tests/ContextifyCoreTests/YourNewTest.swift
```

**Never add tests to:**
```
Contextify/ContextifyTests/  ❌ Xcode test directory (READ-ONLY - deprecated)
```

**Critical:** Treat `Contextify/ContextifyTests/` as read-only. You may only:
- Delete tests (after migrating to SPM)
- Move tests out (to SPM location)
- **NEVER** add new tests or modify existing tests in place

This rule prevents the configuration split that caused commit 9936b081 to fail.

---

## Red-Green Testing (Required for New Features)

### The Process

**RED phase:** Write a test that COMPILES and FAILS on an assertion.
- ❌ Wrong: Test fails because method doesn't exist (compile error)
- ✅ Right: Test compiles, runs, and fails on `XCTAssertEqual` or similar

**GREEN phase:** Write minimum code to make the test pass.

**REFACTOR phase:** Clean up while keeping tests green.

### What Makes a Test Meaningful

Before writing implementation, ask: "What would this test catch if the implementation were wrong?"

**Superficial test (bad):**
```swift
func testMarkProjectActivated_ReturnsResult() throws {
  let result = try orchestrator.markProjectActivated(projectId: id, timestamp: ts)
  XCTAssertNotNil(result)  // ← Passes if method returns anything
}
```

**Meaningful test (good):**
```swift
func testMarkProjectActivated_ComputesUnreadCountRelativeToTimestamp() throws {
  // Create entry BEFORE timestamp
  // Create entry AFTER timestamp
  let result = try orchestrator.markProjectActivated(projectId: id, timestamp: ts)
  XCTAssertEqual(result.unreadCount, 1)  // ← Only newer entry is unread
}
```

### Required Test Scenarios

**For any method claiming to be "atomic" or "transactional":**
- Test rollback on failure (inject error mid-operation, verify no partial state)

**For any method with boundary conditions:**
- Test behavior at the boundary (timestamp exactly equal, empty input, etc.)

**For any method returning computed values:**
- Test that computation is correct, not just that a value is returned

### Specify Scenarios Before Implementation

Before writing code, list test scenarios:
```
- Happy path: normal activation updates all state
- Boundary: entries exactly at timestamp boundary
- Failure: rollback when middle operation fails
- Edge: non-existent project ID
```

Then write tests for ALL of them. Don't cherry-pick the easy ones.

### Skepticism Checklist

After writing tests, answer honestly:
- [ ] Would these tests fail if I returned hardcoded values?
- [ ] Do I test failure modes, not just success paths?
- [ ] If I claim "atomic", do I have a rollback test?
- [ ] What behavior is NOT covered by these tests?

---

## Test Creation Rules

### 1. Where to Put Tests

**Database/Core Logic:**
```
Tests/ContextifyCoreTests/DatabaseTests.swift
Tests/ContextifyCoreTests/RepositoryTests.swift
Tests/ContextifyCoreTests/OrchestratorTests.swift
```

**Parsers:**
```
Tests/ContextifyCoreTests/TranscriptParserTests.swift
Tests/ContextifyCoreTests/MetadataParserTests.swift
```

**Architectural (layer boundaries):**
```
Tests/ContextifyCoreTests/ArchitecturalTests.swift
```

### 2. Test Dependencies

Available in SPM tests:
- XCTest
- GRDB
- SwiftSyntax (for architectural tests)
- SwiftParser (for architectural tests)
- ContextifyCore (via `@testable import`)

### 3. Naming Convention

```swift
// Pattern: test<FeatureName><Scenario>
func testHooverEnginePreviewLimit() throws {
  // Arrange
  // Act
  // Assert
}

// Edge cases: test<FeatureName><EdgeCase>
func testEntriesAfterCursorHandlesEdgeCaseAtSameTimestamp() throws {
  // ...
}
```

---

## Validation Workflow (For AI Agents)

### Scenario 1: Bug Fix

```
1. Write fix
2. Add regression test (if missing)
3. Run: swift test
4. Verify: All tests pass
5. Run: bash scripts/xc.sh build
6. Verify: 0 warnings
7. Commit
```

### Scenario 2: New Feature

```
1. Write feature code
2. Write tests for feature
3. Run: swift test
4. Verify: All tests pass (including new ones)
5. Run: bash scripts/xc.sh build
6. Verify: 0 warnings
7. Commit
```

### Scenario 3: Test-Only Changes

```
1. Modify tests
2. Run: swift test
3. Verify: All tests pass
4. Commit
```

**No build verification needed for test-only changes.**

### Scenario 4: Branch Merge (Most Critical)

```
1. Merge branch
2. Run: swift test
3. If FAILS:
   - Fix issues
   - Run swift test again
   - Repeat until pass
4. Run: bash scripts/xc.sh build
5. If WARNINGS:
   - Fix warnings
   - Rebuild
   - Repeat until 0 warnings
6. Push to origin
```

**Never push a merge that fails tests or has warnings.**

---

## Current Test Count Baseline

**Total:** 46 SPM tests (as of 2025-11-23)

```
ArchitecturalTests:      5 tests
RepositoryTests:         5 tests
DatabaseTests:          21 tests
MetadataParserTests:     6 tests
ProjectIdentityTests:   13 tests
TranscriptParserTests:   3 tests
```

**Success criteria:** All 46/46 must pass

---

## Common Mistakes to Avoid

### ❌ Don't Do This

```bash
# Wrong test location
touch Contextify/ContextifyTests/MyNewTest.swift

# Wrong validation command
make test  # Xcode tests (deprecated for validation)

# Partial validation
swift test  # ← Only running tests, skipping build check

# Ignoring warnings
bash scripts/xc.sh build  # Has warnings, but merging anyway
```

### ✅ Do This Instead

```bash
# Correct test location
touch Tests/ContextifyCoreTests/MyNewTest.swift

# Correct validation commands
swift test && bash scripts/xc.sh build

# Complete validation
swift test                    # Check tests
bash scripts/xc.sh build      # Check build + warnings

# Zero tolerance for warnings
# Fix all warnings before merge
```

---

## Why SPM Only?

### Technical Reasons

1. **SwiftSyntax dependency** - Required for architectural tests, only works in SPM
2. **Simpler configuration** - One Package.swift vs complex Xcode project
3. **Faster builds** - SPM is optimized for testing
4. **CI/CD friendly** - GitHub Actions uses SPM
5. **Cross-platform** - SPM works on Linux (future-proofing)

### Practical Reasons

1. **One source of truth** - No duplicate test files
2. **No configuration drift** - Package.swift is version controlled
3. **Clear expectations** - One command to rule them all

---

## Integration with Existing Workflows

### Git Hooks (Pre-commit)

Already configured: `.githooks/pre-commit`

Runs on staged changes to `Contextify/`:
```bash
bash scripts/xc.sh build  # Headless build, fails on errors
```

**Enhancement needed:** Add `swift test` to pre-commit hook

**Escape hatch for WIP commits:**
```bash
# Skip pre-commit hook for work-in-progress commits
git commit --no-verify

# Or set environment variable
CTXFY_SKIP_TESTS_PRECOMMIT=1 git commit
```

**Important:** Use `--no-verify` only for local WIP. **Never** push or merge without passing tests + build.

### GitHub Actions

Already runs: `.github/workflows/build.yml`

**Should verify:**
```bash
swift test                    # ← Add this
bash scripts/xc.sh build
```

### Zero Warnings Policy

**Current baseline: 0 warnings** (as of commit 3d0b987c after @discardableResult fix)

**Policy:** Any new warning must be fixed before merge.

**What counts as a warning:**
- Compiler warnings from your code
- Warnings from `bash scripts/xc.sh build` output

**What doesn't count:**
- Package resolution messages (not actual warnings)
- Informational logs from build system

**If warnings appear:**
1. Check if they're from your changes (new code)
2. Fix immediately - do not commit code with warnings
3. If from dependencies: Document in a tracked issue, but don't block merge if unavoidable

**Enforcement:** GitHub Actions will fail builds with warnings (Phase 2 implementation)

---

## FAQ for AI Agents

**Q: When should I run tests?**
A: After every code change, before every commit, before every merge.

**Q: What if tests fail?**
A: Fix the failure. Do not commit broken tests.

**Q: What if build has warnings?**
A: Fix the warnings. Zero warnings policy (see CLAUDE.md).

**Q: Can I use `make test`?**
A: No. Use `swift test` only. `make test` has Xcode configuration issues.

**Q: Where do I add architectural tests?**
A: `Tests/ContextifyCoreTests/ArchitecturalTests.swift` - they need SwiftSyntax.

**Q: What about UI tests?**
A: UI tests live in `Contextify/ContextifyUITests/` and are run manually via Xcode. They are **not** part of merge gating. In future, they may be wired into a separate non-blocking CI job.

**Q: How do I run a single test?**
A: `swift test --filter testNameHere`

**Q: How do I run tests in parallel?**
A: SPM does this automatically. Just run `swift test`.

**Q: What if I need to add a test dependency?**
A: Add to `Package.swift` dependencies and to `ContextifyCoreTests` target.

---

## CLAUDE.md Integration

**Replace current testing section with:**

```markdown
## Testing

**Command:** `swift test`
**Baseline:** 46/46 tests passing
**Policy:** All tests must pass before merge, zero warnings required

**Test Location:** `Tests/ContextifyCoreTests/`
**Build Verification:** `bash scripts/xc.sh build` (must show 0 warnings)

**Before any merge:**
1. Run `swift test` - all 46 tests must pass
2. Run `bash scripts/xc.sh build` - must succeed with 0 warnings
3. Fix any failures or warnings before pushing

**See:** `/path/to/TESTING-STRATEGY.md` for complete guidelines
```

---

## Action Items (Implementation)

### Immediate (Before Next Merge)

1. ✅ Document SPM-only testing strategy (this file)
2. ⬜ Update CLAUDE.md with concise testing section
3. ⬜ Add to pre-commit hook: `swift test` validation
4. ⬜ Update GitHub Actions to run `swift test`

### Short-term (Next Sprint)

5. ⬜ Add test count assertion to prevent regression
6. ⬜ Create test coverage report baseline
7. ⬜ Document architectural test patterns

### Long-term (Future)

8. ⬜ Migrate remaining Xcode tests to SPM
9. ⬜ Remove Xcode test target entirely
10. ⬜ Add performance benchmarks

---

## Summary for AI Agents

**Three rules:**

1. **Write tests in** `Tests/ContextifyCoreTests/`
2. **Validate with** `swift test && bash scripts/xc.sh build`
3. **Never merge** if tests fail or warnings exist

That's it. Everything else is detail.
