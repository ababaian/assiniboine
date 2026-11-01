#!/usr/bin/env bash
# Regenerate per-record Kraken2 calls for the classified records rebuilt by
# rebuild_classified.sh. Calls go to stdout: `--output -` SUPPRESSES them.
#
# The report is written whether or not calls are kept, so it proves nothing about
# the .kout. Each part is therefore checked on the .kout itself: one C line per
# record, and taxids tallied from the .kout must equal the original report.
# Usage: rerun_calls.sh [part_NNN]   (one part, or part_020 as a gate then the rest)
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
export PATH=/watson/rnalab/dzhu/.conda/envs/k2workflow/bin:$PATH
DB=/watson/rnalab/js/resource_files/k2_core_nt
OUT=01_kraken_filter/classified
NPROC=4
THREADS=16
CONF=0.1
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }
want_count(){ awk '/sequences classified/{print $1}' "01_kraken_filter/logs/$1.log"; }
taxa(){ awk -F'\t' '$5 != 0 && $3 > 0 {print $5, $3}' "$1" | LC_ALL=C sort; }

calls_one(){
    b="$1"; k="$OUT/$b.kout.zst"
    [ -e "$OUT/$b.calls.done" ] && return 0
    zstd -dc "$OUT/$b.fa.zst" \
      | kraken2 --db "$DB" --memory-mapping --threads "$THREADS" --confidence "$CONF" \
                --report "$OUT/$b.report.txt" /dev/fd/0 2> "$OUT/$b.log" \
      | zstd -q -f -T4 -o "$k"
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] && [ "${st[2]}" = 0 ] || { echo "[FAIL] $b pipe ${st[*]}"; return 1; }
    want=$(want_count "$b")
    read -r n c < <(zstd -dc "$k" | LC_ALL=C mawk -F'\t' '{n++; if($1=="C")c++} END{print n+0, c+0}')
    [ "$n" = "$want" ] && [ "$c" = "$want" ] || { echo "[FAIL] $b kout lines=$n C=$c want=$want"; return 1; }
    if ! cmp -s <(zstd -dc "$k" | LC_ALL=C mawk -F'\t' '{a[$3]++} END{for(t in a) print t, a[t]}' | LC_ALL=C sort) \
                <(taxa "01_kraken_filter/logs/report_$b.txt"); then
        echo "[FAIL] $b kout taxids differ from original report"; return 1
    fi
    touch "$OUT/$b.calls.done"; echo "[ok] $b $n calls, taxids match original report"
}
export -f calls_one want_count taxa; export DB THREADS CONF OUT

if [ $# -eq 1 ]; then calls_one "$1"; exit $?; fi
rm -f "$OUT/CALLS.DONE" "$OUT/CALLS.FAILED"
calls_one part_020 || { touch "$OUT/CALLS.FAILED"; say "FAILED gate"; exit 1; }
ls "$OUT"/part_*.fa.zst | xargs -n1 basename | sed 's/\.fa\.zst$//' \
    | xargs -P "$NPROC" -I{} bash -c 'calls_one "$@"' _ {}
rc=$?
[ "$rc" = 0 ] && [ "$(ls "$OUT"/part_*.calls.done | wc -l)" = 21 ] || { touch "$OUT/CALLS.FAILED"; say "FAILED rc=$rc"; exit 1; }
touch "$OUT/CALLS.DONE"; say "ALL DONE"
