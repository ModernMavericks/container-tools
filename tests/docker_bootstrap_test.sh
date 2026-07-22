#!/bin/sh
# Behavioral tests for docker-machine-bootstrap via PATH stubs.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOOT="$ROOT/payload/docker-machine-bootstrap"
[ -f "$BOOT" ] || { echo "docker_bootstrap_test: helper missing" >&2; exit 1; }

fail() { echo "docker_bootstrap_test: FAIL: $*" >&2; exit 1; }

setup() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/mvd-boot.XXXXXX")
  BIN="$WORK/bin"; mkdir -p "$BIN"
  export HOME="$WORK/home"; mkdir -p "$HOME"
  export MVD_STATE_DIR="$WORK/state"
  export MVD_LOG="$WORK/boot.log"
  export MVD_ISO="$WORK/iso"; : > "$MVD_ISO"
  export MVD_NONINTERACTIVE=1
  export MVD_PROFILES="$HOME/.bash_profile"
  export MVD_FUSION_PRESENT=1
  export DM_LOG="$WORK/dm.args"; : > "$DM_LOG"
  export DOCKER_LOG="$WORK/docker.args"; : > "$DOCKER_LOG"
  export OSA_LOG="$WORK/osa.args"; : > "$OSA_LOG"
  OLDPATH=$PATH; PATH="$BIN:$PATH"
  # osascript stub: record args (used for notifications + Terminal)
  cat > "$BIN/osascript" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$OSA_LOG"
EOF
  chmod +x "$BIN/osascript"
}
teardown() { PATH=$OLDPATH; rm -rf "$WORK"; }

# docker-machine stub: \$1 status -> echoes \$MVD_TEST_STATUS (empty => exit 1);
# create/start/env recorded; env prints canned exports.
make_dm() {
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in
  status) [ -n "\${MVD_TEST_STATUS:-}" ] && { echo "\${MVD_TEST_STATUS}"; exit 0; }; exit 1 ;;
  env) echo 'export DOCKER_TLS_VERIFY="1"'
       echo 'export DOCKER_HOST="tcp://192.168.237.131:2376"'
       echo "export DOCKER_CERT_PATH=\"$HOME/.docker/machine/machines/default\""
       echo 'export DOCKER_MACHINE_NAME="default"' ;;
  *) : ;;
esac
EOF
  chmod +x "$BIN/docker-machine"
}
# docker stub: record args; context inspect exits 1 (no context yet) unless a marker exists.
make_docker() {
  cat > "$BIN/docker" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DOCKER_LOG"
case "\$1 \$2" in
  "context inspect") [ -f "$WORK/ctx-exists" ] || exit 1 ;;
  *) : ;;
esac
EOF
  chmod +x "$BIN/docker"
}

# --- Case: Fusion absent -> notify, exit 0, no docker-machine calls ---
case_fusion_absent() {
  setup; make_dm; make_docker
  MVD_FUSION_PRESENT=0 MVD_TEST_STATUS= sh "$BOOT" || fail "should exit 0 when Fusion absent"
  [ -s "$DM_LOG" ] && fail "must not call docker-machine when Fusion absent"
  grep -q 'Fusion' "$OSA_LOG" || fail "expected a Fusion notification"
  teardown
}

case_fusion_absent
echo "docker_bootstrap_test: OK"
