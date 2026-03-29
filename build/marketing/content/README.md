# Marketing Content Library

Core content that feeds every marketing channel. Write here once, adapt for landing pages, blog posts, social media, and campaigns.

## How It Works

```
content/                          Source of truth
  products/total-recall/            Features
  products/cloud-sync/
  products/timeline/
  clients/macos-app/                Clients (platforms)
  clients/linux-cli/
  audience-segments.md              Who we're talking to
        |
        v
channels/                         Channel adaptations
  landing-pages/                    Content briefs for website pages
  blog/                             Blog post drafts and ideas
  social/                           Social media content
        |
        v
launch/ + announcements/          Campaigns (existing)
  Draws from content + channels
```

## Content Types

### Product content (`content/products/<feature>/`)

Feature-level content (Total Recall, Cloud Sync, Timeline monitoring).

### Client content (`content/clients/<platform>/`)

Platform-level content (macOS app, Linux CLI). Each client may feed its own landing page. The Linux page already exists at `website/platforms/linux/`.

### Common structure

Each product or client directory contains:

| File | Purpose |
|------|---------|
| `proof-points.md` | Real usage examples with evidence and citations |
| `value-props.md` | Core value propositions (what it does, why it matters) |
| `use-cases.md` | Taxonomy of use cases with frequency data |
| `case-studies.md` | Deep case studies from usage analysis |

Proof points are the foundation. Everything else derives from them.

### Audience segments (`content/audience-segments.md`)

Who uses Contextify, what they care about, and which proof points resonate with each segment.

### Channel outputs (`channels/`)

Adaptations of core content for specific channels:

- **Landing pages** - Content briefs that website pages are built from
- **Blog** - Post drafts, topic ideas, content calendar
- **Social** - Platform-specific adaptations (Twitter threads, Reddit posts, HN comments)

Channel content should reference product content by proof point ID (e.g., "TR-1") rather than duplicating it.

## Related

- Brand identity: `build/design/brand/` (colors, logomark, providers)
- Brand voice: ct-666 (planned, `build/design/brand/voice-tone.md`)
- Website: `website/` (the deployed pages that consume this content)
- Campaigns: `build/marketing/launch/`, `build/marketing/announcements/`
- Press: `build/marketing/press/`
