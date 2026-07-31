#!/bin/sh
# Stub-based test of container-tools-sync-image. NEVER touches the real ~/.docker.
# The point under test: before `docker-machine upgrade`, a stale host's Boot2DockerURL is repointed at
# the installed ISO -- else a Wowfunhappy-migrated host (URL = the old, now-unmounted DMG) fails to upgrade.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SYNC="$ROOT/payload/container-tools-sync-image"
[ -f "$SYNC" ] || { echo "docker_sync_image_test: helper missing" >&2; exit 1; }
fail() { echo "docker_sync_image_test: FAIL: $*" >&2; exit 1; }

setup() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-sync.XXXXXX")
  BIN="$WORK/bin"; mkdir -p "$BIN"
  export HOME="$WORK/home"; mkdir -p "$HOME/.docker/machine/machines"
  export MAVERICKS_DOCKER_ISO="$WORK/installed.iso"; printf 'NEW-IMAGE\n' > "$MAVERICKS_DOCKER_ISO"
  # stubs: docker-machine (for command -v + the Terminal-run upgrade), osascript (user picks "Upgrade").
  printf '#!/bin/sh\nexit 0\n' > "$BIN/docker-machine"; chmod +x "$BIN/docker-machine"
  printf '#!/bin/sh\necho Upgrade\n' > "$BIN/osascript"; chmod +x "$BIN/osascript"
  OLDPATH=$PATH; PATH="$BIN:$PATH"
  # A stale, Wowfunhappy-migrated host: its iso differs from the installed one, and its Boot2DockerURL
  # still points at the old DMG.
  H="$HOME/.docker/machine/machines/container-tools"; mkdir -p "$H"
  printf 'OLD-IMAGE\n' > "$H/boot2docker.iso"
  cat > "$H/config.json" <<EOF
{ "Name": "container-tools",
  "Boot2DockerURL": "/Volumes/Docker for Mavericks/boot2docker.iso" }
EOF
}
teardown() { PATH=$OLDPATH; rm -rf "$WORK"; }

case_repoints_before_upgrade() {
  setup
  sh "$SYNC" || fail "sync-image should exit 0"
  H="$HOME/.docker/machine/machines/container-tools"
  grep -q "\"Boot2DockerURL\": \"$MAVERICKS_DOCKER_ISO\"" "$H/config.json" \
    || fail "must repoint Boot2DockerURL at the installed ISO before upgrade"
  grep -q '/Volumes/Docker for Mavericks' "$H/config.json" \
    && fail "must not leave the stale Wowfunhappy DMG URL"
  teardown
}

# A host already on the current image is not touched (no dialog, no rewrite).
case_uptodate_noop() {
  setup
  H="$HOME/.docker/machine/machines/container-tools"
  cp "$MAVERICKS_DOCKER_ISO" "$H/boot2docker.iso"   # same image => not stale
  sh "$SYNC" || fail "sync-image should exit 0 when nothing is stale"
  grep -q '/Volumes/Docker for Mavericks' "$H/config.json" \
    || fail "an up-to-date host must be left untouched"
  teardown
}

case_repoints_before_upgrade
case_uptodate_noop
echo "docker_sync_image_test: OK"
