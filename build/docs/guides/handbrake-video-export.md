# Handbrake Video Export Settings

Standard settings for exporting Contextify demo/marketing videos for YouTube.

## Preset Name
**"contextify web videos"** (save as custom preset in Handbrake)

## Summary Tab
- **Format:** MP4
- **Passthru Common Metadata:** checked
- **Web Optimized:** unchecked
- **Align A/V Start:** unchecked

## Video Tab
- **Video Encoder:** H.265 (VideoToolbox) - uses Apple hardware encoder
- **Framerate (FPS):** Same as source
- **Variable Framerate:** selected
- **Color Range:** Limited
- **Quality:** Constant Quality, **CQ 55**
- **Encoder Options:**
  - Preset: speed
  - Tune: none
  - Profile: auto
  - Level: auto

## Audio Tab
- AAC (CoreAudio), Stereo

## Output
- Resolution: 3840x2160 (4K) or source
- ~200-400MB for a 4 min video (vs 1.6GB from FCP)

## Why These Settings
- **H.265 (VideoToolbox):** Hardware encoding via M-series Media Engine, fast and efficient
- **CQ 55:** Good quality/size balance for YouTube (will re-encode anyway)
- **Variable Framerate:** Preserves source timing
- **Non-10-bit:** More compatible, uses hardware encoder properly

## Notes
- VideoToolbox uses the dedicated Media Engine, not CPU/GPU
- Activity Monitor won't show GPU usage - that's normal
- If CPU pegs at 100%, VideoToolbox isn't being used - check encoder selection
