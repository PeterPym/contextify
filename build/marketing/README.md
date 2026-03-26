# Marketing

Marketing content, campaigns, press coverage, and community engagement.

## Directory Structure

```
marketing/
├── README.md               # This file
├── content/                # Core content library (write once, use everywhere)
│   ├── README.md           # Content library guide
│   ├── products/           # Feature content (proof points, value props, use cases)
│   │   ├── total-recall/   # Total Recall: cross-session AI memory
│   │   ├── cloud-sync/     # Cloud Sync: multi-device history
│   │   └── timeline/       # Timeline: real-time conversation monitoring
│   ├── clients/            # Platform/client content
│   │   ├── macos-app/      # macOS app (DMG + App Store)
│   │   └── linux-cli/      # Linux CLI
│   └── audience-segments.md
├── channels/               # Channel-specific adaptations
│   ├── landing-pages/      # Content briefs for website pages
│   ├── blog/               # Blog post drafts and ideas
│   └── social/             # Social media content
├── launch/                 # Launch campaign materials (HN, Reddit, etc.)
├── announcements/          # Version-specific announcements
├── press/                  # Third-party coverage
├── feedback/               # User feedback collection
└── strategy/               # Distribution plans, launch strategy
```

## Content Flow

Core content lives in `content/products/`. Channel adaptations in `channels/`. Campaigns in `launch/` and `announcements/`.

```
content/products/total-recall/proof-points.md    (source of truth)
    |
    +-> channels/landing-pages/total-recall.md   (website page brief)
    +-> channels/blog/                           (blog post drafts)
    +-> channels/social/                         (social adaptations)
    +-> launch/ or announcements/                (campaign materials)
```

See `content/README.md` for the full content library guide.

## Monitoring Checklist

**Daily during active promotion:**
- [ ] Check press/README.md for URLs to monitor
- [ ] Run opportunity-monitor for new mentions
- [ ] Respond to comments on known surfaces

**Weekly:**
- [ ] Review user feedback for patterns
- [ ] Update press coverage if new articles found

## Related Tools

### Outposter

`~/code/projects/outposter/` - Local tool for discovering and monitoring Contextify mentions across HN, Reddit, Lobsters, and forums.

```bash
cd ~/code/projects/outposter
uv run outposter fetch      # Fetch new items
uv run outposter list       # Show opportunities
```

## Quick Links

- Website: https://contextify.sh
- App Store: https://apps.apple.com/us/app/contextify/id6753190666
- GitHub (public): https://github.com/PeterPym/contextify
- YouTube: https://www.youtube.com/@contextify_sh
