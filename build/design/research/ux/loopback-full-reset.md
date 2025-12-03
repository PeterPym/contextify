# Fully Resetting Rogue Amoeba Loopback Permissions

This guide describes how to completely reset Loopback to a fresh-install state, including all permissions dialogs (especially the ARK audio driver permissions).

## Why a Simple Reinstall Doesn't Work

Loopback stores state in multiple locations:
1. **App preferences** - User-level plist files
2. **TCC permissions** - macOS privacy database (Microphone, Screen Recording)
3. **ARK audio driver** - System-level HAL plugin that persists across app reinstalls
4. **Caches** - WebKit and app caches

Deleting the app and reinstalling only removes the app bundle. Everything else persists.

## Full Reset Procedure

### Step 1: Quit Loopback and Kill All Processes

```bash
killall Loopback loopbackd arkaudiod 2>/dev/null
```

### Step 2: Remove Preferences

```bash
rm -f ~/Library/Preferences/com.rogueamoeba.Loopback.plist
rm -f ~/Library/Preferences/com.rogueamoeba.loopbackd.plist
rm -f ~/Library/Preferences/com.rogueamoeba.arkaudiod.plist
```

### Step 3: Remove Caches

```bash
rm -rf ~/Library/Caches/com.rogueamoeba.Loopback
```

### Step 4: Flush Preference Daemon Cache

```bash
killall cfprefsd
```

### Step 5: Reset TCC Permissions (Requires App to Be Installed)

If Loopback is currently installed:

```bash
tccutil reset Microphone com.rogueamoeba.Loopback
tccutil reset ScreenCapture com.rogueamoeba.Loopback
tccutil reset Microphone com.rogueamoeba.arkaudiod
tccutil reset ScreenCapture com.rogueamoeba.arkaudiod
```

Note: These commands fail if the app isn't installed. Run them while the app is in /Applications.

### Step 6: Remove ARK Audio Driver (Requires sudo)

This is the critical step for seeing the ARK permissions dialog again:

```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/ARK.driver
```

### Step 7: Restart CoreAudio (Requires sudo)

After removing ARK, restart the audio subsystem:

```bash
sudo killall coreaudiod
```

CoreAudio will restart automatically.

### Step 8: Delete and Reinstall Loopback

1. Move Loopback.app to Trash
2. Empty Trash
3. Re-download or unarchive a fresh copy to /Applications

### Step 9: Launch Loopback

Launch Loopback. You should now see:
- Welcome wizard
- ARK driver installation prompt
- Permission dialogs (Microphone, Screen Recording)

## One-Liner Script (Partial)

This handles everything except the sudo commands:

```bash
killall Loopback loopbackd arkaudiod 2>/dev/null; \
rm -f ~/Library/Preferences/com.rogueamoeba.Loopback.plist \
      ~/Library/Preferences/com.rogueamoeba.loopbackd.plist \
      ~/Library/Preferences/com.rogueamoeba.arkaudiod.plist; \
rm -rf ~/Library/Caches/com.rogueamoeba.Loopback; \
killall cfprefsd; \
tccutil reset Microphone com.rogueamoeba.Loopback 2>/dev/null; \
tccutil reset ScreenCapture com.rogueamoeba.Loopback 2>/dev/null; \
tccutil reset Microphone com.rogueamoeba.arkaudiod 2>/dev/null; \
tccutil reset ScreenCapture com.rogueamoeba.arkaudiod 2>/dev/null; \
echo "Done. Now run: sudo rm -rf /Library/Audio/Plug-Ins/HAL/ARK.driver && sudo killall coreaudiod"
```

## Notes

- The ARK driver is shared by all Rogue Amoeba apps (Loopback, Audio Hijack, SoundSource). Removing it affects all of them.
- After removing ARK, any Rogue Amoeba app you launch will reinstall it and prompt for permissions.
- TCC resets only work when the bundle identifier is known to the system (app must be installed).

## Tested On

- macOS 26 (Tahoe)
- Loopback 2.x
- December 2025
