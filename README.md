# Easy stremio on Docker
## Features
Idea here is to have both Stremio web player and server run on the same container and if IPADDRESS env variable is setup generate a certificate and use it for both.

Web player run on port 8080 and server runs on both ports 11470 ( plan http ) and 12470 (https).

1) If you exposed the ports 8080, 11470 for http just point your streaming server in settings to the lan ip address and set the server to be http://{LAN IP}:11470/ and enjoy.

2) If you set your public ip address for the IPADDRESS env variable then streamio server should set the certificate to the wild card *.519b6502d940.stremio.rocks and should generate an A record for your ip address. You should then expose ports 8080 and 12470 to your servers and then setup port forwarding to your router to point these two ports to your server.


3) If you set your private ip address to IPADDRESS then the server should still set the certificate to the wildcard *.519b6502d940.stremio.rocks and have the subdomain set as 192-168-1-10 assuming your private is is 192.168.1.10. Full domain should be 192-168-1-10.519b6502d940.stremio.rocks. You can then setup your /etc/hosts in Linux or c:\Windows\System32\Drivers\etc\hosts in windows to point that host to your lan address like :

```bash
192.168.1.10    192-168-1-10.519b6502d940.stremio.rocks
```

Then you can point your browser to https://192-168-1-10.519b6502d940.stremio.rocks:8080 and setup Streaming server to https://192-168-1-10.519b6502d940.stremio.rocks:12470 .

You can change the address as you can imagine.


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
  --name=stremio \
  -e NO_CORS=1
  -e IPADDRESS=`YOURIPADDRESS`
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

## Updating

To update to the latest version, simply run:

```bash
docker stop stremio-docker
docker rm stremio-docker
docker pull tsaridas/stremio-docker:latest
```

And then run the `docker run -d \ ...` command above again.

## Common Use Cases

* [Using HTTP](https://github.com/tsaridas/tsaridas/wiki/Using-Stremio-Server-HTTP)
* [Using HTTPS Local IP](https://github.com/tsaridas/tsaridas/wiki/Using-Stremio-Server-with-Private-IP)
* [Using HTTPS Public IP](https://github.com/tsaridas/tsaridas/wiki/Using-Stremio-Server-with-Public-IP)
