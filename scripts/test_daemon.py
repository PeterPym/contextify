#!/usr/bin/env python3
"""
Simple test client for iTerm2 daemon.
Tests ping and get_content commands via Unix socket.
"""

import json
import socket
import struct
import sys
import time
from pathlib import Path


def pack_json(payload):
    """Pack JSON into length-prefixed format."""
    b = json.dumps(payload).encode("utf-8")
    return struct.pack(">I", len(b)) + b


def read_framed_json(sock):
    """Read length-prefixed JSON from socket."""
    # Read 4-byte length header
    hdr = sock.recv(4)
    if len(hdr) < 4:
        raise RuntimeError("incomplete header")
    ln = struct.unpack(">I", hdr)[0]

    # Read body
    body = b""
    while len(body) < ln:
        chunk = sock.recv(ln - len(body))
        if not chunk:
            raise RuntimeError("incomplete body")
        body += chunk

    return json.loads(body.decode("utf-8"))


def send_command(sock_path, command, **params):
    """Send a command to the daemon and return response."""
    req = {"id": f"test-{int(time.time()*1000)}", "command": command}
    req.update(params)

    # Connect to socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2.0)

    try:
        sock.connect(sock_path)

        # Send request
        sock.sendall(pack_json(req))

        # Read response
        resp = read_framed_json(sock)
        return resp
    finally:
        sock.close()


def main():
    # Find discovery file
    discovery_path = Path.home() / "Library/Application Support/Contextify/run/daemon.path"

    if not discovery_path.exists():
        print("❌ Discovery file not found:", discovery_path)
        print("   Start the daemon first with: python3 scripts/iterm2_daemon.py")
        sys.exit(1)

    sock_path = discovery_path.read_text().strip()
    print(f"📡 Daemon socket: {sock_path}")

    # Test 1: Ping
    print("\n1️⃣  Testing ping...")
    try:
        resp = send_command(sock_path, "ping")
        if resp.get("success"):
            print(f"✅ Ping successful!")
            print(f"   Status: {resp.get('status')}")
            print(f"   Connection healthy: {resp.get('connection_healthy')}")
            print(f"   iTerm2 down: {resp.get('iterm2_down')}")
            print(f"   Uptime: {resp.get('uptime_ms')}ms")
        else:
            print(f"❌ Ping failed: {resp}")
    except Exception as e:
        print(f"❌ Ping error: {e}")
        sys.exit(1)

    # Test 2: Get content
    print("\n2️⃣  Testing get_content...")
    try:
        start = time.time()
        resp = send_command(sock_path, "get_content", max_lines=100)
        elapsed_ms = int((time.time() - start) * 1000)

        if resp.get("success"):
            content = resp.get("content", "")
            print(f"✅ Content fetched in {elapsed_ms}ms!")
            print(f"   Source: {resp.get('source')}")
            print(f"   Daemon latency: {resp.get('latency_ms')}ms")
            print(f"   Content length: {len(content)} chars")
            print(f"   Line count: {resp.get('line_count')}")
            if content:
                lines = content.split('\n')
                print(f"\n   Last 3 lines:")
                for line in lines[-3:]:
                    print(f"     {line[:80]}")
        else:
            print(f"❌ Get content failed: {resp.get('error')}")
            print(f"   Details: {resp.get('details')}")
    except Exception as e:
        print(f"❌ Get content error: {e}")
        sys.exit(1)

    print("\n✅ All tests passed!")


if __name__ == "__main__":
    main()
