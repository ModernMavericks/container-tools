#!/bin/sh
# On CI, the script prints a valid SDK root. On the box, it is a no-op that
# prints the system SDK path (xcrun unavailable -> prints empty, which the test
# tolerates only on the box). This test only checks the pin, not a live fetch.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/cmake/common.sh"
[ -x "$ROOT/cmake/fetch_10_9_sdk.sh" ] || { echo "fetch_sdk_test: script missing" >&2; exit 1; }
grep -q 'fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0' "$ROOT/cmake/fetch_10_9_sdk.sh" \
  || { echo "fetch_sdk_test: pinned SHA-256 absent" >&2; exit 1; }
echo "fetch_sdk_test: pinned SDK present OK"
