#!/bin/bash

# Default profile
PROFILE=${1:-minimal}

if [[ ! "$PROFILE" =~ ^(minimal|extended|full)$ ]]; then
    echo "Usage: ./stop.sh [minimal|extended|full]"
    exit 1
fi

echo "Stopping Media Center (profile: $PROFILE)..."

docker compose --profile "$PROFILE" stop

echo "Media Center stopped."
