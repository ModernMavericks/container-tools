#!/bin/sh
# iso_fingerprint.sh emit/compare on a crafted fixture (no real ISO needed).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FP="$ROOT/cmake/iso_fingerprint.sh"
[ -f "$FP" ] || { echo "missing $FP" >&2; exit 1; }
sh -n "$FP"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-fptest.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
iso="$tmp/fake.iso"
# 40KB of zeros, then version tokens near the end (strings-greppable).
dd if=/dev/zero of="$iso" bs=1024 count=40 2>/dev/null
printf '5.15.112-boot2docker b2d-v20.10.24\n' | dd of="$iso" bs=1 seek=36000 conv=notrunc 2>/dev/null
# Volume label at PVD offset 32808.
printf 'b2d-v20.10.24' | dd of="$iso" bs=1 seek=32808 conv=notrunc 2>/dev/null
# emit -> ref
sh "$FP" emit "$iso" "$tmp/ref"
for f in kernel label engine; do
  [ -s "$tmp/ref/$f" ] || { echo "emit missing $f" >&2; exit 1; }
done
grep -q '5.15.112-boot2docker' "$tmp/ref/kernel" || { echo "bad kernel emit" >&2; exit 1; }
grep -q 'b2d-v20.10.24'        "$tmp/ref/label"  || { echo "bad label emit" >&2; exit 1; }
# compare identical -> EQUIVALENT (exit 0)
sh "$FP" compare "$tmp/ref" "$iso" || { echo "expected EQUIVALENT" >&2; exit 1; }
# mutate kernel token -> DIVERGENCE (nonzero)
iso2="$tmp/fake2.iso"; cp "$iso" "$iso2"
printf '5.15.999-boot2docker' | dd of="$iso2" bs=1 seek=36000 conv=notrunc 2>/dev/null
if out=$(sh "$FP" compare "$tmp/ref" "$iso2" 2>&1); then
  echo "expected DIVERGENCE on mutated kernel" >&2; exit 1
fi
# divergence self-explains: per-fact old -> new, and the re-baseline flow
echo "$out" | grep -q 'kernel: 5.15.112-boot2docker -> 5.15.999-boot2docker' \
  || { echo "divergence missing old -> new summary" >&2; exit 1; }
echo "$out" | grep -q 'iso_fingerprint.sh emit' \
  || { echo "divergence missing re-baseline command" >&2; exit 1; }
echo "$out" | grep -q 'golden.sha256' \
  || { echo "divergence missing golden.sha256 reminder" >&2; exit 1; }
echo "iso_fingerprint_test: OK"
