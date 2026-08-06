#!/bin/sh
# Static assertions for the auto-setup wiring: agent ships enabled+silent, postinstall loads it
# per-user (no -w), and the get-fusion helper is installed.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "auto_setup_test: FAIL: $*" >&2; exit 1; }

PLIST="$ROOT/payload/dev.modernmavericks.container-tools-machine.plist"

# Agent must NOT ship Disabled=true (it must auto-enable), and must run bootstrap silently.
if grep -A1 '<key>Disabled</key>' "$PLIST" | grep -q '<true/>'; then
  fail "LaunchAgent still ships Disabled=true (must be enabled by default)"
fi
grep -q 'MAVERICKS_DOCKER_NONINTERACTIVE' "$PLIST" || fail "agent must set MAVERICKS_DOCKER_NONINTERACTIVE (silent create)"
grep -q '<key>RunAtLoad</key>' "$PLIST" || fail "agent must keep RunAtLoad"
grep -q '<key>StartInterval</key>' "$PLIST" || fail "agent must keep StartInterval"

PKG="$ROOT/cmake/package_pkg.sh"
# The assembled postinstall must load the machine agent for the console user, WITHOUT -w
# (so a user's explicit login-off opt-out survives upgrades).
grep -q 'launchctl asuser "\$_uid" load' "$PKG" \
  || fail "postinstall must 'launchctl asuser \$_uid load' the machine agent"
grep -q 'container-tools-machine.plist' "$PKG" \
  || fail "postinstall must reference the machine LaunchAgent plist"
if grep -q 'launchctl asuser "\$_uid" load -w' "$PKG"; then
  fail "postinstall must NOT use 'load -w' (that would stomp an explicit opt-out)"
fi

echo "auto_setup_test: OK"
