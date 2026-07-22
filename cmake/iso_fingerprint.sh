#!/bin/sh
# Equivalence gate for a boot2docker ISO. Compares toolchain-INVARIANT version-facts only
# (kernel token, ISO volume label, engine label) -- NOT bytes/timestamps/build-host hash,
# which a from-source rebuild legitimately changes. Portable: strings + dd only.
#   emit    <iso> <out-dir>   : write fingerprint files
#   compare <ref-dir> <iso>   : re-emit + diff vs committed reference
set -eu
. "$(dirname "$0")/common.sh"
export LC_ALL=C

emit() {  # <iso> <out-dir>
  iso=$1; out=$2; mkdir -p "$out"
  [ -f "$iso" ] || mavericks_docker_die "missing iso $iso"
  strings "$iso" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-boot2docker' \
    | sort -u | head -1 > "$out/kernel" || true
  [ -s "$out/kernel" ] || mavericks_docker_die "no kernel token in $iso"
  # PVD volume identifier: 32 bytes at absolute offset 32808 (sector 16 + 40).
  # Capture then printf a single trailing newline: BSD sed appends a newline to
  # unterminated input while GNU sed preserves its absence, so writing sed's output
  # straight to the file made the emitted `label` platform-dependent (the Mac-emitted
  # reference had a trailing newline the Linux re-emit lacked -> spurious DIVERGENCE).
  # $() strips trailing newlines; printf re-adds exactly one, matching kernel/engine
  # (which get theirs from `head`) and the committed reference on every platform.
  label=$(dd if="$iso" bs=1 skip=32808 count=32 2>/dev/null | tr -d '\0' | sed 's/ *$//')
  [ -n "$label" ] || mavericks_docker_die "no volume label in $iso"
  printf '%s\n' "$label" > "$out/label"
  strings "$iso" 2>/dev/null | grep -oE 'b2d-v[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -u | head -1 > "$out/engine" || true
  [ -s "$out/engine" ] || mavericks_docker_die "no engine label in $iso"
}

case "${1:-}" in
  emit)    [ $# -eq 3 ] || { echo "usage: $0 emit <iso> <out-dir>" >&2; exit 64; }
           emit "$2" "$3"; echo "fingerprint written to $3" >&2 ;;
  compare) [ $# -eq 3 ] || { echo "usage: $0 compare <ref-dir> <iso>" >&2; exit 64; }
           ref=$2; iso=$3
           [ -d "$ref" ] || mavericks_docker_die "missing reference dir $ref"
           for f in kernel label engine; do [ -s "$ref/$f" ] || mavericks_docker_die "reference missing $f"; done
           tmp=$(mktemp -d "${TMPDIR:-/tmp}/container-tools-isofp.XXXXXX")
           trap 'rm -rf "$tmp" "$tmp.diff"' EXIT
           emit "$iso" "$tmp"
           if diff -ru "$ref" "$tmp" > "$tmp.diff" 2>&1; then
             echo "EQUIVALENT: $iso matches reference $ref"
           else
             echo "DIVERGENCE: $iso differs from reference $ref" >&2; cat "$tmp.diff" >&2
             # Self-explain: every fact is version-bearing and emit fails closed
             # on malformed ones, so a mismatch here is version-bump-shaped.
             {
               echo ""
               echo "What changed (reference -> this ISO):"
               for f in kernel label engine; do
                 cmp -s "$ref/$f" "$tmp/$f" \
                   || echo "  $f: $(cat "$ref/$f") -> $(cat "$tmp/$f")"
               done
               echo ""
               echo "If the boot2docker pin moved on purpose (e.g. a Renovate bump), the"
               echo "rebuilt ISO is telling the truth and the committed reference is stale."
               echo "Check the new values match the announced upstream release, then:"
               echo "  sh cmake/iso_fingerprint.sh emit <iso> cmake/characterization/boot2docker"
               echo "and commit it together with the updated components/boot2docker/golden.sha256"
               echo "(full flow: README, 'When Renovate bumps boot2docker')."
             } >&2
             exit 1
           fi ;;
  *) echo "usage: $0 emit|compare ..." >&2; exit 64 ;;
esac
