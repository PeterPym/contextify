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
import random
import signal
import stat as statmod
import struct
import sys
import time
import uuid
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
except Exception as e:  # pragma: no cover - startup failure
    print(
        json.dumps({
            "ts": int(time.time() * 1000),
            "level": "FATAL",
            "event": "import_failure",
            "err": str(e),
        }),
        file=sys.stderr,
    )
    raise

# ---- logging -----------------------------------------------------------------
def slog(level: str, event: str, **kw):
    rec = {"ts": int(time.time() * 1000), "level": level, "event": event}
    rec.update(kw)
    print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)


# ---- framing helpers ---------------------------------------------------------
async def read_exact(reader: asyncio.StreamReader, n: int, timeout: float) -> bytes:
    return await asyncio.wait_for(reader.readexactly(n), timeout)


async def read_framed_json(reader: asyncio.StreamReader, timeout: float) -> Dict[str, Any]:
    hdr = await read_exact(reader, 4, timeout)
    ln = struct.unpack(">I", hdr)[0]
    if ln == 0 or ln > MAX_REQ:
        raise ValueError(f"bad_length:{ln}")
    body = await read_exact(reader, ln, timeout)
    return json.loads(body.decode("utf-8", errors="replace"))


def pack_json(payload: Dict[str, Any]) -> bytes:
    """Serialize payload to a MAX_REQ-bounded frame, truncating content if needed."""

    def encode(p: Dict[str, Any]) -> bytes:
        return json.dumps(p, ensure_ascii=False).encode("utf-8", errors="replace")

    blob = encode(payload)
    if len(blob) <= MAX_REQ:
        return struct.pack(">I", len(blob)) + blob

    candidate_payload = dict(payload)
    content = candidate_payload.get("content")
    if isinstance(content, str) and content:
        budget = MAX_REQ - 1024  # leave headroom for metadata adjustments
        lo, hi = 0, len(content)
        best = ""
        while lo <= hi:
            mid = (lo + hi) // 2
            snippet = content[-mid:] if mid > 0 else ""
            candidate_payload["content"] = snippet
            candidate_payload["truncated"] = True
            attempt = encode(candidate_payload)
            if len(attempt) <= budget:
                best = snippet
                lo = mid + 1
            else:
                hi = mid - 1
        candidate_payload["content"] = best
        candidate_payload["truncated"] = True
        blob = encode(candidate_payload)
        if len(blob) <= MAX_REQ:
            return struct.pack(">I", len(blob)) + blob

    truncated = {
        "id": payload.get("id"),
        "success": False,
        "error": "response_too_large",
        "details": f"response > {MAX_REQ} bytes",
        "protocol_version": payload.get("protocol_version", PROTOCOL_VERSION),
    }
    blob = encode(truncated)
    return struct.pack(">I", len(blob)) + blob


# ---- daemon ------------------------------------------------------------------
class Daemon:
    def __init__(self) -> None:
        os.umask(0o077)
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
            "start_ms": int(time.time() * 1000),
            "iterm2_down": False,
            "health_probes": 0,
            "health_failures": 0,
            "last_health_attempt_ms": 0,
        }

    # ---- setup helpers -------------------------------------------------------
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
                slog("INFO", "iterm2_connected", attempt=attempt + 1)
                return True
            except Exception as e:  # pragma: no cover - depends on iTerm state
                delay = 2 ** attempt
                slog("WARN", "iterm2_connect_failed", attempt=attempt + 1, delay_s=delay, err=str(e))
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
        session = tab.current_session
        if not session:
            raise RuntimeError("no_session")
        return session

    # ---- health monitor ------------------------------------------------------
    async def health_monitor(self) -> None:
        while self.running:
            capped = min(self.health_fail_streak, 3)
            base = HEALTH_BASE_INTERVAL_S * (2 ** capped)
            sleep_for = base + random.uniform(-5, 5)
            await asyncio.sleep(max(10, sleep_for))
            if not self.running:
                break

            now_ms = int(time.time() * 1000)
            self.metrics["health_probes"] += 1
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

    # ---- content capture -----------------------------------------------------
    async def fetch_content(self, max_lines: int) -> Dict[str, Any]:
        start = time.time()
        async with self.iterm_lock:
            if not self.iterm_app or not self.conn_healthy:
                ok = await self.connect_iterm()
                if not ok:
                    return {
                        "success": False,
                        "error": "iterm2_down",
                        "details": "iTerm2 Python API unavailable",
                        "protocol_version": PROTOCOL_VERSION,
                    }

            try:
                session = await asyncio.wait_for(self.get_active_session(), timeout=0.2)
            except Exception as e:
                return {
                    "success": False,
                    "error": "no_active_session",
                    "details": str(e),
                    "protocol_version": PROTOCOL_VERSION,
                }

            try:
                selection = await asyncio.wait_for(session.async_get_selection_text(), timeout=0.25)
                if selection and selection.strip():
                    latency = int((time.time() - start) * 1000)
                    return {
                        "success": True,
                        "source": "selection",
                        "content": _cap(selection),
                        "latency_ms": latency,
                        "protocol_version": PROTOCOL_VERSION,
                    }
            except Exception:
                pass

            try:
                screen = await asyncio.wait_for(session.async_get_screen_contents(), timeout=0.3)
                total = screen.number_of_lines
                safe_max = max(1, min(int(max_lines), 10_000))
                start_line = max(0, total - safe_max)
                lines = [screen.line(i).string for i in range(start_line, total)]
                content = _cap("\n".join(lines))
                latency = int((time.time() - start) * 1000)
                return {
                    "success": True,
                    "source": "screen",
                    "line_count": len(lines),
                    "total_lines": total,
                    "content": content,
                    "latency_ms": latency,
                    "protocol_version": PROTOCOL_VERSION,
                }
            except asyncio.TimeoutError:
                return {
                    "success": False,
                    "error": "timeout",
                    "details": "screen_read_timeout",
                    "protocol_version": PROTOCOL_VERSION,
                }
            except Exception as e:
                self.conn_healthy = False
                self.metrics["reconnects"] += 1
                return {
                    "success": False,
                    "error": "rpc_error",
                    "details": str(e),
                    "protocol_version": PROTOCOL_VERSION,
                }

    # ---- IPC handlers --------------------------------------------------------
    async def handle_conn(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            req = await read_framed_json(reader, timeout=1.0)
        except Exception as e:
            payload = {
                "success": False,
                "error": "protocol",
                "details": str(e),
                "protocol_version": PROTOCOL_VERSION,
            }
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
                "uptime_ms": int(time.time() * 1000) - self.metrics["start_ms"],
                "protocol_version": PROTOCOL_VERSION,
            }

        elif cmd == "get_content":
            try:
                max_lines = int(req.get("max_lines", 100))
            except Exception:
                max_lines = 100

            try:
                resp = await asyncio.wait_for(self.fetch_content(max_lines=max_lines), timeout=0.45)
            except asyncio.TimeoutError:
                resp = {
                    "success": False,
                    "error": "server_timeout",
                    "details": "content fetch exceeded 450ms",
                    "protocol_version": PROTOCOL_VERSION,
                }

            resp["id"] = req_id
            if resp.get("success"):
                self.metrics["requests_ok"] += 1
                latency = resp.get("latency_ms")
                if isinstance(latency, int):
                    self.metrics["latency_ms"].append(latency)
                    if len(self.metrics["latency_ms"]) > 100:
                        self.metrics["latency_ms"].pop(0)
            else:
                self.metrics["requests_err"] += 1

        elif cmd == "shutdown":
            self.running = False
            resp = {
                "id": req_id,
                "success": True,
                "status": "shutting_down",
                "protocol_version": PROTOCOL_VERSION,
            }

        else:
            resp = {
                "id": req_id,
                "success": False,
                "error": "unknown_command",
                "protocol_version": PROTOCOL_VERSION,
            }

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
        try:
            st = os.stat(self.run_dir)
            if st.st_uid != os.getuid() or (st.st_mode & 0o077):
                raise RuntimeError(f"run/ permissions changed: uid={st.st_uid} mode={oct(st.st_mode)}")
        except FileNotFoundError:
            raise RuntimeError("run/ directory deleted after startup")

        socket_path = Path(self.socket_path)
        if socket_path.exists():
            st = os.lstat(self.socket_path)
            if not statmod.S_ISSOCK(st.st_mode):
                raise RuntimeError("stale_path_not_socket")
            if st.st_uid != os.getuid():
                raise RuntimeError("socket_not_owned")
            socket_path.unlink()

        self.server = await asyncio.start_unix_server(self.handle_conn, path=self.socket_path, backlog=32)
        os.chmod(self.socket_path, 0o600)
        st = os.lstat(self.socket_path)
        if not statmod.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
            raise RuntimeError("socket_security_failure")

        discovery_written = False
        self._atomic_write_discovery(self.socket_path)
        discovery_written = True
        slog("INFO", "daemon_started", socket=self.socket_path, pid=os.getpid())
        self.running = True

        await self.connect_iterm()
        asyncio.create_task(self.health_monitor())

        try:
            async with self.server:
                while self.running:
                    await asyncio.sleep(0.1)
        finally:
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


# ---- helpers -----------------------------------------------------------------
def _cap(text: str) -> str:
    if len(text) <= MAX_CHARS:
        return text
    return text[-MAX_CHARS:]


async def _main():
    daemon = Daemon()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, setattr, daemon, "running", False)
    try:
        await daemon.run()
    except Exception as e:
        slog("FATAL", "daemon_crash", err=str(e))
        raise


if __name__ == "__main__":
    asyncio.run(_main())
