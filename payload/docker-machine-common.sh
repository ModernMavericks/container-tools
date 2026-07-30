#!/bin/sh
# docker-machine-common.sh — shared constants + helpers for docker-machine-bootstrap
# and docker-machine-ctl. SOURCED, not executed. Honors the MAVERICKS_DOCKER_* test seams.

# The menu-bar app (and anything else launched by LaunchServices) runs with a minimal PATH
# — /usr/bin:/bin:/usr/sbin:/sbin — that omits the install bindir. A bare `docker-machine`/
# `docker` then fails to resolve, so every verb driven from the GUI silently misreports:
# status_word() -> "absent" while the VM is really Stopped, and start/stop no-op. Guarantee
# our bindir is reachable regardless of the caller's PATH. Appended (not prepended) so a
# test/caller stub earlier on PATH still wins. Found dogfooding, 2026-07-29.
BINDIR=${MAVERICKS_DOCKER_BINDIR:-/usr/local/bin}
case ":$PATH:" in
  *:"$BINDIR":*) ;;
  *) PATH="$PATH:$BINDIR"; export PATH ;;
esac

MACHINE=container-tools
CONTEXT=mavericks
ISO=${MAVERICKS_DOCKER_ISO:-/usr/local/share/modernmavericks/container-tools/boot2docker.iso}
LOG=${MAVERICKS_DOCKER_LOG:-$HOME/Library/Logs/ModernMavericks/container-tools/bootstrap.log}
STATE_DIR=${MAVERICKS_DOCKER_STATE_DIR:-$HOME/Library/Application Support/ModernMavericks/container-tools}
STATE_FILE="$STATE_DIR/state"
LOCK="$STATE_DIR/creating.lock"
PROFILES=${MAVERICKS_DOCKER_PROFILES:-$HOME/.bash_profile $HOME/.profile $HOME/.zshrc $HOME/.bashrc}
AGENT_LABEL=dev.modernmavericks.container-tools-machine
AGENT_PLIST=/Library/LaunchAgents/$AGENT_LABEL.plist
MACHDIR=${MAVERICKS_DOCKER_MACHDIR:-$HOME/.docker/machine/machines}

# True if a legacy 'default' machine dir exists (pre-rename installs).
legacy_default_exists() { [ -d "$MACHDIR/default" ]; }

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null || true
}

notify() { # key title message  (throttled once/day per key)
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  _stamp="$STATE_DIR/notified-$1"; _today=$(date '+%Y-%m-%d')
  [ -f "$_stamp" ] && [ "$(cat "$_stamp" 2>/dev/null)" = "$_today" ] && return 0
  echo "$_today" > "$_stamp" 2>/dev/null || true
  osascript -e "display notification \"$3\" with title \"$2\"" >/dev/null 2>&1 || true
}

fusion_present() {
  [ "${MAVERICKS_DOCKER_FUSION_PRESENT:-}" = 0 ] && return 1
  [ "${MAVERICKS_DOCKER_FUSION_PRESENT:-}" = 1 ] && return 0
  [ -d "/Applications/VMware Fusion.app" ] || command -v vmrun >/dev/null 2>&1
}

machine_status() { docker-machine status "$MACHINE" 2>/dev/null; }

create_in_progress() {
  [ -d "$LOCK" ] || return 1
  _mt=$(stat -f %m "$LOCK" 2>/dev/null) || return 0
  if [ $(( $(date +%s) - _mt )) -gt 600 ]; then
    log "stale create lock; reclaiming"
    rmdir "$LOCK" 2>/dev/null || true
    return 1
  fi
  return 0
}

# The single word the state file / menu bar cares about.
status_word() {
  fusion_present || { echo no-fusion; return; }
  create_in_progress && { echo creating; return; }
  case "$(machine_status)" in
    Running) echo running ;;
    Stopped) echo stopped ;;
    "")      echo absent ;;
    *)       echo error ;;
  esac
}

write_state() {
  # Atomic: write a temp then rename, so a reader (or the menu-bar app's kqueue watch)
  # never sees a truncated/empty file mid-write. The watcher re-arms on the rename.
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s\n' "$1" > "$STATE_FILE.tmp" 2>/dev/null && mv -f "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
}
