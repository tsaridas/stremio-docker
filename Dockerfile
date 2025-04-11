# Copyright (C) 2017-2023 Smart code 203358507

# the node version for running the server
ARG NODE_VERSION=20

FROM node:$NODE_VERSION-buster AS base

#ARG VERSION=main
# Which build to download for the image,
# possible values are: desktop, android, androidtv, webos and tizen
# webos and tizen require older versions of node:
# - Node.js `v0.12.2` for WebOS 3.0 (2016 LG TV)
# - Node.js `v4.4.3` for Tizen 3.0 (2017 Samsung TV)
# But, as of writing this, we only support desktop!
ARG BUILD=desktop

LABEL com.stremio.vendor="Smart Code Ltd."
LABEL version=${VERSION}
LABEL description="Stremio's streaming Server"
LABEL org.opencontainers.image.source=https://github.com/tsaridas/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web Player and Server"
LABEL org.opencontainers.image.licenses=MIT

SHELL ["/bin/sh", "-c"]

WORKDIR /stremio

# We require version <= 4.4.1
# https://github.com/jellyfin/jellyfin-ffmpeg/releases/tag/v4.4.1-4
ARG JELLYFIN_VERSION=4.4.1-4

# Install dependencies
RUN apt-get -y update && \
    apt-get -y install wget git apt-transport-https && \
    echo "deb http://deb.debian.org/debian buster main" > /etc/apt/sources.list.d/buster.list && \
    apt-get -y update && \
    apt-get -y install libvpx5 libwebp6 libx264-155 libx265-165

# Install Jellyfin FFMPEG
RUN wget https://repo.jellyfin.org/archive/ffmpeg/debian/4.4.1-4/jellyfin-ffmpeg_4.4.1-4-buster_$(dpkg --print-architecture).deb -O jellyfin-ffmpeg.deb && \
    apt-get -y install ./jellyfin-ffmpeg.deb && \
    rm jellyfin-ffmpeg.deb

# RUN apt-get install -y bash
COPY download_server.sh ./
RUN chmod +x download_server.sh && ./download_server.sh

# This copy could will override the server.js that was downloaded with the one provided in this folder
# for custom or manual builds if $VERSION argument is not empty.
COPY . .

#########################################################################

# Builder image for stremio-web
FROM base AS builder-web

WORKDIR /build
ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; \
    if [ "$BRANCH" == "release" ]; then \
        git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | awk '{print $2}' | sort -V | tail -n1 | cut -d/ -f3) stremio-web; \
    else \
        git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; \
    fi

WORKDIR /build/stremio-web
COPY ./load_localStorage.js ./src/load_localStorage.js
#RUN sed -i "/entry: {/a \\        loader: './src/load_localStorage.js'," webpack.config.js

RUN npm install && npm run build

RUN wget $(wget -O- https://raw.githubusercontent.com/Stremio/stremio-shell/master/server-url.txt) && \
    wget -mkEpnp -nH "https://app.strem.io/" "https://app.strem.io/worker.js" \
    "https://app.strem.io/images/stremio.png" "https://app.strem.io/images/empty.png" -P build/shell/ || true

RUN ls -la

#########################################################################

# Main image
FROM node:$NODE_VERSION-buster-slim

# Install required runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create and set the correct directory structure
WORKDIR /srv/.stremio-server

# Copy stremio-web files from builder
COPY --from=builder-web /build/stremio-web/build ./build
COPY --from=builder-web /build/stremio-web/server.js ./server.js

# Install http-server
RUN npm install -g http-server --no-audit && \
    npm cache clean --force

# Copy configuration files
COPY ./stremio-web-service-run.sh ./
RUN chmod +x stremio-web-service-run.sh
COPY ./certificate.js ./
COPY ./restart_if_idle.sh ./
RUN chmod +x restart_if_idle.sh
COPY ./localStorage.json ./
COPY ./localStorage.json ./server-settings.json

# Set permissions
RUN chmod +x stremio-web-service-run.sh restart_if_idle.sh

# HTTP
EXPOSE 11470

# HTTPS
EXPOSE 12470

# Webserver
EXPOSE 8080

# full path to the ffmpeg binary
ENV FFMPEG_BIN=/bin/ffmpeg

# full path to the ffprobe binary
ENV FFPROBE_BIN=/bin/ffprobe

# default https://app.strem.io/shell-v4.4/
ENV WEBUI_LOCATION=
ENV OPEN=
ENV HLS_DEBUG=
ENV DEBUG=
ENV DEBUG_MIME=
ENV DEBUG_FD=
ENV FFMPEG_DEBUG=
ENV FFSPLIT_DEBUG=
ENV NODE_DEBUG=
ENV NODE_ENV=production
ENV HTTPS_CERT_ENDPOINT=
ENV DISABLE_CACHING=
# disable or enable
ENV READABLE_STREAM=
# remote or local
ENV HLSV2_REMOTE=

# Custom application path for storing server settings, certificates, etc
# You can change this if you like but the default path is where the current dir is in the image.
ENV APP_PATH=/srv/.stremio-server/

# Disable CORS in order to serve stremio-web from the same container.
ENV NO_CORS=1

# "Docker image shouldn't attempt to find network devices or local video players."
# See: https://github.com/Stremio/server-docker/issues/7
ENV CASTING_DISABLED=1

# Set this to your lan or public ip to use https.
ENV IPADDRESS=
# Set this to your domain name
ENV DOMAIN=
# Set this to the path to your certificate file
ENV CERT_FILE=

# Server url
ENV SERVER_URL=

# Volume configuration
VOLUME ["/srv/.stremio-server"]

CMD ["./stremio-web-service-run.sh"]
