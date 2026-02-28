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
