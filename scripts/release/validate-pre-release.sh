#!/bin/bash
# Validate pre-release requirements
# Usage: ./scripts/release/validate-pre-release.sh X.Y.Z

set -e

VERSION="${1}"
FAILED=0

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z"
  exit 1
fi

echo "=========================================="
echo "Pre-Release Validation for v${VERSION}"
echo "=========================================="
echo ""

# Check 1: Tests pass
echo "1. Running tests..."
if swift test > /tmp/test-output.txt 2>&1; then
  TEST_COUNT=$(grep -E "Executed [0-9]+ tests?" /tmp/test-output.txt | tail -1 | grep -oE "[0-9]+" || true)
  echo "   PASS: All tests passed (${TEST_COUNT:-unknown} tests)"
else
  echo "   FAIL: Tests failed"
  FAILED=1
fi
echo ""

# Check 2: Build warnings
echo "2. Checking build warnings..."
WARNING_COUNT=$(bash scripts/xc.sh build 2>&1 | grep -c "warning:" || true)
if [ "$WARNING_COUNT" -eq 0 ]; then
  echo "   PASS: No warnings"
else
  echo "   FAIL: ${WARNING_COUNT} warnings found"
  FAILED=1
fi
echo ""

# Check 3: Working directory clean
echo "3. Checking working directory..."
if [ -z "$(git status --porcelain)" ]; then
  echo "   PASS: Working directory clean"
else
  echo "   FAIL: Uncommitted changes present"
  git status --short
  FAILED=1
fi
echo ""

# Check 4: P0 blockers
echo "4. Checking P0 blockers..."
P0_COUNT=$(grep -c "\[ \] #P0" TODOS.md || true)
if [ "$P0_COUNT" -eq 0 ]; then
  echo "   PASS: No incomplete P0 items"
else
  echo "   WARN: ${P0_COUNT} incomplete P0 items"
  grep "\[ \] #P0" TODOS.md | head -5
fi
echo ""

# Check 5: Version in Xcode
echo "5. Checking Xcode version..."
XCODE_VERSION=$(grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
if [ "$XCODE_VERSION" = "$VERSION" ]; then
  echo "   PASS: Xcode version matches (${XCODE_VERSION})"
else
  echo "   INFO: Xcode version is ${XCODE_VERSION}, release is ${VERSION}"
fi
echo ""

# Summary
echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: All critical checks passed"
  echo "Ready to proceed to Phase 2: Build"
  exit 0
else
  echo "RESULT: Some checks failed"
  echo "Address issues before proceeding"
  exit 1
fi
