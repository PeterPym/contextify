# UX Research: Competitive Analysis

Collected UX patterns from well-designed macOS applications for reference when designing Contextify onboarding and permission flows.

## Rogue Amoeba Loopback

**Application:** Loopback 2.x by Rogue Amoeba
**Category:** Professional audio routing software
**Website:** https://rogueamoeba.com/loopback/

Loopback creates virtual audio devices on macOS, allowing users to route audio between applications. It requires system-level permissions (ARK audio driver, system audio access, microphone) and has an excellent onboarding experience that handles these gracefully.

### Why This Is Relevant to Contextify

Contextify also requires:
- File system access (transcript directories)
- Potentially sensitive permissions (in sandboxed/App Store builds)
- User education about what the app does and why

Loopback demonstrates:
1. **Progressive disclosure** - Features explained one at a time
2. **Permission justification** - Each permission card explains WHY it's needed
3. **Visual feedback** - Real-time checkmarks as permissions are granted
4. **Graceful blocking** - App can't proceed until required permissions granted

### Assets

#### `loopback-onboarding/` - Quick Tour Wizard (5 screens)

| File | Description |
|------|-------------|
| `01-welcome-overview.png` | Welcome screen with app screenshot, tagline, and 5-dot progress indicator |
| `02-virtual-audio-devices.png` | Explains core concept: Audio Sources -> Loopback -> Audio Applications |
| `03-combine-audio-sources.png` | Shows combining Music + USB Microphone into virtual device |
| `04-map-individual-channels.png` | Demonstrates channel mapping with visual wire connections |
| `05-using-loopback-devices.png` | Final screen showing integration with FaceTime, GarageBand, Skype, System Prefs |

**UX Patterns:**
- Consistent pagination dots (5 total)
- Previous/Next navigation with "Close Tour" on final screen
- Mix of illustrations and actual UI screenshots
- Short, scannable text blocks (2 paragraphs max per screen)

#### `loopback-permissions/` - Permission Dialog (4 states)

| File | Description |
|------|-------------|
| `01-initial-all-pending.png` | Three permission cards, all showing "Enable" buttons, "Required" badges |
| `02-ark-enabled.png` | First card shows green checkmark "Enabled", others still pending |
| `03-system-audio-enabled.png` | Two cards enabled, Microphone pending with "Enable" button active |
| `04-microphone-granting-spinner.png` | All cards processed, third shows spinner while macOS dialog appears |

**UX Patterns:**
- Cards unlock sequentially (can't enable #2 until #1 complete)
- "Required" badge clearly marks non-optional permissions
- Each card explains what the permission enables, not just what it is
- Spinner feedback during async macOS permission dialogs
- "Continue" button stays disabled until all required permissions granted

#### `loopback-full-reset.md` - Reset Procedure

Documentation for fully resetting Loopback to fresh-install state, including:
- Preference file locations
- TCC permission reset commands
- ARK driver removal (requires sudo)
- CoreAudio restart procedure

Useful for testing onboarding flows during development.

## Adding New Research

When adding competitive research:

1. Create a subdirectory: `{app-name}-{feature}/`
2. Use numbered, descriptive filenames: `01-description.png`
3. Compress images before committing (pngquant or sips)
4. Update this README with context and UX patterns observed
5. Note relevance to Contextify features

## Date Captured

December 2025, macOS 26 (Tahoe)
