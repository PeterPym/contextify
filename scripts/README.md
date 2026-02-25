---
title: Contextify Scripts Index
purpose: Primary entry point for script discovery and common workflows.
audience: Contributors and automation (including AI agents).
status: active
---

# Contextify Scripts

Utility scripts for Contextify development and maintenance.

This file is the entry point for script discovery. It lists common tasks,
high-traffic scripts, and the best README for each subdirectory.

## Common Tasks

| Task | Script(s) |
|------|-----------|
| Build app | `bash scripts/xc.sh build` |
| Run tests | `swift test` |
| Manage database | `scripts/db_manager.sh` (see `build/docs/operations/database-management.md`) |
| Run benchmarks | `scripts/performance/run-perf-suite.sh` (see `scripts/performance/README.md`) |
| Profile performance | `scripts/performance/profile.sh` |
| QA suite | `scripts/qa/README.md` |
| Log capture/analysis | `scripts/logging/README.md` |
| Transcript repair | `scripts/transcript-repair/README.md` |
| Transcript conversion | `build/docs/guides/transcript-converter.md` |
| Website deploy | `scripts/deploy-website.sh` |
| Release workflow | `build/docs/operations/release/RELEASE-PROCESS.md` and `releases/WORKFLOW.md` |

## Top-Level Scripts

Only three primary entry-point scripts live at the scripts/ root:

| Script | Purpose |
|--------|---------|
| `scripts/xc.sh` | Xcode build/test/clean wrapper |
| `scripts/db_manager.sh` | Database operations and safety rails |
| `scripts/deploy-website.sh` | Deploy static site |

## Subdirectories

| Directory | Purpose | README |
|-----------|---------|--------|
| [`build/`](build/) | CI, build, install, and setup tooling | `scripts/build/README.md` |
| [`release/`](release/) | Release, signing, and DMG scripts | `scripts/release/README.md` |
| [`logging/`](logging/) | Log capture, diagnostics, and analysis | `scripts/logging/README.md` |
| [`transcripts/`](transcripts/) | Transcript conversion and migration | `scripts/transcripts/README.md` |
| [`performance/`](performance/) | Benchmarking and profiling tools | `scripts/performance/README.md` |
| [`qa/`](qa/) | QA test suite | `scripts/qa/README.md` |
| [`transcript-repair/`](transcript-repair/) | Transcript repair tools | `scripts/transcript-repair/README.md` |
| [`screenshots/`](screenshots/) | Screenshot tooling | `scripts/screenshots/README.md` |
| [`sparkle/`](sparkle/) | Sparkle update tooling | `scripts/sparkle/README.md` |
| [`lib/`](lib/) | Shared helper functions | `scripts/lib/README.md` |
| [`archive/`](archive/) | One-off scripts kept for reference | -- |

## Key Scripts by Category

### Build & CI (`scripts/build/`)

| Script | Purpose |
|--------|---------|
| `trigger-ci-build.sh` | Trigger GitHub Actions CI build |
| `docker-linux-build.sh` | Linux Docker build |
| `install-cli.sh` | Install CLI tools |
| `install-shell-bindings.sh` | Shell bindings for CLI |
| `setup-ci-tools.sh` | CI environment setup (SessionStart hook) |
| `setup-github-token.sh` | GitHub token setup for CI |
| `cross-platform-change-detect.sh` | Detect cross-platform changes |
| `validate-xcode-project.sh` | Xcode project validation |
| `setup-server.sh` | Server setup for deployment |
| `auto-deploy-when-ready.sh` | DNS-triggered deploy helper |

### Release (`scripts/release/`)

| Script | Purpose |
|--------|---------|
| `build-release.sh` | Build release artifacts |
| `release.py` | End-to-end release automation |
| `sign_and_notarize.py` | DMG signing and notarization |
| `sign_cli.sh` | CLI signing for Homebrew |
| `generate_dmg_background.swift` | DMG background image generator |
| `compare-builds.sh` | Compare build outputs |
| `test-ci-signing.sh` | Test CI signing setup |

### Logging & Diagnostics (`scripts/logging/`)

| Script | Purpose |
|--------|---------|
| `stream-logs.sh` | Stream app logs in real time |
| `capture-recent-logs.sh` | Snapshot recent logs |
| `build-and-capture-logs.sh` | Build + log capture helper |
| `read_timeline_state.sh` | Read app timeline state |
| `debug_project_state.sh` | Debug project state |
| `healthcheck.sh` | Daemon health check |
| `run-timeline-validation.sh` | Timeline validation runner |
| `analyze_intent_classification.sh` | Intent classification analysis |
| `generate_intent_improvements.py` | Intent improvement suggestions |
| `validate-timeline-fix.swift` | Timeline fix validation |

### Transcripts (`scripts/transcripts/`)

| Script | Purpose |
|--------|---------|
| `convert_transcript.py` | Bidirectional transcript conversion |
| `migrate-transcripts.sh` | Migrate transcript paths after repo moves |
| `classify_transcript.sh` | Transcript classification |

## Legacy Paths

Scripts were reorganized in Feb 2026. Use the new locations:

| Old | New |
|-----|-----|
| `scripts/trigger-ci-build.sh` | `scripts/build/trigger-ci-build.sh` |
| `scripts/docker-linux-build.sh` | `scripts/build/docker-linux-build.sh` |
| `scripts/install-cli.sh` | `scripts/build/install-cli.sh` |
| `scripts/install-shell-bindings.sh` | `scripts/build/install-shell-bindings.sh` |
| `scripts/build-release.sh` | `scripts/release/build-release.sh` |
| `scripts/release.py` | `scripts/release/release.py` |
| `scripts/sign_and_notarize.py` | `scripts/release/sign_and_notarize.py` |
| `scripts/sign_cli.sh` | `scripts/release/sign_cli.sh` |
| `scripts/convert_transcript.py` | `scripts/transcripts/convert_transcript.py` |
| `scripts/migrate-transcripts.sh` | `scripts/transcripts/migrate-transcripts.sh` |
| `scripts/stream-logs.sh` | `scripts/logging/stream-logs.sh` |
| `scripts/capture-recent-logs.sh` | `scripts/logging/capture-recent-logs.sh` |
| `scripts/build-and-capture-logs.sh` | `scripts/logging/build-and-capture-logs.sh` |
| `scripts/RELEASE.md` | `build/docs/operations/release/RELEASE-PROCESS.md` |
| `scripts/DATABASE-MANAGEMENT.md` | `build/docs/operations/database-management.md` |
| `scripts/TRANSCRIPT_CONVERTER_README.md` | `build/docs/guides/transcript-converter.md` |
| `scripts/SIGNING-SETUP.md` | `build/docs/operations/signing-setup.md` |
| `scripts/CI-TRIGGER-README.md` | Merged into `build/docs/guides/linux-ci-builds.md` |
| `scripts/CLAUDE-CODE-WEB-CI-GUIDE.md` | Merged into `build/docs/guides/linux-ci-builds.md` |
| `scripts/profile.sh` | `scripts/performance/profile.sh` |
| `scripts/compare-performance.sh` | `scripts/performance/compare.sh` |
| `scripts/benchmarks/` | `scripts/performance/` |

## Frontmatter Convention

Script READMEs use YAML frontmatter at the top so tools can parse metadata.

```yaml
---
title: Short, descriptive title
purpose: One-line description of what the scripts in this folder do.
audience: Who should read it (e.g., contributors, release engineers).
status: active | deprecated | internal
---
```
