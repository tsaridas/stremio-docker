#!/bin/sh -e

# Set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-/srv/.stremio-server/}"

# Update paths in server-settings.json if it exists
if [ -f "${CONFIG_FOLDER}server-settings.json" ]; then
    echo "Updating paths in server-settings.json to match CONFIG_FOLDER: ${CONFIG_FOLDER}"
    # Use sed to replace any path with the new CONFIG_FOLDER path
    # Remove trailing slash from CONFIG_FOLDER for consistency in the JSON file
    CONFIG_PATH=$(echo "${CONFIG_FOLDER}" | sed 's:/$::')
    sed -i "s|\"appPath\": \"[^\"]*\"|\"appPath\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
    sed -i "s|\"cacheRoot\": \"[^\"]*\"|\"cacheRoot\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
fi

# Check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

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

if [ -n "${SERVER_URL}" ]; then
    TARGET_URL="${SERVER_URL}"
    if [ -z "${TARGET_URL}" ]; then
      TARGET_URL="http://127.0.0.1:11470/"
    fi
    TARGET_URL=$(echo "${TARGET_URL}" | sed 's:/*$:/:' )
    echo "Target URL: ${TARGET_URL}"
    sed -i "s|http://127.0.0.1:11470/|${TARGET_URL}|g" localStorage.json
    cp localStorage.json build/localStorage.json
fi

start_http_server() {
    http-server build/ -p 8080 -d false "$@"
}

# Echo startup message
echo "Starting Stremio server at $(date)"
echo "Config folder: ${CONFIG_FOLDER}"
echo "IP Address: ${IPADDRESS}"
echo "Server URL: ${SERVER_URL}"

node server.js &
SERVER_PID=$!
echo "Stremio server started with PID ${SERVER_PID}"

sleep 2

if [ -n "${IPADDRESS}" ]; then
    echo "Attempting to fetch HTTPS certificate for IP address: ${IPADDRESS}"
    curl --connect-timeout 5 \
        --retry 10 \
        --retry-delay 1 \
        --verbose \
        "http://localhost:${SERVER_PORT}/get-https?authKey=&ipAddress=${IPADDRESS}"
    CURL_STATUS="$?"
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
        echo "${IPADDRESS} ${IMPORTED_DOMAIN}" >>/etc/hosts
        echo "Starting Web UI with HTTPS using fetched certificate..."
        start_http_server -S -C "${IMPORTED_CERT_FILE}" -K "${IMPORTED_CERT_FILE}"
    else
        echo "Failed to setup HTTPS using fetched certificate. Falling back to HTTP."
        start_http_server
    fi
elif [ -n "${CERT_FILE}" ] && [ -n "${DOMAIN}" ]; then
    node certificate.js --action load --pem-path "${CONFIG_FOLDER}${CERT_FILE}" --domain "${DOMAIN}" --json-path "${CONFIG_FOLDER}httpsCert.json"
    LOAD_STATUS="$?"
    if [ "${LOAD_STATUS}" -eq 0 ]; then
        echo "Starting Web UI with HTTPS using provided certificate ${CERT_FILE} for domain ${DOMAIN}..."
        start_http_server -S -C "${CONFIG_FOLDER}${CERT_FILE}" -K "${CONFIG_FOLDER}${CERT_FILE}"
    else
        echo "Failed to load custom certificate ${CERT_FILE}. Falling back to HTTP."
        start_http_server
    fi
else
    echo "Starting Web UI with HTTP..."
    start_http_server
fi

wait ${SERVER_PID}
