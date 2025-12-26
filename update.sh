#!/bin/bash

# Default profile
PROFILE=${1:-minimal}

if [[ ! "$PROFILE" =~ ^(minimal|extended|full)$ ]]; then
    echo "Usage: ./update.sh [minimal|extended|full]"
    exit 1
fi

echo "Updating Media Center images (profile: $PROFILE)..."

# 1. Run Cleanup (while services are still up to talk to APIs)
./scripts/cleanup.sh

# 2. Stop and Update
docker compose --profile "$PROFILE" pull
docker compose --profile "$PROFILE" up -d --remove-orphans

echo "Media Center updated and restarted."
