#!/bin/sh -e

# Set CONFIG_FOLDER based on APP_PATH
if [ -z "${APP_PATH}" ]; then
    CONFIG_FOLDER="${HOME}/.stremio-server/"
else
    CONFIG_FOLDER="${APP_PATH}/"
fi

# Ensure server.js has necessary configurations
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

# Fix for incompatible df command
sed -i 's/df -k/df -Pk/g' server.js


if [ -n "${IPADDRESS}" ]; then 
    # Start the server
    node server.js &
	sleep 2
    # Fetch HTTPS certificate
    curl --connect-timeout 5 \
         --retry-all-errors \
         --retry 5 \
         --silent \
         --output /dev/null \
         "http://localhost:11470/get-https?authKey=&ipAddress=${IPADDRESS}"

    # Extract certificate and get domain
    IMPORTED_DOMAIN="$(node certificate.js --action extract --json-path "${CONFIG_FOLDER}httpsCert.json")"
    EXTRACT_STATUS="$?"
    IMPORTED_CERT_FILE="${CONFIG_FOLDER}${IMPORTED_DOMAIN}.pem"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -n "${IMPORTED_DOMAIN}" ] && [ -f "${CONFIG_FOLDER}${IMPORTED_CERT_FILE}" ]; then
        # Update hosts file
        echo "${IPADDRESS} ${IMPORTED_DOMAIN}" >> /etc/hosts
        
        # Start HTTPS server
        http-server build/ -p 8080 -d false -S -C "${CONFIG_FOLDER}${IMPORTED_CERT_FILE}" -K "${CONFIG_FOLDER}${IMPORTED_CERT_FILE}"
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
        http-server build/ -p 8080 -d false
    fi
elif [ -n "${CERT_FILE}" ] && [ -n "${DOMAIN}" ]; then
    # Load certificate using certificate.js
    node certificate.js --action load --pem-path "${CONFIG_FOLDER}${CERT_FILE}" --domain "${DOMAIN}" --json-path "${CONFIG_FOLDER}httpsCert.json"
    if [ "$?" -eq 0 ]; then
        # Start the server with the loaded certificate
        node server.js &
        # Start HTTPS server with the loaded certificate
        http-server build/ -p 8080 -d false -S -C "${CONFIG_FOLDER}${CERT_FILE}" -K "${CONFIG_FOLDER}${CERT_FILE}"
    else
        echo "Failed to load certificate. Falling back to HTTP."
        node server.js &
        http-server build/ -p 8080 -d false
    fi
else
    # Start the server
    node server.js &
    # Start HTTP server if neither IPADDRESS nor CERT_FILE and DOMAIN are set
    http-server build/ -p 8080 -d false
fi
