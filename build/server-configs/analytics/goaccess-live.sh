#!/bin/bash
# Live view - last hour with minute granularity
# Location: /usr/local/bin/goaccess-live.sh

# Use UTC to match nginx log timestamps
export TZ="UTC"
HOUR_AGO=$(date -d '1 hour ago' '+%d/%b/%Y:%H')
NOW_HOUR=$(date '+%d/%b/%Y:%H')
TMPFILE=$(mktemp)

# Read both current and rotated log for edge cases around rotation time
cat /var/log/nginx/contextify.access.log /var/log/nginx/contextify.access.log.1 2>/dev/null | \
    grep -v '/stats/' | grep -E "$HOUR_AGO|$NOW_HOUR" > "$TMPFILE"

goaccess "$TMPFILE" \
    -o /var/www/contextify.sh/stats/live.html \
    --config-file=/etc/goaccess/goaccess.conf \
    --tz=America/Los_Angeles \
    --date-spec=hr \
    --hour-spec=min \
    --html-report-title="Contextify - Last Hour"
rm -f "$TMPFILE"
