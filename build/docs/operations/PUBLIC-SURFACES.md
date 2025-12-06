# Public Surfaces Inventory

**Purpose:** Canonical inventory of all public-facing surfaces that may need updates with releases.

**Last Updated:** 2025-11-27

---

## Quick Reference

| Surface | URL / Location | Source Files | Update Triggers |
|---------|---------------|--------------|-----------------|
| App Store Listing | [apps.apple.com](https://apps.apple.com/app/contextify/id6753190666) | `appstore-metadata/fastlane/metadata/en-US/` | Major releases, feature changes |
| Website Landing | [contextify.sh](https://contextify.sh) | `website/index.html` | Feature additions, screenshots |
| Website Help | [contextify.sh/help](https://contextify.sh/help/) | `website/help/index.html` | Feature changes, workflow updates |
| Website Support | [contextify.sh/support](https://contextify.sh/support.html) | `website/support.html` | Contact info, issue process changes |
| Website Privacy | [contextify.sh/privacy](https://contextify.sh/privacy.html) | `website/privacy.html` | Data handling changes |
| Release Notes | [contextify.sh/release-notes](https://contextify.sh/release-notes/) | `website/release-notes/{version}.html` | Every release |
| Appcast (Sparkle) | [contextify.sh/appcast.xml](https://contextify.sh/appcast.xml) | `website/appcast.xml` | Every DMG release |
| Public Repo | [github.com/PeterPym/contextify](https://github.com/PeterPym/contextify) | `~/code/projects/contextify-public-repo/` | Major releases, docs changes |
| GitHub Releases | [github.com/banagale/contextify/releases](https://github.com/banagale/contextify/releases) | Created via `gh release` | Every DMG release |

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

### 2. Website - Landing Page

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

### 3. Website - Help Page

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

### 4. Website - Support Page

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

### 5. Website - Privacy Policy

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

### 6. Website - Release Notes

**URL:** https://contextify.sh/release-notes/{version}.html

**Source files:** `website/release-notes/*.html`

**Generation:** Release notes are generated via LLM from git history.
See `scripts/release/generate-release-notes.sh`.

**Artifacts:**
- `releases/vX.Y.Z/assets/changelog.llm.md` - LLM draft
- `releases/vX.Y.Z/assets/changelog.final.md` - Edited final
- `website/release-notes/X.Y.Z.html` - Published HTML

**Update triggers:**
- Every release

**Review checklist:**
- [ ] LLM draft generated and reviewed?
- [ ] Final version saved to `changelog.final.md`?
- [ ] HTML version created?
- [ ] Changes accurately described?
- [ ] Links from landing page updated?

---

### 7. Appcast (Sparkle Auto-Updates)

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

### 8. Public GitHub Repository

**URL:** https://github.com/PeterPym/contextify

**Local clone:** `~/code/projects/contextify-public-repo/`

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

### 9. GitHub Releases (Private Repo)

**URL:** https://github.com/banagale/contextify/releases

**Created via:** `gh release create`

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
- App Store description says "macOS 14.0 (Sonoma)" but app requires macOS 26
- Should be updated to "macOS 26 (Tahoe)" when corrected

**Public Repo:**
- Download links say "(coming soon)" - update when App Store approved

---

## Related Documentation

- `releases/WORKFLOW.md` - LLM-guided release workflow
- `releases/templates/checklists/05-marketing.md` - Marketing checklist
- `releases/templates/checklists/06-post-release.md` - Post-release checklist
- `build/docs/operations/WEBSITE.md` - Website operations
- `build/docs/operations/marketing/launch-plan-v1.md` - Launch plan
