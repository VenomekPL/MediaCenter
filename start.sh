#!/bin/bash

# Default profile
PROFILE=${1:-minimal}

if [[ ! "$PROFILE" =~ ^(minimal|extended|full)$ ]]; then
    echo "Usage: ./start.sh [minimal|extended|full]"
    exit 1
fi

echo "Starting Media Center with profile: $PROFILE..."

# 1. Fix Environment Paths (Expand ~ to absolute paths)
./scripts/fix_env.sh

# 2. Hardware Discovery
# ./scripts/discover_hardware.sh

# 3. Service Configuration (Pre-seeding configs)
./scripts/setup_configs.sh

# 3. Native Installation (Kodi, Samba, etc.)
# Check if a marker file exists to avoid re-running full install every time
if [ ! -f ".native_installed" ]; then
    echo "First run detected. Installing native components..."
    ./scripts/install_native.sh
    touch .native_installed
fi

# 3. Docker Compose
sudo docker compose --profile "$PROFILE" up -d

echo "Waiting for services to initialize..."
sleep 10

# 4. Service Linking (Automation)
echo "Linking services and configuring automations..."
./scripts/link_services.sh "$PROFILE"

echo "Media Center startup complete!"
echo "Check logs with 'docker compose logs -f'"
