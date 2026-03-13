# Contextify Cloud Server

The cloud sync API runs on a dedicated DigitalOcean droplet, completely separate from the contextify.sh website server.

## Server Details

| Field | Value |
|-------|-------|
| **Hostname** | cloud.contextify.sh |
| **IP** | 174.138.94.110 |
| **Provider** | DigitalOcean |
| **Droplet size** | s-2vcpu-4gb |
| **OS** | Ubuntu 24.04 |
| **Region** | NYC3 |
| **SSH user** | `deploy` |
| **SSH command** | `ssh deploy@174.138.94.110` |
| **App directory** | `/opt/contextify-cloud` |
| **App port** | 8443 (internal, proxied by Nginx) |
| **Provisioned** | 2026-03-11 |
| **Provisioning task** | ct-216 |
| **Deployment runbook** | Attached to ct-216 in bloon |

## Stack

- **Application:** Python 3.11, FastAPI, uvicorn
- **Database:** PostgreSQL 16 (Docker container, port 5432 internal only)
- **Containerization:** Docker Compose (api + db services)
- **Reverse proxy:** Nginx (host-level, not containerized)
- **SSL:** Let's Encrypt via certbot, auto-renewal
- **Process management:** systemd (`contextify-cloud.service`)

## SSH Access

```bash
ssh deploy@174.138.94.110
```

The `deploy` user's SSH key was set up during provisioning. Root SSH login is disabled (`PermitRootLogin no`). Password auth is disabled.

## Deploy Procedure

There is no automated deploy script for the cloud server yet. Deploy manually:

```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && git pull origin main && docker compose build --no-cache api && docker compose up -d --wait"
```

Verify after deploy:
```bash
curl https://cloud.contextify.sh/api/v1/health
```

Expected response: `{"status":"ok","version":"0.1.0","database":"connected"}`

### What happens during deploy

1. `git pull` fetches latest from `github.com/banagale/contextify-cloud` main branch
2. `docker compose build --no-cache api` rebuilds the API container (installs deps via uv, copies source)
3. `docker compose up -d --wait` restarts the API container, waits for health check
4. Alembic migrations run automatically on container startup via `entrypoint.sh`
5. The PostgreSQL container (`db`) is NOT rebuilt, only restarted if needed

### Deploy does NOT affect

- The `.env` file (excluded from git, contains production secrets)
- The PostgreSQL data volume (persistent across rebuilds)
- Nginx configuration (managed separately on the host)
- SSL certificates (managed by certbot on the host)

## Configuration

Production config is in `/opt/contextify-cloud/.env` (chmod 600, not in git). Key settings:

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection string (points to `db` Docker service) |
| `API_SECRET_KEY` | JWT signing key (must NOT be the default `dev-secret-change-me`) |
| `STRIPE_SECRET_KEY` | Stripe API key for billing |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signature verification |
| `ALLOWED_ORIGINS` | CORS origins (contextify.sh, cloud.contextify.sh) |
| `ENABLE_DOCS` | Set `true` to enable Swagger UI at `/api/docs` (disabled in production) |
| `MAX_BATCH_SIZE` | Max items per sync push request (default 500) |
| `RATE_LIMIT_SYNC_PER_MINUTE` | Sync endpoint rate limit per API key (default 30) |

To edit production config:
```bash
ssh deploy@174.138.94.110 "nano /opt/contextify-cloud/.env"
# Then restart: docker compose restart api
```

## Nginx

Nginx runs on the host (not in Docker) and proxies to the API container.

| Path Pattern | Backend | Purpose |
|-------------|---------|---------|
| `/api/v1/*` | localhost:8443 | REST API (sync, search, auth, billing) |
| `/cloud/*` | localhost:8443 | Web dashboard (Jinja2/htmx) |
| `/` | localhost:8443 | Root endpoint |

Config file: `/etc/nginx/sites-available/contextify-cloud`

Rate limiting at Nginx level:
- Auth endpoints: 2 req/sec per IP
- API endpoints: 10 req/sec per IP (burst 20)

## Security Hardening

| Feature | Status |
|---------|--------|
| SSH key-only auth | Active |
| Root login disabled | Active |
| UFW firewall (22/80/443 only) | Active |
| fail2ban (SSH + Nginx + bots) | Active |
| unattended-upgrades | Active |
| auditd | Active |
| OpenAPI/Swagger docs | Disabled in production |
| PostgreSQL port | Internal only (not exposed to host network) |

## Monitoring

### Container status
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && docker compose ps"
```

### API logs
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && docker compose logs -f api --tail 100"
```

### Database logs
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && docker compose logs -f db --tail 50"
```

### systemd service
```bash
ssh deploy@174.138.94.110 "sudo systemctl status contextify-cloud"
```

### Disk usage
```bash
ssh deploy@174.138.94.110 "df -h / && echo '---' && docker system df"
```

## Database

PostgreSQL 16 runs in a Docker container. Data persists in a Docker volume.

### Connect to database
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && docker compose exec db psql -U contextify contextify"
```

### Check sync status via API
```bash
curl -H "Authorization: Bearer <api-key>" https://cloud.contextify.sh/api/v1/sync/status
```

### Backup (manual)
```bash
ssh deploy@174.138.94.110 "cd /opt/contextify-cloud && docker compose exec db pg_dump -U contextify contextify > /tmp/backup-\$(date +%Y%m%d).sql"
```

## Relationship to Other Servers

The cloud server has **no relationship** to the website server at banagale.com (143.198.70.216). They are:
- Different DigitalOcean droplets
- Different SSH users (`deploy` vs `web`)
- Different purposes (API vs static website)
- Different deploy procedures (git pull vs rsync)
- Different software stacks (Docker/FastAPI vs Nginx/static HTML)

The only connection is DNS: both `contextify.sh` and `cloud.contextify.sh` are managed in the same DigitalOcean DNS panel.
