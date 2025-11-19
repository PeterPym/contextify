# Operations Documentation

Release management, app store submission, customer support, and marketing materials.

## Purpose

This directory contains operational documentation for:
- Customer support and issue handling
- Website and email administration
- Database operations and migration
- App Store submission and compliance
- Release processes and checklists
- Marketing and distribution strategies
- Notarization and code signing

## Operational Guides

### [Customer Support](customer-support.md)
**Topics:** Support request handling, email setup, and issue triage
- Email configuration (support@contextify.sh, rob@contextify.sh)
- Support request workflow and categorization
- Response templates and escalation procedures
- Converting support requests to TODOs
- Privacy and data handling guidelines

### [Website Administration](WEBSITE.md)
**Topics:** Website deployment and maintenance
- Server configuration (DigitalOcean, Nginx)
- DNS management
- SSL certificate renewal
- Deployment workflow

### [Database Locations](DATABASE-LOCATIONS.md)
**Topics:** Database location management and custom paths
- Default vs custom database locations
- Database discovery and migration
- Multi-machine sync considerations

### [Database Migration Runbook](database-migration-runbook.md)
**Topics:** Database migration procedures
- Migration planning and testing
- Backup and rollback procedures
- Schema version management

### [Transcript Corruption Detection](transcript-corruption-detection.md)
**Topics:** Handling corrupt transcript files
- Detection and logging
- Repair workflows
- Prevention strategies

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
