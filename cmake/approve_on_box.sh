#!/bin/sh
# Approve a container-tools prerelease ON THE BOX -- the one validation CI structurally can't do.
# In one flow it: installs the prerelease .pkg, BOOT-PROOFs the bundled boot2docker.iso in VMware Fusion,
# smoke-tests the daemon, then re-blesses boot2docker's baseline FROM THAT SAME iso -- so the manual
# boot-test is also what greens boot2docker.yml. Afterwards you promote the prerelease to a full release.
#
# Run from a container-tools checkout (it commits the blessing here). Needs: VMware Fusion, docker-machine,
# docker, gh, git. Usage:
#   cmake/approve_on_box.sh [<tag>] [--yes]
#     <tag>   prerelease to approve (default: v$(cat VERSION))
#     --yes   commit + push the blessing without the interactive confirm
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cd "$repo"

REPO_SLUG="ModernMavericks/container-tools"
ISO=/usr/local/share/modernmavericks/container-tools/boot2docker.iso
MACHINE="${MVD_APPROVE_MACHINE:-mvd-approve}"
YES=0; TAG=""
for a in "$@"; do case "$a" in --yes) YES=1;; -*) echo "unknown flag: $a" >&2; exit 2;; *) TAG=$a;; esac; done
[ -n "$TAG" ] || TAG="v$(cat VERSION)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "approve: missing '$1' on PATH" >&2; exit 1; }; }
for t in gh git docker-machine docker curl shasum; do need "$t"; done

work=$(mktemp -d "${TMPDIR:-/tmp}/mvd-approve.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "== 1/5  install the $TAG prerelease .pkg =="
gh release download "$TAG" -R "$REPO_SLUG" -p '*.pkg' -D "$work" --clobber
pkg=$(ls "$work"/*.pkg 2>/dev/null | head -1)
[ -f "$pkg" ] || { echo "approve: no .pkg asset on $TAG" >&2; exit 1; }
sudo installer -pkg "$pkg" -target /
[ -f "$ISO" ] || { echo "approve: installer did not place $ISO" >&2; exit 1; }

echo "== 2/5  BOOT-PROOF: boot the bundled iso in VMware Fusion =="
docker-machine rm -y "$MACHINE" >/dev/null 2>&1 || true
docker-machine create -d vmwarefusion --vmwarefusion-boot2docker-url "$ISO" "$MACHINE"
[ "$(docker-machine status "$MACHINE")" = "Running" ] || { echo "approve: $MACHINE did not reach Running" >&2; exit 1; }
eval "$(docker-machine env "$MACHINE")"

echo "== 3/5  daemon smoke test =="
docker version
docker run --rm hello-world >/dev/null
echo "BOOT-PROOF OK: the shipped iso booted and ran a container."

echo "== 4/5  re-bless boot2docker from the SAME iso =="
REF=$(sed -n 's/^REF=//p'  components/boot2docker/version)
base=$(sed -n 's/^REPO=//p' components/boot2docker/version | sed 's/\.git$//')
# golden.sha256: sha of the upstream release asset (supply-chain bless of the pinned target)
curl -fsSL -o "$work/upstream.iso" "$base/releases/download/$REF/boot2docker.iso"
shasum -a 256 "$work/upstream.iso" | awk '{print $1}' > components/boot2docker/golden.sha256
# fingerprint: version-facts of the iso we actually ship (the from-source build in the .pkg)
sh cmake/iso_fingerprint.sh emit "$ISO" cmake/characterization/boot2docker
echo "-- confirm both gates now pass --"
sh cmake/iso_fetch_verify.sh components/boot2docker
sh cmake/iso_fingerprint.sh compare cmake/characterization/boot2docker "$ISO"

echo "== 5/5  the blessing (review then commit) =="
git --no-pager diff --stat components/boot2docker cmake/characterization/boot2docker
git --no-pager diff components/boot2docker cmake/characterization/boot2docker
MSG="boot2docker: bless $REF (boot-proofed on the box during $TAG approval)"
if [ "$YES" -ne 1 ]; then
  printf 'Commit + push this blessing? [y/N] '; read ans
  case "$ans" in y|Y|yes) ;; *) echo "not committed. Re-run with --yes, or commit by hand."; exit 0;; esac
fi
git add components/boot2docker cmake/characterization/boot2docker
git commit -m "$MSG"
git push
echo
echo "Blessed + pushed. boot2docker.yml will go green. Now promote the prerelease to a full release:"
echo "  gh release edit $TAG -R $REPO_SLUG --prerelease=false     # (or flip it in the GitHub UI)"
