#!/bin/bash

# Load .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

API_KEY="mediacenter1234567890abcdef"
IP="localhost"

# Ports from .env or defaults
TRANSMISSION_PORT=${TRANSMISSION_PORT:-8020}
RADARR_PORT=${RADARR_PORT:-8021}
SONARR_PORT=${SONARR_PORT:-8022}
LIDARR_PORT=${LIDARR_PORT:-8023}
PROWLARR_PORT=${PROWLARR_PORT:-8024}

wait_for_service() {
    local port=$1
    local name=$2
    echo "Waiting for $name to be ready on port $port..."
    until curl -s "http://$IP:$port" > /dev/null; do
        sleep 5
    done
    echo "$name is ready!"
}

add_transmission_to_arr() {
    local port=$1
    local name=$2
    echo "Adding Transmission to $name..."
    curl -X POST "http://$IP:$port/api/v3/downloadclient?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Transmission",
            "implementation": "Transmission",
            "configContract": "TransmissionSettings",
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "fields": [
                {"name": "host", "value": "transmission"},
                {"name": "port", "value": 9091},
                {"name": "username", "value": "'"$TRANSMISSION_USER"'"},
                {"name": "password", "value": "'"$TRANSMISSION_PASS"'"}
            ]
        }'
}

add_arr_to_prowlarr() {
    local app_port=$1
    local app_name=$2
    local sync_level=$3
    echo "Adding $app_name to Prowlarr..."
    curl -X POST "http://$IP:$PROWLARR_PORT/api/v1/applications?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$app_name"'",
            "implementation": "'"$app_name"'",
            "configContract": "'"$app_name"'Settings",
            "enable": true,
            "syncLevel": "'"$sync_level"'",
            "fields": [
                {"name": "prowlarrUrl", "value": "http://prowlarr:9696"},
                {"name": "baseUrl", "value": "http://'"${app_name,,}"':'"$app_port"'"},
                {"name": "apiKey", "value": "'"$API_KEY"'"}
            ]
        }'
}

# Main execution
echo "Starting service linking automation..."

# Wait for services
wait_for_service $RADARR_PORT "Radarr"
wait_for_service $SONARR_PORT "Sonarr"
wait_for_service $LIDARR_PORT "Lidarr"
wait_for_service $PROWLARR_PORT "Prowlarr"

# Link Transmission
add_transmission_to_arr $RADARR_PORT "Radarr"
add_transmission_to_arr $SONARR_PORT "Sonarr"
add_transmission_to_arr $LIDARR_PORT "Lidarr"

# Link Apps to Prowlarr
add_arr_to_prowlarr $RADARR_PORT "Radarr" "fullSync"
add_arr_to_prowlarr $SONARR_PORT "Sonarr" "fullSync"
add_arr_to_prowlarr $LIDARR_PORT "Lidarr" "fullSync"

echo "Service linking complete!"
