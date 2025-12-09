# Website & Marketing Administration

## Website: contextify.sh

**Platform:** Static HTML, Nginx, Let's Encrypt SSL
**Analytics:** GoAccess (server-side, no JS) - see [Website Analytics](website-analytics.md)

## Quick Deployment

```bash
./scripts/deploy-website.sh
```

Rsync-based, one-command deployment to production server.

**Options:**
- `--dry-run` - Preview without uploading
- `--force` - Skip git clean/pushed checks

## Server Configuration

**Server:** web@banagale.com
- **IP:** 143.198.70.216
- **Provider:** DigitalOcean droplet

**DNS:** Managed at DigitalOcean
- **Nameservers:** ns1/2/3.digitalocean.com

**Email:** Apple Custom Email via iCloud+
- **Address:** support@contextify.sh
- **Setup Guide:** `build/docs/operations/customer-support.md`

## Technical Details

**Nginx Configuration:**
- **Config file:** `build/nginx-contextify.conf`
- **Deployed to:** `/etc/nginx/sites-available/contextify`

**Web Root:**
- **Path:** `/var/www/contextify.sh/`

**SSL/HTTPS:**
- **Provider:** Let's Encrypt
- **Auto-renewal:** via certbot

## Additional Documentation

- Website docs: `build/docs/website/`
- Public surfaces: `build/docs/operations/PUBLIC-SURFACES.md`
- Analytics setup: `build/docs/operations/website-analytics.md`
- Server configs: `build/server-configs/analytics/`

## Deployment Workflow

1. Make changes to website files locally
2. Run deployment script: `./scripts/deploy-website.sh`
3. Script shows only files that will change (not full listing)
4. Script syncs changed files to server via rsync
5. Verify changes at https://contextify.sh

**Dry run to preview:**
```bash
./scripts/deploy-website.sh --dry-run
```

## Deployment Safety Features

### Pre-flight Checks
- Working tree must be clean (no uncommitted website/ changes)
- Current branch must be pushed to origin
- Warns if not on main branch

### Protected Directories
Server-side directories that persist across deploys:
```bash
PROTECTED_DIRS=(
    'stats'    # GoAccess analytics
)
```
To add more, edit `PROTECTED_DIRS` in `scripts/deploy-website.sh`.

### Deletion Warnings
Before deploying, the script checks for server content not in local `website/` directory. If found:
- Shows loud warning with list of items to be deleted
- Requires explicit confirmation (y/N)
- Suggests adding to `PROTECTED_DIRS` or investigating

### Automatic Backups
Before each deploy, the previous site is archived:
- **Location:** `/var/www/contextify-archives/`
- **Format:** `YYYY-MM-DD_HHMM_<git-short>.tar.gz`
- **Retention:** Last 5 archives (rolling)
- **Excludes:** Protected directories (they persist anyway)

**To rollback:**
```bash
ssh web@banagale.com
sudo tar -xzf /var/www/contextify-archives/<archive>.tar.gz -C /var/www/contextify.sh/
```

**To list archives:**
```bash
ssh web@banagale.com "ls -lh /var/www/contextify-archives/"
```

## Analytics

**Dashboard:** https://contextify.sh/stats/menu.html (password protected)

Server-side analytics using GoAccess log analysis. No client-side JavaScript.

| View | Update Frequency |
|------|------------------|
| Live (last hour) | Every 30 seconds |
| Today | Every minute |
| All Time | Real-time WebSocket |

**Full documentation:** [Website Analytics](website-analytics.md)

## Image Optimization

**Use WebP for all site images.** PNG/JPEG source files should be converted to WebP before deployment.

**Why:** WebP typically achieves 80-95% size reduction vs PNG with no visible quality loss. This matters for traffic spikes (Show HN, Reddit).

**Convert images:**
```bash
# Single image
cwebp -q 85 image.png -o image.webp

# All PNGs in a directory
for f in website/assets/img/*.png; do cwebp -q 85 "$f" -o "${f%.png}.webp"; done
```

**Quality settings:**
- `-q 85` - Good balance for screenshots/UI images
- `-q 90` - Higher quality for hero images if needed
- `-q 75` - Acceptable for thumbnails

**Requirements:** Install cwebp via `brew install webp`

**Checklist for new images:**
1. Export source as PNG (for archival in `build/design/`)
2. Convert to WebP for deployment
3. Reference `.webp` in HTML
4. Keep PNG source but don't deploy it

**Real-world savings (Dec 2024):**
| Image | PNG | WebP | Savings |
|-------|-----|------|---------|
| feature-search-cropped | 2.1 MB | 174 KB | 92% |
| feature-sync-cropped | 2.4 MB | 47 KB | 98% |
| feature-timeline-cropped | 1.6 MB | 104 KB | 94% |

## Maintenance

**SSL Certificate Renewal:**
- Automatic via certbot
- Check expiry: `sudo certbot certificates` (on server)

**Server Access:**
- SSH: `ssh web@banagale.com`
- Requires SSH key authentication

**Update rsync (if deploy script shows compatibility errors):**
```bash
ssh web@banagale.com "sudo apt update && sudo apt install -y rsync"
```
The deploy script uses rsync features that require a recent version. If you see errors like `unrecognized option`, update rsync on the server.

**Reboot server (via DigitalOcean console if SSH is down):**
- Log into DigitalOcean dashboard
- Select the droplet (143.198.70.216)
- Use Power > Power cycle or Access > Console
