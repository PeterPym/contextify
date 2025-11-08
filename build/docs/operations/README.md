# Operations Documentation

Release management, app store submission, and marketing materials.

## Purpose

This directory contains operational documentation for:
- App Store submission and compliance
- Release processes and checklists
- Marketing and distribution strategies
- Notarization and code signing

## Subdirectories

### app-store/
**Topics:** App Store submission requirements and compliance
- Sandbox implementation requirements
- Entitlements and permissions
- Submission checklists and testing

**Key docs:**
- [Sandbox Implementation Plan](app-store/sandbox-implementation-plan.md)

### marketing/
**Topics:** Distribution and marketing strategies
- Show HN draft
- Distribution strategy
- User acquisition and growth

**Key docs:**
- [Show HN Draft](marketing/show-hn-draft.md)
- [Distribution Strategy](marketing/distribution-strategy.md)

### release/
**Topics:** Release processes and automation
- Notarization setup and workflows
- Build verification checklists
- Release readiness criteria

**Key docs:**
- Notarization setup and success documentation
- Release build verification
- Release readiness checklists

---

## Relationship to Other Docs

- **Architecture/** - Understanding system architecture for release planning
- **Guides/** - Build and CI processes referenced in release workflows
- **Design/** - Design decisions that affect App Store screenshots and marketing

---

## Updating These Docs

**When to update:**
- After App Store submission attempts (document learnings)
- When release processes change or improve
- After marketing campaigns (capture results and insights)

**What to include:**
- Checklists and step-by-step procedures
- Requirements and compliance notes
- Lessons learned from previous releases
- Links to external resources (Apple docs, notarization guides, etc.)

**What NOT to include:**
- Temporary release notes (use /tmp/)
- Private API keys or certificates (use secure credential storage)
- Draft marketing copy before review (use /tmp/ or Google Docs)

---

## Release Workflow Reference

For detailed release procedures, see:
- `scripts/RELEASE.md` - Complete release automation documentation
- `Makefile` - Release targets (`make release`, `make sign-dmg`, etc.)
