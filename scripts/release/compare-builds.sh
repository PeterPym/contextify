#!/usr/bin/env bash
set -euo pipefail

SCRIPT_BUILD_RES=/tmp/script-build-resources.txt
SCRIPT_BUILD_HASHES=/tmp/script-build-hashes.txt
XCODE_BUILD_RES=/tmp/xcode-build-resources.txt
XCODE_BUILD_HASHES=/tmp/xcode-build-hashes.txt

cleanup() {
  rm -f "$SCRIPT_BUILD_RES" "$SCRIPT_BUILD_HASHES" "$XCODE_BUILD_RES" "$XCODE_BUILD_HASHES"
}
trap cleanup EXIT

printf '🧹 Cleaning build artifacts...\n'
rm -rf .derived-dmg

printf '🔨 Building via script...\n'
bash scripts/xc.sh --dist=dmg build

find .derived-dmg/Build/Products/Debug/Contextify.app/Contents/Resources \
  -type f | sort > "$SCRIPT_BUILD_RES"
find .derived-dmg/Build/Products/Debug/Contextify.app/Contents/Resources \
  -type f ! -name "*.plist" -exec shasum -a 256 {} \; | sort > "$SCRIPT_BUILD_HASHES"

printf '\n🧹 Cleaning for Xcode build...\n'
rm -rf .derived-dmg

cat <<'MSG'
⚠️  MANUAL STEP REQUIRED
   1. Open Contextify/Contextify.xcodeproj in Xcode
   2. Product → Clean Build Folder
   3. Product → Run (Cmd+R)
   4. Wait for the build to finish (app may launch)
When finished, return to this terminal and press Enter to continue...
MSG
read -r _

find .derived-dmg/Build/Products/Debug/Contextify.app/Contents/Resources \
  -type f | sort > "$XCODE_BUILD_RES"
find .derived-dmg/Build/Products/Debug/Contextify.app/Contents/Resources \
  -type f ! -name "*.plist" -exec shasum -a 256 {} \; | sort > "$XCODE_BUILD_HASHES"

printf '\n📊 Comparing resource lists...\n'
if diff "$SCRIPT_BUILD_RES" "$XCODE_BUILD_RES" >/dev/null; then
  printf '✅ Resource lists identical\n'
else
  printf '❌ Resource lists differ!\n'
  printf '\nFiles only in script build:\n'
  comm -23 "$SCRIPT_BUILD_RES" "$XCODE_BUILD_RES" || true
  printf '\nFiles only in Xcode build:\n'
  comm -13 "$SCRIPT_BUILD_RES" "$XCODE_BUILD_RES" || true
  exit 1
fi

printf '\n📊 Comparing resource hashes...\n'
if diff "$SCRIPT_BUILD_HASHES" "$XCODE_BUILD_HASHES" >/dev/null; then
  printf '✅ Resource hashes identical\n'
else
  printf '❌ Resource hashes differ!\n'
  diff "$SCRIPT_BUILD_HASHES" "$XCODE_BUILD_HASHES" || true
  exit 1
fi

printf '\n🎉 Build parity verified! Script and Xcode produce identical resources.\n'
