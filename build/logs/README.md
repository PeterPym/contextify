# Logs Archive

This directory stores ad-hoc diagnostic artifacts captured during local
validation runs. Each entry below explains why the corresponding log was kept
and how it relates to release readiness.

| File | Description |
| ---- | ----------- |
| `transcript-queue-monitor-20251114-224840.log` | Captured during `bash scripts/xc.sh --dist=appstore Debug cleanrun` on 2025-11-14. Demonstrates that sandbox/App Store builds ingest transcripts successfully without emitting `[GIT-BROKEN]` errors after git monitoring was disabled. Serves as evidence for TODO items NOGIT4/NOGIT5. |
| `transcript-queue-monitor-20251114-230559.log` | Follow-up log from the same App Store validation session highlighting residual `HOOVER-PARSE-ERROR` entries (ParserError 3) for several transcripts. Retained to pair with the primary cleanrun log and aid future debugging of the parse failures observed post-fix. |
