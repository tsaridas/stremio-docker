#!/bin/sh -e

# set the configuration folder path.
CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"

# check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    cp localStorage.json build/localStorage.json
    sed -i "s|http://127.0.0.1:11470/|${SERVER_URL}|g" build/localStorage.json
fi

node server.js &

start_http_server() {
    nginx -g "daemon off;"
}

if [ -n "${IPADDRESS}" ]; then 
    IMPORTED_DOMAIN="$(node certificate.js)"
    EXTRACT_STATUS="$?"
    IMPORTED_CERT_FILE="${CONFIG_FOLDER}${IMPORTED_DOMAIN}.pem"
    echo "Extracted domain ${IMPORTED_DOMAIN} with status ${EXTRACT_STATUS} and cert file ${IMPORTED_CERT_FILE}"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -n "${IMPORTED_DOMAIN}" ] && [ -f "${IMPORTED_CERT_FILE}" ]; then
        IP_DOMAIN=$(echo $IPADDRESS | sed 's/./-/g')
        echo "${IPADDRESS} ${IP_DOMAIN}.519b6502d940.stremio.rocks" >> /etc/hosts
        cp /etc/nginx/https.conf /etc/nginx/http.d/
        start_http_server
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
    fi
elif [ -n "${CERT_FILE}" ]; then
    if [ -f ${CONFIG_FOLDER}${CERT_FILE} ]; then
        cp ${CONFIG_FOLDER}${CERT_FILE} /srv/stremio-server/
        cp /etc/nginx/https.conf /etc/nginx/http.d/
    fi
fi

start_http_server
