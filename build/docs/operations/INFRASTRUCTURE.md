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
