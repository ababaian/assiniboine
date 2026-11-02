#!/usr/bin/env bash
# Split the selfloops archive into the 21 parts stage 1 used, so later steps can
# work on parts in parallel. Stage 1 cut parts at 45,000,000 records, and every
# record is exactly 2 lines, so a part is 90,000,000 lines.
#
#   split_source.sh <selfloops.v1.1.fa.zst> <outdir>
#     -> <outdir>/part_000.fa.zst ... part_020.fa.zst, then <outdir>/SPLIT.DONE
#
# Parts are zstd -1 to keep the temporary copy near 100 GB instead of 330 GB.
set -uo pipefail
SRC=${1:?source .fa.zst}
OUT=${2:?output dir}
mkdir -p "$OUT"
[ -e "$OUT/SPLIT.DONE" ] && { echo "already split: $OUT"; exit 0; }
rm -f "$OUT"/part_*.fa.zst

zstd -dc "$SRC" | split -d -a3 -l 90000000 \
    --filter='zstd -q -1 -T4 -o "$FILE.fa.zst"' - "$OUT/part_"
st=("${PIPESTATUS[@]}")
[ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] || { echo "split failed: zstd=${st[0]} split=${st[1]}"; exit 1; }
n=$(ls "$OUT"/part_*.fa.zst | wc -l)
[ "$n" = 21 ] || { echo "expected 21 parts, got $n"; exit 1; }
touch "$OUT/SPLIT.DONE"
echo "split into $n parts"
