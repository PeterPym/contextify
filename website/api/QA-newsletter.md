# Newsletter Signup QA Guide

## Branch: `feature/newsletter-signup`

## Visual QA (No Server Needed)

1. Open `website/index.html` directly in browser
2. Scroll to bottom - newsletter section should appear above footer
3. Check both light and dark mode (toggle system appearance)
4. Verify:
   - [ ] "Stay Updated" heading visible
   - [ ] "Get notified when new versions ship..." subtext
   - [ ] Email input field with placeholder "your@email.com"
   - [ ] "Subscribe" button styled with primary color
   - [ ] Section has subtle background (different from page)
   - [ ] Responsive: form stacks nicely on mobile (resize window)

## Functional QA (With Local Server)

### Start the subscribe server:
```bash
cd website/api
SUBSCRIBERS_FILE=/tmp/test-subscribers.txt python3 subscribe.py
```

### Start a local web server (separate terminal):
```bash
cd website
python3 -m http.server 8000
```

### Test in browser:
1. Open http://localhost:8000/
2. Scroll to newsletter form
3. Test cases:

| Test | Input | Expected |
|------|-------|----------|
| Valid email | test@example.com | "Subscribed successfully" (green) |
| Invalid email | "notanemail" | "Invalid email address" (red) |
| Duplicate | Same email twice | "Already subscribed" (green) |
| Empty | (leave blank) | HTML5 validation blocks submit |

4. Verify `/tmp/test-subscribers.txt` contains entries:
```bash
cat /tmp/test-subscribers.txt
```

## Server Deployment Notes

When deploying to production:

1. Copy `subscribe.py` to `/var/www/contextify/api/`
2. Make executable: `chmod +x subscribe.py`
3. Run as systemd service or supervisor
4. Add Nginx proxy config:
```nginx
location /api/subscribe {
    proxy_pass http://127.0.0.1:8080/subscribe;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

## Files Changed

- `website/index.html` - Added newsletter section + JS handler
- `website/styles.css` - Added newsletter section styles
- `website/api/subscribe.py` - Python subscription server (NEW)
