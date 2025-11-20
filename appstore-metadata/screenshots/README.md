# App Store Screenshots

Organization for screenshot workflow.

## Directory Structure

```
screenshots/
├── drafts/              # Work in progress (gitignored)
│   ├── *.png           # Raw screenshots from capture script
│   └── *-with-text.png # Screenshots with text overlays
├── releases/            # Final approved screenshots (committed to git)
│   ├── 01-main-hud.png
│   ├── 02-ai-summaries.png
│   └── ...
├── alternates/          # Alternative versions for comparison
└── SCREENSHOT-SPECIFICATIONS.md
```

## Workflow

### 1. Capture Draft Screenshots

All captures go to `drafts/` (gitignored):

```bash
# Without text overlay
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2

# With text overlay (creates both versions)
./scripts/screenshots/capture-screenshot.sh 01-main-hud 2 --text "Real-time AI monitoring"
```

**Output:**
- `drafts/01-main-hud-20251119-123456.png` (original)
- `drafts/01-main-hud-20251119-123456-with-text.png` (with overlay)

### 2. Review and Iterate

- Review drafts in Preview/Finder
- Capture multiple versions
- Iterate on positioning, text, etc.

### 3. Promote to Releases

When happy with a screenshot, copy to `releases/` with clean names:

```bash
# Copy and rename final version
cp drafts/01-main-hud-20251119-123456-with-text.png releases/01-main-hud.png
```

### 4. Commit Final Releases

```bash
git add appstore-metadata/screenshots/releases/
git commit -m "feat(appstore): add final screenshots for submission"
```

## Naming Convention

**Drafts:** Use descriptive names with timestamps
- `01-main-hud-20251119-123456.png`
- `02-ai-summaries-20251119-123456-with-text.png`

**Releases:** Use clean numbered names (App Store order)
- `01-main-hud.png`
- `02-ai-summaries.png`
- `03-project-switcher.png`
- `04-real-time-monitoring.png`
- `05-settings-panel.png`

## Screenshot Requirements

- **Dimensions:** 1440×900 (macOS)
- **Format:** PNG
- **Content:** Clean, professional, representative of actual app
- **Text overlays:** Optional, Sketch-style with New York serif font

See `SCREENSHOT-SPECIFICATIONS.md` for full App Store requirements.
