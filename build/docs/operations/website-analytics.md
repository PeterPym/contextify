# Website Analytics (GoAccess)

Server-side analytics for contextify.sh using GoAccess log analysis. No client-side JavaScript required.

## Overview

**Tool:** GoAccess 1.8.1
**Access:** https://contextify.sh/stats/menu.html (password protected)
**Log source:** `/var/log/nginx/contextify.access.log`

### Available Views

| View | URL | Update Frequency | Description |
|------|-----|------------------|-------------|
| Live | `/stats/live.html` | Every 30 seconds | Last hour, minute-by-minute granularity |
| Today | `/stats/today.html` | Every minute | Full day stats |
| All Time | `/stats/index.html` | Real-time (WebSocket) | Historical data |

## Configuration Files

All config files are stored in `build/server-configs/analytics/` for reference.

### Server Locations

| Local Reference | Server Location |
|-----------------|-----------------|
| `goaccess.conf` | `/etc/goaccess/goaccess.conf` |
| `goaccess-today.sh` | `/usr/local/bin/goaccess-today.sh` |
| `goaccess-live.sh` | `/usr/local/bin/goaccess-live.sh` |
| `goaccess.service` | `/etc/systemd/system/goaccess.service` |
| `goaccess-today.service` | `/etc/systemd/system/goaccess-today.service` |
| `goaccess-today.timer` | `/etc/systemd/system/goaccess-today.timer` |
| `goaccess-live.service` | `/etc/systemd/system/goaccess-live.service` |
| `goaccess-live.timer` | `/etc/systemd/system/goaccess-live.timer` |
| `stats-menu.html` | `/var/www/contextify.sh/stats/menu.html` |

### Nginx Configuration

The stats endpoint requires updates to the Nginx config (see `build/nginx-contextify.conf`):
- Dedicated access log: `/var/log/nginx/contextify.access.log`
- `/stats/` location with basic auth
- `/stats/ws` WebSocket proxy for real-time updates

## Setup from Scratch

### 1. Install Dependencies

```bash
ssh web@banagale.com
sudo apt update
sudo apt install -y goaccess apache2-utils
```

### 2. Create Stats Directory

```bash
sudo mkdir -p /var/www/contextify.sh/stats
sudo chown web:web /var/www/contextify.sh/stats
```

### 3. Create Basic Auth Credentials

```bash
# Generate password (save this securely)
sudo htpasswd -c /etc/nginx/.htpasswd_stats admin
```

### 4. Deploy Configuration Files

Copy all files from `build/server-configs/analytics/` to their server locations:

```bash
# GoAccess config
sudo cp goaccess.conf /etc/goaccess/goaccess.conf

# Scripts (make executable)
sudo cp goaccess-today.sh /usr/local/bin/
sudo cp goaccess-live.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/goaccess-today.sh
sudo chmod +x /usr/local/bin/goaccess-live.sh

# Systemd units
sudo cp goaccess.service /etc/systemd/system/
sudo cp goaccess-today.service /etc/systemd/system/
sudo cp goaccess-today.timer /etc/systemd/system/
sudo cp goaccess-live.service /etc/systemd/system/
sudo cp goaccess-live.timer /etc/systemd/system/

# Menu page
sudo cp stats-menu.html /var/www/contextify.sh/stats/menu.html
```

### 5. Update Nginx Configuration

Deploy `build/nginx-contextify.conf` to server and reload:

```bash
sudo cp nginx-contextify.conf /etc/nginx/sites-available/contextify
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Enable and Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now goaccess.service
sudo systemctl enable --now goaccess-today.timer
sudo systemctl enable --now goaccess-live.timer
```

### 7. Verify Setup

```bash
# Check services
sudo systemctl status goaccess
sudo systemctl list-timers | grep goaccess

# Test access (replace PASSWORD)
curl -u admin:PASSWORD https://contextify.sh/stats/menu.html
```

## Filtering Configuration

The GoAccess config (`/etc/goaccess/goaccess.conf`) excludes:

**Owner IPs** (update as needed):
- `23.234.81.210`
- `75.164.244.171`

**Filtered content:**
- Bot/crawler traffic (`ignore-crawlers true`)
- Error status codes (400, 401, 403, 404, 429, 5xx)
- `/stats/` paths (filtered in scripts via grep)

**Hidden panels** (technical/noisy):
- HOSTS, REQUESTS_STATIC, NOT_FOUND, KEYPHRASES
- STATUS_CODES, CACHE_STATUS, MIME_TYPE, TLS_TYPE, REMOTE_USER

**Visible panels** (GA-like):
- VISITORS (unique visitors by day)
- REQUESTS (top pages)
- REFERRING_SITES (traffic sources)
- REFERRERS (full referrer URLs)
- GEO_LOCATION (countries)
- BROWSERS, OS (device breakdown)
- VISIT_TIMES (hourly distribution)

## Maintenance

### Adding/Removing Excluded IPs

Edit `/etc/goaccess/goaccess.conf`:

```bash
exclude-ip NEW.IP.ADDRESS
```

Then restart services:

```bash
sudo systemctl restart goaccess
```

### Checking Service Status

```bash
# Main service
sudo systemctl status goaccess
sudo journalctl -u goaccess -f

# Timers
sudo systemctl list-timers | grep goaccess
sudo journalctl -u goaccess-today.service --since '5 minutes ago'
sudo journalctl -u goaccess-live.service --since '5 minutes ago'
```

### Manual Report Generation

```bash
# Today report
sudo /usr/local/bin/goaccess-today.sh

# Live report
sudo /usr/local/bin/goaccess-live.sh
```

## Credentials

**Location:** `/etc/nginx/.htpasswd_stats`
**Username:** `admin`
**Password:** Stored securely (not in repo)

To reset password:

```bash
sudo htpasswd /etc/nginx/.htpasswd_stats admin
```

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Nginx (contextify.sh)       │
                    │                                     │
                    │  /stats/* ──► Basic Auth            │
                    │  /stats/ws ──► WebSocket Proxy:7890 │
                    └─────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────┐
│                     GoAccess Services                        │
│                                                              │
│  goaccess.service (real-time)                                │
│    └─► tail -F access.log | grep -v /stats/ | goaccess      │
│    └─► WebSocket on 127.0.0.1:7890                          │
│    └─► Output: /stats/index.html                            │
│                                                              │
│  goaccess-today.timer (every 1 min)                         │
│    └─► goaccess-today.sh                                    │
│    └─► Output: /stats/today.html                            │
│                                                              │
│  goaccess-live.timer (every 30 sec)                         │
│    └─► goaccess-live.sh                                     │
│    └─► Output: /stats/live.html                             │
└──────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────┐
                    │  /var/log/nginx/contextify.access.log │
                    │  (dedicated log for contextify.sh)   │
                    └─────────────────────────────────────┘
```

## Related Documentation

- [Website Administration](WEBSITE.md) - Server and deployment info
- [Nginx Config](../../nginx-contextify.conf) - Full Nginx configuration
- [Config Files](../../server-configs/analytics/) - All GoAccess configs
