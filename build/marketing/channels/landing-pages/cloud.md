# Landing Page Brief: /cloud/

**Target URL:** contextify.sh/cloud/
**Bloon task:** ct-390
**Status:** Live, hybrid version promoted to index.html

## Current page structure (hybrid, review-informed)

Based on external marketing review analyzing Vercel, Supabase, Linear, Raycast, 1Password, Warp patterns, and Evil Martians' 100-page dev tool study. Structure: scannable first, evidence second, trust third.

1. **Hero** - "I know I figured this out already." (rated 9/10 by reviewer) + subhead naming /total-recall skill + terminal mockup. CTA: Download for Mac + See Plans. Reassurance line: "Free tier available. Opt-in sync. Per-project control. Mac + Linux."
2. **Before/After strip** - 3 cloud-specific rows (switch machines, laptop dies, need context remotely). Mobile: shows positive outcomes only.
3. **Value cards** - 3 cards: Survives everything, Past sessions become context, Mac + Linux one history
4. **Production proof cases** - 3 real stories with "89% returned actionable information" stat. Bug that kept coming back (TR-3), schema work nobody could find (Case 9), pricing decision that never happened (Case 8).
5. **How it works** - 3 steps: Install, Enable Cloud Sync, Search from anywhere
6. **Privacy + FAQ** - Layered trust: 4-item compact grid (off by default, per-project control, encrypted, no lock-in) + 4 FAQ items (Dropbox, offline, what syncs, project exclusion)
7. **Teams teaser** - Compact paragraph with pricing link
8. **Final CTA** - Download for Mac + Install on Linux + See Pricing

## Content sources

- `content/products/cloud-sync/value-props.md` - value propositions
- `content/products/cloud-sync/reviews/2026-03-26-chatgpt-marketing-review.md` - external review
- `content/products/total-recall/proof-points.md` - TR-1 through TR-12
- `content/products/total-recall/usage-analysis/marketing-cases.md` - 15 marketing-ready cases
- ct-390 attachment `388d619e` - product brief with brand voice, audience segments

## Variant pages (for reference)

Three earlier approaches preserved at `website/cloud/variants/`:
- `story-led.html` - narrative-first, real production stories
- `before-after.html` - scannable comparison grid
- `hybrid.html` - the version promoted to index.html (kept as reference copy)

## Open work

- **Architecture diagram:** product brief called for a generated image. Not yet done. Reviewer recommended real terminal mockup + browser screenshot over diagrams.
- **Teams section:** slimmed to teaser, will link to /teams/ page when ct-665 creates it.
- **Total Recall dedicated page:** ct-669 would allow the cloud page's proof section to link deeper.

## Design notes

- Bootstrap 5.3 + CSS tokens from styles.css, dark mode via `data-bs-theme`
- No Bootstrap JS (no interactive components)
- Accessibility: skip link, `<main>` landmark, `:focus-visible` on CTAs, `aria-hidden` on decorative icons
- Mobile responsive: before/after grid hides headers and "without" column, shows positive outcomes only
