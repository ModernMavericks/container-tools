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

# Menu-bar glyph derives from the container art, NOT a whale (updater/ICON-CREDIT.txt),
# is a template image (inverts on light/dark menu bars), and encodes four VM states.
AD="$ROOT/menubar/AppDelegate.m"
if grep -qi 'whale' "$AD"; then fail "menu-bar glyph must not be a whale (see updater/ICON-CREDIT.txt)"; fi
if grep -qi 'docker mark' "$AD"; then fail "menu-bar glyph must not imitate the Docker mark"; fi
grep -qi 'container' "$AD" || fail "menu-bar glyph must draw a container"
grep -q 'template = YES' "$AD" || fail "menu-bar glyph must be a template image"
grep -q '"no-fusion"' "$AD" || fail "glyph must distinguish needs-attention states (no-fusion/absent/error)"

# On-demand "Check for Updates" hands off to the bundled Sparkle updater with --user
# (interactive check) — the same executable the daily LaunchAgent runs with --background.
grep -q 'Check for Updates' "$AD" || fail "menu must offer 'Check for Updates'"
grep -q 'ContainerToolsUpdater.app/Contents/MacOS/ContainerToolsUpdater' "$AD" \
  || fail "'Check for Updates' must launch the bundled updater executable"
grep -q '"--user"' "$AD" || fail "'Check for Updates' must run the updater with --user (interactive)"

grep -q -- '--menubar-app' "$ROOT/cmake/package_pkg.sh" || fail "package_pkg.sh needs --menubar-app"
grep -q 'Applications/Container Tools for Mavericks.app' "$ROOT/cmake/package_pkg.sh" \
  || fail "package_pkg.sh must install the app to /Applications"
grep -q 'asuser' "$ROOT/cmake/package_pkg.sh" || fail "postinstall must launch the app as the console user"

grep -q -- '--menubar-app' "$ROOT/.github/workflows/release.yml" || fail "release.yml must pass --menubar-app"
grep -q 'cmake -S menubar' "$ROOT/.github/workflows/release.yml" || fail "release.yml must build the menubar app"

echo "docker_menubar_test: OK"
