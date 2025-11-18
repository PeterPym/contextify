# ProjectDiscoveryService Implementation Guide

**Status:** Active (2025-11-17)
**Related:** `build/docs/components/project-discovery.md`, `ProjectDiscoveryService.swift`
**Purpose:** Deep implementation guide for multi-provider scanning, security-scoped access, and performance optimization

---

## Executive Summary

This document provides implementation-level details for **ProjectDiscoveryService** beyond the component overview. Read this when:
- Adding support for new transcript providers
- Debugging discovery performance issues
- Understanding security-scoped access patterns
- Investigating deduplication logic
- Working with sandboxed (App Store) builds

**Related Component Doc:** `build/docs/components/project-discovery.md` - Read that first for high-level architecture.

---

## Actor Concurrency Model

### Why Actor?

**ProjectDiscoveryService** is an `actor` (not `@MainActor` class) for several reasons:

```swift
// ProjectDiscoveryService.swift:6
public actor ProjectDiscoveryService {
    private let db: DatabasePool
    private let orchestrator: TranscriptOrchestrator
    private let folderAccessController: FolderAccessController?
    private var ingestionErrors: [String: String] = [:]
    private var cachedCodexTranscriptsByProject: [String: [String]] = [:]
    private var codexScanPerformed = false
}
```

**Design Rationale:**

1. **Isolation of mutable state**
   - `ingestionErrors` map tracks failures per project
   - `cachedCodexTranscriptsByProject` caches Codex transcript paths
   - `codexScanPerformed` prevents redundant scans
   - Actor ensures thread-safe access (no data races)

2. **Off-main-thread execution**
   - Discovery involves expensive FileManager operations (thousands of files)
   - Blocking main thread would freeze UI during scans
   - Actor methods run on background thread by default

3. **Serialization of concurrent requests**
   - Multiple UI components might trigger discovery simultaneously
   - Actor queue serializes requests automatically (no explicit locks)

**Consequence:** Callers must `await` all methods:
```swift
let projects = try await discoveryService.discoverAllProjects(currentProjectPath: path)
```

---

## Security-Scoped Access Patterns

### The Problem: Sandboxed Builds

App Store builds run in **sandbox** with restricted filesystem access:
- **Cannot** read `~/.claude/projects` by default
- **Cannot** read `~/.codex/sessions` by default
- **Must** obtain user permission via file picker or folder authorization
- **Must** use security-scoped bookmarks to maintain access

### The Solution: `withClaudeRoot` and `withCodexRoot`

**Pattern:**

```swift
// ProjectDiscoveryService.swift:46-67
private func withClaudeRoot<T>(
    _ operation: @Sendable (URL) throws -> T
) async throws -> T where T: Sendable {
    guard let controller = folderAccessController else {
        // Non-sandboxed build: direct filesystem access
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        return try operation(root)
    }

    // Sandboxed build: security-scoped access required
    guard let auth = await controller.authorization(for: .claude),
          auth.status == .authorized else {
        throw FolderAccessError.securityScopeAccessDenied(...)
    }

    return try await controller.withAccess(auth, operation)
}
```

**How It Works:**

1. **Check for controller** - `nil` means DMG build (unsandboxed), direct access OK
2. **Get authorization** - Query `FolderAccessController` for Claude folder permission
3. **Execute with access** - `withAccess()` calls `startAccessingSecurityScopedResource()`, runs operation, calls `stopAccessingSecurityScopedResource()`

**Critical Rule:** All `FileManager` operations MUST happen inside the `operation` closure:

```swift
// ✅ CORRECT
let projects = try await withClaudeRoot { root in
    let dirs = try FileManager.default.contentsOfDirectory(at: root, ...)
    return dirs.map { processDirectory($0) }
}

// ❌ WRONG - FileManager call outside security scope
let root = try await withClaudeRoot { $0 }
let dirs = try FileManager.default.contentsOfDirectory(at: root, ...)  // Fails!
```

**Why:** Security scope is **only active** during closure execution. The returned `URL` is just a path string - it carries no active security scope.

### Graceful Authorization Failures

Discovery methods **do not crash** if authorization is missing:

```swift
// ProjectDiscoveryService.swift:220-275 (quickDiscoverNewest)
let claudeCandidates: [(projectPath: URL, transcriptFile: URL, mtime: Date)]
do {
    claudeCandidates = try await withClaudeRoot { root in
        // ... scan logic ...
    }
} catch {
    // Authorization not granted yet (first launch)
    logger.debug("[QUICK-DISCOVERY] Claude scan skipped (no authorization)")
    claudeCandidates = []  // ← Empty list, not error throw
}
```

**Behavior:**
- First launch → no permissions → returns empty list → welcome modal shown
- User grants permission → next discovery → returns projects

---

## Multi-Provider Scanning

### Provider 1: Claude Code (Directory-Based)

**Location:** `~/.claude/projects/<mangled-path>/*.jsonl`

**Discovery Algorithm:**

```swift
// ProjectDiscoveryService.swift:467-486
private func discoverClaudeCodeProjects() async throws -> [URL] {
    return try await withClaudeRoot { root in
        // 1. List all subdirectories under ~/.claude/projects
        let subdirs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        // 2. Reverse-map each directory to original project path
        return subdirs.compactMap { dir in
            reversePathMapping(dirURL: dir)
        }
    }
}
```

**Reverse Mapping:** See "Path Reverse Mapping" section below.

### Provider 2: Codex CLI (cwd-Based)

**Location:** `~/.codex/sessions/YYYY/MM/DD/*.jsonl` (global tree)

**Challenge:** Codex transcripts are NOT organized by project directory. They live in a global time-based tree:
```
~/.codex/sessions/
  ├── 2025/11/15/rollout-abc123.jsonl    # cwd: /Users/me/project-A
  ├── 2025/11/16/rollout-def456.jsonl    # cwd: /Users/me/project-B
  └── 2025/11/17/rollout-ghi789.jsonl    # cwd: /Users/me/project-A
```

**Discovery Algorithm:**

1. **Scan entire tree** (recursively 3 levels deep: YYYY/MM/DD)
2. **Extract `cwd` field** from each JSONL file (via `ProjectIdentity.extractCwdFromTranscriptForOrphaned`)
3. **Group by `cwd`** to associate transcripts with projects
4. **Cache results** in `cachedCodexTranscriptsByProject` (avoids re-parsing JSONL)

**Code:**

```swift
// ProjectDiscoveryService.swift:590-599
private func ensureCodexTranscriptCache() async {
    guard !codexScanPerformed else { return }
    codexScanPerformed = true

    let grouped = try await withCodexRoot { root in
        // Recursively find all .jsonl files (YYYY/MM/DD)
        let codexFiles = // ... recursive directory scan ...

        // Parse cwd from each file and group by project path
        var grouped: [String: [String]] = [:]
        for file in codexFiles {
            if let cwd = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(file) {
                grouped[cwd, default: []].append(file.path)
            }
        }
        return grouped
    }

    cachedCodexTranscriptsByProject = grouped
}
```

**Performance:** Caching prevents re-parsing thousands of JSONL files on every discovery.

### Deduplication Logic

**Question:** What if the same project has both Claude Code AND Codex transcripts?

**Answer:** Projects are deduplicated by **filesystem path** (project root):

```swift
// ProjectDiscoveryService.swift:112-144
for projectPath in claudeProjects {
    let metadata = try await getProjectMetadata(projectId: projectPath.path)

    // Get providers from database (based on ingested transcripts)
    var providers = metadata.providers

    // Ensure Claude is shown (even before first ingestion)
    if providers.isEmpty {
        providers.insert(.claudeCode)
    }

    discovered.append(DiscoveredProject(
        id: projectPath.path,  // ← Path is unique ID
        name: name,
        path: projectPath,
        providers: providers,  // ← May contain both .claudeCode and .codex
        ...
    ))
}
```

**How Providers Are Detected:**

1. **During ingestion:** Transcripts are upserted to database with `provider` column
2. **During discovery:** Database query aggregates distinct providers per project
3. **UI display:** Projects show both icons if transcripts from multiple providers exist

**Example:**
```
Project: /Users/me/myapp
Providers: [.claudeCode, .codex]
← Has transcripts in both ~/.claude/projects/Users-me-myapp/ AND ~/.codex/sessions/2025/11/*/rollout-*.jsonl
```

---

## Quick Discovery vs Full Discovery

### Quick Discovery (Phase 2 - Cold Start)

**Goal:** Find newest project **without** parsing JSONL or writing to database.

**Target:** <500ms for 10-20 projects

**Algorithm:**

```swift
// ProjectDiscoveryService.swift:210-381
public func quickDiscoverNewest() async -> (projectPath: URL, transcriptFile: URL, mtime: Date)? {
    // PART 1: Claude Code - scan directories for newest .jsonl file
    let claudeCandidates = try await withClaudeRoot { root in
        let projectDirs = try FileManager.default.contentsOfDirectory(at: root, ...)

        var results: [(projectPath: URL, transcriptFile: URL, mtime: Date)] = []
        for claudeDir in projectDirs {
            let projectPath = reversePathMapping(dirURL: claudeDir)
            let files = try FileManager.default.contentsOfDirectory(at: claudeDir, ...)
                .filter { $0.pathExtension == "jsonl" }

            // Find newest file by mtime
            let filesWithMtimes = files.compactMap { file -> (URL, Date)? in
                guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return (file, mtime)
            }

            if let newestFile = filesWithMtimes.max(by: { $0.1 < $1.1 }) {
                results.append((projectPath, newestFile.0, newestFile.1))
            }
        }
        return results
    }

    // PART 2: Codex - scan global sessions tree, extract cwd, group by project
    let codexCandidates = try await withCodexRoot { root in
        let codexFiles = // ... recursive scan of YYYY/MM/DD ...

        var codexProjectNewest: [String: (file: URL, mtime: Date)] = [:]
        for file in codexFiles {
            let mtime = // ... get mtime ...
            let cwd = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(file)

            // Track newest file per project
            if codexProjectNewest[cwd].mtime < mtime {
                codexProjectNewest[cwd] = (file, mtime)
            }
        }

        return codexProjectNewest.map { (URL(fileURLWithPath: $0.key), $0.value.file, $0.value.mtime) }
    }

    // PART 3: Find global newest across both providers
    let allCandidates = claudeCandidates + codexCandidates
    return allCandidates.max(by: { $0.mtime < $1.mtime })
}
```

**What's Skipped:**
- JSONL parsing (except cwd extraction for Codex)
- Database writes
- Provider metadata aggregation

**What's Returned:**
- Project path
- Transcript file path
- Modification time

**Use Case:** `StartupCoordinator` calls this to switch to newest project before timeline loads.

### Full Discovery (Phase 3 - Background)

**Goal:** Enumerate all projects with metadata (transcript count, providers, last activity).

**Algorithm:**

```swift
// ProjectDiscoveryService.swift:97-189
public func discoverAllProjects(currentProjectPath: String?) async throws -> [DiscoveredProject] {
    // 1. Scan Claude Code projects
    let claudeProjects = try await discoverClaudeCodeProjects()

    var discovered: [DiscoveredProject] = []

    // 2. For each project, get metadata from database
    for projectPath in claudeProjects {
        let metadata = try await getProjectMetadata(projectId: projectPath.path)
        let name = deriveProjectName(from: projectPath)

        discovered.append(DiscoveredProject(
            id: projectPath.path,
            name: name,
            path: projectPath,
            providers: metadata.providers,      // ← From database
            transcriptCount: metadata.transcriptCount,  // ← From database
            entryCount: metadata.entryCount,    // ← From database
            lastActivity: metadata.lastActivity, // ← From database
            isCurrent: projectPath.path == currentProjectPath,
            ingestionError: ingestionErrors[projectPath.path],
            displayOrder: metadata.displayOrder
        ))
    }

    // 3. Pre-compute mtimes for sorting (parallel via TaskGroup)
    var mtimeCache: [URL: Date] = [:]
    await withTaskGroup(of: (URL, Date).self) { group in
        for project in discovered {
            group.addTask {
                let mtime = await self.getNewestTranscriptMtime(for: project.path)
                return (project.path, mtime)
            }
        }

        for await (path, mtime) in group {
            mtimeCache[path] = mtime
        }
    }

    // 4. Sort by display_order (if set) then newest mtime
    let sorted = discovered.sorted { lhs, rhs in
        if let lOrder = lhs.displayOrder, let rOrder = rhs.displayOrder {
            return lOrder < rOrder  // Explicit ordering
        } else if lhs.displayOrder != nil {
            return true  // Projects with order come first
        } else if rhs.displayOrder != nil {
            return false
        } else {
            // Newest mtime first
            let lhsMtime = mtimeCache[lhs.path] ?? Date.distantPast
            let rhsMtime = mtimeCache[rhs.path] ?? Date.distantPast
            return lhsMtime > rhsMtime
        }
    }

    return sorted
}
```

**Performance Optimization:** Mtime computation uses `TaskGroup` for parallel execution (16x speedup for 16 projects).

---

## Path Reverse Mapping

### The Problem

Claude Code mangles project paths into directory names:
```
/Users/me/my-app          → Users-me-my-app
/Users/me/app-with-dash   → Users-me-app--with--dash  (hyphens escaped)
```

Discovery must **reverse** this mapping to get original paths.

### Algorithm: JSONL Inspection (Primary)

**Strategy:** Read first ~128KB of JSONL file and extract path from `cwd`, `workspaceRoot`, or file paths.

```swift
// ProjectDiscoveryService.swift:519-588
private nonisolated func reversePathMapping(dirURL: URL) -> URL? {
    // 1. Find any JSONL file in directory
    guard let jsonlFiles = try? FileManager.default.contentsOfDirectory(at: dirURL, ...),
          let jsonl = jsonlFiles.first else {
        return nil
    }

    // 2. Read first 128KB
    guard let data = try? Data(contentsOf: jsonl, options: .mappedIfSafe),
          let text = String(data: data.prefix(131_072), encoding: .utf8) else {
        return nil
    }

    // 3. Search for path patterns using regex
    let patterns = [
        #""(?:cwd|workspaceRoot|root|projectRoot)"\s*:\s*"(/[^"]+)""#,
        #""path"\s*:\s*"(/[^"]+)""#,
        #""file"\s*:\s*"(/[^"]+)""#
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
        if let match = regex.firstMatch(in: text, ...) {
            let extractedPath = String(text[match.range(at: 1)])

            // 4. Validate path exists
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: extractedPath, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: extractedPath)
            }

            // 5. Try parent directories (if we found a file path)
            var parent = URL(fileURLWithPath: extractedPath).deletingLastPathComponent()
            for _ in 0..<3 {
                if FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue {
                    return parent
                }
                parent = parent.deletingLastPathComponent()
            }
        }
    }

    // Fallback: use ProjectIdentity.reverseManglePath()
    return try? ProjectIdentity.reverseManglePath(provider: "claude.code", directory: dirURL)
}
```

**Why This Works:**
- Claude Code transcripts always contain `cwd` or file paths
- Regex extracts absolute paths like `/Users/me/my-app`
- Validation ensures path actually exists (handles moved/deleted projects)

### Fallback: Demangling Algorithm

If JSONL inspection fails (corrupted file, no paths in first 128KB), use **demangling**:

```swift
try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: dirURL)
```

**How It Works:**
```
Users-me-app--with--dash  → /Users/me/app-with-dash
   ↓ Split by single hyphen
   ["Users", "me", "app", "", "with", "", "dash"]
   ↓ Replace empty strings with hyphen
   ["Users", "me", "app-with-dash"]
   ↓ Join with slash
   /Users/me/app-with-dash
```

**Limitation:** Heuristic-based - may fail for edge cases (e.g., project name starts with hyphen).

---

## Performance Characteristics

### Discovery Latencies (10-20 Projects)

| Operation | Target | Typical | Bottleneck |
|-----------|--------|---------|------------|
| Quick discovery | <500ms | 200-400ms | FileManager recursive scan |
| Full discovery | <2s | 1-2s | Database metadata queries |
| Parallel mtime scan (16 projects) | N/A | 50-100ms | TaskGroup parallel fetch |

### Scaling Considerations

**100+ Projects:**
- Quick discovery: ~1-2s (linear in project count)
- Full discovery: ~5-10s (database queries dominate)
- Mtime scan: ~500ms (TaskGroup parallelization helps)

**Optimization Opportunities:**
1. **Incremental discovery:** Only scan for new projects since last scan
2. **Mtime caching:** Persist mtimes in database, only re-scan on file change
3. **Lazy loading:** Load metadata on-demand (only visible projects)

### Memory Usage

**Quick Discovery:**
- ~10KB per project (URL, mtime, transcript path)
- 100 projects = ~1MB

**Full Discovery:**
- ~50KB per project (includes database metadata, provider set, error messages)
- 100 projects = ~5MB

**Codex Cache:**
- ~500B per transcript (path string)
- 1000 transcripts = ~500KB

**Peak Memory:** ~10-20MB for 100-project discovery (dominated by JSONL data reads).

---

## Error Handling

### Ingestion Errors (Per-Project Tracking)

**Pattern:**

```swift
// ProjectDiscoveryService.swift:10
private var ingestionErrors: [String: String] = [:]  // projectPath -> error message

// ProjectDiscoveryService.swift:433-437
} catch {
    logger.error("Failed to ingest project \(projectName): \(error)")
    ingestionErrors[projectPath.path] = error.localizedDescription
    // Continue with other projects (don't propagate error)
}
```

**Behavior:**
- Ingestion failures **do not stop** discovery
- Errors are **stored** per project
- UI displays error indicator next to failed projects
- Next successful ingest **clears** error

**Use Case:** One corrupted JSONL file shouldn't prevent discovering 99 other projects.

### Authorization Failures (Graceful Degradation)

**Pattern:**

```swift
// ProjectDiscoveryService.swift:270-275
} catch {
    // Authorization not granted yet (first launch)
    logger.debug("[QUICK-DISCOVERY] Claude scan skipped (no authorization)")
    claudeCandidates = []  // ← Empty list, not error
}
```

**Behavior:**
- Missing permissions → empty project list
- Welcome modal shown → user grants access → next discovery succeeds

### Network Filesystem Timeouts

**Problem:** `FileManager.contentsOfDirectory` can hang on network drives (NFS, SMB).

**Mitigation:** Currently none (blocking call). Future improvement: timeout wrapper.

**Workaround:** Use local disk for `~/.claude/projects` and `~/.codex/sessions`.

---

## Caching Strategy

### Codex Transcript Cache

**Why Cache?**

Codex discovery requires parsing `cwd` field from **every JSONL file** in `~/.codex/sessions` tree. With 1000+ transcripts, this takes 5-10 seconds.

**Implementation:**

```swift
// ProjectDiscoveryService.swift:13-14
private var cachedCodexTranscriptsByProject: [String: [String]] = [:]
private var codexScanPerformed = false

// ProjectDiscoveryService.swift:590-599
private func ensureCodexTranscriptCache() async {
    guard !codexScanPerformed else { return }  // ← One-time scan
    codexScanPerformed = true

    let grouped = try await withCodexRoot { root in
        // ... scan all JSONL files, group by cwd ...
    }

    cachedCodexTranscriptsByProject = grouped
}
```

**Cache Lifetime:**
- Lives for duration of `ProjectDiscoveryService` actor instance
- Typically lives for entire app session
- Invalidated on explicit call to `invalidateCodexCache()`

**Cache Invalidation:**

```swift
// ProjectDiscoveryService.swift:98
public func discoverAllProjects(...) async throws -> [DiscoveredProject] {
    invalidateCodexCache()  // ← Force re-scan
    // ...
}
```

**Trade-off:**
- **Pro:** 10x speedup on subsequent discoveries
- **Con:** Stale cache if user creates new Codex transcript (fixed on next full discovery)

---

## Testing Strategies

### Unit Testing: Actor Isolation

**Challenge:** `ProjectDiscoveryService` is an actor - can't directly inspect private state.

**Solution:** Test via public API:

```swift
func testDiscoverAllProjects() async throws {
    let service = ProjectDiscoveryService(
        db: testDB,
        orchestrator: testOrchestrator,
        folderAccessController: nil  // ← Use DMG mode for testing
    )

    let projects = try await service.discoverAllProjects(currentProjectPath: nil)

    XCTAssertGreaterThan(projects.count, 0)
    XCTAssert(projects.allSatisfy { !$0.path.path.isEmpty })
}
```

### Integration Testing: Security-Scoped Access

**Setup:**

```bash
# Build App Store variant
bash scripts/xc.sh --dist=appstore Debug build

# Grant folder access via welcome modal
open .derived/Build/Products/Debug/Contextify.app
```

**Test:**

```swift
func testSandboxedDiscovery() async throws {
    let controller = FolderAccessController.shared
    let service = ProjectDiscoveryService(
        db: DatabaseManager.shared.pool,
        orchestrator: try TranscriptOrchestrator(dbManager: .shared),
        folderAccessController: controller
    )

    // Should succeed if user granted access
    let projects = try await service.discoverAllProjects(currentProjectPath: nil)

    XCTAssertGreaterThan(projects.count, 0)
}
```

### Performance Testing

**Benchmark:**

```swift
func testQuickDiscoveryPerformance() async throws {
    let service = ProjectDiscoveryService(...)

    measure {
        let result = try await service.quickDiscoverNewest()
        XCTAssertNotNil(result)
    }

    // Assert: <500ms for typical setups
}
```

**Profile with Instruments:**
- Record Time Profiler trace during `discoverAllProjects()`
- Filter to `ProjectDiscoveryService` frames
- Identify hot paths (FileManager calls, regex matching)

---

## Common Pitfalls

### Pitfall 1: FileManager Outside Security Scope

**Anti-pattern:**
```swift
let root = try await withClaudeRoot { $0 }
let dirs = try FileManager.default.contentsOfDirectory(at: root, ...)  // ☠️ Fails!
```

**Correct:**
```swift
let dirs = try await withClaudeRoot { root in
    try FileManager.default.contentsOfDirectory(at: root, ...)
}
```

### Pitfall 2: Blocking Main Thread

**Anti-pattern:**
```swift
@MainActor
class ViewModel {
    func loadProjects() {
        // ☠️ Blocking main thread with actor call
        let projects = await discoveryService.discoverAllProjects(...)
        self.projects = projects
    }
}
```

**Correct:**
```swift
@MainActor
class ViewModel {
    func loadProjects() {
        Task {
            let projects = try await discoveryService.discoverAllProjects(...)
            self.projects = projects  // ← Updates UI on main thread
        }
    }
}
```

### Pitfall 3: Ignoring Ingestion Errors

**Anti-pattern:**
```swift
let projects = try await service.discoverAllProjects(...)
// Assume all projects ingested successfully ☠️
```

**Correct:**
```swift
let projects = try await service.discoverAllProjects(...)
let failed = projects.filter { $0.ingestionError != nil }
if !failed.isEmpty {
    logger.warning("Failed to ingest \(failed.count) projects")
    // Display error indicators in UI
}
```

### Pitfall 4: Stale Codex Cache

**Problem:** User creates new Codex transcript → doesn't appear in discovery.

**Solution:** Call `invalidateCodexCache()` before `discoverAllProjects()`:

```swift
// ProjectDiscoveryService.swift:98
public func discoverAllProjects(...) async throws -> [DiscoveredProject] {
    invalidateCodexCache()  // ← Already done!
    // ...
}
```

**Note:** Cache is automatically invalidated on full discovery.

---

## Debugging Workflows

### Scenario: Project Not Discovered

**Symptoms:**
- Project with transcripts doesn't appear in project list
- Project appears in one build (DMG) but not another (App Store)

**Debug Steps:**

1. **Check security-scoped access:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "ProjectDiscovery"' \
     | grep "authorization"
   ```

2. **Check Claude directory exists:**
   ```bash
   ls -la ~/.claude/projects
   ```

3. **Check reverse mapping:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "ProjectDiscovery"' \
     | grep "reversePathMapping"
   ```

4. **Manually test reverse mapping:**
   ```swift
   let dir = URL(fileURLWithPath: "~/.claude/projects/Users-me-my-app")
   let projectPath = reversePathMapping(dirURL: dir)
   print(projectPath)  // Should match /Users/me/my-app
   ```

### Scenario: Slow Discovery (>5s)

**Debug Steps:**

1. **Profile with logs:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "ProjectDiscovery"' \
     --level debug \
     | grep "DISCOVERY"
   ```

2. **Check project count:**
   ```bash
   ls ~/.claude/projects | wc -l
   ```

3. **Check Codex transcript count:**
   ```bash
   find ~/.codex/sessions -name "*.jsonl" | wc -l
   ```

4. **Profile with Instruments:**
   - Record Time Profiler
   - Filter to `discoverAllProjects` stack frames
   - Identify bottleneck (FileManager, regex, database)

### Scenario: Missing Providers

**Symptoms:**
- Project discovered but providers list empty
- Project shows only Claude icon but has Codex transcripts

**Debug Steps:**

1. **Check database providers:**
   ```sql
   SELECT DISTINCT provider FROM transcripts WHERE project_id = '<project-id>';
   ```

2. **Check ingestion errors:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "ProjectDiscovery"' \
     | grep "ingestion"
   ```

3. **Verify transcripts ingested:**
   ```sql
   SELECT COUNT(*) FROM transcripts WHERE project_id = '<project-id>';
   ```

---

## Extension Points

### Adding New Provider

**Example:** Add support for Cursor IDE transcripts at `~/.cursor/sessions`.

**Steps:**

1. **Add provider enum case:**
   ```swift
   public enum TranscriptProvider {
       case claudeCode
       case codex
       case cursor  // ← New
   }
   ```

2. **Add security-scoped access helper:**
   ```swift
   private func withCursorRoot<T>(
       _ operation: @Sendable (URL) throws -> T
   ) async throws -> T where T: Sendable {
       // Similar to withClaudeRoot
   }
   ```

3. **Add discovery method:**
   ```swift
   private func discoverCursorProjects() async throws -> [URL] {
       return try await withCursorRoot { root in
           // Scan logic based on Cursor's directory structure
       }
   }
   ```

4. **Integrate into `discoverAllProjects()`:**
   ```swift
   let cursorProjects = try await discoverCursorProjects()
   // Merge with claudeProjects, deduplicate by path
   ```

### Custom Sorting Logic

**Use Case:** Sort by last entry timestamp instead of file mtime.

**Implementation:**

```swift
// Replace mtime-based sort with database query sort
let sorted = discovered.sorted { lhs, rhs in
    lhs.lastActivity > rhs.lastActivity  // ← Database timestamp
}
```

**Trade-off:** Requires database query per project (slower for large counts).

---

## Related Documentation

- **Component Overview:** `build/docs/components/project-discovery.md`
- **Source:** `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift` (1000 lines)
- **Security-Scoped Access:** `build/docs/architecture/transcript-access-security.md`
- **Database Schema:** `build/docs/architecture/sql-backend.md`
- **ProjectIdentity:** `app/Sources/ContextifyCore/Database/ProjectIdentity.swift`

---

## Changelog

**2025-11-17:**
- Initial implementation guide created
- Documents actor concurrency model and isolation
- Security-scoped access patterns (withClaudeRoot/withCodexRoot)
- Multi-provider scanning (Claude Code directory-based, Codex cwd-based)
- Quick discovery vs full discovery strategies
- Path reverse mapping algorithm (JSONL inspection + demangling fallback)
- Deduplication logic and provider detection
- Caching strategy for Codex transcripts
- Performance characteristics and scaling considerations
- Error handling (ingestion errors, authorization failures)
- Testing strategies and debugging workflows
