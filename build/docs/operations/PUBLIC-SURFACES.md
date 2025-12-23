# Public Surfaces Inventory

**Purpose:** Canonical inventory of all public-facing surfaces that may need updates with releases.

**Last Updated:** 2025-11-27

---

## Quick Reference

| Surface | URL / Location | Source Files | Update Triggers |
|---------|---------------|--------------|-----------------|
| App Store Listing | [apps.apple.com](https://apps.apple.com/app/contextify/id6753190666) | `appstore-metadata/fastlane/metadata/en-US/` | Major releases, feature changes |
| Website Landing | [contextify.sh](https://contextify.sh) | `website/index.html` | Feature additions, screenshots |
| OG Image | Social share preview | `website/assets/img/og-banner.png` | Messaging changes, branding updates |
| Website Help | [contextify.sh/help](https://contextify.sh/help/) | `website/help/index.html` | Feature changes, workflow updates |
| Website Support | [contextify.sh/support](https://contextify.sh/support.html) | `website/support.html` | Contact info, issue process changes |
| Website Privacy | [contextify.sh/privacy](https://contextify.sh/privacy.html) | `website/privacy.html` | Data handling changes |
| Release Notes | [contextify.sh/release-notes](https://contextify.sh/release-notes/) | `website/release-notes/{version}.html` | Every release |
| Appcast (Sparkle) | [contextify.sh/appcast.xml](https://contextify.sh/appcast.xml) | `website/appcast.xml` | Every DMG release |
| Public Repo | [github.com/PeterPym/contextify](https://github.com/PeterPym/contextify) | `~/code/projects/contextify-public-repo/` | Major releases, docs changes |
| GitHub Releases | [github.com/banagale/contextify/releases](https://github.com/banagale/contextify/releases) | Created via `gh release` | Every DMG release |
| Twitter/X | [x.com/Contextify_sh](https://x.com/Contextify_sh) | - | Launches, updates, engagement |
| Blog | [contextify.sh/blog](https://contextify.sh/blog/) | `website/blog/` | Release announcements, feature deep-dives |

---

## Detailed Surface Inventory

### 1. App Store Listing

**URL:** https://apps.apple.com/app/contextify/id6753190666

**Source files:**
```
appstore-metadata/fastlane/metadata/en-US/
├── description.txt       # Full description
├── keywords.txt          # Search keywords
├── marketing_url.txt     # Website URL
├── name.txt              # App name
├── promotional_text.txt  # Short promo text
├── release_notes.txt     # What's new (per version)
├── subtitle.txt          # App subtitle
├── support_url.txt       # Support page URL
├── privacy_url.txt       # Privacy policy URL
```

**Screenshots:** `appstore-metadata/screenshots/`

**Update triggers:**
- New features (description, keywords, screenshots)
- System requirement changes (description)
- Support/privacy URL changes
- Every release (release_notes.txt)

**Review checklist:**
- [ ] System requirements accurate?
- [ ] Feature list current?
- [ ] Screenshots show current UI?
- [ ] URLs all working?

---

### 2. OG Image (Social Share Preview)

**Used when:** Links shared on Twitter, Slack, Discord, HN, etc.

**Source file:** `website/assets/img/og-banner.png`

**Dimensions:** 1200x630 (standard OG image size)

**Current content:**
- Contextify logo
- App name
- Tagline

**Update triggers:**
- Major messaging changes (e.g., new value prop)
- Branding updates
- Launch campaigns (may want campaign-specific messaging)

**Review checklist:**
- [ ] Tagline matches current website hero copy?
- [ ] Key value prop visible? (e.g., "30-day deletion" hook)
- [ ] Brand colors current?
- [ ] Text readable at small sizes (social previews are often thumbnailed)?

**Design notes:**
- Keep text minimal - it's often displayed small
- Lead with the hook, not the product name
- Test with Twitter Card Validator, LinkedIn Post Inspector

---

### 3. Website - Landing Page

**URL:** https://contextify.sh

**Source file:** `website/index.html`

**Content sections:**
- Hero (headline, subhead, CTA buttons)
- Features overview
- Download links (DMG, App Store badge)
- Screenshots/demo video

**Update triggers:**
- New features
- UI changes (screenshots)
- Download link changes
- App Store approval (add badge)

**Review checklist:**
- [ ] Feature list matches current capabilities?
- [ ] Download links working?
- [ ] Screenshots current?
- [ ] System requirements stated correctly?

---

### 4. Website - Help Page

**URL:** https://contextify.sh/help/

**Source file:** `website/help/index.html`

**Content sections:**
- Getting started guide
- Feature documentation
- Troubleshooting
- Links to support channels

**Update triggers:**
- New features
- Workflow changes
- Permission requirement changes
- New troubleshooting items

**Review checklist:**
- [ ] All documented features still work as described?
- [ ] Screenshots/examples current?
- [ ] Troubleshooting covers known issues?

---

### 5. Website - Support Page

**URL:** https://contextify.sh/support.html

**Source file:** `website/support.html`

**Content:**
- Contact information
- Bug reporting links (GitHub issues)
- Feature request links

**Update triggers:**
- Support channel changes
- Issue template updates
- Contact info changes

**Review checklist:**
- [ ] All links working?
- [ ] GitHub issue links correct?
- [ ] Email addresses valid?

---

### 6. Website - Privacy Policy

**URL:** https://contextify.sh/privacy.html

**Source file:** `website/privacy.html`

**Content:**
- Data collection practices
- Local storage details
- Third-party services (none currently)
- Contact information

**Update triggers:**
- New data collection
- New third-party integrations
- Analytics additions
- Cloud features

**Review checklist:**
- [ ] Accurately describes current data handling?
- [ ] No new data collection undocumented?
- [ ] Third-party services listed (if any)?
- [ ] Contact info current?

---

### 7. Release Notes (Multi-Output)

**Outputs:**
| Output | URL/Location | Purpose |
|--------|--------------|---------|
| Sparkle HTML | `https://contextify.sh/release-notes/X.Y.Z.html` | In-app update dialog |
| CHANGELOG | `~/code/projects/contextify-public-repo/CHANGELOG.md` | Public repo history |
| App Store | App Store Connect "What's New" | App Store listing |

**Source (future):** `releases/vX.Y.Z/release-notes.json` (see #P2-RELEASE-NOTES-JSON)

**Current source:** `website/release-notes/*.html` (manual)

**Generation workflow:**
1. LLM drafts from git commits: `./scripts/release/generate-release-notes.sh X.Y.Z`
2. Human edits for user-facing language
3. Render to outputs (future: from JSON)

**Artifacts:**
- `releases/vX.Y.Z/assets/changelog.llm.md` - LLM draft
- `releases/vX.Y.Z/release-notes.json` - Single source (planned)
- `website/release-notes/X.Y.Z.html` - Sparkle HTML

**Update triggers:**
- Every release

**Review checklist:**
- [ ] LLM draft generated and reviewed?
- [ ] User-facing language (not commit speak)?
- [ ] HTML deployed to website?
- [ ] CHANGELOG updated in public repo?
- [ ] App Store "What's New" updated (if App Store release)?

**Reference:** `build/docs/operations/release/release-notes-guide.md`, `release-notes-json-spec.md`

---

### 8. Appcast (Sparkle Auto-Updates)

**URL:** https://contextify.sh/appcast.xml

**Source file:** `website/appcast.xml`

**Content:**
- Version history
- Download URLs
- Sparkle signatures
- Minimum system version

**Update triggers:**
- Every DMG release

**Review checklist:**
- [ ] New `<item>` added for release?
- [ ] Download URL correct?
- [ ] Signature included?
- [ ] minimumSystemVersion correct?

---

### 9. Public GitHub Repository

**URL:** https://github.com/PeterPym/contextify

**Local clone:** `~/code/projects/contextify-public-repo/`

**Note on org name:** "PeterPym" is a placeholder org. May migrate to a branded org (e.g., `contextify-sh`) in the future if needed. "contextify" is taken on GitHub.

**Key files:**
```
├── README.md                    # Main documentation
├── .github/
│   └── ISSUE_TEMPLATES/
│       ├── bug_report.md        # Bug report template
│       └── feature_request.md   # Feature request template
```

**Update triggers:**
- Major releases (README version, download links)
- New features (README feature list)
- Issue process changes (templates)

**Review checklist:**
- [ ] Version/download links current?
- [ ] Feature list matches current capabilities?
- [ ] System requirements accurate?
- [ ] Issue templates still appropriate?

---

### 10. GitHub Releases (Public Repo)

**URL:** https://github.com/PeterPym/contextify/releases

**Created via:** `gh release create` or web UI

**Content:**
- Release notes/changelog
- DMG attachment
- Git tag

**Update triggers:**
- Every DMG release

**Review checklist:**
- [ ] Release created with correct tag?
- [ ] DMG attached?
- [ ] Release notes accurate?

**Integrity verification:**
```bash
# Expected hash (from build)
cat dist/Contextify-X.Y.Z.dmg.sha256

# Actual hash (from public download)
curl -sL "https://github.com/PeterPym/contextify/releases/download/vX.Y.Z/Contextify-X.Y.Z.dmg" | shasum -a 256
```
Hashes MUST match. If they don't, the wrong file was uploaded.

---

### 11. Twitter/X

**URL:** https://x.com/Contextify_sh

**Purpose:**
- Launch announcements
- Update notifications
- Community engagement
- Support visibility

**Update triggers:**
- Releases
- Major features
- HN/Reddit launches

---

### 12. Blog

**URL:** https://contextify.sh/blog/

**Source files:**
```
website/blog/
├── index.html                    # Blog index
└── YYYY-MM-DD-{slug}.html        # Individual posts
```

**Content:**
- Release announcements
- Feature deep-dives
- Technical articles
- Project updates

**Update triggers:**
- Major releases (announcement post)
- Significant new features
- Technical topics worth documenting

**Naming convention:**
- Files: `YYYY-MM-DD-{descriptive-slug}.html`
- Example: `2025-12-23-version-1.0.6.html`

**Review checklist:**
- [ ] Post content accurate?
- [ ] Index page updated with new post?
- [ ] Open Graph meta tags set?
- [ ] Links to download page working?

---

## Dynamic Links (Future Enhancement)

**TODO:** See #P2-DYNAMIC-FORWARDER in TODOS.md

Currently, download links point to specific versions. Consider implementing:

| Forwarder | Target | Purpose |
|-----------|--------|---------|
| `contextify.sh/download/latest` | Current DMG | Always points to latest release |
| `contextify.sh/download/latest/dmg` | Current DMG | Explicit DMG download |
| `contextify.sh/releases/latest` | Release notes page | Latest release info |

Benefits:
- Links in documentation never go stale
- Simplifies external references
- Single point of update for new releases

---

## Release Review Process

During each release, parse each surface and check for required updates:

### Pre-Release Checklist

```markdown
## Public Surfaces Review for v{VERSION}

### Content Accuracy
- [ ] App Store description matches current features
- [ ] Website landing page features current
- [ ] Help documentation covers all features
- [ ] Privacy policy reflects current data handling
- [ ] Public repo README accurate

### Version References
- [ ] Appcast has new entry
- [ ] Release notes page created
- [ ] GitHub release created
- [ ] README download links current

### System Requirements
- [ ] App Store: macOS version correct
- [ ] Website: requirements stated
- [ ] Public repo: requirements accurate

### Links
- [ ] All download links working
- [ ] Support links functional
- [ ] Privacy policy link valid
- [ ] Help page links working
```

---

## Known Discrepancies to Fix

**App Store vs Reality:**
- (Fixed in v1.0.6) App now supports macOS 15+ with Lite Mode

**Public Repo:**
- (Fixed in v1.0.6) README updated with correct system requirements

---

## Related Documentation

- `releases/WORKFLOW.md` - LLM-guided release workflow
- `releases/templates/checklists/05-marketing.md` - Marketing checklist
- `releases/templates/checklists/06-post-release.md` - Post-release checklist
- `build/docs/operations/WEBSITE.md` - Website operations
- `build/docs/operations/marketing/launch-plan-v1.md` - Launch plan
