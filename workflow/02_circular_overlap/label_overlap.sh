#!/usr/bin/env bash
# Stage 2: label how each record closes and trim the circular overlap.
#
#   in   $WORK_DIR/01_kraken_filter/unclassified/part_NNN.fa
#   out  $WORK_DIR/02_circular_overlap/labelled/part_NNN.fa
#        $WORK_DIR/02_circular_overlap/summary.txt
#
# Every record comes out, with "ovl:<class> trim:<nt>" added to its header:
# circular records lose their trailing [overlap] length bases, hairpin and
# unmatched records are passed through. The rule is in
# src/assiniboine/topology.py; this script only runs it on each part.

source "$(dirname "$0")/../common.sh"

IN=$WORK_DIR/01_kraken_filter
OUT=$WORK_DIR/02_circular_overlap

if stage_is_done "$OUT"; then
    log "stage 2 already done, skipping"
    exit 0
fi
require_done "$IN" "run stage 1 first"
mkdir -p "$OUT"/{labelled,counts}

log "labelling with $COMPUTE_PART_WORKERS workers, overlap $OVERLAP_LENGTH nt"
part_names "$IN/unclassified" \
    | xargs -P "$COMPUTE_PART_WORKERS" -I{} \
        assiniboine label-overlap --overlap "$OVERLAP_LENGTH" \
            --counts "$OUT/counts/{}.tsv" "$IN/unclassified/{}.fa" "$OUT/labelled/{}.fa"

assiniboine sum-counts "$OUT"/counts/part_*.tsv | tee "$OUT/summary.txt"
mark_done "$OUT"
