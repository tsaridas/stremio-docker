# Easy stremio on Docker

## Introduction

[Stremio](https://www.stremio.com/) is a free application which lets you stream your favorite shows and movies.

The Docker images in this repository bundle stremio-server, ffmpeg and web player for you, ready to use in a small Alpine image.

I built this to run Stremio on my Raspberry Pi 5 and couldn't find something that has both player and server but also the official image seemed too big but also lacks the Web Player and doesn't work out of the box if no HTTPS is configured.

## Features

- **All-in-One:** Bundles Stremio server, web player, and ffmpeg in a single container.
- **Simple Networking:** Both the web player and server run on port 8080 behind nginx, so you only need to expose one port.
- **Automatic Server Configuration:** Use `AUTO_SERVER_URL` or `SERVER_URL` to automatically configure the streaming server URL in the web player.
- **HTTPS Out-of-the-Box:** Automatically generates and uses SSL certificates when an `IPADDRESS` is provided.
- **Custom Certificates:** Supports using your own domain and SSL certificates.
- **Hardware Acceleration:** Includes ffmpeg with VAAPI support for Intel and AMD GPUs.
- **Cross-Platform:** Builds are available for `amd64`, `arm/v6`, `arm/v7`, `arm64/v8`, and `ppc64le`.
- **HTTP Basic Auth:** Secure your instance with a username and password.

## Requirements

- A host with Docker installed.

## Installation

### 1. Install Docker

If you haven't installed Docker yet, you can usually install it with:

```bash
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $(whoami)
exit
```
And log in again.

### 2. Run Stremio

**Option A: Using Docker Compose (Recommended)**
```bash
# Clone the repository
git clone https://github.com/tsaridas/stremio-docker.git
cd stremio-docker

# Edit compose.yaml if needed, then run:
docker compose up -d
```
The compose file includes common settings like `NO_CORS: 1` and `AUTO_SERVER_URL: 1`.

**Option B: Using Docker Run**
```bash
docker run -d \
  --name=stremio-docker \
  -e NO_CORS=1 \
  -e AUTO_SERVER_URL=1 \
  -v ./stremio-data:/root/.stremio-server \
  -p 8080:8080/tcp \
  --restart unless-stopped \
  tsaridas/stremio-docker:latest
```

The Web UI will now be available on `http://<YOUR_SERVER_IP>:8080`. The streaming server will be auto-configured for you from the URL of the browser you are using to open it.

> 💡 Your configuration files and cache will be saved in `./stremio-data` on your host machine.

## Configuration Options

These options can be configured by setting environment variables using `-e KEY="VALUE"` in the `docker run` command.

| Env                   | Default | Example                      | Description                                                                                                                                                                                                  |
|-----------------------|---------|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `IPADDRESS`           | -       | `192.168.1.10`               | Set this to a valid IPv4 in order to enable https and generate certificates with stremio domain. If you set this to 0-0-0-0 it will try to automatically get your public ip. Getting the public ip and DNS is not reliable and might need multiple retries. **It will not work for IPv6**                                                                                                                                                                                 |
| `SERVER_URL`          | -       | `http://192.168.1.10:11470/` | Manually sets the streaming server URL. This is useful when you want to force a specific URL.                                                                                                                     |
| `AUTO_SERVER_URL`     | 0       | 1                            | When set to `1`, the streaming server URL is automatically detected from the browser's URL. This is the recommended setting for most users.                                                                    |
| `NO_CORS`             | -       | `1`                          | Set to disable server's cors                                                                                                                                                                                 |
| `CASTING_DISABLED`    | -       | `1`                          | Set to disable casting. You should set this to `1` if you're getting SSDP errors in the logs                                                                                                                 |
| `WEBUI_LOCATION`      | -       | `http://192.168.1.10:8080`   | Sets the redirect page for web player and automatically sets up streaming server for you when one tries to access server at port 11470 or 12470. Default is https://app.strem.io/shell-v4.4/                 |
| `WEBUI_INTERNAL_PORT` | 8080    | `9090`                       | Sets the port inside the docker container for the web player                                                                                                                                                 |
| `FFMPEG_BIN`          | -       | `/usr/bin/`                  | Set for custom ffmpeg bin path                                                                                                                                                                               |
| `FFPROBE_BIN`         | -       | `/usr/bin/`                  | Set for custom ffprobe bin path                                                                                                                                                                              |
| `APP_PATH`            | -       | `/srv/stremio-path/`         | Set for custom path for stremio server. Server will always save cache to /root/.stremio-server though so it's only for its config files.                                                                      |
| `DOMAIN`              | -       | `your.custom.domain`         | Set for custom domain for stremio server. Server will use the specified domain for the web player and streaming server. This should match the certificate and cannot be applied without specifying CERT_FILE |
| `CERT_FILE`           | -       | `certificate.pem`            | Set for custom certificate path. The server and web player will load the specified certificate.                                                                                                              |
| `USERNAME`           | -       | `myusername`            | Set for custom username for http simple authentication.                                                                                                               |
| `PASSWORD`           | -       | `Mypassword`            | Set for custom password for http simple authentication.                                                                                                               |
| `DISABLE_CACHING`     | -       | `1`                          | Disable caching for server if set to 1.                                                                                                                                                                      |                  

There are multiple other options defined but probably best not setting any.

## Usage Scenarios

Here are some common ways to configure and use this Docker image.

### Scenario 1: Simple HTTP (No Certificate)

This is the easiest option and works on your local network without needing a public IP or DNS.

- **Do not set the `IPADDRESS` environment variable.**
- Set `NO_CORS=1` to allow the web player to connect to the server.
- Set `AUTO_SERVER_URL=1` to automatically set the server URL.

```bash
docker run -d \
  --name=stremio-docker \
  -e NO_CORS=1 \
  -e AUTO_SERVER_URL=1 \
  -p 8080:8080 \
  tsaridas/stremio-docker:latest
```
Access Stremio at `http://<YOUR_LAN_IP>:8080`.

### Scenario 2: HTTPS with Public IP

This option automatically gets a certificate for a `*.stremio.rocks` subdomain and points it to your public IP address.

- Set `IPADDRESS=0.0.0.0` to auto-detect your public IP.
- Expose port `8080` and configure port forwarding on your router.

```bash
docker run -d \
  --name=stremio-docker \
  -e IPADDRESS=0.0.0.0 \
  -e AUTO_SERVER_URL=1 \
  -p 8080:8080 \
  tsaridas/stremio-docker:latest
```
The container will generate a certificate and an A record for your public IP. To find the FQDN, look for a `.pem` file in your mounted volume (`~/.stremio-server`).

### Scenario 3: HTTPS with Private IP

This is useful for accessing Stremio via HTTPS on your local network. It generates a certificate for a `*.stremio.rocks` subdomain that resolves to your private IP.

1.  Set `IPADDRESS` to your server's private LAN IP (e.g., `192.168.1.10`).
2.  The container will generate a certificate for a domain like `192-168-1-10.519b6502d940.stremio.rocks`. Find the exact FQDN from the `.pem` filename in your mounted volume.
3.  Add an entry to your hosts file on your client machine to point the FQDN to your server's private IP.

    - **Linux/macOS:** `/etc/hosts`
    - **Windows:** `c:\Windows\System32\Drivers\etc\hosts`

    ```
    192.168.1.10    192-168-1-10.519b6502d940.stremio.rocks
    ```
4.  Run the container:
    ```bash
    docker run -d \
      --name=stremio-docker \
      -e IPADDRESS=192.168.1.10 \
      -e AUTO_SERVER_URL=1 \
      -p 8080:8080 \
      -v ./stremio-data:/root/.stremio-server \
      tsaridas/stremio-docker:latest
    ```
5.  Access Stremio at `https://192-168-1-10.519b6502d940.stremio.rocks:8080`.

### Scenario 4: HTTPS with Your Own Domain and Certificate

If you have your own domain and SSL certificate, you can use them directly.

- Place your certificate file (e.g., `certificate.pem`) in the directory you mount to `/root/.stremio-server`.
- Set the `DOMAIN` and `CERT_FILE` environment variables.

```bash
docker run -d \
  --name=stremio-docker \
  -e DOMAIN=your.custom.domain \
  -e CERT_FILE=certificate.pem \
  -e AUTO_SERVER_URL=1 \
  -v ./stremio-data:/root/.stremio-server \
  -p 8080:8080 \
  tsaridas/stremio-docker:latest
```
The WebPlayer will be available at `https://your.custom.domain:8080`.

## Updating

To update to the latest version, simply run:

```bash
docker stop stremio-docker
docker rm stremio-docker
docker pull tsaridas/stremio-docker:latest
```

And then run your `docker run` or `docker compose up -d` command again.

## Advanced Topics

### FFMPEG

We build our own ffmpeg from the jellyfin repo (version 4.4.1-4), which includes:
- Hardware acceleration support for both Intel and AMD (VAAPI)
- Multiple codec support (H.264, HEVC, VP9, etc.)
- Optimized for streaming workloads

Hardware acceleration is automatically detected. To enable it, you must expose your GPU device to the container.

**Support for Intel/AMD GPU Transcoding (VAAPI)**

If you have a supported Intel or AMD GPU on Linux, you can enable hardware transcoding by passing the `dri` device to the container:

**Docker Compose:**
```yaml
services:
  stremio:
    # ... your other config
    devices:
      - "/dev/dri:/dev/dri"
```

**Docker CLI:**
```bash
docker run -d \
  # ... your other flags
  --device /dev/dri:/dev/dri \
  tsaridas/stremio-docker:latest
```

### Builds

Builds are created for the following architectures:
- `linux/amd64`
- `linux/arm/v6`
- `linux/arm/v7`
- `linux/arm64/v8`
- `linux/ppc64le`

Images are automatically built and tested on pull requests using GitHub Actions.

**Build tags:**
- `latest`: Builds when a new version of the server or Web Player is released.
- `nightly`: Builds daily from the development branch of the web player.
- `vX.X.X`: Specific release versions.

Images are hosted on [Docker Hub](https://hub.docker.com/r/tsaridas/stremio-docker).

### Customizing Local Storage

Stremio's web app stores settings in the browser's local storage. You can pre-configure these settings by editing the `localStorage.json` file and mounting it into the container:

```bash
docker run -d \
  # ... your other flags
  -v /path/to/your/localStorage.json:/srv/stremio-server/build/localStorage.json \
  tsaridas/stremio-docker:latest
```

### Shell

The old Stremio shell files are available at `http(s)://<your_url>/shell/`. These may have issues with some content like YouTube videos.

## Known issues

- Unable to login through Facebook.

## Suggestions

### DNS Caching

Stremio can be heavy on DNS queries. It's recommended to use a local DNS cache like `dnsmasq` to improve performance.

### Idle Restart

The `restart_if_idle.sh` script can restart the Stremio server when it's not in use. You can add this as a healthcheck in your `compose.yaml`:

```yaml
  healthcheck:
    test: ["CMD-SHELL", "./restart_if_idle.sh"]
    interval: 1h
    start_period: 1h
    retries: 1
```

## Security

- **HTTP Basic Authentication:** Supported via `USERNAME` and `PASSWORD` environment variables.
- **HTTPS:** Automatic certificate generation is enabled when `IPADDRESS` is set.
- **CORS:** Can be disabled for local deployments with `NO_CORS=1`.
- **Minimal Images:** All images are built on Alpine with minimal dependencies.

## ToDo

- Build another image with a base that is small and has glibc.
- Automatically add addons passed from environmental variables.
- Add nginx CORS for security.

PRs and Issues are welcome. If you find an issue, please let me know.
