---
name: linux-local-build
description: Build Linux CLI binaries locally with Docker (Colima on ARM Mac). Use when user says "build linux locally", "local linux build", "docker build linux", or wants to build without CI.
---

# Linux Local Build

Build Linux CLI binaries locally with Docker instead of GitHub Actions CI.

## When to Use

- Quick iteration during development
- CI is unavailable or over budget
- Need immediate build without waiting for CI queue

## Prerequisites Check

**IMPORTANT:** Before building, verify Colima is configured correctly.

### Step 1: Check Colima Status

```bash
colima list
```

**Required:** ARCH column must show `x86_64` for amd64 builds.

### Step 2: Fix If Needed

If ARCH shows `aarch64` or Colima isn't running:

```bash
# If Colima exists with wrong architecture
colima stop
colima delete  # WARNING: Removes all container data

# Install dependencies if needed
brew install colima docker lima-additional-guestagents

# Start with Rosetta support
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Step 3: Verify Docker

```bash
docker info | head -5
# Should show "Context: colima"
```

## Build Commands

### x86_64 Build (Recommended, ~5-10 min)

```bash
mkdir -p dist

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

### arm64 Build (Fast with native profile, ~12 min)

**Recommended approach** - faster than CI's QEMU emulation.

```bash
# Ensure arm64 Colima profile exists (one-time setup)
colima start --profile arm64 --arch aarch64 --vm-type vz

# Switch to arm64 context
docker context use colima-arm64

# Verify native architecture
docker run --rm swift:6.0-jammy uname -m  # Should show: aarch64
```

Then run the same docker build command but with `--platform linux/arm64` and output to `contextify-linux-arm64.tar.gz`.

See `build/docs/guides/local-linux-builds.md` for the full command.

## Verification

After building:

```bash
# Check tarball exists
ls -la dist/contextify-linux-x86_64.tar.gz

# Verify contents
tar -tzf dist/contextify-linux-x86_64.tar.gz

# Test binary runs (optional, requires Docker)
docker run --rm -v "$PWD/dist":/dist ubuntu:22.04 \
  sh -c 'tar -xzf /dist/contextify-linux-x86_64.tar.gz -C /tmp && /tmp/contextify --version'
```

## Common Issues

### "Illegal instruction" error

**Cause:** Colima is using QEMU instead of Rosetta.

**Fix:**
```bash
colima stop
colima delete
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Colima won't start

```bash
colima delete
brew install lima-additional-guestagents
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Build fails with "cannot find X in scope"

Check Version.generated.swift path: `Sources/ContextifyCLI/Version.generated.swift`

## Alternative: Use CI

If local builds aren't working, use `/linux-ci-trigger` to build via GitHub Actions.

## Related

- `build/docs/guides/local-linux-builds.md` - Full documentation
- `/linux-ci-trigger` - CI-based builds
