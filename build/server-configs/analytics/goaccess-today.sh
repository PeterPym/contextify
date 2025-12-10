#!/bin/bash
# Generate today-only stats report (excluding /stats/ and owner IP)
# Location: /usr/local/bin/goaccess-today.sh
#
# Log timestamps are UTC. PST day spans two UTC dates:
#   PST Dec 9 00:00 = UTC Dec 9 08:00
#   PST Dec 9 23:59 = UTC Dec 10 07:59
# So we grep for both the PST date AND the next UTC date.

export TZ="America/Los_Angeles"
PST_TODAY=$(date "+%d/%b/%Y")
PST_TOMORROW=$(date -d 'tomorrow' "+%d/%b/%Y")
TMPFILE=$(mktemp)

# Match both UTC dates that comprise "today" in PST
cat /var/log/nginx/contextify.access.log /var/log/nginx/contextify.access.log.1 2>/dev/null | \
    grep -E "$PST_TODAY|$PST_TOMORROW" | grep -v '/stats/' > "$TMPFILE"

goaccess "$TMPFILE" \
    -o /var/www/contextify.sh/stats/today.html \
    --config-file=/etc/goaccess/goaccess.conf \
    --tz=America/Los_Angeles \
    --html-report-title="Contextify - Today"
rm -f "$TMPFILE"
