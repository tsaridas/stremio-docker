#!/bin/sh

# fix for incomptible df
alias df="df -P"

# URL to check
URL="http://localhost:11470/stats.json"

# Process name
PROCESS_NAME="node server.js"

# Make the HTTP call
response=$(curl -s "$URL")
curl_exit_status=$?

# Check if curl failed (non-zero exit status)
if [ $curl_exit_status -ne 0 ]; then
  echo "Curl failed with connection error. Restarting the process..." > /proc/1/fd/1 2>/proc/1/fd/2

  # Find the process ID of "node server.js" and kill it
  pkill -f "$PROCESS_NAME"

  # Restart the process in the background
  nohup $PROCESS_NAME > /proc/1/fd/1 2>/proc/1/fd/2 &

  echo "Process restarted due to curl connection error." > /proc/1/fd/1 2>/proc/1/fd/2

# Check if the response is an empty JSON object
elif [ "$response" == "{}" ]; then
  echo "Empty JSON response detected. Restarting the process..." > /proc/1/fd/1 2>/proc/1/fd/2

  # Find the process ID of "node server.js" and kill it
  pkill -f "$PROCESS_NAME"

  # Restart the process in the background
  nohup $PROCESS_NAME > /proc/1/fd/1 2>/proc/1/fd/2 &

  echo "Process restarted." > /proc/1/fd/1 2>/proc/1/fd/2
else
  echo "Non-empty JSON response. No action needed." > /proc/1/fd/1 2>/proc/1/fd/2
fi
