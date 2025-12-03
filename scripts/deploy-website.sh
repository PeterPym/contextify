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
LOCAL_DIR="website"
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
echo ""

# Validate local directory exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo -e "${RED}Error: Local directory not found: $LOCAL_DIR${NC}"
    echo "Run this script from the project root: ./scripts/deploy-website.sh"
    exit 1
fi

# Exclusions
EXCLUDES=(
    '.DS_Store'
    '.git'
    'drafts'
    '*.mov'
)

# Build rsync exclude args
EXCLUDE_ARGS=""
for pattern in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude '$pattern'"
done

# List files to deploy (respecting exclusions)
echo -e "${YELLOW}Files to deploy:${NC}"
find "$LOCAL_DIR" -type f \
    -not -name '.DS_Store' \
    -not -name '*.mov' \
    -not -path '*/drafts/*' \
    | sed "s|^$LOCAL_DIR/||" | sort
echo ""

# Count files
FILE_COUNT=$(find "$LOCAL_DIR" -type f \
    -not -name '.DS_Store' \
    -not -name '*.mov' \
    -not -path '*/drafts/*' \
    | wc -l | tr -d ' ')
echo "Total files: $FILE_COUNT"
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN - no files will be uploaded${NC}"
    exit 0
fi

# Create temp upload directory on server
echo -e "${YELLOW}Creating temp upload directory on server...${NC}"
ssh "$SERVER" "mkdir -p $TEMP_UPLOAD_DIR"

# Upload files via rsync
echo -e "${YELLOW}Uploading files...${NC}"
rsync -avz --delete \
    --exclude '.DS_Store' \
    --exclude '.git' \
    --exclude 'drafts' \
    --exclude '*.mov' \
    "$LOCAL_DIR/" \
    "$SERVER:$TEMP_UPLOAD_DIR/"

echo ""

# Move to final location and set permissions
echo -e "${YELLOW}Moving to /var/www and setting permissions...${NC}"
ssh "$SERVER" "sudo rsync -a --delete $TEMP_UPLOAD_DIR/ $REMOTE_DIR/ && \
               sudo chown -R www-data:www-data $REMOTE_DIR && \
               sudo find $REMOTE_DIR -type f -exec chmod 644 {} \; && \
               sudo find $REMOTE_DIR -type d -exec chmod 755 {} \; && \
               rm -rf $TEMP_UPLOAD_DIR"

echo -e "${GREEN}✓ Files copied to $REMOTE_DIR${NC}"
echo ""

# Test site accessibility - check all HTML pages
echo -e "${YELLOW}Testing site accessibility...${NC}"
sleep 2

# Build list of URLs to check from local HTML files
FAILED=0
PASSED=0

# Find all HTML files and convert to URLs
while IFS= read -r file; do
    # Convert local path to URL
    url_path="${file#$LOCAL_DIR}"

    # Handle index.html -> directory URL
    if [[ "$url_path" == "/index.html" ]]; then
        url="https://contextify.sh/"
    elif [[ "$url_path" == *"/index.html" ]]; then
        url="https://contextify.sh${url_path%/index.html}/"
    else
        url="https://contextify.sh${url_path}"
    fi

    # Check HTTP status
    status=$(curl -o /dev/null -s -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]]; then
        echo -e "${GREEN}  ✓ $url (200)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}  ✗ $url ($status)${NC}"
        ((FAILED++))
    fi
done < <(find "$LOCAL_DIR" -name "*.html" -type f | sort)

echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ SUCCESS: All $PASSED pages returned 200${NC}"
else
    echo -e "${RED}✗ WARNING: $FAILED page(s) failed, $PASSED passed${NC}"
    echo ""
    echo -e "${YELLOW}This could mean:${NC}"
    echo -e "${YELLOW}  1. DNS hasn't propagated yet (wait 5-10 minutes)${NC}"
    echo -e "${YELLOW}  2. Nginx config needs to be created/reloaded${NC}"
    echo -e "${YELLOW}  3. SSL certificate needs to be issued${NC}"
    echo ""
    echo "Check Nginx status:"
    echo "  ssh $SERVER 'sudo systemctl status nginx'"
    echo ""
    echo "Check Nginx config:"
    echo "  ssh $SERVER 'sudo nginx -t'"
fi
