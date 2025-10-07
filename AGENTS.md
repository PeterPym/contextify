# Repository Guidelines

## Target Platform & Tooling
- Xcode: 16+ (set Command Line Tools to Xcode 16).
- SDKs: Base `macOS 26` (Tahoe); min deployment `macOS 14` or `15`.
- Language: Swift 6; Frameworks: SwiftUI, Observation; optional: SwiftData, Core ML.
- Availability: gate Tahoe-only APIs (`@available(macOS 26, *)`) with clear fallbacks.

## Project Structure & Module Organization
- Source lives under `app/` (SwiftUI macOS HUD) and `cli/` (session/automation tools) when added.
- Documentation in `docs/` (e.g., `docs/roadmap/`) and acceptance/run guides per phase.
- Tests in `tests/` mirroring targets (e.g., `app/Tests/`, `cli/tests/`).
- Assets in `assets/` (icons, symbols). Working artifacts in per‑project `docs/sessions/` as described in the roadmap.

Example layout:
```
app/ ContextifyHUD.xcodeproj …
cli/ context/ …
docs/ roadmap/ …
tests/ app/ cli/
assets/ icons/
```

## Build, Test, and Development Commands
- Preferred: `bash scripts/xc.sh build` (auto-uses Xcode‑beta if installed; DerivedData under `build/`).
- Tests: `bash scripts/xc.sh test` (Swift Testing/XCTest if configured).
- Logs/Results: script writes logs to `build/logs/…` and result bundles to `build/ResultBundles/…`. Use these for error triage; builds fail fast on non‑zero.
- Direct (beta): `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Contextify/Contextify.xcodeproj -scheme Contextify -destination 'platform=macOS' build`.
- Xcode GUI: open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on “My Mac”.

## Git Hooks (Pre-commit Build Guard)
- Enable hooks: `git config core.hooksPath .githooks`
- Behavior: when files under `Contextify/` are staged, the pre-commit hook runs `scripts/xc.sh build` (using Xcode‑beta if present). If the build fails, the commit is blocked; check logs under `build/logs/` and `.xcresult` under `build/ResultBundles/`.

## Coding Style & Naming Conventions
- Swift: 2‑space indent; follow Swift API Design Guidelines. Types `UpperCamelCase`, methods/vars `lowerCamelCase`.
- Concurrency (Swift 6): use async/await, structured `Task`s, `@MainActor` for UI, `Sendable` where crossing threads; avoid detached tasks.
- State: prefer Observation (`@Observable`) or `@StateObject` ViewModels; keep Views declarative and side‑effect‑free.
- Availability: isolate new APIs behind small adapters; `#available(macOS 26, *)` guards with working fallbacks.
- Python (if present): Black (line length 88), isort, flake8; snake_case for functions/vars, PascalCase for classes.
- File/dir names: kebab‑case for non‑code folders (e.g., `docs/sessions/active/`).
- Keep modules small; separate UI (Views), state (ViewModels), and services.

## Testing Guidelines
- Use `XCTest` (or Swift Testing if adopted) for app modules; place under `app/Tests/…Tests.swift`.
- Use `pytest` for CLI utilities under `cli/tests/` with `test_*.py` files.
- Prefer fast, deterministic tests; include minimal fixtures under `tests/fixtures/`.
- Target: add tests with every feature; smoke tests for HUD launch and file ingest flow.

## Project Setup Recommendation
- Preferred (interactive): create a new macOS App (SwiftUI) in Xcode 16, name `ContextifyHUD`, Base SDK `macOS 26`, min `macOS 14/15`. This ensures correct signing, targets, previews, and SDK selection. After creation, we add Views/ViewModels and tests via PRs.
- Alternative (sample‑based): start from an Apple SwiftUI macOS sample that demonstrates drag & drop or `DocumentGroup`, then replace the root view with our HUD and keep the project settings. Avoid iOS‑only samples.
- Avoid: generating `.xcodeproj` by hand in CI; Xcode manages capabilities and schemes more reliably.

## Quickstart For Agents
- Ensure Xcode-beta is installed and selected by the script (it auto-detects).
- Build once: `bash scripts/xc.sh build`.
- If CLI fails, verify: `xcodebuild -version` and `xcode-select -p` (set `DEVELOPER_DIR` or use Xcode GUI).
- Persistence precedence (app startup): bookmark → stored path → env/CWD detection. Fallbacks still follow ENV → persisted → CWD → existing during runtime updates.
- Backward compatibility is out of scope: assume clean builds with no user data and remove legacy migrations instead of maintaining phased deprecations.
- Keep PRs small; rely on CI (macOS build workflow) to validate changes.
- Never run destructive git commands (e.g. `git restore`, `reset --hard`, `clean`) on a teammate’s work without first creating a backup branch or patch; preserve in-progress changes at all costs.
- NEVER delete or clean tracked files without a backup branch/patch that has been coordinated with the user.

## Commit & Pull Request Guidelines
- Commits: Conventional Commits (e.g., `feat(hud): add drop target`, `fix(cli): checkpoint writes timestamp`).
- Scope small, descriptive commits; prefer present tense, imperative mood.
- Keep commits atomic—each commit should represent a single logical change; never bundle unrelated edits.
- Do not attribute work to Codex (or other agents) in commit messages, PR descriptions, or change logs; keep authorship human-focused.
- PRs: clear summary, linked issues, screenshots/GIFs for UI, reproduction or acceptance steps, and notes on risks.
- Require passing checks and reviewer approval before merge; rebase onto `main`.

## Security & Configuration Tips
- Default to no network access unless explicitly enabled; avoid committing secrets.
- Session data belongs under `<project>/docs/sessions/` and may be versioned; do not store sensitive user data there.
- Log minimally with timestamps; exclude local paths or tokens.

## Useful References (Apple)
- SwiftUI `onDrop`: https://developer.apple.com/documentation/swiftui/view/ondrop(of:isTargeted:perform/)
- Transferable (modern data): https://developer.apple.com/documentation/coretransferable/transferable
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- DocumentGroup: https://developer.apple.com/documentation/swiftui/documentgroup
- Testing (Swift Testing/XCTest): https://developer.apple.com/documentation/testing
