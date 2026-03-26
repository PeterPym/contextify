# Landing Page Brief: /cloud/

**Target URL:** contextify.sh/cloud/
**Bloon task:** ct-390
**Status:** Live, v3 polish committed (branch ct-390-v3-polish)

## Current page structure

1. **Hero** - "I know I figured this out already." + terminal showing Total Recall query
2. **Problem** - "Claude Code and Codex conversations are trapped on individual machines" + fenced-devices illustration
3. **Individual value** - "One unified context across every machine" (3 cards: survives everything, search from any machine, Mac + Linux)
4. **Total Recall** - Standalone section with 3 real proof points (TR-2, TR-3, TR-4)
5. **Teams** - Brief teaser paragraph with pricing link (slimmed from 3 cards in v2)
6. **Trust/Privacy** - 7 items including per-project sync control
7. **FAQ** - 6 questions (Dropbox comparison, offline use, what syncs, per-project exclusion, cancellation, self-hosted)
8. **CTA** - Download + pricing

## Content sources

- `content/products/cloud-sync/value-props.md` - value propositions
- `content/products/total-recall/proof-points.md` - TR-1 through TR-12
- ct-390 attachment `388d619e` - full product brief with brand voice, audience segments
- ct-390 attachment `1b055884` - ChatGPT review of v2 (4 findings, all implemented)

## Open work

- **Total Recall headline:** current "Search past AI sessions from your current one" undersells it. Needs refresh, possibly after /total-recall/ page exists and this section becomes a bridge to it.
- **Architecture diagram:** product brief called for a proper generated image (not HTML/CSS). Not yet done.
- **Teams section:** slimmed to teaser, will link to /teams/ page when ct-665 creates it.
- **Image: connected devices:** fenced-devices illustration exists, a "connected" version (fences removed, devices linked) was discussed for the value section.

## Design notes

- Page uses site-wide Bootstrap 5.3 + CSS tokens from styles.css
- Dark mode works via `data-bs-theme` detection
- No Bootstrap JS loaded (no interactive components)
- Accessibility: skip link, `<main>` landmark, `:focus-visible` on all CTAs, `aria-hidden` on decorative icons
