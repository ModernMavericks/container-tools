#!/bin/sh
# iso_fetch_verify.sh sha256 logic, offline (MAVERICKS_DOCKER_ISO_LOCAL skips the download).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FV="$ROOT/cmake/iso_fetch_verify.sh"
[ -f "$FV" ] || { echo "missing $FV" >&2; exit 1; }
sh -n "$FV"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-fvtest.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
# fake pin dir with a known content + its real sha256
pin="$tmp/pin"; mkdir -p "$pin"
printf 'REPO=https://github.com/dragonflylee/boot2docker.git\nREF=v20.10.24\n' > "$pin/version"
printf 'hello boot2docker\n' > "$tmp/asset.iso"
if command -v sha256sum >/dev/null 2>&1; then sum=$(sha256sum "$tmp/asset.iso" | awk '{print $1}')
else sum=$(shasum -a 256 "$tmp/asset.iso" | awk '{print $1}'); fi
printf '%s\n' "$sum" > "$pin/golden.sha256"
# matching -> pass
MAVERICKS_DOCKER_ISO_LOCAL="$tmp/asset.iso" sh "$FV" "$pin" || { echo "expected pass on match" >&2; exit 1; }
# tampered golden -> fail
printf '%064d\n' 0 > "$pin/golden.sha256"
if MAVERICKS_DOCKER_ISO_LOCAL="$tmp/asset.iso" sh "$FV" "$pin" >/dev/null 2>&1; then
  echo "expected fail on sha mismatch" >&2; exit 1
fi
echo "iso_fetch_verify_test: OK"
