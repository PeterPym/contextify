#!/usr/bin/env python3
"""
Build, sign, harden, notarize, and package Contextify for distribution.

Adapted from FileKitty's sign_and_notarize.py for Contextify.

Usage:
    python3 scripts/sign_and_notarize.py              # Full signing + notarization
    python3 scripts/sign_and_notarize.py --no-sign     # Skip signing (DMG layout preview)
    python3 scripts/sign_and_notarize.py --no-notarize # Sign but don't notarize (faster testing)
    python3 scripts/sign_and_notarize.py --skip-cli    # Skip CLI signing (app only)

The script automatically checks if CLI sources have changed and rebuilds/signs
the standalone CLI for Homebrew distribution when needed.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
ROOT = Path(__file__).resolve().parents[1]  # project root
# DMG builds use .derived-dmg; allow override via environment for flexibility
DERIVED_ROOT = Path(os.environ.get("CONTEXTIFY_DERIVED_ROOT", ".derived-dmg"))
DERIVED = ROOT / DERIVED_ROOT / "Build/Products/Release"
DIST = ROOT / "dist"
BUILD = ROOT / "build"
STAGING = BUILD / "Contextify-Staging"

APP_BUNDLE = DERIVED / "Contextify.app"
LAUNCHER = APP_BUNDLE / "Contents/MacOS/Contextify"
DMG_PATH = DIST / "Contextify.dmg"

DMG_SETTINGS = ROOT / "build/assets/dmg/settings.json"
ENTITLEMENTS = ROOT / "Contextify/Contextify.entitlements"
NOTARY_PROFILE = "NotaryProfile"

# CLI signing script
CLI_SIGN_SCRIPT = ROOT / "scripts/sign_cli.sh"


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def run(
    cmd: Sequence[str] | str,
    *,
    check: bool = True,
    capture: bool = False,
    cwd: None | Path = None,
) -> subprocess.CompletedProcess[str]:
    if isinstance(cmd, str):
        cmd = [cmd]
    print("$", " ".join(map(str, cmd)))
    return subprocess.run(
        [str(c) for c in cmd],
        check=check,
        text=True,
        capture_output=capture,
        cwd=str(cwd) if cwd else None,
    )


def developer_id_hash() -> str:
    cmd = "security find-identity -p codesigning -v | awk '/Developer ID Application/ {print $2; exit}'"
    h = subprocess.check_output(["sh", "-c", cmd], text=True).strip()
    if not h:
        sys.exit("✖ Developer-ID certificate not found.")
    return h


CERT_ID = developer_id_hash()


def is_macho(path: Path) -> bool:
    try:
        return "Mach-O" in subprocess.check_output(["file", "-b", str(path)], text=True)
    except subprocess.CalledProcessError:
        return False


# --------------------------------------------------------------------------- #
# Signing helpers
# --------------------------------------------------------------------------- #
def sign_binaries_inside_out(app: Path) -> None:
    if not ENTITLEMENTS.exists():
        sys.exit(f"✖ Missing entitlements: {ENTITLEMENTS}")

    binaries = sorted(
        (p for p in app.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p)),
        key=lambda p: len(p.parts),
        reverse=True,
    )

    if not binaries:
        print("⚠️  No Mach-O binaries found to sign")
        return

    print(f"🔏 Signing {len(binaries)} binaries...")
    for bin_path in binaries:
        cmd = ["codesign", "--force", "--options", "runtime", "--timestamp"]
        if bin_path == LAUNCHER:
            cmd += ["--entitlements", str(ENTITLEMENTS)]
        cmd += ["--sign", CERT_ID, str(bin_path)]
        run(cmd)


def sign_outer_bundle(app: Path) -> None:
    print(f"🔏 Signing outer bundle: {app.name}")
    run(
        [
            "codesign",
            "--force",
            "--options",
            "runtime",
            "--timestamp",
            "--entitlements",
            str(ENTITLEMENTS),
            "--sign",
            CERT_ID,
            str(app),
        ]
    )


def verify_local_signature(app: Path, strict: bool = True) -> None:
    print(f"✅ Verifying signature: {app.name}")
    cmd = ["codesign", "--verify"]
    if strict:
        cmd.extend(["--deep", "--strict"])
    cmd.extend(["-vv", str(app)])
    run(cmd)


def gatekeeper_warn_only(app: Path) -> None:
    res = run(["spctl", "-vvv", "--assess", "--type", "exec", str(app)], check=False, capture=True)
    print("🔒 Gatekeeper:", "accepted" if res.returncode == 0 else "rejected (pre-notarization)")


# --------------------------------------------------------------------------- #
# CLI Signing (Homebrew distribution)
# --------------------------------------------------------------------------- #
def sign_cli_for_homebrew(*, skip_notarize: bool) -> bool:
    """
    Build and sign the standalone CLI for Homebrew distribution.

    Calls scripts/sign_cli.sh which handles:
    - Change detection (only rebuilds if CLI sources changed)
    - Swift build
    - Developer ID signing
    - Notarization (unless skipped)
    - Packaging for Homebrew

    Returns True on success, False on failure.
    Exit codes from sign_cli.sh:
      0  - Success
      10 - No rebuild needed (cached build is current)
      1-5 - Various failures (build, sign, notarize, package, prereqs)
    """
    if not CLI_SIGN_SCRIPT.exists():
        print(f"⚠️  CLI sign script not found: {CLI_SIGN_SCRIPT}")
        return False

    print()
    print("=" * 70)
    print("🔧 CLI Signing (Homebrew Distribution)")
    print("=" * 70)
    print()

    cmd = ["bash", str(CLI_SIGN_SCRIPT)]
    if skip_notarize:
        cmd.append("--no-notarize")

    result = subprocess.run(cmd, cwd=str(ROOT))

    if result.returncode == 0:
        print()
        print("✅ CLI signed successfully")
        return True
    elif result.returncode == 10:
        print()
        print("✅ CLI unchanged, using cached build")
        return True
    else:
        print()
        print(f"✖ CLI signing failed (exit code {result.returncode})")
        return False


# --------------------------------------------------------------------------- #
# Staging & DMG
# --------------------------------------------------------------------------- #
def ditto_copy(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    print(f"📦 Copying {src.name} to staging...")
    run(["ditto", "--rsrc", "--extattr", "--acl", str(src), str(dst)])


def load_dmg_settings() -> dict:
    if not DMG_SETTINGS.exists():
        sys.exit(f"✖ DMG settings not found: {DMG_SETTINGS}")
    with DMG_SETTINGS.open() as fp:
        return json.load(fp)


def replace_applications_symlink(dmg_path: Path, settings: dict) -> None:
    """Replace the Applications symlink with a Finder alias.

    Finder aliases inherit their target's icon (the blue Applications folder),
    while symlinks show a generic dashed rectangle. This post-processes the DMG
    to swap the symlink for an alias.
    """
    print("🔄 Replacing Applications symlink with Finder alias...")

    # Convert compressed DMG to read-write
    rw_dmg = dmg_path.with_suffix(".rw.dmg")
    if rw_dmg.exists():
        rw_dmg.unlink()
    run(["hdiutil", "convert", str(dmg_path), "-format", "UDRW", "-o", str(rw_dmg)])

    # Mount read-write DMG
    result = subprocess.run(
        ["hdiutil", "attach", str(rw_dmg), "-readwrite", "-noautoopen", "-noverify"],
        capture_output=True, text=True, check=True,
    )
    # Parse mount point from hdiutil output (last column of last line)
    mount_point = None
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            mount_point = parts[-1].strip()
    if not mount_point or not Path(mount_point).is_dir():
        sys.exit(f"✖ Could not determine mount point from: {result.stdout}")

    try:
        app_link = Path(mount_point) / "Applications"

        # Remove existing symlink
        if app_link.is_symlink() or app_link.exists():
            app_link.unlink()

        # Create Finder alias to /Applications using osascript
        script = f'''
            tell application "Finder"
                make new alias file at POSIX file "{mount_point}" to POSIX file "/Applications"
            end tell
        '''
        subprocess.run(["osascript", "-e", script], check=True,
                       capture_output=True, text=True)

        # Verify the alias was created
        alias_path = Path(mount_point) / "Applications"
        if not alias_path.exists():
            sys.exit("✖ Failed to create Finder alias for Applications")

        # Set the Applications folder icon on the alias
        # macOS Tahoe (26) no longer renders symlink/alias target icons automatically
        icon_script = f'''
            use framework "AppKit"
            set ws to current application's NSWorkspace's sharedWorkspace()
            set iconPath to "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
            set theIcon to current application's NSImage's alloc()'s initWithContentsOfFile:iconPath
            set result to (ws's setIcon:theIcon forFile:"{alias_path}" options:0)
            return result as boolean
        '''
        icon_result = subprocess.run(
            ["osascript", "-l", "AppleScript", "-e", icon_script],
            capture_output=True, text=True,
        )
        if icon_result.returncode == 0 and "true" in icon_result.stdout.lower():
            print(f"  ✓ Applications folder icon set")
        else:
            print(f"  ⚠ Could not set icon (will use default alias icon)")

        print(f"  ✓ Finder alias created at {mount_point}/Applications")
    finally:
        # Eject
        subprocess.run(["hdiutil", "detach", mount_point], check=True,
                       capture_output=True, text=True)

    # Convert back to compressed read-only
    dmg_path.unlink()
    run(["hdiutil", "convert", str(rw_dmg), "-format", "UDZO",
         "-imagekey", "zlib-level=9", "-o", str(dmg_path)])
    rw_dmg.unlink()


def create_dmg(settings: dict, *, skip_sign: bool, skip_notarize: bool) -> None:
    if DMG_PATH.exists():
        DMG_PATH.unlink()

    if STAGING.exists():
        shutil.rmtree(STAGING)
    STAGING.mkdir(parents=True)

    staged_app = STAGING / APP_BUNDLE.name
    ditto_copy(APP_BUNDLE, staged_app)

    if not skip_sign:
        sign_binaries_inside_out(staged_app)
        sign_outer_bundle(staged_app)
        # TODO: Use strict=True after Phase 1 (bundling resources properly)
        # Currently fails due to PythonVenv symlinks pointing outside bundle
        verify_local_signature(staged_app, strict=False)

    # Remove accidental "Applications" symlink (rare)
    applink = STAGING / "Applications"
    if applink.exists():
        applink.unlink()

    background_abs = (ROOT / settings["background"]).resolve()
    if not background_abs.exists():
        sys.exit(f"✖ Background PNG not found: {background_abs}")

    # -------------------------- create-dmg args --------------------------- #
    print(f"📀 Creating DMG: {DMG_PATH.name}")
    args: list[str] = [
        "create-dmg",
        "--volname",
        settings["title"],
        "--background",
        str(background_abs),
        "--window-size",
        str(settings["window"]["size"]["width"]),
        str(settings["window"]["size"]["height"]),
        "--icon-size",
        str(settings["icon-size"]),
    ]

    if "pos" in settings["window"]:
        args += ["--window-pos", str(settings["window"]["pos"]["x"]), str(settings["window"]["pos"]["y"])]

    for item in settings["contents"]:
        if item["type"] == "file" and Path(item["path"]).name.lower() != "applications":
            args += ["--icon", item["path"], str(item["x"]), str(item["y"])]
        elif item["type"] == "link" and item["path"] == "/Applications":
            args += ["--app-drop-link", str(item["x"]), str(item["y"])]

    # Don't pass --codesign/--notarize to create-dmg; we handle them after
    # post-processing the DMG (replacing symlink with Finder alias).
    args += [str(DMG_PATH), str(STAGING)]

    # Run from ROOT to resolve relative paths correctly
    run(args, cwd=ROOT)

    # Replace Applications symlink with Finder alias (shows proper folder icon)
    replace_applications_symlink(DMG_PATH, settings)

    # Codesign and notarize the final DMG
    if not skip_sign:
        print("🔏 Codesigning DMG...")
        run(["codesign", "-s", CERT_ID, str(DMG_PATH)])
        run(["codesign", "--verify", "--verbose=2", str(DMG_PATH)])
    if not skip_sign and not skip_notarize:
        print("📦 Notarizing DMG (this may take a few minutes)...")
        run(["xcrun", "notarytool", "submit", str(DMG_PATH),
             "--keychain-profile", NOTARY_PROFILE, "--wait"])
        print("📎 Stapling notarization ticket...")
        run(["xcrun", "stapler", "staple", str(DMG_PATH)])


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-sign", action="store_true", help="Skip code-signing")
    ap.add_argument("--no-notarize", action="store_true", help="Skip notarization")
    ap.add_argument("--skip-cli", action="store_true", help="Skip CLI signing for Homebrew")
    return ap.parse_args()


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main() -> None:
    print(f"🚀 Contextify Sign & Notarize")
    print(f"📂 Project root: {ROOT}")
    print(f"🔑 Certificate: {CERT_ID}")
    print()

    args = parse_args()

    if not APP_BUNDLE.exists():
        sys.exit(f"✖ Bundle not found: {APP_BUNDLE}\n"
                 f"   Run: bash scripts/xc.sh --dist=dmg Release build\n"
                 f"   Or build in Xcode with the 'Contextify' scheme (not 'Contextify AppStore')")

    DIST.mkdir(exist_ok=True)

    # Sign CLI for Homebrew distribution (before app signing)
    # This ensures CLI is always in sync with app releases
    if not args.skip_cli and not args.no_sign:
        if not sign_cli_for_homebrew(skip_notarize=args.no_notarize):
            sys.exit("✖ CLI signing failed - aborting build")
    elif args.skip_cli:
        print("⏭️  Skipping CLI signing (--skip-cli)")

    if not args.no_sign:
        sign_binaries_inside_out(APP_BUNDLE)
        sign_outer_bundle(APP_BUNDLE)
        verify_local_signature(APP_BUNDLE, strict=False)  # Less strict for source bundle with symlinks
        gatekeeper_warn_only(APP_BUNDLE)

    create_dmg(load_dmg_settings(), skip_sign=args.no_sign, skip_notarize=args.no_notarize)

    print()
    if not args.no_sign and not args.no_notarize:
        print("✅ DMG built, signed, notarized, stapled.")
        print(f"📦 {DMG_PATH}")
        print()
        print("Next steps:")
        print("  1. Test DMG on this machine: open dist/Contextify.dmg")
        print("  2. Test on fresh Mac to verify notarization")
        print("  3. Create GitHub release with: gh release create v1.0 dist/Contextify.dmg")
        if not args.skip_cli:
            print()
            print("CLI for Homebrew:")
            cli_tarball = BUILD / "cli-release" / f"contextify-query-{os.uname().machine}.tar.gz"
            if cli_tarball.exists():
                print(f"  4. Upload CLI: {cli_tarball}")
                sha_file = BUILD / "cli-release" / "sha256.txt"
                if sha_file.exists():
                    print(f"     SHA256: {sha_file.read_text().strip()}")
    elif not args.no_sign and args.no_notarize:
        print("✅ DMG built & signed (notarization skipped).")
        print(f"📦 {DMG_PATH}")
        print()
        print("⚠️  This DMG will show Gatekeeper warnings on other Macs.")
        print("    Run without --no-notarize to complete notarization.")
    else:
        print("✅ Unsigned DMG built for layout preview.")
        print(f"📦 {DMG_PATH}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n✖ Interrupted")
        sys.exit(1)
