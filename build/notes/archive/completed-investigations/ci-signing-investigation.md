# CI Signing Investigation Report

**Date:** 2025-11-08
**Branch:** `claude/investigate-ci-signing-issue-011CUw161KeBSGrPNYfZ4czf`
**Repository:** `banagale/contextify`
**Investigator:** Claude (AI Agent)

---

## Executive Summary

**Status:** 🟡 **Likely Working, Needs Verification**

The CI signing configuration appears to be correctly set up using **Xcode automatic signing** (the recommended approach for CI builds). However, **I was unable to verify this by triggering an actual build** due to:

1. Network restrictions in the Linux environment preventing GitHub CLI installation
2. No existing authentication credentials available
3. Proxy blocking package downloads

**Bottom Line:** The configuration *looks* correct based on git history and best practices research, but **you need to manually verify** that builds are actually succeeding.

---

## What I Found

### 1. Current CI Configuration ✅

**File:** `.github/workflows/on-demand-build.yml`

```yaml
- name: Build Contextify
  run: |
    bash scripts/xc.sh $BUILD_FLAGS ${{ inputs.configuration }} build
```

**File:** `scripts/xc.sh` (lines 147-149)

```bash
run_xcodebuild -project "$proj" -scheme "$scheme" \
  -configuration "$config" -destination "platform=macOS" \
  -derivedDataPath "$dd" "$action"
```

**Key observation:** No code signing parameters specified → Xcode handles signing automatically

**This is correct** for CI builds that don't require distribution signing.

---

### 2. Evolution of the Signing Approach

The current configuration is the result of **three iterations** over ~1 hour on Nov 4, 2025:

#### Iteration 1: Disable Signing (FAILED)
**Commit:** `49cd462` (Nov 4, 22:30)

```bash
CODE_SIGN_IDENTITY=""
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

**Problem:** Asset catalog compilation requires signing on Apple Silicon
**Result:** ❌ Build failed

---

#### Iteration 2: Ad-Hoc Signing (PARTIAL)
**Commit:** `fed250a` (Nov 4, 23:13)

```bash
CODE_SIGN_IDENTITY="-"  # Dash = ad-hoc signing
```

**Rationale:** Asset catalogs need some form of signing
**Result:** 🟡 Better, but still had issues

---

#### Iteration 3: Automatic Signing (CURRENT)
**Commit:** `686cabe` (Nov 4, 23:16)

**Change:** Removed all code signing overrides

**Commit message:**
> "Remove all code signing overrides and let Xcode handle signing automatically
> in CI environments. Xcode creates temporary signing certificates when needed,
> and overriding this was causing asset catalog compilation failures."

**Result:** ✅ Should work (needs verification)

---

### 3. Why This Approach Should Work

When no signing parameters are specified, Xcode:

1. Detects it's running in CI (no Developer ID certificates available)
2. Auto-generates a temporary ad-hoc signing identity
3. Signs the app bundle with this identity
4. Cleans up after the build completes

This is **Apple's recommended approach** for:
- ✅ PR verification builds
- ✅ Test runs
- ✅ CI compilation checks
- ✅ Apple Silicon compatibility (all code must be signed to execute)

This is **NOT suitable for**:
- ❌ App Store distribution
- ❌ Notarization
- ❌ DMG creation for public distribution

---

### 4. What I Could NOT Verify

Due to environment limitations, I could not:

- ❌ Install GitHub CLI (network proxy blocks downloads)
- ❌ Trigger a test build
- ❌ Check recent workflow run logs
- ❌ Verify actual signing behavior in CI

**This means my analysis is based on:**
- ✅ Git commit history
- ✅ Workflow file configuration
- ✅ Best practices research
- ✅ Apple documentation
- ❌ NOT on actual test results

---

## What You Need to Do

### Priority 1: Verify Current State (15 minutes)

Run the test script I created:

```bash
# From a macOS machine or environment with gh CLI access:
./scripts/test-ci-signing.sh
```

Or manually:

```bash
# 1. Install gh CLI if needed
brew install gh  # macOS
# or https://cli.github.com/ for other platforms

# 2. Authenticate
gh auth login

# 3. Check recent runs
gh run list --workflow=on-demand-build.yml --limit 5

# 4. Trigger a test build
gh workflow run on-demand-build.yml -f configuration=Debug

# 5. Watch the build
gh run watch

# 6. Check for signing errors in logs
gh run view --log | grep -iE "sign|certificate|error"
```

**What to look for:**

✅ **Success indicators:**
- Build completes successfully
- Log shows: "Built: .derived/Build/Products/Debug/Contextify.app"
- No "signing" or "certificate" errors
- May see: "Signing Identity: -" (ad-hoc) or similar

❌ **Failure indicators:**
- "No signing certificate found"
- "CompileAssetCatalogVariant failed"
- "CODE_SIGNING_REQUIRED but no identity"

---

### Priority 2: Document Results (10 minutes)

Based on the test results:

**If builds are succeeding:**
1. Update `build/docs/operations/ci-signing.md` (create if needed):

```markdown
# CI Code Signing

## Current Approach

For CI builds, we use **Xcode automatic signing**:
- No certificates required
- Works on GitHub Actions macOS runners
- Sufficient for build verification

Verified working as of: [date]
Last test run: [workflow URL]

## When Certificate-Based Signing is Needed

Only for distribution builds:
- App Store submission
- Notarized DMG creation
- Public distribution

See: scripts/SIGNING-SETUP.md for local signing setup.
```

2. Add CI status badge to README.md:

```markdown
[![macOS Build](https://github.com/banagale/contextify/workflows/macOS%20Build/badge.svg)](https://github.com/banagale/contextify/actions)
```

**If builds are failing:**
1. Capture the full error log
2. Check if the error is signing-related or something else
3. See "Troubleshooting" section below

---

### Priority 3: Commit and Push (5 minutes)

```bash
git add scripts/test-ci-signing.sh
git commit -m "ci: add CI signing verification script"
git push -u origin claude/investigate-ci-signing-issue-011CUw161KeBSGrPNYfZ4czf
```

---

## Troubleshooting Guide

### If Build Fails with "No signing certificate"

The automatic signing isn't working. Add explicit ad-hoc signing:

**File:** `scripts/xc.sh`

```diff
 run_xcodebuild -project "$proj" -scheme "$scheme" \
   -configuration "$config" -destination "platform=macOS" \
+  CODE_SIGN_IDENTITY="-" \
   -derivedDataPath "$dd" "$action"
```

### If Build Fails with "Asset catalog compilation failed"

This was the original issue. Check:

1. Is Xcode version correct? (Should be 26.0.1)
2. Are `-skipPackagePluginValidation` and `-skipMacroValidation` flags present?

**File:** `.github/workflows/on-demand-build.yml`

Should have these flags in the `macos-build.yml` workflow (not on-demand).

### If Build Succeeds but App Won't Launch

This is expected - CI builds are ad-hoc signed and may not launch. For distribution:

1. Use the local signing setup: `scripts/SIGNING-SETUP.md`
2. Build with: `make build-release && make sign-dmg`
3. For CI distribution, need to add certificates to GitHub Secrets

---

## GitHub Actions Workflow Analysis

### On-Demand Build Workflow

**File:** `.github/workflows/on-demand-build.yml`

**Purpose:** Remote builds for Linux/Claude Code Web users

**Configuration:**
- Runner: `macos-15`
- Xcode: 26.0.1 (set explicitly)
- Formatter: xcbeautify with GitHub Actions renderer
- Inputs:
  - `configuration`: Debug or Release
  - `skip_launch`: Skip opening app after build (default: true)
  - `enable_dev_mode`: Enable developer mode (default: false)

**Current issues identified:**
- ❌ No actual verification that builds are succeeding
- ❌ No artifacts uploaded (changed in commit `81400de`)
- ❌ No signing verification in the workflow

**Recommendation:** Re-enable artifact upload for build logs:

```yaml
- name: Upload build logs
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: build-logs-${{ inputs.configuration }}
    path: build-output.log
    retention-days: 7
```

---

### Main CI Workflow

**File:** `.github/workflows/macos-build.yml`

**Purpose:** PR/push verification on `main` branch

**Configuration:**
- Runner: `macos-15`
- Uses `xcpretty` instead of `xcbeautify`
- Has `-skipPackagePluginValidation` and `-skipMacroValidation` flags
- Archives DerivedData to artifacts

**Key difference:** Uses direct `xcodebuild` command instead of `scripts/xc.sh`

**Potential issue:** Inconsistency between workflows. Should both use the same build method.

---

## Recommended Next Steps (Beyond Verification)

### 1. Unify Build Commands (1 hour)

Both workflows should use `scripts/xc.sh` for consistency:

**File:** `.github/workflows/macos-build.yml`

```diff
- xcodebuild \
-   -project Contextify/Contextify.xcodeproj \
-   -scheme Contextify \
-   -configuration Debug \
-   -destination 'platform=macOS' \
-   -derivedDataPath build/DerivedData \
-   -skipPackagePluginValidation \
-   -skipMacroValidation \
-   build | xcpretty || exit ${PIPESTATUS[0]}
+ CTX_NO_RUN=1 bash scripts/xc.sh Debug build
```

### 2. Add Signing Verification Step (30 minutes)

Add to both workflows after build:

```yaml
- name: Verify Code Signature
  run: |
    codesign -dv .derived/Build/Products/${{ inputs.configuration }}/Contextify.app
    codesign --verify --verbose .derived/Build/Products/${{ inputs.configuration }}/Contextify.app
```

This will show what identity was used and verify the signature is valid.

### 3. Re-enable Build Artifacts (15 minutes)

Commit `81400de` removed artifact uploads to speed up builds. Re-add them with short retention:

```yaml
- name: Upload build artifacts
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: build-logs-${{ github.run_number }}
    path: |
      build-output.log
      build/logs/
    retention-days: 3  # Short retention to save storage
```

Only upload on failure to save bandwidth.

### 4. Add Distribution Signing Workflow (4-6 hours)

**When:** Before App Store submission or public DMG release

**Create:** `.github/workflows/release.yml`

**Requires:**
- GitHub Secrets setup (certificates, notarization credentials)
- Separate workflow triggered only on tags (`v*`)
- Follow guide in `scripts/SIGNING-SETUP.md` for credentials

**Reference:** See my earlier report section "Option A: Distribution Signing Workflow"

---

## What I've Created for You

### 1. Test Script

**File:** `scripts/test-ci-signing.sh`

**Purpose:** Easy way to trigger and monitor CI builds with signing verification

**Usage:**
```bash
./scripts/test-ci-signing.sh
```

**Features:**
- Checks gh CLI installation and authentication
- Shows recent workflow runs
- Triggers new build interactively
- Watches build in real-time
- Searches logs for signing errors
- Opens browser to workflow run

### 2. This Report

**File:** `/tmp/ci-signing-investigation-report.md`

**Purpose:** Comprehensive analysis and action plan

**Sections:**
- Current configuration analysis
- Historical evolution of signing approach
- Verification instructions
- Troubleshooting guide
- Recommended improvements

---

## Key Questions to Answer

After running the verification:

1. **Do CI builds currently succeed?**
   - Yes → Document the working state, add badge, done
   - No → Follow troubleshooting guide

2. **What signing identity is being used?**
   - Check with: `codesign -dv Contextify.app`
   - Expected: "Identifier=dev.contextify.Contextify" with ad-hoc signing

3. **Do you need distribution signing in CI?**
   - No → Current setup is fine
   - Yes → Follow distribution workflow setup

4. **Should both workflows use the same build command?**
   - Recommendation: Yes, use `scripts/xc.sh` everywhere for consistency

---

## Confidence Assessment

**Based on analysis:**
- Configuration appears correct: **High confidence (90%)**
- Builds are succeeding: **Medium confidence (70%)**
  - Last CI-related commit was 4 days ago
  - No follow-up fixes suggests it's working
  - But no actual test results available

**Verification required:** Yes - run `scripts/test-ci-signing.sh` to confirm

---

## Summary of Findings

### ✅ What's Good

1. **Current configuration follows best practices**
   - Xcode automatic signing is the recommended approach
   - No unnecessary complexity
   - Matches Apple's CI guidance

2. **Evolution shows good debugging**
   - Tried multiple approaches systematically
   - Commit messages explain rationale
   - Landed on the correct solution

3. **Workflows are well-configured**
   - Correct runner (macos-15)
   - Correct Xcode version (26.0.1)
   - Good error reporting with xcbeautify

### 🟡 What Needs Verification

1. **Builds actually succeed**
   - No test results available
   - Need manual verification

2. **Signing identity is correct**
   - Should be ad-hoc ("-")
   - Verify with codesign command

### ❌ What's Missing

1. **CI signing documentation**
   - No docs explaining the approach
   - Future maintainers won't know why there are no signing parameters

2. **Build status visibility**
   - No badge in README
   - Hard to see if CI is passing

3. **Workflow inconsistency**
   - `macos-build.yml` uses direct xcodebuild
   - `on-demand-build.yml` uses scripts/xc.sh
   - Should be unified

4. **No signing verification step**
   - Workflows should verify the signature after build
   - Helps catch signing issues early

---

## Action Plan Summary

**Immediate (Today):**
1. ✅ Run `./scripts/test-ci-signing.sh` to verify builds work
2. ✅ Document results in `build/docs/operations/ci-signing.md`
3. ✅ Add CI status badge to README

**Short-term (This Week):**
4. Unify build commands across workflows
5. Add signing verification step to workflows
6. Re-enable artifact upload on failure

**Long-term (Before Release):**
7. Set up distribution signing workflow (if needed)
8. Test App Store submission process
9. Document complete release workflow

---

## References

### Internal Documentation
- `scripts/SIGNING-SETUP.md` - Local signing setup guide
- `build/notes/TODOS.md` - App Store readiness tasks
- `scripts/xc.sh` - Build script (no signing parameters)
- `.github/workflows/on-demand-build.yml` - Remote build workflow
- `.github/workflows/macos-build.yml` - Main CI workflow

### Git Commits
- `686cabe` - Current approach (remove signing overrides)
- `fed250a` - Previous approach (ad-hoc signing)
- `49cd462` - First attempt (disable signing completely)

### External Resources
- [GitHub: macOS 26 runners](https://github.blog/changelog/2025-09-11-actions-macos-26-image-now-in-public-preview/)
- [Stack Overflow: CODE_SIGN_IDENTITY](https://stackoverflow.com/questions/9264727/code-sign-identity-parameter-for-xcodebuild-xcode-4)
- [Apple: Xcode CI best practices](https://developer.apple.com/documentation/xcode/running-automated-tests)

---

## Limitations of This Investigation

What I could analyze:
- ✅ Git history and commit messages
- ✅ Workflow YAML configuration
- ✅ Build scripts
- ✅ Best practices research
- ✅ Apple and GitHub documentation

What I could NOT verify:
- ❌ Actual workflow run results
- ❌ Build logs from recent runs
- ❌ Signing identity used in CI
- ❌ Whether builds are actually succeeding

**This is why manual verification is critical.**

---

## Contact / Questions

If you encounter issues during verification:

1. **Check the workflow run logs** for detailed error messages
2. **Copy the full error** (not just a snippet)
3. **Include the workflow URL** for context
4. **Note the Xcode version** being used in CI

Common issues and solutions are in the Troubleshooting section above.

---

**End of Report**

Generated: 2025-11-08
By: Claude (AI Agent)
For: Rob Banagale / Contextify Project
