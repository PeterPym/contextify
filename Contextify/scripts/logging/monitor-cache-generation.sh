#!/bin/bash
# Monitor Timeline Cache Miss Generator activity
# Usage: bash scripts/logging/monitor-cache-generation.sh [duration_seconds]

DURATION=${1:-60}  # Default 60 seconds
LOGFILE="/tmp/cache-generation-$(date +%Y%m%d-%H%M%S).log"

echo "=== Timeline Cache Miss Generator Monitor ==="
echo "Duration: ${DURATION}s"
echo "Logfile: ${LOGFILE}"
echo ""
echo "Watching for:"
echo "  🟢 Spawning processing task - Task creation"
echo "  🔵 processQueue: start - Processing begins"
echo "  🟡 Queued cache misses - Items added to queue"
echo "  🔷 Processing batch - Batch execution"
echo "  🟣 Batch complete - Batch finished"
echo ""
echo "Press Ctrl+C to stop early..."
echo ""

# Run for specified duration
timeout ${DURATION} log stream \
    --predicate 'subsystem == "dev.contextify.timeline" AND category == "CacheMissGenerator"' \
    --level debug \
    --style compact 2>/dev/null | \
grep --line-buffered -E "Spawning processing task|processQueue: start|Queued.*cache misses|Processing batch|Batch complete" | \
tee "${LOGFILE}" | \
while IFS= read -r line; do
    case "$line" in
        *"Spawning processing task"*)
            echo -e "\033[1;32m🟢 $line\033[0m"
            ;;
        *"processQueue: start"*)
            echo -e "\033[1;34m🔵 $line\033[0m"
            ;;
        *"Queued"*)
            echo -e "\033[1;33m🟡 $line\033[0m"
            ;;
        *"Processing batch"*)
            echo -e "\033[1;36m🔷 $line\033[0m"
            ;;
        *"Batch complete"*)
            echo -e "\033[1;35m🟣 $line\033[0m"
            ;;
        *)
            echo "$line"
            ;;
    esac
done

echo ""
echo "=== Monitoring complete ==="
echo "Full log saved to: ${LOGFILE}"
echo ""
echo "Summary:"
grep -c "Spawning processing task" "${LOGFILE}" 2>/dev/null | xargs -I {} echo "  Task spawns: {}"
grep -c "Queued.*cache misses" "${LOGFILE}" 2>/dev/null | xargs -I {} echo "  Queue events: {}"
grep -c "Batch complete" "${LOGFILE}" 2>/dev/null | xargs -I {} echo "  Batches completed: {}"
