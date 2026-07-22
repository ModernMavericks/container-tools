#!/bin/sh
# emit a characterization of the built binary, then compare it against itself: must be EQUIVALENT.
# Also verify fail-closed: a tampered reference must produce DIVERGENCE (exit 1).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="${1:-$ROOT/build/docker-cli/docker}"
[ -x "$BIN" ] || { echo "build docker-cli first (cmake --build <dir>)" >&2; exit 1; }
REF=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-char.XXXXXX")
TAMPERED=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-char-tamper.XXXXXX")
trap 'rm -rf "$REF" "$TAMPERED"' EXIT   # one handler — a second trap would replace this and leak $REF
sh "$ROOT/cmake/characterize_build.sh" emit "$BIN" "$REF"
sh "$ROOT/cmake/characterize_build.sh" compare "$REF" "$BIN"
# Teeth: a tampered reference must cause DIVERGENCE.
cp "$REF/arch" "$REF/minos" "$REF/gomod" "$TAMPERED/"
printf 'BOGUS_ARCH\n' > "$TAMPERED/arch"
if sh "$ROOT/cmake/characterize_build.sh" compare "$TAMPERED" "$BIN" 2>/dev/null; then
  echo "characterize_test: FAIL: compare accepted tampered reference" >&2; exit 1
fi
echo "characterize_test: OK"
