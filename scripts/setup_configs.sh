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

# 2. Radarr
if [ ! -f "$CONFIG_BASE_PATH/radarr/config.xml" ]; then
    echo "Configuring Radarr..."
    cp configs/radarr/config.xml "$CONFIG_BASE_PATH/radarr/config.xml"
fi

# 3. Sonarr
if [ ! -f "$CONFIG_BASE_PATH/sonarr/config.xml" ]; then
    echo "Configuring Sonarr..."
    cp configs/sonarr/config.xml "$CONFIG_BASE_PATH/sonarr/config.xml"
fi

# 4. Lidarr
if [ ! -f "$CONFIG_BASE_PATH/lidarr/config.xml" ]; then
    echo "Configuring Lidarr..."
    cp configs/lidarr/config.xml "$CONFIG_BASE_PATH/lidarr/config.xml"
fi

# 5. Prowlarr
if [ ! -f "$CONFIG_BASE_PATH/prowlarr/config.xml" ]; then
    echo "Configuring Prowlarr..."
    cp configs/prowlarr/config.xml "$CONFIG_BASE_PATH/prowlarr/config.xml"
fi

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
sed -e "s|{VIDEOS_PATH}|$VIDEOS_PATH|g" \
    -e "s|{MUSIC_PATH}|$MUSIC_PATH|g" \
    -e "s|{BOOKS_PATH}|$BOOKS_PATH|g" \
    -e "s|{AUDIOBOOKS_PATH}|$AUDIOBOOKS_PATH|g" \
    -e "s|{USER}|$CURRENT_USER|g" \
    configs/samba/smb.conf > /tmp/smb.conf
sudo mv /tmp/smb.conf /etc/samba/smb.conf
sudo systemctl restart smbd

echo "Configuration setup complete."
