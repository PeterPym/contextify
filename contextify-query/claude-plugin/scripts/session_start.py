#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shlex
import sys
from pathlib import Path


def main() -> int:
    env_file = os.environ.get("CLAUDE_ENV_FILE")
    if not env_file:
        return 0

    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    transcript_path = payload.get("transcript_path")
    session_id = payload.get("session_id")

    transcript_id = None
    if isinstance(transcript_path, str) and transcript_path:
        name = Path(transcript_path).name
        if name.endswith(".jsonl"):
            transcript_id = name[: -len(".jsonl")]

    exports: list[tuple[str, str]] = []
    if isinstance(session_id, str) and session_id:
        exports.append(("CONTEXTIFY_CLAUDE_SESSION_ID", session_id))
    if isinstance(transcript_path, str) and transcript_path:
        exports.append(("CONTEXTIFY_CLAUDE_TRANSCRIPT_PATH", transcript_path))
    if isinstance(transcript_id, str) and transcript_id:
        exports.append(("CONTEXTIFY_CLAUDE_TRANSCRIPT_ID", transcript_id))

    if not exports:
        return 0

    lines = [f"export {key}={shlex.quote(value)}\n" for key, value in exports]
    try:
        Path(env_file).parent.mkdir(parents=True, exist_ok=True)
        with open(env_file, "a", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception:
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

