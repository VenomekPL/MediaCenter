#!/bin/bash

ENV_FILE=".env"
EXAMPLE_FILE=".env.example"

# Ensure .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating .env from .env.example..."
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    
    # If running as root (sudo), fix ownership to the real user
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$ENV_FILE"
    fi
else
    echo ".env file already exists. Skipping creation to preserve custom settings."
    # We exit here to prevent overwriting existing configurations with auto-discovery
    # If the user wants to re-discover, they should delete .env or run specific sections manually.
    exit 0
fi

echo "Discovering hardware..."

# 1. Detect Architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# 2. Detect GPU / DRM Device for Jellyfin
DRM_DEVICE=""
if [ -e "/dev/dri/renderD128" ]; then
    DRM_DEVICE="/dev/dri/renderD128"
elif [ -e "/dev/dri/card0" ]; then
    DRM_DEVICE="/dev/dri/card0"
fi

if [ -n "$DRM_DEVICE" ]; then
    echo "Found GPU device: $DRM_DEVICE"
    sed -i "s|JELLYFIN_DRM_DEVICE=.*|JELLYFIN_DRM_DEVICE=$DRM_DEVICE|" "$ENV_FILE"
else
    echo "No GPU device found. Jellyfin transcoding might be slow."
    sed -i "s|JELLYFIN_DRM_DEVICE=.*|JELLYFIN_DRM_DEVICE=|" "$ENV_FILE"
fi

# 3. Detect Zigbee/Z-Wave for Home Assistant
HA_DEVICE=""
if [ -e "/dev/ttyUSB0" ]; then
    HA_DEVICE="/dev/ttyUSB0"
elif [ -e "/dev/ttyACM0" ]; then
    HA_DEVICE="/dev/ttyACM0"
fi

if [ -n "$HA_DEVICE" ]; then
    echo "Found potential Zigbee/Z-Wave device: $HA_DEVICE"
    sed -i "s|HA_ZIGBEE_DEVICE=.*|HA_ZIGBEE_DEVICE=$HA_DEVICE|" "$ENV_FILE"
else
    echo "No Zigbee/Z-Wave device found."
    sed -i "s|HA_ZIGBEE_DEVICE=.*|HA_ZIGBEE_DEVICE=|" "$ENV_FILE"
fi

# 4. Detect PUID/PGID
# ... (existing logic)

echo "Hardware discovery complete. .env updated."

# Restore ownership if running as root
if [ "$EUID" -eq 0 ]; then
    # Try to find the real user from SUDO_USER or fallback to owner of current directory
    REAL_USER=${SUDO_USER:-$(stat -c '%U' .)}
    chown "$REAL_USER" "$ENV_FILE"
fi
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
sed -i "s|PUID=.*|PUID=$CURRENT_UID|" "$ENV_FILE"
sed -i "s|PGID=.*|PGID=$CURRENT_GID|" "$ENV_FILE"

# 5. Detect Local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -n "$LOCAL_IP" ]; then
    echo "Detected Local IP: $LOCAL_IP"
    sed -i "s|LOCAL_IP=.*|LOCAL_IP=$LOCAL_IP|" "$ENV_FILE"
fi

echo "Hardware discovery complete. .env updated."
