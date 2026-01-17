# Local Linux Builds with Docker

Build Linux CLI binaries locally using Docker as an alternative to GitHub Actions CI.

## Build Strategy

Ranked approach for building Linux binaries:

| Rank | Method | When to Use |
|------|--------|-------------|
| 1 | **Local Docker (amd64)** | Development iteration, quick validation |
| 2 | **CI (amd64 only)** | Pre-release validation, need amd64 artifact |
| 3 | **CI (both architectures)** | Final release builds, need arm64 |
| 4 | **Local Docker (arm64)** | Emergency only (2-3 hours on ARM Mac) |

**Why this order?**
- Local amd64 builds are fast (~5-10 min) with Colima on ARM Mac
- CI preserves GitHub Actions minutes (limited budget)
- arm64 builds are slow everywhere (QEMU emulation)
- CI arm64 builds timeout at 90 minutes; local takes 2-3 hours

## Prerequisites

### Docker Runtime (Colima on ARM Mac)

ARM Macs require Colima configured with Rosetta for x86_64 builds. QEMU emulation does not work with Swift.

```bash
# Install
brew install colima docker lima-additional-guestagents

# Start with Rosetta support (required for x86_64 builds)
colima start --arch x86_64 --vm-type vz --vz-rosetta
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

## Build arm64 (Native on Apple Silicon - SLOW)

Only use this when CI arm64 build times out or CI is unavailable. Takes 2-3 hours.

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

## Using CI Instead (Recommended for arm64)

CI builds are manual-only. Use `/linux-ci-trigger` skill or trigger directly:

```bash
# amd64 only (faster, ~10 min)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.1.0 \
  -f build_amd64=true \
  -f build_arm64=false

# Both architectures (slow, ~90 min)
gh workflow run "Linux Release" --repo banagale/contextify \
  -f version=1.1.0 \
  -f build_amd64=true \
  -f build_arm64=true

# Monitor progress
gh run list --workflow="Linux Release" --repo banagale/contextify --limit 1
gh run watch --repo banagale/contextify
```

## Build Artifacts

Output location: `dist/contextify-linux-{arch}.tar.gz`

Contents:
- `contextify` - Unified CLI binary
- `contextify-ingest` - Symlink to contextify (backwards compat)
- `contextify-query` - Symlink to contextify (backwards compat)
- `user-skill/` - Total Recall skill files

## Verification

After building, verify static linking:

```bash
# Check tarball contents
tar -tzf dist/contextify-linux-x86_64.tar.gz

# Verify no dynamic SQLite dependency
docker run --rm -v "$PWD/dist":/dist swift:6.0-jammy \
  sh -c 'tar -xzf /dist/contextify-linux-x86_64.tar.gz -C /tmp && ldd /tmp/contextify'
# Should NOT show libsqlite3.so
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
This is expected. Swift compilation under QEMU is slow. Use CI for arm64 when possible.

### Build fails with "cannot find X in scope"
Check that Version.generated.swift is being written to the correct path (`Sources/ContextifyCLI/`).

---

**Last Updated**: 2026-01-14
