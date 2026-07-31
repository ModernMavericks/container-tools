#!/bin/sh
# renovate.json (under .github/ since 777814d) is valid JSON and declares a
# customManager for components/*/version.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 -c "import json,sys; json.load(open('$ROOT/.github/renovate.json'))" \
  || { echo "renovate.json invalid JSON" >&2; exit 1; }
grep -q 'components/.*/version' "$ROOT/.github/renovate.json" \
  || { echo "renovate.json does not track component version files" >&2; exit 1; }
# UPSTREAM_VERSION is the committed input the version derives from. VERSION is NOT checked here: it
# is a build product (gitignored), so requiring it would fail on a fresh clone -- and the committed
# copy this replaces is precisely what drifted to .2 while releases were at .14.
[ -s "$ROOT/UPSTREAM_VERSION" ] || { echo "UPSTREAM_VERSION missing/empty" >&2; exit 1; }
echo "renovate_test: OK"
