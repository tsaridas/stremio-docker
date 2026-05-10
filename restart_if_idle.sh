#!/bin/sh

# URL to check
URL="http://localhost:11470/stats.json"

# Process name
PROCESS_NAME="node server.js"

# Function to restart the process
restart_process() {
    echo "$1" > /proc/1/fd/1 2>/proc/1/fd/2
    pkill -f "$PROCESS_NAME"
    nohup $PROCESS_NAME > /proc/1/fd/1 2>/proc/1/fd/2 &
    echo "Process restarted." > /proc/1/fd/1 2>/proc/1/fd/2
}

# Check if force restart is requested
if [ "$1" = "--force" ]; then
    restart_process "Force restart requested. Restarting the process..."
    exit 0
fi

# Make the HTTP call (BusyBox wget — avoids shipping standalone curl in the image)
response=$(wget -qO- "$URL" 2>/dev/null)
wget_exit_status=$?

# Check if the HTTP fetch failed (non-zero exit status)
if [ $wget_exit_status -ne 0 ]; then
    restart_process "HTTP fetch failed (wget). Restarting the process..."
# Check if the response is an empty JSON object
elif [ "$response" = "{}" ]; then
    restart_process "Empty JSON response detected. Restarting the process..."
else
    echo "Non-empty JSON response. No action needed." > /proc/1/fd/1 2>/proc/1/fd/2
fi
