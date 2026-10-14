#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2001
# Non-GPU tests: fake nvidia-smi stubs, dry-run only (no downloads).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/install.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
mkbin() { # cuda|none
  local d="$T/bin-$1"; mkdir -p "$d"
  for c in bash sh curl unzip sha256sum awk sed sort head cat mktemp grep rm basename dirname; do
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
echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]
