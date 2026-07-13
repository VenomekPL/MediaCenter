#!/bin/bash

# Load .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Default values
TRANSMISSION_USER=${TRANSMISSION_USER:-admin}
TRANSMISSION_PASS=${TRANSMISSION_PASS:-password}
TRANSMISSION_PORT=${TRANSMISSION_PORT:-8020}
DOWNLOADS_PATH=${DOWNLOADS_PATH:-~/Downloads}
DOWNLOADS_PATH="${DOWNLOADS_PATH/#\~/$HOME}"

echo "Starting Media Center Cleanup..."

# 1. Remove Finished/Seeded Torrents from Transmission
echo "Checking for finished torrents in Transmission..."

# Get Session ID
# Use GET (not HEAD): Transmission returns 501 for HEAD on /transmission/rpc
SESSION_ID=$(curl -s -D - -o /dev/null -u "$TRANSMISSION_USER:$TRANSMISSION_PASS" "http://localhost:$TRANSMISSION_PORT/transmission/rpc" | grep -i '^X-Transmission-Session-Id:' | awk '{print $2}' | tr -d '\r')

if [ -n "$SESSION_ID" ]; then
    # Remove torrents that are finished (percentDone = 1) and either:
    #   - stopped (status 0): reached seed-ratio limit (2.0) or manually stopped, or
    #   - seeding (status 6) but already met the 2.0 ratio (safety net for the
    #     brief window before Transmission flips them to stopped).
    # Actively-seeding torrents below 2.0 are left alone so they can finish seeding.
    TORRENT_IDS=$(curl -s -u "$TRANSMISSION_USER:$TRANSMISSION_PASS" \
        -H "X-Transmission-Session-Id: $SESSION_ID" \
        -d '{"method": "torrent-get", "arguments": {"fields": ["id", "percentDone", "status", "uploadRatio"]}}' \
        "http://localhost:$TRANSMISSION_PORT/transmission/rpc" | \
        jq -r '.arguments.torrents[] | select(.percentDone == 1 and (.status == 0 or (.status == 6 and .uploadRatio >= 2.0))) | .id')

    if [ -n "$TORRENT_IDS" ]; then
        for ID in $TORRENT_IDS; do
            echo "Removing finished torrent ID: $ID (and its data from Downloads)..."
            curl -s -u "$TRANSMISSION_USER:$TRANSMISSION_PASS" \
                -H "X-Transmission-Session-Id: $SESSION_ID" \
                -d '{"method": "torrent-remove", "arguments": {"ids": ['$ID'], "delete-local-data": true}}' \
                "http://localhost:$TRANSMISSION_PORT/transmission/rpc" > /dev/null
        done
    else
        echo "No finished torrents to remove."
    fi
else
    echo "Could not connect to Transmission (is it running?). Skipping torrent cleanup."
fi

# 2. Clean up "Dangling" files in Downloads
# These are files that have a link count of 1 (meaning they are NOT hardlinked to the library)
# and are not currently being handled by Transmission (since we just removed finished ones).
echo "Checking for dangling files in $DOWNLOADS_PATH..."

# We only look for files older than 1 hour to avoid deleting active downloads that just started
find "$DOWNLOADS_PATH" -type f -links 1 -mmin +60 -not -path "*/incomplete/*" -not -path "*/watch/*" -delete

# Clean up empty directories in Downloads (preserve incomplete and watch)
find "$DOWNLOADS_PATH" -type d -empty -not -path "$DOWNLOADS_PATH" -not -name "incomplete" -not -name "watch" -delete

echo "Cleanup complete."
