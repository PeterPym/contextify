# Website Design (contextify.sh)

Design documentation for the marketing website.

## Status: Design System Complete, Assets Needed

Website styling complete on `feature/design-system-and-website` branch. Needs screenshots before deploy.

## Completed Work

- **Design system:** Color tokens in `../brand/colors.md` (Slate + Blue, semantic colors)
- **CSS migration:** INSPINIA -> design system tokens in `website/styles.css`
- **Visual polish:** Brand divider, card hover effects, solid navbar background
- **Landing page:** Bootstrap 5, hero with swoopity SVG, feature cards
- **Content pages:** Privacy, terms, support (styled with new tokens)
- **Logomark:** Copied to `website/assets/img/contextify-icon.png`

## Remaining Work

- **App screenshots:** Light + dark mode, 2x for retina
- **OG image:** 1200x630 banner for social sharing
- **Favicon:** Verify current or create new
- **Responsive testing:** Desktop, tablet, mobile
- **Deploy:** `./scripts/deploy-website.sh`

## Design Decisions

| Decision | Choice | Notes |
|----------|--------|-------|
| **Color direction** | Slate + Blue | Neutral slate base, blue (#4A7BA7) for actions |
| **Neutral scale** | Tailwind Slate | 11-step gray scale for text/bg/border |
| **Dark mode** | Systematic derivation | Inversion + lifting documented in colors.md |
| **Brand gradient** | Dividers, hover accents | Yellow/cyan/purple from logomark |

## Planned Contents

| File | Purpose | Status |
|------|---------|--------|
| `components.md` | Buttons, cards, nav, footer specs | TODO |
| `typography.md` | Web fonts, sizing, line heights | TODO |
| `pages/` | Page-specific design notes | TODO |
| `PIPELINE.md` | Build/deploy process (when needed) | Deferred |

## Current Architecture

```
website/                  # Static files, directly uploadable
├── index.html
├── privacy.html
├── terms.html
├── support.html
└── assets/
    ├── css/
    └── img/
        └── swoopity-dark.svg
```

**Deploy:** `scripts/deploy-website.sh` uploads directly to server. No build step currently.

## Next Steps

1. ~~**Finalize color palette**~~ Done - see `../brand/colors.md`
2. ~~**Apply color system**~~ Done - migrated from INSPINIA to design tokens
3. **Add app screenshots** (light + dark mode, 2x for retina)
4. **Create OG image** for social sharing (1200x630)
5. **Document component styles** (buttons, cards, forms)
6. **Define responsive breakpoints**

## Future: Build Pipeline

Currently all website files are static and directly uploadable. A build pipeline would be needed for:
- Asset optimization (image compression)
- Generated content (if help docs become generated)
- Template rendering (if moving to static site generator)

When implemented, document in `PIPELINE.md`.
