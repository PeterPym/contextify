# Future Work

## Toast Feedback For Missing Input
- When the capture hotkey runs but `ClaudeCodeParser` finds no usable text, show a toast (or at least a log entry surfaced in the UI) so the user knows nothing was captured. Right now the failure path is silent.
- Use the existing toast overlay in `ContentView` for consistency (e.g., “No command detected. Try selecting the region you want to capture.”).

## Lock Target Terminal Tab
- Allow users to pin the iTerm2 tab/window that receives commands. Today we always target `current window/current session`, which can be the wrong buffer if the user switches panes.
- Proposal: add a “Lock Target” action that records the session’s UUID via iTerm2 API; subsequent sends should address that session explicitly. Provide UI feedback (e.g., “Target: Tab X (locked)” with a quick unlock option).

## Codex (Claude) Pane Support
- The new Codex UI in iTerm2 renders input differently; the parser fails. Investigate how the buffer is exposed (scrollback vs. structured regions) and update `ClaudeCodeParser` so captures in Codex don’t return empty.
- Ensure both send and capture pathways behave identically between classic terminal tabs and Codex tabs.

## Git Status Glance in HUD
- Next to the branch display, surface high-level repository state: staged vs staged counts, ahead/behind main (via `git status --porcelain=v2` and `git rev-list --left-right`), and highlight risky states (e.g., committing on `main` or detached HEAD).
- Ideally refresh when the HUD opens and when the watcher detects changes, so the summary stays current without manual git commands.
