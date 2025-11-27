# Contextify Demo Video Script

**Version:** 1.0.0
**Created:** November 27, 2025
**Purpose:** App Store Review - Guideline 2.1 Compliance

---

## Apple's Requirements

From rejection feedback (Submission ID: 4a125b1d-7e23-4cb4-be80-09aaa29168cf):

> The demo video should:
> - Show your app running on a physical device, not on a simulator
> - Clearly documents all relevant app features, services, and user permission requests

---

## Recording Setup

**Environment:**
- Physical Mac (not simulator)
- Screen resolution: 1920x1080 or native
- Clean desktop background
- Sample data installed at `~/.claude/projects/`

**Before recording:**
```bash
# Clean database for fresh start
./scripts/db_manager.sh clean --force

# Build app
bash scripts/xc.sh build
```

**Tools:**
- QuickTime Player (built-in) or ScreenFlow
- Optional: Cursor highlighter for visibility

---

## Video Script

**Target duration:** 2-3 minutes
**Format:** MP4 or MOV (H.264)

---

### Scene 1: App Launch (0:00 - 0:15)

**Action:** Launch Contextify from Applications or Dock

**What to show:**
- [ ] App icon visible in Applications folder or Dock
- [ ] Click to launch
- [ ] HUD window appears on screen

**Notes:** Pause briefly to show the app icon clearly before clicking.

---

### Scene 2: Permission Request (0:15 - 0:30)

**Action:** Grant transcript access permission

**What to show:**
- [ ] Permission dialog appears requesting access to `~/.claude/`
- [ ] Read the dialog text (pause so viewer can see it)
- [ ] Click "Allow" button
- [ ] Dialog dismisses

**Notes:** This is critical for Apple - they specifically asked to see permission requests.

---

### Scene 3: Project Detection (0:30 - 0:50)

**Action:** Show projects auto-detected

**What to show:**
- [ ] Project tabs appearing in the tab bar
- [ ] Multiple projects visible (taskflow, weatherly, recipebox from sample data)
- [ ] Brief pause on each project name

**Notes:** Demonstrates that the app found the sample Claude Code transcript files.

---

### Scene 4: Timeline View (0:50 - 1:20)

**Action:** Browse conversation timeline

**What to show:**
- [ ] Click on a project tab (e.g., "taskflow")
- [ ] Timeline loads with conversation entries
- [ ] Timestamps visible on entries
- [ ] User messages and assistant responses displayed
- [ ] Scroll through timeline to show depth of content
- [ ] Click on an entry to expand/view details

**Notes:** Core feature - show there's real content from the transcripts.

---

### Scene 5: LLM Summaries (1:20 - 1:45)

**Action:** Show AI-generated summaries

**What to show:**
- [ ] Summary badges/indicators next to conversations
- [ ] Hover or click to expand a summary
- [ ] Show the summary text (AI-generated description of conversation)
- [ ] If summaries are still generating, briefly show loading state then completed

**Notes:** This is the "summarize feature" Apple specifically asked about.

---

### Scene 6: Quick Search (1:45 - 2:05)

**Action:** Use Quick Search (Cmd+F)

**What to show:**
- [ ] Press Cmd+F (show keyboard if possible, or just the result)
- [ ] Search field appears
- [ ] Type a query (e.g., "authentication" or "API" or "error")
- [ ] Results filter in real-time as you type
- [ ] Click a result to navigate to that conversation

**Notes:** Show the search actually filtering results.

---

### Scene 7: Deep Search (2:05 - 2:20)

**Action:** Use Deep Search (Cmd+Shift+F)

**What to show:**
- [ ] Press Cmd+Shift+F
- [ ] Deep Search window/panel opens
- [ ] Type a query
- [ ] Results appear showing matches across all projects
- [ ] Click a result to jump to that location

**Notes:** Demonstrates cross-project search capability.

---

### Scene 8: Project Switching (2:20 - 2:35)

**Action:** Switch between projects

**What to show:**
- [ ] Click different project tabs
- [ ] Timeline changes to show different project's conversations
- [ ] Each project has distinct content
- [ ] Smooth transitions between projects

**Notes:** Shows multi-project support.

---

### Scene 9: Settings (2:35 - 2:50)

**Action:** Open Settings panel

**What to show:**
- [ ] Open Settings (gear icon or Cmd+,)
- [ ] Settings panel appears
- [ ] Database location options visible
- [ ] Other preferences (if any)
- [ ] Close Settings

**Notes:** Shows app is configurable.

---

### Scene 10: File Ingestion (Optional) (2:50 - 3:00)

**Action:** Drag and drop a file

**What to show:**
- [ ] Find a file on desktop or Finder
- [ ] Drag file toward the HUD window
- [ ] Drop target highlights when file is over window
- [ ] Drop the file
- [ ] Confirmation that file was ingested

**Notes:** Optional but demonstrates additional functionality.

---

### End (3:00)

**Action:** Return to timeline view

**What to show:**
- [ ] Timeline visible with conversations
- [ ] App in normal state
- [ ] End recording

---

## Post-Recording

**File naming:** `demo-video.mp4` or `demo-video.mov`

**Upload location:** `website/review/demo-video.mp4`

**Deploy:**
```bash
./scripts/deploy-website.sh
```

**Final URL:** `https://contextify.sh/review-4a125b1d/demo-video.mp4`

---

## Checklist Summary

Apple's requirements addressed:

- [ ] Physical Mac device (not simulator)
- [ ] Permission requests shown (Scene 2)
- [ ] All app features demonstrated:
  - [ ] Project detection (Scene 3)
  - [ ] Timeline view (Scene 4)
  - [ ] LLM summaries (Scene 5) - specifically requested
  - [ ] Quick Search (Scene 6)
  - [ ] Deep Search (Scene 7)
  - [ ] Project switching (Scene 8)
  - [ ] Settings (Scene 9)
  - [ ] File ingestion (Scene 10)

---

## Tips

1. **Pace:** Move deliberately, pause on important features
2. **Cursor:** Keep mouse movements smooth and intentional
3. **Clean state:** Fresh database shows discovery process
4. **No audio required:** Apple accepts silent demos
5. **Resolution:** Match your display, 1080p minimum
6. **Length:** 2-3 minutes is ideal, don't rush

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-11-27 | Initial script for v1.0 submission |
