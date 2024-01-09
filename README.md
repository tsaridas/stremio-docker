# Easy stremio on Docker

## Introduction

Stremio is a free application which lets you stream your favorite shows and movies. 

The Docker images in this repository have the Stremio server with ffmpeg and web player set up for you, ready to use in a small Alpine image.

My motivation for doing this is having it running on my RPi5 and couldn't find something that has both player and server but also the official image seemed too big.

## Features
Idea here is to have both Stremio web player and server run on the same container and if IPADDRESS env variable is setup generate a certificate and use it for both.

The Web player runs on port 8080 and server runs on both ports 11470 ( plain http ) and 12470 (https).

-----

1) If you exposed the ports 8080, 11470 for HTTP just point your streaming server (http://{LAN IP}:8080/) in settings to the lan ip address and set the server to be http://{LAN IP}:11470/ and enjoy. Make sure you set NO_CORS=1 with this option.

This is the easy option since there is **no need to setup dns or have an external ip. Do not set the IPADDRESS env variable** if you just want HTTP. You do not need to expose port 12470 with this option but you will only be able to use the webplayer with HTTP.

-----

2) If you set your public IP address for the `IPADDRESS` environment variable, then the Stremio server should automatically set the certificate to the wildcard `*.519b6502d940.stremio.rocks` and should generate an A record for your public IP address. You should then expose ports 8080 and 12470 to your servers and then setup port forwarding to your router to point these two ports to your server. Once this is done you can point the WebPlayer to your streaming server on port 12047.

To find the FQDN that the certificate is pointing to, look at the folder you mounted for a file with a `.pem` extension. The filename is the domain you need to add your your hosts in case of local ip address.

-----

3) If you set IPADDRESS to your private ip address then the server should still set the certificate to the wildcard *.519b6502d940.stremio.rocks and have the subdomain set as 192-168-1-10 assuming your private is 192.168.1.10. Full domain should look like 192-168-1-10.519b6502d940.stremio.rocks. You can then setup your /etc/hosts in Linux or c:\Windows\System32\Drivers\etc\hosts in windows to point that host to your lan address like :

```bash
192.168.1.10    192-168-1-10.519b6502d940.stremio.rocks # this is an example. set your own ip and fqnd here.
```

Then you can point your browser to https://192-168-1-10.519b6502d940.stremio.rocks:8080 and setup Streaming server to https://192-168-1-10.519b6502d940.stremio.rocks:12470 .


To find the FQDN that the certificate is pointing to, look at the folder you mounted for a file with a `.pem` extension. The filename is the domain you need to add your your hosts in case of local ip address.

-----

## Thoughts

You don't need to have both Stremio Server and Web Player running. One could use the Stremio web player ([https://app.strem.io/#/](https://app.strem.io/#/)). Stremio's web player should also work for options 2 and 3 above because the web player requires that the server's URL is in HTTPS.

You can also use the native clients for options 2-3 since they use https but those clients also run a server so there is no point doing this.

## Requirements

* A host with Docker installed.

## Installation

### 1. Install Docker

If you haven't installed Docker yet, install it by running:

```bash
$ curl -sSL https://get.docker.com | sh
$ sudo usermod -aG docker $(whoami)
$ exit
```

And log in again.

### 2. Run Stremio Web + Server

To automatically run stremio web player and server in http, simply run:

<pre>
$ docker run -d \
  --name=stremio-docker \
  -e NO_CORS=1 \
  -v ~/.stremio-server:/root/.stremio-server \
  -p 8080:8080/tcp \
  -p 11470:11470/tcp \
  --restart unless-stopped \
  tsaridas/stremio-docker:latest
</pre>


The Web UI will now be available on `http://`YOUR_SERVER_IP`:8080`. Set streaming server to `http://`YOUR_SERVER_IP`:11470` add your add ons and start watching your favourite movie.

> 💡 Your configuration files and cache will be saved in `~/.stremio-server`

## Options

These options can be configured by setting environment variables using `-e KEY="VALUE"` in the `docker run` command.

| Env | Default | Example | Description |
| - | - | - | - |
| `IPADDRESS` | - | `192.168.1.10` | Set this to enable https |
| `NO_CORS` | - | `1` | Set to disable server's cors |
| `CASTING_DISABLED` | - | `1` | Set to disable casting |
| `WEBUI_LOCATION` | - | `http://192.168.1.10:8080` | Sets the redirect page for web player and automatically sets up streaming server for you when one tries to access server at port 11470 or 12470  |
| `FFMPEG_BIN` | - | `/usr/bin/` | Set for custom ffmpeg bin path |
| `FFPROBE_BIN` | - | `/usr/bin/` | Set for custom ffprobe bin path |
| `APP_PATH` | - | `/srv/stremio-path/` | Set for custom path for stremio server. Server will always save cache to /root/.stremio-server though so its only for its config files. |


There are multiple other options defined but probably best not settings any.

## Updating

To update to the latest version, simply run:

```bash
docker stop stremio-docker
docker rm stremio-docker
docker pull tsaridas/stremio-docker:latest
```

And then run the `docker run -d \ ...` command above again.

## FFMPEG

We build our own ffmpeg from jellyfin repo with version 4.4.1-4 This plays well and its what stremio officially supports. 

### FFMPEG add configure options
You could build your own image with extra ffmpeg configure options. Your new option will probably require that you have the -dev libraries installed for alpine. 

If you cannot find the -dev libraries in the alpine repo then you might need to compile them as well. 

```bash
  xvidcore-dev \
  fdk-aac-dev \
  libva-dev \
  git \
  x264 `ADD-DEV-PACKAGE-HERE` && \
```

Add your extra options at the end line before the && :

```bash
--prefix=/usr/lib/jellyfin-ffmpeg --extra-version=Jellyfin --disable-doc --disable-ffplay --disable-shared --disable-libxcb --disable-sdl2 --disable-xlib --enable-lto --enable-gpl --enable-version3 --enable-gmp --enable-gnutls --enable-libdrm --enable-libass --enable-libfreetype --enable-libfribidi --enable-libfontconfig --enable-libbluray --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-libwebp --enable-libvpx --enable-libx264 --enable-libx265  --enable-libzimg --enable-small --enable-nonfree --enable-libxvid --enable-libaom --enable-libfdk_aac --enable-vaapi --enable-hwaccel=h264_vaapi --toolchain=hardened `ADD-OPTION-HERE` &&
```

You also add the dev libraries to the above line from configure where you see lots of -dev packages installed. Those packages are purged later so you will also need to install the normal library (not the headers) in the end.

```bash
apk add --no-cache libwebp libvorbis x265-libs x264-libs libass opus libgmpxx lame-libs gnutls libvpx libtheora libdrm libbluray zimg libdav1d aom-libs xvidcore fdk-aac curl libva `ADD-NON-DEV-PACKAGE-HERE` && \
```

The lines shown above might have changed so just try to use common sense on where to add your package. If you want hardware acceleration you might need to compile it with the driver for your hardware.

## Builds

Builds are setup to make images for the below archs :

* linux/arm/v6
* linux/amd64
* linux/arm64/v8
* linux/arm/v7

I can add more build archs if you require them and you can ask but I doubt anybody ever will need to install these containers in anything else.

### Build tags

* latest -> Builds automatically when new version of server or WebPlayer is released. Builds WebPlayer only from release tags.
* nightly -> Builds automatically daily from development branch of web player and gets latest version of server.
* release version (example v1.0.0) -> to have old releases available in case there is something wrong with new release.

Images saved in [Docker Hub](https://hub.docker.com/r/tsaridas/stremio-docker)

### Build your own

You can build your own image by running the below command. By default it will build from development branch of web player and latest version of the server. If you want to build from latest release of web please you can add --build-arg BRANCH=release or the branch that you want.

```bash
docker build -t stremio:myserver .
```

## Common Use Cases

* [Using HTTP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-HTTP)
* [Using HTTPS Local IP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-with-Private-IP)
* [Using HTTPS Public IP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-with-Public-IP)

## Last words

I don't intend to spend much time on this and tried to automate as much as I had time to.
PRs and Issues are welcome. 
You can also fork and do as you like with the code but if you find some issue please do let me know.
