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
SESSION_ID=$(curl -s -I -u "$TRANSMISSION_USER:$TRANSMISSION_PASS" "http://localhost:$TRANSMISSION_PORT/transmission/rpc" | grep -i X-Transmission-Session-Id | cut -d' ' -f2 | tr -d '\r')

if [ -n "$SESSION_ID" ]; then
    # Get list of torrents that are finished (percentDone = 1 and not downloading)
    # We use a simple heuristic: if they are finished and seeding, we can remove them if they meet criteria.
    # For now, let's remove all torrents that are 100% done and stopped/finished.
    
    TORRENT_IDS=$(curl -s -u "$TRANSMISSION_USER:$TRANSMISSION_PASS" \
        -H "X-Transmission-Session-Id: $SESSION_ID" \
        -d '{"method": "torrent-get", "arguments": {"fields": ["id", "percentDone", "status"]}}' \
        "http://localhost:$TRANSMISSION_PORT/transmission/rpc" | \
        jq -r '.arguments.torrents[] | select(.percentDone == 1 and (.status == 0 or .status == 6)) | .id')

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
find "$DOWNLOADS_PATH" -type f -links 1 -mmin +60 -not -path "*/incomplete/*" -delete

# Clean up empty directories in Downloads
find "$DOWNLOADS_PATH" -type d -empty -not -path "$DOWNLOADS_PATH" -delete

echo "Cleanup complete."
