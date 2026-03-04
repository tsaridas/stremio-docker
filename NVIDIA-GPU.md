# Stremio Docker — NVIDIA GPU (NVENC/NVDEC)

Guia completo para build, deploy, manutenção e troubleshooting da imagem Stremio com
aceleração GPU NVIDIA. Inclui documentação detalhada de todos os problemas encontrados,
soluções aplicadas e abordagens que **não funcionaram** — para evitar repetir erros.

---

## Índice

1. [Pré-requisitos](#pré-requisitos-no-host)
2. [Arquitetura](#arquitetura)
3. [Build](#build)
4. [Deploy](#deploy)
5. [Limites de Recursos](#limites-de-recursos)
6. [Configuração GPU / Transcoding](#configuração-gpu--transcoding)
7. [Patches Runtime (server.js)](#patches-runtime-serverjs)
8. [Rebuild / Atualização](#rebuild--atualização)
9. [O que NÃO funcionou (lições aprendidas)](#o-que-não-funcionou-lições-aprendidas)
10. [Correções aplicadas (resumo)](#correções-aplicadas-resumo)
11. [Referência técnica](#referência-técnica)
12. [Ambiente atual](#ambiente-atual)

---

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
│      └── stremio-web-service-run.sh (entrypoint)    │
└─────────────────────────────────────────────────────┘
```

### Pipeline de transcoding (após patches)

```
Arquivo de vídeo (ex: HEVC 10-bit)
    │
    ▼
[GPU] CUVID decode (hevc_cuvid / h264_cuvid / av1_cuvid)
    │
    ▼ auto-download para memória sistema (ffmpeg faz isso automaticamente
    │ quando não há -hwaccel_output_format cuda)
    │
    ▼
[CPU] scale (lanczos) + format conversion (10-bit p010 → 8-bit yuv420p)
    │
    ▼ auto-upload para GPU (h264_nvenc aceita system memory frames)
    │
    ▼
[GPU] NVENC encode (h264_nvenc, preset p1, tune ull)
    │
    ▼
HLS output → player
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

### Problemas de build resolvidos

| Erro | Causa | Solução |
|------|-------|---------|
| `nvcc fatal: Unsupported gpu architecture 'compute_30'` | CUDA 12.x removeu suporte a compute_30 | `--nvccflags="-gencode arch=compute_52,code=sm_52 -O2"` (Maxwell+) |
| `cuvid requested, but not all dependencies are satisfied: ffnvcodec` | ffmpeg precisa de `nv-codec-headers` para compilar NVENC/NVDEC | Instalação manual do `nv-codec-headers` branch `n12.0.16.1` do GitHub |
| `getpwnam("nginx") failed` | Ubuntu não cria user `nginx` (Alpine sim) | `useradd -r -s /bin/false nginx` no Dockerfile |
| `libwebpmux.so.3: cannot open shared object file` | Ubuntu 22.04 separa `libwebpmux3` de `libwebp7` | Adicionado `libwebpmux3` explicitamente nos pacotes |
| `Bad substitution` no entrypoint | `Dockerfile` usa `/bin/sh` que é `dash` no Ubuntu, não `bash` | Trocado `${var: -1}` (bash-only) por `case "$var" in ... esac` (POSIX) |

## Deploy

```bash
# Subir o container
docker compose -f compose.yaml up -d

# Ver logs
docker logs -f stremio-docker-stremio-1

# Reiniciar (re-aplica patches server.js automaticamente)
docker compose -f compose.yaml restart

# Parar
docker compose -f compose.yaml down
```

**Acesso:** `https://stremio.raspberrypi.lan/` (porta 8085 no host → 8080 no container)

## Limites de Recursos

```yaml
deploy:
  resources:
    limits:
      cpus: "1.5"        # 1.5 cores (NVENC offload → CPU só faz áudio/decode)
      memory: 1536M       # 1.5GB (pico medido: 1.35GB durante transcode)
    reservations:
      memory: 256M        # Mínimo garantido (idle ~200MB: node + nginx)
      devices:
        - driver: nvidia
          count: 1         # 1 GPU (GTX 1070 8GB)
          capabilities: [gpu, video, compute]
```

### Consumo medido durante transcoding ativo

| Processo | CPU | RAM (RSS) | GPU |
|----------|-----|-----------|-----|
| ffmpeg áudio (aac) | ~30% | ~1.15 GB | — |
| ffmpeg vídeo (NVENC) | ~60% | ~234 MB | 15%, 868 MiB VRAM |
| node server.js | ~40% | ~185 MB | — |
| nginx | ~1% | ~28 MB | — |
| **Total** | **~138%** | **~1.35 GB** | **15% util** |

> **Por que 1.5 cores basta?** Com NVENC, o encode de vídeo (a parte mais pesada) roda na GPU.
> A CPU só faz decode de áudio, encode aac, e algum processamento de scale.
> Antes (libx264 software), o CPU ficava em 100%+ só com encode.

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

### Verificar se transcoding está usando GPU

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# Ver processos ffmpeg dentro do container
docker exec $CONTAINER ps aux | grep ffmpeg

# Procurar h264_nvenc nos argumentos (GPU) vs libx264 (software)
docker exec $CONTAINER sh -c 'for pid in $(pgrep ffmpeg); do
  echo "=== PID $pid ==="
  cat /proc/$pid/cmdline | tr "\0" " "
  echo
done'

# Monitor GPU em tempo real
watch -n1 "docker exec $CONTAINER nvidia-smi"
```

> **Se ffmpeg mostra `-c:v libx264` em vez de `h264_nvenc`:** O auto-test pode ter desabilitado
> hw accel. Verificar se os patches do entrypoint foram aplicados (logs devem mostrar
> `"NVENC: patched server.js"`). Reiniciar o container para re-aplicar.

### server-settings.json

O Stremio guarda configurações de transcoding em `/root/.stremio-server/server-settings.json`
(persistido no volume).

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

> **Nota:** A GPU só é usada quando há transcoding (ex: HEVC→H264, mudança de resolução).
> Se o player suporta o codec nativo, o stream vai direto sem ffmpeg.

## Patches Runtime (server.js)

O arquivo `stremio-web-service-run.sh` (entrypoint do container) aplica patches no `server.js`
do Stremio **antes** de iniciar o processo node. Isso é necessário porque o server.js é um
bundle webpack minificado e não podemos modificar o source do Stremio diretamente.

Os patches são re-aplicados automaticamente a cada restart/recreação do container.

### Patch 1: Neutralizar auto-test de hardware acceleration

**Problema:** O Stremio tem um auto-test que verifica se o hardware acceleration funciona.
Ele transcodifica um sample HEVC de 0.2 segundos. Esse teste **sempre falha** porque:
- O sample é muito curto (0.2s)
- Há um bug de race condition com o limite de concorrência
- O ffmpeg retorna "Error: stream ended" antes de produzir output suficiente

Quando o teste falha, o Stremio executa `saveSettings({transcodeHardwareAccel: !1})` que:
1. Seta `userSettings.transcodeHardwareAccel = false` **em memória**
2. Grava `false` no `server-settings.json` em disco

**Por que isso é difícil de corrigir:**
- O `saveSettings()` atualiza o estado **em memória** do processo node
- Editar o arquivo `server-settings.json` depois não adianta — o node já leu o valor
- O auto-test roda em 2 momentos: startup (`initialDetection`) E com callback (`expectResult`)
- Mesmo desabilitando `initialDetection`, o teste com callback ainda roda

**Solução:** Trocar TODAS as instâncias de `transcodeHardwareAccel: !1` (false) para
`transcodeHardwareAccel: !0` (true) no server.js minificado:

```bash
sed -i 's/transcodeHardwareAccel: !1/transcodeHardwareAccel: !0/g' server.js
```

Isso garante que mesmo quando o auto-test falha e chama `saveSettings()`,
o valor gravado é `true` (tanto em memória quanto em disco).

### Patch 2: Perfil nvenc-linux — compatibilidade 10-bit (Pascal)

**Problema:** GPUs Pascal (GTX 1070, 1080, etc.) não suportam encode H.264 10-bit via NVENC.
O perfil original do Stremio usa:
```
-hwaccel cuda -hwaccel_output_format cuda -init_hw_device cuda=cu:0 -filter_hw_device cu
```
Com `-hwaccel_output_format cuda`, os frames decodificados ficam em memória CUDA no formato
nativo (p010le para HEVC 10-bit). O `h264_nvenc` no Pascal rejeita frames 10-bit com erro:
```
10 bit encode not supported
Provided device doesn't support required NVENC features
```

**Solução (6 substituições no server.js):**

```bash
# 1. Remove -hwaccel_output_format cuda
#    Sem isso, ffmpeg auto-downloads frames CUDA para system memory
sed -i 's/"-hwaccel", "cuda", "-hwaccel_output_format", "cuda"/"-hwaccel", "cuda"/' server.js

# 2. Remove -init_hw_device/-filter_hw_device
#    Só eram necessários para scale_cuda (que não usamos mais)
sed -i 's/"-init_hw_device", "cuda=cu:0", "-filter_hw_device", "cu", "-hwaccel"/"-hwaccel"/' server.js

# 3. Desabilita scale_cuda (usa CPU scale com conversão automática 10→8 bit)
sed -i 's/scale: "scale_cuda"/scale: !1/' server.js

# 4. Adiciona flags lanczos ao CPU scale (qualidade)
sed -i '/nvenc/,/vaapi/{s/scaleExtra: ""/scaleExtra: ":flags=lanczos"/}' server.js

# 5. Desabilita wrapSwFilters (hwdownload/hwupload não necessários com CPU scale)
sed -i 's/wrapSwFilters: \[ "hwdownload", "hwupload_cuda" \]/wrapSwFilters: !1/' server.js
```

**Lógica interna do server.js (para referência):**

O server.js (por volta da linha 82560 no bundle webpack) tem esta lógica de filtros:
- Se `accelConfig.scale` é truthy (ex: `"scale_cuda"`): usa filtros HW `scale_cuda=W:H:format=pixfmt`
- Se `accelConfig.scale` é falsy (`!1`): usa filtros SW `scale=W:H:flags=lanczos,format=yuv420p`
- Se `accelConfig.wrapSwFilters` é truthy (array): envolve filtros SW com `[hwdownload, ..., hwupload_cuda]`
- Se `accelConfig.wrapSwFilters` é falsy (`!1`): filtros SW passam direto

A seleção do perfil (por volta da linha 82535):
```javascript
!options.profile && userSettings.transcodeHardwareAccel &&
  userSettings.transcodeProfile && (options.profile = userSettings.transcodeProfile);
```
Verifica `userSettings` **em memória**, não o arquivo — por isso o Patch 1 é essencial.

### Configuração pré-aplicada no settings

O entrypoint também configura o `server-settings.json` no disco como fallback:
```bash
sed -i \
  -e 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' \
  -e 's/"transcodeProfile": null/"transcodeProfile": "nvenc-linux"/' \
  -e 's/"allTranscodeProfiles": \[\]/"allTranscodeProfiles": ["nvenc-linux"]/' \
  "$SETTINGS"
```

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

# 5. Verificar patches aplicados (deve aparecer mensagem NVENC)
docker logs stremio-docker-stremio-1 2>&1 | grep NVENC

# 6. Verificar GPU visível
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) nvidia-smi

# 7. Verificar settings
docker exec $(docker ps --filter "ancestor=stremio-docker:nvidia" -q) \
  grep -E 'transcodeHardware|transcodeProfile' /root/.stremio-server/server-settings.json
```

> **Nota:** O entrypoint patcha `server.js` automaticamente a cada restart — não é necessário
> re-aplicar settings ou patches manualmente. Isso é o ponto-chave do design: o server.js
> original é preservado na imagem Docker, e os patches são aplicados em runtime.

### Atualizar versão CUDA

Editar em `Dockerfile.nvidia`:
```dockerfile
# Stage 1 (build): usar devel da versão desejada
FROM nvidia/cuda:<VERSION>-devel-ubuntu22.04 AS ffmpeg

# Stage 3 (runtime): usar runtime da mesma versão
FROM nvidia/cuda:<VERSION>-runtime-ubuntu22.04 AS final
```

Também verificar compatibilidade de `nv-codec-headers` (branch no git clone, linha 21-24).

---

## O que NÃO funcionou (lições aprendidas)

Esta seção documenta todas as abordagens que foram tentadas e falharam, com explicação de
**por que** falharam. **NÃO tente essas abordagens novamente.**

### ❌ Approach 1: File watcher para manter settings

**Ideia:** Um script em background monitora `server-settings.json` e reverte
`transcodeHardwareAccel` para `true` sempre que o Stremio gravar `false`.

**Implementação tentada:**
```bash
# Background subshell monitorando o arquivo
(while [ "$SECONDS" -lt 360 ]; do
  if grep -q '"transcodeHardwareAccel": false' "$SETTINGS"; then
    sed -i 's/"transcodeHardwareAccel": false/"transcodeHardwareAccel": true/' "$SETTINGS"
  fi
  sleep 2
done) &
```

**Por que falhou:**
1. **Timeout insuficiente:** Primeiro tentou com 90s, mas o auto-test leva ~132s para completar
2. **Não resolve o problema real:** Mesmo com timeout de 360s e o arquivo corrigido,
   o **processo node** já leu o valor em memória. O `saveSettings()` do Stremio atualiza:
   - `userSettings` (objeto JavaScript em memória) → **não afetado por editar o arquivo**
   - `server-settings.json` (disco) → corrigido pelo watcher, mas irrelevante
3. **O ffmpeg continuava usando `libx264`** (software) em vez de `h264_nvenc` porque
   a seleção de perfil verifica `userSettings.transcodeHardwareAccel` em memória

**Conclusão:** Editar o arquivo de settings depois que o node já iniciou é inútil.
A solução tem que ser no código do server.js, antes da execução.

### ❌ Approach 2: Patch `initialDetection = false` no server.js

**Ideia:** Desabilitar o flag `initialDetection` no módulo de auto-teste do server.js
para que ele nunca rode o teste inicial.

**Implementação tentada:**
```bash
sed -i 's/var initialDetection = !0/var initialDetection = !1/' server.js
```

**Por que falhou:**
O auto-teste do Stremio tem **dois caminhos de execução**:
1. `initialDetection = true` → roda na startup (SEM callback)
2. Chamado com callback (`expectResult = !!cb = true`) → roda quando o transcoding é ativado

O patch desabilitava apenas o caminho 1. O caminho 2 ainda executava o teste
e chamava `saveSettings({transcodeHardwareAccel: !1})`.

**Conclusão:** Não basta desabilitar o teste — precisa neutralizar o `saveSettings` que
grava o valor `false`. A solução correta é trocar `!1` por `!0` em TODAS as chamadas
`saveSettings({transcodeHardwareAccel: ...})`.

### ❌ Approach 3: `scale_cuda=format=nv12` para converter 10-bit na GPU

**Ideia:** Usar o filtro `scale_cuda` com opção `format=nv12` para converter frames
de p010le (10-bit) para nv12 (8-bit) inteiramente na GPU, sem download para CPU.

**Implementação tentada:**
```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -c:v hevc_cuvid \
  -i input.mkv -vf "scale_cuda=1920:1080:format=nv12" -c:v h264_nvenc output.mp4
```

**Por que falhou:**
O ffmpeg nesta build (jellyfin-ffmpeg 4.4.1-4) **não suporta a opção `format` no
`scale_cuda`**. O filtro só aceita `w:h` sem conversão de pixel format:
```
Option format not found.
```

Versões mais recentes do ffmpeg (5.x+) e builds customizadas podem suportar
`scale_cuda=format=nv12`, mas a 4.4.x não.

**Conclusão:** Seria a solução ideal (100% GPU), mas requer atualizar o ffmpeg para 5.x+
ou usar uma build com suporte. Com jellyfin-ffmpeg 4.4.1-4, não é possível.

### ❌ Approach 4: `hwdownload,format=nv12` para baixar como 8-bit

**Ideia:** Baixar frames CUDA para system memory já convertendo para nv12 (8-bit)
usando o filtro `hwdownload` seguido de `format=nv12`.

**Implementação tentada:**
```bash
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -c:v hevc_cuvid \
  -i input.mkv -vf "hwdownload,format=nv12,scale=1920:1080" -c:v h264_nvenc output.mp4
```

**Por que falhou:**
O `hwdownload` requer que o formato de saída corresponda **exatamente** ao formato
dos frames CUDA. Frames HEVC 10-bit em CUDA estão em `p010le`, não `nv12`:
```
Discrepancy between hardware pixel format (cuda) and target pixel format (nv12)
```

A sequência correta seria `hwdownload,format=p010le,format=nv12` — mas isso é
exatamente o que a remoção de `-hwaccel_output_format cuda` faz automaticamente
(ffmpeg auto-downloads e o CPU scale converte transparentemente).

**Conclusão:** Rota mais complexa e frágil. Remover `-hwaccel_output_format cuda`
é mais simples e produz o mesmo resultado — ffmpeg faz o download automaticamente.

### ❌ Approach 5: Forçar settings via `server-settings.json` antes do startup

**Ideia:** Configurar `server-settings.json` com os valores corretos antes de iniciar
o `node server.js`, esperando que o node leia esses valores.

**O que acontece na prática:**
1. O entrypoint configura o arquivo com `transcodeHardwareAccel: true` ✅
2. O `node server.js` inicia e lê o arquivo ✅
3. O auto-test executa ~132s depois ⏳
4. O auto-test falha e chama `saveSettings({transcodeHardwareAccel: false})` ❌
5. O valor em memória volta para `false` ❌
6. Todos os requests de transcoding subsequentes usam software encoding ❌

**Conclusão:** Configurar o arquivo é necessário mas não suficiente. O auto-test
sobrescreve o valor em memória. **Sempre combinar** com o patch do server.js.

---

## Correções aplicadas (resumo)

| # | Problema | Sintoma | Causa Raiz | Correção | Arquivo |
|---|----------|---------|------------|----------|---------|
| 1 | CUDA 12.x build fail | `Unsupported gpu architecture 'compute_30'` | CUDA 12.x removeu compute_30 | `--nvccflags="-gencode arch=compute_52,code=sm_52 -O2"` | Dockerfile.nvidia |
| 2 | NVENC/CUVID não compila | `ffnvcodec not satisfied` | Falta nv-codec-headers | Clone `nv-codec-headers n12.0.16.1` + `make install` | Dockerfile.nvidia |
| 3 | nginx crash | `getpwnam("nginx") failed` | Ubuntu não cria user nginx | `useradd -r -s /bin/false nginx` | Dockerfile.nvidia |
| 4 | Runtime lib faltando | `libwebpmux.so.3 not found` | Pacote separado no Ubuntu 22.04 | `apt install libwebpmux3` | Dockerfile.nvidia |
| 5 | Entrypoint crash | `Bad substitution` | `dash` (POSIX sh) vs `bash` | `case` POSIX em vez de `${var: -1}` | stremio-web-service-run.sh |
| 6 | GPU não usada | ffmpeg usa `libx264` | Auto-test falha e desabilita hwaccel | `sed 's/transcodeHardwareAccel: !1/!0/g'` | stremio-web-service-run.sh |
| 7 | Vídeo HTTP 500 | `10 bit encode not supported` | Pascal não faz NVENC 10-bit H.264 | Remove `hwaccel_output_format cuda`, usa CPU scale | stremio-web-service-run.sh |

## Referência técnica

### Arquitetura NVENC por geração de GPU

| Geração | Exemplos | H.264 8-bit | H.264 10-bit | HEVC 8-bit | HEVC 10-bit |
|---------|----------|-------------|--------------|------------|-------------|
| Maxwell (2ª gen) | GTX 950-980 | ✅ | ❌ | ✅ | ❌ |
| **Pascal** | **GTX 1070, 1080** | **✅** | **❌** | **✅** | **❌** |
| Turing | RTX 2070, 2080 | ✅ | ❌ | ✅ | ✅ |
| Ampere | RTX 3070, 3080 | ✅ | ❌ | ✅ | ✅ |
| Ada Lovelace | RTX 4070, 4090 | ✅ | ❌ | ✅ | ✅ |

> **Nota:** H.264 10-bit NVENC não é suportado em **nenhuma geração**. O problema
> é específico para quando o **input** é 10-bit e os frames ficam em memória CUDA
> sem conversão para 8-bit antes do encode.
>
> GPUs Turing+ suportam HEVC 10-bit encode, então poderiam usar `scale_cuda` para
> converter e encodar em HEVC. Mas o Stremio usa H.264 como output target.

### Localização dos patches no server.js (bundle webpack)

Estes offsets são aproximados e podem mudar entre versões do stremio-web:

| Patch | Localização aprox. | Padrão no minificado |
|-------|-------------------|---------------------|
| Auto-test disable | ~linha 71936, 71962 | `saveSettings({transcodeHardwareAccel: !1})` |
| Profile selection | ~linha 82535 | `userSettings.transcodeHardwareAccel && userSettings.transcodeProfile` |
| Filter chain logic | ~linha 82560 | `accelConfig.scale`, `accelConfig.wrapSwFilters` |
| nvenc-linux profile | ~linha 82480 | `profile: "nvenc-linux"`, `scale: "scale_cuda"` |

> **Para verificar após atualização do stremio-web:**
> ```bash
> grep -n "transcodeHardwareAccel" server.js | head -10
> grep -n "scale_cuda" server.js | head -5
> grep -n "nvenc-linux" server.js | head -5
> ```

### Comandos úteis de diagnóstico

```bash
CONTAINER=$(docker ps --filter "ancestor=stremio-docker:nvidia" -q)

# Ver todos os processos ffmpeg e seus argumentos
docker exec $CONTAINER sh -c 'for pid in $(pgrep ffmpeg); do
  echo "=== PID $pid ($(ps -o rss= -p $pid | awk "{printf \"%.0fMB\", \$1/1024}") RSS) ==="
  cat /proc/$pid/cmdline | tr "\0" " "
  echo -e "\n"
done'

# Verificar se patches foram aplicados
docker exec $CONTAINER grep -c 'transcodeHardwareAccel: !0' server.js
# Deve retornar 3 (2 que eram !1 + 1 original que já era !0)

# Verificar se scale_cuda foi removido do perfil nvenc
docker exec $CONTAINER grep -c 'scale_cuda' server.js
# Deve retornar 0 (todos removidos)

# Ver settings atuais em memória (via API do Stremio)
curl -s http://localhost:11470/settings 2>/dev/null | python3 -m json.tool | grep -E 'transcode|Hardware'

# GPU monitoring contínuo
watch -n1 "docker exec $CONTAINER nvidia-smi --query-gpu=utilization.gpu,utilization.encoder,utilization.decoder,memory.used --format=csv,noheader"
```

## Ambiente atual

- **Host:** DietPi Linux, 4 CPUs, 15GB RAM
- **GPU:** NVIDIA GeForce GTX 1070 (8GB VRAM, Pascal, compute 6.1)
- **Driver:** 535.288.01 / CUDA 12.2
- **Docker runtime:** nvidia (nvidia-container-toolkit)
- **Volume:** `/mnt/lvm1-storage/.stremio-server`
- **Acesso:** `https://stremio.raspberrypi.lan/` (porta 8085)
- **Branch git:** `test/gpu-nvidia`

### Limites atuais do container

| Recurso | Limite | Reserva | Justificativa |
|---------|--------|---------|---------------|
| CPU | 1.5 cores | — | NVENC offload (pico medido: 138%) |
| RAM | 1536 MB | 256 MB | Pico medido: 1.35 GB |
| GPU | 1x GTX 1070 | — | Decode + encode |

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
