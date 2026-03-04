#!/bin/sh -e

CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"
AUTH_CONF_FILE="/etc/nginx/auth.conf"
HTPASSWD_FILE="/etc/nginx/.htpasswd"

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    case "$SERVER_URL" in */) ;; *)
        SERVER_URL="$SERVER_URL/"
    ;; esac
    cp localStorage.json build/localStorage.json
    touch build/server_url.env
    sed -i "s|http://127.0.0.1:11470/|"${SERVER_URL}"|g" build/localStorage.json
elif [ -n "${AUTO_SERVER_URL}" ] && [ "${AUTO_SERVER_URL}" -eq 1 ]; then
    cp localStorage.json build/localStorage.json
fi

if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
    echo "Setting up HTTP basic authentication..."
    htpasswd -bc "${HTPASSWD_FILE}" "${USERNAME}" "${PASSWORD}"
    echo 'auth_basic "Restricted Content";' >"${AUTH_CONF_FILE}"
    echo 'auth_basic_user_file '"${HTPASSWD_FILE}"';' >>"${AUTH_CONF_FILE}"
else
    echo "No HTTP basic authentication will be used."
fi

start_http_server() {
    if [ -n "${WEBUI_INTERNAL_PORT}" ] && [ "${WEBUI_INTERNAL_PORT}" -ge 1 ] && [ "${WEBUI_INTERNAL_PORT}" -le 65535 ]; then
        sed -i "s/8080/"${WEBUI_INTERNAL_PORT}"/g" /etc/nginx/http.d/default.conf
    fi
    nginx -g "daemon off;"
}

if [ -n "${IPADDRESS}" ]; then 
    node certificate.js --action fetch
    EXTRACT_STATUS="$?"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -f "/srv/stremio-server/certificates.pem" ]; then
        IP_DOMAIN=$(echo "${IPADDRESS}" | sed 's/\./-/g')
        echo "${IPADDRESS} ${IP_DOMAIN}.519b6502d940.stremio.rocks" >> /etc/hosts
        cp /etc/nginx/https.conf /etc/nginx/http.d/default.conf
        node certificate.js --action load --pem-path "/srv/stremio-server/certificates.pem" --domain "${IP_DOMAIN}.519b6502d940.stremio.rocks" --json-path "${CONFIG_FOLDER}httpsCert.json"
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
    fi
elif [ -n "${CERT_FILE}" ]; then
    if [ -f "${CONFIG_FOLDER}${CERT_FILE}" ]; then
        cp "${CONFIG_FOLDER}${CERT_FILE}" /srv/stremio-server/certificates.pem
        cp /etc/nginx/https.conf /etc/nginx/http.d/default.conf
        node certificate.js --action load --pem-path "/srv/stremio-server/certificates.pem" --domain "${DOMAIN}" --json-path "${CONFIG_FOLDER}httpsCert.json"
    fi
fi
# Force NVENC hw accel: patch server.js to skip the broken auto-test
# The auto-test always fails (0.2s sample + concurrency race) and disables hw accel.
# We disable the test and set correct NVENC settings directly.
if [ -f /usr/bin/nvidia-smi ] 2>/dev/null; then
    SETTINGS="${CONFIG_FOLDER}server-settings.json"

    # Patch server.js: prevent auto-test from disabling hw accel
    sed -i 's/transcodeHardwareAccel: !1/transcodeHardwareAccel: !0/g' server.js

    # Patch nvenc-linux profile for 10-bit compatibility (GTX 1070 / Pascal):
    # 1. Remove -hwaccel_output_format cuda (forces 10-bit CUDA frames → NVENC fails)
    sed -i 's/"-hwaccel", "cuda", "-hwaccel_output_format", "cuda"/"-hwaccel", "cuda"/' server.js
    # 2. Remove -init_hw_device/-filter_hw_device (only needed for scale_cuda)
    sed -i 's/"-init_hw_device", "cuda=cu:0", "-filter_hw_device", "cu", "-hwaccel"/"-hwaccel"/' server.js
    # 3. Use CPU scale instead of scale_cuda (CUDA frames auto-downloaded by ffmpeg)
    sed -i 's/scale: "scale_cuda"/scale: !1/' server.js
    # 4. Restore lanczos scaler flags for CPU scale
    sed -i '/nvenc/,/vaapi/{s/scaleExtra: ""/scaleExtra: ":flags=lanczos"/}' server.js
    # 5. Disable wrapSwFilters (no hwdownload/hwupload needed with CPU scale)
    sed -i 's/wrapSwFilters: \[ "hwdownload", "hwupload_cuda" \]/wrapSwFilters: !1/' server.js

    echo "NVENC: patched server.js (auto-test + 10-bit compat + CPU scale)"

    # Set NVENC settings in config file
    if [ -f "$SETTINGS" ]; then
        sed -i \
            -e 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' \
            -e 's/"transcodeProfile": null/"transcodeProfile": "nvenc-linux"/' \
            -e 's/"allTranscodeProfiles": \[\]/"allTranscodeProfiles": ["nvenc-linux"]/' \
            "$SETTINGS"
        echo "NVENC: settings configured (transcodeHardwareAccel: true, profile: nvenc-linux)"
    fi
fi

node server.js &
SERVER_PID=$!

start_http_server
