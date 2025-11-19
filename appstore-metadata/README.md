# Contextify App Store Metadata

This directory contains all metadata, specifications, and assets required for submitting Contextify to the macOS App Store.

## Directory Structure

```
appstore-metadata/
├── README.md                          # This file
├── metadata.json                      # Complete metadata in structured JSON format
├── fastlane/                          # Fastlane deliver automation
│   └── metadata/
│       ├── copyright.txt              # Copyright information
│       ├── primary_category.txt       # DEVELOPER_TOOLS
│       ├── secondary_category.txt     # PRODUCTIVITY
│       ├── en-US/                     # English (US) localization
│       │   ├── name.txt               # App name (30 char max)
│       │   ├── subtitle.txt           # Subtitle (30 char max)
│       │   ├── promotional_text.txt   # Promotional text (170 char max)
│       │   ├── description.txt        # Full app description (4000 char max)
│       │   ├── keywords.txt           # Keywords (100 char max)
│       │   ├── release_notes.txt      # What's new in this version
│       │   ├── support_url.txt        # Support website URL
│       │   ├── marketing_url.txt      # Marketing website URL
│       │   └── privacy_url.txt        # Privacy policy URL
│       └── review_information/
│           ├── first_name.txt         # [REQUIRED - Update before submission]
│           ├── last_name.txt          # [REQUIRED - Update before submission]
│           ├── phone_number.txt       # [REQUIRED - Update before submission]
│           ├── email_address.txt      # [REQUIRED - Update before submission]
│           └── notes.txt              # App review notes for Apple
├── screenshots/                       # App Store screenshots
│   ├── SCREENSHOT-SPECIFICATIONS.md   # Detailed screenshot specifications
│   ├── 01-main-hud.png               # [TO BE CREATED] Hero shot
│   ├── 02-timeline-view.png          # [TO BE CREATED] Timeline demonstration
│   ├── 03-project-switcher.png       # [TO BE CREATED] Project management
│   ├── 04-ai-summaries.png           # [TO BE CREATED] AI summary feature
│   ├── 05-file-ingestion.png         # [TO BE CREATED] Drag & drop
│   ├── 06-settings-database.png      # [TO BE CREATED] Settings panel
│   ├── 07-git-integration.png        # [TO BE CREATED] Git context
│   ├── alternates/                   # Alternative versions for A/B testing
│   └── working/                      # Working files and raw captures
└── app-previews/                     # App Store preview videos
    ├── APP-PREVIEW-SPECIFICATIONS.md # Detailed video specifications
    ├── preview-01-overview.mov       # [TO BE CREATED] Product overview (30s)
    ├── preview-02-features.mov       # [TO BE CREATED] Feature showcase (25s)
    ├── scripts/                      # Video scripts and storyboards
    ├── storyboards/                  # Visual storyboards
    ├── audio/                        # Background music and audio assets
    ├── alternates/                   # Alternative cuts
    └── working/                      # Working files and project files
```

## Quick Start

### 1. Review the Metadata

The complete metadata is available in two formats:

- **JSON Format**: `metadata.json` - Comprehensive structured data including all fields
- **Fastlane Format**: `fastlane/metadata/` - Individual `.txt` files for use with fastlane deliver

### 2. Update Required Fields

Before submission, you MUST update these files in `fastlane/metadata/review_information/`:

- `first_name.txt` - Your first name for App Review contact
- `last_name.txt` - Your last name for App Review contact
- `phone_number.txt` - Phone number for App Review contact
- `email_address.txt` - Email address for App Review contact

Also verify these URLs are live:
- Support URL: https://contextify.sh/support.html
- Marketing URL: https://contextify.sh
- Privacy Policy URL: https://contextify.sh/privacy.html

### 3. Create Screenshots

Follow the detailed guide in `screenshots/SCREENSHOT-SPECIFICATIONS.md`:

**Requirements**:
- Size: 2880 x 1800 pixels (primary), or 1280x800, 1440x900, 2560x1600
- Format: PNG (preferred) or JPEG
- Quantity: 5-7 screenshots recommended (1 minimum, 10 maximum)

**Screenshot List**:
1. `01-main-hud.png` - Hero shot showing main HUD with active timeline
2. `02-timeline-view.png` - Full timeline visualization
3. `03-project-switcher.png` - Project management and switching
4. `04-ai-summaries.png` - AI-powered conversation summaries
5. `05-file-ingestion.png` - Drag & drop file ingestion
6. `06-settings-database.png` - Settings and database configuration
7. `07-git-integration.png` - Git context awareness

### 4. Create App Preview Videos (Recommended)

Follow the detailed guide in `app-previews/APP-PREVIEW-SPECIFICATIONS.md`:

**Requirements**:
- Resolution: 1920 x 1080 pixels (landscape)
- Duration: 15-30 seconds
- Format: MOV, MP4, or M4V (H.264 codec)
- Quantity: 2 videos recommended (3 maximum)

**Video List**:
1. `preview-01-overview.mov` - 30s product overview and value proposition
2. `preview-02-features.mov` - 25s rapid feature showcase

## Using Fastlane Deliver

### Installation

```bash
# Install fastlane (requires Ruby)
sudo gem install fastlane

# Or via Homebrew
brew install fastlane
```

### Download Current Metadata (if app already exists)

```bash
cd appstore-metadata
fastlane deliver download_metadata --platform osx --use_live_version true
```

### Upload Metadata to App Store Connect

```bash
cd appstore-metadata
fastlane deliver --platform osx \
  --metadata_path ./fastlane/metadata \
  --screenshots_path ./screenshots \
  --skip_binary_upload \
  --force
```

### Upload Screenshots Only

```bash
fastlane deliver --platform osx \
  --screenshots_path ./screenshots \
  --skip_metadata \
  --skip_binary_upload \
  --force
```

## Metadata Details

### App Information

- **Name**: Contextify (30 characters max)
- **Subtitle**: AI Session Manager for Developers (30 characters max)
- **Bundle ID**: dev.contextify.Contextify
- **Primary Category**: Developer Tools
- **Secondary Category**: Productivity
- **Minimum OS**: macOS 14.0
- **Age Rating**: 4+

### Keywords

**Current Keywords** (100 characters):
```
AI,developer,productivity,Claude,coding,assistant,session,tracking,HUD,developer tools,conversation,timeline,project management,git,transcript,summary,LLM,Swift,macOS,code assistant
```

**Character Count**: 99/100

**Keyword Strategy**:
- Primary: AI, developer, productivity, Claude, coding assistant
- Secondary: session tracking, conversation, timeline, project management
- Technical: LLM, Swift, macOS, git, transcript
- Category: HUD, developer tools

### Description Structure

The description (4000 characters max) is organized as:

1. **Opening Hook** - Value proposition and target audience
2. **Key Features** - Bulleted list with visual emoji markers
3. **Perfect For** - Target user personas
4. **How It Works** - Technical overview and workflow
5. **Privacy & Security** - Data handling and privacy commitment
6. **Technical Details** - Technology stack
7. **System Requirements** - Minimum requirements
8. **Closing** - Tagline and call-to-action

**Current Length**: ~2,100 characters (room for expansion)

### Promotional Text

**Current** (170 characters max):
```
Track your Claude Code sessions with real-time AI summaries. Never lose context across conversations.
```

**Character Count**: 122/170

**Note**: Promotional text can be updated WITHOUT submitting a new app version - perfect for announcements, limited-time features, or seasonal messaging.

## App Store Optimization (ASO) Strategy

### App Name + Subtitle Strategy

- **App Name**: "Contextify" (11 characters)
  - Short, memorable, brandable
  - Contains "Context" - relevant keyword

- **Subtitle**: "AI Session Manager for Developers" (34 characters)
  - Front-loads "AI" - high-value keyword
  - Includes "Developers" - target audience
  - Descriptive and clear

**Combined**: 45 characters of 60 available (good use of space)

### Keyword Optimization

**High-Priority Keywords**:
- AI (very high search volume)
- developer (high search volume, highly relevant)
- productivity (high search volume)
- Claude (branded, specific audience)
- coding assistant (compound keyword, high intent)

**Long-Tail Keywords**:
- session tracking
- conversation timeline
- project management
- developer tools

**Competitors to Monitor**:
- Cursor
- GitHub Copilot
- Tabnine
- Raycast
- Alfred
- Other developer productivity tools

### Description Best Practices

✅ **Currently Implemented**:
- Front-loads key value proposition
- Uses visual markers (emoji bullets) for scannability
- Clear feature hierarchy
- Addresses privacy concerns explicitly
- Includes technical details for credibility

🎯 **Future Optimization**:
- Add social proof when available (user count, ratings)
- Include testimonials or reviews (once received)
- Add comparison to alternatives (if beneficial)
- Update with new features regularly

## Privacy & Data Collection

**Privacy Policy**: Contextify collects NO user data.

All data is stored locally on the user's Mac:
- Conversation transcripts are read from Claude Code/Codex directories
- SQLite database stored locally (default or custom location)
- No network requests to external servers
- No analytics or tracking
- No user accounts or authentication

**App Privacy Questions** (for App Store Connect):
- Do you collect data from this app? **NO**
- Data types collected: **NONE**
- Is data linked to user identity? **NO**
- Is data used to track users? **NO**

This is a strong privacy position and should be highlighted in marketing.

## Submission Checklist

### Before First Submission

- [ ] Update review contact information (first name, last name, phone, email)
- [ ] Verify all URLs are live (support, marketing, privacy)
- [ ] Create all 7 screenshots at 2880x1800 (minimum 1, recommended 5-7)
- [ ] Create at least 1 app preview video (2 recommended)
- [ ] Review keywords for optimization (update quarterly)
- [ ] Test app on macOS 14.0+ (minimum supported version)
- [ ] Verify app icon is 1024x1024 PNG without transparency
- [ ] Ensure copyright year is current (2025)
- [ ] Prepare demo environment for App Review if needed
- [ ] Review App Store Review Guidelines compliance
- [ ] Complete App Privacy questions in App Store Connect

### For Each Update

- [ ] Update `release_notes.txt` with new version changes
- [ ] Consider updating `promotional_text.txt` for announcements
- [ ] Update screenshots if UI has changed significantly
- [ ] Update app preview videos if major features added
- [ ] Review and refresh keywords (every 4 weeks recommended)
- [ ] Check competitor listings for new trends
- [ ] Update copyright year if needed
- [ ] Test on latest macOS version

### Ongoing Optimization

- [ ] Monitor keyword rankings (use ASO tools)
- [ ] Track conversion rate (impressions → downloads)
- [ ] A/B test screenshot order based on analytics
- [ ] Gather and respond to user reviews
- [ ] Update metadata based on user feedback
- [ ] Analyze competitors' strategies
- [ ] Consider seasonal promotional text updates

## ASO Tips & Best Practices

### Keyword Strategy

1. **Use all 100 characters** - Currently at 99/100 ✓
2. **No spaces after commas** - Maximizes character usage ✓
3. **Avoid duplicating words** from app name/subtitle - Already indexed
4. **Research competitor keywords** - Use tools like AppRadar, Sensor Tower
5. **Update every 4 weeks** - Monitor performance and adjust
6. **Mix high-volume and long-tail** keywords - Balanced approach ✓

### Description Optimization

1. **Front-load key information** - First 170 characters visible before "more" ✓
2. **Use formatting** for scannability - Bullets, sections, emojis ✓
3. **Include social proof** - Add when available (user count, ratings)
4. **Clear call-to-action** - Tells user what to do next ✓
5. **Update regularly** - Keep fresh with new features

### Screenshot Strategy

1. **First screenshot is critical** - Hero shot that captures attention
2. **Tell a story in sequence** - Logical flow through features
3. **Show, don't tell** - Minimize text overlays
4. **Professional quality** - High-resolution, polished
5. **Update with major releases** - Keep current with UI changes

### App Preview Strategy

1. **Auto-plays muted** - Must be engaging without sound
2. **First 3 seconds crucial** - Hook attention immediately
3. **Show real features** - No simulations or mockups
4. **Smooth, professional** - High production quality
5. **Update periodically** - Refresh when features change

## Tools & Resources

### ASO Tools

- **App Radar** - Keyword research and tracking
- **Sensor Tower** - Competitive intelligence
- **App Annie** - Market analytics
- **App Store Connect Analytics** - Official Apple metrics

### Screenshot Tools

- **Xnapper** - Beautiful app screenshots
- **CleanShot X** - Advanced screenshot tool
- **Pixelmator Pro** - Image editing (Mac-native)
- **Sketch/Figma** - Design and mockups

### Video Tools

- **ScreenFlow** - Professional screen recording and editing
- **Final Cut Pro** - Professional video editing
- **QuickTime Player** - Built-in Mac screen recording
- **DaVinci Resolve** - Free professional editing

### Fastlane Resources

- **Official Docs**: https://docs.fastlane.tools
- **deliver action**: https://docs.fastlane.tools/actions/deliver/
- **App Store Connect API**: https://docs.fastlane.tools/app-store-connect-api/

## Localization Plan

### Current Languages
- English (US) - `en-US` ✓

### Planned Languages (Priority Order)
1. **German** - `de-DE` (Strong developer market)
2. **French** - `fr-FR` (EU market)
3. **Japanese** - `ja-JP` (Strong tech adoption)
4. **Spanish** - `es-ES` (Growing market)

### Localization Process (Future)

1. Create language folder: `fastlane/metadata/de-DE/`
2. Translate all `.txt` files
3. Localize screenshots (UI text)
4. Consider localized app preview videos
5. Test with native speakers
6. Submit updated metadata

## Support & Maintenance

### Metadata Updates

**Frequency**:
- Keywords: Every 4 weeks
- Promotional text: As needed (no submission required)
- Description: With major features or quarterly
- Screenshots: With significant UI changes
- Videos: With major version updates (1.0 → 2.0)

### Version Management

Track metadata changes in git:
```bash
git log -- appstore-metadata/
```

Create branches for major metadata refreshes:
```bash
git checkout -b metadata/v1.1-update
# Make changes
git commit -m "feat(metadata): update screenshots for v1.1 release"
```

### Analytics Monitoring

Key metrics to track (in App Store Connect):
- **Impressions** - How many users see the listing
- **Product Page Views** - How many view full listing
- **App Units** - Downloads
- **Conversion Rate** - Views → Downloads
- **Proceeds** - Revenue (if applicable)

## Getting Help

### App Store Connect
- https://developer.apple.com/app-store-connect/

### App Review Guidelines
- https://developer.apple.com/app-store/review/guidelines/

### Fastlane Documentation
- https://docs.fastlane.tools

### Contextify Project
- Website: https://contextify.sh
- Repository: (internal)
- Contact: (see review_information/)

## Notes

- All metadata in this directory is version-controlled
- Update metadata with each significant release
- Keep screenshots and videos current with app UI
- Monitor competitors for ASO insights
- Respond to user reviews promptly
- Keep privacy policy up-to-date

---

**Last Updated**: 2025-01-15
**App Version**: 1.0.0
**Metadata Version**: 1.0
**Platform**: macOS App Store
