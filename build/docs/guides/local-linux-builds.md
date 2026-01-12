# Local Linux Builds with Docker

Build Linux CLI binaries locally using Docker as an alternative to GitHub Actions.

## When to Use Local Builds

Local Docker builds are a valid alternative to CI builds when:

- **GitHub Actions artifact quota is exhausted** (recalculates every 6-12 hours)
- **Faster iteration** needed during development
- **CI is down** or experiencing issues
- **Network issues** with GitHub Actions

The binaries produced are identical to CI builds - same Swift version, same static linking, same build flags.

## Prerequisites

- Docker runtime installed and running (Colima recommended: `brew install colima docker && colima start`)
- ARM Mac (Apple Silicon) for native arm64 builds
- x86_64 builds work on ARM Macs with Colima (or Docker Desktop with Rosetta enabled)

## Quick Start

### Build arm64 (Native on Apple Silicon)

```bash
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -e CLI_VERSION="1.1.0" \
  -w /build \
  --platform linux/arm64 \
  swift:6.0-noble \
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

    # Build CLIs
    cd /build
    printf "// Generated at build time\nlet generatedCLIVersion = \"1.1.0\"\n" > Sources/ContextifyIngestionCLI/Version.generated.swift
    swift build -c release --product contextify-query --static-swift-stdlib -Xswiftc -DGENERATED_VERSION
    swift build -c release --product contextify-ingest --static-swift-stdlib -Xswiftc -DGENERATED_VERSION

    # Package
    cp .build/release/contextify-ingest .build/release/contextify-query /output/
    cp -R contextify-query/user-skill /output/
    cd /output && tar -czvf contextify-linux-arm64.tar.gz contextify-ingest contextify-query user-skill
    rm -f contextify-ingest contextify-query && rm -rf user-skill
  '
```

### Build x86_64 (Works with Colima on ARM Mac)

ARM Macs can build x86_64 using Colima, which uses Lima VMs with Apple's Virtualization.framework.

```bash
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -w /build \
  --platform linux/amd64 \
  swift:6.0-noble \
  bash -c '
    set -e
    cp -r /workspace/Sources /workspace/Package.swift /workspace/Package.resolved /workspace/app /workspace/contextify-query /build/
    apt-get update -qq && apt-get install -y build-essential curl pkg-config -qq > /dev/null 2>&1
    cd /tmp
    curl -sL "https://www.sqlite.org/2024/sqlite-autoconf-3450100.tar.gz" | tar xz
    cd sqlite-autoconf-*
    CFLAGS="-DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -O2" \
      ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --disable-shared --quiet
    make -j$(nproc) --quiet && make install --quiet && ldconfig
    cd /build
    printf "// Generated at build time\nlet generatedCLIVersion = \"1.1.0\"\n" > Sources/ContextifyIngestionCLI/Version.generated.swift
    swift build -c release --product contextify-query --static-swift-stdlib -Xswiftc -DGENERATED_VERSION
    swift build -c release --product contextify-ingest --static-swift-stdlib -Xswiftc -DGENERATED_VERSION
    cp .build/release/contextify-ingest .build/release/contextify-query /output/
    cp -R contextify-query/user-skill /output/
    cd /output && tar -czvf contextify-linux-x86_64.tar.gz contextify-ingest contextify-query user-skill
    rm -f contextify-ingest contextify-query && rm -rf user-skill
  '
```

**Note on Docker runtimes:**
- **Colima:** Works for both arm64 and x86_64 on ARM Macs
- **Docker Desktop:** May require enabling "Use Rosetta for x86_64/amd64 emulation" in settings, or may crash with "Illegal instruction" under QEMU

## Worktree Compatibility

When building from a git worktree, mount the workspace as read-only (`:ro`) and use a container-internal build directory (`-w /build`). This avoids git path resolution issues where Docker can't access the parent `.git` directory.

## Build Artifacts

Output location: `dist/contextify-linux-{arch}.tar.gz`

Contents:
- `contextify-ingest` - Database ingestion CLI
- `contextify-query` - Query CLI with Total Recall skill
- `user-skill/` - Total Recall skill files

## Verification

After building, verify static linking:

```bash
# Extract and check
tar -tzf dist/contextify-linux-arm64.tar.gz
docker run --rm -v "$PWD/dist":/dist swift:6.0-noble ldd /dist/contextify-query
# Should show no libsqlite3.so dependency
```

## CI vs Local: Which to Use?

| Scenario | Recommendation |
|----------|----------------|
| Normal releases | GitHub Actions (both architectures) |
| Quota exhausted | Local Docker with Rosetta (both architectures) |
| Quick iteration | Local Docker |
| Official release | Both should match - binaries are identical |

## Troubleshooting

### "Illegal instruction" on x86_64

This error occurs with Docker Desktop's QEMU emulation. Solutions:
- **Switch to Colima:** `brew install colima && colima start` - uses Apple's Virtualization.framework
- **Enable Rosetta in Docker Desktop:** Settings → General → "Use Rosetta for x86_64/amd64 emulation"
- **Use GitHub Actions or an Intel Mac**

### Git "dubious ownership" errors

Mount workspace as read-only (`:ro`) and copy files to container-internal path.

### SwiftPM cache permission errors

These warnings are harmless - SwiftPM can't write to the cache in the read-only mount but downloads work.

---

**Last Updated**: 2026-01-12
