#!/usr/bin/env python3
"""Simple test client for iTerm2 daemon."""

import json
import socket
import struct
import sys
import time
from pathlib import Path


def pack_json(payload):
    data = json.dumps(payload).encode("utf-8")
    return struct.pack(">I", len(data)) + data


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
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    try:
        sock.connect(sock_path)
        sock.sendall(pack_json(req))
        return read_framed_json(sock)
    finally:
        sock.close()


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
    print(f"Elapsed: {int((t1 - t0) * 1000)}ms; Daemon latency: {resp.get('latency_ms')}; Source: {resp.get('source')}")
    if resp.get("success"):
        content = resp.get("content", "")
        print("Tail:")
        for line in content.splitlines()[-3:]:
            print("  ", line[:120])
    else:
        print("Error:", resp)


if __name__ == "__main__":
    main()
