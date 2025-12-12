# Contextify v1.0.0 Launch Plan

## Current State

- ✅ App Store: Submitted, pending review
- ✅ DMG: Built, signed, notarized
- ✅ GitHub Release: Created (v1.0.0)
- ⏳ Website: Basic landing page exists
- ⏳ Marketing: Show HN draft started

---

## 1. Website Improvements (contextify.sh)

### Current State
- Basic landing page
- Privacy policy
- Support page (?)

### Needed Before Launch

**Hero Section**
- [ ] Compelling headline (not just "Contextify")
- [ ] Subhead explaining what it does in one sentence
- [ ] Video demo embed (2 min walkthrough)
- [ ] CTA buttons: "Download DMG" + "App Store" (when approved)

**Features Section**
- [ ] 3-4 key features with screenshots
  - Real-time timeline
  - AI summaries
  - Multi-project organization
  - Search (coming soon)

**Screenshots Gallery**
- [ ] Reuse App Store screenshots
- [ ] Lightbox/modal for full-size viewing

**Download Section**
- [ ] DMG direct download link
- [ ] SHA256 checksum
- [ ] System requirements (macOS 26+)
- [ ] App Store badge (when approved)

**Footer**
- [ ] GitHub link
- [ ] Privacy policy
- [ ] Support/contact
- [ ] Twitter/social (if applicable)

### Nice to Have
- [ ] Changelog page
- [ ] FAQ section
- [ ] "Coming soon" roadmap preview
- [ ] Email signup for updates

### Technical
- [ ] Upload DMG to contextify.sh/releases/
- [ ] Set up download tracking (simple analytics?)
- [ ] Ensure HTTPS works for all pages

---

## 2. Distribution Channels

### Primary

| Channel | Status | Action Needed |
|---------|--------|---------------|
| **App Store** | Submitted | Wait for approval, then announce |
| **DMG (contextify.sh)** | Ready | Upload to website, add download link |
| **GitHub Releases** | Done | Already has v1.0.0 |

### Secondary

| Channel | Status | Action Needed |
|---------|--------|---------------|
| **Homebrew Cask** | Not started | Create cask formula after launch |
| **MacUpdater** | Not started | Submit after launch |
| **AlternativeTo** | Not started | Create listing |

---

## 3. Marketing Channels

### Tier 1 (High Impact, Do First)

**Hacker News - Show HN**
- [ ] Finalize Show HN draft
- [ ] Record video demo
- [ ] Prepare for Q&A (have answers ready)
- [ ] Post timing: Weekday, 9-11am PT
- [ ] Have screenshots ready for comments

**Twitter/X**
- [ ] Create announcement thread
- [ ] Tag @AnthropicAI, @OpenAI (they might RT)
- [ ] Share video demo
- [ ] Pin tweet

**Reddit**
- [ ] r/MacApps
- [ ] r/ClaudeAI
- [ ] r/LocalLLaMA (if relevant)
- [ ] r/programming (if Show HN does well)

### Tier 2 (Medium Impact)

**Dev Communities**
- [ ] Dev.to post
- [ ] Lobste.rs (if you have invite)
- [ ] Indie Hackers

**AI/ML Communities**
- [ ] Claude Discord (if exists)
- [ ] AI coding assistant communities

**macOS Communities**
- [ ] MacRumors forums
- [ ] r/macapps
- [ ] 9to5Mac tips

### Tier 3 (Lower Priority)

- [ ] Product Hunt (maybe wait for v1.1 with search?)
- [ ] LinkedIn post
- [ ] Personal blog post
- [ ] Email newsletter (if you have one)

---

## 4. Content to Prepare

### Video Demo (Critical)
- [ ] 2-minute walkthrough
- [ ] Show: launch app, see timeline, switch projects, see summaries
- [ ] Screen recording with voiceover OR silent with captions
- [ ] Host on YouTube (unlisted?) or direct embed

### Screenshots
- [ ] Already have App Store screenshots
- [ ] May need different aspect ratios for website/social

### Written Content
- [ ] Show HN post (in progress)
- [ ] Twitter thread script
- [ ] Reddit post variations (different subs want different angles)

### Press Kit (Optional)
- [ ] App icon (various sizes)
- [ ] Logo
- [ ] Screenshots (high-res)
- [ ] One-paragraph description
- [ ] One-sentence description

---

## 5. Launch Sequence

### Phase 1: Pre-Launch (Now)
- [ ] Finalize website
- [ ] Record video demo
- [ ] Prepare all written content
- [ ] Upload DMG to website
- [ ] Test download flow

### Phase 2: Soft Launch (App Store Approval)
- [ ] Update website with App Store link
- [ ] Tweet announcement
- [ ] Post to r/MacApps, r/ClaudeAI
- [ ] Gather initial feedback

### Phase 3: Show HN (1-2 days after soft launch)
- [ ] Post Show HN
- [ ] Be available for 4-6 hours to answer questions
- [ ] Have screenshots ready to post in comments
- [ ] Cross-post to Twitter with HN link

### Phase 4: Expand (Following Week)
- [ ] Other Reddit communities
- [ ] Dev.to / Indie Hackers
- [ ] Homebrew Cask submission
- [ ] Product Hunt (if momentum is good)

---

## 6. Metrics to Track

**Downloads**
- DMG downloads from website
- App Store downloads (App Store Connect)
- GitHub release downloads

**Engagement**
- HN points/comments
- Twitter impressions/engagement
- Reddit upvotes

**Retention**
- (No analytics in app currently - consider for v1.1?)

---

## 7. Potential Objections & Responses

**"Why macOS only?"**
> Native performance, Apple Intelligence integration. Windows/Linux would require different LLM approach.

**"Why Tahoe only?"**
> Apple Intelligence requires macOS 26. Working on backwards compatibility with lite mode.

**"What about Cursor/Aider/other tools?"**
> Claude Code and Codex CLI first because that's what I use. More tools planned based on demand.

**"Is this open source?"**
> Core app is not open source yet. Considering it based on traction. Transcript formats are documented.

**"How is this different from just reading the JSONL files?"**
> You could read them manually, but: unified timeline across tools, AI summaries, search, project organization. It's the UX layer.

**"What about privacy?"**
> Everything local. No data leaves your Mac. LLM runs on-device via Apple Intelligence.

---

## 8. Open Questions

1. **Video demo**: Record yourself or hire someone? Voiceover or silent?

2. **Show HN timing**: Wait for App Store approval, or go with DMG-only?

3. **Twitter strategy**: Personal account or create @contextifyapp?

4. **Product Hunt**: Now or wait for v1.1 with search?

5. **Analytics**: Add simple download tracking to website?

6. **Email list**: Set up for launch or skip for now?

---

## 9. Timeline

| Day | Action |
|-----|--------|
| D-3 | Website improvements, upload DMG |
| D-2 | Record video demo |
| D-1 | Finalize Show HN, prepare all posts |
| D-0 | App Store approval (hopefully) |
| D+1 | Soft launch: Tweet, Reddit |
| D+2 | Show HN post |
| D+3 | Monitor, respond, iterate |
| D+7 | Expand to other channels |

---

## 10. Success Metrics

**Minimum viable launch:**
- 50+ HN points
- 100+ DMG downloads
- App Store approval

**Good launch:**
- 200+ HN points
- 500+ downloads (DMG + App Store)
- Featured comment/discussion

**Great launch:**
- HN front page
- 1000+ downloads first week
- Inbound interest (press, investors, contributors)
