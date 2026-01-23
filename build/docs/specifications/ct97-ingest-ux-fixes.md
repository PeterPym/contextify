---
date: 2026-01-22
project: contextify
branch: main-wb1
status: ready-for-merge
source_session: c4af09a0-6fdc-44eb-86c3-c485e450e5af
reviewed_by: ChatGPT (2 iterations)
---

# CT-97: Ingest UX Fixes - Implementation Plan

## Context for Reviewers

**What is this?** Contextify is a macOS/Linux tool that indexes Claude Code and Codex CLI conversation transcripts into a SQLite database for full-text search ("Total Recall"). The Linux CLI is distributed as a static binary installed via `curl | sh`.

**The user flow being fixed:**
1. User runs `curl -fsSL https://contextify.sh/install.sh | sh`
2. install.sh downloads the binary, then runs `contextify ingest --quiet` as a subprocess
3. Ingest scans `~/.claude/projects/` and `~/.codex/sessions/` for `.jsonl` transcript files
4. Each transcript is parsed and indexed into SQLite (GRDB library)
5. install.sh monitors a progress file (`/tmp/contextify-ingest-progress`) to show "Indexing X/Y transcripts"

**What's broken:** If the user hits Ctrl+C during step 3-4 and re-runs, the SQLite database is locked (WAL not checkpointed) and the second run spews "database is locked" errors. Additionally, progress display is buggy and debug output leaks into production.

**Tech stack:** Swift 6, GRDB (SQLite wrapper), ArgumentParser, static Linux binary (~105MB), deployed via GitHub Releases.

**Key files:**
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift` - Main ingest logic
- `website/install.sh` - Installer script (bash)
- `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` - File discovery

## Summary

Seven changes to improve the Linux CLI ingest experience, focusing on graceful Ctrl+C handling, database lock recovery, and cleaner output.

## Changes

### 1. Signal Handling (SIGINT/SIGTERM)

**Problem:** Ctrl+C during ingest leaves SQLite WAL in dirty state, locking the DB for subsequent runs. The primary root cause is that install.sh backgrounds the ingest process, so Ctrl+C kills the shell but the orphaned ingest keeps running with locks held.

**Approach (two-part fix):**

**Part A: install.sh signal forwarding (the actual fix for the reported bug)**
- Add a `trap` in `run_initial_ingest()` that forwards SIGINT/SIGTERM to `$INGEST_PID`
- Wait for the ingest process to exit after signalling it
- Clean up the progress file

```bash
trap 'kill -INT "$INGEST_PID" 2>/dev/null; wait "$INGEST_PID" 2>/dev/null; rm -f "$PROGRESS_FILE"' INT TERM
```

**Part B: Swift-side graceful shutdown (defense in depth)**
- Register SIGINT/SIGTERM handler using `DispatchSource.makeSignalSource`
- **IMPORTANT:** Call `signal(SIGINT, SIG_IGN)` and `signal(SIGTERM, SIG_IGN)` BEFORE creating the dispatch sources, so the process doesn't terminate before the handler fires
- Handler sets a `ManagedAtomic<Int32>` flag (from swift-atomics) recording which signal was received (0=none, SIGINT=2, SIGTERM=15)
- Main processing loop checks the atomic between transcripts
- On stop: skip remaining files, run `pool.checkpoint(.truncate)`, close DB pool, `throw ExitCode(Int32(128 + signal))`

**Files:**
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift`
- `website/install.sh` (trap in run_initial_ingest)

**Key details:**
- The handler must NOT call async code. Set the atomic, let the loop check it.
- Check the atomic after discovery returns too (discovery takes 5-7s, user may Ctrl+C during it)
- Exit with code 130 (128+SIGINT) or 143 (128+SIGTERM) on signal termination
- `ManagedAtomic<Int32>` from swift-atomics is the correct approach (NOT `nonisolated(unsafe) var` which is a data race in Swift 6)
- Also run `pool.checkpoint(.truncate)` on normal completion (defer block), not just on cancellation
- Pass a `shouldStop` closure `() -> Bool` into the hoover engine for intra-transcript cancellation of large files

---

### 2. SQLite Busy Timeout

**Problem:** If a previous ingest left a lock (zombie process, crash), the next run immediately fails with "database is locked" on every write.

**Approach:**
- Configure GRDB `DatabasePool` with `busyMode: .timeout(2.0)` (2 seconds - shorter for better installer UX)
- This makes SQLite retry internally for up to 2s before failing
- **Note:** WAL recovery after a dead process is automatic on next open (busy timeout is NOT needed for crash recovery). This mainly helps with live lock contention (another process still running).
- If still locked after timeout, print a single user-friendly message: "Database is locked by another process. Wait for it to finish or kill it." (not per-write spam)

**Files:**
- `Sources/ContextifyIngestionCore/Database/DatabaseOpener.swift` (the canonical location for pool configuration - busy mode, journal mode, pragmas)

**Key details:**
- The busy timeout belongs in `DatabaseOpener`, NOT in `IngestCommand`, since `DatabaseOpener.openDatabase(at:)` is where the pool is created
- Also ensure journal_mode=WAL is set in DatabaseOpener (likely already is)

---

### 3. Remove Debug Logging

**Problem:** `[DEBUG] completedTranscripts.count`, `filesNeedingWork.count`, sample paths are printing in production.

**Approach:**
- Remove or gate behind a `--verbose` flag (which doesn't exist yet)
- Simplest: just delete the debug print statements since we've validated the logic works

**Files:**
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift`

---

### 4. Version Number

**Problem:** Binary reports `1.1.0` but release is `v1.2.1`. The build commands hardcode `CLI_VERSION="1.1.0"`.

**Approach:**
- Update build commands in docs and scripts to use `CLI_VERSION="1.2.1"`
- Consider reading version from a canonical source (Package.swift comment, version file, or git tag) instead of hardcoding

**Files:**
- `build/docs/guides/local-linux-builds.md` (build command examples)
- `.github/workflows/linux-build.yml` (if version is hardcoded there)
- Any build scripts that set CLI_VERSION

---

### 5. Progress Display When Nothing To Do

**Problem:** Shows "Indexing... (0s)" briefly before completing when `filesNeedingWork = 0`.

**Approach:**
- In IngestCommand: when `filesNeedingWork.count == 0`, write a special value to the progress file (e.g., `done:260`) and exit early from processing
- In install.sh: detect the "nothing to do" case and skip the progress loop entirely
- **IMPORTANT:** Progress file must be written regardless of `--quiet` flag. It's IPC between CLI and install.sh, not user-facing stdout. The `--quiet` flag should only suppress stdout/stderr output.

**Progress file protocol (full spec):**
- File path: per-run, created by install.sh and passed via env var
- install.sh creates: `PROGRESS_FILE="$(mktemp -t contextify-ingest-progress.XXXXXX)"`
- install.sh exports: `CONTEXTIFY_INGEST_PROGRESS_FILE="$PROGRESS_FILE"`
- Swift reads: `ProcessInfo.processInfo.environment["CONTEXTIFY_INGEST_PROGRESS_FILE"]`
- If env var not set (standalone CLI run), skip progress file writing
- During processing: `<processed>/<total>\n` (e.g., `45/350\n`)
- When nothing to do: `done:<already_complete_count>\n` (e.g., `done:260\n`)
- **Ownership rule:** When env var is set, CLI NEVER deletes the progress file. Installer owns cleanup (reads `done:N` after wait, then deletes). When env var not set (standalone run), CLI skips progress file entirely.
- install.sh behavior: poll file every 0.5s. File always exists (mktemp created it). Empty = "still discovering". `done:N` = break early.

**Why per-run:** Fixed `/tmp/contextify-ingest-progress` is collision-prone (two terminals, two users, stale files from old runs). Using mktemp + env var is safer and simpler.

**Files:**
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift`
- `website/install.sh`

---

### 6. Linux-env Skill: COPYFILE_DISABLE

**Problem:** `tar` on macOS includes `._*` resource fork files, doubling the file count in containers.

**Approach:**
- Update the skill and any copy commands to use `COPYFILE_DISABLE=1 tar -czf ...`
- Add a note in the skill about this macOS tar behavior

**Files:**
- `.claude/skills/linux-env/SKILL.md` (add note about COPYFILE_DISABLE)

---

### 7. Show Indexed Count on Resume Skip

**Problem:** When all transcripts are already indexed, output is confusing - no indication of how many exist.

**Approach:**
- When `filesNeedingWork.count == 0`: write `done:<count>` to progress file AND print human-readable message (if not quiet)
- install.sh reads the progress file `done:N` value and shows: `✓ 260 transcripts indexed (already up to date)`
- When partial work done on resume: show `✓ N new transcripts indexed (M total)`

**install.sh exit code handling:**
- Exit 0: success (read progress file for count, show indexed message)
- Exit 130/143: user cancelled (show "Cancelled. Run again to resume.")
- Any other non-zero: error (show last 20 lines of log file + "Run 'contextify ingest' manually to retry.")

**install.sh run_initial_ingest rewrite (incorporating review feedback):**
```bash
run_initial_ingest() {
    printf "  ${ARROW} Indexing your transcripts...\n"
    printf "     ${DIM}(one-time database setup)${RESET}\n"

    START_TIME=$(date +%s)
    PROGRESS_FILE="$(mktemp -t contextify-ingest-progress.XXXXXX)"
    LOG_FILE="$(mktemp -t contextify-ingest.XXXXXX.log)"
    export CONTEXTIFY_INGEST_PROGRESS_FILE="$PROGRESS_FILE"

    "$INSTALL_DIR/contextify" ingest --quiet >"$LOG_FILE" 2>&1 &
    INGEST_PID=$!

    # Forward signals to ingest process (prevents orphaned locks)
    # NOTE: Do NOT wait inside the trap (causes double-reap / exit code 127)
    # Uses escalation ladder: INT → TERM (2s) → KILL (5s) so installer never hangs
    CANCELLED=0
    trap '
        CANCELLED=1
        kill -INT "$INGEST_PID" 2>/dev/null
        ( sleep 2; kill -0 "$INGEST_PID" 2>/dev/null && kill -TERM "$INGEST_PID" 2>/dev/null
          sleep 3; kill -0 "$INGEST_PID" 2>/dev/null && kill -9 "$INGEST_PID" 2>/dev/null
        ) &
    ' INT TERM

    # Progress display loop
    while kill -0 "$INGEST_PID" 2>/dev/null; do
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ "$ELAPSED" -ge 60 ]; then
            TIME_STR="$((ELAPSED / 60))m $((ELAPSED % 60))s"
        else
            TIME_STR="${ELAPSED}s"
        fi
        PROGRESS=$(cat "$PROGRESS_FILE" 2>/dev/null | tr -d '\n')
        if [ -n "$PROGRESS" ] && [ "$PROGRESS" != "" ]; then
            case "$PROGRESS" in
                done:*) break ;;  # CLI finished early (nothing to do)
                *) printf "\r     ${DIM}Indexing ${PROGRESS} transcripts (${TIME_STR})${RESET}          " ;;
            esac
        else
            printf "\r     ${DIM}Indexing... (${TIME_STR})${RESET}          "
        fi
        sleep 0.5
    done

    printf "\r                                                    \r"

    wait "$INGEST_PID"
    INGEST_STATUS=$?
    trap - INT TERM  # restore default

    # Handle exit codes (CANCELLED flag takes priority over odd exit codes)
    if [ "$CANCELLED" -eq 1 ] || [ "$INGEST_STATUS" -eq 130 ] || [ "$INGEST_STATUS" -eq 143 ]; then
        printf "  ${YELLOW}Cancelled. Run 'contextify ingest' to resume.${RESET}\n"
    elif [ "$INGEST_STATUS" -eq 0 ]; then
        # Read final count from progress file (CLI leaves it for us)
        FINAL=$(cat "$PROGRESS_FILE" 2>/dev/null | tr -d '\n')
        case "$FINAL" in
            done:*)
                COUNT="${FINAL#done:}"
                printf "  ${CHECK} ${COUNT} transcripts indexed (already up to date)\n"
                ;;
            */*)
                # Normal completion: show processed/total
                printf "  ${CHECK} Transcripts indexed\n"
                ;;
            *)
                printf "  ${CHECK} Transcripts indexed\n"
                ;;
        esac
    else
        printf "  ${YELLOW}Indexing had issues:${RESET}\n"
        tail -n 10 "$LOG_FILE" 2>/dev/null
        printf "     ${DIM}Full log: $LOG_FILE${RESET}\n"
    fi

    # Installer owns progress file cleanup (CLI does NOT delete when env var is set)
    rm -f "$PROGRESS_FILE"
}
```

**Files:**
- `Sources/ContextifyIngestionCLI/Commands/IngestCommand.swift`
- `website/install.sh`

---

## Dependencies

- **swift-atomics** package required for `ManagedAtomic<Int32>` (signal flag). Add to Package.swift:
  ```swift
  .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
  ```
  Add `Atomics` to the ContextifyIngestionCLI target dependencies.

## Implementation Order

1. **Items 3 + 4** (trivial cleanup, do first)
2. **Items 1 + 2** (core reliability fixes, most important - includes install.sh trap)
3. **Items 5 + 7** (UX polish, can be combined since both touch progress display + install.sh rewrite)
4. **Item 6** (test tooling, independent)

## Testing

- Build arm64 binary locally
- Fresh container with `COPYFILE_DISABLE=1 tar` for transcripts
- Run install.sh, verify progress shows correctly
- Ctrl+C mid-ingest, verify DB not locked
- Re-run install.sh, verify resume with correct count
- Let it complete, run again, verify "already up to date" message

---

## Build, Test, and Publish Steps

### Step 1: Commit Changes

Atomic commits per logical change:
```
fix(cli): handle SIGINT gracefully during ingest
fix(cli): add SQLite busy timeout for lock recovery
fix(cli): remove debug logging from ingest
fix(cli): update CLI version to 1.2.1
fix(cli): improve progress display for resume/skip cases
fix(install): show indexed count when already up to date
docs: update linux-env skill with COPYFILE_DISABLE
```

### Step 2: Build arm64 Binary (Local)

```bash
# Ensure arm64 Colima is running
colima list  # Verify arm64 profile is Running
docker context use colima-arm64

# Build
docker run --rm \
  -v "$PWD":/workspace:ro \
  -v "$PWD/dist":/output:rw \
  -e CLI_VERSION="1.2.1" \
  -w /build \
  --platform linux/arm64 \
  swift:6.0-jammy \
  bash -c '...'  # Standard arm64 build command
```

### Step 3: QA Test in Container

#### 3a. Container Setup

```bash
# Ensure arm64 Colima is running (NEVER use x86_64 locally)
colima list  # Verify: arm64 Running
# If not running:
colima start --profile arm64 --arch aarch64 --vm-type vz
docker context use colima-arm64

# Verify architecture
docker run --rm ubuntu:22.04 uname -m  # Must show: aarch64

# Create fresh container
docker rm -f contextify-qa 2>/dev/null
docker run -d --name contextify-qa \
  --init \
  --platform linux/arm64 \
  ubuntu:22.04 \
  sleep infinity

# Install deps and create non-root user
docker exec contextify-qa bash -c '
  useradd -m -s /bin/bash testuser
  apt-get update -qq
  apt-get install -y curl ca-certificates sqlite3 -qq > /dev/null 2>&1
'
```

#### 3b. Copy Test Transcripts (~250 Claude Code + ~250 Codex)

**CRITICAL:** Use `COPYFILE_DISABLE=1` to prevent macOS `._*` resource fork files.

```bash
# Package ~250 Claude Code transcripts (top-level only, no subdirectory agents)
cd ~
COPYFILE_DISABLE=1 find .claude/projects -maxdepth 2 -name "*.jsonl" -type f \
  | head -250 \
  | COPYFILE_DISABLE=1 tar -czf /tmp/claude-transcripts.tar.gz -T -

# Package ~250 Codex transcripts (preserving YYYY/MM/DD structure)
COPYFILE_DISABLE=1 find .codex/sessions -name "*.jsonl" -type f \
  | head -250 \
  | COPYFILE_DISABLE=1 tar -czf /tmp/codex-transcripts.tar.gz -T -

# Copy into container
docker cp /tmp/claude-transcripts.tar.gz contextify-qa:/tmp/
docker cp /tmp/codex-transcripts.tar.gz contextify-qa:/tmp/

# Extract as testuser
docker exec -u testuser contextify-qa bash -c '
  cd ~
  tar -xzf /tmp/claude-transcripts.tar.gz
  tar -xzf /tmp/codex-transcripts.tar.gz
  echo "Claude: $(find ~/.claude/projects -name "*.jsonl" -type f | wc -l) files"
  echo "Codex: $(find ~/.codex/sessions -name "*.jsonl" -type f | wc -l) files"
'

# Verify no ._ files leaked in
docker exec -u testuser contextify-qa bash -c '
  echo "Resource fork files: $(find ~ -name "._*" | wc -l)"
'
# Should show: 0
```

#### 3c. Deploy Local Binary (Skip install.sh Download)

```bash
# Copy the locally-built arm64 binary directly
docker cp dist/contextify contextify-qa:/tmp/contextify-new
docker exec -u root contextify-qa bash -c '
  mkdir -p /home/testuser/.local/bin
  mv /tmp/contextify-new /home/testuser/.local/bin/contextify
  chmod +x /home/testuser/.local/bin/contextify
  chown testuser:testuser /home/testuser/.local/bin/contextify
'

# Verify
docker exec -u testuser contextify-qa bash -c '~/.local/bin/contextify --version'
# Should show: 1.2.1
```

#### 3d. Test Scenarios

Run these in order. Enter the container: `docker exec -it -u testuser contextify-qa bash`

**Test 1: Fresh ingest with progress**
```bash
~/.local/bin/contextify ingest
# Expected: Shows progress (X/~500), processes both Claude and Codex
# Verify: Both providers discovered
```

**Test 2: Ctrl+C mid-ingest (SIGINT handling)**
```bash
# Clear DB first
rm -f ~/.local/share/contextify/contextify.db*
~/.local/bin/contextify ingest
# Hit Ctrl+C after ~5 seconds
# Expected: Exits cleanly, no error spam

# Immediately check DB is usable
sqlite3 ~/.local/share/contextify/contextify.db "SELECT COUNT(*) FROM transcripts;"
# Expected: Returns a number (not "database is locked")
```

**Test 3: Resume after Ctrl+C**
```bash
~/.local/bin/contextify ingest
# Expected: Picks up where it left off
# Progress should show reduced total (e.g., 200/350 not 1/500)
```

**Test 4: Complete run**
```bash
# Let it finish
# Expected: Shows total count when done
```

**Test 5: Re-run when already indexed**
```bash
~/.local/bin/contextify ingest
# Expected: Shows "N transcripts indexed (already up to date)" or similar
# Should complete in <2 seconds (just discovery + DB check)
```

**Test 6: install.sh end-to-end**
```bash
# Clear everything and test via install.sh
rm -f ~/.local/share/contextify/contextify.db*
rm -f ~/.local/bin/contextify
curl -fsSL https://contextify.sh/install.sh | sh
# Expected: Downloads binary, runs ingest, shows progress, completes cleanly
```

#### 3e. Verification Queries

```bash
# Check final DB state
sqlite3 ~/.local/share/contextify/contextify.db "
  SELECT ingest_state, COUNT(*) FROM transcripts GROUP BY ingest_state;
  SELECT provider, COUNT(*) FROM transcripts GROUP BY provider;
"
# Expected: Both claude.code and codex.cli providers present
# Expected: All 'complete', count matches discovered files
```

### Step 4: Deploy install.sh

install.sh is served from contextify.sh (static site). Deploy after testing:

```bash
./scripts/deploy-website.sh
```

This updates the install script that `curl -fsSL https://contextify.sh/install.sh | sh` fetches.

### Step 5: Build x86_64 Binary (CI ONLY)

**NEVER build x86_64 locally on ARM Mac.**

```bash
# Push code changes first (CI builds from branch)
git push origin main-wb1

# Trigger CI build
gh workflow run linux-release.yml --repo banagale/contextify --ref main-wb1 \
  -f version=1.2.1 \
  -f build_amd64=true \
  -f build_arm64=false

# Monitor
gh run list --workflow=linux-release.yml --repo banagale/contextify --limit 1
gh run watch --repo banagale/contextify
```

### Step 6: Upload Binaries to GitHub Release

```bash
# Generate checksums
cd dist
shasum -a 256 contextify-linux-arm64.tar.gz > contextify-linux-arm64.tar.gz.sha256

# Download x86_64 artifact from CI
gh run download <run-id> --repo banagale/contextify -n contextify-linux-x86_64 -D /tmp/x86_64_artifact
cd /tmp/x86_64_artifact
shasum -a 256 contextify-linux-x86_64.tar.gz > contextify-linux-x86_64.tar.gz.sha256

# Delete old assets and upload new ones (public repo)
gh release delete-asset v1.2.1 contextify-linux-arm64.tar.gz --repo PeterPym/contextify -y
gh release delete-asset v1.2.1 contextify-linux-arm64.tar.gz.sha256 --repo PeterPym/contextify -y
gh release delete-asset v1.2.1 contextify-linux-x86_64.tar.gz --repo PeterPym/contextify -y
gh release delete-asset v1.2.1 contextify-linux-x86_64.tar.gz.sha256 --repo PeterPym/contextify -y

gh release upload v1.2.1 \
  dist/contextify-linux-arm64.tar.gz \
  dist/contextify-linux-arm64.tar.gz.sha256 \
  /tmp/x86_64_artifact/contextify-linux-x86_64.tar.gz \
  /tmp/x86_64_artifact/contextify-linux-x86_64.tar.gz.sha256 \
  --repo PeterPym/contextify --clobber
```

### Step 7: Verify End-to-End

```bash
# Fresh container, install via public URL
docker rm -f contextify-qa 2>/dev/null
docker run -d --name contextify-qa --init --platform linux/arm64 ubuntu:22.04 sleep infinity
docker exec contextify-qa bash -c 'useradd -m -s /bin/bash testuser && apt-get update -qq && apt-get install -y curl ca-certificates -qq > /dev/null 2>&1'

# Copy transcripts (reuse tarballs from Step 3b)
docker cp /tmp/claude-transcripts.tar.gz contextify-qa:/tmp/
docker cp /tmp/codex-transcripts.tar.gz contextify-qa:/tmp/
docker exec -u testuser contextify-qa bash -c '
  cd ~
  tar -xzf /tmp/claude-transcripts.tar.gz
  tar -xzf /tmp/codex-transcripts.tar.gz
'

# Run the real install.sh from the web
docker exec -u testuser contextify-qa bash -c 'curl -fsSL https://contextify.sh/install.sh | sh'

# Verify version and DB state
docker exec -u testuser contextify-qa bash -c '
  ~/.local/bin/contextify --version
  sqlite3 ~/.local/share/contextify/contextify.db "SELECT provider, COUNT(*) FROM transcripts GROUP BY provider;"
'
# Should show: 1.2.1
# Should show: both claude.code and codex.cli entries
```

### Step 8: Verify Checksums Work

install.sh downloads `.sha256` files from the release and verifies the tarball checksum automatically. No manual update needed since we upload both the tarball and its `.sha256` file together in Step 6.

```bash
# Verify checksum verification works in install.sh
docker exec -u testuser contextify-qa bash -c '
  # Re-run install - should show "Verifying checksum... ✓"
  curl -fsSL https://contextify.sh/install.sh | sh
'
```

---

## Future Considerations (Not in This PR)

- **PID file for concurrent protection** - If user runs install.sh in two terminals, busy_timeout prevents crashes but doesn't give a clear error. A PID file at startup would detect "already running" cleanly. Low priority since this is an edge case.
- **Subagent transcript discovery** - Currently only top-level `.jsonl` files in project dirs are discovered. The `UUID/subagents/*.jsonl` files are skipped. This is intentional for now (they're internal to Claude Code) but may need revisiting.

---

## Checklist

- [ ] All 7 code changes implemented
- [ ] Debug prints removed
- [ ] Version set to 1.2.1
- [ ] arm64 built and tested locally
- [ ] install.sh deployed to contextify.sh
- [ ] x86_64 built via CI
- [ ] Both tarballs uploaded to v1.2.1 release (public repo)
- [ ] SHA256 files uploaded alongside tarballs (install.sh fetches them dynamically)
- [ ] End-to-end test passes with live install.sh
