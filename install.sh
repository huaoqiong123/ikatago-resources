#!/usr/bin/env bash
# ikatago-resources installer: KataGo (CUDA, Linux x64) + network + ikatago-server
# Usage: curl -fsSL https://raw.githubusercontent.com/huaoqiong123/ikatago-resources/main/install.sh | bash
#        ... | bash -s -- --network b28 --dry-run
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/ikatago}"
NETWORK="${NETWORK:-b18}"
FORCE_CUDA="${FORCE_CUDA:-}"
DRY_RUN="${DRY_RUN:-0}"
UPSTREAM_FALLBACK="${UPSTREAM_FALLBACK:-1}"
SKIP_GPU_CHECK="${SKIP_GPU_CHECK:-0}"
MANIFEST_URL="${MANIFEST_URL:-}"
MANIFEST_FILE="${MANIFEST_FILE:-}"
RETRIES="${RETRIES:-3}"

log()  { printf '[ikatago] %s\n' "$*" >&2; }
warn() { printf '[ikatago][WARN] %s\n' "$*" >&2; }
die()  { local code="$1"; shift; printf '[ikatago][ERROR] %s\n' "$*" >&2; exit "$code"; }

usage() {
  cat <<'U'
ikatago-resources installer (Linux + NVIDIA GPU)
Options:
  --dry-run               只打印计划，不下载 / print plan only
  --network b18|b28       选择权重 (default b18)
  --install-dir DIR       安装目录 (default ~/ikatago)
  --cuda 12.1|12.8|13.2   强制 KataGo CUDA 版本 / force variant
  --no-upstream-fallback  不回退到上游下载地址
  --skip-gpu-check        跳过 nvidia-smi 检测 (需配合 --cuda 或默认 12.1)
  -h, --help              帮助
Env: INSTALL_DIR NETWORK FORCE_CUDA DRY_RUN MANIFEST_URL MANIFEST_FILE RETRIES
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --network) NETWORK="${2:?}"; shift ;;
    --install-dir) INSTALL_DIR="${2:?}"; shift ;;
    --cuda) FORCE_CUDA="${2:?}"; shift ;;
    --no-upstream-fallback) UPSTREAM_FALLBACK=0 ;;
    --skip-gpu-check) SKIP_GPU_CHECK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 1 "unknown option: $1" ;;
  esac
  shift
done
case "$NETWORK" in b18|b28) ;; *) die 1 "--network must be b18 or b28" ;; esac

embedded_manifest() {
cat <<'MANIFEST'
# BEGIN MANIFEST
#id	filename	url	sha256	size	source_url	license
katago_cuda12.1	katago-v1.18.2-cuda12.1-cudnn8.9.7-linux-x64.zip	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/katago-v1.18.2-cuda12.1-cudnn8.9.7-linux-x64.zip	16c69f42291fe8c6d196d722d92299a5b04de852611d6c022a0dd9e0e83b5688	50783789	https://github.com/lightvector/KataGo/releases/download/v1.18.2/katago-v1.18.2-cuda12.1-cudnn8.9.7-linux-x64.zip	MIT
katago_cuda12.8	katago-v1.18.2-cuda12.8-cudnn9.8.0-linux-x64.zip	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/katago-v1.18.2-cuda12.8-cudnn9.8.0-linux-x64.zip	2cb197fc9bc2050f29112abb5b83cdbad63936cb4605d6e199772aedc9806c02	51350638	https://github.com/lightvector/KataGo/releases/download/v1.18.2/katago-v1.18.2-cuda12.8-cudnn9.8.0-linux-x64.zip	MIT
katago_cuda13.2	katago-v1.18.2-cuda13.2-cudnn9.24.0-linux-x64.zip	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/katago-v1.18.2-cuda13.2-cudnn9.24.0-linux-x64.zip	f75ad848543014c3ff8df6e9d378efc078c07d458c5e6def06bbb5df8accb169	50896760	https://github.com/lightvector/KataGo/releases/download/v1.18.2/katago-v1.18.2-cuda13.2-cudnn9.24.0-linux-x64.zip	MIT
network_b18	kata1-b18c384nbt-s9996604416-d4316597426.bin.gz	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz	9d7a6afed8ff5b74894727e156f04f0cd36060a24824892008fbb6e0cba51f1d	97898094	https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz	katagotraining-network-license(MIT-style)
network_b28	kata1-b28c512nbt-s13255194368-d5935380940.bin.gz	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/kata1-b28c512nbt-s13255194368-d5935380940.bin.gz	c5bca453d7b08ea8df6546439325d4dd681e77d975e1da3f7593d771147b73bc	271440852	https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b28c512nbt-s13255194368-d5935380940.bin.gz	katagotraining-network-license(MIT-style)
ikatago_server	ikatago-server-5.0.1-linux.zip	https://github.com/huaoqiong123/ikatago-resources/releases/download/v1.0.0/ikatago-server-5.0.1-linux.zip	fc83d04596dad3b7c1d2a20a19a6d8c1d5bb43612a145225172d78bffbb07145	8215877	https://github.com/kinfkong/ikatago-server/releases/download/v5.0.1/ikatago-server-5.0.1-linux.zip	NO-LICENSE-FILE-upstream(redistribution-unclear)
# END MANIFEST
MANIFEST
}

# ---- deps ----
if command -v curl >/dev/null 2>&1; then DL=curl
elif command -v wget >/dev/null 2>&1; then DL=wget
else die 3 "需要 curl 或 wget / curl or wget is required"; fi
for c in unzip sha256sum awk; do
  if ! command -v "$c" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then warn "missing $c"; else die 3 "缺少依赖 / missing dependency: $c (e.g. sudo apt install $c)"; fi
  fi
done

fetch() { # url out
  if [ "$DL" = curl ]; then curl -fL --progress-bar --connect-timeout 20 -o "$2" "$1"
  else wget -O "$2" "$1"; fi
}

# ---- manifest ----
MANIFEST_DATA=""
if [ -n "$MANIFEST_FILE" ]; then MANIFEST_DATA="$(cat "$MANIFEST_FILE")"
elif [ -n "$MANIFEST_URL" ]; then
  tmpm="$(mktemp)"; fetch "$MANIFEST_URL" "$tmpm" || die 4 "cannot download manifest $MANIFEST_URL"
  MANIFEST_DATA="$(cat "$tmpm")"; rm -f "$tmpm"
else MANIFEST_DATA="$(embedded_manifest)"; fi

# field: 2 filename 3 url 4 sha256 5 size 6 source_url 7 license
mf() { printf '%s\n' "$MANIFEST_DATA" | awk -F'\t' -v id="$1" -v f="$2" '$1==id {print $f; exit}'; }

ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# ---- GPU detection ----
CUDA_VER=""; DRIVER_VER=""
if command -v nvidia-smi >/dev/null 2>&1; then
  smi="$(nvidia-smi 2>&1 || true)"
  DRIVER_VER="$(printf '%s\n' "$smi" | sed -n 's/.*Driver Version: *\([0-9.]*\).*/\1/p' | head -n1)"
  CUDA_VER="$(printf '%s\n' "$smi" | sed -n 's/.*CUDA Version: *\([0-9.]*\).*/\1/p' | head -n1)"
  gpus="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || true)"
  log "GPU: ${gpus:-unknown} | driver ${DRIVER_VER:-?} | max CUDA ${CUDA_VER:-?}"
  [ -n "$CUDA_VER" ] || warn "无法从 nvidia-smi 解析 CUDA 版本 / could not parse CUDA version"
else
  msg="未检测到 nvidia-smi：请先安装 NVIDIA 驱动 (本脚本仅支持 Linux + NVIDIA GPU)。 / nvidia-smi not found: install the NVIDIA driver first (Linux + NVIDIA GPU only)."
  if [ "$SKIP_GPU_CHECK" = 1 ] || [ "$DRY_RUN" = 1 ] || [ -n "$FORCE_CUDA" ]; then warn "$msg"
  else die 2 "$msg"; fi
fi

if [ -n "$FORCE_CUDA" ]; then VARIANT="$FORCE_CUDA"
elif [ -n "$CUDA_VER" ]; then
  if ver_ge "$CUDA_VER" 13.2; then VARIANT=13.2
  elif ver_ge "$CUDA_VER" 12.8; then VARIANT=12.8
  elif ver_ge "$CUDA_VER" 12.1; then VARIANT=12.1
  else die 2 "驱动支持的 CUDA ($CUDA_VER) 太旧，KataGo CUDA 版需要 >= 12.1，请升级驱动 (>= 530) / driver too old: CUDA $CUDA_VER < 12.1, upgrade NVIDIA driver"; fi
else VARIANT=12.1; warn "未知 CUDA 版本，默认使用 12.1 / defaulting to CUDA 12.1 build"; fi

KATAGO_ID="katago_cuda$VARIANT"; NET_ID="network_$NETWORK"; SRV_ID="ikatago_server"
for id in "$KATAGO_ID" "$NET_ID" "$SRV_ID"; do
  [ -n "$(mf "$id" 2)" ] || die 4 "manifest has no entry '$id'"
done
log "KataGo variant: $(mf "$KATAGO_ID" 2)"
log "Network: $(mf "$NET_ID" 2)"
log "Server: $(mf "$SRV_ID" 2)"
log "Install dir: $INSTALL_DIR"

if [ "$DRY_RUN" = 1 ]; then
  for id in "$KATAGO_ID" "$NET_ID" "$SRV_ID"; do
    log "[dry-run] would download $(mf "$id" 3) (sha256 $(mf "$id" 4)); fallback $(mf "$id" 6)"
  done
  log "[dry-run] done, nothing written."; exit 0
fi

DLDIR="$INSTALL_DIR/downloads"; mkdir -p "$DLDIR"
sha_ok() { [ -f "$1" ] && [ "$(sha256sum "$1" | awk '{print $1}')" = "$2" ]; }

download_asset() { # id -> prints path
  local id="$1" f url sha src out tmp u i
  f="$(mf "$id" 2)"; url="$(mf "$id" 3)"; sha="$(mf "$id" 4)"; src="$(mf "$id" 6)"
  out="$DLDIR/$f"
  if sha_ok "$out" "$sha"; then log "已存在且校验通过 / cached: $f"; printf '%s' "$out"; return 0; fi
  local urls=("$url"); [ "$UPSTREAM_FALLBACK" = 1 ] && [ -n "$src" ] && [ "$src" != "$url" ] && urls+=("$src")
  for u in "${urls[@]}"; do
    for ((i=1; i<=RETRIES; i++)); do
      log "下载 / downloading ($i/$RETRIES): $u"
      tmp="$out.part"
      if fetch "$u" "$tmp" && sha_ok "$tmp" "$sha"; then mv "$tmp" "$out"; printf '%s' "$out"; return 0; fi
      warn "下载或 sha256 校验失败 / download or sha256 mismatch: $u"
      rm -f "$tmp"; sleep $((i*3))
    done
  done
  die 5 "无法下载 / failed to download $f"
}

KZ="$(download_asset "$KATAGO_ID")"
NZ="$(download_asset "$NET_ID")"
SZ="$(download_asset "$SRV_ID")"

mkdir -p "$INSTALL_DIR/katago" "$INSTALL_DIR/networks" "$INSTALL_DIR/ikatago-server" "$INSTALL_DIR/configs"
unzip -oq "$KZ" -d "$INSTALL_DIR/katago"
chmod +x "$INSTALL_DIR/katago/katago"
cp -f "$NZ" "$INSTALL_DIR/networks/"
ln -sfn "$(basename "$NZ")" "$INSTALL_DIR/networks/default.bin.gz"
unzip -oq "$SZ" -d "$INSTALL_DIR/ikatago-server"
SRV_BIN="$(find "$INSTALL_DIR/ikatago-server" -type f -name ikatago-server | head -n1)"
[ -n "$SRV_BIN" ] || die 6 "ikatago-server binary not found in zip"
chmod +x "$SRV_BIN"
cp -f "$INSTALL_DIR/katago/default_gtp.cfg" "$INSTALL_DIR/configs/gtp.cfg"
cp -f "$INSTALL_DIR/katago/analysis_example.cfg" "$INSTALL_DIR/configs/analysis.cfg"

K="$INSTALL_DIR/katago/katago"; N="$INSTALL_DIR/networks/default.bin.gz"
mkscript() { printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" > "$INSTALL_DIR/$1"; chmod +x "$INSTALL_DIR/$1"; }
mkscript start-gtp.sh "exec \"$K\" gtp -model \"$N\" -config \"$INSTALL_DIR/configs/gtp.cfg\" \"\$@\""
mkscript start-analysis.sh "exec \"$K\" analysis -model \"$N\" -config \"$INSTALL_DIR/configs/analysis.cfg\" \"\$@\""
mkscript start-benchmark.sh "exec \"$K\" benchmark -model \"$N\" -config \"$INSTALL_DIR/configs/gtp.cfg\" \"\$@\""
mkscript start-ikatago-server.sh "# ikatago-server 需要指向 KataGo 及其配置；参数请以 '\"$SRV_BIN\" --help' 为准。
# KataGo: $K  model: $N  config: $INSTALL_DIR/configs/gtp.cfg
if [ \$# -eq 0 ]; then echo '用法: 传入 ikatago-server 参数，例如 --platform/--token 等；可用参数如下:'; exec \"$SRV_BIN\" --help; fi
exec \"$SRV_BIN\" \"\$@\""

# KataGo v1.18.x Linux 发行包为 AppImage (ELF magic + "AI\x02")；无 FUSE 时用 extract-and-run。
if [ "$(head -c 11 "$K" | tail -c 3 | od -An -c | tr -d ' ')" = 'AI002' ]; then
  log "KataGo 二进制为 AppImage / KataGo binary is an AppImage"
  if ! { [ -e /dev/fuse ] && ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; }; then
    warn "未检测到 FUSE2，启动脚本将设置 APPIMAGE_EXTRACT_AND_RUN=1 / no FUSE2, using APPIMAGE_EXTRACT_AND_RUN=1"
    for f in start-gtp.sh start-analysis.sh start-benchmark.sh; do
      sed -i '2a export APPIMAGE_EXTRACT_AND_RUN=1' "$INSTALL_DIR/$f"
    done
  fi
else
  missing="$(ldd "$K" 2>/dev/null | grep 'not found' || true)"
  if [ -n "$missing" ]; then
    warn "KataGo 缺少动态库 (需要与文件名对应的 CUDA/cuDNN) / missing libs:"
    printf '%s\n' "$missing" >&2
  fi
fi
log "完成 / done. 运行 $INSTALL_DIR/start-benchmark.sh 进行测速，$INSTALL_DIR/start-gtp.sh 启动 GTP。"
