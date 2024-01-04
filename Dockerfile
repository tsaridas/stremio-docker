# Base image
FROM node:14.18.3-alpine AS base

WORKDIR /srv/
RUN apk add --no-cache git

#########################################################################

# Builder image
FROM base AS builder-web


WORKDIR /srv

ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; if [ "$BRANCH" == "release" ];then git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | tail -n1 | cut -d/ -f3); else git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; fi

WORKDIR /srv/stremio-web

#RUN yarn install --no-audit --no-optional --mutex network --no-progress --ignore-scripts
#RUN yarn build
RUN npm ci
RUN npm run build

RUN wget $(wget -O- https://raw.githubusercontent.com/Stremio/stremio-shell/master/server-url.txt)


##########################################################################

# Main image
FROM node:14.18.3-alpine

ARG VERSION=master
LABEL org.opencontainers.image.source=https://github.com/tsaridas/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web Player and Server"
LABEL org.opencontainers.image.licenses=MIT
LABEL version=${VERSION}

WORKDIR /srv/stremio-server
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./
#RUN yarn global add http-server --no-audit --no-optional --mutex network --no-progress --ignore-scripts
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
  --prefix=/usr/lib/jellyfin-ffmpeg --extra-version=Jellyfin --disable-doc --disable-ffplay --disable-shared --disable-libxcb --disable-sdl2 --disable-xlib --enable-lto --enable-gpl --enable-version3 --enable-gmp --enable-gnutls --enable-libdrm --enable-libass --enable-libfreetype --enable-libfribidi --enable-libfontconfig --enable-libbluray --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-libwebp --enable-libvpx --enable-libx264 --enable-libx265  --enable-libzimg --enable-small --enable-nonfree --enable-libxvid --enable-libaom --enable-libfdk_aac --enable-vaapi --enable-hwaccel=h264_vaapi --toolchain=hardened && \
  make -j4 && \
  make install && \
  make distclean && \
  rm -rf "${DIR}"  && \
  apk del --purge .build-dependencies && \
  apk add --no-cache libwebp libvorbis x265-libs x264-libs libass opus libgmpxx lame-libs gnutls libvpx libtheora libdrm libbluray zimg libdav1d aom-libs xvidcore fdk-aac curl libva && \
  rm -rf /var/cache/apk/* && rm -rf /tmp/*

#--------------------------

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080 11470 12470

ENTRYPOINT []

CMD ["./stremio-web-service-run.sh"]
