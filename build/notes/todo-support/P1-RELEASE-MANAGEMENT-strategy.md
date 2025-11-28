---
todo_id: P1-RELEASE-MANAGEMENT
title: Release Management Strategy
type: spec
date: 2025-11-27
status: complete
description: Strategy document for LLM-guided release management system. Implementation complete - see releases/ directory.
---

# Contextify Release Management Strategy

**Version:** 1.0 (Implemented)
**Date:** November 27, 2025
**Purpose:** Define a comprehensive, LLM-guided release management system

**Status:** Implemented - see `releases/` directory at repo root

---

## Executive Summary

This document defines a release management system for Contextify that:
1. Uses **LLM-friendly instructions** rather than full automation
2. Maintains a **single source of truth** per release
3. Covers the **full lifecycle**: build, review, submission, marketing, support
4. Follows patterns already proven in the codebase (screenshots workflow)
5. Enables **validation and verification** at each step

---

## Core Principles

### 1. LLM-Guided Over Fully Automated

**Why:** Full automation (semantic-release, goreleaser) assumes deterministic workflows. Our workflow has:
- Human judgment points (demo video quality, screenshot selection)
- External dependencies (Apple review, website deployment)
- Marketing/support tasks that can't be scripted

**Approach:** Provide structured instructions that an LLM can follow, with validation scripts that confirm completion.

### 2. Single Source of Truth Per Release

**Why:** Release artifacts, metadata, and status are currently scattered across:
- `build/` (temporary, gitignored)
- `dist/` (output)
- `appstore-metadata/` (metadata)
- `website/` (hosted files)
- App Store Connect (external)

**Approach:** Each release gets a dedicated directory with references to all artifacts and a JSON file tracking state.

### 3. Validation Over Trust

**Why:** Manual steps can be forgotten or done incorrectly.

**Approach:** Simple validation scripts that check prerequisites and outcomes. The LLM (or human) runs these and reports results.

### 4. Covers Full Lifecycle

**Why:** A "release" isn't just a build. It includes:
- Pre-release validation (tests, warnings, clean state)
- Build artifacts (DMG, App Store archive)
- Review materials (demo video, sample data)
- Submission (upload, metadata, notes)
- Marketing (changelog, announcements, press)
- Support (documentation updates, FAQ)
- Post-release (monitoring, feedback)

**Approach:** Checklists for each phase, all tracked in the release directory.

---

## Directory Structure

### Top-Level Organization

```
contextify/
├── releases/                        # NEW: Central release management
│   ├── config.json                  # Static release configuration
│   ├── manifest.json                # Release history and current state
│   ├── WORKFLOW.md                  # Master LLM instructions
│   ├── templates/                   # Templates for new releases
│   │   ├── release.json.template
│   │   ├── checklists/
│   │   │   ├── 01-pre-release.md
│   │   │   ├── 02-build.md
│   │   │   ├── 03-review-materials.md
│   │   │   ├── 04-submission.md
│   │   │   ├── 05-marketing.md
│   │   │   └── 06-post-release.md
│   │   └── README.md.template
│   │
│   ├── v1.0.0/                      # Per-release directory
│   │   ├── release.json             # This release's complete state
│   │   ├── README.md                # Human-readable summary
│   │   ├── checklists/              # Copied from templates, tracked
│   │   ├── artifacts/               # References to build outputs
│   │   ├── logs/                    # Validation outputs
│   │   └── assets/                  # Screenshots, submission receipts
│   │
│   └── v1.0.1/
│       └── ...
│
├── scripts/
│   ├── release/                     # NEW: Release helper scripts
│   │   ├── init.sh                  # Initialize new release directory
│   │   ├── validate-pre-release.sh  # Check tests, warnings, clean state
│   │   ├── validate-build.sh        # Verify artifacts exist
│   │   ├── validate-deployment.sh   # Check URLs are live
│   │   └── status.sh                # Show current release state
│   │
│   ├── xc.sh                        # Existing: Build wrapper
│   ├── release.py                   # Existing: DMG automation
│   └── ...
│
├── build/                           # Temporary build outputs (gitignored)
│   ├── archives/                    # Preserved xcarchives per version
│   │   └── v1.0.0.xcarchive
│   └── ...
│
├── dist/                            # DMG outputs (gitignored)
│   └── Contextify-1.0.0.dmg
│
├── website/                         # Website source
│   ├── appcast.xml                  # Sparkle feed
│   ├── release-notes/               # Per-version HTML
│   └── review-4a125b1d/             # Review materials (obscured URL)
│
└── appstore-metadata/               # REORGANIZE: App Store specific
    ├── metadata.json                # Current metadata
    ├── fastlane/                    # Fastlane integration
    ├── screenshots/                 # Screenshot workflow
    └── review-materials/            # MOVE: To release-specific or shared
```

### Per-Release Directory Detail

```
releases/v1.0.0/
├── release.json                     # Complete release state (see schema below)
├── README.md                        # Human summary, auto-generated from JSON
│
├── checklists/                      # Task tracking (markdown with checkboxes)
│   ├── 01-pre-release.md            # Tests, warnings, clean state
│   ├── 02-build.md                  # DMG, App Store archive
│   ├── 03-review-materials.md       # Demo video, sample data
│   ├── 04-submission.md             # Upload, metadata, notes
│   ├── 05-marketing.md              # Changelog, announcements
│   └── 06-post-release.md           # Monitoring, feedback, docs
│
├── artifacts/                       # References (paths, not files)
│   ├── dmg.json                     # {"path": "dist/Contextify-1.0.0.dmg", "sha256": "...", "sparkle_signature": "..."}
│   ├── appstore.json                # {"archive_path": "build/archives/v1.0.0.xcarchive", "build_number": 4}
│   └── review-materials.json        # {"demo_video": "website/review-.../demo-video.mp4", "sample_data": "..."}
│
├── logs/                            # Validation outputs (gitignored except summaries)
│   ├── pre-release-validation.txt   # Output of validate-pre-release.sh
│   ├── build-validation.txt         # Output of validate-build.sh
│   └── upload-receipt.json          # Apple's upload response
│
└── assets/                          # Release-specific assets (committed)
    ├── submission-screenshot.png    # Screenshot of App Store submission
    └── metadata-snapshot.json       # Metadata at submission time
```

---

## Core Files

### 1. `releases/config.json` - Static Configuration

```json
{
  "$schema": "./schemas/config.schema.json",
  "schema_version": 1,

  "project": {
    "name": "Contextify",
    "bundle_id": "sh.contextify.Contextify",
    "minimum_os": "26.0"
  },

  "distributions": {
    "dmg": {
      "target": "Contextify",
      "scheme": "Contextify",
      "build_command": "python3 scripts/release.py --version {version} --yes",
      "artifact_pattern": "dist/Contextify-{version}.dmg",
      "signing": {
        "sparkle_key": ".secrets/sparkle_private_key"
      }
    },
    "appstore": {
      "target": "Contextify AppStore",
      "scheme": "Contextify AppStore",
      "archive_command": "bash scripts/xc.sh --dist=appstore Release archive",
      "export_command": "bash scripts/xc.sh export-pkg",
      "upload_command": "bash scripts/xc.sh upload",
      "archive_path": "build/Contextify.xcarchive",
      "archive_preserve_path": "build/archives/v{version}.xcarchive"
    }
  },

  "review_materials": {
    "base_url": "https://contextify.sh/review-4a125b1d",
    "sample_data_source": "appstore-metadata/review-materials/sample-data.zip",
    "demo_video_script": "appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md"
  },

  "website": {
    "deploy_command": "./scripts/deploy-website.sh",
    "appcast_path": "website/appcast.xml",
    "release_notes_path": "website/release-notes/{version}.html"
  },

  "validation": {
    "pre_release": {
      "tests_command": "swift test",
      "warnings_command": "bash scripts/xc.sh build 2>&1 | grep -c 'warning:'",
      "expected_warnings": 0
    }
  },

  "app_store_connect": {
    "app_id": "6753190666",
    "team_id": "J8P5B23FK7",
    "api_key_id": "AG868N57U6",
    "issuer_id": "69a6de89-2083-47e3-e053-5b8c7c11a4d1"
  }
}
```

### 2. `releases/manifest.json` - Release History

```json
{
  "$schema": "./schemas/manifest.schema.json",
  "schema_version": 1,
  "current_version": "1.0.0",

  "releases": {
    "1.0.0": {
      "created": "2025-11-25",
      "status": "in_progress",
      "git_tag": "v1.0.0",
      "git_commit": "abc123def456",

      "dmg": {
        "status": "not_started",
        "released_at": null,
        "github_release_url": null
      },

      "appstore": {
        "status": "rejected",
        "build_number": 3,
        "submitted_at": "2025-11-25T12:05:00Z",
        "rejection_reason": "Guideline 2.1 - needs demo video and sample data",
        "approved_at": null
      },

      "marketing": {
        "changelog_published": false,
        "announcement_posted": false
      }
    }
  }
}
```

### 3. `releases/v1.0.0/release.json` - Per-Release State

```json
{
  "$schema": "../schemas/release.schema.json",
  "version": "1.0.0",
  "created": "2025-11-25",
  "updated": "2025-11-27",

  "git": {
    "tag": "v1.0.0",
    "commit": "abc123def456",
    "branch": "main"
  },

  "phases": {
    "pre_release": {
      "status": "complete",
      "completed_at": "2025-11-25T10:00:00Z",
      "validation": {
        "tests_passed": true,
        "test_count": 79,
        "warnings": 0,
        "working_directory_clean": true
      }
    },

    "build": {
      "status": "complete",
      "dmg": {
        "built": true,
        "path": "dist/Contextify-1.0.0.dmg",
        "sha256": "abc123...",
        "size_bytes": 12345678,
        "signed": true,
        "notarized": true,
        "sparkle_signature": "xyz789..."
      },
      "appstore": {
        "archived": true,
        "archive_path": "build/archives/v1.0.0.xcarchive",
        "build_number": 4,
        "exported": true,
        "uploaded": true,
        "upload_receipt": "logs/upload-receipt.json"
      }
    },

    "review_materials": {
      "status": "in_progress",
      "demo_video": {
        "recorded": false,
        "path": null,
        "deployed": false
      },
      "sample_data": {
        "generated": true,
        "path": "website/review-4a125b1d/sample-data.zip",
        "deployed": true
      }
    },

    "submission": {
      "status": "pending_resubmission",
      "first_submitted_at": "2025-11-25T12:05:00Z",
      "rejection": {
        "date": "2025-11-26",
        "guideline": "2.1",
        "reason": "Information Needed - demo video and sample files",
        "response_plan": "appstore-metadata/review-materials/REJECTION-RESPONSE-PLAN.md"
      },
      "resubmission": {
        "build_number": 4,
        "notes_updated": true,
        "materials_deployed": false
      }
    },

    "marketing": {
      "status": "not_started",
      "changelog": {
        "written": false,
        "published": false
      },
      "announcements": {
        "twitter": false,
        "mastodon": false,
        "hacker_news": false,
        "product_hunt": false
      }
    },

    "post_release": {
      "status": "not_started",
      "documentation_updated": false,
      "support_faq_updated": false,
      "monitoring_enabled": false
    }
  },

  "notes": [
    {
      "date": "2025-11-25",
      "author": "system",
      "note": "Initial submission to App Store"
    },
    {
      "date": "2025-11-26",
      "author": "apple",
      "note": "Rejected - Guideline 2.1, needs demo video and sample data"
    },
    {
      "date": "2025-11-27",
      "author": "system",
      "note": "Created sample transcripts and demo video script"
    }
  ]
}
```

---

## Workflow Instructions (WORKFLOW.md)

The master workflow document serves as the "prompt" for LLM-guided releases.

### Structure

```markdown
# Release Workflow

This document guides you through releasing a new version of Contextify.

## Prerequisites

- Read `releases/config.json` to understand the release configuration
- Check `releases/manifest.json` for current release state
- Ensure you're on the correct git branch

## Starting a New Release

### 1. Initialize Release Directory

\`\`\`bash
./scripts/release/init.sh X.Y.Z
\`\`\`

This creates `releases/vX.Y.Z/` with:
- `release.json` (from template)
- `checklists/` (from templates)
- `README.md` (generated)

### 2. Follow Phase Checklists

Work through each checklist in order:
1. `checklists/01-pre-release.md`
2. `checklists/02-build.md`
3. `checklists/03-review-materials.md`
4. `checklists/04-submission.md`
5. `checklists/05-marketing.md`
6. `checklists/06-post-release.md`

Each checklist contains:
- [ ] Tasks to complete
- Commands to run
- Validation steps
- Where to record results

### 3. Update Release State

After completing each phase:
1. Update `release.json` with results
2. Mark checklist items complete
3. Run validation script for that phase

## Resuming Work on a Release

1. Read `releases/vX.Y.Z/release.json` to see current state
2. Find the first incomplete phase
3. Continue from that checklist

## Handling Rejections

If App Store rejects:
1. Create rejection note in `release.json`
2. Update `checklists/04-submission.md` with rejection details
3. Address issues per rejection reason
4. Increment build number if code changes needed
5. Re-run submission checklist

## Validation Commands

\`\`\`bash
# Check overall release status
./scripts/release/status.sh X.Y.Z

# Validate specific phase
./scripts/release/validate-pre-release.sh X.Y.Z
./scripts/release/validate-build.sh X.Y.Z
./scripts/release/validate-deployment.sh X.Y.Z
\`\`\`
```

---

## Checklist Templates

### Example: `templates/checklists/01-pre-release.md`

```markdown
# Pre-Release Checklist

**Release:** {version}
**Phase:** 1 of 6
**Status:** [ ] Not Started / [ ] In Progress / [x] Complete

## Code Quality

### Tests
- [ ] Run test suite: `swift test`
- [ ] Expected: All tests pass (currently 79 tests)
- [ ] Actual result: ____

### Build Warnings
- [ ] Run build: `bash scripts/xc.sh build`
- [ ] Expected: 0 warnings
- [ ] Actual warnings: ____
- [ ] If warnings > 0, fix before proceeding

### Working Directory
- [ ] Check status: `git status`
- [ ] Expected: Clean (nothing to commit)
- [ ] If dirty, commit or stash changes

## Version Planning

### Version Number
- [ ] Confirm version: {version}
- [ ] Follows semantic versioning (MAJOR.MINOR.PATCH)
- [ ] Current version in Xcode: `grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Release Notes
- [ ] Draft release notes content
- [ ] Save to: `releases/v{version}/assets/release-notes-draft.md`

## Blockers Check

- [ ] Review P0 issues: `grep "P0" TODOS.md`
- [ ] All P0 issues resolved: [ ] Yes / [ ] No (list blockers below)

**Blockers:**
- (none)

## Validation

Run validation script:
```bash
./scripts/release/validate-pre-release.sh {version}
```

Paste output:
```
(paste here)
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 2: Build

**Completed by:** ____
**Date:** ____
```

---

## Integration Points

### With Existing Systems

| System | Integration |
|--------|-------------|
| `scripts/xc.sh` | Called by build checklist, config references commands |
| `scripts/release.py` | Called for DMG releases, config references |
| `appstore-metadata/` | Review notes, metadata sourced from here |
| `website/` | Release notes, appcast updated per checklist |
| `build/` | Archive preservation path defined in config |

### With App Store Connect

- Upload via `xc.sh upload` (already scripted)
- Review notes from `appstore-metadata/fastlane/metadata/review_information/notes.txt`
- Build number tracked in release.json

### With Sparkle Updates

- Signature generated per checklist
- Appcast updated per checklist
- Release notes HTML created per checklist

---

## Migration Plan

### Phase 1: Create Structure
1. Create `releases/` directory structure
2. Create `config.json` and `manifest.json`
3. Create template files
4. Create validation scripts

### Phase 2: Migrate v1.0.0
1. Create `releases/v1.0.0/` from existing state
2. Populate `release.json` with current status
3. Copy relevant assets
4. Update manifest.json

### Phase 3: Update Documentation
1. Update `RELEASE-CHECKLIST.md` to reference new system
2. Update `APP-STORE-SUBMISSION.md` to reference new system
3. Update `AGENTS.md` releases section
4. Deprecate redundant docs

### Phase 4: Test Workflow
1. Use new system for v1.0.0 resubmission
2. Refine based on experience
3. Document learnings

---

## Benefits

1. **Traceability:** Know exactly what was released, when, and how
2. **Reproducibility:** Same instructions, same results
3. **LLM-Friendly:** Structured for AI assistance
4. **Comprehensive:** Covers build through marketing
5. **Flexible:** Checklists can be customized per release
6. **Auditable:** JSON state + checklists = full history

---

## Open Questions

1. Should `releases/` be in repo root or under `build/`?
2. How much of release.json should be auto-generated vs manual?
3. Should we version the checklist templates?
4. Integration with GitHub Releases automation?

---

## Next Steps

1. Review and approve this strategy
2. Audit existing files for reorganization
3. Create initial structure
4. Migrate v1.0.0
5. Test with resubmission workflow
