## Executive Summary

Replace the per-request Python invocation with a long-running, LaunchAgent-supervised Python daemon that maintains a persistent iTerm2 API connection and communicates with the macOS app via a hardened Unix domain socket (length-prefixed JSON + request IDs). The daemon runs from a bundled, pinned Python venv and includes a 60-second health monitor (with jitter) to pre-emptively reconnect to iTerm2. Target P95 latency <30 ms (vs. 200–500 ms), with immediate fallback to the legacy path if the daemon is unavailable.

## Current Architecture Problems

### Bottleneck Analysis

```
User presses Cmd+Shift+K+K
  ↓
Swift spawns Process()                          [50-100ms]
  ↓
Python3 interpreter starts                      [30-50ms]
  ↓
Import iterm2, asyncio, json                    [20-40ms]
  ↓
asyncio.run() creates event loop                [10-20ms]
  ↓
iterm2.Connection.async_create()                [50-150ms]
  - Unix socket connect to iTerm2
  - Handshake protocol
  - Session negotiation
  ↓
async_get_screen_contents()                     [20-80ms]
  - Fetch entire scrollback
  ↓
JSON encode and print                           [5-10ms]
  ↓
Process exits, socket closes                    [5-10ms]
───────────────────────────────────────────────
TOTAL: 190–460ms per hotkey press
```

### Root Causes

1. Process spawn overhead on every request.
2. Module import tax (iterm2/asyncio).
3. New iTerm2 API socket handshake each time.
4. Event loop creation/destruction per call.
5. Over-fetching (entire scrollback) and no bounded output.

## Proposed Architecture: Long-Running Daemon

### High-Level Flow

```
Login or App Launch:
  LaunchAgent starts daemon (venv/python -I -s -E)
  Daemon connects to iTerm2 (persisted)
  Daemon listens on hardened Unix socket:
    ~/Library/Application Support/Contextify/run/daemon-<id>.sock
  Health monitor probes ~60s with jitter; pre-emptive reconnect on failure

Hotkey Press:
  Swift reads discovery file → socket path
  Send framed JSON request (id, command, max_lines)   [<1ms]
  Daemon returns bounded content                       [10–20ms]
──────────────────────────────────────────────────────
TOTAL: 11–25ms per hotkey press (P95 <30ms)
```

### Component Design

#### 1) Python Daemon (`scripts/iterm2_daemon.py`)

* LaunchAgent-supervised; no ad-hoc Process supervision.
* Persistent iTerm2 connection; serialized access with `asyncio.Lock`.
* Secure IPC: Unix socket in `~/Library/Application Support/Contextify/run/` (0700 dir, 0600 socket), discovery file written atomically.
* Length-prefixed JSON protocol with request IDs; 256 KB max request size.
* Bounded content capture: selection (if present) → last N screen lines; UTF-8 safe tail cap (200 k chars).
* Strict timeouts around all awaits; 60s health monitor with ±5s jitter to pre-emptively reconnect.
* Structured JSON logs to stderr for field diagnostics.

#### 2) Swift Client (`Contextify/ITerm2DaemonClient.swift`)

* Ensures agent is installed and running; kickstarts via `launchctl`.
* Connects to discovery-specified socket; validates it’s a real socket (`lstat` + `S_ISSOCK`).
* SO_NOSIGPIPE, length-prefixed send/receive with full partial-read handling.
* 500 ms end-to-end deadline; returns `.success(text)` or classified errors.
* Kill switch via `UserDefaults("DisableDaemonMode")`.

#### 3) LaunchAgent Management (`Contextify/LaunchAgentManager.swift`)

* Copies bundled daemon script and Python venv to `~/Library/Application Support/Contextify`.
* Writes minimal, deterministic LaunchAgent plist and bootstraps it to GUI domain.
* ProgramArguments: `.../venv/bin/python3 -I -s -E .../scripts/iterm2_daemon.py`.

#### 4) Integration (`TerminalContentReader.swift`)

* If frontmost app is iTerm2, call daemon; on failure, fall back to legacy per-request reader.

## Implementation Plan

### Files Added/Modified

* **ADD** `scripts/iterm2_daemon.py` (Python daemon)
* **ADD** `Contextify/ITerm2DaemonClient.swift` (Swift client)
* **ADD** `Contextify/LaunchAgentManager.swift` (LaunchAgent installer/manager)
* **MOD** `TerminalContentReader.swift` (integrate daemon + fallback)
* **ADD** `scripts/logging/healthcheck.sh` (diagnostics)

### Phase 1 — Daemon core, IPC, security

* Implement `scripts/iterm2_daemon.py` exactly as below.
* Enforce run dir 0700, socket 0600, ownership checks.
* Length-prefixed JSON framing + request IDs; 256 KB request cap.
* Health monitor task (≈60s ±5s jitter) + pre-emptive reconnect.

**File: `scripts/iterm2_daemon.py`**

```python
#!/usr/bin/env python3
"""
Contextify iTerm2 Daemon (v1.1)
- LaunchAgent-supervised, long-running daemon.
- Secure Unix socket IPC (length-prefixed JSON with request IDs).
- Selection-first capture; fallback to bounded screen read.
- Hardened filesystem layout, atomic discovery, strict timeouts.
- Lightweight background health monitor (~60s with jitter) to pre-emptively reconnect.
"""

import asyncio
import json
import os
import signal
import stat as statmod
import struct
import sys
import time
import uuid
import random
from pathlib import Path
from typing import Any, Dict, Optional

# ---- Bundled Python site-packages isolation ---------------------------------
APP_SUPPORT = Path.home() / "Library" / "Application Support" / "Contextify"
VENV_SITE = APP_SUPPORT / "venv" / "lib" / "python3" / "site-packages"
if VENV_SITE.exists():
    sys.path.insert(0, str(VENV_SITE))
else:
    script_dir = Path(__file__).resolve().parent
    bundle_site = script_dir / "Python" / "lib" / "python" / "site-packages"
    if bundle_site.exists():
        sys.path.insert(0, str(bundle_site))

# ---- Dependencies ------------------------------------------------------------
try:
    import iterm2  # pinned via packaging
except Exception as e:
    print(json.dumps({
        "ts": int(time.time()*1000),
        "level": "FATAL",
        "event": "import_failure",
        "err": str(e),
    }), file=sys.stderr)
    raise

# ---- Simple structured logger ------------------------------------------------
def slog(level: str, event: str, **kw):
    rec = {"ts": int(time.time()*1000), "level": level, "event": event}
    rec.update(kw)
    print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)

# ---- Protocol helpers --------------------------------------------------------
MAX_REQ = 256 * 1024  # 256KB hard cap
MAX_CHARS = 200_000   # UTF-8 chars cap in responses

async def read_exact(reader: asyncio.StreamReader, n: int, timeout: float) -> bytes:
    return await asyncio.wait_for(reader.readexactly(n), timeout)

def pack_json(payload: Dict[str, Any]) -> bytes:
    b = json.dumps(payload, ensure_ascii=False).encode("utf-8", errors="replace")
    return struct.pack(">I", len(b)) + b

async def read_framed_json(reader: asyncio.StreamReader, timeout: float) -> Dict[str, Any]:
    hdr = await read_exact(reader, 4, timeout)
    ln = struct.unpack(">I", hdr)[0]
    if ln > MAX_REQ:
        raise ValueError(f"payload_too_large:{ln}")
    body = await read_exact(reader, ln, timeout)
    return json.loads(body.decode("utf-8", errors="replace"))

# ---- Daemon ------------------------------------------------------------------
class Daemon:
    def __init__(self) -> None:
        # Paths
        self.run_dir = APP_SUPPORT / "run"
        self.run_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.run_dir, 0o700)
        st = os.stat(self.run_dir)
        if st.st_uid != os.getuid() or (st.st_mode & 0o077):
            raise RuntimeError("run/ must be owned by user and 0700")
        self.socket_path = self._new_socket_path()
        self.discovery_path = self.run_dir / "daemon.path"

        # Server state
        self.server: Optional[asyncio.AbstractServer] = None
        self.running = False

        # iTerm2 state
        self.iterm_conn: Optional[iterm2.Connection] = None
        self.iterm_app: Optional[iterm2.App] = None
        self.conn_healthy = False
        self.iterm_lock = asyncio.Lock()

        # Health monitor cadence (~60s with jitter)
        self.health_interval_s = 60

        # Metrics (log-only; no RPC)
        self.metrics = {
            "requests_total": 0,
            "requests_ok": 0,
            "requests_err": 0,
            "reconnects": 0,
            "latency_ms": [],     # last 100 samples
            "start_ms": int(time.time()*1000),
            "iterm2_down": False,
            "health_probes": 0,
            "health_failures": 0,
        }

    # ---- Setup helpers -------------------------------------------------------
    def _new_socket_path(self) -> str:
        return str(self.run_dir / f"daemon-{uuid.uuid4().hex[:8]}.sock")

    def _atomic_write_discovery(self, path: str) -> None:
        tmp = self.discovery_path.with_suffix(".tmp")
        tmp.write_text(path, encoding="utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.discovery_path)

    # ---- iTerm2 connection mgmt ---------------------------------------------
    async def connect_iterm(self) -> bool:
        # Few bounded attempts with exponential backoff; mark down on exhaustion.
        for attempt in range(3):
            try:
                self.iterm_conn = await iterm2.Connection.async_create()
                self.iterm_app = await iterm2.async_get_app(self.iterm_conn)
                self.conn_healthy = True
                self.metrics["iterm2_down"] = False
                slog("INFO", "iterm2_connected", attempt=attempt+1)
                return True
            except Exception as e:
                delay = 2 ** attempt  # 1, 2, 4
                slog("WARN", "iterm2_connect_failed", attempt=attempt+1, delay_s=delay, err=str(e))
                await asyncio.sleep(delay)
        self.conn_healthy = False
        self.metrics["iterm2_down"] = True
        return False

    async def get_active_session(self) -> iterm2.Session:
        window = self.iterm_app.current_terminal_window
        if not window:
            raise RuntimeError("no_window")
        tab = window.current_tab
        if not tab:
            raise RuntimeError("no_tab")
        sess = tab.current_session
        if not sess:
            raise RuntimeError("no_session")
        return sess

    # ---- Health monitor ------------------------------------------------------
    async def health_monitor(self) -> None:
        """
        Every ≈60s (±5s jitter), perform a cheap health probe:
        - if healthy, ask for app version with short timeout.
        - if down/unhealthy, attempt a pre-emptive reconnect.
        Uses the same iTerm lock to avoid concurrent RPCs.
        """
        while self.running:
            sleep_for = self.health_interval_s + random.uniform(-5, 5)
            await asyncio.sleep(max(10, sleep_for))
            if not self.running:
                break

            self.metrics["health_probes"] += 1
            try:
                async with self.iterm_lock:
                    if not self.iterm_app or not self.conn_healthy:
                        ok = await self.connect_iterm()
                        if not ok:
                            self.metrics["health_failures"] += 1
                        continue

                    try:
                        _ = await asyncio.wait_for(
                            self.iterm_app.async_get_app_version(), timeout=0.25
                        )
                        self.conn_healthy = True
                        self.metrics["iterm2_down"] = False
                    except Exception:
                        self.metrics["health_failures"] += 1
                        self.conn_healthy = False
                        self.metrics["iterm2_down"] = True
                        self.metrics["reconnects"] += 1
                        await self.connect_iterm()
            except Exception as e:
                slog("WARN", "health_monitor_error", err=str(e))

    # ---- Content capture -----------------------------------------------------
    async def fetch_content(self, max_lines: int) -> Dict[str, Any]:
        start = time.time()
        async with self.iterm_lock:
            if not self.iterm_app or not self.conn_healthy:
                ok = await self.connect_iterm()
                if not ok:
                    return {"success": False, "error": "iterm2_down", "details": "iTerm2 Python API unavailable"}

            try:
                sess = await asyncio.wait_for(self.get_active_session(), timeout=0.2)
            except Exception as e:
                return {"success": False, "error": "no_active_session", "details": str(e)}

            # Priority 1: explicit selection text
            try:
                sel = await asyncio.wait_for(sess.async_get_selection_text(), timeout=0.25)
                if sel and sel.strip():
                    ms = int((time.time()-start)*1000)
                    return {"success": True, "source": "selection", "content": _cap(sel), "latency_ms": ms}
            except Exception:
                pass

            # Priority 2: bounded screen content (last N lines)
            try:
                screen = await asyncio.wait_for(sess.async_get_screen_contents(), timeout=0.3)
                total = screen.number_of_lines
                n = max(1, min(max_lines, 10_000))
                start_line = max(0, total - n)
                lines = []
                for i in range(start_line, total):
                    lines.append(screen.line(i).string)
                content = _cap("\n".join(lines))
                ms = int((time.time()-start)*1000)
                return {
                    "success": True,
                    "source": "screen",
                    "line_count": len(lines),
                    "total_lines": total,
                    "content": content,
                    "latency_ms": ms
                }
            except asyncio.TimeoutError:
                return {"success": False, "error": "timeout", "details": "screen_read_timeout"}
            except Exception as e:
                self.conn_healthy = False
                self.metrics["reconnects"] += 1
                return {"success": False, "error": "rpc_error", "details": str(e)}

    # ---- IPC handlers --------------------------------------------------------
    async def handle_conn(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            req = await read_framed_json(reader, timeout=1.0)
        except Exception as e:
            payload = {"success": False, "error": "protocol", "details": str(e)}
            writer.write(pack_json(payload))
            await writer.drain()
            writer.close()
            return

        self.metrics["requests_total"] += 1
        req_id = req.get("id")
        cmd = req.get("command")

        if cmd == "ping":
            resp = {
                "id": req_id,
                "success": True,
                "status": "alive",
                "connection_healthy": self.conn_healthy,
                "iterm2_down": self.metrics["iterm2_down"],
                "uptime_ms": int(time.time()*1000) - self.metrics["start_ms"],
            }

        elif cmd == "get_content":
            try:
                max_lines = int(req.get("max_lines", 100))
            except Exception:
                max_lines = 100
            resp = await self.fetch_content(max_lines=max_lines)
            resp["id"] = req_id
            if resp.get("success"):
                self.metrics["requests_ok"] += 1
                if "latency_ms" in resp:
                    self.metrics["latency_ms"].append(int(resp["latency_ms"]))
                    if len(self.metrics["latency_ms"]) > 100:
                        self.metrics["latency_ms"].pop(0)
            else:
                self.metrics["requests_err"] += 1

        elif cmd == "shutdown":
            self.running = False
            resp = {"id": req_id, "success": True, "status": "shutting_down"}

        else:
            resp = {"id": req_id, "success": False, "error": "unknown_command"}

        try:
            writer.write(pack_json(resp))
            await writer.drain()
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    # ---- Main loop -----------------------------------------------------------
    async def run(self) -> None:
        # Remove stale socket with validation
        p = Path(self.socket_path)
        if p.exists():
            st = os.lstat(self.socket_path)
            if not statmod.S_ISSOCK(st.st_mode):
                raise RuntimeError("stale_path_not_socket")
            if st.st_uid != os.getuid():
                raise RuntimeError("socket_not_owned")
            p.unlink()

        # Start server
        self.server = await asyncio.start_unix_server(self.handle_conn, path=self.socket_path)
        os.chmod(self.socket_path, 0o600)
        st = os.lstat(self.socket_path)
        if not statmod.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
            raise RuntimeError("socket_security_failure")

        # Publish discovery atomically
        self._atomic_write_discovery(self.socket_path)

        slog("INFO", "daemon_started", socket=self.socket_path, pid=os.getpid())
        self.running = True

        # Initial connect (bounded)
        await self.connect_iterm()

        # Start background health monitor
        asyncio.create_task(self.health_monitor())

        # Serve
        async with self.server:
            while self.running:
                await asyncio.sleep(0.1)

        slog("INFO", "daemon_stopped")

# ---- helpers ----------------------------------------------------------------
def _cap(s: str) -> str:
    if len(s) <= MAX_CHARS:
        return s
    return s[-MAX_CHARS:]

async def _main():
    d = Daemon()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, setattr, d, "running", False)
    try:
        await d.run()
    except Exception as e:
        slog("FATAL", "daemon_crash", err=str(e))
        raise

if __name__ == "__main__":
    asyncio.run(_main())
```

### Phase 2 — LaunchAgent management and venv bundling

**File: `Contextify/LaunchAgentManager.swift`**

```swift
import Foundation
import OSLog
import Darwin

actor LaunchAgentManager {
    static let shared = LaunchAgentManager()
    private let log = Logger(subsystem: "dev.contextify", category: "LaunchAgent")

    private let label = "dev.contextify.iterm2-daemon"

    private var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contextify", isDirectory: true)
    }

    private var scriptsDir: URL { appSupport.appendingPathComponent("scripts", isDirectory: true) }
    private var venvDir: URL { appSupport.appendingPathComponent("venv", isDirectory: true) }
    private var logsDir: URL { appSupport.appendingPathComponent("logs", isDirectory: true) }
    private var runDir: URL { appSupport.appendingPathComponent("run", isDirectory: true) }
    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func installIfNeeded() async throws {
        try createDirs()
        try copyDaemonAndVenvIfNeeded()
        try writePlist()
        try bootstrapAndEnable()
    }

    func kickstart() async throws {
        try run("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(label)"])
    }

    // MARK: - helpers

    private func createDirs() throws {
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: venvDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true,
                                               attributes: [FileAttributeKey.posixPermissions: 0o700])
    }

    private func copyDaemonAndVenvIfNeeded() throws {
        guard let daemonSrc = Bundle.main.url(forResource: "iterm2_daemon", withExtension: "py") else {
            throw NSError(domain: "Contextify", code: 1, userInfo: [NSLocalizedDescriptionKey: "daemon script missing in bundle"])
        }
        let daemonDst = scriptsDir.appendingPathComponent("iterm2_daemon.py")
        if FileManager.default.fileExists(atPath: daemonDst.path) {
            try? FileManager.default.removeItem(at: daemonDst)
        }
        try FileManager.default.copyItem(at: daemonSrc, to: daemonDst)

        if let venvSrc = Bundle.main.url(forResource: "PythonVenv", withExtension: nil) {
            if FileManager.default.fileExists(atPath: venvDir.path) {
                try? FileManager.default.removeItem(at: venvDir)
            }
            try FileManager.default.copyItem(at: venvSrc, to: venvDir)
        }
    }

    private func writePlist() throws {
        let py = venvDir.appendingPathComponent("bin/python3").path
        let script = scriptsDir.appendingPathComponent("iterm2_daemon.py").path
        let stdout = logsDir.appendingPathComponent("daemon.stdout.log").path
        let stderr = logsDir.appendingPathComponent("daemon.stderr.log").path

        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [py, "-I", "-s", "-E", script],
            "RunAtLoad": true,
            "KeepAlive": ["Crashed": true, "SuccessfulExit": false],
            "StandardOutPath": stdout,
            "StandardErrorPath": stderr,
            "ThrottleInterval": 10
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private func bootstrapAndEnable() throws {
        try run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        try run("/bin/launchctl", ["enable", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    private func run(_ bin: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "Contextify", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "launchctl \(args.joined(separator: " ")) failed: \(e)\(o)"])
        }
        return (p.terminationStatus, o)
    }
}
```

### Phase 3 — Swift client & app integration

**File: `Contextify/ITerm2DaemonClient.swift`**

```swift
import Foundation
import OSLog
import Darwin

actor ITerm2DaemonClient {
    static let shared = ITerm2DaemonClient()

    enum DaemonError: Error, CustomStringConvertible {
        case disabled
        case discoveryMissing
        case socketInvalid
        case connectFailed
        case requestTimeout
        case invalidResponse
        case daemonError(String, details: String?)
        var description: String {
            switch self {
            case .disabled: return "daemon disabled"
            case .discoveryMissing: return "discovery path missing"
            case .socketInvalid: return "discovery path not a socket"
            case .connectFailed: return "connect failed"
            case .requestTimeout: return "request timeout"
            case .invalidResponse: return "invalid response"
            case .daemonError(let e, let d): return "daemon error: \(e)\(d.map { " (\($0))" } ?? "")"
            }
        }
    }

    private struct Response: Decodable {
        let id: String?
        let success: Bool
        let content: String?
        let error: String?
        let details: String?
        let source: String?
        let latency_ms: Int?
        let status: String?
        let connection_healthy: Bool?
        let iterm2_down: Bool?
        let uptime_ms: Int?
    }

    private let log = Logger(subsystem: "dev.contextify", category: "iTerm2Daemon")
    private let discoveryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Contextify/run/daemon.path")

    private func disabled() -> Bool {
        UserDefaults.standard.bool(forKey: "DisableDaemonMode")
    }

    func ensureRunning() async {
        if disabled() { return }
        do {
            try await LaunchAgentManager.shared.installIfNeeded()
            try await LaunchAgentManager.shared.kickstart()
        } catch {
            log.error("launchagent ensureRunning failed: \(error.localizedDescription)")
        }
    }

    func getContent(maxLines: Int = 100, deadlineMs: Int = 500) async -> Result<String, DaemonError> {
        if disabled() { return .failure(.disabled) }
        do {
            let (fd, _) = try openSocket()
            defer { close(fd) }

            let reqID = UUID().uuidString
            let req: [String: Any] = ["id": reqID, "command": "get_content", "max_lines": maxLines]
            let payload = try JSONSerialization.data(withJSONObject: req)
            var len = UInt32(payload.count).bigEndian
            var header = Data(bytes: &len, count: 4); header.append(payload)

            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))

            let sent = header.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
            }
            guard sent == header.count else { throw DaemonError.connectFailed }

            let respData = try await readFramed(fd: fd, deadlineMs: deadlineMs)
            let resp = try JSONDecoder().decode(Response.self, from: respData)
            guard resp.success, let content = resp.content else {
                throw DaemonError.daemonError(resp.error ?? "unknown", details: resp.details)
            }
            if let ms = resp.latency_ms { log.debug("daemon \(ms, privacy: .public) ms source=\(resp.source ?? "n/a")") }
            return .success(content)
        } catch let e as DaemonError {
            return .failure(e)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    // MARK: - Internals

    private func openSocket() throws -> (Int32, String) {
        guard FileManager.default.fileExists(atPath: discoveryURL.path) else {
            throw DaemonError.discoveryMissing
        }
        guard let path = try? String(contentsOf: discoveryURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw DaemonError.discoveryMissing
        }

        var sb = stat()
        guard lstat(path, &sb) == 0, (sb.st_mode & S_IFMT) == S_IFSOCK else {
            throw DaemonError.socketInvalid
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.connectFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { strcpy(ptr, $0) }
        }

        let res = withUnsafePointer(to: &addr) { aptr in
            aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard res == 0 else { close(fd); throw DaemonError.connectFailed }
        return (fd, path)
    }

    private func readFramed(fd: Int32, deadlineMs: Int) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var lenBuf = Data(count: 4); var readBytes = 0
                while readBytes < 4 {
                    let r = lenBuf.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: readBytes), 4 - readBytes, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    readBytes += r
                }
                let n = lenBuf.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
                var body = Data(count: Int(n)); var got = 0
                while got < Int(n) {
                    let r = body.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: got), Int(n) - got, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    got += r
                }
                return body
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadlineMs) * 1_000_000)
                throw DaemonError.requestTimeout
            }
            let data = try await group.next()!
            group.cancelAll()
            return data
        }
    }
}
```

**Integration (modify): `TerminalContentReader.swift`**

```swift
private func readActiveTerminalContent() async -> String? {
    guard let frontmost = NSWorkspace.shared.frontmostApplication,
          frontmost.bundleIdentifier == "com.googlecode.iterm2" else {
        return nil
    }
    await ITerm2DaemonClient.shared.ensureRunning()
    switch await ITerm2DaemonClient.shared.getContent(maxLines: 100) {
    case .success(let text):
        return text
    case .failure:
        // Legacy fallback path already present in the project:
        return await ITerm2PythonReader().readTerminalContent()
    }
}
```

### Phase 4 — Packaging and build changes (CI)

1. **Create release venv with pinned deps (CI step):**

   ```bash
   rm -rf dist/PythonVenv
   python3 -m venv dist/PythonVenv
   dist/PythonVenv/bin/python -m pip install --upgrade pip
   dist/PythonVenv/bin/python -m pip install 'iterm2==2.0.0'
   ```
2. **Bundle resources:**

   * Add `dist/PythonVenv` to the app bundle as `Resources/PythonVenv`.
   * Add `scripts/iterm2_daemon.py` to the app bundle Resources as `iterm2_daemon.py`.
3. **First run:** `LaunchAgentManager.installIfNeeded()` copies Resources → `~/Library/Application Support/Contextify/…`, writes plist, bootstraps agent.

### Phase 5 — Validation, diagnostics, and rollout

**File: `scripts/logging/healthcheck.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DISC="$HOME/Library/Application Support/Contextify/run/daemon.path"
if [[ ! -f "$DISC" ]]; then echo "no discovery"; exit 2; fi
SOCK="$(cat "$DISC")"
if [[ ! -S "$SOCK" ]]; then echo "no socket"; exit 2; fi
python3 - <<'PY' "$SOCK"
import os,sys,socket,struct,json
p=sys.argv[1]; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(1.0); s.connect(p)
req={"id":"hc","command":"ping"}; b=json.dumps(req).encode("utf-8")
s.sendall(struct.pack(">I", len(b))+b); hdr=s.recv(4); ln=struct.unpack(">I",hdr)[0]; resp=json.loads(s.recv(ln).decode("utf-8"))
print("OK" if resp.get('success') else "BAD"); sys.exit(0 if resp.get('success') else 3)
PY
```

`chmod +x scripts/logging/healthcheck.sh`

## Testing & Validation

### Functional

* iTerm2 frontmost → `get_content` returns text (selection if present, else last N lines).
* iTerm2 not running → error `iterm2_down`; legacy fallback path invoked.
* No iTerm window/tab/session → error `no_active_session`; legacy fallback invoked.

### Performance

* Press hotkey 100× with mixed selection/no-selection; measure P50 and P95 via app logs:

  * Expected **P50 ≤20 ms**, **P95 ≤30 ms**.
* Kill iTerm2, wait 5 s, open iTerm2; next hotkey should succeed without noticeable delay (health monitor pre-emptively reconnects at ≤60 s; first request also attempts reconnect under lock).

### Reliability

* Sleep/Wake cycle and iTerm2 relaunch: daemon recovers (health monitor + on-demand reconnection).
* Delete socket file while running: server loop re-creates at start only; discovery path matches current socket.
* Permissions tampering (`run/` to 0755): daemon refuses to start; logs error.
* Stale discovery pointing to non-socket: client refuses (`socketInvalid`).

### Security

* Verify run dir: `stat -f "%p %Su" ~/Library/Application\ Support/Contextify/run` → `drwx------` and user-owned.
* Verify socket perms: `ls -l .../daemon-xxxx.sock` → `srw-------`.
* Discovery file is 0600 and replaces atomically; not world-readable.

### Observability

* Tail log: `tail -f ~/Library/Application\ Support/Contextify/logs/daemon.stderr.log` and verify structured JSON events:

  * `daemon_started`, `iterm2_connected`, `health_monitor_error`, `daemon_crash`, request results with latency.

## Edge Cases & Handling

1. **iTerm2 not installed or API disabled** → `iterm2_down`; fallback path used; log rate-limited connection failures.
2. **Large scrollback** → bounded by `max_lines` and `MAX_CHARS=200k`; safe tail kept.
3. **Concurrent hotkeys** → serialized by `asyncio.Lock`; client still 500 ms deadline.
4. **Socket hijack attempt** → discovery/`lstat` check + `S_ISSOCK` and ownership enforcement; 0700 dir prevents other users from planting sockets.
5. **Daemon crash** → LaunchAgent `KeepAlive` restarts on crash; app falls back until healthy.

## Rollout Plan

1. Ship enabled by default with a hidden **kill switch** (`DisableDaemonMode` = true).
2. Monitor logs and healthcheck results from QA; confirm P95 <30 ms.
3. If issues: flip kill switch via configuration and rely on legacy path while investigating.
4. After 1–2 weeks without regressions, finalize and remove the legacy invocation from hot paths (keep as contingency).

## Fallback Strategy

* On any client error (`discoveryMissing`, `socketInvalid`, `connectFailed`, `requestTimeout`, `daemonError`), immediately call the legacy `ITerm2PythonReader().readTerminalContent()` path.
* The daemon can also be disabled globally via `UserDefaults("DisableDaemonMode")`.

## Success Metrics

* **Latency:** P95 <30 ms, P99 <50 ms across 1k requests per user/day.
* **Success rate:** >99% daemon responses (excluding intentional fallbacks).
* **Uptime:** >99.9% daemon availability (LaunchAgent).
* **Fallback rate:** <1% of iTerm2 capture attempts.
* **Error budget:** <0.1% RPC/protocol errors per day (per user).

## De-scoped (v1) to Reduce Risk

* Any Shell Integration–dependent capture (prompt marks) — add later behind capability check.
* Developer UI for metrics — logs suffice in v1.
* Dual SMAppService path — LaunchAgent-only for determinism.