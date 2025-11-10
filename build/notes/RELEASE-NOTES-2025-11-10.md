# Revision Notes

## Performance Improvements

- **Transcript metadata loading:** Intelligent viewport-aware queue processes only visible sessions, preventing Apple Intelligence overload when browsing large transcript collections (400+ sessions now load instantly).
- **Date formatting optimization:** Eliminated O(n) allocations in transcript list rendering, significantly improving scroll performance.
- **Initial load experience:** Cached metadata loads immediately on view appearance, showing existing titles/descriptions without delay.

## UI Improvements

- **Transcript session rows:** Unified styling with timeline entries for visual consistency (removed redundant provider text, normalized accent bars to neutral grey, better spacing).
- **Loading indicators:** Hourglass animation appears during metadata generation with real-time queue status ("Processing X items" with spinner).
- **Detail pane updates:** Metadata refreshes automatically when generation completes; switching between transcripts now correctly resets display state.
- **Info button popovers:** Low-confidence metadata and brief sessions now show explanatory popovers on click.
- **Context menu actions:** Added "Regenerate Metadata" option for manual refresh.
- **Brief sessions filter:** New ellipsis menu with toggle to hide brief sessions (enabled by default).

## Bug Fixes

- **Metadata ordering:** Fixed LIFO queue to always process newest transcripts first, matching expected priority behavior.
- **Detail pane stale data:** Switching from summarized to unsummarized transcript no longer shows previous metadata.
- **Status bar consistency:** Queue depth always shows "Processing X items" with spinner (previously flickered between states).
- **Circuit breaker cleanup:** Fixed task lifecycle management to prevent duplicate reset Tasks.
- **Keychain password prompt:** Machine ID storage moved to Application Support, eliminating unnecessary keychain access on first launch.

## New Features

- **Transcript corruption detection:** Built-in detection and repair utility for Claude Code Web "teleport" corruption (see `scripts/transcript-repair/`).
- **Viewport-aware metadata generation:** Only visible transcript sessions queue for LLM processing, with automatic pruning on scroll (500ms debounce).
- **Batch-free processing:** Simplified queue architecture eliminates batching complexity, matching timeline queue patterns.
- **Refresh Sessions removal:** Automatic session discovery makes manual refresh button redundant (removed from UI).

## Developer Experience

- **CI workflow improvements:** GitHub Actions on-demand builds with automatic trigger scripts for Claude Code Web and Linux environments.
- **Comprehensive documentation:** Updated LLM architecture docs to reflect LIFO sequential processing and viewport-aware pruning.
- **Build monitoring:** Automated result reporting for CI builds with downloadable logs and artifacts.

## Breaking Changes

None. All changes are backward-compatible.

## Known Issues

- Transcript metadata row updates may occasionally lag behind generation completion (investigating notification reliability).
