#!/bin/sh -e

CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"
AUTH_CONF_FILE="/etc/nginx/auth.conf"

# check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    # Check if the last character is a slash
    if [[ "${SERVER_URL: -1}" != "/" ]]; then
        SERVER_URL="$SERVER_URL/"
    fi
    cp localStorage.json build/localStorage.json
    sed -i "s|http://127.0.0.1:11470/|${SERVER_URL}|g" build/localStorage.json
fi

# Setup authentication if environment variables are set
if [[ -n "${USERNAME-}" && -n "${PASSWORD-}" ]]; then
    log "Setting up HTTP basic authentication..."
    htpasswd -bc "$HTPASSWD_FILE" "$USERNAME" "$PASSWORD"
    echo 'auth_basic "Restricted Content";' >$AUTH_CONF_FILE
    echo 'auth_basic_user_file '"$HTPASSWD_FILE"';' >>$AUTH_CONF_FILE
else
    log "No HTTP basic authentication will be used."
fi

node server.js &

start_http_server() {
    nginx -g "daemon off;"
}

if [ -n "${IPADDRESS}" ]; then 
    node certificate.js
    EXTRACT_STATUS="$?"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -f "/srv/stremio-server/certificates.pem" ]; then
        IP_DOMAIN=$(echo $IPADDRESS | sed 's/./-/g')
        echo "${IPADDRESS} ${IP_DOMAIN}.519b6502d940.stremio.rocks" >> /etc/hosts
        cp /etc/nginx/https.conf /etc/nginx/http.d/
        echo "##############################################################################################"
        echo "### PLEASE SETUP YOUR DNS ${IPADDRESS} TO POINT TO ${IP_DOMAIN}.519b6502d940.stremio.rocks ###"
        echo "##############################################################################################"
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
    fi
elif [ -n "${CERT_FILE}" ]; then
    if [ -f ${CONFIG_FOLDER}${CERT_FILE} ]; then
        cp ${CONFIG_FOLDER}${CERT_FILE} /srv/stremio-server/certificates.pem
        cp /etc/nginx/https.conf /etc/nginx/http.d/
    fi
fi

start_http_server
