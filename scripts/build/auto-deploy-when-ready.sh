#!/bin/bash
#
# auto-deploy-when-ready.sh - Automatically deploy once DNS propagates
#
# This script watches /tmp/dns_status.txt and deploys when ready
#

set -e

echo "Waiting for DNS propagation..."
echo "Monitoring: /tmp/dns_status.txt"
echo ""

while true; do
    if [ -f /tmp/dns_status.txt ]; then
        STATUS=$(cat /tmp/dns_status.txt)

        if [ "$STATUS" == "READY" ]; then
            echo "✅ DNS PROPAGATED! Starting deployment..."
            echo ""

            # Run server setup
            cd /Users/rob/code/projects/contextify
            ./scripts/build/setup-server.sh

            # Deploy website
            ./scripts/deploy-website.sh

            echo ""
            echo "=================================================="
            echo "🎉 DEPLOYMENT COMPLETE!"
            echo "=================================================="
            echo ""
            echo "Website live at: https://contextify.sh"
            echo ""
            echo "Next steps:"
            echo "  1. Setup Apple Custom Email (see docs)"
            echo "  2. Test all pages load"
            echo "  3. Send test email to hello@contextify.sh"
            echo ""

            exit 0
        elif [ "$STATUS" == "TIMEOUT" ]; then
            echo "⏰ DNS propagation timed out after 30 minutes"
            echo "Check Namecheap nameservers are set correctly"
            exit 1
        fi
    fi

    sleep 30
done
