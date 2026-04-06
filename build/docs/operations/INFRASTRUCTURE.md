# Contextify Infrastructure

Contextify runs on two separate DigitalOcean droplets plus GitHub for releases. The two servers have no relationship to each other, different SSH users, different purposes, and different deploy procedures.

## Servers

| Resource | Host | IP | SSH | Purpose |
|----------|------|----|----|---------|
| **Website** | contextify.sh | 143.198.70.216 | `ssh web@banagale.com` | Static marketing site, newsletter API, GoAccess analytics |
| **Cloud API** | cloud.contextify.sh | 174.138.94.110 | `ssh deploy@174.138.94.110` | Cloud sync API, web dashboard, PostgreSQL |

These are **completely separate servers**. Different droplets, different users, different deploy processes. The website server predates the cloud server and runs as user `web` on the `banagale.com` hostname. The cloud server was provisioned on 2026-03-11 as a dedicated droplet with a `deploy` user.

## DNS

All DNS is managed at DigitalOcean (ns1/2/3.digitalocean.com).

| Domain | Type | Points To |
|--------|------|-----------|
| contextify.sh | A | 143.198.70.216 (website droplet) |
| www.contextify.sh | A | 143.198.70.216 (website droplet) |
| cloud.contextify.sh | A | 174.138.94.110 (cloud droplet) |

## Repositories

| Repo | URL | Deployed To |
|------|-----|-------------|
| contextify (private) | github.com/banagale/contextify | Website files via rsync |
| contextify-cloud | github.com/banagale/contextify-cloud | Cloud server via git pull |
| contextify (public) | github.com/PeterPym/contextify | GitHub Releases (DMG downloads) |

## Ownership Boundaries

- `contextify` owns the macOS app, local SQLite state, transcript ingestion, worktree grouping detection, and the data that is synced upward.
- `contextify-cloud` owns the cloud API, PostgreSQL data model, sync reconciliation on the server, and the web dashboard/analytics pages served from `cloud.contextify.sh`.
- `contextify-public-repo` does not own the cloud analytics/dashboard implementation. It is only the public release/issues surface.

## Investigation Routing

Use this routing before starting cloud-facing debugging work:

- If the problem is about local grouping behavior before sync, start in `contextify`.
- If the problem is about what the analytics/dashboard page shows, start in `contextify-cloud`.
- If the problem is about grouping or coalescing differing between local app state and the analytics/dashboard page, inspect both repos from latest `origin/main`.

This matters because the "analytics page" is not part of the static marketing website and is not implemented in the public repo. It is part of the cloud stack on the dedicated cloud server.

## Detailed Documentation

- **Website server:** [WEBSITE.md](WEBSITE.md) - Deploy, Nginx, analytics, newsletter
- **Cloud API server:** [CLOUD-SERVER.md](CLOUD-SERVER.md) - Deploy, Docker, PostgreSQL, API
- **Database (local app):** [DATABASE-LOCATIONS.md](DATABASE-LOCATIONS.md) - SQLite locations
- **Public surfaces:** [PUBLIC-SURFACES.md](PUBLIC-SURFACES.md) - All user-facing URLs

## Quick Reference

### Deploy website
```bash
./scripts/deploy-website.sh
```

### Deploy cloud API
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && git pull origin main && docker compose build --no-cache api && docker compose up -d --wait"
```

### Check cloud API health
```bash
curl https://cloud.contextify.sh/api/v1/health
```

### Check cloud sync status
```bash
curl -H "Authorization: Bearer <api-key>" https://cloud.contextify.sh/api/v1/sync/status
```

### Run live systems validation
```bash
./scripts/validate-live-systems.sh
# Or via GitHub Actions: workflow_dispatch on live-systems-validation.yml
```
