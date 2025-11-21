# Revision Notes

## Transcript Browser Window

The transcript browsing experience now handles large collections smoothly and provides clear feedback during AI-powered metadata generation:

- **Smart loading:** Opens instantly even with 400+ transcripts. AI summaries generate only for what you're looking at, not everything at once.
- **Better visuals:** Session rows now match the timeline's clean design. Removed clutter, improved spacing, and made everything easier to scan.
- **Live feedback:** See exactly what's happening when AI generates titles and descriptions. Shows a progress indicator ("Processing 5 items") and marks each session with a hourglass while working on it.
- **Automatic updates:** When AI finishes generating a summary, it appears immediately. Switch between transcripts and the detail pane always shows the right information.
- **Quick actions:** Click info buttons to understand low-confidence summaries or why sessions are marked as brief. Right-click any session to regenerate its metadata. Use the menu to hide brief sessions (on by default).
- **Smarter processing:** Newest sessions get summarized first. Scrolling away from a session stops working on it to focus on what you're actually viewing.

## Bug Fixes

- **Status bar:** No more flickering between different states. Shows consistent status with spinner when work is in progress.
- **Detail pane:** Fixed issue where switching between sessions would sometimes show outdated information.

## New Features

- **Transcript corruption repair:** Automatic detection and repair tools for corrupted Claude Code Web transcripts (happens when using the "teleport" feature). See `scripts/transcript-repair/` for the repair utility.
