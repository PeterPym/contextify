#!/bin/bash
#
# setup-server.sh - Setup Nginx and SSL for contextify.sh
#
# This script will be run once DNS propagates
#

set -e

SERVER="web@banagale.com"
DOMAIN="contextify.sh"
NGINX_CONF="../build/nginx-contextify.conf"

echo "=================================================="
echo "Setting up contextify.sh on server"
echo "=================================================="
echo ""

# Step 1: Create web root
echo "[1/5] Creating web root directory..."
ssh "$SERVER" "sudo mkdir -p /var/www/$DOMAIN && \
               sudo chown www-data:www-data /var/www/$DOMAIN && \
               sudo chmod 755 /var/www/$DOMAIN"
echo "✓ Web root created"
echo ""

# Step 2: Upload Nginx config
echo "[2/5] Uploading Nginx configuration..."
scp "$NGINX_CONF" "$SERVER:/tmp/contextify.conf"
ssh "$SERVER" "sudo mv /tmp/contextify.conf /etc/nginx/sites-available/contextify && \
               sudo chown root:root /etc/nginx/sites-available/contextify && \
               sudo chmod 644 /etc/nginx/sites-available/contextify"
echo "✓ Nginx config uploaded"
echo ""

# Step 3: Enable site
echo "[3/5] Enabling site and testing config..."
ssh "$SERVER" "sudo ln -sf /etc/nginx/sites-available/contextify /etc/nginx/sites-enabled/ && \
               sudo nginx -t"
echo "✓ Nginx config valid"
echo ""

# Step 4: Reload Nginx
echo "[4/5] Reloading Nginx..."
ssh "$SERVER" "sudo systemctl reload nginx"
echo "✓ Nginx reloaded"
echo ""

# Step 5: Get SSL certificate
echo "[5/5] Getting SSL certificate..."
echo "Running certbot (this may take a minute)..."
ssh "$SERVER" "sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email rob@banagale.com --redirect"
echo "✓ SSL certificate installed"
echo ""

echo "=================================================="
echo "✓ Server setup complete!"
echo "=================================================="
echo ""
echo "Test with:"
echo "  curl -I https://contextify.sh"
echo ""
