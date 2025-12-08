# App Icon (macOS 26 Tahoe)

## Current Setup

**Icon file:** `Contextify/icon-composer-project.icon`
**Xcode setting:** `ASSETCATALOG_COMPILER_APPICON_NAME = icon-composer-project`

## macOS 26 Icon Format

macOS 26 Tahoe introduced a new app icon format using **Icon Composer** (bundled with Xcode 26).

### Key Points

1. **New `.icon` format** - Replaces traditional `.appiconset` for Tahoe
2. **Icon Composer app** - Found in Xcode 26, creates the `.icon` bundle
3. **Liquid Glass** - Tahoe applies glass material automatically
4. **Max 4 groups** - Icon Composer files should have max 4 layer groups

### File Structure

```
icon-composer-project.icon/
├── Assets/
│   └── Infinity.png      # The actual logomark image
└── icon.json             # Icon Composer metadata
```

### Xcode Integration

1. Drag `.icon` file into Xcode project navigator
2. Set `ASSETCATALOG_COMPILER_APPICON_NAME` to match filename (without `.icon`)
3. Xcode processes it via `actool` at build time

### Backward Compatibility

For pre-Tahoe macOS (if ever needed):
- Xcode generates fallback icons from Icon Composer file
- Or use `--enable-icon-stack-fallback-generation=disabled` flag
- Add separate `AppIcon.icns` to Resources with `CFBundleIconFile` in Info.plist

## Editing the Icon

1. Open Icon Composer (in Xcode 26: Xcode menu > Open Developer Tool > Icon Composer)
2. Open `Contextify/icon-composer-project.icon`
3. Edit layers/groups
4. Save
5. Rebuild app

## Source Assets

**Logomark source:** `build/design/brand/logomark/`
- `exports/` - PNG exports at various sizes
- `source/` - Original design files

## References

- [Successful Software: Updating icons for macOS 26](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/)
- [Michael Tsai: Icon Composer Notes](https://mjtsai.com/blog/2025/06/23/icon-composer-notes/)
- [Michael Tsai: Separate Icons for Tahoe vs Earlier](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/)
- [Eclectic Light: Tahoe and Xcode icon issues](https://eclecticlight.co/2025/07/10/tahoe-b3-and-xcode-26-b3-can-screw-app-icons/)
