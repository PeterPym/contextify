# Local Linux Builds with Docker

Build Linux CLI binaries locally using Docker as an alternative to GitHub Actions CI.

## Build Strategy

**Recommended approach** (ARM Mac with dual Colima profiles):

| Architecture | Method | Time | Notes |
|--------------|--------|------|-------|
| **x86_64** | CI (GitHub Actions) | ~10 min | Native x86 runners, fast |
| **arm64** | Local Docker (native) | ~12 min | Native on ARM Mac via Colima arm64 profile |

**Why this split?**
- x86_64 on CI: GitHub's x86 runners build natively - no emulation overhead
- arm64 locally: ARM Mac builds natively via dedicated Colima profile (~12 min)
- arm64 on CI: QEMU emulation is painfully slow (60+ min), often times out

**Legacy approach** (if only one Colima profile):

| Rank | Method | When to Use |
|------|--------|-------------|
| 1 | **Local Docker (amd64)** | Development iteration, quick validation |
| 2 | **CI (amd64 only)** | Pre-release validation, need amd64 artifact |
| 3 | **Local Docker (arm64)** | Need arm64, have ARM Mac with arm64 Colima profile |
| 4 | **CI (arm64)** | Last resort - QEMU is very slow (60+ min)

## Prerequisites

### Docker Runtime (Dual Colima Profiles on ARM Mac)

For optimal build speeds, set up **two Colima profiles**:
- `default` (x86_64 via Rosetta) - for x86_64 builds when CI unavailable
- `arm64` (native aarch64) - for fast arm64 builds (~12 min)

```bash
# Install
brew install colima docker lima-additional-guestagents

# Profile 1: x86_64 with Rosetta (for local x86 builds)
colima start --arch x86_64 --vm-type vz --vz-rosetta

# Profile 2: Native arm64 (for fast arm64 builds)
colima start --profile arm64 --arch aarch64 --vm-type vz
```

**Switching between profiles:**
```bash
# For x86_64 builds
docker context use colima

# For arm64 builds
docker context use colima-arm64

# Verify active architecture
docker run --rm swift:6.0-jammy uname -m
# Should show: x86_64 or aarch64
```

### Verify Configuration

```bash
colima list
# ARCH column must show "x86_64" for amd64 builds
```

If ARCH shows `aarch64`, you need to recreate Colima (see Troubleshooting below).

### Other Requirements

- ARM Mac (Apple Silicon) for native arm64 builds
- x86_64 builds require Colima with Rosetta (see setup above)

## Docker Context (CRITICAL)

When multiple Colima profiles exist (e.g., both `colima` and `colima-arm64`), the **active Docker context** determines which VM handles builds.

**The `--platform` flag and `DOCKER_HOST` environment variables are IGNORED if the context points elsewhere.** This causes silent architecture mismatches where you think you're building x86_64 but actually get arm64 (or vice versa).

### Pre-flight Check (Required Before Any Build)

```bash
# Check current context - the * shows which is active
docker context ls

# Switch to x86_64 (default Colima profile)
docker context use colima

# Or switch to arm64
docker context use colima-arm64

# Verify architecture matches your intent
docker run --rm swift:6.0-noble uname -m
# Should show: x86_64 (for colima) or aarch64 (for colima-arm64)
```

## Quick Start: Build x86_64 (Recommended)

```bash
# Create output directory
mkdir -p dist

# Build x86_64 binary (~5-10 minutes on ARM Mac with Colima)
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -e CLI_VERSION="1.1.0" \
  -w /build \
  --platform linux/amd64 \
  swift:6.0-jammy \
  bash -c '
    set -e
    cp -r /workspace/Sources /workspace/Package.swift /workspace/Package.resolved /workspace/app /workspace/contextify-query /build/
    apt-get update -qq && apt-get install -y build-essential curl pkg-config -qq > /dev/null 2>&1

    # Build SQLite with required features
    cd /tmp
    curl -sL "https://www.sqlite.org/2024/sqlite-autoconf-3450100.tar.gz" | tar xz
    cd sqlite-autoconf-*
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -O2" \
      ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --disable-shared --quiet
    make -j$(nproc) --quiet && make install --quiet && ldconfig

    # Build unified CLI
    cd /build
    printf "// Generated at build time\npublic let generatedCLIVersion = \"%s\"\n" "$CLI_VERSION" > Sources/ContextifyCLI/Version.generated.swift
    swift build -c release --product contextify --static-swift-stdlib -Xswiftc -DGENERATED_VERSION

    # Package
    mkdir -p /output
    cp .build/release/contextify /output/
    ln -sf contextify /output/contextify-ingest
    ln -sf contextify /output/contextify-query
    cp -R contextify-query/user-skill /output/
    cd /output && tar -czvf contextify-linux-x86_64.tar.gz contextify contextify-ingest contextify-query user-skill
    rm -f contextify contextify-ingest contextify-query && rm -rf user-skill
  '
```

## Build arm64 (Native on Apple Silicon - FAST with native profile)

With a dedicated arm64 Colima profile, builds take ~12 minutes (native, no emulation).
This is the **recommended approach** for arm64 - much faster than CI's QEMU emulation.

```bash
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -e CLI_VERSION="1.1.0" \
  -w /build \
  --platform linux/arm64 \
  swift:6.0-jammy \
  bash -c '
    set -e
    cp -r /workspace/Sources /workspace/Package.swift /workspace/Package.resolved /workspace/app /workspace/contextify-query /build/
    apt-get update -qq && apt-get install -y build-essential curl pkg-config -qq > /dev/null 2>&1

    # Build SQLite with required features
    cd /tmp
    curl -sL "https://www.sqlite.org/2024/sqlite-autoconf-3450100.tar.gz" | tar xz
    cd sqlite-autoconf-*
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -O2" \
      ./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu --disable-shared --quiet
    make -j$(nproc) --quiet && make install --quiet && ldconfig

    # Build unified CLI
    cd /build
    printf "// Generated at build time\npublic let generatedCLIVersion = \"%s\"\n" "$CLI_VERSION" > Sources/ContextifyCLI/Version.generated.swift
    swift build -c release --product contextify --static-swift-stdlib -Xswiftc -DGENERATED_VERSION

    # Package
    mkdir -p /output
    cp .build/release/contextify /output/
    ln -sf contextify /output/contextify-ingest
    ln -sf contextify /output/contextify-query
    cp -R contextify-query/user-skill /output/
    cd /output && tar -czvf contextify-linux-arm64.tar.gz contextify contextify-ingest contextify-query user-skill
    rm -f contextify contextify-ingest contextify-query && rm -rf user-skill
  '
```

## Using CI (Recommended for x86_64 only)

CI builds are manual-only. Use `/linux-ci-trigger` skill or trigger directly.

**Recommended workflow:**
- x86_64: Build via CI (native runners, fast)
- arm64: Build locally with native Colima profile (see above)

```bash
# x86_64 only (recommended, ~10 min)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.2.1 \
  -f build_amd64=true \
  -f build_arm64=false

# Monitor progress
gh run list --workflow="Linux Release" --repo banagale/contextify --limit 1
gh run watch --repo banagale/contextify
```

**Note:** CI arm64 builds use QEMU emulation and take 60+ minutes. Prefer local arm64 builds on ARM Mac.

## Build Artifacts

Output location: `dist/contextify-linux-{arch}.tar.gz`

Contents:
- `contextify` - Unified CLI binary
- `contextify-ingest` - Symlink to contextify (backwards compat)
- `contextify-query` - Symlink to contextify (backwards compat)
- `user-skill/` - Total Recall skill files

## Verification

After building, verify static linking and architecture:

```bash
# Check tarball contents
tar -tzf dist/contextify-linux-x86_64.tar.gz

# Verify no dynamic SQLite dependency
docker run --rm -v "$PWD/dist":/dist swift:6.0-jammy \
  sh -c 'tar -xzf /dist/contextify-linux-x86_64.tar.gz -C /tmp && ldd /tmp/contextify'
# Should NOT show libsqlite3.so

# Verify binary architecture matches intent
file .build-linux/debug/contextify
# Should show: ELF 64-bit LSB pie executable, x86-64
# OR: ELF 64-bit LSB pie executable, ARM aarch64
```

## Worktree Compatibility

When building from a git worktree, mount the workspace as read-only (`:ro`) and use a container-internal build directory (`-w /build`). This avoids git path resolution issues where Docker can't access the parent `.git` directory.

## Troubleshooting

### "Illegal instruction" error during Swift compilation

**Cause:** Colima is using QEMU emulation instead of Rosetta.

**Diagnosis:**
```bash
colima list
```
If ARCH shows `aarch64`, Rosetta is not enabled.

**Fix:**
```bash
colima stop
colima delete  # WARNING: Removes all container data
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Colima architecture cannot be changed

Colima's architecture is set at VM creation time. To change it, you must delete and recreate:

```bash
colima stop
colima delete
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Git "dubious ownership" errors
Mount workspace as read-only (`:ro`) and copy files to container-internal path.

### SwiftPM cache permission errors
These warnings are harmless - SwiftPM can't write to the cache in the read-only mount but downloads work.

### arm64 build takes too long
If using QEMU emulation (wrong profile), it takes hours. Ensure you're using native arm64:
```bash
docker context use colima-arm64
docker run --rm swift:6.0-jammy uname -m  # Should show: aarch64
```
Native arm64 builds take ~12 minutes. If you don't have an arm64 profile, create one (see Prerequisites).

### Build fails with "cannot find X in scope"
Check that Version.generated.swift is being written to the correct path (`Sources/ContextifyCLI/`).

### Built wrong architecture

If `file` shows arm64 when you wanted x86_64 (or vice versa):

1. Check `docker context ls` - the `*` shows active context
2. Switch context: `docker context use colima` (x86) or `docker context use colima-arm64`
3. Rebuild

The `--platform` flag does NOT override the Docker context. The context determines which Colima VM handles the build, and that VM's architecture is what you get.

Reference: Session 4d16edb0-adcf-4f9d-9539-dde014bc69f9

---

**Last Updated**: 2026-01-19
