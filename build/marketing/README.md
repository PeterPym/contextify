# Marketing

Ongoing marketing, press coverage, and community engagement tracking.

## Directory Structure

```
marketing/
├── README.md           # This file
├── press/              # Third-party coverage
│   ├── README.md       # Press tracking + monitoring URLs
│   └── articles/       # Saved article text
├── feedback/           # User feedback collection
├── strategy/           # Distribution plans, launch strategy
└── launch/             # Launch campaign materials (HN, Reddit, etc.)
```

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

**Two monitoring modes:**
1. **Discovery** - Find new threads where Contextify could be mentioned
2. **Known Surfaces** - Monitor places we've already posted/been covered (see `press/README.md`)

```bash
cd ~/code/projects/outposter
uv run outposter fetch      # Fetch new items
uv run outposter list       # Show opportunities
```

See Outposter README for full usage.

## Quick Links

- Website: https://contextify.sh
- App Store: https://apps.apple.com/us/app/contextify/id6753190666
- GitHub (public): https://github.com/PeterPym/contextify
- YouTube: https://www.youtube.com/@contextify_sh
