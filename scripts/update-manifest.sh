#!/usr/bin/env bash
# Usage: scripts/update-manifest.sh [ASSET_DIR]
# Recompute sha256/size for every manifest.tsv row from files in ASSET_DIR,
# then embed manifest.tsv into install.sh between "# BEGIN MANIFEST" / "# END MANIFEST".
set -euo pipefail
cd "$(dirname "$0")/.."
ASSET_DIR="${1:-../ikatago-resources-release-assets}"
tmp="$(mktemp)"
while IFS= read -r line; do
  case "$line" in '#'*|'') printf '%s\n' "$line" >> "$tmp"; continue ;; esac
  IFS=$'\t' read -r id f url _sha _size src lic <<<"$line"
  if [ -f "$ASSET_DIR/$f" ]; then
    sha="$(sha256sum "$ASSET_DIR/$f" | awk '{print $1}')"; size="$(stat -c %s "$ASSET_DIR/$f")"
  else
    echo "WARN: $ASSET_DIR/$f missing, keeping old values" >&2; sha="$_sha"; size="$_size"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$f" "$url" "$sha" "$size" "$src" "$lic" >> "$tmp"
done < manifest.tsv
mv "$tmp" manifest.tsv
awk -v mf=manifest.tsv '
  /^# BEGIN MANIFEST$/ {print; while ((getline l < mf) > 0) print l; skip=1; next}
  /^# END MANIFEST$/ {skip=0}
  !skip {print}' install.sh > install.sh.new
mv install.sh.new install.sh; chmod +x install.sh
bash -n install.sh && echo "manifest embedded into install.sh"
