#!/usr/bin/env /bin/bash

# Get the paths to curl and wget
CURL=$( which curl )
WGET=$( which wget )

# Pick our optimal fetching program (curl, then wget, then install curl)
if [[ -n ${CURL} ]]; then
    FETCH="${CURL} --fail -O"
elif [[ -n ${WGET} ]]; then
    FETCH="${WGET}"
else
    echo "Failed to find a suitable download program. We're not sure how you dowloaded this script, but we'll install 'curl' automatically."
    # shellcheck disable=SC2206
    # We are OK with word-splitting here since we control the contents
    echo "> Installing required dependencies."
    apt install --yes curl

    FETCH="${CURL} --fail -O"
    echo
fi

# If we have VERSION set (i.e. different than empty), then we want to download it from AWS
if [ -n "$VERSION" ] ; then
    $FETCH https://dl.strem.io/server/${VERSION}/${BUILD}/server.js
fi
