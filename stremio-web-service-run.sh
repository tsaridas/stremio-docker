#!/bin/sh -e

# Set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-/srv/.stremio-server/}"

# Check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    cp localStorage.json build/localStorage.json
    TARGET_URL="${SERVER_URL}"
    if [ -z "${TARGET_URL}" ]; then
      TARGET_URL="http://127.0.0.1:${SERVER_PORT}/"
    fi
    TARGET_URL=$(echo "${TARGET_URL}" | sed 's:/*$:/:' )
    sed -i "s|http://127.0.0.1:11470/|${TARGET_URL}|g" build/localStorage.json
fi

start_http_server() {
    http-server build/ -p "${WEBUI_PORT}" -d false "$@"
}

# Echo startup message
echo "Starting Stremio server at $(date)"
echo "Config folder: ${CONFIG_FOLDER}"
echo "Web UI Port: ${WEBUI_PORT}"
echo "Server Port: ${SERVER_PORT}"

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
