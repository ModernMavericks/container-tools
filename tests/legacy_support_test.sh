#!/bin/sh
# Assert the CMake-built shim archive exports the backfill symbols and no notify stub.
set -eu
A=${1:?usage: legacy_support_test.sh <path-to-libMacportsLegacySupport.a>}
[ -f "$A" ] || { echo "missing $A" >&2; exit 1; }
for sym in _clock_gettime _openat _utimensat; do
  nm "$A" 2>/dev/null | grep -q "T $sym$" || { echo "shim lacks $sym" >&2; exit 1; }
done
nm "$A" 2>/dev/null | grep -q notify_is_valid_token && { echo "shim unexpectedly defines notify" >&2; exit 1; }
echo "legacy_support_test: OK"
