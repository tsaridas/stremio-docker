# Base image
FROM node:16-alpine AS base

WORKDIR /srv/
RUN apk add --no-cache git

#########################################################################

# Builder image
FROM base AS builder-web

WORKDIR /srv/
RUN git clone --branch refactor/video-player https://github.com/Stremio/stremio-web.git


WORKDIR /srv/stremio-web
RUN npm install
# RUN npm audit fix
RUN npm audit fix --force
RUN npm run build

RUN git clone https://github.com/Stremio/stremio-shell.git
RUN wget $(cat stremio-shell/server-url.txt)


##########################################################################
LABEL com.stremio.vendor="Smart Code Ltd."
LABEL version=${VERSION}
LABEL description="Stremio's streaming Server"

# Main image
FROM node:16-alpine

WORKDIR /srv/stremio
COPY ./stremio-web-service-run.sh ./
COPY ./extract_certificate.js ./
RUN chmod +x *.sh
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./
RUN npm install -g http-server

# full path to the ffmpeg binary
ENV FFMPEG_BIN=
# full path to the ffprobe binary
ENV FFPROBE_BIN=
# Custom application path for storing server settings, certificates, etc
ENV APP_PATH=
ENV NO_CORS=1
ENV CASTING_DISABLED=
ENV IPADDRESS=

RUN apk add --no-cache ffmpeg openssl curl

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080 11470 12470

CMD ["./stremio-web-service-run.sh"]
