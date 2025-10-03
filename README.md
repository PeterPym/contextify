# Contextify (macOS SwiftUI HUD)

Contextify is a lightweight macOS HUD for project-centric sessions. It ingests dropped files or URLs, writes timestamped Markdown artifacts, and provides quick checkpoints. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK).

## Quickstart
- Requirements: Xcode 26.x (beta OK), macOS 15+ runtime.
- Build (beta auto-detected): `bash scripts/xc.sh build`
- Run in Xcode: open `Contextify/Contextify.xcodeproj` → scheme `Contextify` → Run on “My Mac”.
- Outputs: `Application Support/Contextify/outputs` (ignored by git). Use the “Reveal Outputs” button or click “Last: …” in the header to open in Finder.

## Enable Build Guard (Pre-commit)
- Turn on hooks: `git config core.hooksPath .githooks`
- What it does: When files in `Contextify/` are staged, the pre-commit hook runs a headless build (Xcode‑beta preferred). On failure, commit is blocked and logs are written to `build/logs/…`; an `.xcresult` is saved under `build/ResultBundles/…`.
- One-shot setup: `make hooks-setup` (also sets executable bits), or `make setup` to enable and run a first build.

## Daily Commands
- Build: `make build` (or `bash scripts/xc.sh build`)
- Test: `make test` (if tests are configured)
- Clean: `make clean`

## Current Functionality
- File drop or URL submit → creates a Markdown artifact with metadata.
- Copies dropped files to `outputs/ingest/` with a timestamped name.
- “Checkpoint” creates a dated Markdown checkpoint under `outputs/checkpoints/`.
- “Set Project Root…” (File menu) to show git branch in the header; persists across launches.
- Spinner and temporary control disable during ingest.

## Notes
- Uses Swift 6 strict concurrency. Drag/drop is implemented with completion handlers and marshaling to the main actor.
- For docs and Apple references, see `docs/knowledge/apple/readme.md`. For contributor guidance, see `AGENTS.md`.
