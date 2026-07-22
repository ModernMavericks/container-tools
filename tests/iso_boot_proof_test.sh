#!/bin/sh
# iso_boot_proof.sh honors the loud-skip contract: exit 77 when it cannot boot.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BP="$ROOT/cmake/iso_boot_proof.sh"
[ -f "$BP" ] || { echo "missing $BP" >&2; exit 1; }
sh -n "$BP"
# Forced skip must exit exactly 77 (ctest SKIP_RETURN_CODE), regardless of host.
set +e
MAVERICKS_DOCKER_FORCE_SKIP=1 sh "$BP" /nonexistent.iso >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 77 ] || { echo "expected exit 77 on forced skip, got $rc" >&2; exit 1; }
echo "iso_boot_proof_test: OK"
