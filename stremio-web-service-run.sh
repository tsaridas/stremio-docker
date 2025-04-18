#!/bin/sh -e

# Set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"

# Update paths in server-settings.json if it exists
if [ -f "${CONFIG_FOLDER}server-settings.json" ]; then
    echo "Updating paths in server-settings.json to match CONFIG_FOLDER: ${CONFIG_FOLDER}"
    # Use sed to replace any path with the new CONFIG_FOLDER path
    # Remove trailing slash from CONFIG_FOLDER for consistency in the JSON file
    CONFIG_PATH=$(echo "${CONFIG_FOLDER}" | sed 's:/$::')
    sed -i "s|\"appPath\": \"[^\"]*\"|\"appPath\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
    sed -i "s|\"cacheRoot\": \"[^\"]*\"|\"cacheRoot\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
fi

# Function to get public IP address from various services
get_public_ip() {
    # Try multiple services to get public IP in case one fails
    PUBLIC_IP=""
    
    # Try ipify.org first
    if [ -z "${PUBLIC_IP}" ]; then
        echo "DEBUG: Trying ipify.org to get public IP..." >&2
        IP_RESULT=$(curl -s --connect-timeout 5 https://api.ipify.org)
        if [ -n "${IP_RESULT}" ] && [ "${IP_RESULT}" != "curl: "* ]; then
            echo "DEBUG: Successfully obtained public IP from ipify.org: ${IP_RESULT}" >&2
            PUBLIC_IP="${IP_RESULT}"
        else
            echo "DEBUG: Failed to get IP from ipify.org" >&2
        fi
    fi
    
    # If ipify failed, try icanhazip.com
    if [ -z "${PUBLIC_IP}" ]; then
        echo "DEBUG: Trying icanhazip.com to get public IP..." >&2
        IP_RESULT=$(curl -s --connect-timeout 5 https://icanhazip.com)
        if [ -n "${IP_RESULT}" ] && [ "${IP_RESULT}" != "curl: "* ]; then
            echo "DEBUG: Successfully obtained public IP from icanhazip.com: ${IP_RESULT}" >&2
            PUBLIC_IP="${IP_RESULT}"
        else
            echo "DEBUG: Failed to get IP from icanhazip.com" >&2
        fi
    fi
    
    # If icanhazip failed, try ifconfig.me
    if [ -z "${PUBLIC_IP}" ]; then
        echo "DEBUG: Trying ifconfig.me to get public IP..." >&2
        IP_RESULT=$(curl -s --connect-timeout 5 https://ifconfig.me)
        if [ -n "${IP_RESULT}" ] && [ "${IP_RESULT}" != "curl: "* ]; then
            echo "DEBUG: Successfully obtained public IP from ifconfig.me: ${IP_RESULT}" >&2
            PUBLIC_IP="${IP_RESULT}"
        else
            echo "DEBUG: Failed to get IP from ifconfig.me" >&2
        fi
    fi
    
    # Return only the IP address, no debug messages
    echo "${PUBLIC_IP}"
}

# Check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then    
    # Check if SERVER_URL contains 0.0.0.0 and replace with public IP
    if echo "${SERVER_URL}" | grep -q "0\.0\.0\.0"; then
        echo "SERVER_URL contains 0.0.0.0, attempting to replace with public IP..."
        PUBLIC_IP=$(get_public_ip)
        
        if [ -n "${PUBLIC_IP}" ]; then
            echo "Replacing 0.0.0.0 with public IP ${PUBLIC_IP} in SERVER_URL"
            # Replace 0.0.0.0 with the public IP while preserving protocol and port
            SERVER_URL=$(echo "${SERVER_URL}" | sed "s/0\.0\.0\.0/${PUBLIC_IP}/g")
            echo "New Target URL: ${SERVER_URL}"
        else
            echo "Failed to obtain public IP. Keeping original SERVER_URL: ${SERVER_URL}"
        fi
    fi
    
    SERVER_URL=$(echo "${SERVER_URL}" | sed 's:/*$:/:' )
    echo "Target URL: ${SERVER_URL}"
    cp localStorage.json build/localStorage.json
    sed -i "s|http://127.0.0.1:11470/|${SERVER_URL}|g" build/localStorage.json
fi

start_http_server() {
    http-server build/ -p 8080 -d false "$@"
}

# If WEBUI_LOCATION is set, modify server.js to use it as the redirect target
if [ -n "${WEBUI_LOCATION}" ]; then
    # Ensure WEBUI_LOCATION ends with a trailing slash for consistency
    WEBUI_LOCATION=$(echo "${WEBUI_LOCATION}" | sed 's:/*$:/:')
    
    echo "Configuring server redirect to custom Web UI location: ${WEBUI_LOCATION}"
    
    # Escape forward slashes in the URL for sed
    ESCAPED_URL=$(echo "${WEBUI_LOCATION}" | sed 's/\//\\\//g')
    
    # Replace all variations of the default redirect URL patterns in server.js
    # Look for exact matches with and without trailing slashes, and with version numbers
    REPLACEMENTS_MADE=0
    
    # Pattern 1: https://app.strem.io/shell-v4.4/
    sed -i "s/https:\/\/app\.strem\.io\/shell-v4\.4\//${ESCAPED_URL}/g" server.js
    REPLACEMENTS_MADE=$((REPLACEMENTS_MADE + $(grep -c "${ESCAPED_URL}" server.js || echo 0)))
    
    # Pattern 2: https://app.strem.io/shell-v4.4 (no trailing slash)
    sed -i "s/https:\/\/app\.strem\.io\/shell-v4\.4([^\/])/${ESCAPED_URL}\1/g" server.js
    
    # Pattern 3: https://app.strem.io/shell-v (with any version number)
    sed -i "s/https:\/\/app\.strem\.io\/shell-v[0-9]\+\.[0-9]\+\//${ESCAPED_URL}/g" server.js
    
    # Pattern 4: Generic app.strem.io with shell-v pattern
    sed -i "s/app\.strem\.io\/shell-v[0-9.]\+/$(echo ${WEBUI_LOCATION} | sed 's/^https\?:\/\///' | sed 's/\//\\\//g')/g" server.js
    
    if [ $REPLACEMENTS_MADE -gt 0 ]; then
        echo "server.js successfully updated with custom redirect. Made $REPLACEMENTS_MADE replacements."
    else
        echo "WARNING: No replacements found in server.js. The default URL pattern may be different than expected."
        echo "Searching for app.strem.io in server.js to help with debugging:"
        grep -n "app.strem.io" server.js || echo "No instances of app.strem.io found in server.js"
    fi
    
    # Also check and update the streamingServer parameter if found
    if grep -q "streamingServer=" server.js; then
        echo "Found streamingServer parameter in server.js, updating..."
        # Replace the URL in streamingServer parameter
        sed -i "s/\(streamingServer=\)[^&]*&/\1${ESCAPED_URL}&/g" server.js
    fi
fi

# Echo startup message
echo "Starting Stremio server at $(date)"
echo "Config folder: ${CONFIG_FOLDER}"
echo "IP Address: ${IPADDRESS}"
echo "Server URL: ${SERVER_URL}"

if [ -n "${IPADDRESS}" ]; then
    node server.js &

    # Check if IPADDRESS is set to a value that means "any address" (0.0.0.0, *, any, etc.)
    if [ "${IPADDRESS}" = "0.0.0.0" ] || [ "${IPADDRESS}" = "*" ] || [ "${IPADDRESS}" = "any" ]; then
        echo "IPADDRESS is set to ${IPADDRESS}, which indicates 'any address'. Attempting to get public IP..."
        PUBLIC_IP=$(get_public_ip)
        
        # If we successfully obtained a public IP, use it instead of the original IPADDRESS
        if [ -n "${PUBLIC_IP}" ]; then
            echo "Using discovered public IP address: ${PUBLIC_IP}"
            IPADDRESS="${PUBLIC_IP}"
        else
            echo "Failed to obtain public IP address. Falling back to original value: ${IPADDRESS}"
        fi
    fi
    
    # Log the URL we're about to call with curl for debugging
    CERT_URL="http://localhost:11470/get-https?authKey=&ipAddress=${IPADDRESS}"
    echo "Attempting to fetch HTTPS certificate using URL: ${CERT_URL}"
    
    # Use set -x to show the exact curl command being executed
    set -x
    curl --connect-timeout 5 \
         --retry-all-errors \
         --retry 10 \
         --retry-delay 1 \
         --verbose \
         "${CERT_URL}"
    CURL_STATUS="$?"
    set +x
    
    if [ "${CURL_STATUS}" -ne 0 ]; then
        echo "Failed to fetch HTTPS certificate. Curl exited with status: ${CURL_STATUS}"
    else
        echo "Successfully fetched HTTPS certificate."
    fi

    IMPORTED_DOMAIN="$(node certificate.js --action extract --json-path "${CONFIG_FOLDER}httpsCert.json")"
    EXTRACT_STATUS="$?"
    IMPORTED_CERT_FILE="${CONFIG_FOLDER}${IMPORTED_DOMAIN}.pem"
    echo "Extracted domain ${IMPORTED_DOMAIN} with status ${EXTRACT_STATUS} and cert file ${IMPORTED_CERT_FILE}"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -n "${IMPORTED_DOMAIN}" ] && [ -f "${IMPORTED_CERT_FILE}" ]; then
        echo "${IPADDRESS} ${IMPORTED_DOMAIN}" >> /etc/hosts
        
        start_http_server -S -C "${IMPORTED_CERT_FILE}" -K "${IMPORTED_CERT_FILE}"
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
        start_http_server
    fi
elif [ -n "${CERT_FILE}" ] && [ -n "${DOMAIN}" ]; then
    node certificate.js --action load --pem-path "${CONFIG_FOLDER}${CERT_FILE}" --domain "${DOMAIN}" --json-path "${CONFIG_FOLDER}httpsCert.json"
    if [ "$?" -eq 0 ]; then
        node server.js &
        start_http_server -S -C "${CONFIG_FOLDER}${CERT_FILE}" -K "${CONFIG_FOLDER}${CERT_FILE}"
    else
        echo "Failed to load certificate. Falling back to HTTP."
        node server.js &
        start_http_server
    fi
else
    echo "Starting Web UI with HTTP..."
    node server.js &
    start_http_server
fi

#wait ${SERVER_PID}
