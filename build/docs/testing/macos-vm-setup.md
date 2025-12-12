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

Get the macOS 15 (Sequoia) IPSW restore image (~13GB):

1. Visit https://ipsw.me/
2. Select "Mac" → Your Mac model (or generic "Mac")
3. Download macOS 15.x (Sequoia) IPSW

**Alternative:** Use `mist` CLI:
```bash
brew install mist
mist download firmware "macOS Sequoia" --output ~/Downloads/
```

### Step 3: Create VM in UTM

1. Open UTM
2. Click "+" → "Virtualize" → "macOS"
3. Select the downloaded IPSW file
4. Configure resources:
   - **RAM:** 4GB minimum (8GB recommended)
   - **CPU Cores:** 2 minimum (4 recommended)
   - **Disk:** 60GB minimum (80GB recommended)
5. Click "Save" and start the VM

### Step 4: Complete macOS Setup

1. Boot the VM (first boot takes several minutes)
2. Complete macOS setup wizard:
   - Skip Apple ID (not needed for testing)
   - Create local account (e.g., "QA Tester")
   - Skip all optional features
3. Install Xcode Command Line Tools (for Claude Code):
   ```bash
   xcode-select --install
   ```

---

## Installing Contextify on VM

### Option A: DMG Build (Recommended for QA)

1. On host Mac, build the DMG:
   ```bash
   bash scripts/xc.sh build
   # Or for release DMG:
   bash scripts/build-release.sh --dmg-only
   ```

2. Copy DMG to VM:
   - Use UTM's shared folder feature, OR
   - Use AirDrop between host and VM, OR
   - Copy via USB drive

3. On VM, open DMG and drag Contextify to Applications

### Option B: Direct Build in VM

If you need to test Xcode builds on older macOS:

1. Install Xcode on VM (requires Apple ID)
2. Clone repo: `git clone https://github.com/banagale/contextify`
3. Build: `bash scripts/xc.sh build`

---

## QA Test Cases

### Lite Mode Smoke Tests

Run these tests after installing Contextify on macOS 15 VM:

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| App launches | No crash, no dyld errors | |
| Status bar shows "Lite Mode" | Not "AI Unavailable" or crash | |
| Timeline displays | Shows entries with fallback content | |
| Fallback content format | "User: [label]" / "Assistant: [label]" | |
| Raw content preview | Shows first ~100 chars of message | |
| Project switching | Works normally | |
| Search (if available) | Returns results | |
| Settings opens | No crashes | |
| Lite Mode info modal | Appears on subsequent launch (if enabled) | |
| Console logs | No LLM-related errors or crashes | |

### Console Log Monitoring

While testing, monitor Console.app for errors:

1. Open Console.app on VM
2. Filter by: `process:Contextify`
3. Look for:
   - `[LLM-AVAILABILITY] Lite mode - macOS version < 26` (expected)
   - Any ERROR or CRASH entries (unexpected)

### Negative Tests

Verify these features are properly disabled:

| Feature | Expected in Lite Mode |
|---------|----------------------|
| Summary generation | Disabled (no queue polling) |
| "Copy Summary" menu | Hidden or shows fallback |
| Summary column | Hidden or shows placeholder |

---

## Troubleshooting

### VM Won't Boot

- Ensure IPSW matches your Mac architecture (Apple Silicon)
- Try re-downloading IPSW (may be corrupted)
- Allocate more RAM (minimum 4GB)

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

1. In UTM, right-click VM → "Snapshots"
2. Create "Clean Install" snapshot after setup
3. Create "Pre-Test" snapshot before each test session

This allows quick rollback if tests corrupt state.

---

## Alternative: Parallels/VMware

If UTM doesn't meet your needs:

- **Parallels Desktop:** Commercial, best macOS VM performance
- **VMware Fusion:** Free for personal use, good performance

Both support macOS 15 VMs on Apple Silicon.

---

## References

- UTM Documentation: https://docs.getutm.app/
- Apple Virtualization.framework: https://developer.apple.com/documentation/virtualization
- IPSW Downloads: https://ipsw.me/
- Mist CLI: https://github.com/ninxsoft/mist-cli
