#!/usr/bin/env bash
set -euo pipefail

DISC="$HOME/Library/Application Support/Contextify/run/daemon.path"

if [[ ! -f "$DISC" ]]; then
    echo "❌ Discovery file not found: $DISC"
    exit 2
fi

SOCK="$(cat "$DISC")"

if [[ ! -S "$SOCK" ]]; then
    echo "❌ Socket not found: $SOCK"
    exit 2
fi

python3 - <<'PY' "$SOCK"
import os, sys, socket, struct, json

sock_path = sys.argv[1]

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    s.connect(sock_path)

    req = {"id": "healthcheck", "command": "ping"}
    payload = json.dumps(req).encode("utf-8")
    header = struct.pack(">I", len(payload))
    s.sendall(header + payload)

    hdr = s.recv(4)
    if len(hdr) < 4:
        print("❌ Invalid response")
        sys.exit(3)

    ln = struct.unpack(">I", hdr)[0]
    body = b""
    while len(body) < ln:
        chunk = s.recv(ln - len(body))
        if not chunk:
            break
        body += chunk

    resp = json.loads(body.decode("utf-8"))

    if resp.get("success"):
        print("✅ Daemon is healthy")
        print(f"   Status: {resp.get('status')}")
        print(f"   Connection healthy: {resp.get('connection_healthy')}")
        print(f"   Uptime: {resp.get('uptime_ms')}ms")
        sys.exit(0)
    else:
        print(f"❌ Error: {resp.get('error')}")
        sys.exit(3)

except Exception as e:
    print(f"❌ Healthcheck failed: {e}")
    sys.exit(3)
PY
