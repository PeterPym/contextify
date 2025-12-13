# macOS VM Setup Guide

**Purpose:** Set up virtual machines for testing Contextify on older macOS versions.
**Primary Use Case:** Testing Lite Mode on macOS 15 (Sequoia) before merging `#LEGACY-MACOS` feature.

---

## Overview

Contextify targets macOS 15+ with "Lite Mode" for users without Apple Intelligence (macOS 26+). VM testing validates:

1. App launches without dyld crashes (proves `#if canImport(FoundationModels)` guards work)
2. Lite mode UI displays correctly
3. Core features work (timeline, indexing, search)
4. No LLM-related crashes in Console

---

## Prerequisites

- Mac with Apple Silicon (M1/M2/M3/M4)
- macOS 13+ on host (for Virtualization.framework)
- ~80GB free disk space (VM + IPSW)
- 30-60 minutes for initial setup

---

## VM Setup with UTM

UTM is the recommended free VM solution. It uses Apple's Virtualization.framework for near-native performance on Apple Silicon.

### Step 1: Install UTM

```bash
brew install --cask utm
```

Or download from: https://mac.getutm.app/

### Step 2: Download macOS IPSW

Get the macOS 15 (Sequoia) IPSW restore image (~17GB):

**Option A: Use `mist` CLI (recommended)**
```bash
brew install mist-cli
# List available versions
mist list firmware "macOS Sequoia" --compatible
# Download latest signed Sequoia
mist download firmware "macOS Sequoia" --compatible -o ~/Downloads/
```

This downloads `UniversalMac_15.x.x_xxxxx_Restore.ipsw` to ~/Downloads/

**Option B: Manual download**
1. Visit https://ipsw.me/
2. Select "Mac" -> macOS Sequoia
3. Choose a version marked as "Signed" (Apple still accepts it)
4. Download to ~/Downloads/

**Note:** IPSW files are hosted by Apple on their CDN. Both mist and ipsw.me just provide links to Apple's official URLs.

### Step 3: Create VM in UTM

1. Open UTM
2. Click "+" -> "Virtualize" -> "macOS"
3. Select the downloaded IPSW file
4. Configure resources:
   - **RAM:** 4GB minimum (8GB recommended)
   - **CPU Cores:** 2 minimum (4 recommended)
   - **Disk:** 60GB minimum (80GB recommended)
5. Click "Save" and start the VM

### Step 4: Complete macOS Setup

1. Boot the VM (first boot takes several minutes)
2. Complete macOS setup wizard:
   - **Internet:** Not required - skip or select "Other network options"
   - **Apple ID:** Skip (not needed for testing)
   - Create local account (e.g., "QA Tester")
   - Skip all optional features
3. No need to install Xcode or CLI tools for basic testing

---

## Transferring Files to VM

### Option A: Shared Folder (Recommended)

1. **Stop the VM** (required to change settings)
2. Right-click VM -> "Edit"
3. Go to **Sharing** tab
4. Enable **Directory Sharing**
5. Set path to: `/Users/YOUR_USERNAME/Public/VMShare`
6. Start the VM
7. In VM Finder, the share appears under Locations

**On host, copy files:**
```bash
mkdir -p ~/Public/VMShare
cp /path/to/Contextify.app ~/Public/VMShare/
# Or create a DMG:
hdiutil create -volname "Contextify" -srcfolder Contextify.app -ov -format UDZO ~/Public/VMShare/Contextify.dmg
```

### Option B: Create DMG and Transfer

If shared folders don't work, create a DMG and use another transfer method:

```bash
# Build and package
bash scripts/xc.sh dev-archive
hdiutil create -volname "Contextify" \
  -srcfolder build/Contextify.xcarchive/Products/Applications/Contextify.app \
  -ov -format UDZO ~/Public/VMShare/Contextify-Test.dmg
```

---

## Seeding Test Transcripts

Fresh VMs have no Claude Code/Codex transcripts. Use the bootstrap script to seed test data:

**On the VM, run:**
```bash
# If shared folder is mounted at /Volumes/VMShare:
bash /Volumes/VMShare/vm-bootstrap.sh
```

This creates the expected folder structure and copies fixture transcripts so the app has projects to display.

See: `scripts/qa/vm-bootstrap.sh`

---

## Debugging on the VM

Logging scripts are included in VMShare for debugging issues:

**On the VM, to capture logs:**
```bash
# Run from shared folder (30 second capture by default)
bash /Volumes/VMShare/monitor-transcript-queues.sh

# Or longer capture
DURATION=60 bash /Volumes/VMShare/monitor-transcript-queues.sh
```

This captures all Contextify logs to `/tmp/transcript-queue-monitor-*.log`.

**Workflow:**
1. Start the monitor script
2. Launch Contextify and reproduce the issue
3. Press Ctrl+C to stop capture
4. Review logs in `/tmp/`

**Available scripts in VMShare:**
- `monitor-transcript-queues.sh` - Comprehensive log capture (all subsystems)
- `monitor-interactive.sh` - Interactive monitoring for specific subsystems

See `scripts/logging/README.md` for full documentation.

---

## QA Test Cases

See `build/docs/testing/lite-mode-qa-checklist.md` for the full 31-point checklist.

**Quick smoke test:**
1. Launch Contextify - should not crash
2. Status bar shows "Lite Mode"
3. Hover tooltip shows reason (e.g., "Requires macOS 26 (Tahoe) or later")
4. Click (i) for detailed explanation
5. Timeline shows fallback content (not AI summaries)

---

## Troubleshooting

### VM Won't Boot

- Ensure IPSW matches your Mac architecture (Apple Silicon)
- Try re-downloading IPSW (may be corrupted)
- Allocate more RAM (minimum 4GB)

### Shared Folder Not Visible

- Must stop VM (not pause) to change sharing settings
- In VM Finder: Go -> Connect to Server -> browse for share
- Try: Finder sidebar under "Locations"

### App Crashes on Launch (dyld)

This indicates `#if canImport(FoundationModels)` guards are not working:

1. Check build settings: `MACOSX_DEPLOYMENT_TARGET = 15.0`
2. Verify no direct FoundationModels imports outside guards
3. Check for weak linking issues

### Slow Performance

- Increase VM RAM to 8GB
- Increase CPU cores to 4
- Ensure host Mac is not under heavy load

---

## VM Snapshots

Create snapshots before testing to quickly reset:

1. In UTM, right-click VM -> "Snapshots"
2. Create "Clean Install" snapshot after setup
3. Create "Pre-Test" snapshot before each test session

This allows quick rollback if tests corrupt state.

---

## References

- UTM Documentation: https://docs.getutm.app/
- Apple Virtualization.framework: https://developer.apple.com/documentation/virtualization
- IPSW Downloads: https://ipsw.me/
- Mist CLI: https://github.com/ninxsoft/mist-cli
