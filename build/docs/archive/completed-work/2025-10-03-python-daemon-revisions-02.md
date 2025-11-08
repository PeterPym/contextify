**Declined recommendations (and why)**

* **#2 pack_json “infinite loop”** — Python `str` slicing is codepoint-based; the code searches on character count, not bytes, and uses `errors="replace"` during encoding. The loop terminates via the standard `lo/hi` convergence. No correctness bug. A hard iteration cap is optional, not required.

* **“Graceful degradation to system Python”** — Falling back to system Python breaks reproducibility and weakens the supply-chain boundary (we pin wheels in the bundled venv). If the venv is missing or corrupt, install should fail fast with a clear, actionable error, not silently change interpreters.

---

**Required fixes (apply now)**

### 1) Health monitor: cap backoff but auto-reset after quiet period (severity: medium)

Keep the existing 8× cap; add time-based reset so recovery isn’t sluggish after prolonged downtime.

```python
# scripts/iterm2_daemon.py
HEALTH_BASE_INTERVAL_S = 60

class Daemon:
    def __init__(self) -> None:
        # ...
        self.health_fail_streak = 0
        self.metrics["last_health_attempt_ms"] = 0

    async def health_monitor(self) -> None:
        while self.running:
            capped = min(self.health_fail_streak, 3)  # max 8x
            base = HEALTH_BASE_INTERVAL_S * (2 ** capped)
            sleep_for = base + random.uniform(-5, 5)
            await asyncio.sleep(max(10, sleep_for))
            if not self.running:
                break

            now_ms = int(time.time() * 1000)
            self.metrics["health_probes"] += 1

            # reset streak if idle > 10 minutes
            last = self.metrics.get("last_health_attempt_ms", 0)
            if self.health_fail_streak > 0 and (now_ms - last) > 600_000:
                slog("INFO", "health_streak_reset_timeout")
                self.health_fail_streak = 0

            self.metrics["last_health_attempt_ms"] = now_ms

            try:
                async with self.iterm_lock:
                    if not self.iterm_app or not self.conn_healthy:
                        slog("INFO", "health_probe_reconnecting")
                        ok = await self.connect_iterm()
                        if ok:
                            self.health_fail_streak = 0
                            slog("INFO", "health_probe_reconnect_ok")
                        else:
                            self.health_fail_streak += 1
                            self.metrics["health_failures"] += 1
                            slog("ERROR", "health_probe_reconnect_failed")
                        continue

                    try:
                        await asyncio.wait_for(self.iterm_app.async_get_app_version(), timeout=0.25)
                        self.conn_healthy = True
                        self.metrics["iterm2_down"] = False
                        self.health_fail_streak = 0
                        slog("DEBUG", "health_probe_ok")
                    except Exception as e:
                        self.metrics["health_failures"] += 1
                        self.conn_healthy = False
                        self.metrics["iterm2_down"] = True
                        self.metrics["reconnects"] += 1
                        self.health_fail_streak += 1
                        slog("WARN", "health_probe_failed", err=str(e))
                        await self.connect_iterm()
            except Exception as e:
                slog("ERROR", "health_monitor_crash", err=str(e))
```

---

### 2) Socket timeouts: split seconds/useconds correctly (severity: high)

SO_RCVTIMEO/SO_SNDTIMEO expect sec/usec; avoid overflowing `tv_usec`.

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
// inside performOnce()
let timeoutSec = Int(deadline / 1000)
let timeoutUsec = Int32((deadline % 1000) * 1000)
var timeout = timeval(tv_sec: timeoutSec, tv_usec: timeoutUsec)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
```

*(Use the existing deadline clamp you added: 100…2000ms)*

---

### 3) Discovery TOCTOU: atomically pair mtime+path (severity: high)

Read attributes and file contents in the same attempt window; then update `lastDiscoveryMtime`.

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
private func openSocket() throws -> (Int32, String) {
    guard FileManager.default.fileExists(atPath: discoveryURL.path) else {
        throw DaemonError.discoveryMissing
    }

    var attempts = 0
    var socketPath: String?
    var currentMtime: Date?

    while attempts < 3 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: discoveryURL.path)
            currentMtime = attrs[.modificationDate] as? Date

            let content = try String(contentsOf: discoveryURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                socketPath = content
                break
            }
        } catch {
            attempts += 1
            usleep(10_000)
            continue
        }
        attempts += 1
        usleep(10_000)
    }

    guard let path = socketPath else { throw DaemonError.discoveryMissing }

    // log restart after we have a valid path
    if let mt = currentMtime, let last = lastDiscoveryMtime, mt > last {
        log.info("Discovery file updated, daemon likely restarted")
    }
    lastDiscoveryMtime = currentMtime

    // Ownership check on discovery file for hardening
    if let attrs = try? FileManager.default.attributesOfItem(atPath: discoveryURL.path),
       let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value,
       owner != getuid() {
        throw DaemonError.discoveryMissing
    }

    // ... existing lstat/socket connect ...
}
```

---

### 4) Retry with discovery refresh (severity: high)

Force a second attempt with refreshed discovery if the first fails.

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
func getContent(maxLines: Int = 100, deadlineMs: Int = 500) async -> Result<String, DaemonError> {
    if disabled() { return .failure(.disabled) }
    let deadline = max(100, min(deadlineMs, 2000))

    func performOnce(forceRefresh: Bool = false) async throws -> String {
        if forceRefresh { _ = try? refreshDiscoveryMtime() }
        let (fd, _) = try openSocket()
        defer { close(fd) }
        // ... existing request/response path, but use `deadline` ...
        // return content
    }

    do {
        return .success(try await performOnce())
    } catch {
        log.warning("First attempt failed, retrying with discovery refresh: \(error.localizedDescription)")
        do { return .success(try await performOnce(forceRefresh: true)) }
        catch let err as DaemonError { return .failure(err) }
        catch { return .failure(.invalidResponse) }
    }
}
```

---

### 5) Validate sockaddr_un construction and CLOEXEC set result (severity: medium)

Zero the struct, enforce NUL-terminated path, and log if `F_SETFD` fails.

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
var addr = sockaddr_un()
withUnsafeMutableBytes(of: &addr) { $0.initialize(repeating: 0) }
addr.sun_family = sa_family_t(AF_UNIX)
let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
guard path.utf8.count <= maxLen - 1 else { throw DaemonError.connectFailed }
withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
    path.withCString { _ = strncpy(ptr, $0, maxLen - 1) } // keep NUL
}

// After creating fd:
var flags = fcntl(fd, F_GETFD)
if flags >= 0 {
    let r = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
    if r == -1 {
        log.warning("Failed to set FD_CLOEXEC on socket")
    }
}
```

---

### 6) Per-connection concurrency cap + fast “server_busy” (severity: medium)

Bound concurrent connections; reject overflow early.

```python
# scripts/iterm2_daemon.py
class Daemon:
    def __init__(self) -> None:
        # ...
        self.connection_semaphore = asyncio.Semaphore(8)
        self.metrics["concurrent_requests"] = 0
        self.metrics["rejected_requests"] = 0

    async def handle_conn(self, reader, writer):
        # admission control
        if self.connection_semaphore.locked() and self.connection_semaphore._value == 0:
            self.metrics["rejected_requests"] += 1
            resp = {"success": False, "error": "server_busy",
                    "details": "max concurrent requests exceeded",
                    "protocol_version": PROTOCOL_VERSION}
            try:
                writer.write(pack_json(resp)); await writer.drain()
            finally:
                writer.close(); await writer.wait_closed()
            return

        async with self.connection_semaphore:
            self.metrics["concurrent_requests"] += 1
            try:
                await self._handle_conn_impl(reader, writer)  # move existing logic here
            finally:
                self.metrics["concurrent_requests"] -= 1
```

*(Refactor your current `handle_conn` body into `_handle_conn_impl`.)*

---

### 7) Use monotonic time for latency metrics (severity: low)

Avoid wall-clock skew.

```python
# scripts/iterm2_daemon.py
from time import perf_counter as _now

async def fetch_content(self, max_lines: int) -> Dict[str, Any]:
    t0 = _now()
    # ... RPCs ...
    latency = int((_now() - t0) * 1000)
    return {..., "latency_ms": latency, ...}
```

---

### 8) Selection branch: include line_count for schema uniformity (severity: low)

```python
selection = await asyncio.wait_for(session.async_get_selection_text(), timeout=0.25)
if selection and selection.strip():
    lines = selection.splitlines()
    latency = int((_now() - start) * 1000)
    return {"success": True, "source": "selection", "content": _cap(selection),
            "line_count": len(lines), "total_lines": len(lines),
            "latency_ms": latency, "protocol_version": PROTOCOL_VERSION}
```

---

### 9) Request protocol_version validation (severity: medium)

Fail fast on mismatched wire versions and make the client send it.

```python
# scripts/iterm2_daemon.py
async def handle_conn(self, reader, writer):
    try:
        req = await read_framed_json(reader, timeout=1.0)
    except Exception as e:
        payload = {"success": False, "error": "protocol", "details": str(e),
                   "protocol_version": PROTOCOL_VERSION}
        writer.write(pack_json(payload)); await writer.drain(); writer.close(); return

    req_version = req.get("protocol_version", 1)
    if req_version != PROTOCOL_VERSION:
        resp = {"success": False, "error": "protocol_mismatch",
                "details": f"client {req_version}, server {PROTOCOL_VERSION}",
                "protocol_version": PROTOCOL_VERSION}
        writer.write(pack_json(resp)); await writer.drain(); writer.close(); return
    # ... rest ...
```

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
let request: [String: Any] = [
  "id": requestID, "command": "get_content",
  "max_lines": safeLines, "protocol_version": 1
]
```

---

### 10) Cleanup guards (severity: medium)

Only remove socket/discovery if actually created.

```python
# scripts/iterm2_daemon.py
async def run(self) -> None:
    socket_created = False
    discovery_written = False
    try:
        self.server = await asyncio.start_unix_server(self.handle_conn, path=self.socket_path, backlog=32)
        socket_created = True
        os.chmod(self.socket_path, 0o600)
        # ... security checks ...
        self._atomic_write_discovery(self.socket_path)
        discovery_written = True
        slog("INFO", "daemon_started", socket=self.socket_path, pid=os.getpid())
        self.running = True
        await self.connect_iterm()
        asyncio.create_task(self.health_monitor())
        async with self.server:
            while self.running:
                await asyncio.sleep(0.1)
    finally:
        if socket_created:
            try:
                if os.path.exists(self.socket_path):
                    os.unlink(self.socket_path)
            except Exception as e:
                slog("WARN", "socket_cleanup_failed", err=str(e))
        if discovery_written:
            try:
                if self.discovery_path.exists():
                    self.discovery_path.unlink()
            except Exception as e:
                slog("WARN", "discovery_cleanup_failed", err=str(e))
        slog("INFO", "daemon_stopped")
```

---

### 11) Remove `WorkingDirectory` and add `Umask` in plist (severity: medium)

Least privilege; enforce secure defaults at launchd layer.

```swift
// Contextify/Contextify/LaunchAgentManager.swift
let dict: [String: Any] = [
    "Label": label,
    "ProgramArguments": [pythonPath, "-I", "-s", "-E", scriptPath],
    "RunAtLoad": true,
    "KeepAlive": ["Crashed": true, "SuccessfulExit": false],
    "StandardOutPath": stdout,
    "StandardErrorPath": stderr,
    "ThrottleInterval": 10,
    "LimitLoadToSessionType": "Aqua",
    "Umask": 0o077,
    "ProcessType": "Background",
    // omit WorkingDirectory
]
```

---

### 12) Log rotation (severity: medium)

Prevent unbounded growth.

```swift
// Contextify/Contextify/LaunchAgentManager.swift
private func rotateLogsIfNeeded() {
    let fm = FileManager.default
    let maxBytes: UInt64 = 10 * 1024 * 1024
    for name in ["daemon.stdout.log", "daemon.stderr.log"] {
        let logURL = logsDir.appendingPathComponent(name)
        if let s = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64, s > maxBytes {
            let rotated = logsDir.appendingPathComponent("\(name).1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: logURL, to: rotated)
        }
    }
}

func installIfNeeded() async throws {
    try createDirs()
    rotateLogsIfNeeded()
    try copyDaemonAndVenvIfNeeded()
    try writePlist()
    try bootstrapAndEnable()
}
```

---

### 13) Discovery file read hardening (already partially present; extend) (severity: medium)

Treat non-socket paths and foreign ownership as invalid.

```swift
// Contextify/Contextify/ITerm2DaemonClient.swift
var sb = stat()
guard lstat(path, &sb) == 0,
      (sb.st_mode & S_IFMT) == S_IFSOCK,
      sb.st_uid == getuid() else {
    throw DaemonError.socketInvalid
}
```

---

### 14) Document `CONTEXTIFY_DEV=1` (severity: low)

Add explicit developer instructions.

````markdown
# build/notes/current.md

#### Local Development

To run the daemon without installing the bundled venv (uses dev fallback paths):

```bash
export CONTEXTIFY_DEV=1
python3 scripts/iterm2_daemon.py
````

The daemon will search `scripts/Python/lib/python/site-packages` and `Resources/Python/lib/python/site-packages`.

````

---

### 15) Read-frame: reject zero-length frames upfront (severity: low)
Reduce exception spam and edge-case ambiguity.

```python
# scripts/iterm2_daemon.py
async def read_framed_json(reader: asyncio.StreamReader, timeout: float) -> Dict[str, Any]:
    hdr = await read_exact(reader, 4, timeout)
    ln = struct.unpack(">I", hdr)[0]
    if ln == 0 or ln > MAX_REQ:
        raise ValueError(f"bad_length:{ln}")
    body = await read_exact(reader, ln, timeout)
    return json.loads(body.decode("utf-8", errors="replace"))
````

---

**Post-review test focus**

* Concurrent request flood → verify `server_busy` and semaphore cap hold under 200 parallel connects.
* iTerm2 quit/reopen loops → ensure streak reset restores normal probe interval.
* Protocol mismatch → client sends `protocol_version=1`, server rejects `!=1`.
* Large selections/scrollback → verify truncation path returns `truncated=true` and frame ≤ 256 KiB.
* Cold boot without discovery → first call retries with refreshed discovery; no user-visible error.
* Log size growth across hours → rotation prevents >10MB per file.
