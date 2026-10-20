#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2001
# Non-GPU tests: fake nvidia-smi stubs, dry-run only (no downloads).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/install.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
mkbin() { # cuda|none
  local d="$T/bin-$1"; mkdir -p "$d"
  for c in bash sh curl unzip sha256sum awk sed sort head cat mktemp grep rm basename dirname tr find od; do
    p="$(command -v "$c")" && ln -sf "$p" "$d/$c"; done
  if [ "$1" != none ]; then
    printf '#!/bin/sh\nif [ "$1" = "--query-gpu=name" ]; then echo "Fake RTX"; exit 0; fi\necho "| NVIDIA-SMI 550.00   Driver Version: 550.00   CUDA Version: %s |"\n' "$1" > "$d/nvidia-smi"
    chmod +x "$d/nvidia-smi"; fi
  echo "$d"; }
check() { # name expected_code pattern -- cmd...
  local name="$1" code="$2" pat="$3"; shift 3
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$code" ] && grep -q -- "$pat" <<<"$out"; then echo "PASS $name"; pass=$((pass+1))
  else echo "FAIL $name (rc=$rc)"; echo "$out" | sed 's/^/   /'; fail=$((fail+1)); fi; }
H="$T/home"
check "help" 0 "Options" env PATH="$(mkbin none)" HOME="$H" bash "$S" -h
check "no nvidia-smi" 2 "nvidia-smi not found" env PATH="$(mkbin none)" HOME="$H" bash "$S"
check "no nvidia-smi dry-run warns" 0 "cuda12.1" env PATH="$(mkbin none)" HOME="$H" bash "$S" --dry-run
check "cuda 12.4 -> 12.1" 0 "katago-v1.18.2-cuda12.1" env PATH="$(mkbin 12.4)" HOME="$H" bash "$S" --dry-run
check "cuda 12.9 -> 12.8" 0 "katago-v1.18.2-cuda12.8" env PATH="$(mkbin 12.9)" HOME="$H" bash "$S" --dry-run
check "cuda 13.2 -> 13.2" 0 "katago-v1.18.2-cuda13.2" env PATH="$(mkbin 13.2)" HOME="$H" bash "$S" --dry-run
check "cuda 11.8 too old" 2 "driver too old" env PATH="$(mkbin 11.8)" HOME="$H" bash "$S" --dry-run
check "b28 network" 0 "kata1-b28c512nbt" env PATH="$(mkbin 12.4)" HOME="$H" bash "$S" --dry-run --network b28
check "bad option" 1 "unknown option" env PATH="$(mkbin 12.4)" HOME="$H" bash "$S" --bogus
[ ! -e "$H/ikatago" ] && { echo "PASS dry-run wrote nothing"; pass=$((pass+1)); } || { echo "FAIL dry-run wrote files"; fail=$((fail+1)); }
check "bad --cuda value" 1 "must be one of" env PATH="$(mkbin 12.4)" HOME="$H" bash "$S" --dry-run --cuda 11
check "ikatago-server primary url is upstream" 0 "ikatago-server/releases/download/v5.0.1.*fallback https://github.com/kinfkong" env PATH="$(mkbin 12.4)" HOME="$H" bash "$S" --dry-run

# ---- end-to-end install against local file:// assets (no network, no GPU) ----
if command -v zip >/dev/null 2>&1; then
  E="$T/e2e"; mkdir -p "$E/assets" "$E/kz" "$E/sv/ikatago-server-5.0.1-linux"
  printf '\177ELF\002\001\001\000AI\002rest' > "$E/kz/katago"
  echo cfg > "$E/kz/default_gtp.cfg"; echo cfg > "$E/kz/analysis_example.cfg"
  (cd "$E/kz" && zip -q "$E/assets/k.zip" katago default_gtp.cfg analysis_example.cfg)
  echo net > "$E/assets/n.bin.gz"
  printf '#!/bin/sh\necho srv "$@"\n' > "$E/sv/ikatago-server-5.0.1-linux/ikatago-server"
  (cd "$E/sv" && zip -qr "$E/assets/s.zip" .)
  sha() { sha256sum "$E/assets/$1" | awk '{print $1}'; }
  mkmanifest() { # out primary_prefix badsha(0|1) crlf(0|1)
    local out="$1" pre="$2" bad="$3" crlf="$4" ks ns ss
    ks="$(sha k.zip)"; ns="$(sha n.bin.gz)"; ss="$(sha s.zip)"
    [ "$bad" = 1 ] && ks=0000000000000000000000000000000000000000000000000000000000000000
    printf 'katago_cuda12.1\tk.zip\t%s/k.zip\t%s\t1\tfile://%s/k.zip\tMIT\nnetwork_b18\tn.bin.gz\t%s/n.bin.gz\t%s\t1\tfile://%s/n.bin.gz\tX\nikatago_server\ts.zip\t%s/s.zip\t%s\t1\tfile://%s/s.zip\tX\n' \
      "$pre" "$ks" "$E/assets" "$pre" "$ns" "$E/assets" "$pre" "$ss" "$E/assets" > "$out"
    [ "$crlf" = 1 ] && sed -i 's/$/\r/' "$out"; return 0; }
  inst() { env HOME="$1" MANIFEST_FILE="$2" RETRIES=1 bash "$S" --cuda 12.1 --skip-gpu-check "${@:3}"; }

  mkmanifest "$E/good.tsv" "file://$E/assets" 0 0
  H1="$T/h1"
  check "e2e install" 0 "done" inst "$H1" "$E/good.tsv"
  [ -x "$H1/ikatago/start-gtp.sh" ] && [ -x "$H1/ikatago/start-ikatago-server.sh" ] && [ -L "$H1/ikatago/networks/default.bin.gz" ] \
    && [ -f "$H1/ikatago/configs/gtp.cfg" ] && [ -x "$H1/ikatago/ikatago-server/ikatago-server-5.0.1-linux/ikatago-server" ] \
    && { echo "PASS e2e layout"; pass=$((pass+1)); } || { echo "FAIL e2e layout"; fail=$((fail+1)); }
  g=0; s_=0
  grep -q APPIMAGE_EXTRACT_AND_RUN "$H1/ikatago/start-gtp.sh" && g=1
  grep -q APPIMAGE_EXTRACT_AND_RUN "$H1/ikatago/start-ikatago-server.sh" && s_=1
  [ "$g" = "$s_" ] && { echo "PASS e2e appimage env consistent across all start scripts"; pass=$((pass+1)); } || { echo "FAIL e2e appimage env differs (gtp=$g server=$s_)"; fail=$((fail+1)); }
  for f in start-analysis.sh start-benchmark.sh; do
    [ "$(grep -c APPIMAGE_EXTRACT_AND_RUN "$H1/ikatago/$f")" = "$g" ] && { echo "PASS e2e $f env"; pass=$((pass+1)); } || { echo "FAIL e2e $f env"; fail=$((fail+1)); }
  done
  check "e2e cached on rerun" 0 "cached" inst "$H1" "$E/good.tsv"

  mkmanifest "$E/fallback.tsv" "file://$E/missing" 0 0
  check "e2e falls back to upstream url" 0 "done" inst "$T/h2" "$E/fallback.tsv"
  check "e2e no-fallback fails (rc 5)" 5 "failed to download" inst "$T/h3" "$E/fallback.tsv" --no-upstream-fallback
  mkmanifest "$E/badsha.tsv" "file://$E/assets" 1 0
  check "e2e sha256 mismatch fails (rc 5)" 5 "sha256 mismatch" inst "$T/h4" "$E/badsha.tsv" --no-upstream-fallback
  mkmanifest "$E/crlf.tsv" "file://$E/assets" 0 1
  check "e2e CRLF manifest" 0 "done" inst "$T/h5" "$E/crlf.tsv"
else
  echo "SKIP e2e tests (zip not installed)"
fi
echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]
