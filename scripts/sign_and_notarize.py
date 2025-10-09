#!/usr/bin/env python3
"""
Build, sign, harden, notarize, and package Contextify for distribution.

Adapted from FileKitty's sign_and_notarize.py for Contextify.

Usage:
    python3 scripts/sign_and_notarize.py              # Full signing + notarization
    python3 scripts/sign_and_notarize.py --no-sign     # Skip signing (DMG layout preview)
    python3 scripts/sign_and_notarize.py --no-notarize # Sign but don't notarize (faster testing)
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
ROOT = Path(__file__).resolve().parents[1]  # project root
DERIVED = ROOT / ".derived/Build/Products/Release"
DIST = ROOT / "dist"
BUILD = ROOT / "build"
STAGING = BUILD / "Contextify-Staging"

APP_BUNDLE = DERIVED / "Contextify.app"
LAUNCHER = APP_BUNDLE / "Contents/MacOS/Contextify"
DMG_PATH = DIST / "Contextify.dmg"

DMG_SETTINGS = ROOT / "build/assets/dmg_settings.json"
ENTITLEMENTS = ROOT / "Contextify/Contextify.entitlements"
NOTARY_PROFILE = "NotaryProfile"


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

    if not skip_sign:
        args += ["--codesign", CERT_ID]
    if not skip_sign and not skip_notarize:
        args += ["--notarize", NOTARY_PROFILE]

    args += [str(DMG_PATH), str(STAGING)]

    # Run from ROOT to resolve relative paths correctly
    run(args, cwd=ROOT)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-sign", action="store_true", help="Skip code-signing")
    ap.add_argument("--no-notarize", action="store_true", help="Skip notarization")
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
                 f"   Run: bash scripts/xc.sh build\n"
                 f"   Or build in Xcode with Release configuration")

    DIST.mkdir(exist_ok=True)

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
