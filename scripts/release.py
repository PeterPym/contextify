#!/usr/bin/env python3
"""
Release automation for Contextify - adapted from FileKitty's release.py

One-shot release helper that:
  • bumps version in Xcode project
  • tags & pushes (git)
  • builds (Release configuration)
  • signs & notarizes (via sign_and_notarize.py)
  • creates SHA256 checksum
  • uploads release (gh CLI)

Requirements: git, gh (logged-in), bash, python3

Usage:
  Interactive mode (prompts for version):
    python3 scripts/release.py

  Non-interactive mode (fully automated):
    python3 scripts/release.py --version 1.0.1 --yes

  Dry run (preview what would happen):
    python3 scripts/release.py --version 1.0.1 --dry-run

  Skip notarization (faster testing):
    python3 scripts/release.py --version 1.0.1 --yes --no-notarize

  Allow uncommitted changes:
    python3 scripts/release.py --allow-dirty
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

# --- Paths & constants -------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]
XCODE_PROJECT = ROOT / "Contextify/Contextify.xcodeproj/project.pbxproj"
DIST = ROOT / "dist"
DMG_TEMPLATE = "Contextify-{ver}.dmg"
REPO = "banagale/contextify"
REQUIRED_TOOLS = ["git", "gh", "bash", "shasum"]


# --- Utility wrappers --------------------------------------------------------
def run(cmd: list[str] | str, *, capture: bool = True, check: bool = True, cwd: Path | None = None) -> str:
    """Run a command and return stdout."""
    if isinstance(cmd, str):
        cmd = cmd.split()
    try:
        res = subprocess.run(
            cmd,
            check=check,
            capture_output=capture,
            text=True,
            cwd=str(cwd) if cwd else None
        )
        return res.stdout.strip() if res.stdout else ""
    except subprocess.CalledProcessError as e:
        print(f"\n✖ Command failed: {' '.join(cmd)}")
        if e.stdout:
            print(e.stdout)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
        sys.exit(1)


def ensure_tools() -> None:
    """Verify required CLI tools are installed."""
    missing = [t for t in REQUIRED_TOOLS if shutil.which(t) is None]
    if missing:
        print("✖ Missing required tools:", ", ".join(missing))
        sys.exit(1)


# --- Version helpers ---------------------------------------------------------
def current_xcode_version() -> str:
    """Extract MARKETING_VERSION from Xcode project."""
    if not XCODE_PROJECT.exists():
        sys.exit(f"✖ Xcode project not found: {XCODE_PROJECT}")

    text = XCODE_PROJECT.read_text()
    # Look for MARKETING_VERSION = "1.0.0"; pattern
    match = re.search(r'MARKETING_VERSION = "?([0-9]+\.[0-9]+\.[0-9]+)"?;', text)
    if not match:
        sys.exit("✖ Could not find MARKETING_VERSION in Xcode project")
    return match.group(1)


def latest_git_tag() -> str | None:
    """Get the latest version tag from git."""
    out = run(["git", "tag", "--list", "v*", "--sort=-v:refname"])
    tag = out.splitlines()[0] if out else None
    return tag[1:] if tag and tag.startswith("v") else tag


def bump_patch(ver: str) -> str:
    """Increment patch version (e.g., 1.0.0 -> 1.0.1)."""
    major, minor, patch = map(int, ver.split("."))
    return f"{major}.{minor}.{patch + 1}"


# --- Git helpers -------------------------------------------------------------
def git_has_changes(path: Path | None = None) -> bool:
    """Check if there are uncommitted changes."""
    cmd = ["git", "diff", "--quiet"]
    if path:
        cmd.extend(["--", str(path)])
    return run(cmd, check=False) != ""


def git_add_commit_push(path: Path, msg: str) -> None:
    """Add, commit, and push changes to a file."""
    if git_has_changes(path):
        run(["git", "add", str(path)])
        run(["git", "commit", "-m", msg])
        run(["git", "push"])
        print(f"✔ Git commit: {msg}")
    else:
        print("✔ No changes to commit.")


# --- Release steps -----------------------------------------------------------
def set_xcode_version(new: str) -> None:
    """Update MARKETING_VERSION in Xcode project."""
    text = XCODE_PROJECT.read_text()
    # Replace all occurrences of MARKETING_VERSION
    new_text = re.sub(
        r'(MARKETING_VERSION = )"?[0-9]+\.[0-9]+\.[0-9]+"?;',
        rf'\1"{new}";',
        text
    )
    XCODE_PROJECT.write_text(new_text)
    git_add_commit_push(XCODE_PROJECT, f"chore(release): bump version to {new}")


def create_tag(ver: str) -> None:
    """Create and push a git tag."""
    tag = f"v{ver}"
    if tag in run(["git", "tag"]).split():
        print(f"✔ Tag {tag} already exists")
        return
    run(["git", "tag", tag])
    run(["git", "push", "origin", tag])
    print(f"✔ Pushed tag {tag}")


def build_release() -> None:
    """Build Contextify in Release configuration."""
    print("🔨 Building Release configuration...")
    run(["bash", "scripts/xc.sh", "Release", "build"], cwd=ROOT, capture=False)
    print("✔ Built Contextify.app")


def sign_and_notarize(skip_notarize: bool = False) -> None:
    """Sign and notarize the app."""
    print("🔏 Signing and creating DMG...")
    cmd = ["python3", "scripts/sign_and_notarize.py"]
    if skip_notarize:
        cmd.append("--no-notarize")
    run(cmd, cwd=ROOT, capture=False)
    print("✔ DMG created and signed")


def write_sha_file(dmg_path: Path) -> Path:
    """Generate SHA256 checksum file."""
    digest = run(["shasum", "-a", "256", str(dmg_path)]).split()[0]
    sha_path = dmg_path.with_suffix(".dmg.sha256")
    sha_path.write_text(f"{digest}  {dmg_path.name}\n")
    print(f"✔ sha256 → {sha_path.name}")
    return sha_path


def gh_release(ver: str, dmg_path: Path, sha_path: Path, notes: str) -> None:
    """Create GitHub release and upload artifacts."""
    tag = f"v{ver}"
    size_mb = dmg_path.stat().st_size / (1024 * 1024)
    print(f"⏳ Uploading {dmg_path.name} ({size_mb:.1f} MB) to GitHub release… please wait.")

    run([
        "gh", "release", "create", tag,
        str(dmg_path),
        str(sha_path),
        "--title", f"Contextify {ver}",
        "--notes", notes,
        "--verify-tag"
    ])
    print("✔ GitHub release published")


# --- Main --------------------------------------------------------------------
def main() -> None:
    ensure_tools()

    ap = argparse.ArgumentParser(description="Contextify release automation")
    ap.add_argument("--dry-run", action="store_true", help="Simulate only, don't make changes")
    ap.add_argument("--no-notarize", action="store_true", help="Skip notarization (faster for testing)")
    ap.add_argument("--version", help="Version to release (e.g., 1.0.1). If not specified, prompts interactively")
    ap.add_argument("--yes", "-y", action="store_true", help="Skip all confirmation prompts (auto-confirm)")
    ap.add_argument("--allow-dirty", action="store_true", help="Allow uncommitted changes in working directory")
    args = ap.parse_args()

    print("🚀 Contextify Release Automation\n")

    # Check for uncommitted changes
    if git_has_changes() and not args.allow_dirty:
        print("⚠️  Warning: You have uncommitted changes.")
        if args.yes:
            print("Continuing anyway (--yes flag enabled)")
        else:
            ans = input("Continue anyway? [y/N] ").lower()
            if ans != "y":
                sys.exit(1)

    # Get current version state
    xcode_ver = current_xcode_version()
    tag_ver = latest_git_tag()

    print(f"Current Xcode version: {xcode_ver}")
    print(f"Latest git tag:        {tag_ver or '(none)'}")
    print()

    # Decide next version
    if args.version:
        # Version specified via argument
        next_ver = args.version
        # Validate version format
        if not re.match(r'^\d+\.\d+\.\d+$', next_ver):
            sys.exit(f"✖ Invalid version format: {next_ver} (expected: X.Y.Z)")
        print(f"Using specified version: {next_ver}")
    elif xcode_ver == tag_ver:
        next_default = bump_patch(xcode_ver)
        if args.yes:
            next_ver = next_default
            print(f"Auto-selecting next version: {next_ver}")
        else:
            ans = input(f"Next version [{next_default}]: ").strip()
            next_ver = ans or next_default
    else:
        print("⚠️  Version mismatch between Xcode and git tags.")
        if args.yes:
            next_ver = xcode_ver
            print(f"Using Xcode version: {next_ver}")
        else:
            ans = input(f"Proceed with Xcode version ({xcode_ver})? [y/N] ").lower()
            if ans != "y":
                sys.exit(1)
            next_ver = xcode_ver

    print(f"\n📦 Releasing version: {next_ver}")

    if args.dry_run:
        print("(dry-run) Would perform:")
        print(f"  1. Bump Xcode version to {next_ver}")
        print(f"  2. Create and push tag v{next_ver}")
        print("  3. Build Release configuration")
        print("  4. Sign and notarize DMG")
        print("  5. Upload to GitHub")
        return

    # Confirm before proceeding
    if not args.yes:
        ans = input("\nProceed with release? [y/N] ").lower()
        if ans != "y":
            print("Cancelled.")
            sys.exit(0)
    else:
        print("\n▶️  Auto-proceeding (--yes flag enabled)")

    # Execute release workflow
    print("\n" + "="*60)
    print("RELEASE WORKFLOW STARTING")
    print("="*60 + "\n")

    # Step 1: Update version
    if xcode_ver != next_ver:
        set_xcode_version(next_ver)
    else:
        print(f"✔ Version already set to {next_ver}")

    # Step 2: Create tag
    create_tag(next_ver)

    # Step 3: Build
    build_release()

    # Step 4: Sign and notarize
    sign_and_notarize(skip_notarize=args.no_notarize)

    # Step 5: Create checksum
    # sign_and_notarize.py creates Contextify.dmg, we rename to versioned name
    fresh_dmg = DIST / "Contextify.dmg"
    versioned_dmg = DIST / DMG_TEMPLATE.format(ver=next_ver)

    if fresh_dmg.exists():
        # Always prefer freshly built DMG over any existing versioned one
        if versioned_dmg.exists():
            versioned_dmg.unlink()  # Delete stale versioned DMG
        fresh_dmg.rename(versioned_dmg)
        dmg_path = versioned_dmg
    elif versioned_dmg.exists():
        # Fall back to existing versioned DMG (resume scenario)
        dmg_path = versioned_dmg
    else:
        sys.exit(f"✖ DMG not found at {DIST}")

    sha_path = write_sha_file(dmg_path)

    # Step 6: Create GitHub release (disabled for now - using Dropbox archives)
    # TODO: Re-enable when ready to use GitHub Releases for distribution
    # release_notes = f"""Contextify {next_ver}
    #
    # ## Installation
    #
    # 1. Download `Contextify-{next_ver}.dmg`
    # 2. Open the DMG and drag Contextify.app to Applications
    # 3. Launch Contextify from Applications
    #
    # ## Verification
    #
    # SHA256: `{sha_path.read_text().split()[0]}`
    #
    # ## Changes
    #
    # See commit history for details.
    # """
    #
    # gh_release(next_ver, dmg_path, sha_path, release_notes)
    print("⏭️  Skipping GitHub release upload (disabled)")

    print("\n" + "="*60)
    print("✅ RELEASE COMPLETE!")
    print("="*60)
    print(f"\n📦 Version:  {next_ver}")
    print(f"🔗 Release:  https://github.com/{REPO}/releases/tag/v{next_ver}")
    print(f"💾 DMG:      {dmg_path}")
    print(f"🔒 SHA256:   {sha_path}")

    if args.no_notarize:
        print("\n⚠️  This release was NOT notarized.")
        print("    It will show Gatekeeper warnings on other Macs.")
        print("    Run without --no-notarize for production releases.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n✖ Interrupted")
        sys.exit(1)
