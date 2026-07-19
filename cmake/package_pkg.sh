#!/bin/sh
# Assemble the (unsigned) mavericks-docker product .pkg: the docker CLI + Compose + Machine binaries,
# the boot2docker.iso, and the Sparkle updater (app + shim + daily LaunchAgent), with a hard 10.9.5
# install floor. Signing + appcast happen separately (shared sign_and_appcast.sh) in the release
# workflow; this script only builds the .pkg.
#
# Product-specific payload layout lives HERE; the generic mechanics (updater staging, the OS-floor
# product archive) come from mavericks-shared-cmake via $MSC_SCRIPTS. Prints the .pkg path on stdout.
#
# Usage:
#   package_pkg.sh --out PKG --version V --docker BIN --compose BIN --machine BIN --iso ISO \
#     --updater-app APP.app [--msc-scripts DIR] [--resources DIR --welcome FILE]
set -eu
export COPYFILE_DISABLE=1

OUT=""; VER=""; DOCKER=""; COMPOSE=""; MACHINE=""; LAZY=""; ISO=""; UPD_APP=""; DOCKED=""; SYNC=""; README=""
MSC="${MSC_SCRIPTS:-}"; RES=""; WELCOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    --docker) DOCKER="$2"; shift 2;;
    --compose) COMPOSE="$2"; shift 2;;
    --machine) MACHINE="$2"; shift 2;;
    --lazydocker) LAZY="$2"; shift 2;;
    --iso) ISO="$2"; shift 2;;
    --updater-app) UPD_APP="$2"; shift 2;;
    --docked) DOCKED="$2"; shift 2;;
    --sync-helper) SYNC="$2"; shift 2;;
    --readme) README="$2"; shift 2;;
    --msc-scripts) MSC="$2"; shift 2;;
    --resources) RES="$2"; shift 2;;
    --welcome) WELCOME="$2"; shift 2;;
    *) echo "package_pkg: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$OUT" ] && [ -n "$VER" ] && [ -n "$DOCKER" ] && [ -n "$COMPOSE" ] && [ -n "$MACHINE" ] \
  && [ -n "$LAZY" ] && [ -n "$ISO" ] && [ -n "$UPD_APP" ] && [ -n "$DOCKED" ] && [ -n "$SYNC" ] && [ -n "$README" ] \
  || { echo "package_pkg: need --out --version --docker --compose --machine --lazydocker --iso --updater-app --docked --sync-helper --readme" >&2; exit 2; }
[ -n "$MSC" ] || { echo "package_pkg: MSC_SCRIPTS unset (install mavericks-shared-cmake, or pass --msc-scripts)" >&2; exit 2; }
for f in "$DOCKER" "$COMPOSE" "$MACHINE" "$LAZY" "$ISO" "$DOCKED" "$SYNC" "$README"; do [ -f "$f" ] || { echo "package_pkg: missing input: $f" >&2; exit 1; }; done
[ -d "$UPD_APP" ] || { echo "package_pkg: no updater .app: $UPD_APP" >&2; exit 1; }
for h in stage_updater.sh productbuild_floor.sh; do
  [ -f "$MSC/$h" ] || { echo "package_pkg: shared helper missing: $MSC/$h" >&2; exit 1; }
done

IDENT="com.schmonz.mavericks-docker"
AGENT_LABEL="com.schmonz.mavericks-docker-updatecheck"
UPD_LIBDIR="/usr/local/lib/mavericks-docker"
SHIM_NAME="mavericks-docker-update"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mvd-pkg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
stage="$WORK/stage"; scripts="$WORK/scripts"; comp="$WORK/component.pkg"

# --- product payload (docker CLI + plugins + iso) ---
mkdir -p "$stage/usr/local/bin" "$stage/usr/local/lib/docker/cli-plugins" "$stage/usr/local/share/mavericks-docker"
install -m 0755 "$DOCKER"  "$stage/usr/local/bin/docker"
install -m 0755 "$MACHINE" "$stage/usr/local/bin/docker-machine"
install -m 0755 "$LAZY"    "$stage/usr/local/bin/lazydocker"
install -m 0755 "$DOCKED"  "$stage/usr/local/bin/docked"
install -m 0755 "$SYNC"    "$stage/usr/local/bin/mavericks-docker-sync-image"
# Compose v2 as a CLI plugin (enables `docker compose`), plus a standalone `docker-compose` symlink.
install -m 0755 "$COMPOSE" "$stage/usr/local/lib/docker/cli-plugins/docker-compose"
ln -s ../lib/docker/cli-plugins/docker-compose "$stage/usr/local/bin/docker-compose"
install -m 0644 "$ISO"    "$stage/usr/local/share/mavericks-docker/boot2docker.iso"
install -m 0644 "$README" "$stage/usr/local/share/mavericks-docker/README.txt"

# --- updater app + shim + LaunchAgent + postinstall (shared, hoisted) ---
sh "$MSC/stage_updater.sh" --stage "$stage" --app "$UPD_APP" --lib-dir "$UPD_LIBDIR" \
  --agent-label "$AGENT_LABEL" --shim-name "$SHIM_NAME" --scripts-out "$scripts"

# --- flat component pkg over the whole payload, with the agent-loading postinstall ---
# Strip AppleDouble sidecars copied in from the (NFS) source tree. NOTE: macOS 26 stamps an
# UNREMOVABLE com.apple.provenance xattr on every Mach-O, and pkgbuild encodes each as a ._ payload
# entry -- unavoidable, and identical to golang/swift's shipped pkgs. Those merge back into inert
# xattrs when Installer extracts onto the 10.9 box's HFS+, so no ._ FILES land on the target.
find "$stage" -name '._*' -delete 2>/dev/null || true
pkgbuild --root "$stage" --identifier "$IDENT" --version "$VER" \
         --scripts "$scripts" --install-location / "$comp" >&2

# --- product archive with the 10.9.5 OS floor (shared helper) ---
lic=""; [ -n "$WELCOME" ] && lic="--welcome $WELCOME"
resflag=""; [ -n "$RES" ] && resflag="--resources $RES"
sh "$MSC/productbuild_floor.sh" \
  --identifier "$IDENT" \
  --title "Docker for Mavericks $VER" \
  --component "$comp" --out "$OUT" \
  $resflag $lic --require-scripts --host-arch x86_64 >&2

echo "$OUT"
