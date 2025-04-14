# Base image
ARG NODE_VERSION=${NODE_VERSION:-18}
FROM node:${NODE_VERSION}-alpine3.18 AS base

# Update base packages
RUN apk update && apk upgrade

# --- FFMpeg Build Stage ---
# Builds a custom version of ffmpeg required by Stremio Server
FROM base AS ffmpeg

# Install build dependencies for ffmpeg
# We build our own ffmpeg since 4.X is the only one supported
ENV BIN="/usr/bin"
RUN cd && \
  apk add --no-cache --virtual .build-dependencies \
  gnutls \
  freetype-dev \
  gnutls-dev \
  lame-dev \
  libass-dev \
  libogg-dev \
  libtheora-dev \
  libvorbis-dev \
  libvpx-dev \
  libwebp-dev \
  libssh2 \
  opus-dev \
  rtmpdump-dev \
  x264-dev \
  x265-dev \
  yasm-dev \
  build-base \
  coreutils \
  gnutls \
  nasm \
  dav1d-dev \
  libbluray-dev \
  libdrm-dev \
  zimg-dev \
  aom-dev \
  xvidcore-dev \
  fdk-aac-dev \
  libva-dev \
  git \
  x264 && \
  DIR=$(mktemp -d) && \
  cd "${DIR}" && \
  # Clone Jellyfin's ffmpeg fork (version 4.4.1-4)
  git clone --depth 1 --branch v4.4.1-4 https://github.com/jellyfin/jellyfin-ffmpeg.git && \
  cd jellyfin-ffmpeg* && \
  PATH="$BIN:$PATH" && \
  # Configure ffmpeg build
  ./configure --help && \
  ./configure --bindir="$BIN" --disable-debug \
  --prefix=/usr/lib/jellyfin-ffmpeg --extra-version=Jellyfin --disable-doc --disable-ffplay --disable-shared --disable-libxcb --disable-sdl2 --disable-xlib --enable-lto --enable-gpl --enable-version3 --enable-gmp --enable-gnutls --enable-libdrm --enable-libass --enable-libfreetype --enable-libfribidi --enable-libfontconfig --enable-libbluray --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-libwebp --enable-libvpx --enable-libx264 --enable-libx265  --enable-libzimg --enable-small --enable-nonfree --enable-libxvid --enable-libaom --enable-libfdk_aac --enable-vaapi --enable-hwaccel=h264_vaapi --toolchain=hardened && \
  # Build and install ffmpeg
  make -j$(nproc) && \
  make install && \
  make distclean && \
  # Clean up build dependencies and temp files
  rm -rf "${DIR}"  && \
  apk del --purge .build-dependencies

#########################################################################

# --- Web UI Build Stage ---
# Builds the Stremio Web UI static files
FROM base AS builder-web

WORKDIR /srv
# Install dependencies needed for building the web UI
RUN apk add --no-cache git wget

# Clone the Stremio Web UI repository
# Fetches the latest release tag if BRANCH=release, otherwise fetches the specified branch (default: development)
ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; if [ "$BRANCH" == "release" ];then git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | awk '{print $2}' | sort -V | tail -n1 | cut -d/ -f3); else git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; fi

WORKDIR /srv/stremio-web

COPY ./load_localStorage.js ./src/load_localStorage.js
#RUN sed -i "/entry: {/a \        loader: './src/load_localStorage.js'," webpack.config.js

# Install Node.js dependencies and build the web UI
RUN yarn install --no-audit --no-optional --mutex network --no-progress --ignore-scripts
RUN yarn build

# Download additional shell files (worker, images)
RUN wget $(wget -O- https://raw.githubusercontent.com/Stremio/stremio-shell/master/server-url.txt) && wget -mkEpnp -nH "https://app.strem.io/" "https://app.strem.io/worker.js" "https://app.strem.io/images/stremio.png" "https://app.strem.io/images/empty.png" -P build/shell/ || true

##########################################################################

# --- Final Stage ---
# Assembles the final image with the Stremio server and web UI
FROM base AS final

# --- Metadata ---
ARG VERSION=master
LABEL org.opencontainers.image.source=https://github.com/th3w1zard1/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web Player and Server in Docker"
LABEL org.opencontainers.image.licenses=MIT
LABEL version=${VERSION}

# --- Application Setup ---
WORKDIR /srv/stremio-server

# Copy built web UI and server files from previous stages
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./

# Install http-server globally to serve the web UI
RUN yarn global add http-server --no-audit --no-optional --mutex network --no-progress --ignore-scripts

# Copy custom scripts and configuration files
COPY ./stremio-web-service-run.sh ./
# Ensure the script uses Unix-style line endings (LF instead of CRLF)
RUN sed -i 's/\r$//' ./stremio-web-service-run.sh
COPY ./certificate.js ./
RUN chmod +x stremio-web-service-run.sh
COPY ./restart_if_idle.sh ./
RUN chmod +x restart_if_idle.sh
COPY localStorage.json ./

# --- Environment Variables ---
# Define arguments for configurable ports (can be set during build)
ARG WEBUI_PORT=8080
ARG SERVER_PORT=11470
ARG CASTING_PORT=12470

# Set default environment variables (can be overridden at runtime)
# Ports
# Port for the Stremio Web UI (served by http-server)
ENV WEBUI_PORT=${WEBUI_PORT}
# Port for the Stremio Server backend (HTTP)
ENV SERVER_PORT=${SERVER_PORT}
# Port likely used for casting/discovery
ENV CASTING_PORT=${CASTING_PORT}

# Paths and Binaries (usually automatically detected)
# Path to ffmpeg binary (leave empty for auto-detection)
ENV FFMPEG_BIN=
# Path to ffprobe binary (leave empty for auto-detection)
ENV FFPROBE_BIN=

# Web UI Configuration
# default https://app.strem.io/shell-v4.4/ - Keep empty unless you know what you're doing
ENV WEBUI_LOCATION=

# Server Behavior Configuration
# Unknown purpose (Stremio specific)
ENV OPEN=
# Enable HLS debugging (set to 'true')
ENV HLS_DEBUG=
# Generic debug flag (e.g., 'stremio-server')
ENV DEBUG=
# Enable MIME type debugging
ENV DEBUG_MIME=
# Enable file descriptor debugging
ENV DEBUG_FD=
# Enable ffmpeg process debugging
ENV FFMPEG_DEBUG=
# Enable ffsplit debugging
ENV FFSPLIT_DEBUG=
# Enable Node.js internal debugging
ENV NODE_DEBUG=
# Set Node.js environment (use 'development' for more logs)
ENV NODE_ENV=production
# Custom endpoint for fetching HTTPS certificates
ENV HTTPS_CERT_ENDPOINT=
# Disable server-side caching (set to 'true')
ENV DISABLE_CACHING=
# 'disable' or 'enable' readable stream handling
ENV READABLE_STREAM=
# 'remote' or 'local' HLSv2 handling
ENV HLSV2_REMOTE=

# Application Paths and Security
# Path for storing server settings, cache, certificates. Default is /srv/.stremio-server/
ENV APP_PATH=/srv/.stremio-server/
# Disable CORS protection (set to 'true', use with caution)
ENV NO_CORS=
# Disable casting functionality (set to 'true')
ENV CASTING_DISABLED=

# --- User Configuration (Override these as needed) ---
# Network Configuration
# Your LAN or public IP address (required for HTTPS certificate fetching)
ENV IPADDRESS=
# Your domain name (used with custom certificates)
ENV DOMAIN=
# Custom Certificate Files (place in APP_PATH volume)
# Filename of your custom PEM certificate file (e.g., mycert.pem)
ENV CERT_FILE=

# Server URL (if running behind a reverse proxy)
# The public URL of your Stremio server (e.g., https://stremio.mydomain.com)
ENV SERVER_URL=

# --- FFMpeg & Runtime Dependencies ---
# Copy ffmpeg binaries and libraries from the ffmpeg build stage
COPY --from=ffmpeg /usr/bin/ffmpeg /usr/bin/ffprobe /usr/bin/
COPY --from=ffmpeg /usr/lib/jellyfin-ffmpeg /usr/lib/

# Install runtime libraries required by ffmpeg and Stremio server
RUN apk add --no-cache libwebp libvorbis x265-libs x264-libs libass opus libgmpxx lame-libs gnutls libvpx libtheora libdrm libbluray zimg libdav1d aom-libs xvidcore fdk-aac libva curl

# Install architecture-specific hardware acceleration drivers (e.g., Intel VAAPI)
RUN if [ "$(uname -m)" = "x86_64" ]; then \
  apk add --no-cache intel-media-driver mesa-va-gallium; \
  fi

# Clean up package cache
RUN rm -rf /var/cache/apk/* && rm -rf /tmp/*

# --- Volume Mapping ---
# Persist server configuration, cache, and certificates outside the container
# Maps to APP_PATH by default unless overridden
VOLUME ["/srv/.stremio-server"]

# --- Ports ---
# Expose the configurable ports
EXPOSE ${WEBUI_PORT} ${SERVER_PORT} ${CASTING_PORT}

# --- Entrypoint & Command ---
# Use the custom run script as the main command
ENTRYPOINT []
CMD ["./stremio-web-service-run.sh"]
