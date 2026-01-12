# Cross-Platform Architecture

Contextify supports both macOS (full application) and Linux (ingestion CLI only). This document explains the architecture that enables cross-platform support while sharing core ingestion logic.

---

## Overview

Contextify is a macOS application at its core, but its transcript ingestion engine is designed to run on Linux for server-side or headless scenarios. This enables:

- **macOS users:** Full HUD experience with LLM summaries, real-time monitoring, search
- **Linux users:** CLI-based transcript ingestion into Contextify-compatible databases
- **Server deployments:** Automated ingestion via cron/systemd with database sync to macOS

The Linux CLI produces SQLite databases that are fully compatible with the macOS app.

---

## Package Structure

The project uses conditional compilation in `Package.swift` to build different targets per platform.

### macOS Build

```
Products:
  - ContextifyCore (library)           # Full app library
  - TranscriptValidatorCLI (executable)
  - contextify-query (executable)
  - contextify-ingest (executable)

Targets:
  - ContextifyCore                     # All sources in app/Sources/ContextifyCore
  - ContextifyIngestionCLI             # Depends on ContextifyCore
  - ContextifyCoreTests                # Full test suite
```

### Linux Build

```
Products:
  - ContextifyIngestionCore (library)  # Ingestion-only subset
  - contextify-ingest (executable)     # CLI binary

Targets:
  - ContextifyIngestionCore            # Explicit source list (19 files)
  - ContextifyIngestionCLI             # Depends on ContextifyIngestionCore
```

### Source Selection

On Linux, only ingestion-related sources are compiled. The explicit list in `Package.swift`:

```swift
let linuxSources: [String] = [
  // Platform abstractions
  "Platform/CrossPlatformCrypto.swift",
  "Platform/CrossPlatformLock.swift",
  "Platform/CrossPlatformLogger.swift",
  "Platform/IngestionEventSink.swift",
  "Platform/PlatformSandbox.swift",
  // Database layer
  "Database/DatabaseSchema.swift",
  "Database/KeyGeneration.swift",
  "Database/Models.swift",
  "Database/PathNormalizer.swift",
  "Database/Repositories.swift",
  "Database/HooverEngine.swift",
  "Database/TranscriptParsers.swift",
  "Database/IngestProgress.swift",
  "Database/Utilities/TimeUnits.swift",
  // Discovery and core types
  "Discovery/LightweightDiscoveryService.swift",
  "Clock.swift",
  "ContextifyConfig.swift",
  "LoggingConfig.swift",
  "ProjectIdentity.swift",
  "Projects/ProjectModels.swift",
  "Projects/TranscriptAccessProvider.swift",
  "Projects/TranscriptProviderID.swift",
]
```

This explicit list ensures Linux builds don't accidentally pull in macOS-only code.

---

## Platform Abstractions

Five platform abstraction modules enable shared code to work on both platforms.

### CrossPlatformLogger

**Purpose:** Unified logging API across platforms.

| Platform | Implementation |
|----------|----------------|
| Darwin | Wraps `OSLog.Logger` with system-integrated logging |
| Linux | Writes to stderr with timestamp/level prefixes |

**File:** `app/Sources/ContextifyCore/Platform/CrossPlatformLogger.swift`

**Usage:**
```swift
let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "Parser")
log.info("Processing started")
log.error("Failed: \(error)")
```

### CrossPlatformCrypto

**Purpose:** SHA256 hashing for project identity and checksums.

| Platform | Implementation |
|----------|----------------|
| Darwin | Uses `CryptoKit.SHA256` |
| Linux | Uses `Crypto.SHA256` from swift-crypto package |

**File:** `app/Sources/ContextifyCore/Platform/CrossPlatformCrypto.swift`

**Usage:**
```swift
let hash = CrossPlatformCrypto.sha256("input string")
let prefix = CrossPlatformCrypto.sha256Prefix(data, length: 12)
```

### CrossPlatformLock

**Purpose:** Thread-safe state protection with consistent API.

| Platform | Implementation |
|----------|----------------|
| Darwin | Wraps `OSAllocatedUnfairLock<State>` for maximum performance |
| Linux | Uses `NSLock` with reentrancy detection (DEBUG only) |

**File:** `app/Sources/ContextifyCore/Platform/CrossPlatformLock.swift`

**Usage:**
```swift
let lock = CrossPlatformLock(initialState: MyState())
lock.withLock { state in
  state.counter += 1
}
```

### PlatformSandbox

**Purpose:** Sandbox detection for App Store builds.

| Platform | Implementation |
|----------|----------------|
| Darwin | Detects App Store sandbox via entitlements |
| Linux | Always returns `false` (no sandbox concept) |

**File:** `app/Sources/ContextifyCore/Platform/PlatformSandbox.swift`

**Usage:**
```swift
if Sandbox.isSandboxed {
  // App Store sandbox-specific code path
}
```

### IngestionEventSink

**Purpose:** Protocol for reporting ingestion events (progress, errors, completion).

**File:** `app/Sources/ContextifyCore/Platform/IngestionEventSink.swift`

The CLI implements this with `CLIEventSink` for human-readable or JSONL output.

---

## Feature Parity Matrix

| Feature | macOS App | Linux CLI |
|---------|-----------|-----------|
| **Transcript ingestion** | Yes | Yes |
| **Database creation** | Yes | Yes |
| **Full-text search index** | Yes | Yes |
| **Project discovery** | Yes | Yes (lightweight) |
| **Total Recall skill** | Yes | Yes |
| **contextify-query CLI** | Yes | Yes |
| **Real-time file watching** | Yes | No |
| **LLM summaries** | Yes (macOS 26+) | No |
| **Timeline cache generation** | Yes | No |
| **UI/HUD** | Yes | No |
| **Transcript metadata (LLM)** | Yes | No |
| **Security-scoped bookmarks** | Yes | N/A |
| **Background indexing** | Yes | N/A (batch mode) |

### Why Linux Has Fewer Features

- **LLM summaries:** Require Apple's FoundationModels framework (macOS 26+)
- **Real-time watching:** FSEvents is Darwin-only; Linux equivalent (inotify) not yet implemented
- **Timeline cache:** Generated by LLM, which requires macOS
- **UI:** SwiftUI/AppKit are Darwin-only

The CLI focuses on reliable batch ingestion. The macOS app handles real-time and LLM features.

---

## Database Compatibility

Databases created by the Linux CLI are fully compatible with the macOS app:

- **Same schema:** Both use `DatabaseSchema.swift` (currently v32+)
- **Same migrations:** Schema migrations run identically on both platforms
- **Same content:** Projects, transcripts, entries are stored identically
- **FTS5 index:** Full-text search index is created and usable

### Sync Strategy

For cross-machine workflows:

1. **Linux server ingests transcripts:** `contextify-ingest ingest --db /path/to/shared.db`
2. **Database synced to macOS:** Via Dropbox, iCloud Drive, rsync, etc.
3. **macOS app opens database:** Settings > Database > Custom Location

The app detects external modifications and refreshes as needed.

---

## CLI Architecture

The Linux CLI (`contextify-ingest`) is structured as:

```
ContextifyIngestionCLI/
  main.swift              # Entry point, command configuration
  Commands/
    IngestCommand.swift   # Main ingestion logic
    DiscoverCommand.swift # Find transcripts without ingesting
    VerifyCommand.swift   # Database integrity checks
    SchemaCommand.swift   # Schema inspection
  CLIEventSink.swift      # Progress/error output (human/JSONL)
  DatabaseOpener.swift    # Database setup with FTS5 preflight
```

The CLI reuses the same ingestion engine (`HooverEngine`) as the macOS app.

---

## Build & CI

### Local Development

```bash
# Build for current platform (macOS)
swift build --product contextify-ingest

# Build for Linux via Docker
bash scripts/docker-linux-build.sh

# Build for Linux with E2E test
bash scripts/docker-linux-build.sh --e2e
```

### GitHub Actions

- **linux-build.yml:** PR/push builds with E2E test
- **linux-release.yml:** Tagged releases (cli-v*) for x86_64 and arm64

### SQLite Requirements

Linux builds require SQLite with `SQLITE_ENABLE_SNAPSHOT` and `SQLITE_ENABLE_FTS5`. The CI workflow builds SQLite from source; the Docker script does the same locally.

---

## See Also

- **CLI usage:** `Sources/ContextifyIngestionCLI/README.md`
- **Swift patterns:** `build/docs/guides/cross-platform-swift.md`
- **CI builds:** `build/docs/guides/linux-ci-builds.md`
- **Investigation notes:** `build/notes/todo-support/CROSS-PLATFORM-INGESTION-investigation.md`
- **Ingestion workflow:** `build/docs/architecture/ingestion-workflow.md` (macOS-focused)
- **Database schema:** `build/docs/architecture/sql-backend.md`

---

**Last Updated:** 2026-01-12
