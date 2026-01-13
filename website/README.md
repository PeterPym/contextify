# Contextify.sh Website

**URL:** https://contextify.sh
**Purpose:** Product website for App Store submission + user trust

> **Note:** This README is excluded from deployment and will not appear on the live site.

---

## Reference Documentation

Before making changes, consult these docs:

| Topic | Location |
|-------|----------|
| **Deployment & Server** | `build/docs/operations/WEBSITE.md` |
| **Email Addresses** | `build/docs/operations/customer-support.md` |
| **Public URLs** | `build/docs/operations/PUBLIC-SURFACES.md` |
| **Design System** | `build/design/README.md` |
| **Color Tokens** | `build/design/brand/colors.md` (CSS must stay in sync) |
| **App Store Badges** | `build/design/brand/app-store-badges/` |
| **Design Specimens** | `build/design/website/specimens/` |

---

## Deployment

```bash
./scripts/deploy-website.sh           # Deploy to production
./scripts/deploy-website.sh --dry-run # Preview what would be deployed
```

**Script:** `scripts/deploy-website.sh` - Contains file exclusion list (README.md, QUICKSTART.txt, drafts/, etc.)

## Local Development

**Start both servers for full functionality:**

```bash
# Terminal 1: Static file server (HTML/CSS/JS)
cd website && python3 -m http.server 8000

# Terminal 2: Newsletter API server
cd website/api && python3 subscribe.py
```

| Server | Port | Purpose |
|--------|------|---------|
| Static | 8000 | HTML pages at http://localhost:8000 |
| API | 8080 | Newsletter form submissions |

**Static server only** (if not testing newsletter):
```bash
cd website && python3 -m http.server 8000
```

---

## Infrastructure Setup (One-Time)

**Run these commands ONCE to set up DNS, SSL, and email:**

### Step 1: Add DNS Record

```bash
# Add A record for contextify.sh
doctl compute domain records create contextify.sh \
  --record-type A \
  --record-name @ \
  --record-data 143.198.70.216 \
  --record-ttl 300

# Verify DNS propagation (wait 5-10 minutes)
dig contextify.sh +short
# Should return: 143.198.70.216
```

### Step 2: Create Nginx Configuration

```bash
# SSH to server
ssh web@banagale.com

# Create web root
sudo mkdir -p /var/www/contextify.sh
sudo chown www-data:www-data /var/www/contextify.sh
sudo chmod 755 /var/www/contextify.sh

# Create Nginx vhost
sudo nano /etc/nginx/sites-available/contextify
```

**Nginx config to paste:**

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name contextify.sh www.contextify.sh;

    root /var/www/contextify.sh;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Static files with caching
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # HTML pages (no caching for now)
    location / {
        try_files $uri $uri/ =404;
    }
}
```

**Enable site:**

```bash
sudo ln -s /etc/nginx/sites-available/contextify /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Exit SSH
exit
```

### Step 3: Get SSL Certificate

```bash
# SSH back to server
ssh web@banagale.com

# Run certbot
sudo certbot --nginx -d contextify.sh -d www.contextify.sh

# Follow prompts (use your email, agree to terms)
# Certbot will automatically update Nginx config for HTTPS

# Test auto-renewal
sudo certbot renew --dry-run

# Exit SSH
exit
```

### Step 4: Setup Email (Apple Custom Email)

**Prerequisites:** You need iCloud+ subscription (already have for banagale.com)

1. Go to **iCloud Settings** → **Custom Email Domain**
2. Click "+" to add domain
3. Enter `contextify.sh`
4. Apple will provide DNS records to add

**Example DNS records (Apple will give you the actual values):**

```bash
# Add TXT record for verification
doctl compute domain records create contextify.sh \
  --record-type TXT \
  --record-name @ \
  --record-data "apple-domain-verification=XXXXXXXX" \
  --record-ttl 300

# Add MX records for email routing
doctl compute domain records create contextify.sh \
  --record-type MX \
  --record-name @ \
  --record-data "mx01.mail.icloud.com" \
  --record-priority 10 \
  --record-ttl 300

doctl compute domain records create contextify.sh \
  --record-type MX \
  --record-name @ \
  --record-data "mx02.mail.icloud.com" \
  --record-priority 20 \
  --record-ttl 300

# Add CNAME for www
doctl compute domain records create contextify.sh \
  --record-type CNAME \
  --record-name www \
  --record-data "contextify.sh." \
  --record-ttl 300
```

5. Create email alias in iCloud: `support@contextify.sh`
6. Test by sending email to `support@contextify.sh`

---

## File Structure

```
website/
├── index.html        # Homepage
├── privacy.html      # Privacy Policy (App Store requirement)
├── support.html      # Support/FAQ
└── README.md         # This file

Future additions:
├── screenshot.png    # App screenshot (add when ready)
└── favicon.ico       # Site icon (optional)
```

---

## Content Updates

### Update Homepage

1. Edit `website/index.html`
2. Test locally: `python3 -m http.server 8000`
3. Deploy: `./scripts/deploy-website.sh`

### Add Screenshot

1. Take screenshot of app:
   ```bash
   # Capture window (Cmd+Shift+4, then Space, click window)
   # Or use: screencapture -w screenshot.png
   ```

2. Resize for web:
   ```bash
   sips -Z 1600 screenshot.png
   ```

3. Copy to website directory:
   ```bash
   cp screenshot.png website/
   ```

4. Uncomment screenshot line in `index.html`:
   ```html
   <!-- Remove these comment tags: -->
   <img src="screenshot.png" alt="Contextify Screenshot" class="screenshot">
   ```

5. Deploy:
   ```bash
   ./scripts/deploy-website.sh
   ```

### Add Download Link

When ready to distribute DMG:

1. Upload DMG to server or GitHub releases
2. Edit `index.html`, replace "Coming soon" section with:
   ```html
   <a href="Contextify-v1.0.dmg" class="download-btn">Download for macOS</a>
   ```
3. Deploy: `./scripts/deploy-website.sh`

---

## App Store Submission URLs

**Use these in App Connect:**

- **Marketing URL:** `https://contextify.sh`
- **Privacy Policy URL:** `https://contextify.sh/privacy.html`
- **Support URL:** `https://contextify.sh/support.html`

---

## Troubleshooting

### Site not loading after deployment

1. Check DNS:
   ```bash
   dig contextify.sh +short
   # Should return: 143.198.70.216
   ```

2. Check Nginx status:
   ```bash
   ssh web@banagale.com 'sudo systemctl status nginx'
   ```

3. Check Nginx config:
   ```bash
   ssh web@banagale.com 'sudo nginx -t'
   ```

4. Check SSL certificate:
   ```bash
   ssh web@banagale.com 'sudo certbot certificates'
   ```

5. Test from server:
   ```bash
   ssh web@banagale.com 'curl -I http://localhost'
   ```

### Email not working

1. Check DNS records:
   ```bash
   dig MX contextify.sh +short
   ```

2. Verify in Apple iCloud settings
3. Wait 1-2 hours for DNS propagation
4. Send test email

### Permission errors during deployment

```bash
# Fix ownership on server
ssh web@banagale.com 'sudo chown -R www-data:www-data /var/www/contextify.sh'
```

---

## Maintenance

### Update SSL Certificate (Auto-renewal)

Certbot auto-renews. Verify:

```bash
ssh web@banagale.com 'sudo certbot renew --dry-run'
```

### Check Logs

```bash
# Access logs
ssh web@banagale.com 'sudo tail -f /var/log/nginx/access.log'

# Error logs
ssh web@banagale.com 'sudo tail -f /var/log/nginx/error.log'
```

### Backup

Website files are in version control (Git). Database and server config should be backed up separately.

---

## TODO

**Before App Store submission:**
- [ ] Add app screenshot to homepage
- [ ] Test all links work
- [ ] Proofread all content
- [ ] Test on mobile devices
- [ ] Verify email `support@contextify.sh` works

**Future enhancements:**
- [ ] Add favicon
- [ ] Add meta tags for social sharing (Open Graph)
- [ ] Consider adding analytics (optional)
- [ ] Add testimonials/reviews section
- [ ] Create FAQ based on user feedback

---

**Last Updated:** 2025-11-11
