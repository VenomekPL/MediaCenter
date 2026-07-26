#!/bin/bash

# Profile argument (default to full to attempt everything if not specified)
PROFILE=${1:-full}

# Load .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

API_KEY="${API_KEY:-mediacenter1234567890abcdef}"
IP="localhost"

# Credentials from .env or defaults
TRANSMISSION_USER=${TRANSMISSION_USER:-admin}
TRANSMISSION_PASS=${TRANSMISSION_PASS:-password}

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
            {"name": "host", "value": "gluetun"},
            {"name": "port", "value": 9091},
            {"name": "username", "value": "'"$TRANSMISSION_USER"'"},
            {"name": "password", "value": "'"$TRANSMISSION_PASS"'"},
            {"name": "'"$category_field"'", "value": "'"${name,,}"'"}
        ]
    }'

    local response status
    if [ -n "$existing_client" ]; then
        local id=$(echo "$existing_client" | jq -r '.id')
        echo "  - Updating existing client (ID: $id)..."
        # Merge existing ID into payload
        payload=$(echo "$payload" | jq ".id = $id")
        response=$(curl -s -w "\n%{http_code}" -X PUT "http://$IP:$port/api/$api_version/downloadclient/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        echo "  - Creating new client..."
        response=$(curl -s -w "\n%{http_code}" -X POST "http://$IP:$port/api/$api_version/downloadclient?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    status=$(echo "$response" | tail -1)
    if [[ "$status" =~ ^2 ]]; then
        echo "  - Transmission configured for $name successfully."
    else
        echo "  - ERROR: Failed to configure Transmission for $name (HTTP $status)"
    fi
}

add_transmission_to_prowlarr() {
    local port=$PROWLARR_PORT
    
    echo "Configuring Transmission for Prowlarr..."
    
    # Check if client exists
    local existing_client=$(curl -s "http://$IP:$port/api/v1/downloadclient?apiKey=$API_KEY" | jq -r '.[] | select(.name == "Transmission")')
    
    local payload='{
        "name": "Transmission",
        "implementation": "Transmission",
        "configContract": "TransmissionSettings",
        "enable": true,
        "protocol": "torrent",
        "priority": 1,
        "tags": [],
        "categories": [],
        "fields": [
            {"name": "host", "value": "gluetun"},
            {"name": "port", "value": 9091},
            {"name": "username", "value": "'"$TRANSMISSION_USER"'"},
            {"name": "password", "value": "'"$TRANSMISSION_PASS"'"},
            {"name": "category", "value": "prowlarr"}
        ]
    }'

    local response status
    if [ -n "$existing_client" ]; then
        local id=$(echo "$existing_client" | jq -r '.id')
        echo "  - Updating existing client (ID: $id)..."
        # Merge existing ID into payload
        payload=$(echo "$payload" | jq ".id = $id")
        response=$(curl -s -w "\n%{http_code}" -X PUT "http://$IP:$port/api/v1/downloadclient/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        echo "  - Creating new client..."
        response=$(curl -s -w "\n%{http_code}" -X POST "http://$IP:$port/api/v1/downloadclient?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    status=$(echo "$response" | tail -1)
    if [[ "$status" =~ ^2 ]]; then
        echo "  - Transmission configured for Prowlarr successfully."
    else
        echo "  - ERROR: Failed to configure Transmission for Prowlarr (HTTP $status)"
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
if [[ "$PROFILE" == "extended" || "$PROFILE" == "full" ]]; then
    add_transmission_to_prowlarr
fi 

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
    local api_version=${3:-v3}
    echo "Adding Root Folder '$path' to service on port $port..."
    curl -s -X POST "http://$IP:$port/api/$api_version/rootfolder?apiKey=$API_KEY" \
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
        local priority=${4:-25}
        
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
                "priority": '"$priority"',
                "appProfileId": 1,
                "tags": '"$tags_json"',
                "fields": [
                    {"name": "definitionFile", "value": "'"$def_file"'"}
                ]
            }' > /dev/null
    }

    add_cardigann_indexer "The Pirate Bay" "thepiratebay" "true" 25
    add_cardigann_indexer "Nyaa" "nyaasi" "false" 20
    add_cardigann_indexer "1337x" "1337x" "true" 25
    add_cardigann_indexer "TorrentGalaxy" "torrentgalaxy" "true" 25
    add_cardigann_indexer "YTS" "yts" "true" 15
}

upsert_release_profile_ignore() {
    local port=$1
    local app_name=$2
    local profile_name=$3
    local ignored_term=$4

    echo "Configuring $app_name release profile '$profile_name' (ignore: $ignored_term)..."
    local existing
    existing=$(curl -s "http://$IP:$port/api/v3/releaseprofile?apiKey=$API_KEY" | jq -c --arg n "$profile_name" '.[] | select(.name == $n)')

    local payload
    payload=$(jq -n \
        --arg name "$profile_name" \
        --arg ignored "$ignored_term" \
        '{name:$name, enabled:true, required:[], ignored:[$ignored], indexerId:0, tags:[]}')

    local response status
    if [ -n "$existing" ]; then
        local id
        id=$(echo "$existing" | jq -r '.id')
        payload=$(echo "$payload" | jq --argjson id "$id" '.id = $id')
        response=$(curl -s -w "\n%{http_code}" -X PUT "http://$IP:$port/api/v3/releaseprofile/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        response=$(curl -s -w "\n%{http_code}" -X POST "http://$IP:$port/api/v3/releaseprofile?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    status=$(echo "$response" | tail -1)
    if [[ "$status" =~ ^2 ]]; then
        echo "  - $app_name release profile configured."
    else
        echo "  - ERROR: Failed to configure $app_name release profile (HTTP $status)"
    fi
}

configure_release_hygiene() {
    upsert_release_profile_ignore "$RADARR_PORT" "Radarr" "Block CYBER bait" "CYBER"
    upsert_release_profile_ignore "$SONARR_PORT" "Sonarr" "Block CYBER bait" "CYBER"
}

upsert_language_custom_format() {
    local port=$1
    local app_name=$2
    local cf_name=$3
    local negate=$4

    echo "  - Upserting $app_name custom format '$cf_name'..."
    local existing
    existing=$(curl -s "http://$IP:$port/api/v3/customformat?apiKey=$API_KEY" | jq -c --arg n "$cf_name" '.[] | select(.name == $n)')

    local payload
    payload=$(jq -n \
        --arg name "$cf_name" \
        --argjson negate "$negate" \
        '{
            name: $name,
            includeCustomFormatWhenRenaming: false,
            specifications: [
                {
                    name: $name,
                    implementation: "LanguageSpecification",
                    negate: $negate,
                    required: true,
                    fields: [
                        {name: "value", value: -2},
                        {name: "exceptLanguage", value: false}
                    ]
                }
            ]
        }')

    local response status
    if [ -n "$existing" ]; then
        local id
        id=$(echo "$existing" | jq -r '.id')
        payload=$(echo "$payload" | jq --argjson id "$id" '.id = $id')
        response=$(curl -s -w "\n%{http_code}" -X PUT "http://$IP:$port/api/v3/customformat/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        response=$(curl -s -w "\n%{http_code}" -X POST "http://$IP:$port/api/v3/customformat?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    status=$(echo "$response" | tail -1)
    if [[ "$status" =~ ^2 ]]; then
        echo "    - OK"
    else
        echo "    - ERROR: HTTP $status"
    fi
}

apply_language_format_scores() {
    local port=$1
    local app_name=$2
    local original_score=$3
    local not_original_score=$4

    echo "  - Applying language format scores on $app_name quality profiles..."
    local formats profiles
    formats=$(curl -s "http://$IP:$port/api/v3/customformat?apiKey=$API_KEY")
    local orig_id not_id
    orig_id=$(echo "$formats" | jq -r '.[] | select(.name == "Language Original") | .id')
    not_id=$(echo "$formats" | jq -r '.[] | select(.name == "Language Not Original") | .id')
    if [ -z "$orig_id" ] || [ -z "$not_id" ] || [ "$orig_id" = "null" ] || [ "$not_id" = "null" ]; then
        echo "    - ERROR: Language custom formats missing; skip scoring."
        return
    fi

    profiles=$(curl -s "http://$IP:$port/api/v3/qualityprofile?apiKey=$API_KEY")
    local id
    for id in $(echo "$profiles" | jq -r '.[].id'); do
        local profile updated status
        profile=$(echo "$profiles" | jq -c --argjson id "$id" '.[] | select(.id == $id)')
        updated=$(echo "$profile" | jq \
            --argjson orig "$orig_id" \
            --argjson notid "$not_id" \
            --argjson oscore "$original_score" \
            --argjson nscore "$not_original_score" '
            .formatItems = (
                ((.formatItems // [])
                  | map(
                      if .format == $orig or .name == "Language Original" then .score = $oscore
                      elif .format == $notid or .name == "Language Not Original" then .score = $nscore
                      else .
                      end
                    )
                ) as $items
                | $items
                  + (if ($items | map(.format) | index($orig)) then [] else [{format:$orig, name:"Language Original", score:$oscore}] end)
                  + (if ($items | map(.format) | index($notid)) then [] else [{format:$notid, name:"Language Not Original", score:$nscore}] end)
            )
        ')
        status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://$IP:$port/api/v3/qualityprofile/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$updated")
        if [[ ! "$status" =~ ^2 ]]; then
            echo "    - ERROR: quality profile id=$id HTTP $status"
        fi
    done
    echo "    - Scores set (Original=$original_score, Not Original=$not_original_score)."
}

configure_original_language_preference() {
    # Sonarr v4 language profiles are deprecated stubs (API returns 202 but does not persist).
    # Prefer Original audio via custom formats on quality profiles instead.
    echo "Configuring Original-language preference (custom formats)..."
    upsert_language_custom_format "$RADARR_PORT" "Radarr" "Language Original" false
    upsert_language_custom_format "$RADARR_PORT" "Radarr" "Language Not Original" true
    apply_language_format_scores "$RADARR_PORT" "Radarr" 100 -10000

    upsert_language_custom_format "$SONARR_PORT" "Sonarr" "Language Original" false
    upsert_language_custom_format "$SONARR_PORT" "Sonarr" "Language Not Original" true
    apply_language_format_scores "$SONARR_PORT" "Sonarr" 100 -10000
}

retag_japanese_series_as_anime() {
    echo "Retagging Japanese-original series as anime..."
    local series
    series=$(curl -s "http://$IP:$SONARR_PORT/api/v3/series?apiKey=$API_KEY")
    local ids
    ids=$(echo "$series" | jq -r '
        .[]
        | select((.originalLanguage.name // "") == "Japanese")
        | select((.seriesType // "standard") == "standard")
        | .id
    ')

    if [ -z "$ids" ]; then
        echo "  - No Japanese standard series to retag."
        return
    fi

    local id count=0
    for id in $ids; do
        local body
        body=$(echo "$series" | jq -c --argjson id "$id" '.[] | select(.id == $id) | .seriesType = "anime"')
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://$IP:$SONARR_PORT/api/v3/series/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$body")
        if [[ "$status" =~ ^2 ]]; then
            count=$((count + 1))
        else
            echo "  - ERROR: Failed to retag series id=$id (HTTP $status)"
        fi
    done
    echo "  - Retagged $count series to anime."
}

configure_prowlarr_indexer_hygiene() {
    echo "Configuring Prowlarr indexer hygiene (Nyaa trusted, priorities)..."
    local indexers
    indexers=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/indexer?apiKey=$API_KEY")

    set_indexer_priority() {
        local name=$1
        local priority=$2
        local existing
        existing=$(echo "$indexers" | jq -c --arg n "$name" '.[] | select(.name == $n)')
        if [ -z "$existing" ]; then
            echo "  - Skipping priority for $name (not found)."
            return
        fi
        local current
        current=$(echo "$existing" | jq -r '.priority')
        if [ "$current" = "$priority" ]; then
            echo "  - $name priority already $priority."
            return
        fi
        local id payload status
        id=$(echo "$existing" | jq -r '.id')
        payload=$(echo "$existing" | jq --argjson p "$priority" '.priority = $p')
        status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://$IP:$PROWLARR_PORT/api/v1/indexer/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
        if [[ "$status" =~ ^2 ]]; then
            echo "  - $name priority set to $priority."
            indexers=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/indexer?apiKey=$API_KEY")
        else
            echo "  - ERROR: Failed to set $name priority (HTTP $status)"
        fi
    }

    configure_nyaa_trusted() {
        local existing
        existing=$(echo "$indexers" | jq -c '.[] | select(.name == "Nyaa")')
        if [ -z "$existing" ]; then
            echo "  - Skipping Nyaa trusted filter (indexer not found)."
            return
        fi

        local id payload status
        id=$(echo "$existing" | jq -r '.id')
        payload=$(echo "$existing" | jq '
            .priority = 20
            | (.fields) |= map(
                if .name == "filter-id" then .value = 2
                elif .name == "sonarr_compatibility" then .value = true
                else .
                end
              )
        ')
        status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://$IP:$PROWLARR_PORT/api/v1/indexer/$id?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
        if [[ "$status" =~ ^2 ]]; then
            echo "  - Nyaa set to Trusted only + Sonarr compatibility."
            indexers=$(curl -s "http://$IP:$PROWLARR_PORT/api/v1/indexer?apiKey=$API_KEY")
        else
            echo "  - ERROR: Failed to update Nyaa (HTTP $status)"
        fi
    }

    configure_nyaa_trusted
    set_indexer_priority "YTS" 15
    set_indexer_priority "Nyaa" 20
    set_indexer_priority "1337x" 25
    set_indexer_priority "The Pirate Bay" 25
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
    configure_prowlarr_indexer_hygiene
fi

add_root_folder $RADARR_PORT "/data/Videos/Movies"
add_root_folder $SONARR_PORT "/data/Videos/TvSeries"
if [[ "$PROFILE" == "extended" || "$PROFILE" == "full" ]]; then
    add_root_folder $LIDARR_PORT "/data/Music" "v1"
fi

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

# Idempotent release/language hygiene (safe to re-run)
configure_release_hygiene
configure_original_language_preference
retag_japanese_series_as_anime

add_trakt_list $RADARR_PORT "Radarr" "/data/Videos/Movies"
add_trakt_list $SONARR_PORT "Sonarr" "/data/Videos/TvSeries"
trigger_library_rescan

echo "Service linking complete!"
