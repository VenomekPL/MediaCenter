#!/bin/bash

# Default profile
PROFILE=${1:-minimal}

if [[ ! "$PROFILE" =~ ^(minimal|extended|full)$ ]]; then
    echo "Usage: ./start.sh [minimal|extended|full]"
    exit 1
fi

echo "Starting Media Center with profile: $PROFILE..."

# 1. VPN Configuration Check
if [ -f .env ]; then
    source <(grep -v '^#' .env | sed 's/^/export /')
fi
VPN_PROVIDER="${VPN_SERVICE_PROVIDER:-}"
VPN_KEY="${WIREGUARD_PRIVATE_KEY:-}"
OVPN_USER="${OPENVPN_USER:-}"
if [ -z "$VPN_PROVIDER" ] || { [ -z "$VPN_KEY" ] && [ -z "$OVPN_USER" ]; }; then
    echo "============================================"
    echo "  WARNING: VPN is NOT configured!"
    echo "  Torrent traffic will have NO encryption."
    echo "  Edit .env and set VPN_SERVICE_PROVIDER"
    echo "  and your WireGuard/OpenVPN credentials."
    echo "============================================"
    read -rp "Continue without VPN? (y/N): " vpn_confirm
    if [[ ! "$vpn_confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted. Configure VPN in .env first."
        exit 1
    fi
fi

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
