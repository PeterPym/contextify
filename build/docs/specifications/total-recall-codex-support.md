# Design Specification: Codex CLI Support for Total Recall Skill

**Status:** Draft
**Author:** Claude
**Date:** 2026-01-10
**Target Version:** contextify-query 1.1.0

---

## Executive Summary

This specification describes the changes needed to install the Total Recall skill for OpenAI Codex CLI in addition to Claude Code. The implementation must update the `contextify-query install-plugin` command, the Homebrew formula, and related documentation.

---

## Background & Context

### Historical Context

When Total Recall was implemented (late 2024), Codex CLI did not officially support agent skills. The skill system was experimental and undocumented. Consequently, the installation infrastructure only targeted Claude Code:

- Skill installed to: `~/.claude/skills/total-recall/SKILL.md`
- Plugin installed to: `~/.claude/plugins/cache/contextify/query/<version>/`
- Agent installed to: `~/.claude/plugins/cache/contextify/query/<version>/agents/contextify-researcher.md`

### Current State (January 2026)

OpenAI Codex CLI now officially supports skills via the [open agent skills specification](https://agentskills.io/specification):

- User skills at: `~/.codex/skills/<skill-name>/SKILL.md`
- Repo skills at: `.codex/skills/<skill-name>/SKILL.md`
- Skills enabled via: `codex --enable skills` (feature flag)

**Key finding:** Codex adopted the same SKILL.md format as Claude Code. The open agent skills specification provides a common standard that both tools follow.

### Critical Limitation: Codex Has No Task Tool

**Claude Code** has a built-in `Task` tool that allows skills to spawn subagents:
```
Task(subagent_type: "query:contextify-researcher", prompt: "...")
```

**Codex CLI does NOT have a native Task tool.** This means:
1. The `contextify-researcher` agent cannot be invoked by Codex
2. The "delegate to researcher" section in the skill template is harmless but non-functional in Codex
3. There is no need to install the agent file for Codex

**Source:** [Codex CLI documentation](https://developers.openai.com/codex/skills) and community implementations confirm Codex lacks native agent delegation.

---

## Technical Comparison: Claude Code vs Codex

### Skill Locations

| Scope | Claude Code | Codex CLI |
|-------|-------------|-----------|
| User-level | `~/.claude/skills/<name>/` | `~/.codex/skills/<name>/` |
| Repo-level | `.claude/skills/<name>/` | `.codex/skills/<name>/` |
| Admin-level | N/A | `/etc/codex/skills/<name>/` |

### SKILL.md Format

Both tools use the same format per the [agent skills specification](https://agentskills.io/specification):

```yaml
---
name: total-recall
description: Contextify Total Recall - Search past conversations...
---

# Skill instructions...
```

**Compatibility:** The existing `SKILL.md` file works for both Claude Code and Codex without modification.

### Agent/Subagent Support

| Feature | Claude Code | Codex CLI |
|---------|-------------|-----------|
| Native Task tool | Yes | No |
| Agent delegation | Yes (via Task) | No |
| Agent directory | `<plugin>/agents/` | N/A |
| Skills can invoke agents | Yes | No |

**Implication:** The `contextify-researcher.md` agent only benefits Claude Code users. Codex users get the basic skill but cannot delegate to the researcher agent for complex multi-query searches.

### Known Codex Limitation: Symlinks

Codex CLI explicitly ignores symlinked directories when loading skills. Files must be **copied** to the skill location, not symlinked.

**Source:** Prior conversation (entry_id=8ea0a0e2-3da3-4bef-a6b8-cf7c607cbf21)

---

## Proposed Changes

### 1. Update `install-plugin` Command

**File:** `Sources/ContextifyQueryCLI/main.swift`

**Current behavior (lines 1686-1754):**
- Installs user skill to `~/.claude/skills/total-recall/`
- Installs plugin to `~/.claude/plugins/cache/contextify/query/<version>/`

**Proposed changes:**

```swift
private func runInstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser

  // === EXISTING: Claude Code installation ===
  let claudeSkillsDir = home.appendingPathComponent(".claude/skills/total-recall")
  // ... existing Claude installation code ...

  // === NEW: Codex CLI installation ===
  // Always install unconditionally (harmless if Codex not used)
  if let userSkillSource = sources.userSkill {
    let codexSkillsDir = home.appendingPathComponent(".codex/skills/total-recall")
    try FileManager.default.createDirectory(at: codexSkillsDir, withIntermediateDirectories: true)

    let skillFile = userSkillSource.appendingPathComponent("SKILL.md")
    let codexSkillDest = codexSkillsDir.appendingPathComponent("SKILL.md")

    // Must COPY, not symlink (Codex ignores symlinks)
    if FileManager.default.fileExists(atPath: codexSkillDest.path) {
      try FileManager.default.removeItem(at: codexSkillDest)
    }
    try FileManager.default.copyItem(at: skillFile, to: codexSkillDest)
  }

  // ... rest of existing code ...
}
```

**Output message update:**
```swift
try ContextifyQueryCLI.printResponse(type: "pluginInstalled", data: payload, json: options.jsonOutput) {
  print("Contextify Total Recall installed!")
  print("  Claude Code: ~/.claude/skills/total-recall/")
  print("  Codex CLI:   ~/.codex/skills/total-recall/")
  print("")
  print("Restart your CLI tool, then use /total-recall to search history.")
}
```

### 2. Update `uninstall-plugin` Command

**File:** `Sources/ContextifyQueryCLI/main.swift` (lines 1756-1794)

**Add Codex cleanup:**

```swift
private func runUninstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser

  // === EXISTING: Remove Claude skill ===
  let claudeUserSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
  if FileManager.default.fileExists(atPath: claudeUserSkillDir.path) {
    try FileManager.default.removeItem(at: claudeUserSkillDir)
  }

  // === NEW: Remove Codex skill ===
  let codexUserSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
  if FileManager.default.fileExists(atPath: codexUserSkillDir.path) {
    try FileManager.default.removeItem(at: codexUserSkillDir)
  }

  // ... rest of existing code ...
}
```

### 3. Update Homebrew Formula Caveats

**File:** `/Users/rob/code/projects/homebrew-contextify/Formula/contextify-query.rb`

**Current caveats:**
```ruby
def caveats
  <<~EOS
    contextify-query has been installed.

    To enable Contextify skills in Claude Code, run:
      contextify-query install-plugin
    ...
  EOS
end
```

**Proposed caveats:**
```ruby
def caveats
  <<~EOS
    contextify-query has been installed.

    To enable Contextify Total Recall skill, run:
      contextify-query install-plugin

    This installs the skill for both:
      - Claude Code (~/.claude/skills/total-recall/)
      - Codex CLI (~/.codex/skills/total-recall/)

    Requires Contextify.app for database access.

    Verify installation:
      contextify-query status

    For more information:
      https://contextify.sh/docs/cli
  EOS
end
```

### 4. No Changes to SKILL.md (Compatibility Confirmed)

The existing `SKILL.md` is compatible with both tools. The "delegate to researcher" section is:
- **Functional** in Claude Code (Task tool available)
- **Harmless** in Codex (no Task tool, instructions ignored)

No modification needed. Users get degraded functionality in Codex (no multi-query delegation) but the core skill works.

### 5. Agent Installation (Claude Code Only)

The `contextify-researcher.md` agent continues to be installed only for Claude Code:
- **Location:** `~/.claude/plugins/cache/contextify/query/<version>/agents/`
- **Reason:** Codex has no mechanism to invoke agents

No changes needed to agent installation logic.

---

## Installation Matrix

| Component | Claude Code | Codex CLI |
|-----------|-------------|-----------|
| `~/.claude/skills/total-recall/SKILL.md` | Yes | N/A |
| `~/.codex/skills/total-recall/SKILL.md` | N/A | Yes (NEW) |
| `~/.claude/plugins/.../agents/contextify-researcher.md` | Yes | N/A |
| Plugin manifest update | Yes | N/A |

---

## Detection Strategy

**Decision:** Install to Codex unconditionally (user preference from design discussion).

**Rationale:**
- Harmless if Codex not installed (empty directory)
- Ready immediately when user installs Codex
- Simpler implementation (no detection logic)
- Consistent with "install once, works everywhere" philosophy

---

## User Experience

### After `contextify-query install-plugin`

```
Contextify Total Recall installed!
  Claude Code: ~/.claude/skills/total-recall/
  Codex CLI:   ~/.codex/skills/total-recall/

Restart your CLI tool, then use /total-recall to search history.
```

### In Claude Code

```
> /total-recall find authentication discussions

> **Contextify Total Recall**
>
> **Found:** Authentication implementation discussion from last week...
```

User can also delegate to researcher agent for complex searches.

### In Codex CLI

```
> /total-recall find authentication discussions

> **Contextify Total Recall**
>
> **Found:** Authentication implementation discussion from last week...
```

Note: Multi-query delegation (researcher agent) is not available. The skill works for single queries.

---

## Documentation Updates

### Files to Update

1. **`contextify-query/user-skill/total-recall/SKILL.md`**
   - Add note in preconditions: "Works with Claude Code and Codex CLI"
   - No functional changes needed

2. **`build/docs/guides/cli-installation.md`**
   - Add Codex CLI section
   - Mention skill location difference

3. **Homebrew README** (`homebrew-contextify/README.md`)
   - Update to mention Codex support
   - Add Codex troubleshooting section

4. **Website** (contextify.sh/docs/cli)
   - Add Codex CLI installation instructions
   - Note feature parity differences

---

## Implementation Plan

### Branch Strategy

**Branch name:** `feature/codex-skill-support`

**Base branch:** `main`

**Merge strategy:** Squash merge to main after validation passes

---

### Commit Sequence

| # | Commit Message | Files Changed |
|---|----------------|---------------|
| 1 | `feat(cli): add Codex skill installation support` | `Sources/ContextifyQueryCLI/main.swift` |
| 2 | `docs(cli): update installation guide for Codex` | `build/docs/guides/cli-installation.md` |
| 3 | `docs(skill): note Claude Code and Codex compatibility` | `contextify-query/user-skill/total-recall/SKILL.md` |
| 4 | `test(qa): add Codex support validation scripts` | `scripts/qa/codex-support/*.sh` |
| 5 | `docs(spec): add Codex support design specification` | `build/docs/specifications/total-recall-codex-support.md` |

**Post-merge (separate repos):**

| # | Repo | Commit Message |
|---|------|----------------|
| 6 | `homebrew-contextify` | `feat(formula): update caveats for Codex CLI support` |
| 7 | `homebrew-contextify` | `docs: add Codex CLI section to README` |

---

### Phase 1: Code Changes

**Commit 1:** `feat(cli): add Codex skill installation support`

**Files:**
- `Sources/ContextifyQueryCLI/main.swift`

**Changes:**
- Add Codex skill directory creation at `~/.codex/skills/total-recall/`
- Copy (not symlink) SKILL.md to Codex location
- Update success message to show both locations
- Add Codex cleanup to `uninstall-plugin`
- Bump `cliVersion` from `1.0.5` to `1.1.0`

---

### Phase 2: Documentation Updates

**Commit 2:** `docs(cli): update installation guide for Codex`

**Files:**
- `build/docs/guides/cli-installation.md`

**Changes:**
- Add "Codex CLI Support" section
- Document skill location difference
- Note feature parity (no agent delegation in Codex)

---

**Commit 3:** `docs(skill): note Claude Code and Codex compatibility`

**Files:**
- `contextify-query/user-skill/total-recall/SKILL.md`

**Changes:**
- Add note in preconditions: "Works with Claude Code and Codex CLI"

---

### Phase 3: Validation Infrastructure

**Commit 4:** `test(qa): add Codex support validation scripts`

**Files:**
- `scripts/qa/codex-support/clear-state.sh`
- `scripts/qa/codex-support/validate-install.sh`
- `scripts/qa/codex-support/generate-audit.sh`

**Changes:**
- State clearing script
- Automated validation with headless CLI tests
- Audit report generation

---

**Commit 5:** `docs(spec): add Codex support design specification`

**Files:**
- `build/docs/specifications/total-recall-codex-support.md`

**Changes:**
- Move spec from `/tmp/` to version control
- Final spec with all validation results

---

### Phase 4: Validation & Release

**4.1 Run automated validation suite**
```bash
./scripts/qa/codex-support/clear-state.sh
./scripts/qa/codex-support/validate-install.sh
```

**4.2 Run manual QA checklist** (see Manual QA section)

**4.3 Generate audit report**
```bash
./scripts/qa/codex-support/generate-audit.sh
```

**4.4 Merge to main**
```bash
git checkout main
git merge --squash feature/codex-skill-support
git commit -m "feat(cli): add Codex CLI skill support (#XX)"
```

**4.5 Tag release**
```bash
git tag -a v1.1.0 -m "Add Codex CLI skill support"
git push origin main --tags
```

---

### Phase 5: Homebrew Update (Post-Release)

**Commit 6:** `feat(formula): update caveats for Codex CLI support`

**Repo:** `homebrew-contextify`

**Files:**
- `Formula/contextify-query.rb`

**Changes:**
- Update version to 1.1.0
- Update SHA256 for new tarball
- Update caveats to mention Codex

---

**Commit 7:** `docs: add Codex CLI section to README`

**Repo:** `homebrew-contextify`

**Files:**
- `README.md`

**Changes:**
- Add Codex CLI section
- Update troubleshooting for dual-platform

---

## Automated Validation Suite

### Overview

Automated validation uses headless CLI execution to verify skill installation and functionality without human interaction. Reports are written to `/tmp/` for audit.

**Reference implementations:**
- `appstore-metadata/review-materials/generate-transcripts.sh` - Headless transcript generation
- `build/docs/specifications/transcript-formats.md` - CLI invocation patterns

**Headless execution patterns:**
| CLI | Non-interactive Flag | Permission Bypass |
|-----|---------------------|-------------------|
| Claude Code | `-p` (print mode) | `--dangerously-skip-permissions` |
| Codex CLI | `codex exec` | `--dangerously-bypass-approvals-and-sandbox` |

**Note:** Codex skills are gated behind `--enable-skills` flag.

### State Clearing (Pre-Validation)

Before each validation run, clear all prior state.

**SAFETY NOTES:**
- Script validates paths before deletion
- Only removes Contextify-specific directories (not parent dirs)
- Requires explicit confirmation unless `--force` flag provided
- Creates backup of manifest before modification

```bash
#!/bin/bash
# scripts/qa/codex-support/clear-state.sh
#
# Safely clears validation state for Total Recall Codex testing.
# Use --force to skip confirmation prompts.

set -e

FORCE=false
if [ "$1" = "--force" ]; then
  FORCE=true
fi

echo "=== Clearing validation state ==="

# Safety: validate we're removing expected paths only
CLAUDE_SKILL="$HOME/.claude/skills/total-recall"
CODEX_SKILL="$HOME/.codex/skills/total-recall"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/contextify"

# Confirm paths are under expected parent directories
validate_path() {
  local path="$1"
  local expected_parent="$2"
  if [[ "$path" != "$expected_parent"* ]]; then
    echo "ERROR: Path $path is not under $expected_parent - aborting"
    exit 1
  fi
}

validate_path "$CLAUDE_SKILL" "$HOME/.claude/"
validate_path "$CODEX_SKILL" "$HOME/.codex/"
validate_path "$PLUGIN_CACHE" "$HOME/.claude/"

# Show what will be removed
echo "Will remove:"
[ -d "$CLAUDE_SKILL" ] && echo "  - $CLAUDE_SKILL"
[ -d "$CODEX_SKILL" ] && echo "  - $CODEX_SKILL"
[ -d "$PLUGIN_CACHE" ] && echo "  - $PLUGIN_CACHE"

# Confirm unless --force
if [ "$FORCE" != "true" ]; then
  read -p "Proceed with removal? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# Remove installed skills (with path validation already done)
[ -d "$CLAUDE_SKILL" ] && rm -rf "$CLAUDE_SKILL"
[ -d "$CODEX_SKILL" ] && rm -rf "$CODEX_SKILL"

# Remove plugin cache
[ -d "$PLUGIN_CACHE" ] && rm -rf "$PLUGIN_CACHE"

# Backup and update plugin manifest (preserve other plugins)
MANIFEST="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$MANIFEST" ]; then
  # Create backup
  cp "$MANIFEST" "$MANIFEST.backup.$(date +%Y%m%d-%H%M%S)"
  # Remove only our entry
  jq 'del(.plugins["query@contextify"])' "$MANIFEST" > /tmp/manifest.tmp
  mv /tmp/manifest.tmp "$MANIFEST"
  echo "Manifest updated (backup created)"
fi

echo "State cleared successfully"
```

### Validation Script

```bash
#!/bin/bash
# scripts/qa/codex-support/validate-install.sh
#
# Automated validation for Total Recall Codex support
# Outputs report to /tmp/total-recall-codex-validation-<timestamp>.md

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="/tmp/total-recall-codex-validation-${TIMESTAMP}.md"

# Initialize report
cat > "$REPORT" << 'EOF'
# Total Recall Codex Support Validation Report

**Generated:** $(date -Iseconds)
**Validator:** automated

---

## Pre-Flight Checks

EOF

echo "=== Running validation suite ==="
echo "Report: $REPORT"

# Track pass/fail
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  echo "PASS: $1"
  echo "- [x] $1" >> "$REPORT"
  ((TESTS_PASSED++))
}

fail() {
  echo "FAIL: $1"
  echo "- [ ] **FAIL:** $1" >> "$REPORT"
  ((TESTS_FAILED++))
}

# === PRE-FLIGHT CHECKS ===

# Check contextify-query is available
if command -v contextify-query &> /dev/null; then
  VERSION=$(contextify-query --version 2>&1 || echo "unknown")
  pass "contextify-query found: $VERSION"
else
  fail "contextify-query not found in PATH"
  echo "Aborting validation" >> "$REPORT"
  exit 1
fi

# Check database exists
if contextify-query status --json 2>/dev/null | grep -q '"projectCount"'; then
  pass "Contextify database accessible"
else
  fail "Contextify database not found"
fi

echo "" >> "$REPORT"
echo "## Installation Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === CLEAR STATE ===
echo "Clearing prior state..."
rm -rf ~/.claude/skills/total-recall 2>/dev/null || true
rm -rf ~/.codex/skills/total-recall 2>/dev/null || true

# === TEST: Fresh Install ===
echo "Testing fresh install..."
if contextify-query install-plugin 2>&1 | grep -q "installed"; then
  pass "install-plugin completed successfully"
else
  fail "install-plugin failed"
fi

# === TEST: Claude skill exists ===
if [ -f ~/.claude/skills/total-recall/SKILL.md ]; then
  pass "Claude skill installed at ~/.claude/skills/total-recall/SKILL.md"
else
  fail "Claude skill NOT found at ~/.claude/skills/total-recall/SKILL.md"
fi

# === TEST: Codex skill exists ===
if [ -f ~/.codex/skills/total-recall/SKILL.md ]; then
  pass "Codex skill installed at ~/.codex/skills/total-recall/SKILL.md"
else
  fail "Codex skill NOT found at ~/.codex/skills/total-recall/SKILL.md"
fi

# === TEST: Not symlinked (Codex requirement) ===
if [ -L ~/.codex/skills/total-recall/SKILL.md ]; then
  fail "Codex skill is a symlink (Codex ignores symlinks!)"
else
  pass "Codex skill is a real file (not symlink)"
fi

# === TEST: Content matches ===
if diff -q ~/.claude/skills/total-recall/SKILL.md ~/.codex/skills/total-recall/SKILL.md > /dev/null 2>&1; then
  pass "Skill content identical in both locations"
else
  fail "Skill content differs between Claude and Codex locations"
fi

# === TEST: Idempotent reinstall ===
echo "Testing idempotent reinstall..."
if contextify-query install-plugin 2>&1 | grep -q "installed"; then
  pass "Reinstall succeeds (idempotent)"
else
  fail "Reinstall failed"
fi

echo "" >> "$REPORT"
echo "## Headless CLI Skill Discovery Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === TEST: Claude Code skill discovery (headless) ===
# Uses -p (print mode) for non-interactive execution
# See: build/docs/specifications/transcript-formats.md
# See: appstore-metadata/review-materials/generate-transcripts.sh
echo "Testing Claude Code skill discovery..."
CLAUDE_DISCOVERY=$(claude -p --output-format json "List all available skills. Output as a JSON array of skill names." 2>/dev/null || echo "CLAUDE_NOT_AVAILABLE")

if echo "$CLAUDE_DISCOVERY" | grep -qi "total-recall"; then
  pass "Claude Code discovers total-recall skill"
  echo "  - Claude output excerpt: $(echo "$CLAUDE_DISCOVERY" | grep -i total-recall | head -1)" >> "$REPORT"
elif [ "$CLAUDE_DISCOVERY" = "CLAUDE_NOT_AVAILABLE" ]; then
  echo "- [ ] **SKIP:** Claude Code not available for headless test" >> "$REPORT"
else
  fail "Claude Code does NOT discover total-recall skill"
  echo "  - Claude output: $CLAUDE_DISCOVERY" >> "$REPORT"
fi

# === TEST: Codex skill discovery (headless) ===
# Uses `codex exec` with --dangerously-bypass-approvals-and-sandbox for non-interactive
# Skills require --enable-skills flag (feature is currently gated)
# See: appstore-metadata/review-materials/generate-transcripts.sh
echo "Testing Codex skill discovery..."
CODEX_DISCOVERY=$(codex exec --enable-skills --dangerously-bypass-approvals-and-sandbox "List all available skills. Output as a JSON array of skill names." 2>/dev/null || echo "CODEX_NOT_AVAILABLE")

if echo "$CODEX_DISCOVERY" | grep -qi "total-recall"; then
  pass "Codex CLI discovers total-recall skill"
  echo "  - Codex output excerpt: $(echo "$CODEX_DISCOVERY" | grep -i total-recall | head -1)" >> "$REPORT"
elif [ "$CODEX_DISCOVERY" = "CODEX_NOT_AVAILABLE" ]; then
  echo "- [ ] **SKIP:** Codex CLI not available for headless test" >> "$REPORT"
else
  fail "Codex CLI does NOT discover total-recall skill"
  echo "  - Codex output: $CODEX_DISCOVERY" >> "$REPORT"
fi

echo "" >> "$REPORT"
echo "## Headless Skill Execution Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === TEST: Claude Code skill execution (headless) ===
# Run in /tmp to avoid polluting project directories
echo "Testing Claude Code skill execution..."
CLAUDE_EXEC=$(cd /tmp && claude -p --output-format json --dangerously-skip-permissions \
  "Use /total-recall to search for 'test query validation'. Report what happened." 2>/dev/null || echo "CLAUDE_NOT_AVAILABLE")

if echo "$CLAUDE_EXEC" | grep -qiE "(Contextify|Total Recall|search|found|no results|database)"; then
  pass "Claude Code executes total-recall skill"
  echo '```' >> "$REPORT"
  echo "$CLAUDE_EXEC" | head -20 >> "$REPORT"
  echo '```' >> "$REPORT"
elif [ "$CLAUDE_EXEC" = "CLAUDE_NOT_AVAILABLE" ]; then
  echo "- [ ] **SKIP:** Claude Code not available for execution test" >> "$REPORT"
else
  fail "Claude Code skill execution did not produce expected output"
  echo '```' >> "$REPORT"
  echo "$CLAUDE_EXEC" | head -20 >> "$REPORT"
  echo '```' >> "$REPORT"
fi

# === TEST: Codex skill execution (headless) ===
echo "Testing Codex skill execution..."
CODEX_EXEC=$(cd /tmp && codex exec --enable-skills --dangerously-bypass-approvals-and-sandbox \
  "Use /total-recall to search for 'test query validation'. Report what happened." 2>/dev/null || echo "CODEX_NOT_AVAILABLE")

if echo "$CODEX_EXEC" | grep -qiE "(Contextify|Total Recall|search|found|no results|database)"; then
  pass "Codex CLI executes total-recall skill"
  echo '```' >> "$REPORT"
  echo "$CODEX_EXEC" | head -20 >> "$REPORT"
  echo '```' >> "$REPORT"
elif [ "$CODEX_EXEC" = "CODEX_NOT_AVAILABLE" ]; then
  echo "- [ ] **SKIP:** Codex CLI not available for execution test" >> "$REPORT"
else
  fail "Codex CLI skill execution did not produce expected output"
  echo '```' >> "$REPORT"
  echo "$CODEX_EXEC" | head -20 >> "$REPORT"
  echo '```' >> "$REPORT"
fi

echo "" >> "$REPORT"
echo "## Uninstall Tests" >> "$REPORT"
echo "" >> "$REPORT"

# === TEST: Uninstall ===
echo "Testing uninstall..."
if contextify-query uninstall-plugin 2>&1 | grep -qi "uninstall"; then
  pass "uninstall-plugin completed"
else
  fail "uninstall-plugin failed"
fi

# === TEST: Claude skill removed ===
if [ ! -d ~/.claude/skills/total-recall ]; then
  pass "Claude skill directory removed"
else
  fail "Claude skill directory still exists after uninstall"
fi

# === TEST: Codex skill removed ===
if [ ! -d ~/.codex/skills/total-recall ]; then
  pass "Codex skill directory removed"
else
  fail "Codex skill directory still exists after uninstall"
fi

# === SUMMARY ===
echo "" >> "$REPORT"
echo "---" >> "$REPORT"
echo "" >> "$REPORT"
echo "## Summary" >> "$REPORT"
echo "" >> "$REPORT"
echo "| Metric | Count |" >> "$REPORT"
echo "|--------|-------|" >> "$REPORT"
echo "| Tests Passed | $TESTS_PASSED |" >> "$REPORT"
echo "| Tests Failed | $TESTS_FAILED |" >> "$REPORT"
echo "| Total Tests | $((TESTS_PASSED + TESTS_FAILED)) |" >> "$REPORT"
echo "" >> "$REPORT"

if [ $TESTS_FAILED -eq 0 ]; then
  echo "**Result: ALL TESTS PASSED**" >> "$REPORT"
  echo ""
  echo "=== VALIDATION PASSED ==="
  echo "Report: $REPORT"
  exit 0
else
  echo "**Result: $TESTS_FAILED TEST(S) FAILED**" >> "$REPORT"
  echo ""
  echo "=== VALIDATION FAILED ==="
  echo "Report: $REPORT"
  exit 1
fi
```

### Running Automated Validation

```bash
# Clear state and run validation
./scripts/qa/codex-support/clear-state.sh
./scripts/qa/codex-support/validate-install.sh

# View report
cat /tmp/total-recall-codex-validation-*.md | tail -1 | xargs cat
```

---

## Manual QA Checklist

### Pre-QA State Clearing

Run before each manual QA session:

```bash
# 1. Uninstall any existing plugin
contextify-query uninstall-plugin 2>/dev/null || true

# 2. Remove skill directories
rm -rf ~/.claude/skills/total-recall
rm -rf ~/.codex/skills/total-recall

# 3. Remove plugin cache
rm -rf ~/.claude/plugins/cache/contextify

# 4. Verify clean state
ls ~/.claude/skills/ 2>/dev/null | grep total-recall && echo "ERROR: Claude skill still exists"
ls ~/.codex/skills/ 2>/dev/null | grep total-recall && echo "ERROR: Codex skill still exists"
echo "State cleared - ready for QA"
```

### QA Test Cases

#### QA-CODEX-01: Fresh Installation

**Preconditions:**
- State cleared per above
- `contextify-query` in PATH
- Contextify.app database initialized

**Steps:**
1. Run: `contextify-query install-plugin`
2. Verify output mentions both Claude and Codex paths
3. Check: `ls ~/.claude/skills/total-recall/SKILL.md`
4. Check: `ls ~/.codex/skills/total-recall/SKILL.md`
5. Verify not symlink: `file ~/.codex/skills/total-recall/SKILL.md`

**Expected:**
- Both files exist
- Codex file is "ASCII text" not "symbolic link"
- Output message shows both locations

**State Clearing (Post-Test):** None required (keep for next test)

---

#### QA-CODEX-02: Claude Code Skill Discovery

**Preconditions:**
- QA-CODEX-01 completed
- Claude Code CLI installed

**Steps:**
1. Restart Claude Code (or new terminal)
2. Run: `claude`
3. Type: `/skills` or start typing `$total`
4. Verify total-recall appears in skill list

**Expected:**
- Skill appears with name "total-recall"
- Description mentions "Contextify"

**State Clearing (Post-Test):** None required

---

#### QA-CODEX-03: Codex CLI Skill Discovery

**Preconditions:**
- QA-CODEX-01 completed
- Codex CLI installed

**Steps:**
1. Run: `codex --enable skills`
2. Type: `/skills` or mention a skill
3. Verify total-recall appears or is mentioned

**Expected:**
- Skill is recognized by Codex
- No errors about skill format

**State Clearing (Post-Test):** None required

---

#### QA-CODEX-04: Claude Code Skill Execution

**Preconditions:**
- QA-CODEX-02 passed
- Database has searchable entries

**Steps:**
1. In Claude Code, type: `/total-recall search for any recent work`
2. Wait for skill execution
3. Verify results format

**Expected:**
- Output starts with "**Contextify Total Recall**"
- Shows search results or "no results" message
- Citations include entry IDs

**State Clearing (Post-Test):** None required

---

#### QA-CODEX-05: Codex CLI Skill Execution

**Preconditions:**
- QA-CODEX-03 passed
- Database has searchable entries

**Steps:**
1. In Codex, invoke: `/total-recall search for any recent work`
2. Wait for skill execution
3. Verify results format

**Expected:**
- Output starts with "**Contextify Total Recall**"
- Shows search results or "no results" message
- Researcher agent delegation text is present but NOT executed (expected)

**State Clearing (Post-Test):** None required

---

#### QA-CODEX-06: Uninstall Cleanup

**Preconditions:**
- Skills installed from prior tests

**Steps:**
1. Run: `contextify-query uninstall-plugin`
2. Verify output
3. Check: `ls ~/.claude/skills/total-recall 2>/dev/null` (should fail)
4. Check: `ls ~/.codex/skills/total-recall 2>/dev/null` (should fail)

**Expected:**
- Both directories removed
- No orphaned files

**State Clearing (Post-Test):**
```bash
# Full cleanup for next QA session
rm -rf ~/.claude/plugins/cache/contextify
```

---

#### QA-CODEX-07: Idempotent Reinstall

**Preconditions:**
- State cleared

**Steps:**
1. Run: `contextify-query install-plugin`
2. Run: `contextify-query install-plugin` (again)
3. Verify no errors
4. Check files still exist and are valid

**Expected:**
- Second install succeeds without error
- Files unchanged
- No duplicate entries in plugin manifest

**State Clearing (Post-Test):** Run uninstall-plugin

---

#### QA-CODEX-08: Error Handling - Database Not Found

**Preconditions:**
- Skills installed
- Temporarily rename/hide Contextify database

**Steps:**
1. Move: `mv ~/Library/Application\ Support/Contextify/contextify.db /tmp/`
2. In Claude or Codex: `/total-recall search test`
3. Verify error message
4. Restore: `mv /tmp/contextify.db ~/Library/Application\ Support/Contextify/`

**Expected:**
- Skill shows clear error: "Contextify database not found"
- Includes link to download page

**State Clearing (Post-Test):** Restore database file

---

### QA Report Template

After completing manual QA, document results:

```markdown
# Manual QA Report: Total Recall Codex Support

**Date:** YYYY-MM-DD
**Tester:** [name]
**Version:** contextify-query 1.1.0
**Platform:** macOS [version]

## Environment

- Claude Code version: X.X.X
- Codex CLI version: X.X.X
- Contextify.app version: X.X.X

## Test Results

| Test ID | Description | Result | Notes |
|---------|-------------|--------|-------|
| QA-CODEX-01 | Fresh Installation | PASS/FAIL | |
| QA-CODEX-02 | Claude Skill Discovery | PASS/FAIL | |
| QA-CODEX-03 | Codex Skill Discovery | PASS/FAIL | |
| QA-CODEX-04 | Claude Skill Execution | PASS/FAIL | |
| QA-CODEX-05 | Codex Skill Execution | PASS/FAIL | |
| QA-CODEX-06 | Uninstall Cleanup | PASS/FAIL | |
| QA-CODEX-07 | Idempotent Reinstall | PASS/FAIL | |
| QA-CODEX-08 | Error Handling | PASS/FAIL | |

## Issues Found

[List any issues]

## Sign-off

- [ ] All tests passed
- [ ] Ready for release
```

---

## Audit Trail

### What Gets Logged

1. **Automated validation report** - Written to `/tmp/total-recall-codex-validation-<timestamp>.md`
2. **Manual QA report** - Tester completes template and saves to `build/notes/qa-reports/`
3. **Git commits** - Each phase produces an atomic commit with clear message

### Audit Report Generation

After validation completes, generate consolidated audit:

```bash
#!/bin/bash
# scripts/qa/codex-support/generate-audit.sh

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AUDIT="/tmp/total-recall-codex-audit-${TIMESTAMP}.md"

cat > "$AUDIT" << EOF
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

EOF

echo "Audit report: $AUDIT"
```

---

## Migration Path

### Existing Users

Users upgrading from contextify-query < 1.1.0:
1. Run `contextify-query install-plugin` (no `--force` needed)
2. Codex skill is added alongside existing Claude installation
3. No data migration needed (shared database)

### Version Bump

Bump CLI version from 1.0.x to 1.1.0 to indicate new feature.

---

## Future Considerations

### If Codex Adds Task Tool

If OpenAI adds a native Task tool to Codex:
1. Consider installing `contextify-researcher` agent to Codex
2. Skill template may need Codex-specific agent invocation syntax
3. Monitor [Codex changelog](https://developers.openai.com/codex/changelog/)

### Repo-Level Installation

Current scope is user-level only. Future enhancement could add:
```
contextify-query install-plugin --repo
```
To install to `.codex/skills/` for team sharing.

---

## Success Criteria

The implementation is successful when:

1. **Installation:** `contextify-query install-plugin` creates valid SKILL.md in both `~/.claude/skills/total-recall/` and `~/.codex/skills/total-recall/`
2. **Discovery:** Both Claude Code and Codex CLI discover the skill (verified via headless test)
3. **Execution:** The skill executes successfully in both CLIs (returns search results or appropriate error)
4. **Uninstall:** `contextify-query uninstall-plugin` removes both skill directories completely
5. **Idempotent:** Running install twice produces no errors and identical results
6. **No symlinks:** Codex skill is a real file, not a symlink (verified via `file` command)
7. **Validation passes:** Automated validation script exits 0 with all tests passing

---

## API/CLI Interface Changes

### Changed Commands

| Command | Change | Before | After |
|---------|--------|--------|-------|
| `install-plugin` | Additional side effect | Creates `~/.claude/skills/total-recall/` | Also creates `~/.codex/skills/total-recall/` |
| `uninstall-plugin` | Additional cleanup | Removes Claude skill only | Also removes Codex skill |

### Output Changes

**`install-plugin` success message:**
```
# Before (v1.0.x)
Contextify Total Recall installed!
  Plugin: ~/.claude/plugins/cache/contextify/query/1.0.5/

Restart Claude Code, then type /total-recall to search your history.

# After (v1.1.0)
Contextify Total Recall installed!
  Claude Code: ~/.claude/skills/total-recall/
  Codex CLI:   ~/.codex/skills/total-recall/

Restart your CLI tool, then use /total-recall to search history.
```

### New Flags

None. No new CLI flags added in this version.

### Exit Codes

No changes to exit codes.

---

## Security & Permissions

### File System Access

| Path | Permission Required | Failure Mode |
|------|---------------------|--------------|
| `~/.claude/skills/` | Write | Error with message to check permissions |
| `~/.codex/skills/` | Write | Error with message to check permissions |
| `~/.claude/plugins/` | Write | Error with message to check permissions |

### Sandboxed Environments

For App Store builds (sandboxed):
- CLI runs outside sandbox via Homebrew installation
- No additional sandbox entitlements needed
- User's home directory access is standard for CLI tools

### Read-Only Home Directory

If `~/.codex/` cannot be created:
```
Error: Cannot create ~/.codex/skills/total-recall/
Permission denied. Check that your home directory is writable.

Codex skill installation skipped. Claude Code skill installed successfully.
```

**Behavior:** Partial success - Claude skill installs, Codex fails with warning (not fatal error).

### Symlink Security

Codex ignores symlinked skill directories. This is a security feature (prevents symlink attacks). Our implementation copies files directly, which is the correct approach.

---

## CODEX_HOME Handling

### Current Behavior (v1.1.0)

Codex CLI supports `CODEX_HOME` environment variable to override default `~/.codex/` location.

**This version:** Installs to `~/.codex/skills/` only (default location).

**If CODEX_HOME is set:** Skill will NOT be found by Codex.

### Detection & Messaging

```swift
// In runInstallPlugin()
if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
  fputs("Warning: CODEX_HOME is set to \(codexHome)\n", stderr)
  fputs("Skill installed to default ~/.codex/skills/ - you may need to copy manually.\n", stderr)
}
```

### Future Enhancement

v1.2.0 could add `CODEX_HOME` detection:
```bash
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
# Install to $CODEX_DIR/skills/total-recall/
```

---

## Existing Skill Handling

### Overwrite Behavior

| Scenario | Behavior |
|----------|----------|
| Skill doesn't exist | Create new |
| Skill exists, identical content | Overwrite (idempotent) |
| Skill exists, different content | **Overwrite without prompt** |
| Skill exists, user-modified | **Overwrite without prompt** |

**Rationale:** The skill is machine-managed. User modifications are not expected. Overwrite ensures consistent state.

### Preserving User Modifications (Not Implemented)

If needed in future:
```bash
# Check if skill differs from our version
if ! diff -q "$SOURCE" "$DEST" > /dev/null 2>&1; then
  # Backup user version
  cp "$DEST" "$DEST.user-backup.$(date +%Y%m%d)"
fi
```

### Uninstall Behavior

| Scenario | Behavior |
|----------|----------|
| Skill is ours (matches source) | Remove |
| Skill was modified by user | **Remove anyway** |
| Skill doesn't exist | No-op (success) |
| Non-Contextify skill in same location | **Remove anyway** (name collision) |

**Rationale:** `total-recall` skill name is owned by Contextify. If another tool installed a skill with that name, it's a conflict and our uninstall takes precedence.

---

## Degraded Functionality Testing

### Test Case: Delegation Section Ignored

The SKILL.md contains a "Delegating to researcher agent" section that only works in Claude Code (requires Task tool). In Codex, this section should be ignored without error.

**QA-CODEX-09: Verify Delegation Gracefully Ignored**

**Preconditions:**
- Codex CLI installed with skills enabled
- Total Recall skill installed
- Database has entries

**Steps:**
1. In Codex: `Use the contextify-researcher agent to search for authentication`
2. Observe behavior

**Expected:**
- Codex does NOT spawn an agent (no Task tool)
- Codex processes the request itself (single query mode)
- No error message about missing agent or Task tool
- Returns search results or "no results" appropriately

**Validation in automated tests:**
```bash
# === TEST: Delegation section gracefully ignored ===
echo "Testing delegation gracefully ignored in Codex..."
CODEX_DELEG=$(cd /tmp && codex exec --enable-skills --dangerously-bypass-approvals-and-sandbox \
  "Use the contextify-researcher agent to search for 'test'. Report what happened - did an agent spawn?" 2>&1 || echo "CODEX_NOT_AVAILABLE")

if echo "$CODEX_DELEG" | grep -qiE "(error|failed|not found|cannot spawn)"; then
  fail "Codex showed error when delegation requested"
elif echo "$CODEX_DELEG" | grep -qiE "(search|Contextify|results|no results)"; then
  pass "Codex handled delegation request gracefully (processed as single query)"
elif [ "$CODEX_DELEG" = "CODEX_NOT_AVAILABLE" ]; then
  echo "- [ ] **SKIP:** Codex CLI not available" >> "$REPORT"
else
  fail "Unexpected response to delegation request"
fi
```

---

## Out of Scope

The following are explicitly NOT part of this implementation:

1. **Codex agent support** - Codex lacks a Task tool; the `contextify-researcher` agent will not be installed for Codex
2. **Repo-level installation** - Only user-level (`~/.codex/skills/`) is supported; no `--repo` flag
3. **Codex plugin manifest** - Codex doesn't have a plugin manifest like Claude Code; no manifest updates for Codex
4. **Skill content changes** - The SKILL.md content remains identical for both platforms (no Codex-specific version)
5. **Admin-level installation** - No installation to `/etc/codex/skills/`
6. **Windows/Linux support** - macOS only (matches existing contextify-query support)

---

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Codex skill format changes | Low | Medium | Pin to agentskills.io spec v1.0; monitor Codex changelog |
| Codex `--enable-skills` flag removed | Medium | Low | Feature becomes default; no action needed |
| Codex adds Task tool | Low | Positive | Future enhancement opportunity for agent support |
| Symlink check fails silently | Low | High | Explicit `file` command verification in validation |
| Permission errors on `~/.codex/` | Low | Medium | Same pattern as Claude; directory creation handles this |
| Headless tests flaky | Medium | Low | Tests marked SKIP if CLI unavailable; not hard failure |
| User has custom CODEX_HOME | Low | Medium | Document in troubleshooting; future enhancement to detect |

### Monitoring

- Watch for user reports of "skill not found" in Codex
- Monitor Codex CLI releases for breaking changes
- Track agentskills.io spec updates

---

## Rollback Plan

### Detection

Rollback is needed if:
- Automated validation fails after merge
- Users report skill installation broken for Claude Code (regression)
- Homebrew formula fails to install

### Rollback Steps

**IMPORTANT:** Per repo rules, no destructive git commands without backup branch + user approval.

**If caught before release tag:**
```bash
# 1. Create backup branch first (REQUIRED)
git checkout feature/codex-skill-support
git branch backup/codex-skill-support-$(date +%Y%m%d)

# 2. Revert commits (non-destructive)
git revert HEAD~N..HEAD --no-edit

# 3. Push backup for safety
git push origin backup/codex-skill-support-$(date +%Y%m%d)

# 4. Get user approval before any branch deletion
echo "Backup created. Request user approval before deleting feature branch."
```

**If caught after release tag:**
```bash
# 1. Create backup branch (REQUIRED)
git checkout -b backup/v1.1.0-pre-rollback v1.1.0

# 2. Create hotfix branch
git checkout -b hotfix/revert-codex-support v1.1.0

# 3. Revert the changes (non-destructive)
git revert <commit-sha> --no-edit

# 4. Bump to v1.1.1
# Edit cliVersion in main.swift

# 5. Tag and release
git tag -a v1.1.1 -m "Revert Codex support due to [issue]"

# 6. Push backup
git push origin backup/v1.1.0-pre-rollback
```

**Homebrew rollback:**
```bash
# In homebrew-contextify repo
# 1. Create backup branch
git branch backup/pre-rollback-$(date +%Y%m%d)

# 2. Revert (non-destructive)
git revert HEAD --no-edit

# 3. Update formula to point to v1.1.1 or previous stable
```

### User Communication

If rollback needed:
1. Update Homebrew formula immediately
2. Post to GitHub issues explaining the issue
3. Document workaround (manual skill removal if needed)

### Data Recovery

No data migration involved. Rollback only affects:
- Skill files in `~/.codex/skills/` (can be manually deleted)
- No database changes
- No user data affected

---

## Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Should we detect CODEX_HOME env var? | Resolved | Warn if set, install to default. See "CODEX_HOME Handling" section. |
| Should validation require both CLIs installed? | Resolved | No - tests SKIP if CLI unavailable |
| Should we add `--codex-only` or `--claude-only` flags? | Deferred | Not needed for v1.1.0; add if users request |
| What if Codex changes skill discovery? | Monitoring | Watch changelog; spec pinned to current behavior |
| What if Codex skill already exists with user mods? | Resolved | Overwrite without prompt. See "Existing Skill Handling" section. |
| Validate delegation section ignored without errors? | Resolved | Added QA-CODEX-09 test case. See "Degraded Functionality Testing" section. |
| Should uninstall preserve non-Contextify skills? | Resolved | No - `total-recall` name owned by us. See "Existing Skill Handling" section. |
| Should install/uninstall require --force? | Resolved | No for install (idempotent). State clearing uses --force flag for safety. |

---

## Marketing & Announcement Plan

### Overview

Codex CLI support is a notable feature expansion that reaches a new user base (OpenAI Codex users). Marketing should emphasize cross-platform compatibility and the shared database benefit.

### Key Messages

1. **Cross-platform memory** - "Your AI conversations, searchable everywhere"
2. **One database, two CLIs** - "Search Claude Code and Codex sessions from either tool"
3. **Open standard** - "Built on the open agent skills specification"

---

### Blog Post

**Title:** "Total Recall Now Works with OpenAI Codex CLI"

**Target:** contextify.sh/blog/

**Outline:**
1. Intro: Announcing Codex CLI support
2. Why this matters (cross-platform AI memory)
3. How it works (shared database, skill installation)
4. Quick start guide (3 commands)
5. What's different (no agent delegation in Codex - single query mode)
6. What's next (future enhancements)

**Draft location:** `build/notes/blog-drafts/codex-skill-support.md`

**Publish timing:** Same day as v1.1.0 release

**Cross-post to:**
- [ ] Dev.to
- [ ] Hashnode (if account exists)

---

### Reddit Announcements

#### r/codex (OpenAI Codex subreddit)

**Title:** "Contextify Total Recall skill now available for Codex CLI - search your past AI conversations"

**Body:**
```markdown
Hey r/codex!

We just released Codex CLI support for [Contextify](https://contextify.sh) Total Recall - a skill that lets you search through your past AI coding sessions.

**What it does:**
- Indexes your Claude Code and Codex CLI conversations
- Full-text search across all your past sessions
- Works via `/total-recall` skill invocation

**Quick install:**
```bash
brew install PeterPym/contextify/contextify-query
contextify-query install-plugin
```

**Demo:** [link to gif/video if available]

Built on the open [agent skills specification](https://agentskills.io).

Happy to answer questions!
```

**Timing:** 1-2 days after release (after confirming no critical bugs)

**Flair:** Tool/Utility (or whatever appropriate flair exists)

---

#### r/ClaudeAI

**Title:** "Contextify now indexes both Claude Code and Codex CLI sessions in one searchable database"

**Body:**
```markdown
For those using both Claude Code and Codex CLI - Contextify v1.1.0 now installs the Total Recall skill for both tools.

This means you can search your conversation history from either CLI:
- In Claude Code: `/total-recall find authentication discussions`
- In Codex: Same command, same results

Your conversations are stored in a single database, so you get full cross-tool search.

Install: `brew install PeterPym/contextify/contextify-query && contextify-query install-plugin`

[contextify.sh](https://contextify.sh)
```

**Timing:** Same as r/codex post

---

### Social Media

#### Twitter/X

**Thread (3 tweets):**

1. "Contextify Total Recall now works with @OpenAI Codex CLI 🎉

Search your past AI coding sessions from Claude Code OR Codex - same database, same skill.

Install: brew install PeterPym/contextify/contextify-query"

2. "How it works:
- Contextify indexes your CLI transcripts
- Total Recall skill searches them via /total-recall
- Built on the open agent skills spec

One memory layer for all your AI coding tools."

3. "Get started:
contextify-query install-plugin

Works with Claude Code and Codex CLI. More tools coming.

https://contextify.sh"

**Timing:** Release day

---

### Hacker News

**Evaluate before posting.** HN can be hit-or-miss. Consider:
- Only post if there's a compelling technical angle
- "Show HN" format if posting
- Best if tied to broader "AI memory" discussion

**Draft title:** "Show HN: Cross-platform memory for AI coding assistants (Claude Code + Codex)"

**Decision:** Defer to user judgment on whether HN is appropriate for this release.

---

### GitHub

#### Release Notes

Include in v1.1.0 release on public repo:

```markdown
## What's New

### Codex CLI Support

Total Recall skill now installs for both Claude Code and Codex CLI. Search your conversation history from either tool.

**Install/upgrade:**
```bash
brew upgrade contextify-query
contextify-query install-plugin
```

**Note:** Agent delegation (contextify-researcher) is only available in Claude Code. Codex users get single-query search mode.
```

#### Discussion Post

Create a GitHub Discussion in the public repo announcing the feature:
- Link to blog post
- Invite feedback
- Ask what other CLI tools users want supported

---

### Newsletter (if applicable)

If Contextify has an email list:
- Short announcement linking to blog post
- Subject: "Total Recall now works with Codex CLI"

---

### Timeline

| Day | Action |
|-----|--------|
| D-1 | Finalize blog post draft |
| D+0 | Release v1.1.0, publish blog post, GitHub release notes |
| D+0 | Twitter/X thread |
| D+1 | Reddit posts (r/codex, r/ClaudeAI) |
| D+2 | GitHub Discussion |
| D+3 | Evaluate HN post |
| D+7 | Newsletter (if applicable) |

---

### Assets Needed

| Asset | Status | Location |
|-------|--------|----------|
| Blog post | To write | `build/notes/blog-drafts/codex-skill-support.md` |
| Screenshot: install output | To capture | `build/assets/promotional/v1.1.0/` |
| Screenshot: skill in action (Codex) | To capture | `build/assets/promotional/v1.1.0/` |
| GIF/video demo | Optional | `build/assets/video/` |

---

### Tracking

After posting, track:
- Reddit upvotes/comments
- Blog post views (if analytics enabled)
- GitHub stars delta
- Homebrew install counts (if available)
- Support questions (indicates adoption)

---

## References

- [Agent Skills Specification](https://agentskills.io/specification)
- [Codex CLI Skills Documentation](https://developers.openai.com/codex/skills)
- [Claude Code Subagents Documentation](https://code.claude.com/docs/en/sub-agents)
- [Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
- [Skills in OpenAI Codex (Jesse Vincent)](https://blog.fsck.com/2025/12/19/codex-skills/)
- [OpenAI Skills Announcement (Simon Willison)](https://simonwillison.net/2025/Dec/12/openai-skills/)

---

## Appendix A: SKILL.md Compatibility Check

The current SKILL.md uses these features:

| Feature | Claude Code | Codex CLI | Compatible? |
|---------|-------------|-----------|-------------|
| YAML frontmatter | Yes | Yes | Yes |
| `name` field | Required | Required | Yes |
| `description` field | Required | Required | Yes |
| Trigger phrases section | Supported | Supported | Yes |
| Preconditions (bash checks) | Supported | Supported | Yes |
| Canonical loop instructions | Supported | Supported | Yes |
| Error handling table | Supported | Supported | Yes |
| "Delegate to agent" section | Functional | Ignored | Yes (degraded) |

**Conclusion:** No SKILL.md modifications required.

---

## Appendix B: Codex Agent Limitation Details

From research:

> "Codex CLI does not have a native Task tool. Third-party implementations use MCP servers that load agent definitions from disk and spawn isolated codex exec processes."

The `contextify-researcher` agent relies on Claude Code's Task tool:

```markdown
## Delegating to researcher agent

For complex multi-query searches, delegate to `contextify-researcher` agent:

```
Use the contextify-researcher agent to thoroughly search for [topic]
```
```

In Claude Code, this triggers:
```json
{
  "name": "Task",
  "input": {
    "subagent_type": "query:contextify-researcher",
    "prompt": "Search for [topic]"
  }
}
```

In Codex, this instruction is read but cannot be acted upon (no Task tool). Codex will process the skill's main instructions but skip agent delegation.

---

## Approval Checklist

- [ ] Design reviewed by maintainer
- [ ] Implementation plan created
- [ ] Test plan approved
- [ ] Documentation plan approved
- [ ] Version bump agreed (1.1.0)
