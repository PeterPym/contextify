# Contextify Distribution Strategy

## Distribution Channels

### 1. Direct Download (Primary)
**URL:** https://github.com/banagale/contextify/releases

**Packaging:**
- Standard macOS `.app` bundle
- Notarized for Gatekeeper (requires Apple Developer account)
- DMG installer with drag-to-Applications
- Includes embedded CLI tool

**Advantages:**
- No App Store review delays
- Can update quickly
- Full system capabilities
- No 30% revenue share (if future paid version)
- Direct user relationship

**Requirements:**
- Apple Developer account ($99/year) for notarization
- Code signing certificate
- Automated release workflow (GitHub Actions)

**Installation:**
1. Download `Contextify-1.0.dmg`
2. Open DMG, drag Contextify.app to Applications
3. First launch: "Install CLI Tool" menu → sets up `contextify` command

### 2. Mac App Store (Secondary)
**Bundle ID:** `com.contextify.Contextify`

**Packaging:**
- Sandboxed build (stricter entitlements)
- No manual notarization needed (App Store handles it)
- Automatic updates via App Store
- Includes embedded CLI tool (PATH-based installation)

**Advantages:**
- Discoverability (users browse App Store)
- Built-in update mechanism
- Trust signal (App Store badge)
- No hosting costs

**Disadvantages:**
- Review process (1-3 days per update)
- Sandbox restrictions (but our features work within sandbox)
- 30% revenue share (if paid)
- Less control over distribution

**Requirements:**
- Apple Developer account ($99/year)
- App Store compliance:
  - Privacy policy
  - App description and screenshots
  - Age rating (4+)
  - Categories: Developer Tools, Productivity

**Sandbox Considerations:**
- ✅ Read Claude Code transcripts: `~/.claude/` (user-selected file access)
- ✅ Read Codex transcripts: `~/.codex/` (user-selected file access)
- ✅ Write converted files (save panel)
- ✅ SQLite database in app support directory
- ✅ CLI tool in app support directory (no /usr/local/bin needed)
- ✅ File system watchers (within entitled directories)

**CLI Installation (App Store version):**
1. App copies binary to `~/Library/Application Support/Contextify/bin/contextify`
2. Setup assistant shows: "Add to your shell config:"
   ```bash
   export PATH="$HOME/Library/Application Support/Contextify/bin:$PATH"
   ```
3. "Copy Command" or "Add Automatically" buttons
4. Works identically to direct download (no sudo, no system modification)

### 3. Homebrew (Tertiary)
**Formula:** `homebrew/cask/contextify`

**Packaging:**
- Points to GitHub releases DMG
- Installs to `/Applications/Contextify.app`
- Optional: separate `homebrew/core/contextify-cli` for CLI-only

**Advantages:**
- Popular with developers
- Easy updates: `brew upgrade contextify`
- Familiar workflow for target audience

**Requirements:**
- Stable release cadence
- Maintain Homebrew formula (can be community-maintained)

**Installation:**
```bash
brew install --cask contextify

# Optional: CLI-only
brew install contextify-cli  # If we create separate CLI distribution
```

## Recommended Launch Sequence

### Phase 1: Soft Launch (Week 1)
**Channel:** Direct download only (GitHub Releases)

**Goal:** Validate with early adopters, gather feedback

**Actions:**
1. Create GitHub Release v1.0.0
2. Notarize and upload DMG
3. Post to Show HN
4. Share in relevant communities (r/ClaudeAI, r/MacApps)

**Success Metrics:**
- 50+ downloads
- 5+ GitHub stars
- 2+ feature requests or bug reports
- Zero critical bugs

### Phase 2: Public Launch (Week 2-3)
**Channels:** Direct download + App Store submission

**Goal:** Broader reach, establish presence

**Actions:**
1. Submit to Mac App Store (allow 1-3 days for review)
2. Create Homebrew cask formula
3. Write blog post / tutorial
4. Social media announcements

**Success Metrics:**
- 200+ downloads across channels
- 20+ GitHub stars
- App Store approval
- 10+ reviews/feedback comments

### Phase 3: Growth (Month 2+)
**Channels:** All three + content marketing

**Actions:**
1. SEO-optimized landing page
2. Tutorial videos (YouTube)
3. Integration guides (blog posts)
4. Community engagement (respond to issues, feature requests)
5. Consider ProductHunt launch

## Distribution Artifacts

### For Each Release

**1. GitHub Release**
- `Contextify-1.0.0.dmg` (notarized)
- `Contextify-1.0.0.zip` (for Homebrew)
- Release notes (changelog)
- SHA256 checksums

**2. App Store Build**
- Separate build with sandbox entitlements
- Same version number as GitHub release
- App Store Connect upload

**3. Documentation**
- README.md updates
- Installation guide
- CLI usage guide
- Changelog

## Technical Requirements

### Code Signing & Notarization

**Direct Download:**
```bash
# Sign the app
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name" \
  --options runtime \
  Contextify.app

# Create DMG
hdiutil create -volname Contextify -srcfolder Contextify.app -ov Contextify.dmg

# Notarize
xcrun notarytool submit Contextify.dmg \
  --apple-id your@email.com \
  --team-id TEAMID \
  --password app-specific-password \
  --wait

# Staple notarization ticket
xcrun stapler staple Contextify.dmg
```

**App Store:**
```bash
# Archive for App Store
xcodebuild archive \
  -project Contextify.xcodeproj \
  -scheme Contextify \
  -archivePath Contextify.xcarchive

# Export for App Store
xcodebuild -exportArchive \
  -archivePath Contextify.xcarchive \
  -exportPath . \
  -exportOptionsPlist ExportOptions.plist

# Upload to App Store Connect
xcrun altool --upload-app \
  --file Contextify.ipa \
  --type ios \
  --apiKey KEY_ID \
  --apiIssuer ISSUER_ID
```

### Automated Release Workflow

**GitHub Actions** (`.github/workflows/release.yml`):
```yaml
name: Release
on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v3
      - name: Build and sign
        run: ./scripts/release/build-release.sh
      - name: Notarize
        run: ./scripts/notarize.sh
      - name: Create Release
        uses: actions/create-release@v1
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
          draft: false
```

## Pricing Strategy (Future)

**Initial:** Free (focus on adoption and feedback)

**Future Options:**
1. **Freemium:** Free basic conversion, paid for advanced features
   - Free: Basic message conversion
   - Paid: Tool call preservation, batch conversion, cloud sync

2. **One-time Purchase:** $19.99
   - Simple, fair pricing for developer tool
   - Lower barrier than subscription

3. **Donation/Sponsorship:** GitHub Sponsors
   - Keep free, ask for support
   - Good for open-source community

**Recommendation:** Launch free, consider pricing after reaching 500+ active users

## Update Strategy

### Direct Download
- GitHub Releases for updates
- In-app update check (query GitHub API)
- Optional: Sparkle framework for auto-updates

### App Store
- Automatic updates via App Store
- No in-app update mechanism needed

### Homebrew
- Update formula on new releases
- Users update via `brew upgrade`

## Support & Community

**Primary:**
- GitHub Issues (bug reports, feature requests)
- GitHub Discussions (questions, showcase)

**Secondary:**
- Email: support@contextify.dev (if we set up domain)
- Twitter/X: @contextify (if we create account)

**Documentation:**
- GitHub Wiki or docs site
- In-app help menu → opens web docs

## Legal Requirements

### Privacy Policy
Required for App Store, good practice for all channels.

**Key Points:**
- Local-only data storage (no cloud, no analytics)
- Transcript files never leave user's machine
- No personal data collection
- On-device LLM processing (macOS 26+)

### Terms of Service
Optional for free app, but recommended.

**Key Points:**
- Provided "as-is" without warranty
- Not responsible for data loss
- Open source license (MIT/Apache 2.0)

### App Store Metadata
- App name: Contextify
- Subtitle: AI Conversation Timeline & Cross-CLI Converter
- Description: 4000 character limit (write compelling copy)
- Keywords: developer tools, AI, Claude, Codex, conversation, transcript
- Screenshots: 3-5 screenshots showing key features
- Preview video: Optional but recommended (30 seconds)

## Distribution Checklist

**Before Launch:**
- [ ] Apple Developer account active ($99/year)
- [ ] Code signing certificate generated
- [ ] App notarized and tested on clean machine
- [ ] README with installation instructions
- [ ] Privacy policy written and published
- [ ] App Store listing prepared (if using App Store)
- [ ] Release notes / changelog prepared
- [ ] Demo video or screenshots ready
- [ ] Show HN post drafted

**First Release (v1.0.0):**
- [ ] Create GitHub Release with DMG
- [ ] Post to Show HN
- [ ] Submit to App Store (if ready)
- [ ] Create Homebrew formula (or wait for community)
- [ ] Announce in relevant communities

**Ongoing:**
- [ ] Monitor GitHub Issues
- [ ] Respond to feedback within 24-48 hours
- [ ] Release updates regularly (monthly cadence)
- [ ] Keep App Store and GitHub Release in sync

## Success Metrics

**Week 1:**
- 50+ downloads
- 5+ GitHub stars
- 2+ user testimonials

**Month 1:**
- 200+ downloads
- 20+ GitHub stars
- App Store approval
- 10+ community discussions

**Month 3:**
- 500+ downloads
- 50+ GitHub stars
- Featured on Product Hunt or similar
- 3+ blog posts/tutorials from community

**Month 6:**
- 1000+ downloads
- 100+ GitHub stars
- Active contributor community
- Decide on pricing model (if going paid)

---

## Key Takeaway

**Start with direct download (GitHub Releases) for speed and flexibility. Add App Store and Homebrew as adoption grows. Both distribution channels use the same PATH-based CLI installation, ensuring consistent experience regardless of how users install Contextify.**
