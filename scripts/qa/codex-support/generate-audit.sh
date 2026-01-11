#!/bin/bash
# scripts/qa/codex-support/generate-audit.sh

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AUDIT="/tmp/total-recall-codex-audit-${TIMESTAMP}.md"

cat > "$AUDIT" << AUDIT
# Total Recall Codex Support - Release Audit

**Generated:** $(date -Iseconds)
**CLI Version:** $(contextify-query --version 2>&1)

---

## Files Changed

$(git diff --name-only HEAD~1 2>/dev/null || echo "Run from git repository")

## Validation Results

$(cat /tmp/total-recall-codex-validation-*.md 2>/dev/null | tail -50 || echo "No automated validation found")

## Installation State

### Claude Code
$(ls -la ~/.claude/skills/total-recall/ 2>/dev/null || echo "Not installed")

### Codex CLI
$(ls -la ~/.codex/skills/total-recall/ 2>/dev/null || echo "Not installed")

### Plugin Manifest
$(cat ~/.claude/plugins/installed_plugins.json 2>/dev/null | jq '.plugins["query@contextify"]' || echo "No manifest")

---

## Checklist

- [ ] Automated validation passed
- [ ] Manual QA completed
- [ ] Documentation updated
- [ ] Homebrew formula ready
- [ ] Release tagged

AUDIT

echo "Audit report: $AUDIT"
