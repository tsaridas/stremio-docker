#!/bin/sh -e

# set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"

# check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

start_http_server() {
    http-server build/ -p 8080 -d false "$@"
}

if [ -n "${IPADDRESS}" ]; then 
    node server.js &

    echo "Attempting to fetch HTTPS certificate for IP address: ${IPADDRESS}"
    curl --connect-timeout 5 \
         --retry-all-errors \
         --retry 10 \
         --retry-delay 1 \
         --verbose \
         "http://localhost:11470/get-https?authKey=&ipAddress=${IPADDRESS}"
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
    node server.js &
    start_http_server
fi
