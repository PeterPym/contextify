# Cursor CLI Installation UX Research

**Date:** 2025-12-15
**Purpose:** Understand Cursor's CLI installation flow and admin privilege requirements
**Relevance:** Informs our CLI auto-install design decisions

---

## Contents

- **analysis.md** - Full technical analysis with recommendations
- **01-initial-setup.png** - Preferences screen with "Install" button
- **02-admin-warning.png** - Cursor's warning dialog before system prompt
- **03-password-prompt.png** - macOS admin password dialog
- **04-success.png** - Success confirmation

## Key Findings

### Why Admin Password Was Required

**TL;DR:** `/usr/local/bin/` is owned by `root:wheel`, so creating files there requires admin privileges.

**The Flow:**
1. User clicks "Install" for `cursor` command
2. Cursor warns: "Will prompt for admin privileges"
3. macOS shows password dialog: "osascript wants to make changes"
4. User enters password
5. Cursor creates symlink: `/usr/local/bin/cursor` → app bundle
6. Success - `cursor` command now works in any terminal

### Why Cursor Chose `/usr/local/bin` (Even With Homebrew Installed!)

**Important discovery:** The test Mac has homebrew at `/opt/homebrew/bin` with writable permissions (no admin needed), but Cursor STILL chose `/usr/local/bin` with admin prompt.

**Cursor's reasoning (likely):**
1. ✅ **Consistency** - Works on ALL Macs (homebrew is optional)
2. ✅ **Simplicity** - One path, one flow, no detection logic
3. ✅ **Predictable** - Same UX for everyone
4. ✅ **Universal** - Works even if user uninstalls homebrew
5. ✅ **Industry standard** - Docker, VS Code, etc. do the same

**Trade-off:**
- Cursor: Asks admin from EVERYONE for predictability
- Us: Avoid admin for 90% (homebrew users), warn the other 10%

### Comparison with Our Approach

**Our DMG strategy:**
1. Try `/opt/homebrew/bin` or `/usr/local/bin` (works for homebrew users - NO admin)
2. Fall back to `~/bin` with PATH warning

**Why this is smart:**
- 90% of developers have homebrew → no admin needed
- 10% get `~/bin` + PATH warning → acceptable for v1.0
- Simpler implementation
- Matches "zero manual steps" goal for majority

**Key Product Decision Difference:**
- **Cursor:** "Works for everyone, ask admin upfront" (100% success rate, 100% admin prompt)
- **Contextify:** "Works for most, graceful fallback for rest" (90% no prompt, 10% PATH warning)

**Recommendation:** Keep current approach for v1.0. Our PATH warning UI handles the edge case gracefully. Cursor's choice validates that requesting admin is acceptable UX for professional tools, but optimizing for the common case (homebrew users) is also valid.

---

## Technical Details

See **analysis.md** for:
- Full installation flow breakdown
- Directory ownership explanation
- Comparison of `/usr/local/bin` vs `~/bin`
- Our implementation analysis
- Recommendations for future versions

---

## Screenshots

To copy screenshots to this directory, run:
```bash
/tmp/copy-screenshots.sh
```

Or manually copy from Desktop/Screenshots with these names:
- `01-initial-setup.png` (Screenshot 2025-12-15 at 10.03.33 AM.png)
- `02-admin-warning.png` (Screenshot 2025-12-15 at 10.03.38 AM.png)
- `03-password-prompt.png` (Screenshot 2025-12-15 at 10.03.49 AM.png)
- `04-success.png` (Screenshot 2025-12-15 at 10.03.54 AM.png)
