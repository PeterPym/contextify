# Contextify.sh Website Implementation Plan
**Created:** 2025-11-11
**Goal:** Minimal viable website for App Store submission + user credibility
**Timeline:** 2-4 hours total work
**Approach:** Static site, markdown-based, hosted on existing DO droplet

---

## Executive Summary

**Strategy:** Ultra-minimal static HTML site with Rogue Amoeba-style clarity and professionalism. Avoid startup clichés, skip WordPress entirely, leverage existing infrastructure.

**Tech Stack:**
- **Generator:** Python + Markdown → HTML (or pure HTML if faster)
- **Hosting:** Existing DO droplet (`web@banagale.com` / `143.198.70.216`)
- **Deployment:** SCP script (copy from deploy-cv.sh pattern)
- **Email:** Apple Custom Email via iCloud+ (already used for banagale.com)
- **SSL:** Let's Encrypt (certbot, same as other domains)

**Total Pages:** 3-4 maximum
1. Home (product overview)
2. Privacy Policy (App Store requirement)
3. Support (optional but recommended)
4. Download (can be same as Home initially)

---

## Phase 1: Infrastructure Setup (30 minutes)

### 1.1: DNS & SSL Configuration

**Tasks:**
- [ ] Add DNS A record for `contextify.sh` → `143.198.70.216`
- [ ] Create Nginx vhost for contextify.sh
- [ ] Run certbot for SSL certificate
- [ ] Test HTTPS access

**Commands:**
```bash
# Add DNS via DigitalOcean CLI (you have doctl installed)
doctl compute domain records create contextify.sh \
  --record-type A \
  --record-name @ \
  --record-data 143.198.70.216 \
  --record-ttl 300

# SSH to server
ssh web@banagale.com

# Create web root
sudo mkdir -p /var/www/contextify.sh
sudo chown www-data:www-data /var/www/contextify.sh
sudo chmod 755 /var/www/contextify.sh

# Create Nginx vhost (see config below)
sudo nano /etc/nginx/sites-available/contextify

# Enable site
sudo ln -s /etc/nginx/sites-available/contextify /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Get SSL certificate
sudo certbot --nginx -d contextify.sh -d www.contextify.sh
```

**Nginx Config (`/etc/nginx/sites-available/contextify`):**
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

    # Managed by Certbot (will add SSL config)
}
```

**Acceptance Criteria:**
- [ ] `https://contextify.sh` loads (even with blank page)
- [ ] SSL certificate valid (green lock)
- [ ] No Nginx errors in logs

---

### 1.2: Email Setup (Apple Custom Email)

**You already use this for banagale.com, so process is familiar:**

**Tasks:**
- [ ] Add `contextify.sh` domain to iCloud+ Custom Email
- [ ] Create `hello@contextify.sh` alias
- [ ] Create `support@contextify.sh` alias (optional)
- [ ] Test email receiving

**Steps:**
1. Go to iCloud Settings → Custom Email Domain
2. Add `contextify.sh`
3. Follow verification steps (add TXT records via doctl)
4. Create email aliases

**DNS Records Needed (Apple will provide):**
```bash
# Apple will give you specific values, add via:
doctl compute domain records create contextify.sh \
  --record-type TXT \
  --record-name @ \
  --record-data "apple-domain-verification=XYZ..." \
  --record-ttl 300

# MX records for email routing
doctl compute domain records create contextify.sh \
  --record-type MX \
  --record-name @ \
  --record-data "mx01.mail.icloud.com" \
  --record-priority 10 \
  --record-ttl 300
```

**Test:**
```bash
# Send test email to hello@contextify.sh
# Verify it arrives in your iCloud Mail
```

**Acceptance Criteria:**
- [ ] Email to `hello@contextify.sh` arrives in your inbox
- [ ] Can reply from `hello@contextify.sh`

---

## Phase 2: Content & Design (1-2 hours)

### 2.1: Homepage (`index.html`)

**Design Inspiration: Rogue Amoeba Style**
- Clean, spacious layout
- Large, clear product screenshot
- Simple value proposition
- No jargon, no hype
- Muted color palette (grays, blues)
- Sans-serif typography (system fonts)

**Content Sections:**
1. **Hero:** Product name + tagline + screenshot
2. **What it does:** 3-4 bullet points
3. **Download:** Direct download link or "Coming Soon"
4. **System Requirements:** macOS version
5. **Footer:** Privacy Policy link, Email contact

**Copywriting Principles:**
- **Clear over clever:** "Monitor your Claude Code sessions" not "Revolutionize AI workflows"
- **Specific over generic:** "Real-time timeline with LLM summaries" not "Powerful insights"
- **Benefit over feature:** "Never lose track of AI conversations" not "Local SQLite database"

**Example Copy (Draft):**

```markdown
# Contextify

A macOS app for monitoring your Claude Code and Codex CLI sessions.

## What it does

- **Real-time timeline** of your AI coding sessions
- **Local database** backup of all conversations
- **LLM-generated summaries** using macOS on-device intelligence
- **Project-centric view** across multiple sessions

## System Requirements

- macOS 15 (Sequoia) or later
- Full features require macOS 26 (Tahoe) for on-device LLM

## Download

Coming soon to the Mac App Store.

[Privacy Policy](privacy.html) • [Support](mailto:hello@contextify.sh)
```

**See Section 2.4 for full HTML template**

---

### 2.2: Privacy Policy (`privacy.html`)

**Strategy:** Use a template and customize minimally.

**Key Points to Cover (App Store Requirements):**
1. What data you collect (local only, no analytics)
2. How data is used (user's own database)
3. Third-party services (none)
4. Data retention (user controls)
5. Contact information

**Template Sources:**
- https://www.freeprivacypolicy.com/free-privacy-policy-generator/
- https://app-privacy-policy-generator.firebaseapp.com/

**Customization Needed:**
- App name: Contextify
- Developer: Your name/entity
- Data collection: "All data stored locally on user's Mac"
- No analytics, no tracking, no third-party services
- Contact: hello@contextify.sh

**Template Variables:**
```
App Name: Contextify
Developer: Rob Banagale (or LLC if applicable)
Website: https://contextify.sh
Contact: hello@contextify.sh
Last Updated: 2025-11-11

Data Collected: None (all local)
Third-party Services: None
Cookies: None
Analytics: None
```

**Action:**
- [ ] Generate privacy policy via template generator
- [ ] Save as `privacy.html`
- [ ] Review for accuracy
- [ ] Add to site

**Alternative:** Use ChatGPT/Claude to generate based on your specs (faster than web forms)

---

### 2.3: Support Page (Optional but Recommended)

**Purpose:** Give users a place to ask questions, deflects support emails initially.

**Content:**
```markdown
# Support

## Getting Started

Contextify automatically discovers Claude Code and Codex projects in:
- `~/.claude/projects/`
- `~/.codex/sessions/`

The first launch will scan these directories and ingest conversation history.

## Common Questions

**Q: How do I change the active project?**
A: Use the project tabs at the top of the window, or press Cmd+Shift+P.

**Q: Where is my data stored?**
A: All data is stored locally in `~/Library/Application Support/Contextify/contextify.db`

**Q: Can I use a custom database location?**
A: Yes, go to Settings → Database tab to choose a custom location.

## Contact

Email: [hello@contextify.sh](mailto:hello@contextify.sh)

We typically respond within 24-48 hours.
```

---

### 2.4: HTML Template (Clean, Rogue Amoeba-inspired)

**File:** `template.html` (used for all pages)

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="Contextify - Monitor your Claude Code and Codex CLI sessions on macOS">
    <title>Contextify - AI Session Monitoring for macOS</title>
    <style>
        :root {
            --bg: #ffffff;
            --text: #2c2c2c;
            --text-muted: #666666;
            --accent: #0066cc;
            --border: #e0e0e0;
            --code-bg: #f5f5f5;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text);
            background: var(--bg);
            padding: 20px;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
        }

        header {
            margin-bottom: 60px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border);
        }

        h1 {
            font-size: 2.5rem;
            font-weight: 600;
            margin-bottom: 10px;
        }

        .tagline {
            font-size: 1.25rem;
            color: var(--text-muted);
            margin-bottom: 30px;
        }

        h2 {
            font-size: 1.75rem;
            font-weight: 600;
            margin: 40px 0 20px 0;
        }

        h3 {
            font-size: 1.25rem;
            font-weight: 600;
            margin: 30px 0 15px 0;
        }

        p {
            margin-bottom: 15px;
        }

        ul, ol {
            margin-bottom: 20px;
            margin-left: 20px;
        }

        li {
            margin-bottom: 10px;
        }

        a {
            color: var(--accent);
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        .screenshot {
            width: 100%;
            border: 1px solid var(--border);
            border-radius: 8px;
            margin: 30px 0;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }

        .download-btn {
            display: inline-block;
            background: var(--accent);
            color: white;
            padding: 12px 24px;
            border-radius: 6px;
            font-weight: 500;
            margin: 20px 0;
        }

        .download-btn:hover {
            background: #0052a3;
            text-decoration: none;
        }

        .requirements {
            background: var(--code-bg);
            padding: 20px;
            border-radius: 6px;
            margin: 20px 0;
        }

        footer {
            margin-top: 60px;
            padding-top: 20px;
            border-top: 1px solid var(--border);
            color: var(--text-muted);
            font-size: 0.9rem;
        }

        footer a {
            margin: 0 10px;
        }

        code {
            background: var(--code-bg);
            padding: 2px 6px;
            border-radius: 3px;
            font-family: "SF Mono", Monaco, monospace;
            font-size: 0.9em;
        }

        @media (max-width: 600px) {
            h1 {
                font-size: 2rem;
            }

            .tagline {
                font-size: 1.1rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Contextify</h1>
            <p class="tagline">Monitor your Claude Code and Codex CLI sessions on macOS</p>
        </header>

        <main>
            <!-- PAGE CONTENT GOES HERE -->
        </main>

        <footer>
            <p>
                &copy; 2025 Contextify. All rights reserved.
                <br>
                <a href="privacy.html">Privacy Policy</a>
                <a href="mailto:hello@contextify.sh">Contact</a>
            </p>
        </footer>
    </div>
</body>
</html>
```

**Usage:**
1. Copy template for each page
2. Replace `<!-- PAGE CONTENT GOES HERE -->` with actual content
3. Update `<title>` and `<meta name="description">` per page

---

### 2.5: Homepage Content (Full)

**File:** `index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="Contextify - Monitor your Claude Code and Codex CLI sessions on macOS">
    <title>Contextify - AI Session Monitoring for macOS</title>
    <!-- COPY FULL <style> FROM TEMPLATE ABOVE -->
</head>
<body>
    <div class="container">
        <header>
            <h1>Contextify</h1>
            <p class="tagline">Monitor your Claude Code and Codex CLI sessions on macOS</p>
        </header>

        <main>
            <!-- Screenshot placeholder - replace with actual screenshot -->
            <img src="screenshot.png" alt="Contextify Screenshot" class="screenshot">

            <h2>What it does</h2>
            <ul>
                <li><strong>Real-time timeline</strong> of your AI coding sessions</li>
                <li><strong>Local database backup</strong> of all conversations</li>
                <li><strong>LLM-generated summaries</strong> using macOS on-device intelligence</li>
                <li><strong>Project-centric view</strong> across multiple sessions</li>
                <li><strong>Transcript repair tool</strong> for corrupted Claude Code Web sessions</li>
            </ul>

            <h2>Download</h2>
            <p>Coming soon to the Mac App Store.</p>
            <!-- When ready, replace with: -->
            <!-- <a href="Contextify-v1.0.dmg" class="download-btn">Download for macOS</a> -->

            <div class="requirements">
                <h3>System Requirements</h3>
                <ul>
                    <li>macOS 15 (Sequoia) or later</li>
                    <li>macOS 26 (Tahoe) required for LLM summaries</li>
                    <li>Works with Claude Code and Codex CLI</li>
                </ul>
            </div>

            <h2>Features</h2>

            <h3>Project Discovery</h3>
            <p>Automatically discovers Claude Code and Codex projects on your Mac. Switch between projects with a single click.</p>

            <h3>Timeline View</h3>
            <p>See a chronological view of all messages in your AI sessions. Each entry includes a summary generated by macOS's on-device LLM (Sequoia only).</p>

            <h3>Local Storage</h3>
            <p>All data stored locally in a SQLite database. No cloud services, no tracking, no analytics. Your conversations stay on your Mac.</p>

            <h3>Transcript Repair</h3>
            <p>Built-in tool to detect and repair corrupted Claude Code Web transcripts that cause API 400 errors when resuming sessions.</p>
        </main>

        <footer>
            <p>
                &copy; 2025 Contextify. All rights reserved.
                <br>
                <a href="privacy.html">Privacy Policy</a>
                <a href="support.html">Support</a>
                <a href="mailto:hello@contextify.sh">Contact</a>
            </p>
        </footer>
    </div>
</body>
</html>
```

---

## Phase 3: Deployment Automation (30 minutes)

### 3.1: Create Deployment Script

**File:** `scripts/deploy-website.sh`

**Based on your existing `deploy-cv.sh` pattern:**

```bash
#!/bin/bash
#
# deploy-website.sh - Deploy contextify.sh website to server
#
# Usage: ./scripts/deploy-website.sh [--dry-run]
#

set -e

# Configuration
SERVER="web@banagale.com"
REMOTE_DIR="/var/www/contextify.sh"
LOCAL_DIR="website"  # Local directory with HTML files
TEMP_UPLOAD_DIR="/home/web/contextify-upload"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

echo -e "${YELLOW}Deploying contextify.sh website...${NC}"

# Validate local directory exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo -e "${RED}Error: Local directory not found: $LOCAL_DIR${NC}"
    exit 1
fi

# List files to deploy
echo -e "${YELLOW}Files to deploy:${NC}"
find "$LOCAL_DIR" -type f | sed "s|^$LOCAL_DIR/||"
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN - no files will be uploaded${NC}"
    exit 0
fi

# Create temp upload directory on server
echo -e "${YELLOW}Creating temp upload directory...${NC}"
ssh "$SERVER" "mkdir -p $TEMP_UPLOAD_DIR"

# Upload files via rsync
echo -e "${YELLOW}Uploading files...${NC}"
rsync -avz --delete \
    "$LOCAL_DIR/" \
    "$SERVER:$TEMP_UPLOAD_DIR/"

# Move to final location and set permissions
echo -e "${YELLOW}Moving to /var/www and setting permissions...${NC}"
ssh "$SERVER" "sudo rsync -a --delete $TEMP_UPLOAD_DIR/ $REMOTE_DIR/ && \
               sudo chown -R www-data:www-data $REMOTE_DIR && \
               sudo find $REMOTE_DIR -type f -exec chmod 644 {} \; && \
               sudo find $REMOTE_DIR -type d -exec chmod 755 {} \; && \
               rm -rf $TEMP_UPLOAD_DIR"

# Test site accessibility
echo -e "${YELLOW}Testing site accessibility...${NC}"
sleep 2
if curl -fsSL https://contextify.sh > /dev/null; then
    echo -e "${GREEN}✓ SUCCESS: Website deployed and accessible!${NC}"
    echo -e "${GREEN}✓ Visit: https://contextify.sh${NC}"
else
    echo -e "${RED}✗ WARNING: Site may not be accessible yet${NC}"
    echo -e "${YELLOW}Check Nginx config and SSL certificate${NC}"
fi
```

**Make executable:**
```bash
chmod +x scripts/deploy-website.sh
```

---

### 3.2: Local Website Directory Structure

```
contextify/
├── scripts/
│   └── deploy-website.sh
└── website/
    ├── index.html
    ├── privacy.html
    ├── support.html
    ├── screenshot.png  (add later)
    └── (optional: css/, images/, etc.)
```

**Initialize directory:**
```bash
mkdir -p website
cd website
# Create HTML files here (see Phase 2)
```

---

## Phase 4: Screenshot & Assets (15 minutes)

### 4.1: Screenshot Checklist

**What to capture:**
- [ ] Main window with timeline visible
- [ ] Multiple projects in switcher tabs
- [ ] At least 5-10 timeline entries visible
- [ ] Some entries with LLM summaries (if macOS 26)
- [ ] Clean, uncluttered workspace

**Screenshot Specifications:**
- Resolution: 2880x1800 (Retina) or similar
- Format: PNG (best quality) or JPG (smaller size)
- Dimensions: Max 1600px wide for web
- Optimize: Use ImageOptim or similar

**macOS Screenshot Commands:**
```bash
# Capture specific window (Cmd+Shift+4, then Space, click window)
# Saves to ~/Desktop/Screenshot YYYY-MM-DD at HH.MM.SS.png

# Or use screencapture CLI:
screencapture -w ~/Desktop/contextify-screenshot.png
# (-w = window mode, click on Contextify window)
```

**Processing:**
```bash
# Resize to web-friendly size
sips -Z 1600 contextify-screenshot.png

# Optimize (if you have ImageOptim CLI)
imageoptim contextify-screenshot.png

# Or use online: tinypng.com, squoosh.app
```

**Deployment:**
```bash
cp ~/Desktop/contextify-screenshot.png website/screenshot.png
```

---

### 4.2: Favicon (Optional)

**Quick Favicon:**
1. Use app icon PNG (export from Xcode)
2. Convert to `.ico` format: https://favicon.io/favicon-converter/
3. Add to `website/favicon.ico`

**Update HTML (add to `<head>`):**
```html
<link rel="icon" type="image/x-icon" href="favicon.ico">
<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">
```

---

## Phase 5: Testing & Launch (15 minutes)

### 5.1: Pre-Launch Checklist

**Infrastructure:**
- [ ] DNS resolves: `dig contextify.sh`
- [ ] HTTPS works: `curl -I https://contextify.sh`
- [ ] SSL certificate valid (check in browser)
- [ ] Email works: send test to `hello@contextify.sh`

**Content:**
- [ ] All links work (Privacy, Support, Contact)
- [ ] No placeholder text left
- [ ] Screenshot displays correctly
- [ ] Mobile responsive (test on phone or resize browser)
- [ ] No typos (proofread 2x)

**App Store Requirements:**
- [ ] Privacy Policy link is accessible
- [ ] Contact email is valid
- [ ] Website loads within 2 seconds

**Cross-browser Testing:**
- [ ] Safari (primary macOS browser)
- [ ] Chrome (most common)
- [ ] Firefox (optional)

---

### 5.2: Launch Commands

```bash
# 1. Build website locally (if using generator)
# cd contextify/website
# (manual HTML editing - no build step needed)

# 2. Test locally (optional - use Python HTTP server)
cd website
python3 -m http.server 8000
# Visit http://localhost:8000

# 3. Deploy to server
cd ..
./scripts/deploy-website.sh

# 4. Verify deployment
curl -I https://contextify.sh
curl -s https://contextify.sh | grep -i "contextify"

# 5. Test from different location (use phone, VPN, or ask friend)
```

---

## Phase 6: Post-Launch (Ongoing)

### 6.1: Analytics (Optional)

**Recommendation:** Skip analytics initially. Add later if needed.

**If you want basic stats:**
- **Server logs:** Parse Nginx access logs
- **Privacy-friendly:** Plausible Analytics (self-hosted or paid)
- **Dead simple:** GoatCounter (open source, free tier)

**Implementation (GoatCounter example):**
```html
<!-- Add before </body> in all pages -->
<script data-goatcounter="https://contextify.goatcounter.com/count"
        async src="//gc.zgo.at/count.js"></script>
```

---

### 6.2: Content Updates

**Common updates:**
- [ ] Add "Download" link when app is ready
- [ ] Update system requirements if they change
- [ ] Add FAQ items based on user questions
- [ ] Add testimonials/reviews if you get them

**Update workflow:**
```bash
# 1. Edit HTML files in website/
# 2. Test locally (optional)
python3 -m http.server 8000

# 3. Deploy
./scripts/deploy-website.sh

# 4. Verify
open https://contextify.sh
```

---

### 6.3: Monitoring

**Uptime Monitoring:**
- Use DigitalOcean built-in monitoring (free)
- Or: UptimeRobot (free for 50 monitors)
- Or: Simple cron + curl script

**Setup DigitalOcean Monitoring:**
1. Go to DO dashboard → Monitoring
2. Add uptime check for `https://contextify.sh`
3. Set alert email to `rob@banagale.com`

---

## Alternative: Faster MVP (Pure HTML, No Deployment Script)

**If you need website live in <1 hour:**

### Quick Path:

1. **Skip deployment script** - use SFTP/SCP directly
2. **Single-page website** - combine Privacy Policy into footer
3. **No screenshot** - use placeholder text or skip entirely
4. **Manual upload:**

```bash
# Create minimal index.html
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Contextify - AI Session Monitoring for macOS</title>
    <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; line-height: 1.6; }
        h1 { margin-bottom: 10px; }
        .tagline { color: #666; margin-bottom: 30px; }
    </style>
</head>
<body>
    <h1>Contextify</h1>
    <p class="tagline">Monitor your Claude Code and Codex CLI sessions on macOS.</p>

    <h2>Features</h2>
    <ul>
        <li>Real-time timeline of AI conversations</li>
        <li>Local database backup</li>
        <li>LLM-powered summaries (macOS 26 Tahoe+)</li>
    </ul>

    <h2>Download</h2>
    <p>Coming soon to the Mac App Store.</p>

    <h2>Privacy</h2>
    <p>All data is stored locally on your Mac. No tracking, no analytics, no cloud services.</p>

    <p><small>Contact: <a href="mailto:hello@contextify.sh">hello@contextify.sh</a></small></p>
</body>
</html>
EOF

# Upload directly
scp index.html web@banagale.com:/home/web/
ssh web@banagale.com 'sudo mv /home/web/index.html /var/www/contextify.sh/ && sudo chown www-data:www-data /var/www/contextify.sh/index.html && sudo chmod 644 /var/www/contextify.sh/index.html'

# Done! Visit https://contextify.sh
```

**Time to complete:** 20-30 minutes (including DNS setup)

---

## Decision Matrix: Which Path?

| Approach | Time | Quality | Flexibility | Recommendation |
|----------|------|---------|-------------|----------------|
| **Full Plan (Phases 1-6)** | 2-4 hours | High | High | Best for long-term |
| **Quick Path (Alternative)** | 30 min | Medium | Low | Launch today, iterate later |
| **Hybrid (Phases 1-2 + Quick deploy)** | 1-2 hours | Medium-High | Medium | **RECOMMENDED** |

---

## Recommended Hybrid Approach

**Day 1 (Today):** Phases 1-2 + Quick Deploy (1-2 hours)
1. Set up DNS + SSL (30 min)
2. Set up email (15 min)
3. Create simple HTML pages (30 min)
4. Manual SCP upload (5 min)
5. Test and verify (10 min)

**Day 2 (Tomorrow):** Phases 3-4 (1 hour)
1. Create deployment script (30 min)
2. Add screenshot (15 min)
3. Polish content (15 min)
4. Redeploy with script

**Week 2 (After App Store submission):** Phase 5-6
1. Add analytics if desired
2. Expand FAQ based on feedback
3. Add testimonials

---

## App Store Submission Checklist

**Website requirements for App Store:**
- [x] Working HTTPS website
- [x] Privacy Policy accessible via public URL
- [x] Support/Contact email address
- [ ] (Optional) Link to website in app's "About" window

**Submit these URLs:**
- **Marketing URL:** `https://contextify.sh`
- **Privacy Policy URL:** `https://contextify.sh/privacy.html`
- **Support URL:** `hello@contextify.sh` (or `https://contextify.sh/support.html`)

---

## Budget & Costs

**One-time:**
- Domain: $34.98/year (already purchased)
- SSL: Free (Let's Encrypt)
- Hosting: Free (using existing droplet)

**Recurring:**
- Domain renewal: $34.98/year
- Email: Free (included with iCloud+)
- Hosting: $0 extra (shared with banagale.com)

**Total first year:** $35
**Total recurring:** $35/year

---

## Next Steps

**Choose your path:**

**Option A: Get live today (1-2 hours)**
```bash
# Execute Phases 1-2 + Quick Deploy
# Goal: https://contextify.sh live by end of day
```

**Option B: Full implementation (2-4 hours across 2 days)**
```bash
# Execute all phases methodically
# Goal: Polished site with deployment automation
```

**Recommendation:** Start with Option A, iterate to Option B.

---

## Appendix: Resources

### Design Inspiration
- **Rogue Amoeba:** https://rogueamoeba.com/ (clean, minimal, Mac-native feel)
- **Panic:** https://panic.com/ (playful but professional)
- **Bare Bones Software:** https://www.barebones.com/ (straightforward, no-nonsense)
- **Many Tricks:** https://manytricks.com/ (simple, clear value props)

### Privacy Policy Generators
- https://www.freeprivacypolicy.com/free-privacy-policy-generator/
- https://app-privacy-policy-generator.firebaseapp.com/
- https://www.privacypolicies.com/privacy-policy-generator/

### Tools
- **HTML Validator:** https://validator.w3.org/
- **SSL Test:** https://www.ssllabs.com/ssltest/
- **Mobile Test:** https://search.google.com/test/mobile-friendly
- **Image Optimizer:** https://squoosh.app/

---

**End of Implementation Plan**

Ready to start? Let's begin with Phase 1: Infrastructure Setup.
