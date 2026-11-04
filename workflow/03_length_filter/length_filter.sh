#!/usr/bin/env bash
# Stage 3: keep the records between [length] min_nt and max_nt, inclusive.
#
#   in   $WORK_DIR/02_circular_overlap/labelled/part_NNN.fa
#   out  $WORK_DIR/03_length_filter/in_range/part_NNN.fa    goes on to stage 4
#        $WORK_DIR/03_length_filter/too_short/part_NNN.fa   parked
#        $WORK_DIR/03_length_filter/too_long/part_NNN.fa    parked
#        $WORK_DIR/03_length_filter/summary.txt
#
# Nothing is deleted: the out-of-range records are kept so either bound can
# be revisited without re-running stage 1. The rule is in
# src/assiniboine/filtering.py.

source "$(dirname "$0")/../common.sh"

IN=$WORK_DIR/02_circular_overlap
OUT=$WORK_DIR/03_length_filter

if stage_is_done "$OUT"; then
    log "stage 3 already done, skipping"
    exit 0
fi
require_done "$IN" "run stage 2 first"
mkdir -p "$OUT/counts"

log "filtering to $LENGTH_MIN_NT-$LENGTH_MAX_NT nt with $COMPUTE_PART_WORKERS workers"
part_names "$IN/labelled" \
    | xargs -P "$COMPUTE_PART_WORKERS" -I{} \
        assiniboine length-filter --min-length "$LENGTH_MIN_NT" --max-length "$LENGTH_MAX_NT" \
            --out-dir "$OUT" --name {} --counts "$OUT/counts/{}.tsv" "$IN/labelled/{}.fa"

assiniboine sum-counts "$OUT"/counts/part_*.tsv | tee "$OUT/summary.txt"
mark_done "$OUT"
