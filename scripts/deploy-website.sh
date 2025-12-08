#!/bin/bash
#
# deploy-website.sh - Deploy contextify.sh website to server
#
# Usage: ./scripts/deploy-website.sh [--dry-run] [--force]
#
# Options:
#   --dry-run  Preview files without uploading
#   --force    Skip git clean/pushed checks
#
# Pre-flight checks (unless --force):
#   - Working tree must be clean (no uncommitted changes in website/)
#   - Current branch must be pushed to origin
#   - Warns if not on main branch (prompts to stop)
#
# Safety features:
#   - Archives current site before deploying (rolling 5 backups)
#   - Warns about server content that will be removed
#   - Protects server-side directories (stats/)
#
# Writes .version file to deployed site with git hash and timestamp
#

set -e

# Configuration
SERVER="web@banagale.com"
REMOTE_DIR="/var/www/contextify.sh"
LOCAL_DIR="website"
TEMP_UPLOAD_DIR="/home/web/contextify-upload"
ARCHIVE_DIR="/var/www/contextify-archives"
KEEP_ARCHIVES=5

# Server-side directories to preserve (not in local website/)
# These are generated/maintained on the server and should never be deleted
PROTECTED_DIRS=(
    'stats'    # GoAccess analytics - see build/docs/operations/website-analytics.md
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Parse arguments
DRY_RUN=false
FORCE=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
    esac
done

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Deploying contextify.sh website${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Pre-flight checks (skip with --force)
if ! $FORCE; then
    # Check for clean working tree
    if ! git diff --quiet HEAD -- "$LOCAL_DIR"; then
        echo -e "${RED}Error: Uncommitted changes in $LOCAL_DIR${NC}"
        echo "Commit your changes or use --force to deploy anyway"
        exit 1
    fi

    # Check if pushed to origin
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse @{u} 2>/dev/null || echo "no-upstream")

    if [[ "$REMOTE_HASH" == "no-upstream" ]]; then
        echo -e "${RED}Error: No upstream branch configured${NC}"
        echo "Push your branch or use --force to deploy anyway"
        exit 1
    fi

    if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
        echo -e "${RED}Error: Local commits not pushed to origin${NC}"
        echo "Push your changes or use --force to deploy anyway"
        exit 1
    fi

    echo -e "${GREEN}✓ Git state clean and pushed${NC}"

    # Warn if not on main branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  WARNING: You are on branch '$CURRENT_BRANCH', not 'main'${NC}"
        echo -e "${YELLOW}   Consider merging to main before deploying to production.${NC}"
        echo ""
        read -p "Stop deploying? [Y/n] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "${RED}Deployment cancelled.${NC}"
            exit 1
        fi
        echo ""
    fi
fi

# Validate local directory exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo -e "${RED}Error: Local directory not found: $LOCAL_DIR${NC}"
    echo "Run this script from the project root: ./scripts/deploy-website.sh"
    exit 1
fi

# List files to deploy (respecting exclusions)
echo -e "${YELLOW}Files to deploy:${NC}"
find "$LOCAL_DIR" -type f \
    -not -name '.DS_Store' \
    -not -name '*.mov' \
    -not -name 'README.md' \
    -not -name 'QUICKSTART.txt' \
    -not -path '*/drafts/*' \
    | sed "s|^$LOCAL_DIR/||" | sort
echo ""

# Count files
FILE_COUNT=$(find "$LOCAL_DIR" -type f \
    -not -name '.DS_Store' \
    -not -name '*.mov' \
    -not -name 'README.md' \
    -not -name 'QUICKSTART.txt' \
    -not -path '*/drafts/*' \
    | wc -l | tr -d ' ')
echo "Total files: $FILE_COUNT"
echo ""

# Build protected dirs exclude args for rsync
PROTECTED_EXCLUDE_ARGS=""
for dir in "${PROTECTED_DIRS[@]}"; do
    PROTECTED_EXCLUDE_ARGS="$PROTECTED_EXCLUDE_ARGS --exclude '$dir'"
done

# Check for unexpected server content that will be removed
echo -e "${YELLOW}Checking server for content that will be affected...${NC}"
SERVER_ITEMS=$(ssh "$SERVER" "ls -1 $REMOTE_DIR 2>/dev/null" || echo "")

if [[ -n "$SERVER_ITEMS" ]]; then
    WILL_DELETE=()
    WILL_PROTECT=()

    while IFS= read -r item; do
        [[ -z "$item" ]] && continue

        # Check if protected
        IS_PROTECTED=false
        for protected in "${PROTECTED_DIRS[@]}"; do
            if [[ "$item" == "$protected" ]]; then
                IS_PROTECTED=true
                break
            fi
        done

        if $IS_PROTECTED; then
            WILL_PROTECT+=("$item")
        elif [[ ! -e "$LOCAL_DIR/$item" ]]; then
            WILL_DELETE+=("$item")
        fi
    done <<< "$SERVER_ITEMS"

    # Show protected directories
    if [[ ${#WILL_PROTECT[@]} -gt 0 ]]; then
        echo -e "${GREEN}✓ Protected (will preserve):${NC}"
        for item in "${WILL_PROTECT[@]}"; do
            echo -e "    ${GREEN}$item/${NC} (server-side, in PROTECTED_DIRS)"
        done
        echo ""
    fi

    # Warn about deletions
    if [[ ${#WILL_DELETE[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}  ⚠️  WARNING: CONTENT WILL BE REMOVED${NC}"
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${RED}The following server content is NOT in local website/ and will be DELETED:${NC}"
        for item in "${WILL_DELETE[@]}"; do
            echo -e "    ${RED}✗ $item${NC}"
        done
        echo ""
        echo -e "${YELLOW}If this is unexpected, you may want to:${NC}"
        echo -e "${YELLOW}  1. Add to PROTECTED_DIRS in this script${NC}"
        echo -e "${YELLOW}  2. Copy content to local website/ directory${NC}"
        echo -e "${YELLOW}  3. Cancel and investigate${NC}"
        echo ""
        echo -e "${CYAN}Note: Previous site version will be archived before deletion.${NC}"
        echo ""
        read -p "Continue with deployment? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Deployment cancelled.${NC}"
            exit 1
        fi
        echo ""
    fi
else
    echo -e "${CYAN}  (Server directory empty or new deployment)${NC}"
    echo ""
fi

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN - no files will be uploaded${NC}"
    exit 0
fi

# Generate version file with deploy info
GIT_HASH=$(git rev-parse HEAD)
GIT_SHORT=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
DEPLOY_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOY_TIMESTAMP=$(date +"%Y-%m-%d_%H%M")

echo -e "${YELLOW}Writing deploy info...${NC}"
cat > "$LOCAL_DIR/.version" << EOF
{
  "commit": "$GIT_HASH",
  "short": "$GIT_SHORT",
  "branch": "$GIT_BRANCH",
  "deployed": "$DEPLOY_TIME"
}
EOF
echo "  Commit: $GIT_SHORT ($GIT_BRANCH)"
echo "  Time:   $DEPLOY_TIME"
echo ""

# Archive current site before deploying
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  Creating backup archive${NC}"
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo ""
ARCHIVE_NAME="${DEPLOY_TIMESTAMP}_${GIT_SHORT}.tar.gz"

echo -e "${YELLOW}Archiving current site to: ${ARCHIVE_DIR}/${ARCHIVE_NAME}${NC}"
echo -e "${CYAN}  This backup can be used to rollback if needed.${NC}"
echo ""

ssh "$SERVER" "
    sudo mkdir -p $ARCHIVE_DIR
    if [ -d '$REMOTE_DIR' ] && [ \"\$(ls -A $REMOTE_DIR 2>/dev/null)\" ]; then
        echo '  Creating archive (excluding protected dirs)...'
        sudo tar -czf $ARCHIVE_DIR/$ARCHIVE_NAME -C $REMOTE_DIR $(for d in "${PROTECTED_DIRS[@]}"; do echo "--exclude='$d'"; done) . 2>/dev/null || true
        ARCHIVE_SIZE=\$(du -h $ARCHIVE_DIR/$ARCHIVE_NAME 2>/dev/null | cut -f1)
        echo \"  Archive created: \$ARCHIVE_SIZE\"
    else
        echo '  No existing content to archive (fresh deployment)'
    fi

    # Keep only last N archives
    ARCHIVE_COUNT=\$(ls -1 $ARCHIVE_DIR/*.tar.gz 2>/dev/null | wc -l)
    if [ \$ARCHIVE_COUNT -gt $KEEP_ARCHIVES ]; then
        echo ''
        echo '  Cleaning old archives (keeping last $KEEP_ARCHIVES)...'
        ls -t $ARCHIVE_DIR/*.tar.gz | tail -n +\$(($KEEP_ARCHIVES + 1)) | xargs -r sudo rm -v
    fi
"
echo ""
echo -e "${GREEN}✓ Backup complete${NC}"
echo ""
echo -e "${CYAN}  To rollback: ssh $SERVER${NC}"
echo -e "${CYAN}               sudo tar -xzf $ARCHIVE_DIR/$ARCHIVE_NAME -C $REMOTE_DIR/${NC}"
echo ""

# Create temp upload directory on server
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  Uploading new content${NC}"
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}Creating temp upload directory on server...${NC}"
ssh "$SERVER" "mkdir -p $TEMP_UPLOAD_DIR"

# Upload files via rsync
echo -e "${YELLOW}Uploading files...${NC}"
rsync -avz --delete \
    --exclude '.DS_Store' \
    --exclude '.git' \
    --exclude 'drafts' \
    --exclude '*.mov' \
    --exclude 'README.md' \
    --exclude 'QUICKSTART.txt' \
    "$LOCAL_DIR/" \
    "$SERVER:$TEMP_UPLOAD_DIR/"

echo ""

# Move to final location and set permissions
echo -e "${YELLOW}Moving to /var/www and setting permissions...${NC}"
ssh "$SERVER" "sudo rsync -a --delete $(for d in "${PROTECTED_DIRS[@]}"; do echo "--exclude '$d'"; done) $TEMP_UPLOAD_DIR/ $REMOTE_DIR/ && \
               sudo chown -R www-data:www-data $REMOTE_DIR && \
               sudo find $REMOTE_DIR -type f -exec chmod 644 {} \; && \
               sudo find $REMOTE_DIR -type d -exec chmod 755 {} \; && \
               rm -rf $TEMP_UPLOAD_DIR"

echo -e "${GREEN}✓ Files copied to $REMOTE_DIR${NC}"
echo ""

# Test site accessibility - check all HTML pages
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  Testing site accessibility${NC}"
echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────${NC}"
echo ""
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

echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}  ✓ DEPLOYMENT SUCCESSFUL${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}All $PASSED pages returned 200${NC}"
else
    echo -e "${BOLD}${RED}  ⚠️  DEPLOYMENT COMPLETE WITH WARNINGS${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}$FAILED page(s) failed, $PASSED passed${NC}"
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

echo ""
echo -e "${CYAN}Archive available at: $ARCHIVE_DIR/$ARCHIVE_NAME${NC}"
echo ""
