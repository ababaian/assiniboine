#!/usr/bin/env bash
# Overnight companion to run_all.sh. Does not touch the running driver or workers.
#   1. waits for the Kraken2 calls rerun, so k2 goes first and its cores free up
#   2. adds 4 screen workers on the idle cores, which stop claiming with 16 chunks
#      unclaimed so that run.sh normally outlasts them and writes SCREEN.DONE itself
#   3. backstop: if the driver ends without RUN_ALL.DONE (an extra worker outlasted
#      run.sh, or a chunk went BAD), re-run run.sh to finish it, then step 5.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
LEB=$ROOT/Lebowski
DRIVER=1237137
cd "$ROOT"
source /opt/miniconda3/etc/profile.d/conda.sh
conda activate circpipe
NPROC=4
J=22
RESERVE=16
K=01_kraken_filter/classified
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }

say "waiting for Kraken2 calls"
until [ -e "$K/CALLS.DONE" ] || [ -e "$K/CALLS.FAILED" ]; do sleep 60; done
say "calls: $(ls $K | grep -E '^CALLS\.')"

unclaimed(){ n=0; for c in 04_rod_screen/chunks/chunk_*; do
    [ -d "04_rod_screen/claims/$(basename "$c")" ] || n=$((n+1)); done; echo "$n"; }

process_chunk() {
    c="$1"; b=$(basename "$c")
    [ "$(unclaimed)" -gt "$RESERVE" ] || return 0
    [ -e "04_rod_screen/logs/$b.done" ] && return 0
    mkdir "04_rod_screen/claims/$b" 2>/dev/null || return 0
    cache="04_rod_screen/rfam/$b"
    mkdir -p "$cache"; cp "$LEB"/CM/RF*.cm "$cache"/ 2>/dev/null
    nin=$(grep -c '^>' "$c")
    python3 "$LEB/Scripts/run_pipeline.py" -i "$c" -o "04_rod_screen/results/$b.csv" \
        --lib-dir "$LEB/Scripts" --circular -j "$J" \
        --model "$LEB/rodnotrod_model/model.pkl" \
        --dvr5-cm "$LEB/CM/dvr5.cm" --cmsearch-cpu "$J" \
        --rfam-cache-dir "$cache" --batch-size 50000 \
        > "04_rod_screen/logs/$b.log" 2>&1
    rc=$?
    nout=$(( $(wc -l < "04_rod_screen/results/$b.csv" 2>/dev/null || echo 1) - 1 ))
    rm -rf "$cache"
    if [ "$rc" -eq 0 ] && [ "$nout" -eq "$nin" ]; then
        echo "$nin" > "04_rod_screen/logs/$b.done"
        echo "[$(date -u '+%H:%M:%S')] ok   $b  $nout rows"
    else
        echo "$b in=$nin out=$nout rc=$rc at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> 04_rod_screen/MISMATCH.txt
        rmdir "04_rod_screen/claims/$b" 2>/dev/null
        echo "[$(date -u '+%H:%M:%S')] BAD  $b in=$nin out=$nout rc=$rc"
    fi
}
export -f process_chunk unclaimed
export LEB J RESERVE

say "extra workers: $NPROC x -j$J, $(unclaimed) chunks unclaimed"
ls 04_rod_screen/chunks/chunk_* | xargs -P "$NPROC" -I{} bash -c 'process_chunk "$@"' _ {}
say "extra workers finished"

say "waiting for driver"
while kill -0 "$DRIVER" 2>/dev/null; do sleep 60; done
[ -e RUN_ALL.DONE ] && { say "driver finished the run"; exit 0; }

say "backstop: driver ended without RUN_ALL.DONE"
for t in 1 2 3; do
    ./04_rod_screen/run.sh && [ -e 04_rod_screen/SCREEN.DONE ] && break
    say "screen incomplete, try $t"; sleep 300
done
[ -e 04_rod_screen/SCREEN.DONE ] || { say "FAILED: screen incomplete"; exit 1; }
./05_results/make_results.sh || { say "FAILED: results"; exit 1; }
say "ALL DONE"; touch RUN_ALL.DONE
