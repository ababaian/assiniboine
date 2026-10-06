#!/usr/bin/env bash
# Stage 2 of the Kraken2 filter, decoupled from the split so it can run
# WHILE `zstd | split` is still writing parts.
#
# A part is only eligible once it is complete: while `split` is alive, the
# highest-numbered part is the one being appended to, so it is held back.
# Each part is claimed with an atomic mkdir, so this is safe to run in
# several copies and safe to re-run after an interruption.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
export PATH=/watson/rnalab/dzhu/.conda/envs/k2workflow/bin:$PATH
DB=/watson/rnalab/js/resource_files/k2_core_nt
NPROC=10
THREADS=32
CONF=0.1
mkdir -p unclassified logs claims
say(){ echo "[$(date -u +%H:%M:%S)] $*"; }

split_alive(){ pgrep -f 'split -a3 -d -l 90000000' > /dev/null; }

classify_one(){
    part="$1"; b=$(basename "$part")
    [ -e "logs/$b.done" ] && return 0
    mkdir "claims/$b" 2>/dev/null || return 0          # someone else has it
    say "start $b"
    kraken2 --db "$DB" --memory-mapping --threads "$THREADS" --confidence "$CONF" \
            --unclassified-out "unclassified/unclass_$b.fa" \
            --output /dev/null --report "logs/report_$b.txt" \
            "$part" > "logs/$b.log" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        touch "logs/$b.done"; rm -f "$part"
        say "done  $b -- $(grep -o '[0-9]* sequences unclassified ([^)]*)' logs/$b.log | head -1)"
    else
        rmdir "claims/$b" 2>/dev/null; say "FAIL  $b rc=$rc"
    fi
}
export -f classify_one say; export DB THREADS CONF PATH

while :; do
    mapfile -t all < <(ls parts/part_* 2>/dev/null | sort)
    if split_alive && [ "${#all[@]}" -gt 0 ]; then
        unset 'all[${#all[@]}-1]'                      # hold back the part being written
    fi
    todo=()
    for p in "${all[@]:-}"; do
        [ -n "$p" ] || continue
        [ -e "logs/$(basename "$p").done" ] && continue
        [ -d "claims/$(basename "$p")" ] && continue
        todo+=("$p")
    done
    if [ "${#todo[@]}" -gt 0 ]; then
        printf '%s\n' "${todo[@]}" | xargs -P "$NPROC" -I{} bash -c 'classify_one "$@"' _ {}
    else
        split_alive || { ls parts/part_* >/dev/null 2>&1 || break; }
        sleep 20
    fi
done

{
  echo "Kraken2 filter summary  ($(date -u))"
  echo "db=$DB  confidence=$CONF  source=selfloops.v1.1.fa.zst"
  echo "input records (counted): 900042456"
  awk '/sequences \(/{s+=$1} /sequences classified/{c+=$1} /sequences unclassified/{u+=$1}
       END{printf "processed    %d\nclassified   %d (%.2f%%)\nunclassified %d (%.2f%%)\n",s,c,100*c/s,u,100*u/s}' logs/part_*.log
  echo "unclassified FASTA: $(du -sh unclassified | cut -f1) across $(ls unclassified/*.fa 2>/dev/null | wc -l) files"
} > SUMMARY_k2_filter.txt 2>&1
cat SUMMARY_k2_filter.txt
touch K2_FILTER.DONE
say "ALL DONE"
