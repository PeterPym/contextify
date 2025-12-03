# Website Design (contextify.sh)

Design documentation for the marketing website.

## Status: Active Development

Website design is actively being developed on `feature/design-system-and-website` branch.

## Current Work

- **Design comparator:** `specimens/website-comparator.html` (Lens A: Website, Lens B: Specimens)
- **Color system:** `../brand/colors.md` (Slate + Blue, full inventory)
- **Landing page:** Bootstrap 5, hero section, feature cards
- **Content pages:** Privacy, terms, support (styled)

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
2. **Apply color system** to production `website/styles.css`
3. **Document component styles** (buttons, cards, forms)
4. **Define responsive breakpoints**

## Future: Build Pipeline

Currently all website files are static and directly uploadable. A build pipeline would be needed for:
- Asset optimization (image compression)
- Generated content (if help docs become generated)
- Template rendering (if moving to static site generator)

When implemented, document in `PIPELINE.md`.
