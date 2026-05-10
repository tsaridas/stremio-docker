# Stremio Docker — NVIDIA GPU (NVENC/NVDEC)

Complete guide to building, deploying, maintaining, and troubleshooting the Stremio image with
NVIDIA GPU acceleration. Includes detailed documentation of every issue encountered,
applied solutions, and approaches that **did not work** — so the same mistakes are not repeated.

GPU stacks use **`compose-nvidia.yaml`** (`Dockerfile.nvidia`, NVIDIA runtime, GPU reservations). The default **`compose.yaml`** in this repo targets the standard CPU image (`tsaridas/stremio-docker:latest`) and is unrelated to NVENC; always pass `-f compose-nvidia.yaml` for the commands in this guide.

---

## Table of contents

1. [Prerequisites on the host](#prerequisites-on-the-host)
2. [Architecture](#architecture)
3. [Build](#build)
4. [Deploy](#deploy)
5. [Resource limits](#resource-limits)
6. [GPU / transcoding configuration](#gpu--transcoding-configuration)
7. [Runtime patches (server.js)](#runtime-patches-serverjs)
8. [Rebuild / update](#rebuild--update)
9. [What did NOT work (lessons learned)](#what-did-not-work-lessons-learned)
10. [Applied fixes (summary)](#applied-fixes-summary)
11. [Technical reference](#technical-reference)
12. [CI and registry tags](#ci-and-registry-tags)
13. [Current environment](#current-environment)

---

## Prerequisites on the host

- NVIDIA driver >= 535 (`nvidia-smi` must work)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed
- Docker with the `nvidia` runtime configured (`docker info | grep nvidia`)

```bash
# Verify prerequisites
nvidia-smi
docker info | grep -i "runtimes.*nvidia"
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  compose-nvidia.yaml                                │
│  ├── build: Dockerfile.nvidia                       │
│  ├── runtime: nvidia                                │
│  └── deploy.resources (CPU/RAM/GPU limits)          │
├─────────────────────────────────────────────────────┤
│  Dockerfile.nvidia (multi-stage)                    │
│  ├── Stage 1: ffmpeg     (cuda:12.2.2-devel)        │
│  │   ├── nv-codec-headers (ffnvcodec n12.0.16.1)   │
│  │   └── jellyfin-ffmpeg v4.4.1-4                   │
│  │       └── NVENC + NVDEC + CUVID + VAAPI          │
│  ├── Stage 2: builder-web (node:20-alpine)          │
│  │   └── stremio-web (pnpm build)                   │
│  └── Stage 3: final     (cuda:12.2.2-runtime)       │
│      ├── Node.js 20 + nginx + ffmpeg binaries       │
│      └── stremio-web-service-run.sh (entrypoint)    │
└─────────────────────────────────────────────────────┘
```

### Transcoding pipeline (after patches)

```
Video file (e.g. HEVC 10-bit)
    │
    ▼
[GPU] CUVID decode (hevc_cuvid / h264_cuvid / av1_cuvid)
    │
    ▼ auto-download to system memory (ffmpeg does this automatically
    │ when there is no -hwaccel_output_format cuda)
    │
    ▼
[CPU] scale (lanczos) + format conversion (10-bit p010 → 8-bit yuv420p)
    │
    ▼ auto-upload to GPU (h264_nvenc accepts system-memory frames)
    │
    ▼
[GPU] NVENC encode (h264_nvenc, preset p1, tune ull)
    │
    ▼
HLS output → player
```

## Build

```bash
# Default build
docker compose -f compose-nvidia.yaml build

# Build without cache (after changing base images)
docker compose -f compose-nvidia.yaml build --no-cache

# Build with a specific stremio-web branch
docker compose -f compose-nvidia.yaml build --build-arg BRANCH=release
```

**Build time:** ~5–10 min (ffmpeg with CUDA is the slowest part).

### CI and registry tags

GitHub Actions builds **`Dockerfile.nvidia`** in a separate job **`build-nvidia`** that runs **in parallel** with the main multi-arch matrix (`linux/amd64`, `arm/v6`, `arm/v7`, `arm64`, `ppc64le`). The NVIDIA job only targets **`linux/amd64`** for now: the CUDA base is multi-arch-capable, but the Ubuntu package pins in `Dockerfile.nvidia` (e.g. `libx264-163`) are amd64-specific. When those stages are parameterized per `TARGETARCH`, you can extend the NVIDIA matrix the same way as the default image.

**Naming (same repository, suffix tags — recommended):**

| Registry / workflow | Default image tag | NVIDIA image tag |
|---------------------|-------------------|------------------|
| Docker Hub nightly (schedule) | `tsaridas/stremio-docker:nightly` | **`tsaridas/stremio-docker:nightly-nvidia`** |
| Docker Hub release (when `check_release` publishes) | `…:latest`, `…:vX.Y.Z` | **`…:latest-nvidia`**, **`…:vX.Y.Z-nvidia`** |
| GHCR (PR builds) | `ghcr.io/<org>/<repo>:<branch>` | **`ghcr.io/<org>/<repo>:<branch>-nvidia`** |

**`latest-nvidia` vs `nightly-nvidia`:** Same rule as the CPU image: **`latest-nvidia` moves only when a Docker Hub release runs** (stable). **`nightly-nvidia`** is rebuilt every night from `development` and is the right tag to pull for “newest CI build” without waiting for a versioned release.

Rationale: one image name (`stremio-docker`), discoverable **`-nvidia`** suffix, no second Docker Hub repository to maintain, and manifest lists can grow to more architectures later without renaming.

Local compose uses `image: stremio-docker:nvidia` when you build yourself; to run a prebuilt hub image instead, use **`nightly-nvidia`** for bleeding edge or **`latest-nvidia`** once you want the last released NVIDIA variant (and remove or keep the `build:` block as you prefer).

### Resolved build issues

| Error | Cause | Fix |
|------|-------|-----|
| `nvcc fatal: Unsupported gpu architecture 'compute_30'` | CUDA 12.x dropped compute_30 | `--nvccflags="-gencode arch=compute_52,code=sm_52 -O2"` (Maxwell+) |
| `cuvid requested, but not all dependencies are satisfied: ffnvcodec` | ffmpeg needs `nv-codec-headers` to compile NVENC/NVDEC | Manual install of `nv-codec-headers` branch `n12.0.16.1` from GitHub |
| `getpwnam("nginx") failed` | Ubuntu does not create the `nginx` user (Alpine does) | `useradd -r -s /bin/false nginx` in the Dockerfile |
| `libwebpmux.so.3: cannot open shared object file` | Ubuntu 22.04 splits `libwebpmux3` from `libwebp7` | Added `libwebpmux3` explicitly to packages |
| `Bad substitution` in entrypoint | `Dockerfile` uses `/bin/sh` which is `dash` on Ubuntu, not `bash` | Replaced `${var: -1}` (bash-only) with `case "$var" in ... esac` (POSIX) |

## Deploy

```bash
# Start the container
docker compose -f compose-nvidia.yaml up -d

# View logs
docker logs -f stremio-docker-stremio-1

# Restart (re-applies server.js patches automatically)
docker compose -f compose-nvidia.yaml restart

# Stop
docker compose -f compose-nvidia.yaml down
```

**Access:** `https://stremio.media.lan/` (host port 8085 → container 8080; replace with your own DNS or IP)

## Resource limits

```yaml
deploy:
  resources:
    limits:
      cpus: "1.5"        # 1.5 cores (NVENC offload → CPU only does audio/decode)
      memory: 1536M       # 1.5GB (measured peak: 1.35GB during transcode)
    reservations:
      memory: 256M        # Guaranteed minimum (idle ~200MB: node + nginx)
      devices:
        - driver: nvidia
          count: 1         # 1 GPU (GTX 1070 8GB)
          capabilities: [gpu, video, compute]
```

### Measured usage during active transcoding

| Process | CPU | RAM (RSS) | GPU |
|----------|-----|-----------|-----|
| ffmpeg audio (aac) | ~30% | ~1.15 GB | — |
| ffmpeg video (NVENC) | ~60% | ~234 MB | 15%, 868 MiB VRAM |
| node server.js | ~40% | ~185 MB | — |
| nginx | ~1% | ~28 MB | — |
| **Total** | **~138%** | **~1.35 GB** | **15% util** |

> **Why 1.5 cores is enough:** With NVENC, video encoding (the heaviest part) runs on the GPU.
> The CPU only does audio decode, AAC encode, and some scaling work.
> Before (libx264 software), the CPU sat at 100%+ from encoding alone.

To adjust limits, edit `compose-nvidia.yaml` and run:
```bash
docker compose -f compose-nvidia.yaml up -d   # applies without rebuild
```

## GPU / transcoding configuration

### Quick checks

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# GPU visible?
docker exec $CONTAINER nvidia-smi

# ffmpeg with NVENC?
docker exec $CONTAINER ffmpeg -hwaccels 2>&1 | grep cuda
docker exec $CONTAINER ffmpeg -encoders 2>/dev/null | grep nvenc
docker exec $CONTAINER ffmpeg -decoders 2>/dev/null | grep cuvid

# Libraries OK?
docker exec $CONTAINER sh -c 'ldd /usr/bin/ffmpeg | grep "not found"'
```

### Check whether transcoding uses the GPU

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# ffmpeg processes inside the container
docker exec $CONTAINER ps aux | grep ffmpeg

# Look for h264_nvenc in args (GPU) vs libx264 (software)
docker exec $CONTAINER sh -c 'for pid in $(pgrep ffmpeg); do
  echo "=== PID $pid ==="
  cat /proc/$pid/cmdline | tr "\0" " "
  echo
done'

# Real-time GPU monitor
watch -n1 "docker exec $CONTAINER nvidia-smi"
```

> **If ffmpeg shows `-c:v libx264` instead of `h264_nvenc`:** The auto-test may have disabled
> hw accel. Confirm entrypoint patches were applied (logs should show
> `"NVENC: patched server.js"`). Restart the container to re-apply.

### server-settings.json

Stremio stores transcoding settings in `/root/.stremio-server/server-settings.json`
(persisted on the volume).

**Relevant fields:**
```json
{
    "transcodeHardwareAccel": true,
    "transcodeProfile": "nvenc-linux",
    "allTranscodeProfiles": ["nvenc-linux"],
    "transcodeConcurrency": 1,
    "transcodeMaxWidth": 1920,
    "transcodeMaxBitRate": 0
}
```

> **Note:** The GPU is only used when transcoding happens (e.g. HEVC→H264, resolution change).
> If the player supports the codec natively, the stream goes straight through without ffmpeg.

## Runtime patches (server.js)

The `stremio-web-service-run.sh` file (container entrypoint) patches Stremio's `server.js`
**before** starting the node process. This is necessary because `server.js` is a minified
webpack bundle and we cannot change Stremio's source directly.

Patches are re-applied automatically on every container restart/recreate.

### Patch 1: Neutralize the hardware-acceleration auto-test

**Problem:** Stremio runs an auto-test to verify hardware acceleration.
It transcodes a 0.2 second HEVC sample. That test **always fails** because:
- The sample is too short (0.2s)
- There is a race with the concurrency limit
- ffmpeg returns "Error: stream ended" before enough output is produced

When the test fails, Stremio calls `saveSettings({transcodeHardwareAccel: !1})` which:
1. Sets `userSettings.transcodeHardwareAccel = false` **in memory**
2. Writes `false` to `server-settings.json` on disk

**Why this is hard to fix:**
- `saveSettings()` updates the node process’s **in-memory** state
- Editing `server-settings.json` afterwards does not help — node already read the value
- The auto-test runs at two times: startup (`initialDetection`) **and** with a callback (`expectResult`)
- Even disabling `initialDetection`, the callback path still runs the test

**Solution:** Replace every instance of `transcodeHardwareAccel: !1` (false) with
`transcodeHardwareAccel: !0` (true) in the minified `server.js`:

```bash
sed -i 's/transcodeHardwareAccel: !1/transcodeHardwareAccel: !0/g' server.js
```

That way, when the auto-test fails and calls `saveSettings()`, the value written stays
`true` (both in memory and on disk).

### Patch 2: nvenc-linux profile — 10-bit compatibility (Pascal)

**Problem:** Pascal GPUs (GTX 1070, 1080, etc.) do not support 10-bit H.264 NVENC encoding.
Stremio's original profile uses:
```
-hwaccel cuda -hwaccel_output_format cuda -init_hw_device cuda=cu:0 -filter_hw_device cu
```
With `-hwaccel_output_format cuda`, decoded frames stay in CUDA memory in the native format
(p010le for 10-bit HEVC). `h264_nvenc` on Pascal rejects 10-bit frames with:
```
10 bit encode not supported
Provided device doesn't support required NVENC features
```

**Solution (6 substitutions in server.js):**

```bash
# 1. Remove -hwaccel_output_format cuda
#    Without it, ffmpeg auto-downloads CUDA frames to system memory
sed -i 's/"-hwaccel", "cuda", "-hwaccel_output_format", "cuda"/"-hwaccel", "cuda"/' server.js

# 2. Remove -init_hw_device/-filter_hw_device
#    Only needed for scale_cuda (which we no longer use)
sed -i 's/"-init_hw_device", "cuda=cu:0", "-filter_hw_device", "cu", "-hwaccel"/"-hwaccel"/' server.js

# 3. Disable scale_cuda (use CPU scale with automatic 10→8 bit conversion)
sed -i 's/scale: "scale_cuda"/scale: !1/' server.js

# 4. Add lanczos flags to CPU scale (quality)
sed -i '/nvenc/,/vaapi/{s/scaleExtra: ""/scaleExtra: ":flags=lanczos"/}' server.js

# 5. Disable wrapSwFilters (hwdownload/hwupload not needed with CPU scale)
sed -i 's/wrapSwFilters: \[ "hwdownload", "hwupload_cuda" \]/wrapSwFilters: !1/' server.js
```

**Internal server.js logic (for reference):**

Around line 82560 in the webpack bundle, filter logic works like this:
- If `accelConfig.scale` is truthy (e.g. `"scale_cuda"`): uses HW filters `scale_cuda=W:H:format=pixfmt`
- If `accelConfig.scale` is falsy (`!1`): uses SW filters `scale=W:H:flags=lanczos,format=yuv420p`
- If `accelConfig.wrapSwFilters` is truthy (array): wraps SW filters with `[hwdownload, ..., hwupload_cuda]`
- If `accelConfig.wrapSwFilters` is falsy (`!1`): SW filters pass through unchanged

Profile selection (around line 82535):
```javascript
!options.profile && userSettings.transcodeHardwareAccel &&
  userSettings.transcodeProfile && (options.profile = userSettings.transcodeProfile);
```
This reads `userSettings` **in memory**, not the file — which is why Patch 1 is essential.

### Pre-applied settings configuration

The entrypoint also adjusts `server-settings.json` on disk as a fallback:
```bash
sed -i \
  -e 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' \
  -e 's/"transcodeProfile": null/"transcodeProfile": "nvenc-linux"/' \
  -e 's/"allTranscodeProfiles": \[\]/"allTranscodeProfiles": ["nvenc-linux"]/' \
  "$SETTINGS"
```

## Rebuild / update

### When to rebuild?

| Situation | Command |
|---|---|
| Update stremio-web | `docker compose -f compose-nvidia.yaml build --no-cache` |
| Update CUDA base image | Edit version in Dockerfile.nvidia, then `build --no-cache` |
| Change compose configuration | `docker compose -f compose-nvidia.yaml up -d` (no rebuild) |
| Change nginx/scripts/env | `docker compose -f compose-nvidia.yaml build` (partial cache) |
| Update NVIDIA driver on host | Restart container only |

### Full rebuild walkthrough

```bash
cd /path/to/stremio-docker

# 1. Stop container
docker compose -f compose-nvidia.yaml down

# 2. Rebuild (--no-cache if updating base images)
docker compose -f compose-nvidia.yaml build --no-cache

# 3. Start again
docker compose -f compose-nvidia.yaml up -d

# 4. Wait for startup (~10s)
sleep 10

# 5. Confirm patches applied (NVENC message should appear)
docker logs stremio-docker-stremio-1 2>&1 | grep NVENC

# 6. Confirm GPU visible
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) nvidia-smi

# 7. Check settings
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) \
  grep -E 'transcodeHardware|transcodeProfile' /root/.stremio-server/server-settings.json
```

> **Note:** The entrypoint patches `server.js` automatically on every restart — you do not need
> to re-apply settings or patches manually. That is the core design: the original `server.js`
> stays in the Docker image, and patches are applied at runtime.

### Updating the CUDA version

Edit `Dockerfile.nvidia`:
```dockerfile
# Stage 1 (build): use devel for the desired version
FROM nvidia/cuda:<VERSION>-devel-ubuntu22.04 AS ffmpeg

# Stage 3 (runtime): use runtime for the same version
FROM nvidia/cuda:<VERSION>-runtime-ubuntu22.04 AS final
```

Also verify `nv-codec-headers` compatibility (branch in the git clone, lines 21–24).

---

## What did NOT work (lessons learned)

This section documents every approach that was tried and failed, with an explanation of
**why** it failed. **Do not try these approaches again.**

### ❌ Approach 1: File watcher to keep settings

**Idea:** A background script watches `server-settings.json` and flips
`transcodeHardwareAccel` back to `true` whenever Stremio writes `false`.

**Attempted implementation:**
```bash
# Background subshell watching the file
(while [ "$SECONDS" -lt 360 ]; do
  if grep -q '"transcodeHardwareAccel": false' "$SETTINGS"; then
    sed -i 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' "$SETTINGS"
  fi
  sleep 2
done) &
```

**Why it failed:**
1. **Timeout too short:** First try used 90s, but the auto-test takes ~132s to finish
2. **Does not fix the real issue:** Even with a 360s timeout and the file corrected,
   the **node process** already read the value in memory. Stremio's `saveSettings()` updates:
   - `userSettings` (in-memory JavaScript object) → **not affected by editing the file**
   - `server-settings.json` (disk) → fixed by the watcher, but irrelevant
3. **ffmpeg kept using `libx264`** (software) instead of `h264_nvenc` because
   profile selection checks `userSettings.transcodeHardwareAccel` in memory

**Conclusion:** Editing the settings file after node has started is useless.
The fix must be in `server.js` before execution.

### ❌ Approach 2: Patch `initialDetection = false` in server.js

**Idea:** Disable the `initialDetection` flag in the server.js auto-test module
so the initial test never runs.

**Attempted implementation:**
```bash
sed -i 's/var initialDetection = !0/var initialDetection = !1/' server.js
```

**Why it failed:**
Stremio's auto-test has **two execution paths**:
1. `initialDetection = true` → runs at startup (no callback)
2. Invoked with a callback (`expectResult = !!cb = true`) → runs when transcoding is enabled

The patch only disabled path 1. Path 2 still ran the test
and called `saveSettings({transcodeHardwareAccel: !1})`.

**Conclusion:** Disabling the test alone is not enough — you must neutralize `saveSettings`
that writes `false`. The correct fix is to replace `!1` with `!0` in **all**
`saveSettings({transcodeHardwareAccel: ...})` calls.

### ❌ Approach 3: `scale_cuda=format=nv12` to convert 10-bit on the GPU

**Idea:** Use the `scale_cuda` filter with `format=nv12` to convert frames
from p010le (10-bit) to nv12 (8-bit) entirely on the GPU, without a CPU download.

**Attempted implementation:**
```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -c:v hevc_cuvid \
  -i input.mkv -vf "scale_cuda=1920:1080:format=nv12" -c:v h264_nvenc output.mp4
```

**Why it failed:**
ffmpeg in this build (jellyfin-ffmpeg 4.4.1-4) **does not support the `format` option on
`scale_cuda`**. The filter only accepts `w:h` without pixel-format conversion:
```
Option format not found.
```

Newer ffmpeg (5.x+) and custom builds may support
`scale_cuda=format=nv12`, but 4.4.x does not.

**Conclusion:** That would be the ideal solution (100% GPU), but it requires ffmpeg 5.x+
or a build with support. With jellyfin-ffmpeg 4.4.1-4, it is not possible.

### ❌ Approach 4: `hwdownload,format=nv12` to download as 8-bit

**Idea:** Download CUDA frames to system memory already converted to nv12 (8-bit)
using `hwdownload` followed by `format=nv12`.

**Attempted implementation:**
```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -c:v hevc_cuvid \
  -i input.mkv -vf "hwdownload,format=nv12,scale=1920:1080" -c:v h264_nvenc output.mp4
```

**Why it failed:**
`hwdownload` requires the output format to **exactly** match the CUDA frame format.
10-bit HEVC frames in CUDA are `p010le`, not `nv12`:
```
Discrepancy between hardware pixel format (cuda) and target pixel format (nv12)
```

The correct sequence would be `hwdownload,format=p010le,format=nv12` — but that is
essentially what removing `-hwaccel_output_format cuda` achieves automatically
(ffmpeg auto-downloads and the CPU scale converts transparently).

**Conclusion:** More complex and fragile. Removing `-hwaccel_output_format cuda`
is simpler and yields the same result — ffmpeg downloads automatically.

### ❌ Approach 5: Force settings via `server-settings.json` before startup

**Idea:** Set `server-settings.json` to the right values before starting
`node server.js`, expecting node to read them.

**What actually happens:**
1. Entrypoint sets the file with `transcodeHardwareAccel: true` ✅
2. `node server.js` starts and reads the file ✅
3. The auto-test runs ~132s later ⏳
4. The auto-test fails and calls `saveSettings({transcodeHardwareAccel: false})` ❌
5. The in-memory value becomes `false` again ❌
6. Subsequent transcode requests use software encoding ❌

**Conclusion:** Configuring the file is necessary but not sufficient. The auto-test
overwrites the in-memory value. **Always combine** with the `server.js` patch.

---

## Applied fixes (summary)

| # | Problem | Symptom | Root cause | Fix | File |
|---|----------|---------|------------|-----|------|
| 1 | CUDA 12.x build fail | `Unsupported gpu architecture 'compute_30'` | CUDA 12.x removed compute_30 | `--nvccflags="-gencode arch=compute_52,code=sm_52 -O2"` | Dockerfile.nvidia |
| 2 | NVENC/CUVID won’t compile | `ffnvcodec not satisfied` | Missing nv-codec-headers | Clone `nv-codec-headers n12.0.16.1` + `make install` | Dockerfile.nvidia |
| 3 | nginx crash | `getpwnam("nginx") failed` | Ubuntu does not create nginx user | `useradd -r -s /bin/false nginx` | Dockerfile.nvidia |
| 4 | Missing runtime lib | `libwebpmux.so.3 not found` | Separate package on Ubuntu 22.04 | `apt install libwebpmux3` | Dockerfile.nvidia |
| 5 | Entrypoint crash | `Bad substitution` | `dash` (POSIX sh) vs `bash` | POSIX `case` instead of `${var: -1}` | stremio-web-service-run.sh |
| 6 | GPU not used | ffmpeg uses `libx264` | Auto-test fails and disables hwaccel | `sed 's/transcodeHardwareAccel: !1/!0/g'` | stremio-web-service-run.sh |
| 7 | Video HTTP 500 | `10 bit encode not supported` | Pascal cannot NVENC 10-bit H.264 | Remove `hwaccel_output_format cuda`, use CPU scale | stremio-web-service-run.sh |

## Technical reference

### NVENC architecture by GPU generation

| Generation | Examples | H.264 8-bit | H.264 10-bit | HEVC 8-bit | HEVC 10-bit |
|---------|----------|-------------|--------------|------------|-------------|
| Maxwell (2nd gen) | GTX 950-980 | ✅ | ❌ | ✅ | ❌ |
| **Pascal** | **GTX 1070, 1080** | **✅** | **❌** | **✅** | **❌** |
| Turing | RTX 2070, 2080 | ✅ | ❌ | ✅ | ✅ |
| Ampere | RTX 3070, 3080 | ✅ | ❌ | ✅ | ✅ |
| Ada Lovelace | RTX 4070, 4090 | ✅ | ❌ | ✅ | ✅ |

> **Note:** H.264 10-bit NVENC is not supported on **any** generation. The issue here is
> specific to when **input** is 10-bit and frames stay in CUDA memory
> without conversion to 8-bit before encode.
>
> Turing+ GPUs support HEVC 10-bit encode, so they could use `scale_cuda` to
> convert and encode to HEVC. Stremio targets H.264 as output.

### Patch locations in server.js (webpack bundle)

These offsets are approximate and may change between stremio-web versions:

| Patch | Approx. location | Minified pattern |
|-------|------------------|------------------|
| Auto-test disable | ~lines 71936, 71962 | `saveSettings({transcodeHardwareAccel: !1})` |
| Profile selection | ~line 82535 | `userSettings.transcodeHardwareAccel && userSettings.transcodeProfile` |
| Filter chain logic | ~line 82560 | `accelConfig.scale`, `accelConfig.wrapSwFilters` |
| nvenc-linux profile | ~line 82480 | `profile: "nvenc-linux"`, `scale: "scale_cuda"` |

> **To verify after a stremio-web update:**
> ```bash
> grep -n "transcodeHardwareAccel" server.js | head -10
> grep -n "scale_cuda" server.js | head -5
> grep -n "nvenc-linux" server.js | head -5
> ```

### Useful diagnostic commands

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# All ffmpeg processes and their arguments
docker exec $CONTAINER sh -c 'for pid in $(pgrep ffmpeg); do
  echo "=== PID $pid ($(ps -o rss= -p $pid | awk "{printf \"%.0fMB\", \$1/1024}") RSS) ==="
  cat /proc/$pid/cmdline | tr "\0" " "
  echo -e "\n"
done'

# Check patches were applied
docker exec $CONTAINER grep -c 'transcodeHardwareAccel: !0' server.js
# Should return 3 (2 that were !1 + 1 original that was already !0)

# Check scale_cuda was removed from nvenc profile
docker exec $CONTAINER grep -c 'scale_cuda' server.js
# Should return 0 (all removed)

# Current settings in memory (via Stremio API)
curl -s http://localhost:11470/settings 2>/dev/null | python3 -m json.tool | grep -E 'transcode|Hardware'

# Continuous GPU monitoring
watch -n1 "docker exec $CONTAINER nvidia-smi --query-gpu=utilization.gpu,utilization.encoder,utilization.decoder,memory.used --format=csv,noheader"
```

## Current environment

- **Host:** Linux, 4 CPUs, 15GB RAM
- **GPU:** NVIDIA GeForce GTX 1070 (8GB VRAM, Pascal, compute 6.1)
- **Driver:** 535.288.01 / CUDA 12.2
- **Docker runtime:** nvidia (nvidia-container-toolkit)
- **Volume:** `/mnt/lvm1-storage/.stremio-server`
- **Access:** `https://stremio.media.lan/` (port 8085; example URL — match `SERVER_URL` in `compose-nvidia.yaml`)
- **Git branch:** `test/gpu-nvidia`

### Current container limits

| Resource | Limit | Reservation | Rationale |
|---------|--------|-------------|-----------|
| CPU | 1.5 cores | — | NVENC offload (measured peak: 138%) |
| RAM | 1536 MB | 256 MB | Measured peak: 1.35 GB |
| GPU | 1× GTX 1070 | — | Decode + encode |

### Commits (branch test/gpu-nvidia)

```
44f6233 perf: reduce container limits — NVENC offloads to GPU
f869494 docs: update NVIDIA-GPU.md with 10-bit compat and auto-patch info
2ba78fd fix: patch nvenc-linux profile for 10-bit compat (Pascal GPUs)
a8d74c5 fix: neutralize hw accel auto-test by patching saveSettings calls
b6db603 fix: patch server.js to skip broken hw accel auto-test
2ecfd3e fix: extend NVENC watcher to 360s (auto-test takes ~2min)
e321aca feat: NVIDIA GPU hardware acceleration (NVENC/NVDEC/CUVID)
```
