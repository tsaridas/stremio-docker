#!/bin/sh -e
if [ -z "$APP_PATH" ]; then
	CONFIG_FOLDER="$HOME"/.stremio-server/
else
	CONFIG_FOLDER=$APP_PATH/
fi
# fix for not passed config option
jq '. + {"proxyStreamsEnabled": false}' "$CONFIG_FOLDER"server-settings.json > tmp.$$.json && mv tmp.$$.json "$CONFIG_FOLDER"server-settings.json

# fix for incomptible df
alias df="df -P"

node server.js &
if [ ! -z "$IPADDRESS" ]; then 
	curl "http://localhost:11470/get-https??authKey=&ipAddress=$IPADDRESS"
	CERT=$(node extract_certificate.js "$CONFIG_FOLDER")
	echo "$IPADDRESS" "$CERT" >> /etc/hosts
	http-server build/ -p 8080 -d false -S -K "$CONFIG_FOLDER""$CERT".pem -C "$CONFIG_FOLDER""$CERT".pem
else
	http-server build/ -p 8080 -d false
fi
