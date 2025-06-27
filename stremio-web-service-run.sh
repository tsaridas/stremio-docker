#!/bin/sh -e

CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"
AUTH_CONF_FILE="/etc/nginx/auth.conf"
HTPASSWD_FILE="/etc/nginx/.htpasswd"

# check if proxyStreamsEnabled is set to false in server.js and add it if not.
if ! grep -q 'self.proxyStreamsEnabled = false,' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js
fi

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    if [[ "${SERVER_URL: -1}" != "/" ]]; then
        SERVER_URL="$SERVER_URL/"
    fi
    cp localStorage.json build/localStorage.json
    touch build/server_url.env
    sed -i "s|http://127.0.0.1:11470/|${SERVER_URL}|g" build/localStorage.json
elif [ -n "${AUTO_SERVER_URL}" ] && [ "${AUTO_SERVER_URL}" -eq 1 ]; then
    cp localStorage.json build/localStorage.json
fi

# Setup authentication if environment variables are set
if [[ -n "${USERNAME-}" && -n "${PASSWORD-}" ]]; then
    echo "Setting up HTTP basic authentication..."
    htpasswd -bc "$HTPASSWD_FILE" "$USERNAME" "$PASSWORD"
    echo 'auth_basic "Restricted Content";' >$AUTH_CONF_FILE
    echo 'auth_basic_user_file '"$HTPASSWD_FILE"';' >>$AUTH_CONF_FILE
else
    echo "No HTTP basic authentication will be used."
fi

start_http_server() {
    if [ -n "${WEBUI_INTERNAL_PORT-}" ] && [[ "${WEBUI_INTERNAL_PORT}" =~ ^[0-9]+$ ]] && [ "${WEBUI_INTERNAL_PORT}" -ge 1 ] && [ "${WEBUI_INTERNAL_PORT}" -le 65535 ]; then
        sed -i "s/8080/${WEBUI_INTERNAL_PORT}/g" /etc/nginx/http.d/default.conf
    fi
    nginx -g "daemon off;"
}

if [ -n "${IPADDRESS}" ]; then 
    node certificate.js --action fetch
    EXTRACT_STATUS="$?"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -f "/srv/stremio-server/certificates.pem" ]; then
        IP_DOMAIN=$(echo $IPADDRESS | sed 's/\./-/g')
        echo "${IPADDRESS} ${IP_DOMAIN}.519b6502d940.stremio.rocks" >> /etc/hosts
        cp /etc/nginx/https.conf /etc/nginx/http.d/default.conf
        
        node certificate.js --action load --pem-path "/srv/stremio-server/certificates.pem" --domain "${IP_DOMAIN}.519b6502d940.stremio.rocks" --json-path "${CONFIG_FOLDER}httpsCert.json"
        if [ "$?" -eq 0 ]; then
            echo "Certificate for stremio server on port 12470 was setup."
        else
            echo "Failed to setup Certificate for stremio server on port 12470."
        fi
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
    fi
elif [ -n "${CERT_FILE}" ]; then
    if [ -f ${CONFIG_FOLDER}${CERT_FILE} ]; then
        cp ${CONFIG_FOLDER}${CERT_FILE} /srv/stremio-server/certificates.pem
        cp /etc/nginx/https.conf /etc/nginx/http.d/default.conf
        node certificate.js --action load --pem-path "/srv/stremio-server/certificates.pem" --domain "${DOMAIN}" --json-path "${CONFIG_FOLDER}httpsCert.json"
        if [ "$?" -eq 0 ]; then
            echo "Certificate for stremio server on port 12470 was setup."
        else
            echo "Failed to setup Certificate for stremio server on port 12470."
        fi
    fi
fi
node server.js &
start_http_server
