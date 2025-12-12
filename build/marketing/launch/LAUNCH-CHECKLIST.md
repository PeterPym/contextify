# Contextify Launch Checklist

## Launch Calendar

| Date | Platform | Status | Notes |
|------|----------|--------|-------|
| Dec 9 (Tue) | Hacker News | ✅ Done | 3 pts, 566 visitors - modest |
| Dec 10 (Wed) | Reddit Blitz | 🎯 Next | r/ClaudeAI + r/MacApps + r/OpenAI |
| Dec 10 (Wed) | Twitter/X | 🎯 Next | Announce thread |
| TBD | Lobsters | ⏸️ Skip | Not active there, would look spammy |
| TBD | Product Hunt | Later | Separate launch day |

**Strategy:** HN underperformed, so pivot to Reddit blitz tomorrow. Post to multiple subreddits in the morning, space them ~1-2 hours apart to avoid looking spammy. Support with Twitter thread.

---

## Pre-Launch (Do First)

- [x] **Demo video** - 3:39 video uploaded to YouTube
  - Video: https://www.youtube.com/watch?v=FvrvRGp4C9M
  - Channel: https://www.youtube.com/@contextify_sh

- [ ] **OG image update** (P2 - can launch without)
  - Spec: `build/design/website/og-image-spec.md`
  - New copy: "Your Claude Code history deletes after 30 days / Contextify keeps it forever"

- [ ] **App icon review** (P0 - verify it's the angled one everywhere)

## Hacker News (Show HN) - DONE

- [x] Review/finalize post draft: `build/launch/show-hn/draft.md`
- [x] Post title: "Show HN: Contextify - Your Claude Code history deletes after 30 days. This keeps it forever."
- [x] YouTube link added to draft
- [x] Posted 2025-12-09: https://news.ycombinator.com/item?id=46209081
- [x] Monitored comments for first few hours
- **Result:** 3 points, 566 visitors (mostly Windows drive-bys), modest traction

## Lobsters - NEXT (Dec 10)

- [x] Draft ready: `build/launch/lobsters/draft.md`
- [ ] Post title: "Contextify - Searchable history for Claude Code and Codex CLI"
- [ ] Tags: `show`, `macos`, `ai`
- [ ] Post at ~10am PT (good for West Coast + Europe overlap)
- [ ] Be ready to respond - Lobsters audience appreciates technical depth
- [ ] Link: contextify.sh

## Reddit - BACKUP/SUPPLEMENT

**Strategy:** See `build/launch/reddit/README.md` for full research.

**Timing:**
- If HN gets traction: wait 1-2 days before Reddit
- If HN flops: post to Reddit same day or next day

### r/ClaudeAI (386k members) - PRIMARY REDDIT TARGET
- [x] Draft ready: `build/launch/reddit/post-claudeai.md`
- [ ] Use "Built with Claude" or "Self-Promotion" flair
- [ ] Include screenshots inline
- [ ] Post format: what you built, how, screenshots, why

### r/MacApps (193k members) - SECONDARY
- [x] Draft ready: `build/launch/reddit/post-macapps.md`
- [ ] Emphasize: free, native SwiftUI, privacy-focused
- [ ] Be ready for critical feedback (respond well = momentum)

### r/OpenAI - FOR CODEX USERS
- [x] Draft ready: `build/launch/reddit/post-openai.md`
- [ ] Lead with Codex angle
- [ ] Mention Claude Code as bonus (unified history)

### r/LocalLLaMA (577k members) - SKIP
- Apple Intelligence isn't really "local LLaMA" - poor fit
- Only consider if all other channels fail

### r/SideProject - OPTIONAL
- [ ] Origin story angle
- [ ] FileKitty background

## Product Hunt (Later - separate launch)

- [ ] Create upcoming page
- [ ] Schedule launch (different day from HN)
- [ ] Prep assets (icon, screenshots, tagline)
- [ ] Hunter outreach (optional)

## Other Channels

### Twitter/X
- [ ] Announce thread
- [ ] Include video or GIF
- [ ] Tag @AnthropicAI?

### Mastodon
- [ ] Post to relevant instances
- [ ] #macOS #AI #DeveloperTools

### Indie Hackers
- [ ] Post in community
- [ ] Link to origin story

### Dev.to (optional)
- [ ] Write-up: "I built a searchable backup for my AI coding sessions"

## Assets Status

| Asset | Status | Location |
|-------|--------|----------|
| Demo video | ✅ | https://www.youtube.com/watch?v=FvrvRGp4C9M |
| Screenshots | ✅ | website |
| App icon | ✅ | Contextify.app |
| OG image | ⚠️ Needs update | `website/assets/img/og-banner.png` |
| Origin story | ✅ | `build/launch/origin-story.md` |
| Show HN draft | ✅ | `build/launch/show-hn/draft.md` |
| Reddit drafts | ✅ | `build/launch/reddit/` |

## Links to Include

- Website: https://contextify.sh
- Download (DMG): https://github.com/PeterPym/contextify/releases/latest
- App Store: https://apps.apple.com/us/app/contextify/id6753190666
- GitHub (issues): https://github.com/PeterPym/contextify/issues
- Demo video: https://www.youtube.com/watch?v=FvrvRGp4C9M

## Key Messages

1. **Hook:** "Your Claude Code history deletes after 30 days"
2. **Solution:** "Contextify keeps it forever and makes it searchable"
3. **Differentiator:** "Apple Intelligence summaries - 100% local, no API costs"
4. **Trust:** "From the maker of FileKitty"
5. **Privacy:** "All data stays on your Mac"

## Post-Launch

- [ ] Monitor HN comments (first 2-3 hours critical)
- [ ] Monitor Reddit threads
- [ ] Check support email (support@contextify.sh)
- [ ] Watch GitHub issues
- [ ] Thank commenters, answer questions
- [ ] If HN flops, execute Reddit backup plan
