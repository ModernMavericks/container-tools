#!/bin/sh
# THE real proof: boot the rebuilt ISO in VMware Fusion via docker-machine and run
# hello-world. Box-only. Loudly SKIPS (exit 77 -> ctest "Skipped", never a silent pass)
# where docker-machine/VMware are absent. Expected engine version is read from the
# committed fingerprint reference (engine label b2d-vX.Y.Z -> X.Y.Z).
#   Arg: $1 = path to rebuilt boot2docker.iso
#   Env: MAVERICKS_DOCKER_FORCE_SKIP=1 -> skip (for the unit test)
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <iso>" >&2; exit 64; }
ISO=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ -n "${MAVERICKS_DOCKER_FORCE_SKIP:-}" ] \
   || ! command -v docker-machine >/dev/null 2>&1 \
   || [ ! -d "/Applications/VMware Fusion.app" ]; then
  echo "SKIP: boot-proof needs docker-machine + VMware Fusion (box only)" >&2
  exit 77
fi
[ -f "$ISO" ] || { echo "missing iso $ISO" >&2; exit 1; }
# Expected engine version, derived from the fingerprint reference's engine label
# (b2d-vX.Y.Z -> X.Y.Z). NOTE: this assumes the ISO's b2d tag == the Docker engine
# version, which holds for the dragonflylee pin. If a future bump decouples the ISO tag
# from the engine version, source the expected engine from the pin instead.
WANT=$(sed 's/^b2d-v//' "$ROOT/cmake/characterization/boot2docker/engine")

M="container-tools-bootproof-$$"
cleanup() { docker-machine rm -y -f "$M" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker-machine rm -y -f "$M" >/dev/null 2>&1 || true
docker-machine create -d vmwarefusion \
  --vmwarefusion-boot2docker-url "file://$ISO" "$M"
eval "$(docker-machine env "$M")"
docker run --rm hello-world
GOT=$(docker version --format '{{.Server.Version}}')
[ "$GOT" = "$WANT" ] || { echo "engine $GOT != expected $WANT" >&2; exit 1; }
echo "BOOT-PROOF OK: rebuilt iso booted, hello-world ran, engine $GOT"
