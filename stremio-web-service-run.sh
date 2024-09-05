#!/bin/sh -e
if [ -z "$APP_PATH" ]; then
	CONFIG_FOLDER="$HOME"/.stremio-server/
else
	CONFIG_FOLDER=$APP_PATH/
fi

# fix for not passed config option
sed -i '/self.allTranscodeProfiles = \[\]/a \ \ \ \ \ \ \ \ self.proxyStreamsEnabled = false,' server.js

# fix for incomptible df
alias df="df -P"

node server.js &
sleep 1

if [ ! -z "$IPADDRESS" ]; then 
	curl "http://localhost:11470/get-https??authKey=&ipAddress=$IPADDRESS"
	CERT=$(node extract_certificate.js "$CONFIG_FOLDER")
	echo "$IPADDRESS" "$CERT" >> /etc/hosts
	http-server build/ -p 8080 -d false -S -K "$CONFIG_FOLDER""$CERT".pem -C "$CONFIG_FOLDER""$CERT".pem
else
	http-server build/ -p 8080 -d false
fi
