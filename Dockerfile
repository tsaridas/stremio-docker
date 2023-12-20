# Base image
FROM node:18-alpine AS base

WORKDIR /srv/
RUN apk add --no-cache git curl

#########################################################################

# Builder image
FROM base AS builder-web


WORKDIR /srv

ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; if [ "$BRANCH" == "release" ];then git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | tail -n1 | cut -d/ -f3); else git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; fi

WORKDIR /srv/stremio-web
RUN npm ci --no-audit --no-fund
RUN npm run build

RUN wget $(wget -O- https://raw.githubusercontent.com/Stremio/stremio-shell/master/server-url.txt)


##########################################################################

# Main image
FROM node:18-alpine

ARG VERSION=master
LABEL org.opencontainers.image.source=https://github.com/tsaridas/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web Player and Server"
LABEL org.opencontainers.image.licenses=MIT
LABEL version=${VERSION}

WORKDIR /srv/stremio-server
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./
RUN npm install -g http-server

COPY ./stremio-web-service-run.sh ./
COPY ./extract_certificate.js ./
RUN chmod +x stremio-web-service-run.sh

ENV FFMPEG_BIN=
ENV FFPROBE_BIN=
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
ENV NODE_ENV=
ENV HTTPS_CERT_ENDPOINT=
ENV DISABLE_CACHING=
# disable or enable
ENV READABLE_STREAM=
# remote or local
ENV HLSV2_REMOTE=

# Custom application path for storing server settings, certificates, etc
# You can change this but server.js always saves cache to /root/.stremio-server/
ENV APP_PATH=
ENV NO_CORS=
ENV CASTING_DISABLED=

# Do not change the above ENVs. 

# Set this to your lan or public ip.
ENV IPADDRESS=


#--------------------------
# We build our own ffmpeg since after checking 4.X has way better performance than later versions.
ENV SOFTWARE_VERSION="4.1"
ENV SOFTWARE_VERSION_URL="http://ffmpeg.org/releases/ffmpeg-${SOFTWARE_VERSION}.tar.bz2"
ENV BIN="/usr/bin"

RUN cd && \
  apk update && \
  apk upgrade && \
  apk add --no-cache --virtual \ 
  .build-dependencies \ 
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
  bzip2 \ 
  coreutils \ 
  gnutls \ 
  nasm \ 
  tar \ 
  x264 && \
  DIR=$(mktemp -d) && \
  cd "${DIR}" && \
  wget "${SOFTWARE_VERSION_URL}" && \
  tar xjvf "ffmpeg-${SOFTWARE_VERSION}.tar.bz2" && \
  cd ffmpeg* && \
  PATH="$BIN:$PATH" && \
  ./configure --help && \
  ./configure --bindir="$BIN" --disable-debug \
  --disable-doc \ 
  --disable-ffplay \ 
  --enable-avresample \ 
  --enable-gnutls \
  --enable-gpl \ 
  --enable-libass \ 
  --enable-libfreetype \ 
  --enable-libmp3lame \ 
  --enable-libopus \ 
  --enable-librtmp \ 
  --enable-libtheora \ 
  --enable-libvorbis \ 
  --enable-libvpx \ 
  --enable-libwebp \ 
  --enable-libx264 \ 
  --enable-libx265 \ 
  --enable-nonfree \ 
  --enable-postproc \ 
  --enable-small \ 
  --enable-version3 && \
  make -j4 && \
  make install && \
  make distclean && \
  rm -rf "${DIR}"  && \
  apk del --purge .build-dependencies && \
  apk add --no-cache libxcb libass lame-libs libwebp libvorbis librtmp libtheora opus libvpx libwebpmux x265-libs x264-libs curl && \
  rm -rf /var/cache/apk/* && rm -rf /tmp/*

#--------------------------

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080 11470 12470

CMD ["./stremio-web-service-run.sh"]
