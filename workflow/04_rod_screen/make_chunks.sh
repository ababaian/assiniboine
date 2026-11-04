#!/usr/bin/env bash
# Stage 4, first half: cut the in-range records into chunks for the screen.
#
#   in   $WORK_DIR/03_length_filter/in_range/part_NNN.fa
#   out  $WORK_DIR/04_rod_screen/chunks/chunk_NNN.fa
#
# The parts are concatenated and re-cut into chunks of COMPUTE_RECORDS_PER_CHUNK
# records, so that a crash costs one chunk's work rather than the whole run.
# Cutting on a line count is only safe when every record is exactly two
# lines, which stages 2 and 3 guarantee and this script checks anyway.
#
# Defining a new chunk set invalidates the bookkeeping of an earlier one, so
# this script refuses to run while chunks or results from a previous screen
# exist. rod_screen.sh calls it when the chunk directory is empty.

source "$(dirname "$0")/../common.sh"

IN=$WORK_DIR/03_length_filter
OUT=$WORK_DIR/04_rod_screen

require_done "$IN" "run stage 3 first"
mkdir -p "$OUT"/{chunks,results,logs}

[ "$(ls "$OUT"/chunks/chunk_*.fa 2> /dev/null | wc -l)" -eq 0 ] \
    || die "$OUT/chunks is not empty. Remove it by hand if you mean to re-chunk."
[ "$(ls "$OUT"/results/chunk_*.csv 2> /dev/null | wc -l)" -eq 0 ] \
    || die "$OUT/results holds results from an earlier chunk set. Move or delete them before re-chunking."
rm -f "$OUT"/logs/chunk_*.done "$OUT/FAILED.txt"

for part in "$IN"/in_range/part_*.fa; do
    if [ $(( $(wc -l < "$part") % 2 )) -ne 0 ]; then
        die "$part has an odd number of lines; it is not two lines per record"
    fi
done

log "chunking into $COMPUTE_RECORDS_PER_CHUNK records per chunk"
cat "$IN"/in_range/part_*.fa \
    | split -d -a 3 -l $((2 * COMPUTE_RECORDS_PER_CHUNK)) --additional-suffix=.fa - "$OUT/chunks/chunk_"

# Every chunk must begin with a header. With two-line records that proves no
# record straddles a chunk boundary.
for chunk in "$OUT"/chunks/chunk_*.fa; do
    [ "$(head -c 1 "$chunk")" = ">" ] || die "$chunk does not start at a record header"
done
log "$(ls "$OUT"/chunks/chunk_*.fa | wc -l) chunks written"
