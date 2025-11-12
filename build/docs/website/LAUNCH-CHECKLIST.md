# Contextify.sh Website Launch Checklist

**Goal:** Get website live for App Store submission
**Timeline:** 1-2 hours
**Status:** Ready to execute

---

## Phase 1: Infrastructure (30 minutes)

### DNS Setup
- [ ] Add A record for `contextify.sh` → `143.198.70.216`
  ```bash
  doctl compute domain records create contextify.sh \
    --record-type A \
    --record-name @ \
    --record-data 143.198.70.216 \
    --record-ttl 300
  ```
- [ ] Add CNAME for `www.contextify.sh` → `contextify.sh`
  ```bash
  doctl compute domain records create contextify.sh \
    --record-type CNAME \
    --record-name www \
    --record-data "contextify.sh." \
    --record-ttl 300
  ```
- [ ] Verify DNS propagation: `dig contextify.sh +short` (should return `143.198.70.216`)

### Nginx Configuration
- [ ] SSH to server: `ssh web@banagale.com`
- [ ] Create web root:
  ```bash
  sudo mkdir -p /var/www/contextify.sh
  sudo chown www-data:www-data /var/www/contextify.sh
  sudo chmod 755 /var/www/contextify.sh
  ```
- [ ] Create Nginx vhost: `sudo nano /etc/nginx/sites-available/contextify`
  - Copy config from `website/README.md`
- [ ] Enable site:
  ```bash
  sudo ln -s /etc/nginx/sites-available/contextify /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx
  ```
- [ ] Exit SSH

### SSL Certificate
- [ ] SSH to server: `ssh web@banagale.com`
- [ ] Run certbot:
  ```bash
  sudo certbot --nginx -d contextify.sh -d www.contextify.sh
  ```
- [ ] Test auto-renewal: `sudo certbot renew --dry-run`
- [ ] Exit SSH
- [ ] Verify HTTPS: `curl -I https://contextify.sh` (should return 200 OK with SSL)

---

## Phase 2: Deploy Website (15 minutes)

### Deploy Files
- [ ] From project root: `./scripts/deploy-website.sh`
- [ ] Verify deployment output shows success
- [ ] Test in browser: `open https://contextify.sh`

### Verify Pages
- [ ] Homepage loads: https://contextify.sh
- [ ] Privacy Policy loads: https://contextify.sh/privacy.html
- [ ] Support loads: https://contextify.sh/support.html
- [ ] All footer links work
- [ ] No 404 errors

### Mobile Test
- [ ] Open on iPhone/iPad or resize browser window
- [ ] Text is readable
- [ ] Layout not broken

---

## Phase 3: Email Setup (15 minutes)

### Apple Custom Email
- [ ] Go to iCloud Settings → Custom Email Domain
- [ ] Add `contextify.sh` domain
- [ ] Apple provides DNS records (TXT, MX, etc.)
- [ ] Add DNS records via `doctl`:
  ```bash
  # TXT verification (Apple will provide exact value)
  doctl compute domain records create contextify.sh \
    --record-type TXT \
    --record-name @ \
    --record-data "apple-domain-verification=XXXXXXXX" \
    --record-ttl 300

  # MX records (Apple will provide exact values)
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
  ```
- [ ] Wait for Apple verification (5-15 minutes)
- [ ] Create email alias: `hello@contextify.sh`
- [ ] Send test email to `hello@contextify.sh`
- [ ] Verify email arrives in iCloud Mail
- [ ] Reply to test email to verify sending works

---

## Phase 4: Content Review (10 minutes)

### Proofread All Pages
- [ ] Homepage: No typos, links work
- [ ] Privacy Policy: No placeholder text, email is correct
- [ ] Support: FAQ makes sense, email is correct
- [ ] Footer: All links work on all pages

### Update Any Placeholders
- [ ] Privacy Policy effective date is correct (2025-11-11)
- [ ] Contact email is `hello@contextify.sh` everywhere
- [ ] Copyright year is 2025

### Cross-Browser Test
- [ ] Safari (primary)
- [ ] Chrome (fallback)

---

## Phase 5: Final Checks (10 minutes)

### SSL & Security
- [ ] HTTPS enforced (http:// redirects to https://)
- [ ] Green lock icon in browser
- [ ] Test on https://www.ssllabs.com/ssltest/ (optional but recommended)

### Performance
- [ ] Page loads in <2 seconds
- [ ] No console errors in browser dev tools

### App Store Requirements
- [ ] Privacy Policy URL is public: `https://contextify.sh/privacy.html`
- [ ] Contact email works: `hello@contextify.sh`
- [ ] Website is accessible from anywhere (test on phone with cellular)

---

## Phase 6: Documentation (5 minutes)

### Record URLs
**Save these for App Store submission:**

```
Marketing URL: https://contextify.sh
Privacy Policy URL: https://contextify.sh/privacy.html
Support URL: https://contextify.sh/support.html
Contact Email: hello@contextify.sh
```

### Take Screenshots (Optional)
- [ ] Homepage screenshot for records
- [ ] Privacy Policy screenshot for records

---

## Post-Launch Tasks (Can be done later)

### Add App Screenshot (When ready)
- [ ] Take screenshot of Contextify app
- [ ] Resize: `sips -Z 1600 screenshot.png`
- [ ] Copy to `website/screenshot.png`
- [ ] Uncomment screenshot line in `index.html`
- [ ] Redeploy: `./scripts/deploy-website.sh`

### Add Favicon (Optional)
- [ ] Export app icon as PNG from Xcode
- [ ] Convert to .ico: https://favicon.io/favicon-converter/
- [ ] Add `favicon.ico` to `website/`
- [ ] Add meta tags to HTML `<head>`
- [ ] Redeploy

### Monitor Uptime (Optional)
- [ ] Set up DigitalOcean monitoring for `https://contextify.sh`
- [ ] Configure alerts to `rob@banagale.com`

### Analytics (Optional, Deferred)
- [ ] Decide if you want basic analytics
- [ ] If yes: Add GoatCounter or Plausible
- [ ] Update Privacy Policy if adding analytics

---

## Troubleshooting

### DNS not resolving
**Wait 5-10 minutes for propagation**, then:
```bash
dig contextify.sh +short
# Should return: 143.198.70.216
```

### Nginx errors
```bash
ssh web@banagale.com 'sudo nginx -t'
ssh web@banagale.com 'sudo systemctl status nginx'
```

### SSL certificate issues
```bash
ssh web@banagale.com 'sudo certbot certificates'
```

### Email not working
- Wait 1-2 hours for DNS propagation
- Check MX records: `dig MX contextify.sh +short`
- Verify in Apple iCloud settings

### Site not loading
```bash
# Test from server
ssh web@banagale.com 'curl -I http://localhost'

# Check Nginx logs
ssh web@banagale.com 'sudo tail /var/log/nginx/error.log'
```

---

## Success Criteria

**You're done when:**
- ✅ https://contextify.sh loads in browser
- ✅ All pages accessible (homepage, privacy, support)
- ✅ HTTPS works (green lock icon)
- ✅ Email works (`hello@contextify.sh` receives mail)
- ✅ Mobile responsive (test on phone)
- ✅ No console errors in browser
- ✅ All links work
- ✅ Ready for App Store submission

---

## Time Breakdown

| Phase | Task | Time |
|-------|------|------|
| 1 | DNS Setup | 5 min |
| 1 | Nginx Config | 10 min |
| 1 | SSL Certificate | 10 min |
| 2 | Deploy Website | 10 min |
| 2 | Verify Pages | 5 min |
| 3 | Email Setup | 15 min |
| 4 | Content Review | 10 min |
| 5 | Final Checks | 10 min |
| 6 | Documentation | 5 min |
| **Total** | | **1 hour 20 minutes** |

---

## Quick Start (TL;DR)

**Minimum viable path:**

```bash
# 1. Add DNS (wait 5 minutes)
doctl compute domain records create contextify.sh --record-type A --record-name @ --record-data 143.198.70.216 --record-ttl 300

# 2. Setup Nginx (see Phase 1)
ssh web@banagale.com
# (create vhost, enable, reload)
exit

# 3. Get SSL
ssh web@banagale.com
sudo certbot --nginx -d contextify.sh -d www.contextify.sh
exit

# 4. Deploy
./scripts/deploy-website.sh

# 5. Test
open https://contextify.sh

# 6. Setup email (see Phase 3)
# (Apple iCloud settings, add DNS records, create alias)

# Done!
```

---

**Start Time:** ___________
**End Time:** ___________
**Status:** [ ] Complete

---

**Last Updated:** 2025-11-11
