#!/bin/sh

TADO_USERNAME='YOUR_TADO_USERNAME_GOES_HERE'
TADO_PASSWORD='YOUR_TADO_PASSWORD_GOES_HERE'
CHECKING_INTERVAL='60'
CHECK_IF_PHONES_ARE_HOME='true'
ENABLE_LOG='false'
LOG_FILE='tado-assistant.log'

# Create log directory if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

TOKEN=""
OPEN_WINDOW_ACTIVATION_TIME=""

LAST_MESSAGE="" # Used to prevent duplicate messages

set_token() {
    TOKEN=$1
}

set_open_window_actiovation_time() {
    OPEN_WINDOW_ACTIVATION_TIME=$1
}

set_home_id() {
    HOME_ID=$1
}

check_mac() {
    search_mac=$1
    for mac in $all_macs; do
        if [ "$mac" = "$search_mac" ]; then
            return 1
        fi
    done
    return 0
}

reset_log_if_needed() {
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi

    local max_age_days=10 # Max age in days (e.g., 10 days)
    local current_time
    local last_modified
    local age_days
    local timestamp
    local backup_log

    current_time=$(date +%s)
    last_modified=$(date -r "$LOG_FILE" +%s)
    age_days=$(((current_time - last_modified) / 86400))

    if [ "$age_days" -ge "$max_age_days" ]; then
        timestamp=$(date '+%Y%m%d%H%M%S')
        backup_log="${LOG_FILE}.${timestamp}"
        mv "$LOG_FILE" "$backup_log"
        touch "$LOG_FILE"
        echo "🔄 Log reset: $backup_log"
    fi
}

# Error handling for curl
handle_curl_error() {
    if [ $? -ne 0 ]; then
        log_message "Curl command failed. Retrying in 60 seconds."
        sleep 60
        return 1
    fi
    return 0
}

# Login function
login() {
    echo "Logging in..."
    response=$(curl -s -X POST "https://auth.tado.com/oauth/token" \
        -d 'client_id=public-api-preview' \
        -d 'client_secret=4HJGRffVR8xb3XdEUQpjgZ1VplJi6Xgw' \
        -d 'grant_type=password' \
        -d 'scope=home.user' \
        --data-urlencode 'username='"$TADO_USERNAME" \
        --data-urlencode 'password='"$TADO_PASSWORD")
    handle_curl_error

    token=$(echo "$response" | jq -r '.access_token')
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        log_message "❌ Login error for account $account_index: Please check the username and password. Then restart the container or service."
        exit 1
    fi

    set_token "$token"
    expires_in=$(echo "$response" | jq -r '.expires_in')
    EXPIRY_TIME=$(($(date +%s) + expires_in - 60))

    home_data=$(curl -s -X GET "https://my.tado.com/api/v2/me" -H "Authorization: Bearer ${TOKEN}")
    handle_curl_error

    home_id=$(echo "$home_data" | jq -r '.homes[0].id')
    if [ -z "$home_id" ]; then
        log_message "⚠️ Error fetching home ID for account $account_index!"
        exit 1
    fi

    set_home_id "$home_id"
}

log_message() {
    local message="$1"
    reset_log_if_needed
    if [ "$ENABLE_LOG" = true ] && [ "$LAST_MESSAGE" != "$message" ]; then
        echo "$(date '+%d-%m-%Y %H:%M:%S') # $message" >>"$LOG_FILE"
        LAST_MESSAGE="$message"
    fi
    echo "$(date '+%d-%m-%Y %H:%M:%S') # $message"
}

homeState() {
    home_id=${HOME_ID}
    current_time=$(date +%s)

    if [ -n "${EXPIRY_TIME}" ] && [ "$current_time" -ge "${EXPIRY_TIME}" ]; then
        login
    fi

    home_state=$(curl -s -X GET "https://my.tado.com/api/v2/homes/$home_id/state" -H "Authorization: Bearer ${TOKEN}" | jq -r '.presence')
    handle_curl_error

    # Get connected clients using iwinfo
    connected_macs2=$(iwinfo phy0-ap0 assoclist | awk '/[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]/ {print $1}')
    connected_macs5=$(iwinfo phy1-ap0 assoclist | awk '/[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]/ {print $1}')
    all_macs=$(printf '%s\n%s\n' "$connected_macs2" "$connected_macs5")

    phone1="PHONE_MAC_ADDRESS_GOES_HERE"
    phone2="PHONE_MAC_ADDRESS_GOES_HERE"

    both_macs=0

    check_mac "$phone1"
    if [ $? -eq 1 ]; then
        echo "Phone1 is home"
        both_macs=$((both_macs + 1))
    fi

    check_mac "$phone2"
    if [ $? -eq 1 ]; then
        echo "Phone2 is home"
        both_macs=$((both_macs + 1))
    fi

    # Now both_macs will contain:
    # 0 = none found
    # 1 = one found
    # 2 = both found
    # echo "$both_macs"

    if [ "$CHECK_IF_PHONES_ARE_HOME" = true ]; then
        log_message "🏠 Checking if phones are home"

        if [ ${both_macs} -gt 0 ] && [ "$home_state" = "HOME" ]; then
            log_message "🏠 Home is in HOME Mode, and both devices are at home."
        elif [ ${both_macs} -eq 0 ] && [ "$home_state" = "AWAY" ]; then
            log_message "🚶 Home is in AWAY Mode and there are no devices at home."
        elif [ ${both_macs} -eq 0 ] && [ "$home_state" = "HOME" ]; then
            log_message "🏠 Home is in HOME Mode but there are no devices at home."
            curl -s -X PUT "https://my.tado.com/api/v2/homes/$home_id/presenceLock" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d '{"homePresence": "AWAY"}'
            handle_curl_error
            log_message "Done! Activated AWAY mode for account $account_index."
        elif [ ${both_macs} -gt 0 ] && [ "$home_state" = "AWAY" ]; then
            log_message "🚶 Home is in AWAY Mode but at least one device is home."
            curl -s -X PUT "https://my.tado.com/api/v2/homes/$home_id/presenceLock" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d '{"homePresence": "HOME"}'
            handle_curl_error
            log_message "Done! Activated HOME mode"
        fi
    else
        log_message "🏠 Account $account_index: Geofencing disabled."
    fi

    # Get rooms    
    rooms=$(curl -s -X GET "https://hops.tado.com/homes/$home_id/rooms" -H "Authorization: Bearer ${TOKEN}")
    handle_curl_error

    # OWD settings
    settings=$(curl -s -X GET "https://hops.tado.com/homes/$home_id/settings/owd" -H "Authorization: Bearer ${TOKEN}")
    handle_curl_error

    echo "$rooms" | jq -c '.[]' | while read -r room; do
        room_id=$(echo "$room" | jq -r '.id')
        room_name=$(echo "$room" | jq -r '.name')


        open_window_detection_enabled=$(echo "$settings" | jq '.rooms[] | select(.roomId == 1) | .enabled')
        if [ "$open_window_detection_enabled" = false ]; then
            continue
        fi

        open_window_detected=$(curl -s -X GET "https://hops.tado.com/homes/$home_id/rooms/$room_id" -H "Authorization: Bearer ${TOKEN}" | jq -r '.openWindow.activated')
        handle_curl_error

        if [ "$open_window_detected" = false ]; then
            current_time=$(date +%s) 

            log_message "❄️ $room_name: Open window detected, turning off heating."
            # Set open window mode for the zone
            curl -s -X POST "https://hops.tado.com/homes/$home_id/rooms/$room_id/openWindow" \
                -d '{}' \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json"
            handle_curl_error
            log_message "🌬️ Activating open window mode for $room_name."

            # Record the activation time
            set_open_window_actiovation_time "$current_time"
        fi
    done

    log_message "⏳ Waiting for a change in devices location or for an open window.."
}

# Main execution loop
login
while true; do
    homeState
    sleep "$CHECKING_INTERVAL"
done