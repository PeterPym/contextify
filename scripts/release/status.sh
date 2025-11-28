#!/bin/bash
# Show release status
# Usage: ./scripts/release/status.sh [X.Y.Z]

VERSION="${1}"

echo "=========================================="
echo "Contextify Release Status"
echo "=========================================="
echo ""

# If no version specified, show manifest summary
if [ -z "$VERSION" ]; then
  if [ -f "releases/manifest.json" ]; then
    echo "Current release from manifest:"
    CURRENT=$(cat releases/manifest.json | grep -o '"current_version": "[^"]*"' | cut -d'"' -f4)
    echo "  Version: $CURRENT"
    echo ""

    echo "All releases:"
    grep -E '"[0-9]+\.[0-9]+\.[0-9]+":' releases/manifest.json | sed 's/[",:]//g' | while read ver; do
      echo "  - v$ver"
    done
    echo ""
    echo "For details: $0 <version>"
  else
    echo "No manifest.json found."
    echo "Initialize a release with: ./scripts/release/init.sh X.Y.Z"
  fi
  exit 0
fi

# Show specific version status
RELEASE_DIR="releases/v${VERSION}"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Release v${VERSION} not found."
  echo "Available releases:"
  ls -d releases/v* 2>/dev/null | sed 's/releases\//  /'
  exit 1
fi

echo "Release: v${VERSION}"
echo "Directory: $RELEASE_DIR"
echo ""

# Parse release.json for status
if [ -f "$RELEASE_DIR/release.json" ]; then
  echo "Phase Status:"
  echo "-------------------------------------------"

  # Extract phase statuses (simple grep approach)
  for phase in pre_release build review_materials submission marketing post_release; do
    STATUS=$(grep -A2 "\"$phase\":" "$RELEASE_DIR/release.json" | grep '"status"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
    PHASE_DISPLAY=$(echo "$phase" | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')
    printf "  %-20s %s\n" "$PHASE_DISPLAY:" "${STATUS:-unknown}"
  done

  echo ""
  echo "Git:"
  TAG=$(grep '"tag"' "$RELEASE_DIR/release.json" | head -1 | grep -o '"v[^"]*"' | tr -d '"')
  COMMIT=$(grep '"commit"' "$RELEASE_DIR/release.json" | head -1 | grep -o '"[a-f0-9]*"' | tr -d '"')
  echo "  Tag: ${TAG:-not set}"
  echo "  Commit: ${COMMIT:-not set}"

  echo ""
  echo "Recent Notes:"
  grep -A1 '"note":' "$RELEASE_DIR/release.json" | grep '"note"' | tail -3 | while read line; do
    NOTE=$(echo "$line" | grep -o '"[^"]*"$' | tr -d '"')
    echo "  - $NOTE"
  done
else
  echo "No release.json found"
fi

echo ""
echo "Checklists:"
for checklist in "$RELEASE_DIR/checklists/"*.md; do
  if [ -f "$checklist" ]; then
    NAME=$(basename "$checklist")
    TOTAL=$(grep -c "^\- \[" "$checklist" || echo "0")
    DONE=$(grep -c "^\- \[x\]" "$checklist" || echo "0")
    printf "  %-25s %s/%s complete\n" "$NAME" "$DONE" "$TOTAL"
  fi
done

echo ""
echo "Commands:"
echo "  Validate pre-release: ./scripts/release/validate-pre-release.sh $VERSION"
echo "  Validate build:       ./scripts/release/validate-build.sh $VERSION"
