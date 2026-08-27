#!/bin/sh -e

CONFIG_FOLDER="${APP_PATH:-${HOME}/.stremio-server/}"
AUTH_CONF_FILE="/etc/nginx/auth.conf"
HTPASSWD_FILE="/etc/nginx/.htpasswd"

sed -i 's/df -k/df -Pk/g' server.js

if [ -n "${SERVER_URL}" ]; then
    if [ "${SERVER_URL: -1}" != "/" ]; then
        SERVER_URL="$SERVER_URL/"
    fi
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

# Probe DRM render nodes for a usable VA-API device (issue #141).
# stremio-server tests its vaapi profile against /dev/dri/renderD128 only and
# falls back to CPU silently when that handshake fails; on kernels >= 6.1 the
# iGPU may enumerate as renderD129/card1+ instead.
vaapi_preflight() {
    [ "${VAAPI_PREFLIGHT:-1}" = "1" ] || return 0
    [ -d /dev/dri ] || return 0
    command -v ffmpeg >/dev/null 2>&1 || return 0

    echo "[vaapi] Probing DRM render nodes..."
    ok_nodes=""
    for node in /dev/dri/renderD*; do
        [ -c "$node" ] || continue
        if err=$(ffmpeg -nostdin -v error \
                -init_hw_device vaapi=probe:"$node" \
                -f lavfi -i "color=c=black:s=256x256:r=1" \
                -vf "format=nv12,hwupload,hwdownload,format=yuv420p" \
                -frames:v 1 -f null - 2>&1); then
            echo "[vaapi] $node: OK"
            ok_nodes="$ok_nodes $node"
        else
            echo "[vaapi] $node: FAILED${err:+: $(printf '%s\n' "$err" | head -n 1)}"
            if [ "${VAAPI_PREFLIGHT_DEBUG:-0}" = "1" ]; then
                printf '%s\n' "$err"
            fi
        fi
    done

    case "$ok_nodes" in
        *"renderD128"*)
            echo "[vaapi] /dev/dri/renderD128 is VA-API capable."
            ;;
        "")
            echo "[vaapi] WARNING: no usable VA-API render node found; transcoding will fall back to CPU."
            drivers=""
            for drv in /usr/lib/dri/*_drv_video.so /usr/lib/*/dri/*_drv_video.so; do
                if [ -e "$drv" ]; then
                    drivers="$drivers $(basename "$drv" _drv_video.so)"
                fi
            done
            echo "[vaapi] Installed libva drivers:${drivers:- none}"
            echo "[vaapi] Hint: pin LIBVA_DRIVER_NAME (iHD for Intel Gen8+, i965 for older) if the wrong driver loads."
            ;;
        *)
            echo "[vaapi] WARNING: /dev/dri/renderD128 is not VA-API capable but other nodes are."
            echo "[vaapi] stremio-server probes renderD128 only and will silently fall back to CPU (issue #141)."
            for n in $ok_nodes; do
                case "$n" in
                    *"renderD128"*) ;;
                    *) echo "[vaapi] Suggested compose remap: \"- /dev/dri/$(basename "$n"):/dev/dri/renderD128\"" ;;
                esac
            done
            ;;
    esac
}

if [ -n "${IPADDRESS}" ]; then 
    node certificate.js --action fetch
    EXTRACT_STATUS="$?"

    if [ "${EXTRACT_STATUS}" -eq 0 ] && [ -f "/srv/stremio-server/certificates.pem" ]; then
        RESOLVED_IP="${IPADDRESS}"
        if [ "${IPADDRESS}" = "0-0-0-0" ] && [ -f "/srv/stremio-server/detected-ip.txt" ]; then
            RESOLVED_IP=$(cat /srv/stremio-server/detected-ip.txt)
        fi
        IP_DOMAIN=$(echo "${RESOLVED_IP}" | sed 's/\./-/g')
        echo "${RESOLVED_IP} ${IP_DOMAIN}.519b6502d940.stremio.rocks" >> /etc/hosts
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
vaapi_preflight || true
node --no-deprecation server.js &
start_http_server
