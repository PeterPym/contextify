---
name: linux-ci-trigger
description: Trigger and monitor Linux CLI CI builds on GitHub Actions. Use when user says "build linux", "trigger linux ci", "linux release", "/linux-ci-trigger", or needs to build Linux CLI binaries.
---

# Linux CI Trigger

Trigger Linux CLI builds on GitHub Actions and monitor their progress.

## When to Use

- User wants to build Linux CLI binaries
- Need to validate a release before shipping
- Testing CI workflow changes

## Build Strategy

Ranked approach (prefer earlier options):

| Rank | Method | When to Use |
|------|--------|-------------|
| 1 | Local Docker (amd64) | Development iteration, quick validation |
| 2 | CI (amd64 only) | Pre-release validation |
| 3 | CI (both architectures) | Final release builds |
| 4 | Local Docker (arm64) | Emergency only (2-3 hours) |

## Triggering CI

The workflow is **manual-only** (workflow_dispatch). It does NOT run automatically on commits or tags.

### Prerequisites

1. GitHub CLI authenticated: `gh auth status`
2. Access to banagale/contextify repo

### Trigger Commands

```bash
# amd64 only (faster, ~10 min build + ~2 min validation)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.1.0 \
  -f build_amd64=true \
  -f build_arm64=false

# Both architectures (slow, arm64 takes 60-90 min)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.1.0 \
  -f build_amd64=true \
  -f build_arm64=true

# arm64 only (rare - usually want both or just amd64)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.1.0 \
  -f build_amd64=false \
  -f build_arm64=true
```

### Monitoring

```bash
# Watch the run (blocks until complete)
gh run watch --repo banagale/contextify

# List recent runs
gh run list --workflow="Linux Release" --repo banagale/contextify --limit 5

# View specific run details
gh run view <run-id> --repo banagale/contextify

# View in browser
gh run view <run-id> --repo banagale/contextify --web
```

### Download Artifacts

```bash
# Download all artifacts from latest run
gh run download --repo banagale/contextify

# Download specific artifact
gh run download <run-id> --repo banagale/contextify -n contextify-linux-x86_64
gh run download <run-id> --repo banagale/contextify -n contextify-linux-arm64
```

## CI Jobs

The workflow has 4 jobs:

| Job | Duration | Purpose |
|-----|----------|---------|
| build-linux-amd64 | ~6-10 min | Build x86_64 binary |
| build-linux-arm64 | ~60-90 min | Build arm64 binary (QEMU) |
| validate-binary-amd64 | ~2 min | Verify glibc, static linking, container test |
| validate-binary-arm64 | ~3 min | Same validation for arm64 |

## Validation Checks

CI performs these validations automatically:

1. **glibc floor** - Binary must require glibc <= 2.35 (Ubuntu 22.04)
2. **No Swift runtime deps** - Must be statically linked
3. **Container test** - Must run in minimal ubuntu:22.04

## Local Build Alternative

For faster iteration, build locally with Docker. Use `/linux-local-build` skill or follow these steps:

### Pre-Flight Check (Required on ARM Mac)

```bash
# Check Colima configuration
colima list
# ARCH must show "x86_64" - if it shows "aarch64", fix it:

colima stop
colima delete  # WARNING: Removes container data
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Quick Build

```bash
# See: build/docs/guides/local-linux-builds.md for full command
mkdir -p dist

# x86_64 (~5-10 min on ARM Mac with Colima + Rosetta)
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -e CLI_VERSION="1.1.0" \
  -w /build \
  --platform linux/amd64 \
  swift:6.0-jammy \
  bash -c '...'  # See /linux-local-build for full command
```

**Note:** Local builds require Colima with Rosetta. Without `--arch x86_64 --vm-type vz --vz-rosetta`, you'll get "Illegal instruction" errors.

## Troubleshooting

### "Illegal instruction" error (local builds)

Colima is using QEMU instead of Rosetta. Fix:

```bash
colima stop
colima delete
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### "Actions budget is preventing further use"

GitHub Actions requires:
1. Payment method on file
2. Account-wide spending limit set (not just repo-scoped budget)

Go to: GitHub Settings > Billing > Spending limits

### arm64 build timeout

The 90-minute timeout may not be enough. Options:
- Build arm64 locally (2-3 hours)
- Retry - sometimes QEMU is faster on second attempt
- Skip arm64 for validation, only build for releases

### Build fails with "cannot find X in scope"

Check that `Version.generated.swift` is being written to correct path:
`Sources/ContextifyCLI/Version.generated.swift`

## Related

- `/linux-local-build` - Local Docker builds skill
- `build/docs/guides/local-linux-builds.md` - Local builds documentation
- `build/docs/guides/linux-ci-builds.md` - CI system overview
- `.github/workflows/linux-release.yml` - Workflow definition
