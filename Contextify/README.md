# Contextify App (Xcode Project)

This folder contains the macOS SwiftUI app used for Contextify’s HUD.

## Run
- Open `Contextify.xcodeproj` and select the `Contextify` scheme.
- Run on “My Mac”. Minimum macOS: 15. Base SDK: macOS 26 (Xcode 26 beta).

## Build (CLI)
- Preferred: `bash ../scripts/xc.sh build` (auto‑uses Xcode‑beta; logs to `../build/logs/`).
- Result bundles saved to `../build/ResultBundles/` for Xcode inspection.

## Outputs
- Artifacts: `~/Contextify/outputs/` (ignored by git).
- Buttons: “Last: …” reveals the file; “Reveal Outputs” opens the folder.

## Project Root & Branch
- First run: use File → “Set Project Root…” to select your repo. The choice persists.
- Header shows the current git branch; click “Refresh” after switching branches.

## Phase 2 Features
- Drag/drop files or submit a URL → timestamped Markdown with basic metadata.
- Dropped files copied to `outputs/ingest/`.
- “Checkpoint” writes a Markdown file under `outputs/checkpoints/`.
- Ingest shows a spinner and disables controls.

## Pre‑commit Guard
- Enable hooks at repo root: `git config core.hooksPath .githooks`.
- Commits touching `Contextify/` will build the app; failures block the commit with logs.

## Notes
- Swift 6 + SwiftUI. Drop handling uses completion handlers, marshaled to the main actor.
