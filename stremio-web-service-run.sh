#!/bin/sh -e
node server.js &
sleep 1
CONFIG_FOLDER="/root/.stremio-server/"
if [ ! -z "$IPADDRESS" ]; then 
	curl http://localhost:11470/get-https?ipAddress="$IPADDRESS"
	CERT=$(node extract_certificate.js "$CONFIG_FOLDER")
	echo "$IPADDRESS"\t"$CERT" >> /etc/hosts
	http-server build/ -p 8080 -d false -S -K "$CONFIG_FOLDER""$CERT".pem -C "$CONFIG_FOLDER""$CERT".pem
else
	http-server build/ -p 8080 -d false
fi
