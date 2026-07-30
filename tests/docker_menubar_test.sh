#!/bin/sh
# Consistency: the menu-bar app is an LSUIElement, and the pkg installs + launches it.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "docker_menubar_test: FAIL: $*" >&2; exit 1; }

grep -q 'LSUIElement' "$ROOT/menubar/Info.plist.in" || fail "app must be LSUIElement (agent)"
grep -q 'dev.modernmavericks.DockerMenu' "$ROOT/menubar/CMakeLists.txt" || fail "bundle id missing"

# App icon derives from the project's shipping-container art (NOT a whale — see
# updater/ICON-CREDIT.txt), single-sourced from updater/ where the .icns is generated.
[ -f "$ROOT/updater/container-tools-updater.icns" ] || fail "container art .icns missing"
grep -q 'CFBundleIconFile' "$ROOT/menubar/Info.plist.in" || fail "Info.plist must declare CFBundleIconFile"
grep -q 'MACOSX_BUNDLE_ICON_FILE' "$ROOT/menubar/CMakeLists.txt" || fail "CMake must set MACOSX_BUNDLE_ICON_FILE"
grep -q 'container-tools-updater.icns' "$ROOT/menubar/CMakeLists.txt" || fail "menubar must bundle the container art .icns"

grep -q -- '--menubar-app' "$ROOT/cmake/package_pkg.sh" || fail "package_pkg.sh needs --menubar-app"
grep -q 'Applications/Container Tools for Mavericks.app' "$ROOT/cmake/package_pkg.sh" \
  || fail "package_pkg.sh must install the app to /Applications"
grep -q 'asuser' "$ROOT/cmake/package_pkg.sh" || fail "postinstall must launch the app as the console user"

grep -q -- '--menubar-app' "$ROOT/.github/workflows/release.yml" || fail "release.yml must pass --menubar-app"
grep -q 'cmake -S menubar' "$ROOT/.github/workflows/release.yml" || fail "release.yml must build the menubar app"

echo "docker_menubar_test: OK"
