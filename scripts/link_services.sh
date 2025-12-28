#!/bin/bash

# Profile argument (default to full to attempt everything if not specified)
PROFILE=${1:-full}

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
    until curl -s "http://$IP:$port/ping" > /dev/null; do
        sleep 5
    done
    echo "$name is ready!"
    
    # Verify API Key (Try v3 then v1)
    local status=$(curl -s -o /dev/null -w "%{http_code}" "http://$IP:$port/api/v3/system/status?apiKey=$API_KEY")
    if [ "$status" == "404" ]; then
        status=$(curl -s -o /dev/null -w "%{http_code}" "http://$IP:$port/api/v1/system/status?apiKey=$API_KEY")
    fi

    if [ "$status" != "200" ]; then
        echo "WARNING: API Key rejected for $name (Status: $status). Configuration might fail."
        echo "  - Expected Key: $API_KEY"
        echo "  - Please check config.xml or restart the container."
    else
        echo "  - API Key verified."
    fi
}

add_transmission_to_arr() {
    local port=$1
    local name=$2
    local category_field=$3
    
    local api_version="v3"
    if [ "$name" == "Lidarr" ]; then
        api_version="v1"
    fi

    echo "Configuring Transmission for $name (API $api_version)..."
    
    # Check if client exists
    local existing_client=$(curl -s "http://$IP:$port/api/$api_version/downloadclient?apiKey=$API_KEY" | jq -r '.[] | select(.name == "Transmission")')
    
    local payload='{
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
            {"name": "password", "value": "'"$TRANSMISSION_PASS"'"},
            {"name": "'"$category_field"'", "value": ""}
        ]
    }'

    if [ -n "$existing_client" ]; then
        local id=$(echo "$existing_client" | jq -r '.id')
        echo "  - Updating existing client (ID: $id)..."
        # Merge existing ID into payload
        payload=$(echo "$payload" | jq ".id = $id")
        curl -s -X PUT "http://$IP:$port/api/$api_version/downloadclient/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    else
        echo "  - Creating new client..."
        curl -s -X POST "http://$IP:$port/api/$api_version/downloadclient?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

add_arr_to_prowlarr() {
    local internal_port=$1
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
                {"name": "baseUrl", "value": "http://'"${app_name,,}"':'"$internal_port"'"},
                {"name": "apiKey", "value": "'"$API_KEY"'"}
            ]
        }'
}

# Main execution
echo "Starting service linking automation..."

# Wait for services
wait_for_service $RADARR_PORT "Radarr"
wait_for_service $SONARR_PORT "Sonarr"

if [[ "$PROFILE" == "extended" || "$PROFILE" == "full" ]]; then
    wait_for_service $LIDARR_PORT "Lidarr"
    wait_for_service $PROWLARR_PORT "Prowlarr"
fi

# Link Transmission
add_transmission_to_arr $RADARR_PORT "Radarr" "movieCategory"
add_transmission_to_arr $SONARR_PORT "Sonarr" "tvCategory"
# Lidarr uses v1 API for download clients usually, but let's try v3 endpoint first as it might be compatible or proxied.
# If not, we might need a separate function for Lidarr.
# Checking Lidarr API docs, it supports /api/v1/downloadclient. 
# The script uses /api/v3/downloadclient in add_transmission_to_arr.
# Let's assume Lidarr might fail with v3.
# For now, let's comment out Lidarr transmission linking or try it.
# Given the previous 404 on status, Lidarr is definitely v1.
# I will update add_transmission_to_arr to handle API version if needed, but for now let's just fix Radarr/Sonarr.
# I'll pass "musicCategory" for Lidarr but it might fail if endpoint is wrong.
# Actually, I'll just update the calls for Radarr and Sonarr.
# I'll leave Lidarr as is but with the new argument, maybe it works if I change the endpoint in the function.

# Wait, I should make the endpoint version dynamic.
# But for now, let's just fix Radarr and Sonarr.

if [[ "$PROFILE" == "extended" || "$PROFILE" == "full" ]]; then
    add_transmission_to_arr $LIDARR_PORT "Lidarr" "musicCategory"

    # Link Apps to Prowlarr (Using internal ports)
    add_arr_to_prowlarr 7878 "Radarr" "fullSync"
    add_arr_to_prowlarr 8989 "Sonarr" "fullSync"
    add_arr_to_prowlarr 8686 "Lidarr" "fullSync"
fi

# --- New Configuration Functions ---

add_root_folder() {
    local port=$1
    local path=$2
    echo "Adding Root Folder '$path' to service on port $port..."
    curl -s -X POST "http://$IP:$port/api/v3/rootfolder?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d '{ "path": "'"$path"'" }' > /dev/null
}

set_quality_limit() {
    local port=$1
    local max_mb_min=$2
    local app_name=$3
    
    echo "Setting size limits for $app_name to ${max_mb_min} MB/min..."
    
    # Get all definitions
    local definitions=$(curl -s "http://$IP:$port/api/v3/qualitydefinition?apiKey=$API_KEY")
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Cannot configure quality limits."
        return
    fi

    # Iterate through each definition
    for id in $(echo "$definitions" | jq -r '.[].id'); do
        # Get current definition
        local def=$(echo "$definitions" | jq ".[] | select(.id == $id)")
        local current_max=$(echo "$def" | jq '.maxSize')
        
        # If current_max is 0 (unlimited) or greater than target, update it.
        # Using awk for float comparison
        if [ $(echo "$current_max == 0" | awk '{print ($1 == 0)}') -eq 1 ] || \
           [ $(echo "$current_max > $max_mb_min" | awk '{print ($1 > $2)}') -eq 1 ]; then
            
            local name=$(echo "$def" | jq -r '.quality.name')
            # echo "  - Capping $name (was $current_max)..."
            
            local updated_def=$(echo "$def" | jq ".maxSize = $max_mb_min | .preferredSize = $max_mb_min")
            
            curl -s -X PUT "http://$IP:$port/api/v3/qualitydefinition/$id?apiKey=$API_KEY" \
                -H "Content-Type: application/json" \
                -d "$updated_def" > /dev/null
        fi
    done
}

configure_radarr_quality() {
    # 4GB/hour ~= 66.7 MB/min
    set_quality_limit $RADARR_PORT 66.7 "Radarr"
}

configure_sonarr_quality() {
    # 1.5GB/hour ~= 25.0 MB/min
    set_quality_limit $SONARR_PORT 25.0 "Sonarr"
}

configure_radarr_naming() {
    echo "Configuring Radarr Naming..."
    # Get current config
    local config=$(curl -s "http://$IP:$RADARR_PORT/api/v3/config/naming?apiKey=$API_KEY")
    
    # Update config: Rename Movies = True, Format = {Movie Title} ({Release Year})
    # We use jq to update the JSON
    local new_config=$(echo "$config" | jq '.renameMovies = true | .standardMovieFormat = "{Movie Title} ({Release Year})"')
    
    curl -X PUT "http://$IP:$RADARR_PORT/api/v3/config/naming?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d "$new_config"
}

configure_radarr_media_management() {
    echo "Configuring Radarr Media Management..."
    # Get current config
    local config=$(curl -s "http://$IP:$RADARR_PORT/api/v3/config/mediamanagement?apiKey=$API_KEY")
    
    # Update config: Unmonitor Deleted Movies = True
    local new_config=$(echo "$config" | jq '.autoUnmonitorPreviouslyDownloadedMovies = true')
    
    curl -X PUT "http://$IP:$RADARR_PORT/api/v3/config/mediamanagement?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d "$new_config"
}

configure_sonarr_naming() {
    echo "Configuring Sonarr Naming..."
    # Get current config
    local config=$(curl -s "http://$IP:$SONARR_PORT/api/v3/config/naming?apiKey=$API_KEY")
    
    # Update config based on user screenshot
    local new_config=$(echo "$config" | jq '
        .renameEpisodes = true |
        .replaceIllegalCharacters = true |
        .colonReplacementFormat = 4 | 
        .multiEpisodeStyle = 5 |
        .standardEpisodeFormat = "{Series Title} - S{season:00}E{episode:00}" |
        .dailyEpisodeFormat = "{Series Title} - {Air-Date} - {Episode Title} {Quality Full}" |
        .animeEpisodeFormat = "{Series Title} - S{season:00}E{episode:00}" |
        .seasonFolderFormat = "Season {season}"
    ')
    
    curl -X PUT "http://$IP:$SONARR_PORT/api/v3/config/naming?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d "$new_config"
}

configure_sonarr_media_management() {
    echo "Configuring Sonarr Media Management..."
    # Get current config
    local config=$(curl -s "http://$IP:$SONARR_PORT/api/v3/config/mediamanagement?apiKey=$API_KEY")
    
    # Update config: Unmonitor Deleted Episodes = True
    local new_config=$(echo "$config" | jq '.autoUnmonitorPreviouslyDownloadedEpisodes = true')
    
    curl -X PUT "http://$IP:$SONARR_PORT/api/v3/config/mediamanagement?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d "$new_config"
}

add_trakt_list() {
    local port=$1
    local app_name=$2
    local root_folder=$3
    
    # Source .env to get TRAKT_USERNAME if not already set
    if [ -f "$(dirname "$0")/../.env" ]; then
        source "$(dirname "$0")/../.env"
    fi

    if [ -z "$TRAKT_USERNAME" ]; then
        echo "Skipping Trakt List for $app_name: TRAKT_USERNAME not set in .env"
        return
    fi

    echo "Configuring Trakt Watchlist for $app_name..."
    
    # Check if list exists
    local existing_list=$(curl -s "http://$IP:$port/api/v3/importlist?apiKey=$API_KEY" | jq -r '.[] | select(.name == "Trakt Watchlist")')
    
    local payload=""
    
    if [ "$app_name" == "Sonarr" ]; then
        # Sonarr specific payload
        payload='{
            "name": "Trakt Watchlist",
            "enableAutomaticAdd": true,
            "enabled": false,
            "rootFolderPath": "'"$root_folder"'",
            "qualityProfileId": 1,
            "implementation": "TraktUserImport",
            "configContract": "TraktUserSettings",
            "searchForMissingEpisodes": true,
            "monitor": "firstSeason",
            "monitorNewItems": "all",
            "seriesType": "standard",
            "seasonFolder": true,
            "fields": [
                {"name": "traktListType", "value": 0},
                {"name": "traktWatchedListType", "value": 0},
                {"name": "traktWatchSorting", "value": 1},
                {"name": "username", "value": "'"$TRAKT_USERNAME"'"},
                {"name": "limit", "value": 100}
            ],
            "tags": []
        }'
    else
        # Radarr specific payload
        payload='{
            "name": "Trakt Watchlist",
            "enableAuto": true,
            "enabled": false,
            "rootFolderPath": "'"$root_folder"'",
            "qualityProfileId": 1,
            "searchOnAdd": true,
            "minimumAvailability": "released",
            "implementation": "TraktUserImport",
            "configContract": "TraktUserSettings",
            "fields": [
                {"name": "traktListType", "value": 0},
                {"name": "traktWatchSorting", "value": 1},
                {"name": "username", "value": "'"$TRAKT_USERNAME"'"},
                {"name": "limit", "value": 100}
            ],
            "tags": []
        }'
    fi

    if [ -n "$existing_list" ]; then
        local id=$(echo "$existing_list" | jq -r '.id')
        echo "  - Updating existing list (ID: $id)..."
        # Merge existing ID into payload
        payload=$(echo "$payload" | jq ".id = $id")
        curl -s -X PUT "http://$IP:$port/api/v3/importlist/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    else
        echo "  - Creating new list..."
        curl -s -X POST "http://$IP:$port/api/v3/importlist?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

setup_flaresolverr_prowlarr() {
    echo "Configuring FlareSolverr in Prowlarr..."
    
    # 1. Get or Create Tag
    local tag_label="flaresolverr"
    local tag_id=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/tag?apiKey=$API_KEY" | jq -r ".[] | select(.label == \"$tag_label\") | .id")
    
    if [ -z "$tag_id" ]; then
        echo "  - Creating tag '$tag_label'..."
        tag_id=$(curl -s -X POST "http://$IP:$PROWLARR_PORT/api/v1/tag?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"label\": \"$tag_label\"}" | jq -r '.id')
    fi
    echo "  - Tag ID: $tag_id"

    # 2. Configure Proxy
    local existing=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/indexerProxy?apiKey=$API_KEY" | jq -r '.[] | select(.name == "FlareSolverr")')
    
    if [ -n "$existing" ]; then
        echo "  - FlareSolverr proxy already configured."
    else
        curl -s -X POST "http://$IP:$PROWLARR_PORT/api/v1/indexerProxy?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "FlareSolverr",
                "implementation": "FlareSolverr",
                "configContract": "FlareSolverrSettings",
                "enable": true,
                "tags": ['$tag_id'],
                "fields": [
                    {"name": "host", "value": "http://flaresolverr:8191"},
                    {"name": "requestTimeout", "value": 60}
                ]
            }' > /dev/null
        echo "  - FlareSolverr proxy added."
    fi
    
    # Export TAG_ID for indexers to use
    export FLARESOLVERR_TAG_ID=$tag_id
}

add_prowlarr_indexers() {
    echo "Adding Indexers to Prowlarr..."
    
    # Helper to add Cardigann indexer
    add_cardigann_indexer() {
        local name=$1
        local def_file=$2
        local use_flare=$3
        
        local tags_json="[]"
        if [ "$use_flare" == "true" ] && [ -n "$FLARESOLVERR_TAG_ID" ]; then
            tags_json="[$FLARESOLVERR_TAG_ID]"
        fi

        echo "  - Adding $name..."
        # Check if exists
        local existing=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/indexer?apiKey=$API_KEY" | jq -r '.[] | select(.name == "'"$name"'")')
        if [ -n "$existing" ]; then
             echo "    - Already exists."
             return
        fi

        curl -s -X POST "http://$IP:$PROWLARR_PORT/api/v1/indexer?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'"$name"'",
                "implementation": "Cardigann",
                "configContract": "CardigannSettings",
                "enable": true,
                "protocol": "torrent",
                "priority": 25,
                "appProfileId": 1,
                "tags": '"$tags_json"',
                "fields": [
                    {"name": "definitionFile", "value": "'"$def_file"'"}
                ]
            }' > /dev/null
    }

    add_cardigann_indexer "The Pirate Bay" "thepiratebay" "true"
    add_cardigann_indexer "Nyaa" "nyaasi" "false"
    add_cardigann_indexer "1337x" "1337x" "true"
}

trigger_library_rescan() {
    echo "Triggering library rescan..."
    
    echo "  - Radarr: Refreshing movies..."
    curl -s -X POST "http://$IP:$RADARR_PORT/api/v3/command?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"name": "RefreshMovie"}' > /dev/null

    echo "  - Sonarr: Refreshing series..."
    curl -s -X POST "http://$IP:$SONARR_PORT/api/v3/command?apiKey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"name": "RefreshSeries"}' > /dev/null
}

# Run new configurations
if [[ "$PROFILE" == "extended" || "$PROFILE" == "full" ]]; then
    setup_flaresolverr_prowlarr
    add_prowlarr_indexers
fi

add_root_folder $RADARR_PORT "/data/Videos/Movies"
add_root_folder $SONARR_PORT "/data/Videos/TvSeries"

# Only apply destructive configurations (Naming, Quality, Media Management) once
if [ ! -f ".config_applied" ]; then
    echo "Applying initial configuration (Naming, Quality, Media Management)..."
    configure_radarr_quality
    configure_sonarr_quality
    configure_radarr_naming
    configure_radarr_media_management
    configure_sonarr_naming
    configure_sonarr_media_management
    touch .config_applied
else
    echo "Skipping initial configuration (already applied)."
fi

add_trakt_list $RADARR_PORT "Radarr" "/data/Videos/Movies"
add_trakt_list $SONARR_PORT "Sonarr" "/data/Videos/TvSeries"
trigger_library_rescan

echo "Service linking complete!"
