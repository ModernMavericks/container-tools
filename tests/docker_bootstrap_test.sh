#!/bin/sh
# Behavioral tests for docker-machine-bootstrap via PATH stubs.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOOT="$ROOT/payload/docker-machine-bootstrap"
[ -f "$BOOT" ] || { echo "docker_bootstrap_test: helper missing" >&2; exit 1; }

fail() { echo "docker_bootstrap_test: FAIL: $*" >&2; exit 1; }

setup() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-boot.XXXXXX")
  BIN="$WORK/bin"; mkdir -p "$BIN"
  export HOME="$WORK/home"; mkdir -p "$HOME"
  export MAVERICKS_DOCKER_STATE_DIR="$WORK/state"
  export MAVERICKS_DOCKER_LOG="$WORK/boot.log"
  export MAVERICKS_DOCKER_ISO="$WORK/iso"; : > "$MAVERICKS_DOCKER_ISO"
  export MAVERICKS_DOCKER_NONINTERACTIVE=1
  export MAVERICKS_DOCKER_PROFILES="$HOME/.bash_profile"
  export MAVERICKS_DOCKER_FUSION_PRESENT=1
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

# docker-machine stub: \$1 status -> echoes \$MAVERICKS_DOCKER_TEST_STATUS (empty => exit 1);
# create/start/env recorded; env prints canned exports.
make_dm() {
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in
  status) [ -n "\${MAVERICKS_DOCKER_TEST_STATUS:-}" ] && { echo "\${MAVERICKS_DOCKER_TEST_STATUS}"; exit 0; }; exit 1 ;;
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
  MAVERICKS_DOCKER_FUSION_PRESENT=0 MAVERICKS_DOCKER_TEST_STATUS= sh "$BOOT" || fail "should exit 0 when Fusion absent"
  [ -s "$DM_LOG" ] && fail "must not call docker-machine when Fusion absent"
  grep -q 'Fusion' "$OSA_LOG" || fail "expected a Fusion notification"
  teardown
}

case_fusion_absent

# --- Case: no machine -> create, then start ---
case_create() {
  setup; make_docker
  # status: absent (exit 1) on first call, Stopped after create
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in
  status) [ -f "$WORK/created" ] && { echo Stopped; exit 0; }; exit 1 ;;
  create) : > "$WORK/created" ;;
  start)  : > "$WORK/started" ;;
  env)    echo 'export DOCKER_HOST="tcp://192.168.237.131:2376"'
          echo "export DOCKER_CERT_PATH=\"$HOME/x\"" ;;
esac
EOF
  chmod +x "$BIN/docker-machine"
  sh "$BOOT" || fail "create path should exit 0"
  grep -q 'create -d vmwarefusion' "$DM_LOG" || fail "expected docker-machine create"
  grep -q "default" "$DM_LOG" || fail "create should target 'default'"
  [ -f "$WORK/started" ] || fail "expected start after create"
  teardown
}

# --- Case: stopped -> start (no create) ---
case_start() {
  setup; make_docker
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in
  status) echo Stopped ;;
  start)  : > "$WORK/started" ;;
  env)    echo 'export DOCKER_HOST="tcp://192.168.237.131:2376"'
          echo "export DOCKER_CERT_PATH=\"$HOME/x\"" ;;
esac
EOF
  chmod +x "$BIN/docker-machine"
  sh "$BOOT" || fail "start path should exit 0"
  grep -q 'create' "$DM_LOG" && fail "must not create an existing machine"
  [ -f "$WORK/started" ] || fail "expected start"
  teardown
}

case_create
case_start

# --- Case: running -> create context from docker-machine env, then use it ---
case_context_create() {
  setup; make_dm; make_docker
  MAVERICKS_DOCKER_TEST_STATUS=Running sh "$BOOT" || fail "running path should exit 0"
  grep -q 'context create mavericks' "$DOCKER_LOG" || fail "expected context create"
  grep -q 'host=tcp://192.168.237.131:2376' "$DOCKER_LOG" || fail "context must carry env host"
  grep -q 'ca=.*/ca.pem' "$DOCKER_LOG" || fail "context must carry ca cert path"
  grep -q 'context use mavericks' "$DOCKER_LOG" || fail "expected context use"
  teardown
}

# --- Case: context exists with same host -> update skipped, still 'use' ---
case_context_current() {
  setup; make_dm
  : > "$WORK/ctx-exists"
  cat > "$BIN/docker" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DOCKER_LOG"
case "\$1 \$2" in
  "context inspect")
    # --format present => return current host (matches env); else exit 0
    case "\$*" in *Endpoints*) echo 'tcp://192.168.237.131:2376' ;; esac ;;
esac
EOF
  chmod +x "$BIN/docker"
  MAVERICKS_DOCKER_TEST_STATUS=Running sh "$BOOT" || fail "should exit 0"
  grep -q 'context update' "$DOCKER_LOG" && fail "must not update when host unchanged"
  grep -q 'context use mavericks' "$DOCKER_LOG" || fail "expected context use"
  teardown
}

case_context_create
case_context_current

# --- Case: leftover eval line in profile -> notify ---
case_env_override() {
  setup; make_dm; make_docker
  printf '%s\n' 'eval "$(docker-machine env default)"' > "$HOME/.bash_profile"
  MAVERICKS_DOCKER_TEST_STATUS=Running sh "$BOOT" || fail "should exit 0"
  grep -q 'overrides' "$OSA_LOG" || fail "expected env-override notification"
  teardown
}

# --- Case: clean profile -> no override notification ---
case_env_clean() {
  setup; make_dm; make_docker
  printf '%s\n' 'export PS1="$ "' > "$HOME/.bash_profile"
  MAVERICKS_DOCKER_TEST_STATUS=Running sh "$BOOT" || fail "should exit 0"
  grep -q 'overrides' "$OSA_LOG" && fail "must not warn on a clean profile"
  teardown
}

case_env_override
case_env_clean

# --- Case: interactive create -> Terminal do-script + lock acquired ---
case_interactive_create() {
  setup; make_docker
  unset MAVERICKS_DOCKER_NONINTERACTIVE
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in status) exit 1 ;; esac
EOF
  chmod +x "$BIN/docker-machine"
  sh "$BOOT" || fail "interactive create should exit 0"
  grep -q 'do script' "$OSA_LOG" || fail "expected a Terminal do-script"
  grep -q 'docker-machine create' "$OSA_LOG" || fail "Terminal must run docker-machine create"
  [ -d "$MAVERICKS_DOCKER_STATE_DIR/creating.lock" ] || fail "interactive create must hold the lock"
  teardown
}

# --- Case: create already in progress (fresh lock) -> no second create ---
case_create_locked() {
  setup; make_docker
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in status) exit 1 ;; esac
EOF
  chmod +x "$BIN/docker-machine"
  mkdir -p "$MAVERICKS_DOCKER_STATE_DIR/creating.lock"
  sh "$BOOT" || fail "should exit 0 when create locked"
  grep -q 'create' "$DM_LOG" && fail "must not create while lock held"
  grep -q 'docker-machine create' "$OSA_LOG" && fail "must not spawn create Terminal while lock held"
  teardown
}

# --- Case: stale lock (>10 min) -> reclaimed, create proceeds ---
case_stale_lock() {
  setup; make_docker
  cat > "$BIN/docker-machine" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$DM_LOG"
case "\$1" in
  status) [ -f "$WORK/created" ] && { echo Stopped; exit 0; }; exit 1 ;;
  create) : > "$WORK/created" ;;
  start)  : > "$WORK/started" ;;
  env)    echo 'export DOCKER_HOST="tcp://192.168.237.131:2376"'
          echo "export DOCKER_CERT_PATH=\"$HOME/x\"" ;;
esac
EOF
  chmod +x "$BIN/docker-machine"
  mkdir -p "$MAVERICKS_DOCKER_STATE_DIR/creating.lock"
  touch -t 200001010000 "$MAVERICKS_DOCKER_STATE_DIR/creating.lock"
  sh "$BOOT" || fail "should exit 0 on stale lock"
  grep -q 'create -d vmwarefusion' "$DM_LOG" || fail "stale lock must be reclaimed and create proceed"
  teardown
}

case_interactive_create
case_create_locked
case_stale_lock

# --- Case: packaging references are consistent ---
case_packaging() {
  grep -q '/usr/local/bin/docker-machine-bootstrap' "$ROOT/payload/dev.modernmavericks.container-tools-machine.plist" \
    || fail "plist must launch docker-machine-bootstrap"
  grep -q 'docker-machine-ensure-default' "$ROOT/payload/dev.modernmavericks.container-tools-machine.plist" \
    && fail "plist still references the old guard"
  grep -q -- '--bootstrap' "$ROOT/cmake/package_pkg.sh" || fail "package_pkg.sh missing --bootstrap"
  grep -q 'install -m 0755 "\$BOOT"' "$ROOT/cmake/package_pkg.sh" \
    || fail "package_pkg.sh must install the bootstrap helper"
  grep -q -- '--ensure-guard' "$ROOT/cmake/package_pkg.sh" && fail "package_pkg.sh still has --ensure-guard"
  [ -f "$ROOT/payload/docker-machine-ensure-default" ] && fail "old guard file still present"
  grep -q -- '--bootstrap payload/docker-machine-bootstrap' "$ROOT/.github/workflows/release.yml" \
    || fail "release.yml must pass --bootstrap"
  echo "  packaging-consistency OK"
}

case_packaging
echo "docker_bootstrap_test: OK"
