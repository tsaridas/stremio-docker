# Stremio Docker — NVIDIA GPU (NVENC/NVDEC)

Guia completo para build, deploy e manutenção da imagem Stremio com aceleração GPU NVIDIA.

## Pré-requisitos no Host

- Driver NVIDIA >= 535 (`nvidia-smi` deve funcionar)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) instalado
- Docker com runtime `nvidia` configurado (`docker info | grep nvidia`)

```bash
# Verificar pré-requisitos
nvidia-smi
docker info | grep -i "runtimes.*nvidia"
```

## Arquitetura

```
┌─────────────────────────────────────────────────────┐
│  compose.yaml                                       │
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
│      └── stremio-web-service-run.sh                 │
└─────────────────────────────────────────────────────┘
```

## Build

```bash
# Build padrão
docker compose -f compose.yaml build

# Build sem cache (após mudar base images)
docker compose -f compose.yaml build --no-cache

# Build com branch específico do stremio-web
docker compose -f compose.yaml build --build-arg BRANCH=release
```

**Tempo de build:** ~5-10 min (ffmpeg com CUDA é o mais demorado).

## Deploy

```bash
# Subir o container
docker compose -f compose.yaml up -d

# Ver logs
docker logs -f stremio-docker-stremio-1

# Reiniciar
docker compose -f compose.yaml restart

# Parar
docker compose -f compose.yaml down
```

**Acesso:** `https://stremio.raspberrypi.lan/` (porta 8085 no host → 8080 no container)

## Limites de Recursos (compose.yaml)

```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"        # Max 2 cores (de 4 disponíveis)
      memory: 2G          # Max 2GB RAM (de 15GB disponíveis)
    reservations:
      memory: 512M        # Mínimo garantido
      devices:
        - driver: nvidia
          count: 1         # 1 GPU (GTX 1070 8GB)
          capabilities: [gpu, video, compute]
```

Para ajustar limites, edite `compose.yaml` e rode:
```bash
docker compose -f compose.yaml up -d   # aplica sem rebuild
```

## Configuração GPU / Transcoding

### Verificação rápida

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# GPU visível?
docker exec $CONTAINER nvidia-smi

# ffmpeg com NVENC?
docker exec $CONTAINER ffmpeg -hwaccels 2>&1 | grep cuda
docker exec $CONTAINER ffmpeg -encoders 2>/dev/null | grep nvenc
docker exec $CONTAINER ffmpeg -decoders 2>/dev/null | grep cuvid

# Libs ok?
docker exec $CONTAINER sh -c 'ldd /usr/bin/ffmpeg | grep "not found"'
```

### server-settings.json

O Stremio guarda configurações de transcoding em `/root/.stremio-server/server-settings.json` (persistido no volume).

**Campos relevantes:**
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

**Problema conhecido:** O teste automático de hwaccel do Stremio falha com o sample curto (0.2s) e marca `transcodeHardwareAccel: false`. Se isso acontecer após rebuild:

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# Forçar NVENC
docker exec $CONTAINER sed -i \
  -e 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' \
  -e 's/"transcodeProfile": null/"transcodeProfile": "nvenc-linux"/' \
  -e 's/"allTranscodeProfiles": \[\]/"allTranscodeProfiles": ["nvenc-linux"]/' \
  /root/.stremio-server/server-settings.json

# Reiniciar para aplicar
docker compose -f compose.yaml restart
```

### Monitorar uso de GPU durante streaming

```bash
# Tempo real
watch -n1 "docker exec $(docker ps --filter 'ancestor=stremio-docker:nvidia' -q) nvidia-smi"
```

> **Nota:** A GPU só é usada quando há transcoding (ex: HEVC→H264, mudança de resolução). Se o player suporta o codec nativo, o stream vai direto sem ffmpeg.

### Perfil nvenc-linux (pipeline ffmpeg)

O perfil `nvenc-linux` no server.js do Stremio usa:
- **Decode:** `hevc_cuvid`, `h264_cuvid`, `av1_cuvid` (GPU)
- **Scale:** `scale_cuda` (GPU)
- **Encode:** `h264_nvenc`, `hevc_nvenc` (GPU)
- **Args:** `-init_hw_device cuda=cu:0 -filter_hw_device cu -hwaccel cuda -hwaccel_output_format cuda`

## Rebuild / Atualização

### Quando rebuildar?

| Situação | Comando |
|---|---|
| Atualizar stremio-web | `docker compose build --no-cache` |
| Atualizar CUDA base image | Editar versão no Dockerfile.nvidia, depois `build --no-cache` |
| Mudar configuração de compose | `docker compose up -d` (sem rebuild) |
| Mudar nginx/scripts/env | `docker compose build` (cache parcial) |
| Atualizar driver NVIDIA no host | Reiniciar container apenas |

### Passo a passo para rebuild completo

```bash
cd /home/lgldsilva/backup-dietpi-home/stremio-docker

# 1. Parar container
docker compose -f compose.yaml down

# 2. Rebuild (--no-cache se atualizar base images)
docker compose -f compose.yaml build --no-cache

# 3. Subir novamente
docker compose -f compose.yaml up -d

# 4. Aguardar inicialização (~10s)
sleep 10

# 5. Verificar se GPU funciona
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) \
  ffmpeg -hwaccels 2>&1 | grep cuda

# 6. Re-aplicar configuração NVENC (se teste automático falhar)
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) sed -i \
  -e 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' \
  -e 's/"transcodeProfile": null/"transcodeProfile": "nvenc-linux"/' \
  -e 's/"allTranscodeProfiles": \[\]/"allTranscodeProfiles": ["nvenc-linux"]/' \
  /root/.stremio-server/server-settings.json

# 7. Reiniciar para aplicar
docker compose -f compose.yaml restart

# 8. Confirmar tudo ok
docker logs stremio-docker-stremio-1 2>&1 | tail -5
```

### Atualizar versão CUDA

Editar em `Dockerfile.nvidia`:
```dockerfile
# Stage 1 (build): usar devel da versão desejada
FROM nvidia/cuda:<VERSION>-devel-ubuntu22.04 AS ffmpeg

# Stage 3 (runtime): usar runtime da mesma versão
FROM nvidia/cuda:<VERSION>-runtime-ubuntu22.04 AS final
```

Também verificar compatibilidade de `nv-codec-headers` (branch no git clone).

## Correções aplicadas (vs Dockerfile original)

| Problema | Correção | Arquivo |
|---|---|---|
| `nvcc fatal: Unsupported gpu architecture 'compute_30'` | `--nvccflags="-gencode arch=compute_52,code=sm_52 -O2"` | Dockerfile.nvidia |
| `cuvid requested, but not all dependencies are satisfied: ffnvcodec` | Instalação de `nv-codec-headers n12.0.16.1` | Dockerfile.nvidia |
| `getpwnam("nginx") failed` | `useradd -r -s /bin/false nginx` | Dockerfile.nvidia |
| `libwebpmux.so.3: cannot open` | Adicionado `libwebpmux3` aos pacotes | Dockerfile.nvidia |
| `Bad substitution` (dash vs bash) | `case` POSIX em vez de `${var: -1}` | stremio-web-service-run.sh |
| Teste hwaccel falha (sample curto) | Configuração manual em server-settings.json | Pós-deploy |

## Ambiente atual

- **Host:** DietPi Linux, 4 CPUs, 15GB RAM
- **GPU:** NVIDIA GeForce GTX 1070 (8GB VRAM)
- **Driver:** 535.288.01 / CUDA 12.2
- **Volume:** `/mnt/lvm1-storage/.stremio-server` (2.7TB, 755GB livre)
- **Acesso:** `https://stremio.raspberrypi.lan/` (porta 8085)
