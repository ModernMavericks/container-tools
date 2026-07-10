#!/bin/sh
# Fetch + cache + checksum-verify MacOSX10.9.sdk. Prints the SDK root on stdout.
# Cross builds link against it; sdk_coverage verifies against it on box and CI
# alike. Cache default is per-machine and durable: TMPDIR gets purged by macOS
# (stranding the path CMake cached at configure), and the repo tree lives on
# NFS, where per-link stub reads and shared box/CI state would both hurt.
set -eu
CACHE="${MVD_SDK_CACHE:-$HOME/Library/Caches/mavericks-docker}"
URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.9.sdk.tar.xz"
SHA="fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0"
SDK="$CACHE/MacOSX10.9.sdk"
mkdir -p "$CACHE"
if [ ! -d "$SDK" ]; then
  TARBALL="$CACHE/MacOSX10.9.sdk.tar.xz"
  [ -f "$TARBALL" ] || curl -sL --fail -o "$TARBALL" "$URL"
  echo "$SHA  $TARBALL" | shasum -a 256 -c - >&2
  tar xf "$TARBALL" -C "$CACHE"
  # Modern ld (Xcode 15+) emits a deprecation warning for every ancient
  # MH_DYLIB_STUB stub it reads. Where tapi exists (modern host; never the 10.9
  # box), convert those stubs to .tbd once at extract time: same exported
  # symbols, no warnings. The box's gates read unconverted stubs via nm.
  if TAPI=$(xcrun --find tapi 2>/dev/null); then
    LIBDIRS="$SDK/usr/lib $SDK/System/Library/Frameworks"
    find $LIBDIRS -type f \( -name '*.dylib' -o ! -name '*.*' \) | while IFS= read -r f; do
      [ "$(otool -h "$f" 2>/dev/null | awk 'NR==4 {print $5}')" = 9 ] || continue
      # Pin tbd-v4 (YAML): the default v5 is JSON, which sdk_coverage can't parse.
      "$TAPI" stubify --filetype=tbd-v4 --delete-input-file "$f" 2>/dev/null || :  # unconvertible: keep stub
    done
    # Re-point symlinks whose target was converted. Loop to fixpoint: chains
    # like libc.dylib -> libSystem.dylib -> libSystem.B.dylib need two passes.
    changed=1
    while [ "$changed" = 1 ]; do
      changed=0
      for l in $(find $LIBDIRS -type l); do
        [ -e "$l" ] && continue
        t=$(readlink "$l")
        case "$l" in *.dylib) new_l="${l%.dylib}.tbd" ;; *) new_l="$l.tbd" ;; esac
        case "$t" in *.dylib) new_t="${t%.dylib}.tbd" ;; *) new_t="$t.tbd" ;; esac
        case "$new_t" in /*) tgt="$SDK$new_t" ;; *) tgt="$(dirname "$l")/$new_t" ;; esac
        [ -e "$tgt" ] || continue
        ln -sf "$new_t" "$new_l"
        rm "$l"
        changed=1
      done
    done
  fi
fi
[ -d "$SDK/usr/lib" ] || { echo "SDK missing usr/lib: $SDK" >&2; exit 1; }
echo "$SDK"
