# Base image
FROM node:18-alpine AS base

WORKDIR /srv/
RUN apk add --no-cache git

#########################################################################

# Builder image
FROM base AS builder-web

WORKDIR /srv
# change to use some other branch
RUN git clone --branch $BRANCH https://github.com/Stremio/stremio-web.git
#RUN git clone https://github.com/Stremio/stremio-web.git


WORKDIR /srv/stremio-web
RUN npm ci --no-audit
RUN npm run build

RUN git clone https://github.com/Stremio/stremio-shell.git
RUN wget $(cat stremio-shell/server-url.txt)


##########################################################################
LABEL org.opencontainers.image.source=https://github.com/tsaridas/stremio-docker
LABEL org.opencontainers.image.description="Stremio Web and Server"
LABEL org.opencontainers.image.licenses=MIT
LABEL version="1.0.0"

# Main image
FROM node:18-alpine

WORKDIR /srv/stremio-server
COPY ./stremio-web-service-run.sh ./
COPY ./extract_certificate.js ./
RUN chmod +x stremio-web-service-run.sh
COPY --from=builder-web /srv/stremio-web/build ./build
COPY --from=builder-web /srv/stremio-web/server.js ./
RUN npm install -g http-server

ENV FFMPEG_BIN=
ENV FFPROBE_BIN=

# Custom application path for storing server settings, certificates, etc
# You can change this but server.js always saves cache to /root/.stremio-server/
ENV APP_PATH=
ENV NO_CORS=
ENV CASTING_DISABLED=
# Set this to your lan or public ip.
ENV IPADDRESS=

RUN apk add --no-cache ffmpeg openssl curl

VOLUME ["/root/.stremio-server"]

# Expose default ports
EXPOSE 8080 11470 12470

CMD ["./stremio-web-service-run.sh"]
