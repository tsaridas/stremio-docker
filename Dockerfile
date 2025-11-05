# We use node:20-alpine3.18 because it's the only one that supports the build-base package for ffmpeg. Changing to 3.21 will require a new ffmpeg build.
FROM node:20-alpine3.18 AS base

RUN apk update && apk upgrade

FROM base AS ffmpeg

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
  git clone --depth 1 --branch v4.4.1-4 https://github.com/jellyfin/jellyfin-ffmpeg.git && \
  cd jellyfin-ffmpeg* && \
  PATH="$BIN:$PATH" && \
  ./configure --help && \
  ./configure --bindir="$BIN" --disable-debug \
  --prefix=/usr/lib/jellyfin-ffmpeg --extra-version=Jellyfin --disable-doc --disable-ffplay --disable-shared --disable-libxcb --disable-sdl2 --disable-xlib --enable-lto --enable-gpl --enable-version3 --enable-gmp --enable-gnutls --enable-libdrm --enable-libass --enable-libfreetype --enable-libfribidi --enable-libfontconfig --enable-libbluray --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-libwebp --enable-libvpx --enable-libx264 --enable-libx265  --enable-libzimg --enable-small --enable-nonfree --enable-libxvid --enable-libaom --enable-libfdk_aac --enable-vaapi --enable-hwaccel=h264_vaapi --enable-hwaccel=hevc_vaapi --toolchain=hardened && \
  make -j4 && \
  make install && \
  make distclean && \
  rm -rf "${DIR}"  && \
  apk del --purge .build-dependencies

#########################################################################

# Builder image
FROM base AS builder-web


WORKDIR /srv
RUN apk add --no-cache git wget

ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; if [ "$BRANCH" == "release" ];then git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | awk '{print $2}' | sort -V | tail -n1 | cut -d/ -f3); else git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; fi

WORKDIR /srv/stremio-web

COPY ./load_localStorage.js ./src/load_localStorage.js
RUN sed -i "/entry: {/a \\        loader: './src/load_localStorage.js'," webpack.config.js

RUN npm install -g pnpm --force
RUN pnpm install --frozen-lockfile --reporter=silent
RUN pnpm run build

RUN wget $(wget -O- https://raw.githubusercontent.com/Stremio/stremio-shell/master/server-url.txt) && wget -mkEpnp -nH "https://app.strem.io/" "https://app.strem.io/worker.js" "https://app.strem.io/images/stremio.png" "https://app.strem.io/images/empty.png" -P build/shell/ || true


##########################################################################

# Main image
FROM base AS final

ARG VERSION=main
LABEL org.opencontainers.image.source=https://github.com/tsaridas/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web Player and Server"
LABEL org.opencontainers.image.licenses=MIT
LABEL version=${VERSION}

WORKDIR /srv/stremio-server
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./

RUN apk add --no-cache nginx apache2-utils

COPY ./nginx/ /etc/nginx/
COPY ./stremio-web-service-run.sh ./
COPY ./certificate.js ./
RUN chmod +x stremio-web-service-run.sh
COPY ./restart_if_idle.sh ./
RUN chmod +x restart_if_idle.sh
COPY localStorage.json ./

ENV FFMPEG_BIN=
ENV FFPROBE_BIN=
# default https://app.strem.io/shell-v4.4/
ENV WEBUI_LOCATION=
ENV WEBUI_INTERNAL_PORT=
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

# Custom application path for storing server settings, certificates, etc
# You can change this but server.js always saves cache to /root/.stremio-server/
ENV APP_PATH=
ENV NO_CORS=1
ENV CASTING_DISABLED=

# Do not change the above ENVs. 

# Set this to your lan or public ip.
ENV IPADDRESS=
# Set this to your domain name
ENV DOMAIN=
# Set this to the path to your certificate file
ENV CERT_FILE=

# Server url
ENV SERVER_URL=
ENV AUTO_SERVER_URL=0

# Copy ffmpeg
COPY --from=ffmpeg /usr/bin/ffmpeg /usr/bin/ffprobe /usr/bin/
COPY --from=ffmpeg /usr/lib/jellyfin-ffmpeg /usr/lib/

# Add libs
RUN apk add --no-cache libwebp libvorbis x265-libs x264-libs libass opus libgmpxx lame-libs gnutls libvpx libtheora libdrm libbluray zimg libdav1d aom-libs xvidcore fdk-aac libva curl

# Add arch specific libs
RUN if [ "$(uname -m)" = "x86_64" ]; then \
  apk add --no-cache intel-media-driver mesa-va-gallium; \
  fi

# Clear cache
RUN rm -rf /var/cache/apk/* && rm -rf /tmp/*

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080

ENTRYPOINT []

CMD ["./stremio-web-service-run.sh"]
