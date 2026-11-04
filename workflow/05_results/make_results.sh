#!/usr/bin/env bash
# Stage 5: reduce the screen output to the rod tables and the shortlist.
#
#   in   $WORK_DIR/04_rod_screen/chunks/chunk_NNN.fa + results/chunk_NNN.csv
#   out  $WORK_DIR/05_results/rods.csv                every rod, with its sequence
#        $WORK_DIR/05_results/rods_with_ribozyme.csv  rods with at least one ribozyme
#        $WORK_DIR/05_results/shortlist.csv           two tiers of candidates
#        $WORK_DIR/05_results/summary.txt
#
# Refuses to run until stage 4 has its DONE marker, which is what proves no
# chunk was silently truncated. The rules are in src/assiniboine/results.py.

source "$(dirname "$0")/../common.sh"

IN=$WORK_DIR/04_rod_screen
OUT=$WORK_DIR/05_results

if stage_is_done "$OUT"; then
    log "stage 5 already done, skipping"
    exit 0
fi
require_done "$IN" "finish stage 4 before reducing its output"
mkdir -p "$OUT"

assiniboine results --chunks-dir "$IN/chunks" --results-dir "$IN/results" --out-dir "$OUT" \
    --tier2-min-confidence "$SHORTLIST_TIER2_MIN_CONFIDENCE" --tier2-max-rows "$SHORTLIST_TIER2_MAX_ROWS"
mark_done "$OUT"
