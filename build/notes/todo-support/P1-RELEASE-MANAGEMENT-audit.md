---
todo_id: P1-RELEASE-MANAGEMENT
title: Release Management Audit
type: investigation
date: 2025-11-27
status: complete
description: Audit of existing release files and reorganization plan. Implementation complete - see releases/ directory.
---

# Release Management Audit

**Date:** November 27, 2025
**Purpose:** Audit existing release-related files for reorganization

**Status:** Complete - reorganization implemented in `releases/` directory

---

## Current File Inventory

### Release Documentation

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| `RELEASE-CHECKLIST.md` | `build/docs/operations/release/` | Master checklist | ✅ Good, recently updated |
| `README.md` | `build/docs/operations/release/` | Release operations index | ✅ Good |
| `sparkle-updates.md` | `build/docs/operations/release/` | Sparkle auto-updates | ✅ Good |
| `notarization-setup.md` | `build/docs/operations/release/` | Notarization credentials | ✅ Good |
| `notarization-success.md` | `build/docs/operations/release/` | Notarization verification | ✅ Good |
| `release-build-verification.md` | `build/docs/operations/release/` | Build validation | ✅ Good |
| `release-readiness.md` | `build/docs/operations/release/` | Pre-release checklist | ⚠️ May overlap with CHECKLIST |
| `RELEASE.md` | `scripts/` | DMG release guide | ⚠️ Overlaps with operations docs |
| `APP-STORE-SUBMISSION.md` | `build/docs/guides/` | App Store process | ✅ Good, recently updated |

### App Store Metadata

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| `README.md` | `appstore-metadata/` | Metadata overview | ✅ Good, recently updated |
| `metadata.json` | `appstore-metadata/` | Structured metadata | ✅ Good |
| `fastlane/` | `appstore-metadata/` | Fastlane integration | ✅ Good |
| `screenshots/` | `appstore-metadata/` | Screenshot workflow | ✅ Good pattern |
| `app-previews/` | `appstore-metadata/` | Preview videos | ⚠️ Mostly placeholders |
| `review-materials/` | `appstore-metadata/` | Review materials | ✅ Good, recently created |
| `FEATURE-BENEFIT-MAPPING.md` | `appstore-metadata/` | Marketing content | ⚠️ Marketing, not release |
| `REVIEW-ANALYSIS.md` | `appstore-metadata/` | Competitive analysis | ⚠️ Marketing, not release |

### Release Artifacts/Tracking

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| `README.md` | `build/releases/v1.0.0/` | Release summary | ✅ Good start |
| `metadata-v1.0.0.json` | `build/releases/v1.0.0/` | Metadata snapshot | ✅ Good |
| `app-store-submission-v1.0.0.png` | `build/releases/v1.0.0/` | Submission screenshot | ✅ Good |

### Scripts

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| `release.py` | `scripts/` | DMG automation | ✅ Good |
| `sign_and_notarize.py` | `scripts/` | Signing/notarization | ✅ Good |
| `xc.sh` | `scripts/` | Build wrapper | ✅ Good |
| `sparkle/sign.sh` | `scripts/sparkle/` | Sparkle signing | ✅ Good |
| `sparkle/keygen.sh` | `scripts/sparkle/` | Key management | ✅ Good |
| `deploy-website.sh` | `scripts/` | Website deployment | ✅ Good |

### Website

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| `appcast.xml` | `website/` | Sparkle feed | ✅ Good |
| `1.0.0.html` | `website/release-notes/` | Release notes | ✅ Good |
| `sample-data.zip` | `website/review-4a125b1d/` | Review materials | ✅ Good |

### AGENTS.md (Main Config)

| Section | Status | Notes |
|---------|--------|-------|
| `## Releases` | ✅ Good | Recently updated, comprehensive |
| Quick Commands | ✅ Good | Correct commands |
| Handling Rejections | ✅ Good | Clear workflow |
| Version Backdating | ✅ Good | Edge case covered |

---

## Issues Identified

### 1. Documentation Overlap/Fragmentation

**Problem:** Release documentation is split across multiple locations:
- `scripts/RELEASE.md` - 500+ line comprehensive DMG guide
- `build/docs/operations/release/RELEASE-CHECKLIST.md` - Master checklist
- `build/docs/operations/release/README.md` - Index
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store guide
- `AGENTS.md` - Quick reference

**Overlap areas:**
- DMG build commands appear in 3+ places
- App Store commands appear in 2+ places
- Troubleshooting spread across multiple files

**Recommendation:**
- `scripts/RELEASE.md` should be **deprecated** (content moved to operations docs)
- Single source of truth per topic in `build/docs/operations/release/`
- `AGENTS.md` contains only quick reference, links to detailed docs

### 2. No Central Release Manifest

**Problem:** No single file tracks release history and current state.

**Current state:**
- `build/releases/v1.0.0/` exists but is ad-hoc
- No `manifest.json` tracking all releases
- No `config.json` defining release configuration

**Recommendation:** Create `releases/manifest.json` and `releases/config.json` at repo root (not under `build/`)

### 3. Release Directory Location

**Problem:** `build/releases/` is under `build/` which is partially gitignored.

**Current `.gitignore`:**
```
build/Contextify-Staging/
build/logs/
build/ResultBundles/
build/demo-videos/
build/db-backups/
build/screenshots-and-video/
build/Contextify.xcarchive/
build/appstore/
```

Note: `build/releases/` is NOT gitignored, so it works. But location is confusing.

**Recommendation:** Move to `releases/` at repo root for clarity.

### 4. Review Materials Tied to App Store Metadata

**Problem:** `appstore-metadata/review-materials/` contains release-specific materials that should be tied to specific versions.

**Example:** Demo video for v1.0.0 should be in `releases/v1.0.0/`, not generic location.

**Recommendation:**
- Keep generic templates in `appstore-metadata/review-materials/`
- Copy/link release-specific materials to `releases/vX.Y.Z/`

### 5. Missing Validation Scripts

**Problem:** No scripts to validate release prerequisites or completion.

**Currently manual:**
- Check tests pass
- Check warnings zero
- Check working directory clean
- Verify artifacts exist
- Verify deployments live

**Recommendation:** Create `scripts/release/validate-*.sh` scripts

### 6. Missing Marketing/Post-Release Checklists

**Problem:** Release docs focus on build/submission, not what happens after.

**Missing:**
- Changelog publication checklist
- Social media announcement checklist
- Support documentation update checklist
- Monitoring/feedback collection checklist

**Recommendation:** Add `05-marketing.md` and `06-post-release.md` checklist templates

### 7. Inconsistent Artifact Naming

**Problem:** Artifacts use different naming patterns.

**Examples:**
- `metadata-v1.0.0.json` (with v prefix)
- `app-store-submission-v1.0.0.png` (with v prefix)
- `Contextify-1.0.0.dmg` (without v prefix)
- `1.0.0.html` (without v prefix)

**Recommendation:** Standardize on `{version}` without v prefix in filenames, `v{version}` only in git tags.

---

## Proposed Reorganization

### New Top-Level Structure

```
contextify/
├── releases/                          # NEW: Central release management
│   ├── config.json                    # Release configuration
│   ├── manifest.json                  # Release history
│   ├── WORKFLOW.md                    # LLM instructions
│   ├── templates/                     # Checklist templates
│   └── v1.0.0/                        # Per-release directory
│
├── scripts/
│   ├── release/                       # NEW: Release helper scripts
│   │   ├── init.sh
│   │   ├── validate-pre-release.sh
│   │   ├── validate-build.sh
│   │   └── status.sh
│   └── (existing scripts)
│
├── build/
│   ├── docs/operations/release/       # KEEP: Detailed documentation
│   ├── docs/guides/APP-STORE-SUBMISSION.md  # KEEP
│   ├── releases/                      # REMOVE: Move to /releases/
│   └── archives/                      # NEW: Preserved xcarchives
│
├── appstore-metadata/                 # REORGANIZE
│   ├── (keep most as-is)
│   └── review-materials/              # Keep templates only
│
└── website/                           # KEEP as-is
```

### File Moves

| Current Location | New Location | Action |
|-----------------|--------------|--------|
| `build/releases/` | `releases/` | **Move** to repo root |
| `build/releases/v1.0.0/` | `releases/v1.0.0/` | Move with parent |
| `scripts/RELEASE.md` | (deprecated) | **Consolidate** into `build/docs/operations/release/` |
| `appstore-metadata/FEATURE-BENEFIT-MAPPING.md` | `marketing/` (future) | **Flag** for future move |
| `appstore-metadata/REVIEW-ANALYSIS.md` | `marketing/` (future) | **Flag** for future move |

### Files to Create

| File | Location | Purpose |
|------|----------|---------|
| `config.json` | `releases/` | Release configuration |
| `manifest.json` | `releases/` | Release history tracking |
| `WORKFLOW.md` | `releases/` | LLM workflow instructions |
| `templates/` | `releases/` | Checklist templates |
| `init.sh` | `scripts/release/` | Initialize new release |
| `validate-pre-release.sh` | `scripts/release/` | Pre-release checks |
| `validate-build.sh` | `scripts/release/` | Build verification |
| `status.sh` | `scripts/release/` | Show release state |

### Files to Deprecate/Consolidate

| File | Action | Reason |
|------|--------|--------|
| `scripts/RELEASE.md` | Consolidate | Content overlaps with `build/docs/operations/release/` |
| `build/docs/operations/release/release-readiness.md` | Review | May overlap with new checklists |

---

## Migration Plan

### Phase 1: Create New Structure (Can do now)

1. Create `releases/` directory at repo root
2. Create `releases/config.json` from strategy doc
3. Create `releases/manifest.json` with v1.0.0 entry
4. Create `releases/templates/` with checklist templates
5. Create `releases/WORKFLOW.md`
6. Create `scripts/release/` validation scripts

### Phase 2: Migrate v1.0.0 (Can do now)

1. Move `build/releases/v1.0.0/` to `releases/v1.0.0/`
2. Create `releases/v1.0.0/release.json` with current state
3. Create checklists from templates, mark completed items
4. Update manifest.json

### Phase 3: Update References (After Phase 2)

1. Update `AGENTS.md` releases section to reference new structure
2. Update `build/docs/operations/release/README.md` to reference new structure
3. Update `build/docs/operations/release/RELEASE-CHECKLIST.md` to integrate with new system
4. Add deprecation notice to `scripts/RELEASE.md`

### Phase 4: Test with v1.0.0 Resubmission (Validation)

1. Use new workflow for resubmission
2. Record issues/refinements needed
3. Update templates based on experience

---

## Gaps to Fill

### Must Have for v1.0.0 Resubmission

- [ ] `releases/v1.0.0/release.json` with current state
- [ ] Demo video path tracking
- [ ] Build number tracking (currently 3, next 4)

### Should Have for Professional System

- [ ] `releases/config.json` - Release configuration
- [ ] `releases/manifest.json` - Release history
- [ ] `releases/templates/` - Checklist templates
- [ ] `scripts/release/validate-pre-release.sh`
- [ ] `scripts/release/status.sh`

### Nice to Have (Future)

- [ ] Marketing checklists
- [ ] Support documentation checklists
- [ ] Automated manifest updates
- [ ] Integration with GitHub Actions

---

## Recommendations Summary

1. **Move** `build/releases/` to `releases/` at repo root
2. **Create** `config.json`, `manifest.json`, `WORKFLOW.md` in `releases/`
3. **Create** checklist templates in `releases/templates/`
4. **Create** validation scripts in `scripts/release/`
5. **Deprecate** `scripts/RELEASE.md` (consolidate into existing docs)
6. **Keep** detailed docs in `build/docs/operations/release/` (reference from workflow)
7. **Keep** `appstore-metadata/` mostly as-is (good pattern)

---

## Next Steps

1. Review this audit with user
2. Approve/modify reorganization plan
3. Execute Phase 1 (create new structure)
4. Execute Phase 2 (migrate v1.0.0)
5. Use for resubmission (validate approach)
