# Easy stremio on Docker

## Features
Idea here is to have both Stremio web player and server run on the same container and if IPADDRESS env variable is setup generate a certificate and use it for both.

The Web player runs on port 8080 and server runs on both ports 11470 ( plain http ) and 12470 (https).

1) If you exposed the ports 8080, 11470 for http just point your streaming server (http://{LAN IP}:8080/) in settings to the lan ip address and set the server to be http://{LAN IP}:11470/ and enjoy. Make sure you set NO_CORS=1 with this option.

This is the easy option since there is no need to setup and dns or have an external ip.

-----

2) If you set your public ip address for the IPADDRESS env variable then streamio server should automatically set the certificate to the wild card *.519b6502d940.stremio.rocks and should generate an A record for your public ip address. You should then expose ports 8080 and 12470 to your servers and then setup port forwarding to your router to point these two ports to your server. Once this is done you can point the WebPlayer to your streaming server on port 12047.

In order to find the fqdn that the certificate is pointing to you can look at the folder you mounted for a file that has
.pem extension. The filename is the domain you need to add your your hosts in case of local ip address.

-----

3) If you set your private ip address to IPADDRESS then the server should still set the certificate to the wildcard *.519b6502d940.stremio.rocks and have the subdomain set as 192-168-1-10 assuming your private is 192.168.1.10. Full domain should look like 192-168-1-10.519b6502d940.stremio.rocks. You can then setup your /etc/hosts in Linux or c:\Windows\System32\Drivers\etc\hosts in windows to point that host to your lan address like :

```bash
192.168.1.10    192-168-1-10.519b6502d940.stremio.rocks # this is an example. set your own ip and fqnd here.
```

Then you can point your browser to https://192-168-1-10.519b6502d940.stremio.rocks:8080 and setup Streaming server to https://192-168-1-10.519b6502d940.stremio.rocks:12470 .


In order to find the fqdn that the certificate is pointing to you can look at the folder you mounted for a file that has .pem extension. The filename is the domain you need to add your your hosts in case of local ip address.


## Thoughts

You don't need to have both Stremio Server and Web Player running. One could disable CORS and use the stremio web player (https://app.strem.io/#/). Stremio's web player should also work for option 2 and 3 above because the webplayer requires that the server's url is in HTTPS.

You can also use the native clients for options 2-3 since they use https. Its probably the best since I imagine your docker servers might not be that powerful.


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

To automatically install & run stremio, simply run:

<pre>
$ docker run -d \
  --name=stremio-docker \
  -e NO_CORS=1 \
  -e IPADDRESS=`YOURIPADDRESS` \
  -v ~/.stremio-server:/root/.stremio-server \
  -p 8080:8080/tcp \
  -p 11470:11470/tcp \
  -p 12470:12470/tcp \
  --restart unless-stopped \
  tsaridas/stremio-docker:latest
</pre>

> 💡 Replace `YOUR_SERVER_IP` with your WAN IP or LAN IP
> 
The Web UI will now be available on `http://0.0.0.0:8080`.

> 💡 Your configuration files will be saved in `~/.stremio-server`

## Options

These options can be configured by setting environment variables using `-e KEY="VALUE"` in the `docker run` command.

| Env | Default | Example | Description |
| - | - | - | - |
| `FFMPEG_BIN` | - | `/usr/bin/` | Set for custom ffmpeg bin path |
| `FFPROBE_BIN` | - | `/usr/bin/` | Set for custom ffprobe bin path |
| `APP_PATH` | - | `/srv/stremio-path/` | Set for custom path for stremio server. Server will always save cache to /root/.stremio-server though so its only for its config files. |
| `NO_CORS` | - | `1` | Set to disable server's cors |
| `CASTING_DISABLED` | - | `1` | Set to disable casting |
| `IPADDRESS` | - | `192.168.1.10` | Set this to enable https |

THere are multiple other options defined but probably best not settings any.

## Updating

To update to the latest version, simply run:

```bash
docker stop stremio-docker
docker rm stremio-docker
docker pull tsaridas/stremio-docker:latest
```

And then run the `docker run -d \ ...` command above again.

## Builds

Builds are setup to make images for :

linux/arm/v6,linux/amd64,linux/arm64/v8,linux/arm/v7

there are two builds. 

latest -> ones I tested all three options I described and release
nightly -> builds daily from development branches
testing -> only builds for arm64

## Common Use Cases - ToDo

* [Using HTTP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-HTTP)
* [Using HTTPS Local IP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-with-Private-IP)
* [Using HTTPS Public IP](https://github.com/tsaridas/stremio-docker/wiki/Using-Stremio-Server-with-Public-IP)
