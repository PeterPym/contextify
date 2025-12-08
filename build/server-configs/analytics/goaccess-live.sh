#!/bin/bash
# Live view - last hour with minute granularity
# Location: /usr/local/bin/goaccess-live.sh

HOUR_AGO=$(date -d '1 hour ago' '+%d/%b/%Y:%H')
NOW_HOUR=$(date '+%d/%b/%Y:%H')

grep -v '/stats/' /var/log/nginx/contextify.access.log | \
    grep -E "$HOUR_AGO|$NOW_HOUR" | \
    goaccess - \
    -o /var/www/contextify.sh/stats/live.html \
    --config-file=/etc/goaccess/goaccess.conf \
    --date-spec=hr \
    --hour-spec=min \
    --html-report-title="Contextify - Last Hour"
