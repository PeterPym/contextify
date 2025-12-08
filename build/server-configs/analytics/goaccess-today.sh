#!/bin/bash
# Generate today-only stats report (excluding /stats/ and owner IP)
# Location: /usr/local/bin/goaccess-today.sh

TODAY=$(date "+%d/%b/%Y")
grep "$TODAY" /var/log/nginx/contextify.access.log | grep -v '/stats/' | \
    goaccess - \
    -o /var/www/contextify.sh/stats/today.html \
    --config-file=/etc/goaccess/goaccess.conf \
    --html-report-title="Contextify - Today"
