# Pre-Merge Checklist

Complete this checklist before merging any feature branch to main. This expands on Phase 5 (Review) from `feature-development-workflow.md`.

---

## Quick Reference

```bash
# Validation commands (must all pass)
swift test                           # Unit tests
bash scripts/xc.sh build             # Build + zero warnings
./scripts/qa/run-all-tests.sh        # E2E tests (if applicable)
```

---

## 1. Code Validation

### Required (Every Merge)

- [ ] **Unit tests pass:** `swift test`
- [ ] **Build succeeds with zero warnings:** `bash scripts/xc.sh build`
- [ ] **No compiler errors or deprecation warnings**

### If Touching LLM Features

- [ ] **Lite Mode simulation:** Test with `-simulate-legacy-macos` flag
- [ ] **VM validation:** Run `build/docs/testing/lite-mode-qa-checklist.md` on macOS 15 VM (before releases)

---

## 2. E2E Testing

### When to Run Full Suite

Run `./scripts/qa/run-all-tests.sh` when:
- Changes touch user-facing flows (timeline, search, project switching)
- Database schema changes
- File watcher or monitoring changes
- Before any release

### When to Run Specific Tests

```bash
# Run single test
./scripts/qa/tests/QA-03-codex-discovery.sh

# Run with fixtures (no CLI tools needed)
QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore
```

### E2E Checklist

- [ ] **New flows covered:** Added QA test for new user flows
- [ ] **Existing tests updated:** Modified tests if flow changed
- [ ] **Test contracts valid:** `@test_contract` headers accurate
- [ ] **Fixture mode works:** Tests pass with `QA_FIXTURE_MODE=1`

---

## 3. Documentation Audit

### Identify Affected Docs

Run this command to find docs mentioning your feature:
```bash
grep -rl "YOUR_FEATURE" build/docs/ AGENTS.md TODOS.md ROADMAP.md
```

### Documentation Checklist

- [ ] **AGENTS.md:** Updated if feature changes how agents should work with codebase
- [ ] **Architecture docs:** Updated if new components or patterns introduced
- [ ] **Guide docs:** Updated if developer workflows changed
- [ ] **Testing docs:** Updated if new testing requirements

### Common Docs to Check

| Feature Type | Docs to Review |
|--------------|----------------|
| LLM changes | `llm-processing.md`, `COMPONENTS.md` |
| Database changes | `sql-backend.md`, `DatabaseSchema.swift` header |
| UI changes | `swiftui-patterns.md` |
| Build/tooling | `DEVELOPMENT.md` |
| Testing | `TESTING-STRATEGY.md`, `scripts/qa/README.md` |

---

## 4. TODOS.md Administration

### Mark Items Complete

When a TODO item is done:
1. **Remove the item entirely** (don't leave checked boxes)
2. **Update the section item count** in the heading
3. **Remove empty sections** if all items complete

### Archive Support Documents

Move completed feature docs from `build/notes/todo-support/` to archive:
```bash
# Pattern: YYYY-MM-DD-feature-name.md
mv build/notes/todo-support/FEATURE-spec.md \
   build/docs/archive/completed-work/2025-12-13-feature-spec.md

mv build/notes/todo-support/FEATURE-implementation-plan.md \
   build/docs/archive/completed-work/2025-12-13-feature-implementation-plan.md
```

### Update References

After archiving, update any references to the old paths:
```bash
# Find references to moved files
grep -r "todo-support/FEATURE" build/docs/
```

### TODOS.md Checklist

- [ ] **Completed items removed:** No leftover checked boxes for this feature
- [ ] **Section counts accurate:** Heading says "(N items)" matches actual count
- [ ] **Support docs archived:** Specs and plans moved to `build/docs/archive/completed-work/`
- [ ] **References updated:** All paths point to new archive locations
- [ ] **Related items updated:** Other TODOs that referenced this feature updated

---

## 5. Technical Debt Tracking

### When to Update Debt Trackers

If your feature introduces:
- Version-specific conditionals (`#available`, `#if canImport`)
- Temporary workarounds
- Known limitations to address later

### Debt Tracking Checklist

- [ ] **Conditionals documented:** Added to appropriate tracker in `build/docs/technical-debt/`
- [ ] **Cleanup conditions stated:** When can this debt be removed?
- [ ] **Files listed:** Which files contain the debt?

---

## 6. Final Verification

### Pre-Push Checks

```bash
# Verify clean state
git status                           # Should show only your changes

# Verify tests still pass after any last changes
swift test
bash scripts/xc.sh build
```

### Commit Hygiene

- [ ] **Atomic commits:** Each commit is one logical change
- [ ] **Conventional format:** `feat(scope):`, `fix(scope):`, `docs:`, etc.
- [ ] **No WIP commits:** Squash or reword any work-in-progress commits

---

## 7. Merge Execution

### Standard Merge

```bash
git checkout main
git pull origin main
git merge feature/your-branch
git push origin main
```

### If Conflicts

1. Resolve conflicts
2. Re-run validation: `swift test && bash scripts/xc.sh build`
3. Complete merge

### Post-Merge

- [ ] **Delete feature branch** (after confirming merge successful)
- [ ] **Verify main builds:** `git checkout main && bash scripts/xc.sh build`

---

## Checklist by Feature Size

### Small (Bug fix, minor tweak)

- [ ] Unit tests pass
- [ ] Build zero warnings
- [ ] Commit message correct

### Medium (New feature, refactor)

All of Small, plus:
- [ ] E2E tests (if touching user flows)
- [ ] TODOS.md updated
- [ ] Relevant docs updated

### Large (Major feature, architectural change)

All of Medium, plus:
- [ ] Full E2E suite passes
- [ ] Documentation audit complete
- [ ] Support docs archived
- [ ] Technical debt tracked (if applicable)
- [ ] Lite Mode tested (if touching LLM)

---

## Related Documentation

- **Development workflow:** `feature-development-workflow.md`
- **Testing strategy:** `TESTING-STRATEGY.md`
- **E2E test suite:** `scripts/qa/README.md`
- **Commit guidelines:** `AGENTS.md` (Commit Guidelines section)
