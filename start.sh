#!/bin/bash

# Default profile
PROFILE=${1:-minimal}

if [[ ! "$PROFILE" =~ ^(minimal|extended|full)$ ]]; then
    echo "Usage: ./start.sh [minimal|extended|full]"
    exit 1
fi

echo "Starting Media Center with profile: $PROFILE..."

# 1. Hardware Discovery
./scripts/discover_hardware.sh

# 2. Service Configuration (Pre-seeding configs)
./scripts/setup_configs.sh

# 3. Native Installation (Kodi, Samba, etc.)
# Check if a marker file exists to avoid re-running full install every time
if [ ! -f ".native_installed" ]; then
    echo "First run detected. Installing native components..."
    ./scripts/install_native.sh
    touch .native_installed
fi

# 3. Docker Compose
docker compose --profile "$PROFILE" up -d

# 4. Service Linking (Automation)
# Run in background as it waits for services to be ready
./scripts/link_services.sh &

echo "Media Center is starting up. Check logs with 'docker compose logs -f'"
