#!/bin/sh
# Verify the reproduction TARGET's integrity: the pinned dragonflylee release asset must
# match components/boot2docker/golden.sha256. Independent of our rebuild.
# Arg: $1 = pin dir (components/boot2docker) holding `version` + `golden.sha256`.
# Env: MAVERICKS_DOCKER_ISO_LOCAL=<file> -> verify that local file instead of downloading (for tests).
set -eu
. "$(dirname "$0")/common.sh"
[ $# -eq 1 ] || { echo "usage: $0 <pin-dir>" >&2; exit 64; }
PIN=$1
GOLD=$(cat "$PIN/golden.sha256")
echo "$GOLD" | grep -qE '^[0-9a-f]{64}$' || mavericks_docker_die "golden.sha256 not 64 hex"

sha_of() {  # <file> -> stdout sha256 hex
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

if [ -n "${MAVERICKS_DOCKER_ISO_LOCAL:-}" ]; then
  iso=$MAVERICKS_DOCKER_ISO_LOCAL
else
  REPO=$(sed -n 's/^REPO=//p' "$PIN/version")
  REF=$(sed -n 's/^REF=//p' "$PIN/version")
  base=$(printf '%s' "$REPO" | sed 's/\.git$//')
  url="$base/releases/download/$REF/boot2docker.iso"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-fv.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  iso="$tmp/boot2docker.iso"
  echo "fetching $url"
  curl -fsSL -o "$iso" "$url" || mavericks_docker_die "download failed: $url"
fi
got=$(sha_of "$iso")
if [ "$got" = "$GOLD" ]; then
  echo "FETCH-VERIFY OK: asset sha256 $got matches golden"
else
  echo "FETCH-VERIFY FAIL: got $got, want $GOLD" >&2; exit 1
fi
