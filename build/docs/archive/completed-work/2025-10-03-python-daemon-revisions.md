**Declined recommendations (and why)**

* **#9 “MAX_REQ on response size” as written:** returning an error when the JSON frame exceeds 256 KiB penalizes UX even though the daemon already bounds terminal text with `MAX_CHARS`. Correct behavior is to **shrink the response to fit** the frame limit (byte-precise) and mark it truncated, not fail the request.

---

## Adopted fixes (fully integrated)

### `scripts/iterm2_daemon.py` — server timeouts, safe packing, stronger health logs, run-dir validation, cleanup, protocol version

```python
#!/usr/bin/env python3
"""
Contextify iTerm2 Daemon (v1.2)
- LaunchAgent-supervised, long-running daemon.
- Secure Unix socket IPC (length-prefixed JSON with request IDs).
- Selection-first capture; fallback to bounded screen read.
- Hardened filesystem layout, atomic discovery, strict timeouts.
- Lightweight health monitor (~60s adaptive with jitter) to pre-emptively reconnect.
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

# ---- constants ---------------------------------------------------------------
PROTOCOL_VERSION = 1
MAX_REQ = 256 * 1024  # 256KB hard cap (wire frame)
MAX_CHARS = 200_000   # cap for content field (chars), further trimmed to fit frame
HEALTH_BASE_INTERVAL_S = 60

# ---- paths / venv isolation --------------------------------------------------
APP_SUPPORT = Path.home() / "Library" / "Application Support" / "Contextify"
VENV_SITE = APP_SUPPORT / "venv" / "lib" / "python3" / "site-packages"
if VENV_SITE.exists():
    sys.path.insert(0, str(VENV_SITE))
else:
    # DEV-only fallbacks guarded by env flag
    if os.environ.get("CONTEXTIFY_DEV") == "1":
        script_dir = Path(__file__).resolve().parent
        bundle_site = script_dir / "Python" / "lib" / "python" / "site-packages"
        if bundle_site.exists():
            sys.path.insert(0, str(bundle_site))
        else:
            project_root = script_dir.parent
            dev_site = project_root / "Resources" / "Python" / "lib" / "python" / "site-packages"
            if dev_site.exists():
                sys.path.insert(0, str(dev_site))

# ---- deps --------------------------------------------------------------------
try:
    import iterm2
except Exception as e:
    print(json.dumps({"ts": int(time.time()*1000), "level": "FATAL", "event": "import_failure", "err": str(e)}),
          file=sys.stderr)
    raise

# ---- logging -----------------------------------------------------------------
def slog(level: str, event: str, **kw):
    rec = {"ts": int(time.time()*1000), "level": level, "event": event}
    rec.update(kw)
    print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)

# ---- framing helpers ---------------------------------------------------------
async def read_exact(reader: asyncio.StreamReader, n: int, timeout: float) -> bytes:
    return await asyncio.wait_for(reader.readexactly(n), timeout)

async def read_framed_json(reader: asyncio.StreamReader, timeout: float) -> Dict[str, Any]:
    hdr = await read_exact(reader, 4, timeout)
    ln = struct.unpack(">I", hdr)[0]
    if ln > MAX_REQ:
        raise ValueError(f"payload_too_large:{ln}")
    body = await read_exact(reader, ln, timeout)
    return json.loads(body.decode("utf-8", errors="replace"))

def pack_json(payload: Dict[str, Any]) -> bytes:
    """
    Serialize payload to a MAX_REQ-bounded frame. If too large, attempt to shrink
    the 'content' field by bytes so the final frame fits; mark as truncated.
    """
    def encode(p) -> bytes:
        return json.dumps(p, ensure_ascii=False).encode("utf-8", errors="replace")

    b = encode(payload)
    if len(b) <= MAX_REQ:
        return struct.pack(">I", len(b)) + b

    # Attempt to shrink content only
    p = dict(payload)
    content = p.get("content")
    if isinstance(content, str) and content:
        # Byte-precise truncation from the head to preserve most recent lines
        # Reserve 1KB for JSON overhead wiggle room
        budget = MAX_REQ - 1024
        # Binary search on byte length
        lo, hi = 0, len(content)
        best = ""
        while lo <= hi:
            mid = (lo + hi) // 2
            candidate = content[-mid:] if mid > 0 else ""
            p["content"] = candidate
            p["truncated"] = True
            bb = encode(p)
            if len(bb) <= budget:
                best = candidate
                lo = mid + 1
            else:
                hi = mid - 1
        p["content"] = best
        p["truncated"] = True
        b2 = encode(p)
        if len(b2) <= MAX_REQ:
            return struct.pack(">I", len(b2)) + b2

    # If still too big, return a structured error (retain id if present)
    truncated = {
        "id": payload.get("id"),
        "success": False,
        "error": "response_too_large",
        "details": f"response > {MAX_REQ} bytes"
    }
    bt = encode(truncated)
    return struct.pack(">I", len(bt)) + bt

# ---- daemon ------------------------------------------------------------------
class Daemon:
    def __init__(self) -> None:
        os.umask(0o077)  # secure defaults
        self.run_dir = APP_SUPPORT / "run"
        self.run_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.run_dir, 0o700)
        st = os.stat(self.run_dir)
        if st.st_uid != os.getuid() or (st.st_mode & 0o077):
            raise RuntimeError("run/ must be owned by user and 0700")

        self.socket_path = str(self.run_dir / f"daemon-{uuid.uuid4().hex[:8]}.sock")
        self.discovery_path = self.run_dir / "daemon.path"

        self.server: Optional[asyncio.AbstractServer] = None
        self.running = False

        self.iterm_conn: Optional[iterm2.Connection] = None
        self.iterm_app: Optional[iterm2.App] = None
        self.conn_healthy = False
        self.iterm_lock = asyncio.Lock()

        self.health_fail_streak = 0

        self.metrics = {
            "requests_total": 0,
            "requests_ok": 0,
            "requests_err": 0,
            "reconnects": 0,
            "latency_ms": [],
            "start_ms": int(time.time()*1000),
            "iterm2_down": False,
            "health_probes": 0,
            "health_failures": 0,
        }

    def _atomic_write_discovery(self, path: str) -> None:
        tmp = self.discovery_path.with_suffix(".tmp")
        tmp.write_text(path, encoding="utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.discovery_path)

    async def connect_iterm(self) -> bool:
        for attempt in range(3):
            try:
                self.iterm_conn = await iterm2.Connection.async_create()
                self.iterm_app = await iterm2.async_get_app(self.iterm_conn)
                self.conn_healthy = True
                self.metrics["iterm2_down"] = False
                slog("INFO", "iterm2_connected", attempt=attempt+1)
                return True
            except Exception as e:
                delay = 2 ** attempt
                slog("WARN", "iterm2_connect_failed", attempt=attempt+1, delay_s=delay, err=str(e))
                await asyncio.sleep(delay)
        self.conn_healthy = False
        self.metrics["iterm2_down"] = True
        return False

    async def get_active_session(self) -> iterm2.Session:
        window = self.iterm_app.current_terminal_window
        if not window: raise RuntimeError("no_window")
        tab = window.current_tab
        if not tab: raise RuntimeError("no_tab")
        sess = tab.current_session
        if not sess: raise RuntimeError("no_session")
        return sess

    async def health_monitor(self) -> None:
        while self.running:
            # Adaptive interval: 60s * 2^(min(streak,3)) ± jitter (max ~8min)
            base = HEALTH_BASE_INTERVAL_S * (2 ** min(self.health_fail_streak, 3))
            sleep_for = base + random.uniform(-5, 5)
            await asyncio.sleep(max(10, sleep_for))
            if not self.running:
                break

            self.metrics["health_probes"] += 1
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
                        _ = await asyncio.wait_for(self.iterm_app.async_get_app_version(), timeout=0.25)
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
                return {"success": False, "error": "no_active_session", "details": str(e), "protocol_version": PROTOCOL_VERSION}

            # 1) selection
            try:
                sel = await asyncio.wait_for(sess.async_get_selection_text(), timeout=0.25)
                if sel and sel.strip():
                    ms = int((time.time()-start)*1000)
                    return {"success": True, "source": "selection", "content": _cap(sel),
                            "latency_ms": ms, "protocol_version": PROTOCOL_VERSION}
            except Exception:
                pass

            # 2) screen (bounded)
            try:
                screen = await asyncio.wait_for(sess.async_get_screen_contents(), timeout=0.3)
                total = screen.number_of_lines
                n = max(1, min(int(max_lines), 10_000))
                start_line = max(0, total - n)
                lines = [screen.line(i).string for i in range(start_line, total)]
                content = _cap("\n".join(lines))
                ms = int((time.time()-start)*1000)
                return {"success": True, "source": "screen", "line_count": len(lines),
                        "total_lines": total, "content": content, "latency_ms": ms,
                        "protocol_version": PROTOCOL_VERSION}
            except asyncio.TimeoutError:
                return {"success": False, "error": "timeout", "details": "screen_read_timeout", "protocol_version": PROTOCOL_VERSION}
            except Exception as e:
                self.conn_healthy = False
                self.metrics["reconnects"] += 1
                return {"success": False, "error": "rpc_error", "details": str(e), "protocol_version": PROTOCOL_VERSION}

    async def handle_conn(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            req = await read_framed_json(reader, timeout=1.0)
        except Exception as e:
            writer.write(pack_json({"success": False, "error": "protocol", "details": str(e), "protocol_version": PROTOCOL_VERSION}))
            await writer.drain()
            writer.close()
            return

        self.metrics["requests_total"] += 1
        req_id = req.get("id")
        cmd = req.get("command")

        if cmd == "ping":
            resp = {
                "id": req_id, "success": True, "status": "alive",
                "connection_healthy": self.conn_healthy,
                "iterm2_down": self.metrics["iterm2_down"],
                "uptime_ms": int(time.time()*1000) - self.metrics["start_ms"],
                "protocol_version": PROTOCOL_VERSION
            }

        elif cmd == "get_content":
            try:
                max_lines = int(req.get("max_lines", 100))
            except Exception:
                max_lines = 100

            try:
                # server-side soft deadline shorter than client's 500ms
                resp = await asyncio.wait_for(self.fetch_content(max_lines=max_lines), timeout=0.45)
            except asyncio.TimeoutError:
                resp = {"success": False, "error": "server_timeout", "details": "content fetch exceeded 450ms",
                        "protocol_version": PROTOCOL_VERSION}

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
            resp = {"id": req_id, "success": True, "status": "shutting_down", "protocol_version": PROTOCOL_VERSION}

        else:
            resp = {"id": req_id, "success": False, "error": "unknown_command", "protocol_version": PROTOCOL_VERSION}

        try:
            writer.write(pack_json(resp))
            await writer.drain()
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def run(self) -> None:
        # Validate run_dir just before creating socket
        try:
            st = os.stat(self.run_dir)
            if st.st_uid != os.getuid() or (st.st_mode & 0o077):
                raise RuntimeError(f"run/ permissions changed: uid={st.st_uid} mode={oct(st.st_mode)}")
        except FileNotFoundError:
            raise RuntimeError("run/ directory deleted after startup")

        # Remove stale socket with validation
        p = Path(self.socket_path)
        if p.exists():
            st = os.lstat(self.socket_path)
            if not statmod.S_ISSOCK(st.st_mode):
                raise RuntimeError("stale_path_not_socket")
            if st.st_uid != os.getuid():
                raise RuntimeError("socket_not_owned")
            p.unlink()

        # Start server with backlog
        self.server = await asyncio.start_unix_server(self.handle_conn, path=self.socket_path, backlog=32)
        os.chmod(self.socket_path, 0o600)
        st = os.lstat(self.socket_path)
        if not statmod.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
            raise RuntimeError("socket_security_failure")

        self._atomic_write_discovery(self.socket_path)
        slog("INFO", "daemon_started", socket=self.socket_path, pid=os.getpid())
        self.running = True

        await self.connect_iterm()
        asyncio.create_task(self.health_monitor())

        try:
            async with self.server:
                while self.running:
                    await asyncio.sleep(0.1)
        finally:
            # cleanup
            try:
                if os.path.exists(self.socket_path):
                    os.unlink(self.socket_path)
            except Exception as e:
                slog("WARN", "socket_cleanup_failed", err=str(e))
            try:
                if self.discovery_path.exists():
                    self.discovery_path.unlink()
            except Exception as e:
                slog("WARN", "discovery_cleanup_failed", err=str(e))
            slog("INFO", "daemon_stopped")

# ---- helpers -----------------------------------------------------------------
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

---

### `Contextify/Contextify/LaunchAgentManager.swift` — venv validation + safer plist bootstrap

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

    // MARK: helpers

    private func createDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: venvDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: runDir, withIntermediateDirectories: true,
                               attributes: [FileAttributeKey.posixPermissions: 0o700])
    }

    private func copyDaemonAndVenvIfNeeded() throws {
        let fm = FileManager.default

        guard let daemonSrc = Bundle.main.url(forResource: "iterm2_daemon", withExtension: "py") else {
            throw NSError(domain: "Contextify", code: 1, userInfo: [NSLocalizedDescriptionKey: "daemon script missing in bundle"])
        }
        let daemonDst = scriptsDir.appendingPathComponent("iterm2_daemon.py")
        if fm.fileExists(atPath: daemonDst.path) { try? fm.removeItem(at: daemonDst) }
        try fm.copyItem(at: daemonSrc, to: daemonDst)

        if let venvSrc = Bundle.main.url(forResource: "PythonVenv", withExtension: nil) {
            if fm.fileExists(atPath: venvDir.path) { try? fm.removeItem(at: venvDir) }
            try fm.copyItem(at: venvSrc, to: venvDir)

            let pythonBin = venvDir.appendingPathComponent("bin/python3")
            guard fm.isExecutableFile(atPath: pythonBin.path) else {
                throw NSError(domain: "Contextify", code: 2, userInfo: [NSLocalizedDescriptionKey: "venv python3 not executable at \(pythonBin.path)"])
            }
        } else {
            throw NSError(domain: "Contextify", code: 2, userInfo: [NSLocalizedDescriptionKey: "bundled PythonVenv missing"])
        }
    }

    private func writePlist() throws {
        let venvPython = venvDir.appendingPathComponent("bin/python3")
        guard FileManager.default.isExecutableFile(atPath: venvPython.path) else {
            throw NSError(domain: "Contextify", code: 2, userInfo: [NSLocalizedDescriptionKey: "bundled Python venv missing or not executable"])
        }
        let pythonPath = venvPython.path
        let scriptPath = scriptsDir.appendingPathComponent("iterm2_daemon.py").path
        let stdout = logsDir.appendingPathComponent("daemon.stdout.log").path
        let stderr = logsDir.appendingPathComponent("daemon.stderr.log").path

        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [pythonPath, "-I", "-s", "-E", scriptPath],
            "RunAtLoad": true,
            "KeepAlive": ["Crashed": true, "SuccessfulExit": false],
            "StandardOutPath": stdout,
            "StandardErrorPath": stderr,
            "ThrottleInterval": 10,
            "LimitLoadToSessionType": "Aqua",
            "WorkingDirectory": appSupport.path
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private func bootstrapAndEnable() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"

        // sanity check uid
        let whoami = try? run("/usr/bin/id", ["-u"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whoami == "\(uid)" else {
            throw NSError(domain: "Contextify", code: 3, userInfo: [NSLocalizedDescriptionKey: "UID mismatch: expected \(uid) got \(whoami ?? "nil")"])
        }

        if (try? run("/bin/launchctl", ["print", "\(domain)/\(label)"]).0) == 0 {
            log.info("LaunchAgent already bootstrapped")
            return
        }

        try run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        try run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
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

---

### `Contextify/Contextify/ITerm2DaemonClient.swift` — discovery race handling + restart awareness

```swift
import Foundation
import OSLog
import Darwin

actor ITerm2DaemonClient {
    static let shared = ITerm2DaemonClient()

    enum DaemonError: Error, CustomStringConvertible {
        case disabled, discoveryMissing, socketInvalid, connectFailed, requestTimeout, invalidResponse, daemonError(String, details: String?)
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
        let protocol_version: Int?
        let truncated: Bool?
    }

    private let log = Logger(subsystem: "dev.contextify", category: "iTerm2Daemon")
    private let discoveryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Contextify/run/daemon.path")
    private var lastDiscoveryMtime: Date?

    private func disabled() -> Bool { UserDefaults.standard.bool(forKey: "DisableDaemonMode") }

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

        func performOnce() throws -> String {
            let (fd, _) = try openSocket()
            defer { close(fd) }
            let reqID = UUID().uuidString
            let safeLines = max(1, min(maxLines, 10_000))
            let req: [String: Any] = ["id": reqID, "command": "get_content", "max_lines": safeLines]
            let payload = try JSONSerialization.data(withJSONObject: req)
            var len = UInt32(payload.count).bigEndian
            var buf = Data(bytes: &len, count: 4); buf.append(payload)

            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
            // Kernel-level timeouts: 500ms rcv/snd
            var tv = timeval(tv_sec: 0, tv_usec: 500_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            // CLOEXEC
            var flags = fcntl(fd, F_GETFD)
            if flags != -1 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }

            let sent = buf.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, $0.count, 0) }
            guard sent == buf.count else { throw DaemonError.connectFailed }

            let respData = try await readFramed(fd: fd, deadlineMs: deadlineMs)
            let resp = try JSONDecoder().decode(Response.self, from: respData)
            guard (resp.protocol_version ?? 1) == 1 else { throw DaemonError.invalidResponse }
            guard resp.success, let content = resp.content else {
                throw DaemonError.daemonError(resp.error ?? "unknown", details: resp.details)
            }
            if let ms = resp.latency_ms { log.debug("daemon \(ms, privacy: .public) ms source=\(resp.source ?? "n/a") truncated=\(resp.truncated == true)") }
            return content
        }

        do {
            return .success(try await performOnce())
        } catch {
            // On failure, re-read discovery (daemon may have rotated socket)
            _ = try? refreshDiscoveryMtime()
            do { return .success(try await performOnce()) }
            catch let e as DaemonError { return .failure(e) }
            catch { return .failure(.invalidResponse) }
        }
    }

    private func refreshDiscoveryMtime() -> Date? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: discoveryURL.path),
           let mtime = attrs[.modificationDate] as? Date {
            if let last = lastDiscoveryMtime, mtime > last {
                log.info("Discovery file updated, daemon likely restarted")
            }
            lastDiscoveryMtime = mtime
            return mtime
        }
        return nil
    }

    private func openSocket() throws -> (Int32, String) {
        // Discovery read with small retry to handle atomic replace race
        guard FileManager.default.fileExists(atPath: discoveryURL.path) else { throw DaemonError.discoveryMissing }
        var attempts = 0
        var path: String?
        while attempts < 3 {
            if let content = try? String(contentsOf: discoveryURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                path = content
                break
            }
            attempts += 1
            usleep(10_000) // 10ms
        }
        guard let socketPath = path else { throw DaemonError.discoveryMissing }
        _ = refreshDiscoveryMtime()

        var sb = stat()
        guard lstat(socketPath, &sb) == 0, (sb.st_mode & S_IFMT) == S_IFSOCK, sb.st_uid == getuid() else {
            throw DaemonError.socketInvalid
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.connectFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < maxLen else { close(fd); throw DaemonError.connectFailed }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in socketPath.withCString { strcpy(ptr, $0) } }

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { close(fd); throw DaemonError.connectFailed }
        return (fd, socketPath)
    }

    private func readFramed(fd: Int32, deadlineMs: Int) async throws -> Data {
        let maxResp = 256 * 1024
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var lenBuf = Data(count: 4); var readBytes = 0
                while readBytes < 4 {
                    let r = lenBuf.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress!.advanced(by: readBytes), 4 - readBytes, 0) }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    readBytes += r
                }
                let n = lenBuf.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
                guard n <= maxResp else { throw DaemonError.invalidResponse }

                var body = Data(count: Int(n)); var got = 0
                while got < Int(n) {
                    let r = body.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress!.advanced(by: got), Int(n) - got, 0) }
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

---

### `scripts/logging/healthcheck.sh` — response validation + documented exit codes

```bash
#!/usr/bin/env bash
# iTerm2 Daemon Health Check
# Exit codes:
#   0 - Healthy (daemon responding to pings)
#   2 - Discovery file or socket missing (daemon not running)
#   3 - Daemon running but unhealthy (connection failed or bad response)
set -euo pipefail

DISC="$HOME/Library/Application Support/Contextify/run/daemon.path"

if [[ ! -f "$DISC" ]]; then
    echo "❌ Discovery file not found: $DISC"
    exit 2
fi

SOCK="$(cat "$DISC" 2>/dev/null || true)"
if [[ -z "${SOCK:-}" || ! -S "$SOCK" ]]; then
    echo "❌ Socket not found: ${SOCK:-<empty>}"
    exit 2
fi

python3 - <<'PY' "$SOCK"
import sys, socket, struct, json

sock_path = sys.argv[1]
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(sock_path)
    req = {"id": "healthcheck", "command": "ping"}
    payload = json.dumps(req).encode("utf-8")
    s.sendall(struct.pack(">I", len(payload)) + payload)

    # read header
    hdr = b""
    while len(hdr) < 4:
        chunk = s.recv(4 - len(hdr))
        if not chunk:
            print("❌ Invalid response")
            sys.exit(3)
        hdr += chunk
    ln = struct.unpack(">I", hdr)[0]

    body = b""
    while len(body) < ln:
        chunk = s.recv(min(4096, ln - len(body)))
        if not chunk:
            print("❌ Incomplete response body")
            sys.exit(3)
        body += chunk

    try:
        resp = json.loads(body.decode("utf-8"))
    except Exception:
        print("❌ Invalid response format")
        sys.exit(3)

    if not isinstance(resp, dict) or "success" not in resp or "status" not in resp:
        print("❌ Malformed response (missing required fields)")
        sys.exit(3)

    if resp.get("success"):
        print("✅ Daemon is healthy")
        print(f"   Status: {resp.get('status')}")
        print(f"   Connection healthy: {resp.get('connection_healthy', 'unknown')}")
        print(f"   iTerm2 down: {resp.get('iterm2_down', 'unknown')}")
        uptime = resp.get('uptime_ms', 0)
        try:
            print(f"   Uptime: {uptime/1000:.1f}s")
        except Exception:
            print(f"   Uptime: {uptime}ms")
        sys.exit(0)
    else:
        print(f"❌ Error: {resp.get('error')}")
        sys.exit(3)

except Exception as e:
    print(f"❌ Healthcheck failed: {e}")
    sys.exit(3)
finally:
    try:
        s.close()
    except Exception:
        pass
PY
```

---

### `scripts/test_daemon.py` — robust partial reads

```python
#!/usr/bin/env python3
import json, socket, struct, sys, time
from pathlib import Path

def pack_json(payload):
    b = json.dumps(payload).encode("utf-8")
    return struct.pack(">I", len(b)) + b

def read_framed_json(sock):
    hdr = b""
    while len(hdr) < 4:
        chunk = sock.recv(4 - len(hdr))
        if not chunk:
            raise RuntimeError("incomplete header")
        hdr += chunk
    ln = struct.unpack(">I", hdr)[0]
    body = b""
    while len(body) < ln:
        chunk = sock.recv(min(4096, ln - len(body)))
        if not chunk:
            raise RuntimeError("incomplete body")
        body += chunk
    return json.loads(body.decode("utf-8"))

def send_command(sock_path, command, **params):
    req = {"id": f"test-{int(time.time()*1000)}", "command": command}
    req.update(params)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(sock_path)
        s.sendall(pack_json(req))
        return read_framed_json(s)
    finally:
        s.close()

def main():
    discovery_path = Path.home() / "Library/Application Support/Contextify/run/daemon.path"
    if not discovery_path.exists():
        print("❌ Discovery file not found:", discovery_path)
        sys.exit(1)
    sock_path = discovery_path.read_text().strip()
    print(f"📡 Daemon socket: {sock_path}")

    print("\n1️⃣  Ping...")
    resp = send_command(sock_path, "ping")
    print(resp)

    print("\n2️⃣  get_content...")
    t0 = time.time()
    resp = send_command(sock_path, "get_content", max_lines=100)
    t1 = time.time()
    print(f"Elapsed: {int((t1-t0)*1000)}ms; Daemon latency: {resp.get('latency_ms')}; Source: {resp.get('source')}")
    if resp.get("success"):
        content = resp.get("content","")
        print("Tail:")
        for line in content.splitlines()[-3:]:
            print("  ", line[:120])
    else:
        print("Error:", resp)

if __name__ == "__main__":
    main()
```

---

### `build/notes/current.md` — Python venv packaging docs

````markdown
### Build Requirements

#### Python venv packaging (one-time per dependency change)
```bash
# Create isolated venv for bundling
rm -rf dist/PythonVenv
python3 -m venv dist/PythonVenv

# Install pinned dependencies
dist/PythonVenv/bin/python -m pip install --upgrade pip
dist/PythonVenv/bin/python -m pip install 'iterm2==2.7'  # PIN THIS

# Verify installation
dist/PythonVenv/bin/python - <<'PY'
import iterm2
print("iterm2", iterm2.__version__)
PY
````

#### Xcode integration

1. Add `dist/PythonVenv` to the project as a **folder reference**.
2. Copy Files build phase → **Resources** → set destination **Resources/PythonVenv**.
3. Ensure LaunchAgent `ProgramArguments` includes `-I -s -E`.

#### CI/CD

* Run the venv creation before `xcodebuild`.
* Cache `dist/PythonVenv` keyed by your `requirements.lock` hash.

```

---

## Additional test coverage (gaps to close)

1. **iTerm2 restarts:** Manually quit iTerm2; verify `healthcheck.sh` → non-zero, then re-open iTerm2; daemon reconnects without user request failing (server ping “alive” within two intervals).
2. **Concurrent requests:** Fire 10 parallel `get_content` calls; ensure only one fetch occurs at a time (others succeed or return `busy` if you later adopt fast-fail).
3. **Socket tampering:** `chmod 0644` on socket; client must refuse with `.socketInvalid`. Restore perms; verify recovery.
4. **Latency sampling:** Collect 100 calls and compute P95 < 50 ms using the test client’s elapsed times; compare daemon-reported `latency_ms` for sanity.

---

## Rationale mapping to recommendations

- **#1 Server-side timeout:** **Implemented** (`asyncio.wait_for(..., timeout=0.45)` in `handle_conn`).
- **#2 Venv validation:** **Implemented** (require bundled venv, executability check).
- **#3 Discovery race:** **Implemented** (3-attempt read with 10 ms backoff).
- **#4 Run-dir invalidation:** **Implemented** (pre-socket validation and explicit error).
- **#5 Health monitor logs:** **Implemented** (`health_probe_*` events).
- **#6 Healthcheck structure validation:** **Implemented**.
- **#7 Venv build docs:** **Implemented**.
- **#8 Test client partial reads:** **Implemented**.
- **#9 Response MAX_REQ handling:** **Implemented differently** (truncate-to-fit with `truncated=true`; no failure).
- **#10 UID bootstrap hardening:** **Implemented** (domain verification).
- **#11 Healthcheck exit codes doc:** **Implemented**.

The client additionally refreshes discovery timestamps on failures to reduce user-visible retries after daemon restarts.
```