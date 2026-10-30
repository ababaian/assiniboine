#!/usr/bin/env bash
# Step 1 of the circles pipeline: Kraken2-filter the Logan selfloops at
# confidence 0.1 and keep everything UNCLASSIFIED for run_pipeline.py.
#
# Two stages, because a streaming splitter (paste|split|tr) throttles each
# kraken2 worker to a third of its solo speed:
#   1. zstd -dc | split  -> 20 plain-FASTA parts on disk (~588 MB/s)
#   2. 10 concurrent kraken2 processes, 32 threads each, over those parts
#      (each worker sustains ~8.1M seq/min; they share the mmap'd db via
#      the page cache, so RAM cost is one copy, not ten)
# Each part is deleted as soon as its own kraken2 exits 0, to cap peak disk.
# Resume-safe: re-running skips the split if done and skips finished parts.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
export PATH=/watson/rnalab/dzhu/.conda/envs/k2workflow/bin:$PATH
DB=/watson/rnalab/js/resource_files/k2_core_nt
SRC=00_source/selfloops.v1.1.fa.zst
LINES_PER_PART=90000000        # 45M records -> 20 parts
NPROC=10
THREADS=32
CONF=0.1

mkdir -p 01_kraken_filter/parts 01_kraken_filter/unclassified 01_kraken_filter/logs
rm -f 01_kraken_filter/K2_FILTER.DONE 01_kraken_filter/K2_FILTER.FAILED
say(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ---- stage 1: decompress + split ------------------------------------------
if [ ! -e 01_kraken_filter/parts/.SPLIT_DONE ]; then
    say "stage 1: decompressing and splitting $SRC"
    rm -f 01_kraken_filter/parts/part_*
    zstd -dc "$SRC" | split -a3 -d -l $LINES_PER_PART - 01_kraken_filter/parts/part_
    st=("${PIPESTATUS[@]}")
    if [ "${st[0]}" != 0 ] || [ "${st[1]}" != 0 ]; then
        say "FAILED: zstd=${st[0]} split=${st[1]}"; touch 01_kraken_filter/K2_FILTER.FAILED; exit 1
    fi
    touch 01_kraken_filter/parts/.SPLIT_DONE
    say "stage 1 done: $(ls 01_kraken_filter/parts/part_* | wc -l) parts, $(du -sh 01_kraken_filter/parts | cut -f1)"
else
    say "stage 1 already done, skipping"
fi

# ---- stage 2: classify ----------------------------------------------------
# Warm the db into the page cache once so the first workers don't fault it in.
say "warming db page cache"
cat $DB/hash.k2d > /dev/null
cat $DB/taxo.k2d > /dev/null

classify_one() {
    part="$1"; b=$(basename "$part")
    [ -e "01_kraken_filter/logs/$b.done" ] && { echo "[skip] $b already done"; return 0; }
    kraken2 --db "$DB" --memory-mapping --threads "$THREADS" \
            --confidence "$CONF" \
            --unclassified-out "01_kraken_filter/unclassified/unclass_$b.fa" \
            --output /dev/null \
            --report "01_kraken_filter/logs/report_$b.txt" \
            "$part" > "01_kraken_filter/logs/$b.log" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        touch "01_kraken_filter/logs/$b.done"; rm -f "$part"
        echo "[ok] $b $(grep -o '[0-9]* sequences unclassified.*' 01_kraken_filter/logs/$b.log | head -1)"
    else
        echo "[FAIL rc=$rc] $b"; return $rc
    fi
}
export -f classify_one; export DB THREADS CONF PATH

say "stage 2: classifying with $NPROC x $THREADS threads"
ls 01_kraken_filter/parts/part_* 2>/dev/null | xargs -P "$NPROC" -I{} bash -c 'classify_one "$@"' _ {}
rc=$?

# ---- stage 3: tally -------------------------------------------------------
{
  echo "Kraken2 filter summary  ($(date -u))"
  echo "db=$DB  confidence=$CONF  source=$SRC"
  awk '/sequences \(/{s+=$1} /sequences classified/{c+=$1} /sequences unclassified/{u+=$1}
       END{printf "processed   %d\nclassified  %d (%.2f%%)\nunclassified %d (%.2f%%)\n",
                  s,c,100*c/s,u,100*u/s}' 01_kraken_filter/logs/part_*.log
  echo "unclassified FASTA: $(du -sh 01_kraken_filter/unclassified | cut -f1) in $(ls 01_kraken_filter/unclassified/*.fa 2>/dev/null | wc -l) files"
} > 01_kraken_filter/SUMMARY_k2_filter.txt 2>&1
cat 01_kraken_filter/SUMMARY_k2_filter.txt

if [ "$rc" -eq 0 ] && [ "$(ls 01_kraken_filter/parts/part_* 2>/dev/null | wc -l)" -eq 0 ]; then
    touch 01_kraken_filter/K2_FILTER.DONE; say "ALL DONE"
else
    touch 01_kraken_filter/K2_FILTER.FAILED; say "finished with failures (rc=$rc); re-run to resume"
fi
