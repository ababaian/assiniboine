#!/usr/bin/env bash
# Step 2: features + rod classification over every deduped unclassified circle.
#
# 320 chunks, 16 concurrent workers x -j30 (= all 480 cores). 16-way beat both
# 8-way and 48-way in a head-to-head on identical data. Chunks are claimed with
# an atomic mkdir and marked done only when the output row count EQUALS the
# input record count -- that equality is the guard against RNAfold's silent
# truncation on oversized circles (it exits 0 after emitting nothing further).
#
# Each chunk gets a private Rfam cache: build_combined_rfam_library()
# unconditionally rewrites and re-cmpresses the combined library, so any two
# processes sharing a cache dir collide and one dies.
#
# Resume-safe: re-running skips completed chunks and retries failed ones.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
LEB=$ROOT/Lebowski
cd "$ROOT"
source /opt/miniconda3/etc/profile.d/conda.sh
conda activate circpipe
NPROC=4
J=22
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }

process_chunk() {
    c="$1"; b=$(basename "$c")
    [ -e "step2/logs/$b.done" ] && return 0
    mkdir "step2/claims/$b" 2>/dev/null || return 0
    cache="step2/rfam/$b"
    mkdir -p "$cache"; cp "$LEB"/CM/RF*.cm "$cache"/ 2>/dev/null
    nin=$(grep -c '^>' "$c")
    python3 "$LEB/Scripts/run_pipeline.py" -i "$c" -o "step2/results/$b.csv" \
        --lib-dir "$LEB/Scripts" --circular -j "$J" \
        --model "$LEB/rodnotrod_model/model.pkl" \
        --dvr5-cm "$LEB/CM/dvr5.cm" --cmsearch-cpu "$J" \
        --rfam-cache-dir "$cache" --batch-size 50000 \
        > "step2/logs/$b.log" 2>&1
    rc=$?
    nout=$(( $(wc -l < "step2/results/$b.csv" 2>/dev/null || echo 1) - 1 ))
    rm -rf "$cache"
    if [ "$rc" -eq 0 ] && [ "$nout" -eq "$nin" ]; then
        echo "$nin" > "step2/logs/$b.done"
        echo "[$(date -u '+%H:%M:%S')] ok   $b  $nout rows"
    else
        echo "$b in=$nin out=$nout rc=$rc at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> step2/MISMATCH.txt
        rmdir "step2/claims/$b" 2>/dev/null
        echo "[$(date -u '+%H:%M:%S')] BAD  $b in=$nin out=$nout rc=$rc"
    fi
}
export -f process_chunk
export LEB J ROOT

# This runner is designed to run alongside step2_run.sh, so it does NOT clear
# STEP2.DONE/INCOMPLETE: that is the primary runner's to manage.
total=$(ls step2/chunks/chunk_* 2>/dev/null | wc -l)
if [ "$total" -eq 0 ]; then
    say "no chunks in step2/chunks/; run step2/make_chunks.sh first"
    exit 1
fi

say "starting: $total chunks, $NPROC workers x -j$J"
ls step2/chunks/chunk_* | xargs -P "$NPROC" -I{} bash -c 'process_chunk "$@"' _ {}

# Count only markers belonging to the CURRENT chunk set. Counting every
# *.done in step2/logs lets markers from an earlier, differently-sized chunk
# set satisfy the gate.
done_n=0
for c in step2/chunks/chunk_*; do
    [ -e "step2/logs/$(basename "$c").done" ] && done_n=$((done_n+1))
done
{
  echo "Step 2 summary  ($(date -u))"
  echo "chunks completed: $done_n / $total"
  echo "input records:    $(cat step2/logs/*.done 2>/dev/null | awk '{s+=$1}END{print s}')"
  echo "result rows:      $(cat step2/results/*.csv 2>/dev/null | grep -vc '^sample_name')"
  # A chunk that mismatched and then succeeded on retry has a .done marker.
  # Only chunks still lacking one are actually outstanding.
  if [ -s step2/MISMATCH.txt ]; then
      unresolved=$(awk '{print $1}' step2/MISMATCH.txt | sort -u | while read -r b; do
          [ -e "step2/logs/$b.done" ] || echo "$b"
      done)
      [ -n "$unresolved" ] && { echo "UNRESOLVED MISMATCHES:"; printf '%s\n' "$unresolved"; }
  fi
} > SUMMARY_step2.txt 2>&1
cat SUMMARY_step2.txt
[ "$done_n" -eq "$total" ] && touch STEP2.DONE || touch STEP2.INCOMPLETE
say "finished"
