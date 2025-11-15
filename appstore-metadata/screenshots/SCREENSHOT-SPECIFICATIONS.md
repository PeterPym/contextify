# Screenshot Specifications for Contextify

## Technical Requirements

- **Platform**: macOS
- **Primary Size**: 2880 x 1800 pixels (16:10 aspect ratio)
- **Alternative Sizes**: 1280 x 800, 1440 x 900, 2560 x 1600
- **Format**: PNG (preferred) or JPEG
- **Max File Size**: 10 MB per screenshot
- **Quantity**: Minimum 1, Maximum 10 (Recommended: 5-7)

## Color Space & Quality

- Use sRGB color space
- Save at highest quality (100% for JPEG, PNG-24 for PNG)
- Ensure text is crisp and readable at full resolution
- Avoid compression artifacts

## Capture Method

### Recommended Workflow

1. **Use a MacBook Pro with Retina Display** for native 2880x1800 capture
2. **Alternative**: Capture at any supported resolution and upscale/downscale to 2880x1800
3. **Use macOS Screenshot Tool**: ⌘⇧4 then Space to capture window, or ⌘⇧5 for advanced options
4. **Post-processing**: Use Pixelmator Pro, Photoshop, or Sketch for any annotations/editing

### Display Settings

- Set display resolution to "More Space" if needed for 2880x1800 native
- Disable desktop icons or use clean desktop background
- Use default system appearance (Light or Dark mode) consistently
- Ensure menu bar is clean (hide unnecessary menu bar items)

## Screenshot Sequence & Specifications

### Screenshot 1: Hero Shot - Main HUD
**Filename**: `01-main-hud.png`
**Size**: 2880 x 1800

**Description**:
The flagship screenshot that showcases Contextify's core value proposition.

**What to Show**:
- Contextify HUD window in center-right of screen, ~60% of frame
- Active conversation timeline with 5-7 visible entries
- Project name clearly visible in header
- Real-time entries showing user/assistant exchanges
- AI-generated summary panel open and visible
- Professional developer desktop in background (Terminal + VSCode/Xcode)
- Background should be slightly blurred to emphasize HUD

**Visual Elements**:
- Ensure Contextify logo is visible in HUD
- Git branch indicator showing "main" or feature branch
- Timestamp showing "Just now" or recent time
- At least one tool call entry visible (colorful, distinctive)
- Summary text should be readable and impressive

**Composition**:
- Rule of thirds: Place HUD window slightly off-center
- Background: Developer environment (code editor, terminal)
- Lighting: Professional, well-lit UI
- No text overlays needed - let the UI speak for itself

---

### Screenshot 2: Timeline Visualization
**Filename**: `02-timeline-view.png`
**Size**: 2880 x 1800

**Description**:
Demonstrates the powerful timeline navigation and conversation history.

**What to Show**:
- Full timeline view with scroll bar visible
- 10-15 conversation entries spanning several hours/days
- Different entry types clearly distinguishable:
  - User messages (blue accent)
  - Assistant responses (purple/gray)
  - Tool calls (orange/yellow)
  - System messages (gray)
- Timestamps on each entry
- Search/filter bar active (if implemented)
- Scroll position indicator

**Visual Elements**:
- Variety in message types and lengths
- Some entries collapsed, some expanded
- Hover state on one entry (if applicable)
- Clear visual hierarchy
- Date separators between conversation groups

**Composition**:
- Full HUD window filling most of the frame
- Timeline should feel "busy" but organized
- Show depth of content available

---

### Screenshot 3: Project Switcher
**Filename**: `03-project-switcher.png`
**Size**: 2880 x 1800

**Description**:
Showcases multi-project organization and easy switching.

**What to Show**:
- Project switcher dropdown/panel open
- 4-6 different projects listed with:
  - Project names (e.g., "contextify", "mobile-app", "api-server")
  - Git repository paths
  - Last activity timestamps ("5 minutes ago", "2 hours ago", "Yesterday")
  - Git branch names
  - Conversation count per project
- Active project highlighted
- Search/filter field in project list (if available)

**Visual Elements**:
- Professional project names (not "test" or "demo")
- Realistic git branches (feature/auth, bugfix/timeline, main, develop)
- Icons or avatars for different projects (if implemented)
- Clean, scannable list design

**Composition**:
- Project switcher should be prominent
- Background HUD slightly dimmed (modal overlay effect)
- Show this is a well-organized workspace

---

### Screenshot 4: AI-Powered Summaries
**Filename**: `04-ai-summaries.png`
**Size**: 2880 x 1800

**Description**:
Highlights the intelligent AI summary generation feature.

**What to Show**:
- Large, readable AI-generated summary
- Summary should be impressive and informative, e.g.:
  ```
  Summary of Conversation (Last 30 minutes)

  • Implemented new timeline caching system using GRDB
  • Fixed race condition in conversation monitor
  • Added support for custom database locations
  • Discussed approach for handling transcript corruption
  • Created 3 new test cases for edge conditions

  Key Decisions:
  - Use actor pattern for thread-safe cache access
  - Store summaries in separate table for performance

  Next Steps:
  - Review PR for timeline cache implementation
  - Test with large transcript files (>10MB)
  ```
- Summary metadata: timestamp, token count, generation time
- "Regenerate" or "Refresh" button visible
- Summary applies to visible conversation section

**Visual Elements**:
- Professional typography for summary text
- Bullet points and formatting preserved
- "AI-generated" indicator or icon
- Subtle background or card design for summary
- Maybe show "thinking" animation captured mid-generation

**Composition**:
- Summary should dominate the frame
- Clear, readable text at 2880x1800
- Professional, polished appearance

---

### Screenshot 5: File Ingestion (Drag & Drop)
**Filename**: `05-file-ingestion.png`
**Size**: 2880 x 1800

**Description**:
Demonstrates the file and URL ingestion capability.

**What to Show**:
- Active drag operation: file being dragged over HUD
- Drop zone highlighted with visual feedback:
  - Dashed border or glow effect
  - "Drop files here" indicator
  - Icon showing acceptable file types
- File being dragged: code file (`.swift`, `.py`, `.tsx`) or document
- Alternatively: Show the result immediately after drop:
  - New artifact created
  - Markdown preview of ingested content
  - Timestamp of ingestion
  - File metadata (name, size, type)

**Visual Elements**:
- Clear visual feedback for drag state
- Professional drag-and-drop UI
- File icon visible in cursor
- Smooth, modern interaction design

**Composition**:
- Capture the moment of interaction
- Show both the file and the HUD
- Dynamic, engaging screenshot

---

### Screenshot 6: Settings & Database Configuration
**Filename**: `06-settings-database.png`
**Size**: 2880 x 1800

**Description**:
Shows advanced configuration options and database management.

**What to Show**:
- Settings panel open with tabs/sections:
  - **Database** (active tab)
    - Current database location shown
    - Options: Default, Custom, Dropbox, iCloud Drive
    - Path selection UI
    - Database size/statistics
  - **Monitoring** tab visible
  - **Appearance** tab visible
  - **Advanced** tab visible
- Professional settings UI with:
  - Clear labels and descriptions
  - Toggle switches for boolean options
  - Dropdown menus for selections
  - Text fields for paths
  - "Save" or "Apply" buttons

**Visual Elements**:
- Clean, macOS-native settings design
- Icons for each tab
- Helpful descriptions under each setting
- Current values clearly shown
- Maybe show a "Changes saved" confirmation

**Composition**:
- Settings window centered or overlaying HUD
- Professional, polished appearance
- Show depth of configuration available

---

### Screenshot 7: Git Integration & Context
**Filename**: `07-git-integration.png`
**Size**: 2880 x 1800

**Description**:
Demonstrates automatic git repository detection and context awareness.

**What to Show**:
- Conversation timeline with git context clearly visible:
  - Repository name in header
  - Current branch name with icon
  - Commit hash (short form, e.g., `a1b2c3d`)
  - Repository path
- Git information integrated into conversation metadata
- Maybe show conversation from two different branches:
  - Split view or before/after
  - Same project, different branches
  - Demonstrates git-aware organization
- Alternatively: Show git branch switching UI

**Visual Elements**:
- Git branch icon (standard git branch symbol)
- Monospace font for commit hash
- Color coding for different branches (optional)
- Clean integration into existing UI (not intrusive)

**Composition**:
- Git information should be prominent but not overwhelming
- Professional developer tool aesthetic
- Show this is a git-aware application

---

## Design Guidelines

### Consistency
- Use the same macOS appearance mode (Light or Dark) across all screenshots
- Maintain consistent HUD size and positioning style
- Use realistic, professional content (no lorem ipsum or "test" data)

### Content Quality
- Use meaningful project names: "contextify", "auth-service", "mobile-app"
- Realistic conversation content related to actual development tasks
- Professional git branch names: `feature/timeline-cache`, `bugfix/summaries`, `main`
- Actual timestamps that make sense sequentially

### Background Elements
- Keep backgrounds clean but realistic
- Show typical developer tools: VSCode, Xcode, Terminal, browser
- Blur or dim backgrounds to emphasize Contextify HUD
- Avoid cluttered desktops or distracting elements

### Text Readability
- All text must be readable at full 2880x1800 resolution
- Avoid text smaller than 12pt when viewed at actual size
- Use high contrast for important information
- Test readability by viewing at 50% size

### Professional Polish
- No debug information or error states
- No placeholder content or "TODO" items
- Clean, finished UI in all screenshots
- Avoid showing incomplete features

## Screenshot Order & Storytelling

The screenshots should tell a story:

1. **Introduction** (Hero): "This is Contextify - a beautiful HUD for your AI conversations"
2. **Core Feature** (Timeline): "See your entire conversation history organized"
3. **Organization** (Projects): "Manage multiple projects effortlessly"
4. **Intelligence** (AI Summaries): "Get AI-powered insights automatically"
5. **Interaction** (Drag & Drop): "Easy file ingestion with drag & drop"
6. **Customization** (Settings): "Configure database location and preferences"
7. **Integration** (Git): "Automatic git context awareness"

## File Organization

```
appstore-metadata/screenshots/
├── SCREENSHOT-SPECIFICATIONS.md (this file)
├── 01-main-hud.png
├── 02-timeline-view.png
├── 03-project-switcher.png
├── 04-ai-summaries.png
├── 05-file-ingestion.png
├── 06-settings-database.png
├── 07-git-integration.png
├── alternates/
│   ├── 01-main-hud-dark.png (dark mode variant)
│   ├── 01-main-hud-light.png (light mode variant)
│   └── ... (other variations for A/B testing)
└── working/
    └── (raw captures before editing)
```

## Pre-Submission Checklist

Before uploading screenshots to App Store Connect:

- [ ] All screenshots are exactly 2880 x 1800 pixels
- [ ] File sizes are under 10 MB each
- [ ] All screenshots use PNG format
- [ ] sRGB color space is used
- [ ] Text is crisp and readable at full resolution
- [ ] Consistent appearance mode (Light or Dark) across all screenshots
- [ ] No debug information or error states visible
- [ ] Professional, realistic content throughout
- [ ] Screenshots tell a coherent story in sequence
- [ ] All UI elements are properly rendered (no clipping or artifacts)
- [ ] Backgrounds are appropriate and not distracting
- [ ] File names match the specification (01-main-hud.png, etc.)

## Tools & Resources

**Screenshot Capture**:
- macOS built-in screenshot tool (⌘⇧5)
- CleanShot X (advanced screenshot tool)
- Xnapper (beautiful app screenshots)

**Image Editing**:
- Pixelmator Pro (Mac-native, excellent for screenshots)
- Adobe Photoshop
- Sketch (for mockups and annotations)
- Figma (for design and composition)

**Resizing/Optimization**:
- ImageOptim (lossless compression)
- Retrobatch (batch processing)
- sips (command-line tool: `sips -z 1800 2880 input.png --out output.png`)

**Screenshot Testing**:
- View at 50% zoom to simulate App Store preview size
- Test on actual App Store Connect upload to verify rendering
- Review on different displays (Retina vs. non-Retina)

## Notes

- The first screenshot is the most important - it's what users see first
- Screenshots are displayed in order on the App Store
- Users can swipe through screenshots on the App Store page
- Consider creating dark mode variants for A/B testing
- Update screenshots with each major feature release
- Monitor competitor screenshots for inspiration and differentiation
