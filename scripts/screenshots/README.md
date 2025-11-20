# Screenshot Automation Scripts

Scripts to automate positioning windows and capturing App Store screenshots.

## Requirements

- **ImageMagick** (required for text overlays):
  ```bash
  brew install imagemagick
  ```
- **oxipng** (optional but recommended): Lossless PNG compression, saves 30-50%
  ```bash
  brew install oxipng
  ```

## Quick Start

```bash
# List your iTerm2 windows to find the right index
./scripts/screenshots/list-iterm-windows.sh

# Capture screenshot using window #2
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2

# With text overlay (Sketch-style)
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2 --text "Real-time AI monitoring"

# Or let script countdown and you click the window
./scripts/screenshots/capture-screenshot.sh 02-timeline
```

## Workflow

All captures go to `appstore-metadata/screenshots/drafts/` (gitignored) so you can experiment freely:

1. **Capture drafts** with the script
2. **Review** in Preview/Finder
3. **Promote finals** to `releases/` when satisfied:
   ```bash
   cp appstore-metadata/screenshots/drafts/01-main-hud-*-with-text.png \
      appstore-metadata/screenshots/releases/01-main-hud.png
   ```
4. **Commit** only the finals

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

Positions windows and automatically captures a 1440x900 screenshot. **Opens the screenshot automatically by default** for immediate review.

**Usage:**
```bash
./scripts/screenshots/capture-screenshot.sh [name] [window-number] [--text "Overlay text"] [--no-open]
```

**Parameters:**
- `name`: Optional. Description for the screenshot file (default: "screenshot")
- `window-number`: Optional. iTerm2 window index from list-iterm-windows.sh
- `--text "Text"`: Optional. Add Sketch-style text overlay with New York serif font
- `--no-open`: Optional. Skip auto-opening the screenshot

**Examples:**
```bash
# Manual selection (3-second countdown), opens automatically
./scripts/screenshots/capture-screenshot.sh 01-main-hud

# Use specific window by index
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2

# With text overlay (creates both original and with-text versions)
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2 --text "Real-time AI monitoring"

# Use specific window, don't open
./scripts/screenshots/capture-screenshot.sh 02-timeline 1 --no-open

# With text, no auto-open
./scripts/screenshots/capture-screenshot.sh 03-projects 2 --text "Track multiple projects" --no-open
```

**Output:**
- Screenshots saved to: `appstore-metadata/screenshots/drafts/` (gitignored)
- Format without text: `{name}-{timestamp}.png`
- Format with text: `{name}-{timestamp}-with-text.png`
- Size: 1440x900 pixels
- **Auto-opens** in default image viewer (unless `--no-open` specified)

### `setup-screenshot.sh`

Positions Contextify and iTerm2 windows for screenshot capture.

**Usage:**
```bash
./scripts/screenshots/setup-screenshot.sh [window-number]
```

**Parameters:**
- `window-number`: Optional. iTerm2 window index (1, 2, 3, etc.)

Usually called by `capture-screenshot.sh`, but can be run standalone for manual screenshots.

### `add-text-overlay.sh`

Adds Sketch-style text overlay to existing screenshots using ImageMagick.

**Usage:**
```bash
./scripts/screenshots/add-text-overlay.sh <input-image> <text> [output-image]
```

**Parameters:**
- `input-image`: Path to source screenshot
- `text`: Text to overlay (e.g., "Real-time AI monitoring")
- `output-image`: Optional output path (defaults to drafts/ with -with-text.png suffix)

**Examples:**
```bash
# Add text to existing screenshot
./scripts/screenshots/add-text-overlay.sh \
  appstore-metadata/screenshots/drafts/01-main-hud-20251119-123456.png \
  "Real-time AI monitoring"

# Specify output location
./scripts/screenshots/add-text-overlay.sh \
  input.png \
  "Track multiple projects" \
  output-final.png
```

**Font:** Uses .New-York-Medium serif at 68pt (Apple's editorial font)

## Window Layout

Screenshots show:
- **Left:** Contextify HUD (483×633px, 15% larger) - Compact design showcasing the app
- **Right:** iTerm2 window (633×460px) - Provides development context
- **Gap:** 50px between windows
- **Padding:** 137px on left and right (centered in 1440px frame)
- **Alignment:** Bottoms aligned at Y=910

Total capture area: 1440×900 pixels (macOS App Store requirement)

## Tips

1. **Match conversations:** Use window index to ensure the iTerm2 window matches the Contextify conversation displayed
2. **Prepare the scene:** Set up your Contextify view (timeline, project switcher, etc.) before running the script
3. **Experiment freely:** All drafts are gitignored, so capture as many variations as you need
4. **Text overlay suggestions:**
   - "Real-time AI conversation monitoring"
   - "Intelligent summaries for every session"
   - "Track multiple projects effortlessly"
   - "Never lose context while coding"
5. **Promote to releases:** When satisfied, copy from `drafts/` to `releases/` with clean names (e.g., `01-main-hud.png`)
