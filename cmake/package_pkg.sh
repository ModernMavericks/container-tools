#!/bin/sh
# Assemble the (unsigned) container-tools product .pkg: the docker CLI + Compose + Machine binaries,
# the boot2docker.iso, and the Sparkle updater (app + shim + daily LaunchAgent), with a hard 10.9.5
# install floor. Signing + appcast happen separately (shared sign_and_appcast.sh) in the release
# workflow; this script only builds the .pkg.
#
# Product-specific payload layout lives HERE; the generic mechanics (updater staging, the OS-floor
# product archive) come from mavericks-shared-cmake via $MSC_SCRIPTS. Prints the .pkg path on stdout.
#
# Usage:
#   package_pkg.sh --out PKG --version V --docker BIN --compose BIN --machine BIN --iso ISO \
#     --updater-app APP.app --bootstrap BIN --common FILE --ctl BIN --migrate BIN --menubar-app APP.app \
#     --launch-agent PLIST [--msc-scripts DIR] [--resources DIR --welcome FILE]
set -eu
export COPYFILE_DISABLE=1

OUT=""; VER=""; DOCKER=""; COMPOSE=""; MACHINE=""; LAZY=""; ISO=""; UPD_APP=""; DOCKED=""; SYNC=""
BOOT=""; COMMON=""; CTL=""; MIGRATE=""; MENUBAR=""; LAUNCHAGENT=""
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
    --bootstrap) BOOT="$2"; shift 2;;
    --common) COMMON="$2"; shift 2;;
    --ctl) CTL="$2"; shift 2;;
    --migrate) MIGRATE="$2"; shift 2;;
    --menubar-app) MENUBAR="$2"; shift 2;;
    --launch-agent) LAUNCHAGENT="$2"; shift 2;;
    --msc-scripts) MSC="$2"; shift 2;;
    --resources) RES="$2"; shift 2;;
    --welcome) WELCOME="$2"; shift 2;;
    *) echo "package_pkg: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$OUT" ] && [ -n "$VER" ] && [ -n "$DOCKER" ] && [ -n "$COMPOSE" ] && [ -n "$MACHINE" ] \
  && [ -n "$LAZY" ] && [ -n "$ISO" ] && [ -n "$UPD_APP" ] && [ -n "$DOCKED" ] && [ -n "$SYNC" ] \
  && [ -n "$BOOT" ] && [ -n "$COMMON" ] && [ -n "$CTL" ] && [ -n "$MIGRATE" ] && [ -n "$MENUBAR" ] && [ -n "$LAUNCHAGENT" ] \
  || { echo "package_pkg: need --out --version --docker --compose --machine --lazydocker --iso --updater-app --docked --sync-helper --bootstrap --common --ctl --migrate --menubar-app --launch-agent" >&2; exit 2; }
[ -n "$MSC" ] || { echo "package_pkg: MSC_SCRIPTS unset (install mavericks-shared-cmake, or pass --msc-scripts)" >&2; exit 2; }
for f in "$DOCKER" "$COMPOSE" "$MACHINE" "$LAZY" "$ISO" "$DOCKED" "$SYNC" "$BOOT" "$COMMON" "$CTL" "$MIGRATE" "$LAUNCHAGENT"; do [ -f "$f" ] || { echo "package_pkg: missing input: $f" >&2; exit 1; }; done
[ -d "$UPD_APP" ] || { echo "package_pkg: no updater .app: $UPD_APP" >&2; exit 1; }
[ -d "$MENUBAR" ] || { echo "package_pkg: no menubar .app: $MENUBAR" >&2; exit 1; }
for h in stage_updater.sh set_install_floor.sh; do
  [ -f "$MSC/$h" ] || { echo "package_pkg: shared helper missing: $MSC/$h" >&2; exit 1; }
done

IDENT="dev.modernmavericks.container-tools"
AGENT_LABEL="dev.modernmavericks.container-tools-updatecheck"
UPD_APPDIR="/Library/Application Support/ModernMavericks"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-pkg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
stage="$WORK/stage"; scripts="$WORK/scripts"; comp="$WORK/component.pkg"

# --- product payload (docker CLI + plugins + iso) ---
mkdir -p "$stage/usr/local/bin" "$stage/usr/local/lib/docker/cli-plugins" "$stage/usr/local/share/modernmavericks/container-tools"
install -m 0755 "$DOCKER"  "$stage/usr/local/bin/docker"
install -m 0755 "$MACHINE" "$stage/usr/local/bin/docker-machine"
install -m 0755 "$LAZY"    "$stage/usr/local/bin/lazydocker"
install -m 0755 "$DOCKED"  "$stage/usr/local/bin/docked"
install -m 0755 "$SYNC"    "$stage/usr/local/bin/container-tools-sync-image"
install -m 0755 "$BOOT"    "$stage/usr/local/bin/docker-machine-bootstrap"
install -m 0755 "$CTL"    "$stage/usr/local/bin/docker-machine-ctl"
install -m 0755 "$MIGRATE" "$stage/usr/local/bin/docker-machine-migrate"
mkdir -p "$stage/usr/local/libexec/modernmavericks/docker"
install -m 0644 "$COMMON" "$stage/usr/local/libexec/modernmavericks/docker/docker-machine-common.sh"
# Compose v2 as a CLI plugin (enables `docker compose`), plus a standalone `docker-compose` symlink.
install -m 0755 "$COMPOSE" "$stage/usr/local/lib/docker/cli-plugins/docker-compose"
ln -s ../lib/docker/cli-plugins/docker-compose "$stage/usr/local/bin/docker-compose"
install -m 0644 "$ISO"    "$stage/usr/local/share/modernmavericks/container-tools/boot2docker.iso"
mkdir -p "$stage/Applications"
cp -R "$MENUBAR" "$stage/Applications/Mavericks Container Tools.app"

# Optional VM auto-start: a per-user LaunchAgent (ships Disabled) driving the bootstrap helper.
# Off by default -- the user turns it on with `launchctl load -w`. root:wheel 0644 so launchd accepts it.
mkdir -p "$stage/Library/LaunchAgents"
install -m 0644 "$LAUNCHAGENT" "$stage/Library/LaunchAgents/dev.modernmavericks.container-tools-machine.plist"

# --- updater app + LaunchAgent + postinstall (shared, hoisted) ---
sh "$MSC/stage_updater.sh" --stage "$stage" --app "$UPD_APP" --app-dir "$UPD_APPDIR" \
  --agent-label "$AGENT_LABEL" --scripts-out "$scripts"

# stage_updater.sh's generated postinstall ends with `exit 0`; drop a trailing standalone
# one so the launch below runs, then re-add exit 0 at the very end. Robust if it changes.
[ -f "$scripts/postinstall" ] || printf '#!/bin/sh\n' > "$scripts/postinstall"
sed -i '' -e '${/^[[:space:]]*exit 0[[:space:]]*$/d;}' "$scripts/postinstall"
cat >> "$scripts/postinstall" <<'POST'
# Converge on the renamed bundle. The .pkg lays down "/Applications/Mavericks Container Tools.app",
# but installing over a pre-rename box leaves the old "/Applications/Container Tools for Mavericks.app"
# behind -- still the running menu-bar process and still the registered Login Item (MDLoginItem keys
# on the bundle URL) -- so the user keeps seeing the old name. Stop the old process and remove its
# bundle (identity-checked, so an unrelated app is never touched) before (re)launching the new one,
# which re-registers the Login Item at the new path.
_uid=$(stat -f %u /dev/console 2>/dev/null)
if [ -n "$_uid" ] && [ "${_uid:-0}" -gt 0 ]; then
  # Match the executable name (unchanged across the rename), NOT the .app path, so this also stops a
  # menu-bar app still running from the old bundle. Graceful TERM, then a guaranteed KILL.
  MENU_EXE='Contents/MacOS/DockerMenu'
  pkill -TERM -U "$_uid" -f "$MENU_EXE" 2>/dev/null || true
  sleep 1
  pkill -KILL -U "$_uid" -f "$MENU_EXE" 2>/dev/null || true
  # One-time cleanup of the pre-rename bundle, but ONLY if it is ours (identity-checked, so we never
  # delete an unrelated /Applications/Container Tools for Mavericks.app) AND only once the new bundle
  # is actually in place. The [ -d "$NEW_APP" ] guard is the safety belt: if bundle relocation ever
  # writes the payload back onto OLD_APP (leaving NEW_APP absent), removing OLD_APP would delete the
  # app we just installed -- the exact failure that emptied /Applications on the .12 install.
  NEW_APP="/Applications/Mavericks Container Tools.app"
  OLD_APP="/Applications/Container Tools for Mavericks.app"
  if [ -d "$NEW_APP" ] && [ "$OLD_APP" != "$NEW_APP" ] && [ -d "$OLD_APP" ] && \
     [ "$(defaults read "$OLD_APP/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "dev.modernmavericks.DockerMenu" ]; then
    rm -rf "$OLD_APP"
  fi
  # Launch the (new) menu-bar app as the console user so it registers its Login Item and appears
  # immediately (installer runs as root).
  launchctl asuser "$_uid" open -a "/Applications/Mavericks Container Tools.app" >/dev/null 2>&1 || true
fi
exit 0
POST
chmod +x "$scripts/postinstall"

# --- flat component pkg over the whole payload, with the agent-loading postinstall ---
# Strip AppleDouble sidecars copied in from the (NFS) source tree. NOTE: macOS 26 stamps an
# UNREMOVABLE com.apple.provenance xattr on every Mach-O, and pkgbuild encodes each as a ._ payload
# entry -- unavoidable, and identical to golang/swift's shipped pkgs. Those merge back into inert
# xattrs when Installer extracts onto the 10.9 box's HFS+, so no ._ FILES land on the target.
find "$stage" -name '._*' -delete 2>/dev/null || true
# Disable bundle relocation. Otherwise PackageKit sees the menu-bar app's CFBundleIdentifier already
# registered at a DIFFERENT path (e.g. a pre-rename "/Applications/Container Tools for Mavericks.app")
# and RELOCATES the payload back onto it -- "Mavericks Container Tools.app relocated to Container Tools
# for Mavericks.app" in install.log -- so the declared install path is silently ignored and the rename
# never lands. A component plist with BundleIsRelocatable=false on every bundle forces each to install
# at its RootRelativeBundlePath. --analyze lists one dict per bundle; flip them all.
cplist="$WORK/component.plist"
pkgbuild --analyze --root "$stage" "$cplist" >&2
_i=0
while /usr/libexec/PlistBuddy -c "Print :${_i}:BundleIsRelocatable" "$cplist" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :${_i}:BundleIsRelocatable false" "$cplist" >&2
  _i=$((_i + 1))
done
pkgbuild --root "$stage" --component-plist "$cplist" --identifier "$IDENT" --version "$VER" \
         --scripts "$scripts" --install-location / "$comp" >&2

# --- product archive with the 10.9.5 OS floor (shared helper) ---
lic=""; [ -n "$WELCOME" ] && lic="--welcome $WELCOME"
resflag=""; [ -n "$RES" ] && resflag="--resources $RES"
sh "$MSC/set_install_floor.sh" \
  --identifier "$IDENT" \
  --title "Container Tools for Mavericks $VER" \
  --component "$comp" --out "$OUT" \
  $resflag $lic --require-scripts --host-arch x86_64 >&2

echo "$OUT"
