# Contextify Logomark

The infinity symbol with circular arrows - Contextify's primary visual identifier.

## Files

```
logomark/
├── README.md           # This file
├── HISTORY.md          # Version history with hashes
├── source/
│   ├── infinity-1024.png     # Canonical master (flat, true 1024x1024)
│   ├── infinity-904-glass.png # Historical variant (904px, glass effect)
│   └── infinity.svg          # Vector source (TODO)
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

- **source/infinity-1024.png**: Canonical master, flat style, true 1024x1024
- **source/infinity-904-glass.png**: Historical variant with glass effect (904px)
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

**Note:** Do not compress `source/infinity-1024.png` to preserve hash consistency.

## TODO

- [ ] Create SVG vector source from PNG (trace or recreate)
- [ ] Define clear space requirements
- [ ] Define minimum size guidelines
- [ ] Document color values (yellow/cyan/purple gradient)
