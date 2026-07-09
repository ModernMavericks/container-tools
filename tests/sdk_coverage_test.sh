#!/bin/sh
# Every undefined import of the docker binary must be provided by the pinned 10.9
# SDK stubs, or be on the weak allowlist.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="${1:-$ROOT/build/docker-cli/docker}"
[ -x "$BIN" ] || { echo "build docker-cli first (cmake --build <dir>)" >&2; exit 1; }
sh "$ROOT/cmake/sdk_coverage.sh" "$BIN"
echo "sdk_coverage_test: OK"
