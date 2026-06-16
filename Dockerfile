# syntax=docker/dockerfile:1
# Base: Alpine 3.23 across all target architectures; install Node like docker-node.
FROM alpine:3.23 AS base

ENV NODE_VERSION=22.22.3

RUN --mount=type=cache,id=apk-base,target=/var/cache/apk \
  apk update && apk upgrade \
  && apk add --no-cache libstdc++ \
  && apk add --no-cache --virtual .build-deps curl \
  && ARCH= OPENSSL_ARCH='linux*' && alpineArch="$(apk --print-arch)" \
  && case "${alpineArch##*-}" in \
    x86_64) ARCH='x64' CHECKSUM="fc04ab27123cb34d2bca3416493e86ced2f81e1ab9b51e532721ed27a1ef677d" OPENSSL_ARCH=linux-x86_64;; \
    x86) OPENSSL_ARCH=linux-elf;; \
    aarch64) OPENSSL_ARCH=linux-aarch64;; \
    arm*) OPENSSL_ARCH=linux-armv4;; \
    ppc64le) OPENSSL_ARCH=linux-ppc64le;; \
    s390x) OPENSSL_ARCH=linux-s390x;; \
    *) ;; \
  esac \
  && if [ -n "${CHECKSUM}" ]; then \
    set -eu; \
    curl -fsSLO --compressed "https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz"; \
    echo "$CHECKSUM  node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" | sha256sum -c - \
    && tar -xJf "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && ln -sf /usr/local/bin/node /usr/local/bin/nodejs; \
  else \
    echo "Building Node from source" \
    && apk add --no-cache --virtual .build-deps-full \
      binutils-gold g++ gcc gnupg libgcc linux-headers make python3 py-setuptools \
    && export GNUPGHOME="$(mktemp -d)" \
    && for key in \
      5BE8A3F6C8A5C01D106C0AD820B1A390B168D356 \
      DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
      CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
      8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
      890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
      C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
      108F52B48DB57BB0CC439B2997B01419BD92F80A \
      A363A499291CBBC940DD62E41F10027AF002F8B0 \
    ; do \
      { gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" && gpg --batch --fingerprint "$key"; } || \
      { gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" && gpg --batch --fingerprint "$key"; } ; \
    done \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xf "node-v$NODE_VERSION.tar.xz" \
    && cd "node-v$NODE_VERSION" \
    && ./configure \
    && make -j"$(getconf _NPROCESSORS_ONLN)" V= \
    && make install \
    && apk del .build-deps-full \
    && cd .. \
    && rm -rf "node-v$NODE_VERSION" "node-v$NODE_VERSION.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt; \
  fi \
  && rm -f "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" \
  && find /usr/local/include/node/openssl/archs -mindepth 1 -maxdepth 1 ! -name "$OPENSSL_ARCH" -exec rm -rf {} + \
  && apk del .build-deps \
  && node --version \
  && npm --version \
  && rm -rf /tmp/*

FROM base AS ffmpeg

# We build our own ffmpeg since 4.X is the only one supported
ENV BIN="/usr/bin"
COPY ./patches/ffmpeg-mathops-binutils241.patch /tmp/ffmpeg-mathops-binutils241.patch
COPY ./patches/ffmpeg-mlpdsp-armv5te-binutils243.patch /tmp/ffmpeg-mlpdsp-armv5te-binutils243.patch
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
  awk '/^diff --git /,0' /tmp/ffmpeg-mathops-binutils241.patch | patch -p1 && \
  awk '/^diff --git /,0' /tmp/ffmpeg-mlpdsp-armv5te-binutils243.patch | patch -p1 && \
  PATH="$BIN:$PATH" && \
  ./configure --help && \
  EXTRA_FFMPEG_FLAGS="" && \
  case "$(uname -m)" in armv6l|armv7l|armhf) EXTRA_FFMPEG_FLAGS="--disable-vaapi --disable-hwaccel=h264_vaapi --disable-hwaccel=hevc_vaapi";; esac && \
  ./configure --bindir="$BIN" --disable-debug \
  --extra-cflags="-Wno-error -Wno-error=deprecated-declarations -Wno-error=discarded-qualifiers" \
  --prefix=/usr/lib/jellyfin-ffmpeg --extra-version=Jellyfin --disable-doc --disable-ffplay --disable-shared --disable-libxcb --disable-sdl2 --disable-xlib --enable-lto --enable-gpl --enable-version3 --enable-gmp --enable-gnutls --enable-libdrm --enable-libass --enable-libfreetype --enable-libfribidi --enable-libfontconfig --enable-libbluray --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-libwebp --enable-libvpx --enable-libx264 --enable-libx265  --enable-libzimg --enable-small --enable-nonfree --enable-libxvid --enable-libaom --enable-libfdk_aac --enable-vaapi --enable-hwaccel=h264_vaapi --enable-hwaccel=hevc_vaapi --toolchain=hardened $EXTRA_FFMPEG_FLAGS && \
  make -j"$(nproc)" && \
  make install && \
  find /usr/lib/jellyfin-ffmpeg -name '*.a' -delete && rm -rf /usr/lib/jellyfin-ffmpeg/include && \
  make distclean && \
  rm -rf "${DIR}"  && \
  apk del --purge .build-dependencies

#########################################################################

# Builder image
FROM base AS builder-web

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /srv
RUN apk add --no-cache git wget

ARG BRANCH=development
RUN REPO="https://github.com/Stremio/stremio-web.git"; if [ "$BRANCH" == "release" ];then git clone "$REPO" --depth 1 --branch $(git ls-remote --tags --refs $REPO | awk '{print $2}' | sort -V | tail -n1 | cut -d/ -f3); else git clone --depth 1 --branch "$BRANCH" https://github.com/Stremio/stremio-web.git; fi

WORKDIR /srv/stremio-web

RUN sed -i "s#const COMMIT_HASH = execSync('git rev-parse HEAD').toString().trim();#const GIT_COMMIT = execSync('git rev-parse HEAD').toString().trim();\\nconst BUILD_LABEL = process.env.COMMIT_HASH ? String(process.env.COMMIT_HASH).replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/-+/g, '-').replace(/^-+|-+\$/g, '') : '';\\nconst COMMIT_HASH = BUILD_LABEL ? BUILD_LABEL + '-' + GIT_COMMIT : GIT_COMMIT;\\nprocess.env.COMMIT_HASH = COMMIT_HASH;#" webpack.config.js

COPY ./load_localStorage.js ./src/load_localStorage.js
RUN sed -i "/entry: {/a \\        loader: './src/load_localStorage.js'," webpack.config.js

RUN npm install -g pnpm@11 --force
RUN pnpm install --frozen-lockfile --reporter=silent
ARG COMMIT_HASH=
RUN COMMIT_HASH=$COMMIT_HASH pnpm run build

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
RUN apk add --no-cache libwebp libwebpmux libvorbis x265-libs x264-libs libass opus libgmpxx lame-libs gnutls libvpx libtheora libdrm libbluray zimg libdav1d aom-libs xvidcore fdk-aac libva

# Add arch specific libs
RUN if [ "$(uname -m)" = "x86_64" ]; then \
  apk add --no-cache intel-media-driver mesa-va-gallium; \
  fi

# Base apk upgrade may be a days-old Docker layer cache; refresh once more before image shrink.
RUN --mount=type=cache,id=apk-base,target=/var/cache/apk \
  apk update && apk upgrade

# Clean up package managers and docs.
RUN rm -rf /opt/yarn-v* /usr/local/lib/node_modules \
  && rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
  && rm -rf /usr/share/man/* /usr/share/doc/* \
  && rm -rf /var/cache/apk/* /tmp/*

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080

ENTRYPOINT []

CMD ["./stremio-web-service-run.sh"]
