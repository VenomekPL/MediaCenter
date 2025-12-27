#!/bin/bash

# Load .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Default values if not in .env
CONFIG_BASE_PATH=${CONFIG_BASE_PATH:-./config}
DOWNLOADS_PATH=${DOWNLOADS_PATH:-~/Downloads}
MOVIES_PATH=${MOVIES_PATH:-~/Videos/Movies}
TV_PATH=${TV_PATH:-~/Videos/TvSeries}
MUSIC_PATH=${MUSIC_PATH:-~/Music}
BOOKS_PATH=${BOOKS_PATH:-~/Documents/books}
AUDIOBOOKS_PATH=${AUDIOBOOKS_PATH:-~/Documents/audiobooks}
PODCASTS_PATH=${PODCASTS_PATH:-~/Documents/podcasts}

TRANSMISSION_USER=${TRANSMISSION_USER:-admin}
TRANSMISSION_PASS=${TRANSMISSION_PASS:-password}
SAMBA_PASS=${SAMBA_PASS:-password}
CURRENT_USER=$(whoami)

# Expand tilde in paths
DOWNLOADS_PATH="${DOWNLOADS_PATH/#\~/$HOME}"
MOVIES_PATH="${MOVIES_PATH/#\~/$HOME}"
TV_PATH="${TV_PATH/#\~/$HOME}"
MUSIC_PATH="${MUSIC_PATH/#\~/$HOME}"
BOOKS_PATH="${BOOKS_PATH/#\~/$HOME}"
AUDIOBOOKS_PATH="${AUDIOBOOKS_PATH/#\~/$HOME}"
PODCASTS_PATH="${PODCASTS_PATH/#\~/$HOME}"
VIDEOS_PATH=$(dirname "$MOVIES_PATH")

echo "Setting up service configurations..."

# Create base directories
mkdir -p "$CONFIG_BASE_PATH"/{transmission,radarr,sonarr,lidarr,prowlarr,homeassistant}
mkdir -p "$DOWNLOADS_PATH/incomplete"
mkdir -p "$MOVIES_PATH"
mkdir -p "$TV_PATH"
mkdir -p "$MUSIC_PATH"
mkdir -p "$BOOKS_PATH"
mkdir -p "$AUDIOBOOKS_PATH"
mkdir -p "$PODCASTS_PATH"

# 1. Transmission
if [ ! -f "$CONFIG_BASE_PATH/transmission/settings.json" ]; then
    echo "Configuring Transmission..."
    sed -e "s|{TRANSMISSION_USER}|$TRANSMISSION_USER|g" \
        -e "s|{TRANSMISSION_PASS}|$TRANSMISSION_PASS|g" \
        configs/transmission/settings.json > "$CONFIG_BASE_PATH/transmission/settings.json"
fi

# Function to enforce API Key and Auth settings in config.xml
enforce_arr_config() {
    local app=$1
    local config_file="$CONFIG_BASE_PATH/$app/config.xml"
    local template_file="configs/$app/config.xml"
    
    echo "Configuring $app..."
    
    # If config doesn't exist, copy template
    if [ ! -f "$config_file" ]; then
        cp "$template_file" "$config_file"
    else
        echo "  - Updating existing config for $app..."
        # Enforce API Key
        sed -i 's|<ApiKey>.*</ApiKey>|<ApiKey>mediacenter1234567890abcdef</ApiKey>|g' "$config_file"
        # Enforce No Auth (so scripts can access it)
        sed -i 's|<AuthenticationMethod>.*</AuthenticationMethod>|<AuthenticationMethod>None</AuthenticationMethod>|g' "$config_file"
    fi
}

# 2. Radarr
enforce_arr_config "radarr"

# 3. Sonarr
enforce_arr_config "sonarr"

# 4. Lidarr
enforce_arr_config "lidarr"

# 5. Prowlarr
enforce_arr_config "prowlarr"

# 6. Home Assistant
if [ ! -f "$CONFIG_BASE_PATH/homeassistant/configuration.yaml" ]; then
    echo "Configuring Home Assistant..."
    cp configs/homeassistant/configuration.yaml "$CONFIG_BASE_PATH/homeassistant/configuration.yaml"
    touch "$CONFIG_BASE_PATH/homeassistant/automations.yaml"
    touch "$CONFIG_BASE_PATH/homeassistant/scripts.yaml"
    touch "$CONFIG_BASE_PATH/homeassistant/scenes.yaml"
fi

# 7. Samba (Native)
echo "Configuring Samba..."
sudo mkdir -p /etc/samba
sed -e "s|{VIDEOS_PATH}|$VIDEOS_PATH|g" \
    -e "s|{MUSIC_PATH}|$MUSIC_PATH|g" \
    -e "s|{BOOKS_PATH}|$BOOKS_PATH|g" \
    -e "s|{AUDIOBOOKS_PATH}|$AUDIOBOOKS_PATH|g" \
    -e "s|{USER}|$CURRENT_USER|g" \
    configs/samba/smb.conf > /tmp/smb.conf
sudo mv /tmp/smb.conf /etc/samba/smb.conf

# Set Samba password for current user
echo -e "$SAMBA_PASS\n$SAMBA_PASS" | sudo smbpasswd -a -s "$CURRENT_USER"

sudo systemctl restart smbd

# Fix permissions for config directory (Ensure containers can read/write)
echo "Fixing permissions for config directory..."
# Use PUID/PGID from .env or default to 1000
TARGET_UID=${PUID:-1000}
TARGET_GID=${PGID:-1000}
chown -R $TARGET_UID:$TARGET_GID "$CONFIG_BASE_PATH"

echo "Configuration setup complete."
