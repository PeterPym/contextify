# Screenshot Automation Scripts

Scripts to automate positioning windows and capturing App Store screenshots.

## Quick Start

```bash
# List your iTerm2 windows to find the right index
./scripts/screenshots/list-iterm-windows.sh

# Capture screenshot using window #2
./scripts/screenshots/capture-screenshot.sh main-hud 2

# Or let script countdown and you click the window
./scripts/screenshots/capture-screenshot.sh timeline-view
```

## Scripts

### `list-iterm-windows.sh`

Lists all iTerm2 windows with their indices, session names, and paths.

**Usage:**
```bash
./scripts/screenshots/list-iterm-windows.sh
```

**Output:**
```
iTerm2 Windows:
===============

Window #1: rob — zsh — 111×53
  Session: rob — zsh — 111×53
  Path: /Users/rob/code/projects/contextify

Window #2: claude — zsh — 80×24
  Session: Default Session
  Path: /Users/rob/code/projects/contextify
```

### `capture-screenshot.sh`

Positions windows and automatically captures a 1440x900 screenshot.

**Usage:**
```bash
./scripts/screenshots/capture-screenshot.sh [name] [window-number]
```

**Parameters:**
- `name`: Optional. Description for the screenshot file (default: "screenshot")
- `window-number`: Optional. iTerm2 window index from list-iterm-windows.sh

**Examples:**
```bash
# Manual selection (3-second countdown)
./scripts/screenshots/capture-screenshot.sh main-hud

# Use specific window by index
./scripts/screenshots/capture-screenshot.sh main-hud 2
./scripts/screenshots/capture-screenshot.sh timeline-view 1
```

**Output:**
- Screenshots saved to: `appstore-metadata/screenshots/`
- Format: `{name}-{timestamp}.png`
- Size: 1440x900 pixels

### `setup-screenshot.sh`

Positions Contextify and iTerm2 windows for screenshot capture.

**Usage:**
```bash
./scripts/screenshots/setup-screenshot.sh [window-number]
```

**Parameters:**
- `window-number`: Optional. iTerm2 window index (1, 2, 3, etc.)

Usually called by `capture-screenshot.sh`, but can be run standalone for manual screenshots.

## Window Layout

Screenshots show:
- **Left:** Contextify HUD (580x700px) - Showcases the app
- **Right:** iTerm2 window (800x850px) - Provides context

Both windows are vertically centered within the 1440x900 capture area.

## Tips

1. **Match conversations:** Use window index to ensure the iTerm2 window matches the Contextify conversation displayed
2. **Prepare the scene:** Set up your Contextify view (timeline, project switcher, etc.) before running the script
3. **Multiple captures:** Run the script multiple times with different window states for various screenshots
