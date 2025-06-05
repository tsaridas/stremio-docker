#!/bin/sh -e

#############################################
# STREMIO WEB SERVICE RUN SCRIPT
#############################################
# This script manages the Stremio web service, handling configuration setup,
# server patching, IP resolution, and certificate management for both HTTP and HTTPS.
# It supports automatic public IP detection, domain resolution, and HTTPS certificate generation.
#
# Environment variables:
# - APP_PATH:      Optional. Sets custom configuration folder path. Default: $HOME/.stremio-server/
# - SERVER_URL:    Optional. Custom server URL. Supports IP address, domain name, or 0.0.0.0
# - IPADDRESS:     Optional. IP address for HTTPS certificate generation
# - UPDATE_HOSTS:  Optional. Set to "true" to update /etc/hosts with certificate domain
# - CERT_FILE:     Optional. Custom certificate file name (used with DOMAIN)
# - DOMAIN:        Optional. Custom domain name for certificate (used with CERT_FILE)

#############################################
# INITIAL SERVER CONFIGURATION
#############################################

# Set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"

# Update paths in server-settings.json if it exists
if [ -f "${CONFIG_FOLDER}server-settings.json" ]; then
    echo "[CONFIG] Found server-settings.json at ${CONFIG_FOLDER}server-settings.json"
    # Remove trailing slash from CONFIG_FOLDER for consistency in the JSON file
    CONFIG_PATH=$(echo "${CONFIG_FOLDER}" | sed 's:/$::')

    # Get current values for logging
    CURRENT_APP_PATH=$(grep -o '"appPath": "[^"]*"' "${CONFIG_FOLDER}server-settings.json" | cut -d'"' -f4)
    CURRENT_CACHE_ROOT=$(grep -o '"cacheRoot": "[^"]*"' "${CONFIG_FOLDER}server-settings.json" | cut -d'"' -f4)

    echo "[CONFIG] Updating paths in server-settings.json:"
    echo "  - appPath: '${CURRENT_APP_PATH}' -> '${CONFIG_PATH}'"
    echo "  - cacheRoot: '${CURRENT_CACHE_ROOT}' -> '${CONFIG_PATH}'"

    sed -i "s|\"appPath\": \"[^\"]*\"|\"appPath\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
    sed -i "s|\"cacheRoot\": \"[^\"]*\"|\"cacheRoot\": \"${CONFIG_PATH}\"|g" "${CONFIG_FOLDER}server-settings.json"
fi

#############################################
# HELPER FUNCTIONS
#############################################

# Function to start HTTP server with specified options
start_http_server() {
    echo "[SERVER] Starting HTTP server on port 8080 with options: $*"
    http-server build/ -p 8080 -d false "$@"
}

# Function to get public IP address from various services
get_public_ip() {
    # Try multiple services to get public IP in case one fails
    PUBLIC_IP=""

    # Try ifconfig.me first
    if [ -z "${PUBLIC_IP}" ]; then
        echo "[IP LOOKUP] Attempting to get public IP from ifconfig.me..." >&2
        IP_RESULT=$(curl -s --connect-timeout 5 https://ifconfig.me)
        if [ -n "${IP_RESULT}" ] && [ "${IP_RESULT}" != "curl: "* ]; then
            echo "[IP LOOKUP] Successfully obtained IP from ifconfig.me: ${IP_RESULT}" >&2
            PUBLIC_IP="${IP_RESULT}"
        else
            echo "[IP LOOKUP] Failed to get IP from ifconfig.me" >&2
        fi
    fi

    # If ifconfig.me failed, try icanhazip
    if [ -z "${PUBLIC_IP}" ]; then
        echo "[IP LOOKUP] Attempting to get public IP from icanhazip.com..." >&2
        IP_RESULT=$(curl -s --connect-timeout 5 https://icanhazip.com)
        if [ -n "${IP_RESULT}" ] && [ "${IP_RESULT}" != "curl: "* ]; then
            echo "[IP LOOKUP] Successfully obtained IP from icanhazip.com: ${IP_RESULT}" >&2
            PUBLIC_IP="${IP_RESULT}"
        else
            echo "[IP LOOKUP] Failed to get IP from icanhazip.com" >&2
        fi
    fi

    # Return only the IP address, no debug messages
    echo "${PUBLIC_IP}"
}

# Function to resolve a domain/hostname to an IP address
resolve_domain_to_ip() {
    DOMAIN="$1"
    
    # Check if input is already an IP address (simple check)
    if echo "${DOMAIN}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "${DOMAIN}"
        return
    fi
    
    echo "[DNS LOOKUP] Attempting to resolve domain: ${DOMAIN}" >&2
    
    # Try to resolve using host command
    if command -v host >/dev/null 2>&1; then
        RESOLVED_IP=$(host -t A "${DOMAIN}" | grep "has address" | head -n 1 | awk '{print $NF}')
        if [ -n "${RESOLVED_IP}" ]; then
            echo "[DNS LOOKUP] Resolved ${DOMAIN} to IP: ${RESOLVED_IP} using 'host' command" >&2
            echo "${RESOLVED_IP}"
            return
        fi
    fi
    
    # Try to resolve using nslookup as fallback
    if command -v nslookup >/dev/null 2>&1; then
        RESOLVED_IP=$(nslookup "${DOMAIN}" | grep -A1 "Name:" | grep "Address:" | head -n 1 | awk '{print $NF}')
        if [ -n "${RESOLVED_IP}" ]; then
            echo "[DNS LOOKUP] Resolved ${DOMAIN} to IP: ${RESOLVED_IP} using 'nslookup' command" >&2
            echo "${RESOLVED_IP}"
            return
        fi
    fi
    
    # Return original input if resolution failed
    echo "[DNS LOOKUP] Failed to resolve domain ${DOMAIN} to IP address" >&2
    echo "${DOMAIN}"
}

# Patch server.js with necessary fixes
echo "[PATCH] Checking server.js for required patches..."

# Disable proxy streams if not already disabled
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    echo "[PATCH] Adding 'self.proxyStreamsEnabled = false' to server.js after 'self.allTranscodeProfiles = []' line"
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
    echo "[PATCH] ✓ Proxy streams disabled"
else
    echo "[PATCH] ✓ Proxy streams already disabled"
fi

# Fix disk space check to work in all environments
if grep -q 'df -k' server.js; then
    echo "[PATCH] Replacing 'df -k' with 'df -Pk' in server.js to ensure consistent output format across systems"
    sed -i 's/df -k/df -Pk/g' server.js
    echo "[PATCH] ✓ Disk space check fixed"
else
    echo "[PATCH] ✓ Disk space check already using correct command"
fi

#############################################
# SERVER URL CONFIGURATION
#############################################

if [ -n "${SERVER_URL}" ]; then
    echo "[URL CONFIG] Processing SERVER_URL: ${SERVER_URL}"
    ORIGINAL_SERVER_URL="${SERVER_URL}"

    # Handle special cases in SERVER_URL (0.0.0.0 or stremio.rocks domains)
    if echo "${SERVER_URL}" | grep -q "0\.0\.0\.0"; then
        echo "[URL CONFIG] Found '0.0.0.0' in SERVER_URL, will replace with actual IP"
        PUBLIC_IP=$(get_public_ip)

        if [ -n "${PUBLIC_IP}" ]; then
            # Replace 0.0.0.0 with the public IP while preserving protocol and port
            SERVER_URL=$(echo "${SERVER_URL}" | sed "s/0\.0\.0\.0/${PUBLIC_IP}/g")
            echo "[URL CONFIG] Replaced 0.0.0.0 with public IP: ${ORIGINAL_SERVER_URL} -> ${SERVER_URL}"
        else
            echo "[URL CONFIG] Failed to obtain public IP, keeping original SERVER_URL with 0.0.0.0"
        fi
    elif echo "${SERVER_URL}" | grep -q "0-0-0-0\.519b6502d940\.stremio\.rocks"; then
        echo "[URL CONFIG] Found 'stremio.rocks' test domain in SERVER_URL, will replace with actual IP"
        PUBLIC_IP=$(get_public_ip)

        if [ -n "${PUBLIC_IP}" ]; then
            # Convert dots in IP to dashes for domain format, then replace 0-0-0-0 with it
            FORMATTED_IP=$(echo "${PUBLIC_IP}" | sed 's/\./-/g')
            SERVER_URL=$(echo "${SERVER_URL}" | sed "s/0-0-0-0/${FORMATTED_IP}/g")
            echo "[URL CONFIG] Replaced 0-0-0-0 in domain with public IP (using dashes): ${ORIGINAL_SERVER_URL} -> ${SERVER_URL}"
        else
            echo "[URL CONFIG] Failed to obtain public IP, keeping original SERVER_URL with stremio.rocks domain"
        fi
    fi

    # Ensure URL has trailing slash for consistency
    SERVER_URL_BEFORE="${SERVER_URL}"
    SERVER_URL=$(echo "${SERVER_URL}" | sed 's:/*$:/:')

    if [ "${SERVER_URL}" != "${SERVER_URL_BEFORE}" ]; then
        echo "[URL CONFIG] Added trailing slash for consistency: ${SERVER_URL_BEFORE} -> ${SERVER_URL}"
    fi

    echo "[URL CONFIG] Final server URL: ${SERVER_URL}"

    # Update localStorage for the web client to use our server
    echo "[CONFIG] Updating localStorage.json to use configured server URL"
    echo "[CONFIG] Replacing 'http://127.0.0.1:11470/' with '${SERVER_URL}'"
    cp localStorage.json build/localStorage.json
    sed -i "s|http://127.0.0.1:11470/|${SERVER_URL}|g" build/localStorage.json
fi

#############################################
# WEB UI CONFIGURATION
#############################################

# Echo startup message
echo "[STARTUP] Starting Stremio server at $(date)"
echo "[STARTUP] Configuration summary:"
echo "  - Config folder: ${CONFIG_FOLDER}"
echo "  - IP Address: ${IPADDRESS}"
echo "  - Server URL: ${SERVER_URL}"

# Handle different startup modes based on configuration
if [ -n "${IPADDRESS}" ]; then
    # Start the server process
    echo "[STARTUP] Starting Stremio server process"
    node server.js &
    SERVER_PID=$!
    echo "[STARTUP] Server started with PID: ${SERVER_PID}"

    # Handle IP address resolution for "any address" values
        echo "[STARTUP] IPADDRESS is set to '${IPADDRESS}' which indicates 'any address'"
        PUBLIC_IP=$(get_public_ip)

        # If we successfully obtained a public IP, use it instead of the original IPADDRESS
        if [ -n "${PUBLIC_IP}" ]; then
            echo "[STARTUP] Will use discovered public IP address: ${PUBLIC_IP} (replacing ${IPADDRESS})"
            IPADDRESS="${PUBLIC_IP}"
        else
            echo "[STARTUP] ⚠ Failed to obtain public IP address, falling back to original value: ${IPADDRESS}"
            echo "[STARTUP] ⚠ This may cause issues with certificate generation"
        fi
    else
        # Resolve domain name in IPADDRESS if needed
        if ! echo "${IPADDRESS}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "[STARTUP] IPADDRESS '${IPADDRESS}' doesn't look like an IP address, attempting to resolve"
            RESOLVED_IP=$(resolve_domain_to_ip "${IPADDRESS}")

            if [ "${RESOLVED_IP}" != "${IPADDRESS}" ]; then
                echo "[STARTUP] Resolved domain to IP: ${IPADDRESS} -> ${RESOLVED_IP}"
                IPADDRESS="${RESOLVED_IP}"
            else
                echo "[STARTUP] ⚠ Could not resolve domain to IP, using as-is: ${IPADDRESS}"
                echo "[STARTUP] ⚠ This may cause issues with certificate generation"
            fi
        else
            echo "[STARTUP] Using provided IP address: ${IPADDRESS}"
        fi
    fi

    # Certificate setup for HTTPS
    CERT_URL="http://localhost:11470/get-https?authKey=&ipAddress=${IPADDRESS}"
    echo "[HTTPS] Attempting to fetch HTTPS certificate for IP: ${IPADDRESS}"
    echo "[HTTPS] Using URL: ${CERT_URL}"

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
        echo "[HTTPS] ⚠ Failed to fetch HTTPS certificate. Curl exited with status: ${CURL_STATUS}"
    else
        echo "[HTTPS] ✓ Successfully requested HTTPS certificate"
    fi

    # Extract certificate information
    echo "[HTTPS] Extracting certificate information from ${CONFIG_FOLDER}httpsCert.json"
    IMPORTED_DOMAIN="$(node certificate.js --action extract --json-path "${CONFIG_FOLDER}httpsCert.json")"
    EXTRACT_STATUS="$?"
    IMPORTED_CERT_FILE="${CONFIG_FOLDER}${IMPORTED_DOMAIN}.pem"

    if [ "${EXTRACT_STATUS}" -eq 0 ]; then
        echo "[HTTPS] ✓ Successfully extracted domain from certificate: ${IMPORTED_DOMAIN}"
        echo "[HTTPS] Certificate file location: ${IMPORTED_CERT_FILE}"

        # Only update hosts file if UPDATE_HOSTS is set to true
        if [ "${UPDATE_HOSTS:-false}" = "true" ]; then
            echo "[HOSTS] Adding entry to /etc/hosts: '${IPADDRESS} ${IMPORTED_DOMAIN}'"
            echo "${IPADDRESS} ${IMPORTED_DOMAIN}" >> /etc/hosts
        fi
        
        if [ -n "${IMPORTED_DOMAIN}" ] && [ -f "${IMPORTED_CERT_FILE}" ]; then
        echo "[SERVER] Starting Web UI server with HTTPS enabled"
        echo "[SERVER] Using certificate: ${IMPORTED_CERT_FILE}"
        start_http_server -S -C "${IMPORTED_CERT_FILE}" -K "${IMPORTED_CERT_FILE}"
    else
            echo "[HTTPS] ⚠ Failed to setup HTTPS due to missing or invalid certificate"
            echo "[HTTPS] ⚠ Attempting to start Web UI server with HTTP instead"
            echo "[SERVER] Starting Web UI server with HTTP"
            start_http_server
        fi
    else
        echo "[HTTPS] ⚠ Failed to extract domain from certificate, exit code: ${EXTRACT_STATUS}"
        echo "[HTTPS] ⚠ This may indicate a problem with the certificate generation process"
        echo "[HTTPS] ⚠ Attempting to start Web UI server with HTTP instead"
        echo "[SERVER] Starting Web UI server with HTTP"
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
    node server.js &
    start_http_server
fi
