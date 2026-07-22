#!/bin/sh
# Cross-build equivalence gate for a Go binary.
# emit    <binary> <out-dir>   : write toolchain-invariant fingerprint
# compare <ref-dir> <binary>   : re-emit + diff vs committed native-10.9 reference
# Toolchain-INDEPENDENT properties only: arch, min-OS, and Go module versions.
# The undefined-import set is intentionally NOT compared: it legitimately differs
# between the box's native build (gcc12 / old system clang + system SDK) and the CI
# modern-clang cross build (+ fetched SDK) -- e.g. stack-protector and CF/Sec symbols.
# sdk_coverage.sh independently gates that every import is 10.9-available.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd); . "$(dirname "$0")/common.sh"
export LC_ALL=C

emit() {  # <binary> <out-dir>
  bin=$1; out=$2; mkdir -p "$out"
  [ -f "$bin" ] || mavericks_docker_die "missing binary $bin"
  # Pipeline enforces thin x86_64; assert_binary_compatible.sh gates that. $NF is arch name for thin binaries.
  lipo -info "$bin" 2>/dev/null | awk '{print $NF}' > "$out/arch" || mavericks_docker_die "lipo $bin"
  [ -s "$out/arch" ] || mavericks_docker_die "no arch for $bin"
  otool -l "$bin" 2>/dev/null | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&$1=="version"{print $2; exit}' > "$out/minos" || mavericks_docker_die "otool $bin"
  [ -s "$out/minos" ] || mavericks_docker_die "no min-OS for $bin"
  # Go module + toolchain versions: proves same sources across toolchains.
  ( "${GO:-go}" version -m "$bin" 2>/dev/null || go version -m "$bin" 2>/dev/null ) \
    | awk '$1=="path"||$1=="mod"||$1=="dep"{print $2"@"$3}' | sort -u > "$out/gomod" || true
  [ -s "$out/gomod" ] || mavericks_docker_die "no Go module info for $bin (not a Go binary?)"
}

case "${1:-}" in
  emit)    [ $# -eq 3 ] || { echo "usage: $0 emit <binary> <out-dir>" >&2; exit 64; }
           emit "$2" "$3"; echo "characterization written to $3" >&2 ;;
  compare) [ $# -eq 3 ] || { echo "usage: $0 compare <ref-dir> <binary>" >&2; exit 64; }
           ref=$2; bin=$3
           [ -d "$ref" ] || mavericks_docker_die "missing reference dir $ref"
           for f in arch minos gomod; do [ -s "$ref/$f" ] || mavericks_docker_die "reference missing $f"; done
           tmp=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-char.XXXXXX")
           trap 'rm -rf "$tmp" "$tmp.diff"' EXIT
           emit "$bin" "$tmp"
           if diff -ru "$ref" "$tmp" > "$tmp.diff" 2>&1; then
             echo "EQUIVALENT: $bin matches reference $ref"
           else
             echo "DIVERGENCE: $bin differs from reference $ref" >&2; cat "$tmp.diff" >&2; exit 1
           fi ;;
  *) echo "usage: $0 emit|compare ..." >&2; exit 64 ;;
esac
