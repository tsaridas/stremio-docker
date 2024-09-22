#!/bin/sh -e

# Set CONFIG_FOLDER based on APP_PATH
if [ -z "$APP_PATH" ]; then
    CONFIG_FOLDER="$HOME/.stremio-server/"
else
    CONFIG_FOLDER="$APP_PATH/"
fi

# Ensure server.js has necessary configurations
if ! grep -q 'self.proxyStreamsEnabled = false;' server.js; then
    sed -i '/self.allTranscodeProfiles = \[\]/a \    self.proxyStreamsEnabled = false;' server.js
fi

# Fix for incompatible df command
sed -i 's/df -k/df -Pk/g' server.js

# Start the server
node server.js &
sleep 2  # Increased sleep time to ensure server is ready

if [ -n "$IPADDRESS" ]; then 
    # Fetch HTTPS certificate
    curl --connect-timeout 5 \
         --retry-all-errors \
         --retry 5 \
         --silent \
         --output /dev/null \
         "http://localhost:11470/get-https?authKey=&ipAddress=$IPADDRESS"

    # Extract certificate and start server
    IMPORTED_DOMAIN=$(node certificate.js --action extract --json-path "$CONFIG_FOLDER/httpsCert.json")
    IMPORTED_CERT_FILE="$CONFIG_FOLDER$IMPORTED_DOMAIN.pem"

    if [ $? -eq 0 ] && [ -n "$IMPORTED_DOMAIN" ] && [ -f "$IMPORTED_CERT_FILE" ]; then
        # Update hosts file
        echo "$IPADDRESS $IMPORTED_DOMAIN" >> /etc/hosts
        
        # Start HTTPS server
        http-server build/ -p 8080 -d false -S -C "$IMPORTED_CERT_FILE"
    else
        echo "Failed to setup HTTPS. Falling back to HTTP."
        http-server build/ -p 8080 -d false
    fi
elif [ -n "$CERT_FILE" ] && [ -n "$DOMAIN" ]; then
    # Load certificate using certificate.js
    node certificate.js --action load --cert-file "$CONFIG_FOLDER/$CERT_FILE" --domain "$DOMAIN" --json-path "$CONFIG_FOLDER/httpsCert.json"
    
    # Start HTTPS server with the loaded certificate
    http-server build/ -p 8080 -d false -S -C "$CERT_FILE.pem"
else
    # Start HTTP server if neither IPADDRESS nor CERT_FILE and DOMAIN are set
    http-server build/ -p 8080 -d false
fi
