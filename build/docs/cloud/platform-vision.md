# Cloud Platform Vision

**Last Updated:** 2026-03-07

---

## The Idea

Contextify Cloud is being built as a sync and team backend for the Contextify macOS app. The deeper intention is that it serves as the proof-of-concept for a generalized backend platform -- one that can eventually support any AI CLI tool that needs shared, highly available, backed-up data across users and devices.

The strategy is deliberate: **prove it works in Contextify first, then generalize if it succeeds.** Not the other way around.

---

## Why This Matters

Several AI CLI tools in this ecosystem share the same infrastructure problem:

| Tool | Data | Need |
|------|------|------|
| **Contextify** | Conversation transcripts, summaries, project timelines | Sync across machines, team search, dashboards |
| **bloon** | Task database | Available on all machines, backed up, no git sync complexity |
| **administration** | AI agent config, scripts, session data | Accessible remotely via mobile/Tailscale |
| **gcal** | Calendar cache, scheduling context | Available to AI agents across machines |

Each of these currently solves availability with ad-hoc approaches: Dropbox symlinks, git repos, local-only storage. The underlying need is the same: **a reliable, tenant-aware backend with push/pull sync, search, and access control.**

---

## What Contextify Cloud Already Gets Right

The architecture decisions made during the Contextify build are already oriented toward generalization, even if not designed for it explicitly:

- **API contracts are generic.** `/sync/push`, `/sync/pull`, `/sync/status` -- not `/transcripts/push`. The `kind` field on entries is a string, not an enum locked to Claude/Codex message types.
- **Schema-per-tenant isolation.** Each tenant gets their own PostgreSQL schema. A future bloon tenant is not a square peg.
- **API key auth is tool-agnostic.** The `ctx_<key_id>_<secret>` format doesn't assume anything about which tool is using it.
- **Self-hosted via Docker Compose.** The homeserver path (Mac Mini + Docker) works equally well for any tool's data.

---

## Design Principles to Preserve During the Contextify Build

These are the decisions where "keeping the abstraction in mind" matters. None of them require extra work now -- they are constraints on what NOT to do.

1. **Don't hardcode Contextify-specific types into the API contract.** The `kind` field should remain an open string. Avoid adding fields like `claude_model` or `codex_version` to the base entry schema; put those in `metadata` (JSONB) instead.

2. **Keep the sync protocol generic.** The push/pull semantics (cursor-based, idempotent, content-addressed) are tool-agnostic. Don't add Contextify-specific semantics into the core sync path.

3. **Tenant provisioning should not assume Contextify.** Tenant configuration, retention settings, and billing tiers should not have Contextify-specific fields in the base model.

4. **Don't couple the dashboard to transcript concepts.** Team dashboards should query generic entry/project data, not Contextify-specific views. Tool-specific visualizations belong in tool-specific dashboard extensions, not the core.

5. **Homeserver deployment stays generic.** The `homeserver-setup.sh` bootstrap and Docker Compose configuration should work regardless of which tool's data is being hosted.

---

## The Self-Hosted Path

The Mac Mini homeserver (tracked in ad-3, ct-209) serves as the personal instance of this platform. It runs:

- **contextify-cloud stack** -- FastAPI + PostgreSQL via Docker Compose
- Accessible via Tailscale from all personal machines and mobile devices
- Intended to eventually host data for multiple tools, not just Contextify

This is the same Docker Compose stack used for self-hosted enterprise deployments, run locally. It is the first real proof that the platform works end-to-end.

---

## Generalization Path (Future)

If the Contextify deployment succeeds -- meaning push/pull is reliable, the homeserver is stable, and team features work -- the generalization path is:

1. **bloon sync** -- bloon.db currently lives in Dropbox. A push/pull sync backend would remove the Dropbox dependency and add cross-device availability without git complexity.
2. **administration project** -- AI agent config, session data, and the remote access backend (ad-88 epic) would run on the same homeserver stack.
3. **gcal and other CLIs** -- Calendar cache and scheduling context could be synced the same way.
4. **Publish the platform** -- At sufficient maturity, the platform itself (without Contextify-specific features) could be offered as a self-hostable open-source backend for AI CLI tools generally.

None of this is currently in scope. It depends entirely on the Contextify build succeeding.

---

## Related

- **contextify-cloud repo:** `~/code/projects/contextify-cloud/` -- the server implementation
- **Cloud dashboard ownership:** team/dashboard/analytics pages under `cloud.contextify.sh` live in `contextify-cloud`, not in the static website repo
- **Cross-repo debugging rule:** if a problem spans local grouping and cloud visualization, inspect latest `origin/main` in both `contextify` and `contextify-cloud`
- **Homeserver setup:** `contextify-cloud/scripts/homeserver-setup.sh`
- **Mac Mini setup task:** `bloon show ad-3` (administration project)
- **Cloud deploy task:** `bloon show ct-209` (contextify project, cloud tag)
- **Remote access epic:** `bloon show ad-88` (administration project)
- **Cloud sync epic:** `bloon show ct-167` (contextify project)
- **Original investigation:** `/private/tmp/loop-mode-true.md` (2026-02-19, session bb79ead0)
