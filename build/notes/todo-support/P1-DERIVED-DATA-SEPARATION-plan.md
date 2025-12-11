---
todo_id: P1-DERIVED-DATA-SEPARATION
title: Separate Derived Data Directories by Distribution
type: plan
date: 2025-12-06
status: active
description: Fix release build crash caused by shared derived data contamination between App Store and DMG builds
---

# Derived Data Separation Plan v2

**Status:** Ready for implementation
**Risk Level:** Low
**Estimated Effort:** 45-60 minutes

---

## Problem Statement

The crash at launch with "different Team IDs" occurs because App Store and DMG builds share the same derived data directory (`.derived`). When building both distributions sequentially, Xcode's incremental build may not re-sign cached frameworks, causing code signature mismatches.

**Evidence from crash report:**
```
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: code signature not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

The path explicitly shows dyld loading from `.derived/Build/Products/Release/`, confirming the shared derived data root is the contamination vector.

---

## Solution Overview

Separate derived data directories by distribution type:
- `.derived-dmg` for DMG/direct distribution builds
- `.derived-appstore` for App Store builds

This eliminates cross-contamination and makes builds predictable.

---

## Implementation Plan

### Phase 1: Core Script Changes (Critical)

#### 1.1 `scripts/xc.sh` - Primary Fix

**Current state (problematic):**
```bash
# Line 10
dd=".derived"  # Shared by all distributions
```

**Required changes:**

1. **Remove the initial `dd` assignment at line 10** - delete or comment out `dd=".derived"`

2. **Add distribution-specific assignment AFTER argument parsing** (after the `for arg` loop, around line 127):
```bash
# Set derived data path based on distribution (MUST be after argument parsing)
dd=".derived-${dist}"  # Results in .derived-dmg or .derived-appstore
```

3. **Update user-facing message at line 140:**
```bash
# Change from:
echo "      • Clean build cache (.derived/)"
# To:
echo "      • Clean build cache ($dd/)"
```

**Why this ordering matters:** The `$dist` variable is set during `parse_arg()`. If `dd` is set before parsing completes, it will use the wrong default. By setting `dd` immediately after the parsing loop, all subsequent code paths (`clean`, `test`, `build`, `dev-archive`, etc.) will use the correct distribution-specific path.

#### 1.2 `scripts/sign_and_notarize.py` - DMG-Only Script

**Current state:**
```python
# Line 27
DERIVED = ROOT / ".derived/Build/Products/Release"
```

**Required changes:**

1. **Change to explicit DMG path with environment override:**
```python
# Line 27 - Replace with:
DERIVED_ROOT = Path(os.environ.get("CONTEXTIFY_DERIVED_ROOT", ".derived-dmg"))
DERIVED = ROOT / DERIVED_ROOT / "Build/Products/Release"
```

2. **Improve error message (around line 241):**
```python
# Change from:
sys.exit(f"✖ Bundle not found: {APP_BUNDLE}\n"
         f"   Run: bash scripts/xc.sh build\n"
         f"   Or build in Xcode with Release configuration")
# To:
sys.exit(f"✖ Bundle not found: {APP_BUNDLE}\n"
         f"   Run: bash scripts/xc.sh --dist=dmg Release build\n"
         f"   Or build in Xcode with the 'Contextify' scheme (not 'Contextify AppStore')")
```

**Rationale:** The environment variable provides an escape hatch for CI experiments without adding CLI complexity. The improved error message prevents confusion when someone runs this after an App Store-only build.

#### 1.3 `scripts/sparkle/keygen.sh` - Sparkle Key Generation

**Current state:**
```bash
# Lines 22-23
if [[ -f "$PROJECT_ROOT/.derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" ]]; then
    echo "$PROJECT_ROOT/.derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

**Required changes:**

1. **Update primary search path:**
```bash
if [[ -f "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" ]]; then
    echo "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

2. **Update find fallback (line 29):**
```bash
derived_sparkle=$(find "$PROJECT_ROOT/.derived-dmg" -path "*/artifacts/*/bin/generate_keys" -type f 2>/dev/null | head -1)
```

3. **Improve error message (lines 58-65):**
```bash
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "Error: Sparkle binaries not found."
  echo ""
  echo "Options to install:"
  echo "  1. Build the DMG scheme first: bash scripts/xc.sh --dist=dmg build"
  echo "  2. Install via Homebrew: brew install --cask sparkle"
  echo "  3. Download from: https://github.com/sparkle-project/Sparkle/releases"
  echo ""
  exit 1
fi
```

**Important:** Do NOT add `.derived` as a fallback. Failing fast when `.derived-dmg` doesn't exist is safer than accidentally finding stale binaries.

#### 1.4 `scripts/sparkle/sign.sh` - Sparkle DMG Signing

**Same pattern as keygen.sh:**

1. **Update primary search path (lines 39-40):**
```bash
if [[ -f "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" ]]; then
    echo "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

2. **Update find fallback (line 46):**
```bash
derived_sparkle=$(find "$PROJECT_ROOT/.derived-dmg" -path "*/artifacts/*/bin/sign_update" -type f 2>/dev/null | head -1)
```

3. **Update error message (line 76-77):**
```bash
echo "Error: Sparkle binaries not found."
echo "Build the DMG scheme first: bash scripts/xc.sh --dist=dmg build"
```

---

### Phase 2: Utility Scripts

#### 2.1 `scripts/compare-builds.sh`

This is a development utility for verifying build parity. Update all hardcoded paths:

```bash
# Line 15: Change
rm -rf .derived
# To:
rm -rf .derived-dmg

# Line 26: Change
rm -rf .derived
# To:
rm -rf .derived-dmg

# Lines 20-23, 38-41: Change all occurrences of
.derived/Build/Products/Debug/Contextify.app
# To:
.derived-dmg/Build/Products/Debug/Contextify.app
```

#### 2.2 `scripts/logging/monitor-automated-test.sh`

**Line 83:** Update default app path:
```bash
# Change from:
open -a "${APP_PATH:-/Users/rob/code/projects/contextify/.derived/Build/Products/Debug/Contextify.app}"
# To:
open -a "${APP_PATH:-/Users/rob/code/projects/contextify/.derived-dmg/Build/Products/Debug/Contextify.app}"
```

#### 2.3 QA Test Suite

The automated QA suite has hardcoded paths that need updating.

**`scripts/qa/lib/common.sh`** - Update default app paths (lines 13-14):
```bash
# Change from:
DMG_APP_PATH="${DMG_APP_PATH:-$REPO_ROOT/.derived/Build/Products/Debug/Contextify.app}"
APPSTORE_APP_PATH="${APPSTORE_APP_PATH:-$REPO_ROOT/.derived/Build/Products/Debug/Contextify AppStore.app}"

# To:
DMG_APP_PATH="${DMG_APP_PATH:-$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app}"
APPSTORE_APP_PATH="${APPSTORE_APP_PATH:-$REPO_ROOT/.derived-appstore/Build/Products/Debug/Contextify AppStore.app}"
```

**`scripts/qa/lib/common.sh`** - Update error messages in `launch_dmg_app` and `launch_appstore_app`:
```bash
# Change from:
log_error "Build with: bash scripts/xc.sh build"
# To:
log_error "Build with: bash scripts/xc.sh --dist=dmg build"

# Change from:
log_error "Build with: bash scripts/xc.sh --dist=appstore Debug build"
# To (no change needed, already correct)
```

**`scripts/qa/README.md`** - Update build commands in documentation:
```markdown
# Change from:
- Build with: `bash scripts/xc.sh build`
# To:
- Build with: `bash scripts/xc.sh --dist=dmg build`
```

---

### Phase 3: Configuration Files

#### 3.1 `.gitignore`

```gitignore
# Line 35: Change from
.derived/

# To (add both patterns)
.derived-dmg/
.derived-appstore/
```

#### 3.2 `Makefile`

The current Makefile has a pre-existing inconsistency: it cleans `build/DerivedData` (CI path) but not `.derived` (local path).

**Fix to cover all cases:**
```makefile
# Line 14-15: Change from
clean:
	rm -rf build/DerivedData build/DerivedData-beta

# To:
clean:
	rm -rf .derived-dmg .derived-appstore build/DerivedData build/DerivedData-beta
```

This ensures `make clean` clears both local development caches and CI caches.

---

### Phase 4: Documentation Updates

**Priority 1 (Agent-consumed, update with code changes):**

These files may be consumed by automated tools/agents and should be updated in the same PR:

| File | Line | Change |
|------|------|--------|
| `AGENTS.md` | 19 | `.derived/Build/Products/Debug/` → `.derived-dmg/Build/Products/Debug/` |
| `.claude/commands/run.md` | 6 | `open .derived/Build/Products/Debug/Contextify.app` → `open .derived-dmg/Build/Products/Debug/Contextify.app` |

**Priority 2 (Human docs, can batch update):**

| File | Lines | Change |
|------|-------|--------|
| `build/docs/guides/DEVELOPMENT.md` | 311-312 | Update Debug/Release paths |
| `scripts/RELEASE.md` | 115, 166-167, 184, 332 | Update all path references |
| `scripts/DATABASE-MANAGEMENT.md` | 148 | Update debug app path |
| `scripts/logging/README.md` | 540 | Update debug app path |

---

### Phase 5: One-Time Migration

After implementing all changes, perform cleanup:

```bash
# Remove old shared derived data directory
rm -rf .derived

# Verify it's gone
ls -la .derived 2>&1 | grep "No such file"
```

**Note:** The old `.derived` directory will be orphaned if not removed. It won't cause problems but wastes disk space.

---

## Verification Steps

Execute these steps after implementation to confirm the fix works:

### Step 1: Clean Slate
```bash
rm -rf .derived .derived-dmg .derived-appstore
```

### Step 2: Build App Store
```bash
bash scripts/xc.sh --dist=appstore Release build
ls .derived-appstore/Build/Products/Release/
# Should show: Contextify AppStore.app (NO Sparkle.framework)
```

### Step 3: Build DMG
```bash
bash scripts/xc.sh --dist=dmg Release build
ls .derived-dmg/Build/Products/Release/
# Should show: Contextify.app (WITH Sparkle.framework)
```

### Step 4: Verify Isolation
```bash
# Should see TWO separate directories
ls -la | grep derived
# .derived-appstore
# .derived-dmg

# Verify no shared .derived exists
ls .derived 2>&1 | grep "No such file"
```

### Step 5: Full Release Build
```bash
bash scripts/release/build.sh 1.0.1 --no-notarize
```

### Step 6: Launch Test
```bash
# Should launch without Team ID crash
open .derived-dmg/Build/Products/Release/Contextify.app
```

### Step 7: Sparkle Script Test
```bash
# Should find binaries in .derived-dmg
./scripts/sparkle/sign.sh dist/Contextify-1.0.1.dmg
```

---

## Files Changed Summary

### Code Changes (9 files)

| File | Type | Changes |
|------|------|---------|
| `scripts/xc.sh` | Core | Remove initial `dd`, set after parsing, update message |
| `scripts/sign_and_notarize.py` | Core | Use `.derived-dmg` with env override, improve error |
| `scripts/sparkle/keygen.sh` | Script | Update search paths, improve error |
| `scripts/sparkle/sign.sh` | Script | Update search paths, improve error |
| `scripts/compare-builds.sh` | Script | Update all hardcoded paths |
| `scripts/logging/monitor-automated-test.sh` | Script | Update default app path |
| `scripts/qa/lib/common.sh` | QA | Update DMG_APP_PATH, APPSTORE_APP_PATH defaults |
| `scripts/qa/README.md` | QA | Update build commands in documentation |
| `Makefile` | Config | Clean both local and CI derived data |

### Configuration Changes (1 file)

| File | Changes |
|------|---------|
| `.gitignore` | Add `.derived-dmg/` and `.derived-appstore/` |

### Documentation Changes (7 files)

| File | Priority |
|------|----------|
| `AGENTS.md` | High (agent-consumed) |
| `.claude/commands/run.md` | High (agent-consumed) |
| `build/docs/guides/DEVELOPMENT.md` | Medium |
| `scripts/RELEASE.md` | Medium |
| `scripts/DATABASE-MANAGEMENT.md` | Medium |
| `scripts/logging/README.md` | Medium |

**Total: 17 files**

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missed hardcoded path | Low | Medium | Thorough grep audit completed; verification steps catch issues |
| `dd` used before `dist` set | Low | High | Explicit ordering in implementation; no early `dd` uses found |
| Sparkle scripts fail after migration | Low | Low | Clear error messages guide user to build DMG first |
| Disk space doubles | Medium | Low | Derived data is scratch; `make clean` removes both |
| Stale docs confuse users | Medium | Low | Priority docs updated with code; others can follow |

---

## Follow-Up Tasks (Post-Implementation)

These are not blockers but worth investigating:

1. **Inspect LC_RPATH entries in shipped DMG:**
   - Verify no absolute paths to DerivedData are baked into the binary
   - Command: `otool -l Contextify.app/Contents/MacOS/Contextify | grep -A2 LC_RPATH`

2. **Verify Sparkle exclusion from App Store scheme:**
   - Confirm Sparkle is entirely absent from App Store target's dependency graph
   - Check: `ls .derived-appstore/Build/Products/Release/*.app/Contents/Frameworks/`

3. **Audit `scripts/release.py`:**
   - Verify it relies entirely on `xc.sh` and `sign_and_notarize.py` for paths
   - No direct `.derived` references found in audit, but worth confirming

---

## Summary

This plan addresses the root cause (shared derived data) with a clean architectural fix (per-distribution directories). Key refinements from review:

1. **`dd` assignment ordering is critical** - must be after argument parsing
2. **No fallbacks to `.derived`** - fail fast is safer than silent contamination
3. **Agent-consumed docs are higher priority** - AGENTS.md and .claude/commands affect automation
4. **Full separation over shared SourcePackages** - simplicity and safety over minor disk savings
5. **Makefile should clean all caches** - both local and CI derived data

The implementation is mechanical and low-risk. Most changes are find-and-replace operations with clear verification steps.
