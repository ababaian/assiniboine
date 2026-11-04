#!/usr/bin/env bash
# Stage 4: fold every in-range record, search it for ribozymes, call rod or not.
#
#   in   $WORK_DIR/04_rod_screen/chunks/chunk_NNN.fa   (made by make_chunks.sh)
#   out  $WORK_DIR/04_rod_screen/results/chunk_NNN.csv  one row per record
#        $WORK_DIR/04_rod_screen/logs/chunk_NNN.log      the classifier's output
#        $WORK_DIR/04_rod_screen/summary.txt
#
# The screen itself is the external classifier in [screen] lebowski_dir
# (docs/dependencies.md): getorf on the doubled sequence, RNAfold --circ,
# cmsearch against dvr5 and the Rfam ribozyme models, then the rodnotrod
# random forest. This script only feeds it chunks, COMPUTE_SCREEN_WORKERS at
# a time, and checks what comes back.
#
# A chunk counts as done only when its CSV has exactly one row per record.
# That equality is the only thing that catches RNAfold stopping early on an
# oversized sequence: it exits 0 having emitted nothing further, and the
# classifier reports success.
#
# Each chunk gets a private Rfam cache seeded from the bundle's CM/RF*.cm
# files: the classifier rebuilds and re-indexes its combined library on every
# start, so two workers sharing a cache directory would collide.
#
# Resume-safe: re-running skips chunks with a logs/chunk_NNN.done marker and
# redoes the rest.

source "$(dirname "$0")/../common.sh"

OUT=$WORK_DIR/04_rod_screen
LEBOWSKI=$SCREEN_LEBOWSKI_DIR
PIPELINE=$LEBOWSKI/Scripts/run_pipeline.py
MODEL=$LEBOWSKI/rodnotrod_model/model.pkl
DVR5_CM=$LEBOWSKI/CM/dvr5.cm

if stage_is_done "$OUT"; then
    log "stage 4 already done, skipping"
    exit 0
fi
for path in "$PIPELINE" "$MODEL" "$DVR5_CM"; do
    require_file "$path" "unpack the Lebowski bundle at [screen] lebowski_dir (docs/dependencies.md)"
done
[ "$(ls "$LEBOWSKI"/CM/RF*.cm 2> /dev/null | wc -l)" -gt 0 ] || die "no Rfam models in $LEBOWSKI/CM"
require_command python3 RNAfold cmsearch cmpress getorf

if [ "$(ls "$OUT"/chunks/chunk_*.fa 2> /dev/null | wc -l)" -eq 0 ]; then
    "$(dirname "$0")/make_chunks.sh"
fi
mkdir -p "$OUT"/{results,logs,rfam_cache}
rm -f "$OUT/FAILED.txt"

screen_chunk() {
    local chunk=$1 name cache status
    name=$(basename "$chunk" .fa)
    [ -e "$OUT/logs/$name.done" ] && return 0

    cache=$OUT/rfam_cache/$name
    mkdir -p "$cache"
    cp "$LEBOWSKI"/CM/RF*.cm "$cache/"

    python3 "$PIPELINE" \
        --input "$chunk" --output "$OUT/results/$name.csv" \
        --lib-dir "$LEBOWSKI/Scripts" --circular \
        --model "$MODEL" --dvr5-cm "$DVR5_CM" --rfam-cache-dir "$cache" \
        --jobs "$COMPUTE_SCREEN_THREADS" --cmsearch-cpu "$COMPUTE_SCREEN_THREADS" \
        --batch-size "$COMPUTE_SCREEN_BATCH_SIZE" \
        > "$OUT/logs/$name.log" 2>&1
    status=$?
    rm -rf "$cache"

    if [ $status -eq 0 ] && assiniboine validate screen "$chunk" "$OUT/results/$name.csv" >> "$OUT/logs/$name.log" 2>&1; then
        touch "$OUT/logs/$name.done"
        echo "ok   $name"
    else
        echo "$name  exit=$status  $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$OUT/FAILED.txt"
        echo "FAIL $name (see $OUT/logs/$name.log)"
    fi
}
export -f screen_chunk
export OUT LEBOWSKI PIPELINE MODEL DVR5_CM COMPUTE_SCREEN_THREADS COMPUTE_SCREEN_BATCH_SIZE

total=$(ls "$OUT"/chunks/chunk_*.fa | wc -l)
log "screening $total chunks with $COMPUTE_SCREEN_WORKERS workers x $COMPUTE_SCREEN_THREADS threads"
ls "$OUT"/chunks/chunk_*.fa | xargs -P "$COMPUTE_SCREEN_WORKERS" -I{} bash -c 'screen_chunk "$1"' _ {}

done_count=$(ls "$OUT"/logs/chunk_*.done 2> /dev/null | wc -l)
{
    echo "chunks completed  $done_count / $total"
    echo "result rows       $(cat "$OUT"/results/chunk_*.csv 2> /dev/null | grep -vc '^sample_name')"
    if [ -s "$OUT/FAILED.txt" ]; then
        echo "failed chunks (re-run this stage to retry them):"
        sed 's/^/  /' "$OUT/FAILED.txt"
    fi
} | tee "$OUT/summary.txt"

[ "$done_count" -eq "$total" ] || die "$((total - done_count)) chunks are not done; re-run to retry them"
mark_done "$OUT"
