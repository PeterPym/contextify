# Screenshot Automation Scripts

Scripts to automate positioning windows and capturing App Store screenshots.

> **⚠️ Note for AI agents:** This README contains marketing content (Screenshot Plan section) that is temporarily co-located with technical scripts. This content should eventually be refactored to live in dedicated marketing/release documentation under `appstore-metadata/` or a future `marketing/` directory. See "Marketing Organization Strategy" section below.

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

## Screenshot Plan

This section documents the narrative flow and content strategy for the 5 App Store screenshots.

### Overview

The screenshots tell a story about Contextify's value proposition:
1. **Real-time monitoring** during long AI sessions
2. **Universal compatibility** with major AI coding tools
3. **Multi-project management** with notification system
4. **Deep exploration** of transcript history
5. **Centralized database** with cloud backup support

### 1. Main HUD (01-main-hud)

**Shows:** Real-time conversation monitoring with timeline view
**Illustrates:** Core value - stay informed during long AI coding sessions without context switching
**Composition:** Dual window - HUD on left + iTerm2 on right (shows active AI session)
**Text overlay:** "Stay in the loop during long AI conversations"
**Status:** ✅ Preset complete

**Key elements to capture:**
- Timeline with recent conversation entries
- LLM-generated summaries visible
- Real-time updates indicator
- Clean, focused HUD layout

### 2. Dual Provider Support (02-dual-provider)

**Shows:** Timeline view with mixed Claude Code and Codex CLI entries
**Illustrates:** Works seamlessly with both major AI coding assistants
**Composition:** Dual window - timeline showing provider icons for different entries
**Text overlay:** "Works seamlessly with both Claude Code and Codex CLI"
**Status:** ✅ Preset complete, needs timeline data with mixed providers

**Key elements to capture:**
- Visible Claude Code icon (purple) and Codex CLI icon (blue/white)
- Alternating entries from different providers
- Unified timeline despite different sources
- Smooth integration aesthetic

### 3. Project Tabs with Unread Badges (03-project-tabs)

**Shows:** Main HUD window with multiple project tabs, unread count badges visible
**Illustrates:** Multi-project workflow with notification system - never miss updates across codebases
**Composition:** Single window - HUD with prominent project tabs OR dual window with magnifier callout
**Text overlay:** "Track conversations across multiple projects" (or similar)
**Status:** ⚠️ Needs design + implementation

**Key elements to capture:**
- 3-4 project tabs clearly visible
- Unread count badges on inactive tabs (e.g., "5", "12")
- Optional: circular magnifier overlay (iOS/macOS style) zooming 2-3x on a badge
- Active tab showing current conversation

**Open questions:**
- Should this be single window (just HUD) or dual window?
- Magnifier callout or just clear visibility of badges?
- What's the best text overlay to emphasize the multi-project + notification value?

### 4. Transcripts (04-transcript-inventory)

**Shows:** Transcript browser window with list of past conversations
**Illustrates:** Deep exploration capability - review and gain insights from history
**Composition:** Single window - centered transcript browser
**Text overlay:** "Explore source transcripts and gain insights"
**Status:** ✅ Preset complete

**Key elements to capture:**
- List of transcripts with metadata (date, project, provider)
- Search/filter capabilities visible
- Clean inventory UI centered in frame
- Suggests rich historical data

### 5. Settings / Database (05-settings)

**Shows:** Settings window with Database tab active, Dropbox storage location visible
**Illustrates:** Centralized SQL database with cloud backup support
**Composition:** Single window - settings dialog centered, Dropbox badge visible
**Text overlay:** "Centralize scattered transcripts / into one queryable database" (two lines)
**Status:** ✅ Preset complete

**Key elements to capture:**
- Database settings tab prominent
- Dropbox badge visible (visual, not text - trademark sensitivity)
- Custom database location path shown
- Professional, trustworthy settings UI

**Note:** Avoids explicit "Dropbox" or "iCloud" text in overlay due to Apple trademark sensitivity. Shows feature visually.

---

### Narrative Flow

The 5 screenshots progress from **immediate value** → **broad compatibility** → **workflow integration** → **depth of features** → **infrastructure**.

1. Hook with real-time monitoring (solves immediate pain)
2. Reassure about tool compatibility (works with what you use)
3. Show it scales to real workflows (multiple projects)
4. Demonstrate depth (historical exploration)
5. Build trust with infrastructure (serious database, backups)

---

### Current Issues & Open Questions

**Duplicate title (screenshots #2 and #4):**
- Original #4 (project-switcher) had same text as #2: "Works with both Claude Code and Codex CLI"
- Proposed reorder: Move transcript-inventory from #3 to #4, create new #3 for project tabs with unread badges
- New #3 needs title that emphasizes multi-project + notifications

**Screenshot #3 design:**
- Need to decide: single window HUD or dual window with magnifier?
- Magnifier callout could be powerful visual but adds complexity
- Text overlay needs to emphasize both multi-project AND unread notifications

**Preset implementation:**
- #3 (project-tabs) not yet implemented
- Needs AppleScript for window positioning + possible magnifier overlay post-processing

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

## Marketing Organization Strategy

> **Note for future refactoring:** This section outlines how marketing materials, release tracking, and campaigns should be organized once we move beyond initial launch.

### Current State (Pre-Launch)

Marketing content is currently scattered:
- **Screenshots:** `appstore-metadata/screenshots/`
- **Screenshot strategy:** This README (temporary)
- **App Store metadata:** Not yet created (descriptions, keywords, categories)
- **Press materials:** Not yet created
- **Campaign tracking:** No system in place

### Proposed Structure

As the project matures, marketing materials should be centralized:

```
marketing/                          # New top-level directory
├── appstore/
│   ├── metadata.md                # App Store listing content
│   ├── screenshots/               # Move from appstore-metadata/
│   │   ├── plan.md               # Screenshot strategy (move from scripts/screenshots/README.md)
│   │   ├── releases/             # Final approved screenshots
│   │   └── alternates/           # Rejected options for reference
│   └── review-responses.md       # Template responses for app reviews
│
├── press/
│   ├── kit.md                    # Press kit with boilerplate, facts, contact
│   ├── outreach-list.md          # Target publications, bloggers, podcasters
│   ├── pitch-templates.md        # Email templates for different audiences
│   └── coverage.md               # Log of press mentions, outcomes
│
├── campaigns/
│   ├── launch-v1.md              # Launch campaign plan and results
│   ├── product-hunt.md           # Product Hunt launch plan/results
│   └── social-media.md           # Twitter, Mastodon, HN posts/engagement
│
├── website/                       # Content for contextify.sh
│   ├── copy.md                   # Website copy, headlines, CTAs
│   ├── changelog.md              # User-facing release notes
│   └── assets/                   # Hero images, demos, GIFs
│
└── analytics/
    ├── app-store-metrics.md      # Downloads, conversion rates, regions
    ├── user-feedback.md          # Aggregated feedback from support, reviews
    └── roadmap-influence.md      # How user feedback affects roadmap
```

### Campaign Tracking Framework

Each marketing activity should be documented with:

**Before launch:**
- **Goal:** What are we trying to achieve? (downloads, awareness, feedback)
- **Target audience:** Who are we reaching?
- **Channels:** Where are we posting/reaching out?
- **Timeline:** When does this happen?
- **Budget:** Any costs involved? (ads, tools, sponsorships)

**After launch:**
- **Results:** Measurable outcomes (impressions, clicks, conversions, downloads)
- **Learnings:** What worked? What didn't?
- **ROI:** Was the effort worth it?
- **Follow-ups:** Any ongoing engagement or next steps?

### Example: Press Outreach Template

Each press outreach should be logged:

```markdown
## Outreach: [Publication Name]

**Date:** 2025-12-01
**Contact:** [Name, email]
**Type:** Cold pitch / warm intro / request for review
**Message:** [Link to sent email or DM]

**Goal:** Feature article or app review
**Target audience:** Developers using AI coding tools

**Response:** [Response received, date]
**Outcome:**
- [ ] No response
- [ ] Declined
- [ ] Interested, needs more info
- [ ] Article published: [link]
- [ ] Review published: [link]

**Metrics:**
- Article views: [number]
- Referral traffic: [number]
- App Store clicks: [number]
- Downloads attributed: [number]

**Learnings:**
- What messaging resonated?
- What could be improved?
- Would we reach out again?
```

### App Store Metadata Tracking

Track how App Store listing evolves:

```markdown
## App Store Listing Changelog

### v1.0 Launch (2025-12-01)
**Title:** Contextify: AI Session Monitor
**Subtitle:** Real-time insights for Claude Code & Codex
**Keywords:** AI, coding, Claude, assistant, monitor, transcript, developer
**Screenshots:** 5 (main-hud, dual-provider, project-tabs, transcript-inventory, settings)
**Results:**
- Impressions: [number]
- Product page views: [number]
- Conversion rate: [percentage]

### v1.1 Optimization (2026-01-15)
**Changes:**
- Updated subtitle to emphasize "real-time" more
- Replaced screenshot #3 with improved unread badge visibility
- Added keyword "productivity"

**Results:**
- Impressions: [number] (+/- %)
- Conversion rate: [percentage] (+/- %)
- Learnings: [what improved or worsened]
```

### Integration with Release Process

Marketing should be integrated into the release workflow:

1. **Pre-release:** Update changelog, prepare announcement copy
2. **Release day:**
   - Update App Store metadata if needed
   - Post to social media
   - Send to press list if major release
   - Update website
3. **Post-release:**
   - Monitor App Store reviews and respond
   - Track downloads and user feedback
   - Log metrics for future reference

### Measurement Philosophy

Track what matters:
- **Vanity metrics** (followers, impressions): Useful for trends, not for decisions
- **Actionable metrics** (conversion rates, retention, engagement): Drive roadmap
- **User feedback** (reviews, support emails, feature requests): Most valuable
- **ROI** (time spent vs. downloads/revenue generated): Prioritize what works

### Next Steps for Organization

1. **Create `marketing/` directory** when App Store submission is imminent
2. **Move screenshot plan** from this README to `marketing/appstore/screenshots/plan.md`
3. **Create press kit** with boilerplate about Contextify, founder bio, contact info
4. **Set up campaign tracking** template in `marketing/campaigns/launch-v1.md`
5. **Document App Store metadata** in version-controlled markdown before submission

### Benefits of Centralized Marketing Docs

- **Historical record:** Know what we tried and what worked
- **Reusability:** Templates for future campaigns
- **Onboarding:** If someone joins team, they can see past efforts
- **Continuity:** Prevent knowledge loss over time
- **Decision-making:** Data-driven choices for future marketing
