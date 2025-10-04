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
    # Try app bundle structure (Resources/iterm2_daemon.py -> Resources/Python/...)
    bundle_site = script_dir / "Python" / "lib" / "python" / "site-packages"
    if bundle_site.exists():
        sys.path.insert(0, str(bundle_site))
    else:
        # Try project dev structure (scripts/iterm2_daemon.py -> ../Resources/Python/...)
        project_root = script_dir.parent
        dev_site = project_root / "Resources" / "Python" / "lib" / "python" / "site-packages"
        if dev_site.exists():
            sys.path.insert(0, str(dev_site))

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
