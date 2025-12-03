# Contextify Logomark

The infinity symbol with circular arrows - Contextify's primary visual identifier.

## Files

```
logomark/
├── README.md           # This file
├── HISTORY.md          # Version history with hashes
├── source/
│   ├── infinity.svg    # Vector source (TODO)
│   └── infinity-1024.png  # High-res master
└── exports/
    ├── infinity-512.png
    ├── infinity-256.png
    ├── infinity-128.png
    ├── infinity-64.png
    ├── infinity-48.png
    ├── infinity-32.png
    └── infinity-16.png
```

## Usage

The logomark can be used:
- Standalone (without wordmark)
- With wordmark lockup (horizontal or stacked)
- On light or dark backgrounds (has transparency)

## File Notes

- **source/infinity-1024.png**: Uncompressed master (matches Icon Composer asset)
- **exports/*.png**: Compressed with `oxipng` for web/app use

## Regenerating Exports

From the 1024px source:

```bash
cd build/design/brand/logomark
for SIZE in 512 256 128 64 48 32 16; do
  sips -z $SIZE $SIZE source/infinity-1024.png --out exports/infinity-$SIZE.png
done
oxipng -o 4 --strip safe exports/infinity-*.png
```

**Note:** Do not compress `source/infinity-1024.png` - keep it identical to the Icon Composer asset for hash consistency.

## TODO

- [ ] Create SVG vector source from PNG (trace or recreate)
- [ ] Define clear space requirements
- [ ] Define minimum size guidelines
- [ ] Document color values (yellow/cyan/purple gradient)
