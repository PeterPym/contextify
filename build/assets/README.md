# Contextify Assets

Unified hub for all visual assets. Browse via symlinks or query MANIFEST.yaml.

## Quick Start

```bash
# Browse website images
ls build/assets/website/

# Browse App Store screenshots
ls build/assets/appstore/

# Find assets by keyword
grep "queue" build/assets/MANIFEST.yaml
```

## Structure

| Directory | Type | Contents |
|-----------|------|----------|
| `website/` | Symlink → `website/assets/img/` | Production website images |
| `appstore/` | Symlink → `appstore-metadata/screenshots/final/` | App Store screenshots |
| `promotional/` | Real files | Version-tagged promotional screenshots |
| `video/` | Real files | Demo videos and backgrounds |
| `dmg/` | Real files | DMG installer assets |
| `app-icon/` | Real files | App icon build assets |

## Asset Locations

| Asset Type | Location | Notes |
|------------|----------|-------|
| Website images | `website/assets/img/` | PNG + WebP, deployed to contextify.sh |
| App Store screenshots | `appstore-metadata/screenshots/final/` | 2880x1800, with/without text |
| Promotional screenshots | `build/assets/promotional/v{VERSION}/` | For social, docs |
| Demo videos | `build/assets/video/` | Final exports only |
| Video source files | `~/Dropbox/Contextify/marketing/` | Large files outside git |
| Brand assets | `build/design/brand/` | Colors, logo, provider icons |
| DMG build assets | `build/assets/dmg/` | Background, settings |

## MANIFEST.yaml

Structured metadata for programmatic queries:
- `id`: Unique identifier
- `path`: File path (relative to repo root)
- `type`: screenshot, video, icon, badge, social, config, build-asset
- `app_version`: Which app version this represents
- `purpose`: [website, appstore, social, docs, build]
- `keywords`: Searchable terms

## Adding New Assets

1. **Website**: Add to `website/assets/img/`, generate WebP (except og-banner)
2. **App Store**: Use `scripts/screenshots/` workflow
3. **Promotional**: Add to `promotional/v{CURRENT_VERSION}/`
4. **Video**: Add final export to `video/`, source to Dropbox

After adding, update MANIFEST.yaml.

## Related

- Screenshot specs: `appstore-metadata/screenshots/SCREENSHOT-SPECIFICATIONS.md`
- Screenshot scripts: `scripts/screenshots/`
- Brand system: `build/design/brand/`
