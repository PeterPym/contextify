# Website & Marketing Administration

## Website: contextify.sh

**Platform:** Static HTML, Nginx, Let's Encrypt SSL

## Quick Deployment

```bash
./scripts/deploy-website.sh
```

Rsync-based, one-command deployment to production server.

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
- Launch status: `build/notes/todo-support/P0-APP-STORE-checklist.md`

## Deployment Workflow

1. Make changes to website files locally
2. Run deployment script: `./scripts/deploy-website.sh`
3. Script syncs files to server via rsync
4. Verify changes at https://contextify.sh

## Maintenance

**SSL Certificate Renewal:**
- Automatic via certbot
- Check expiry: `sudo certbot certificates` (on server)

**Server Access:**
- SSH: `ssh web@banagale.com`
- Requires SSH key authentication
