# App Preview Video Specifications for Contextify

## Technical Requirements

- **Platform**: macOS
- **Resolution**: 1920 x 1080 pixels (16:9 aspect ratio)
- **Orientation**: Landscape only (required for macOS)
- **Format**: MOV, MP4, or M4V
- **Video Codec**: H.264 or ProRes 422 (HQ only)
- **Audio Codec**: AAC
- **Duration**: 15-30 seconds (recommended: 25-30s to maximize storytelling)
- **Max File Size**: 500 MB per video
- **Frame Rate**: 30 fps (preferred) or 60 fps
- **Quantity**: Maximum 3 videos (recommended: 2)

## Content Requirements (Apple Guidelines)

**MUST**:
- Contain ONLY screen captures recorded from the actual app
- Show real app functionality and features
- Use actual app footage (no simulations or mockups)
- Be captured on the device/platform (macOS)

**MUST NOT**:
- Include hands, cursors, or people operating the device (unless cursor is essential for demonstration)
- Show simulated device frames or 3D renders
- Include live-action footage or promotional content
- Use copyrighted material not part of the app
- Add marketing text overlays (subtle labels/callouts OK)
- Show other apps prominently (brief Terminal/CLI appearance is acceptable)

## Video Capture Method

### Recording Tools

**Recommended**:
1. **QuickTime Player** (Built-in, free)
   - File > New Screen Recording
   - Select area or full screen
   - Records at native resolution
   - Export as MOV with H.264

2. **ScreenFlow** (Professional, paid)
   - Multi-track editing
   - Built-in effects and transitions
   - Excellent for polished videos
   - Direct export to App Store specs

3. **OBS Studio** (Free, open-source)
   - Powerful recording options
   - Good for complex setups
   - Requires more configuration

4. **Camtasia** (Professional, paid)
   - Easy editing interface
   - Built-in annotations
   - Good for tutorial-style videos

### Capture Settings

- **Resolution**: Record at 1920x1080 or higher (will be scaled to 1920x1080)
- **Frame Rate**: 30 fps minimum (60 fps for smoother animations)
- **Bitrate**: High quality (10-20 Mbps for H.264)
- **Audio**: Optional, but if used, must be high quality
  - 48 kHz sample rate
  - 256 kbps bitrate minimum
  - AAC codec

## Video Specifications

### Video 1: Product Overview (30 seconds)
**Filename**: `preview-01-overview.mov`
**Duration**: 30 seconds

**Purpose**: Introduce Contextify and demonstrate core value proposition

**Script/Storyboard**:

**0:00-0:03** - Opening (3s)
- Fade in from black to Contextify logo
- Minimal animation (subtle glow or fade)
- Optional: Tagline text appears: "Stay in Context"

**0:03-0:08** - Problem Setup (5s)
- Desktop view showing Terminal
- Developer types `claude` command and starts session
- Brief Claude Code interaction (1-2 exchanges)
- Implication: "You have conversations, but no organization"

**0:08-0:13** - Solution Introduction (5s)
- Contextify HUD appears (smooth fade-in or slide-in animation)
- HUD automatically detects the active Claude Code session
- Project name appears in header
- Show "Session detected" or similar confirmation

**0:13-0:20** - Core Features Demonstration (7s)
- Timeline starts populating with entries (real-time feel)
- Entries appear one by one (2-3 entries)
- Show variety: user message, assistant response, tool call
- AI summary generates (show progress indicator, then result)
- Timestamps update to "Just now"

**0:20-0:25** - Multi-Project Value (5s)
- Quick transition: Project switcher opens
- Show 3-4 projects listed
- User selects different project
- Timeline instantly switches to that project's conversations
- Demonstrates organization capability

**0:25-0:30** - Closing (5s)
- Return to hero view of HUD with active timeline
- Text overlay appears: "Contextify"
- Subtitle: "AI Session Manager for Developers"
- Optional: "Available on the Mac App Store"
- Fade to black or end on logo

**Visual Style**:
- Clean, professional
- Smooth transitions (1-2 second crossfades or quick cuts)
- No jarring movements
- Consistent color scheme matching app branding
- Minimal text overlays (only essential information)

**Audio** (Optional but recommended):
- Subtle background music (tech/productivity vibe)
- No voiceover needed
- UI sound effects from app (optional, keep subtle)
- Music should be royalty-free or licensed
- Fade in at start, fade out at end

---

### Video 2: Feature Showcase (25 seconds)
**Filename**: `preview-02-features.mov`
**Duration**: 25 seconds

**Purpose**: Demonstrate key features in rapid succession

**Script/Storyboard**:

**0:00-0:02** - Opening (2s)
- Contextify logo or app icon
- Text: "Key Features"

**0:02-0:05** - Feature 1: Drag & Drop Ingestion (3s)
- Show file being dragged over HUD
- Drop zone highlights
- File drops, artifact immediately created
- Text overlay: "Drag & Drop Files"

**0:05-0:09** - Feature 2: Timeline Navigation (4s)
- Scroll through long conversation history
- Show search/filter in action (if implemented)
- Jump to specific timestamp
- Text overlay: "Timeline Navigation"

**0:09-0:12** - Feature 3: Checkpoints (3s)
- User creates checkpoint (button click or keyboard shortcut)
- Checkpoint appears in timeline with marker
- Checkpoint name/description visible
- Text overlay: "Session Checkpoints"

**0:12-0:17** - Feature 4: AI Summaries (5s)
- Show summary generation process
- Progress indicator or "thinking" animation
- Summary appears with formatted text
- Highlight key information in summary
- Text overlay: "AI-Powered Summaries"

**0:17-0:20** - Feature 5: Git Integration (3s)
- Show git branch indicator
- Switch to different branch view
- Timeline updates with branch-specific conversations
- Text overlay: "Git-Aware Organization"

**0:20-0:23** - Feature 6: Custom Database (3s)
- Settings panel showing database location options
- Dropbox and iCloud Drive icons visible
- User selects custom location
- Text overlay: "Flexible Storage"

**0:23-0:25** - Closing (2s)
- Contextify logo
- Text: "contextify.sh"
- Fade out

**Visual Style**:
- Fast-paced, energetic
- Quick cuts between features (1-2 second per feature)
- Text overlays for each feature name
- Consistent label positioning (lower third)
- Modern, dynamic feel

**Audio** (Optional):
- Upbeat background music
- Faster tempo than overview video
- Match cuts to music beats for polish
- No voiceover

---

### Video 3: Use Case Story (Optional, if 3 videos desired)
**Filename**: `preview-03-workflow.mov`
**Duration**: 28 seconds

**Purpose**: Show real-world developer workflow with Contextify

**Script/Storyboard**:

**0:00-0:05** - Morning: Start New Feature (5s)
- Developer opens Terminal, starts Claude Code session
- Working on "feature/user-auth" branch
- Contextify detects session, shows project context
- Timeline begins tracking conversation

**0:05-0:12** - Midday: Review Progress (7s)
- Developer opens Contextify to review morning's work
- Scrolls through timeline of earlier conversation
- Reads AI summary: "Implemented JWT authentication..."
- Creates checkpoint: "Auth flow complete"

**0:12-0:18** - Afternoon: Context Switch (6s)
- Notification or need to switch to different project
- Opens project switcher in Contextify
- Switches to "bugfix/api-errors" project
- Timeline instantly shows that project's context
- Continues work without losing context

**0:18-0:25** - End of Day: Knowledge Capture (7s)
- Developer drags documentation file into Contextify
- Artifact created with notes about auth implementation
- Creates final checkpoint: "Day complete"
- Reviews AI summary of entire day's work

**0:25-0:28** - Closing (3s)
- Text: "Your AI Conversations, Organized"
- Contextify logo
- "contextify.sh"

**Visual Style**:
- Story-driven narrative
- Follows a developer through a day
- Realistic workflow demonstration
- Slightly slower pace than feature showcase
- Professional, relatable

---

## Production Guidelines

### Pre-Production

1. **Script & Storyboard**
   - Write detailed script with exact timings
   - Create storyboard with screenshots
   - Plan transitions between scenes
   - Identify which features to highlight

2. **Prepare App & Environment**
   - Create realistic demo data (conversations, projects)
   - Use professional project names and content
   - Clean desktop background
   - Close unnecessary apps/windows
   - Disable notifications
   - Set up proper display resolution

3. **Audio Planning** (if using)
   - Select royalty-free music
   - Ensure proper licensing
   - Plan audio levels
   - Prepare sound effects if needed

### Production (Recording)

1. **Recording Setup**
   - Set display to 1920x1080 or record at higher resolution
   - Launch recording software
   - Do a test recording (5 seconds) to verify quality
   - Check audio levels if recording audio
   - Ensure smooth performance (close heavy apps)

2. **Recording Tips**
   - Record multiple takes of each segment
   - Record segments separately, edit together
   - Move deliberately (not too fast, not too slow)
   - Pause between actions for easier editing
   - Record extra footage for flexibility in editing
   - Use keyboard shortcuts instead of clicking when possible (cleaner)

3. **What to Capture**
   - Clean app interactions
   - Smooth transitions
   - Clear feature demonstrations
   - No errors or glitches
   - Professional content throughout

### Post-Production (Editing)

1. **Editing Software**
   - **Final Cut Pro** (Professional, Mac-native)
   - **Adobe Premiere Pro** (Professional, cross-platform)
   - **DaVinci Resolve** (Professional, free version available)
   - **iMovie** (Simple, free, Mac-only)
   - **ScreenFlow** (Great for screencasts)

2. **Editing Process**
   - Import all footage
   - Arrange clips according to storyboard
   - Trim to exact timings (fit within 30s)
   - Add transitions (subtle, professional)
   - Add text overlays (feature names, labels)
   - Color correction (ensure consistent brightness/contrast)
   - Add audio track (music/sound effects)
   - Balance audio levels

3. **Text Overlays**
   - Use readable fonts (San Francisco, Helvetica, Arial)
   - Size: Large enough to read on mobile devices
   - Position: Lower third (consistent placement)
   - Duration: 2-3 seconds per text element
   - Animation: Subtle fade in/out
   - Color: High contrast with background

4. **Transitions**
   - Crossfade: 0.5-1 second (smooth, professional)
   - Quick cut: 0 seconds (energetic, modern)
   - Avoid fancy transitions (wipes, spins, etc.)
   - Consistency is key

### Export Settings

**Final Cut Pro / Premiere Pro**:
- Format: H.264
- Resolution: 1920 x 1080
- Frame Rate: 30 fps (or match source)
- Bitrate: VBR, 2-pass, 10-15 Mbps
- Audio: AAC, 256 kbps, 48 kHz

**QuickTime Player**:
- File > Export As > 1080p
- Automatically uses H.264 and AAC

**Verify Export**:
- Resolution: 1920 x 1080 ✓
- Duration: 15-30 seconds ✓
- File size: Under 500 MB ✓
- Codec: H.264 ✓
- Audio: AAC (if present) ✓
- Plays smoothly without stuttering ✓

## Quality Checklist

Before submitting app previews to App Store Connect:

### Technical
- [ ] Resolution is exactly 1920 x 1080 pixels
- [ ] Duration is between 15-30 seconds
- [ ] File size is under 500 MB
- [ ] Video codec is H.264 or ProRes 422 HQ
- [ ] Audio codec is AAC (if audio present)
- [ ] Frame rate is consistent (30 or 60 fps)
- [ ] Orientation is landscape

### Content
- [ ] Only shows actual app footage (no simulations)
- [ ] No hands or cursors visible (unless essential)
- [ ] No copyrighted material
- [ ] No excessive marketing text
- [ ] Professional demo data (no "test" or placeholder content)
- [ ] No error states or glitches
- [ ] Clean, distraction-free background

### Production Quality
- [ ] Video plays smoothly without stuttering
- [ ] Audio (if present) is clear and balanced
- [ ] Text overlays are readable
- [ ] Transitions are smooth and professional
- [ ] Color is consistent throughout
- [ ] Brightness/contrast is appropriate
- [ ] No visual artifacts or compression issues

### Storytelling
- [ ] Opens with clear introduction
- [ ] Demonstrates key value proposition
- [ ] Shows features in logical order
- [ ] Ends with clear branding/call-to-action
- [ ] Pacing is appropriate (not too fast, not too slow)
- [ ] Tells a coherent story

## File Organization

```
appstore-metadata/app-previews/
├── APP-PREVIEW-SPECIFICATIONS.md (this file)
├── preview-01-overview.mov
├── preview-02-features.mov
├── preview-03-workflow.mov (optional)
├── scripts/
│   ├── preview-01-script.md
│   ├── preview-02-script.md
│   └── preview-03-script.md
├── storyboards/
│   ├── preview-01-storyboard.pdf
│   └── preview-02-storyboard.pdf
├── audio/
│   ├── background-music-01.mp3
│   ├── background-music-02.mp3
│   └── LICENSE.txt (music licensing info)
├── alternates/
│   └── (alternative cuts for A/B testing)
└── working/
    ├── raw-footage/
    ├── project-files/ (Final Cut Pro, Premiere, etc.)
    └── exports/
```

## Tips for Success

### Do:
- Keep it simple and focused
- Show real features in action
- Use professional demo content
- Test on multiple devices before submission
- Get feedback from others before finalizing
- Update videos with major feature releases

### Don't:
- Rush the production process
- Use low-quality demo data
- Include too many features in one video
- Make videos too short (aim for 25-30s to maximize value)
- Forget to test playback before uploading
- Ignore Apple's content guidelines

### Best Practices:
- Record at higher resolution, downscale to 1080p (better quality)
- Use 60 fps if app has smooth animations
- Keep text on screen for 2-3 seconds minimum
- Use subtle background music to enhance professionalism
- Show the app in context of real developer workflow
- Highlight unique features that differentiate from competitors
- End with clear branding (logo, website, tagline)

## Music Resources (Royalty-Free)

- **Epidemic Sound** (Subscription, commercial license)
- **Artlist** (Subscription, unlimited downloads)
- **AudioJungle** (Pay-per-track)
- **YouTube Audio Library** (Free, attribution may be required)
- **Free Music Archive** (Free, check individual licenses)
- **Incompetech** (Free, attribution required)

**Important**: Always verify licensing allows commercial use in App Store promotional materials.

## Accessibility Considerations

- Ensure text overlays have sufficient contrast
- Keep important action in center of frame
- Avoid rapid flashing or strobing effects
- Consider adding captions (optional but helpful)
- Test readability on smaller screens

## Performance Optimization

If video file size exceeds 500 MB:

1. **Reduce bitrate**: Lower from 15 Mbps to 10 Mbps
2. **Shorten duration**: Trim to 25-27 seconds
3. **Use H.264**: More efficient than ProRes for distribution
4. **2-pass encoding**: Better quality at same file size
5. **Remove audio**: If music isn't essential
6. **Use HandBrake**: Free tool for video compression

## Testing Before Upload

1. **Play on Mac**: Verify smooth playback
2. **Check on iPhone/iPad**: Ensure readability (App Store shows on all devices)
3. **Review on TV**: If you have Apple TV (optional)
4. **Get feedback**: Show to colleagues/friends
5. **Compare to competitors**: See how yours stacks up

## Notes

- App previews auto-play on the App Store (muted by default)
- First 3-5 seconds are crucial for grabbing attention
- Videos should be engaging even without sound
- Consider creating seasonal variations for updates
- Monitor analytics to see which videos perform best
- Update videos when UI changes significantly

## Example Timeline (30-second video)

```
0:00 ████ Logo/Opening (3s)
0:03 ████████ Problem/Context (5s)
0:08 ████████ Solution Intro (5s)
0:13 ████████████████ Core Demo (10s)
0:23 ██████ Additional Features (4s)
0:27 ██████ Closing/CTA (3s)
0:30 END
```

## Approval Tips

- Apple reviews app previews manually
- Common rejection reasons:
  - Contains non-app footage
  - Shows competitors' apps prominently
  - Includes copyrighted material
  - Has excessive marketing text
  - Poor quality or glitchy footage
  - Doesn't accurately represent the app

Avoid these issues by strictly following Apple's guidelines and this specification.

---

**Last Updated**: 2025-01-15
**Specification Version**: 1.0
**Platform**: macOS App Store
