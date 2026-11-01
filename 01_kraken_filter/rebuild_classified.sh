#!/usr/bin/env bash
# Rebuild the classified records stage 1 never wrote, then rerun Kraken2 on them
# with per-record output. The classified set is source minus unclassified: both
# keep source order, so one linear pass recovers it with no index.
#
# Each part must reproduce the original run: record count against logs/part_NNN.log,
# per-taxon direct counts against logs/report_part_NNN.txt. A plain FASTA is only
# compressed away after its part passes. part_020 is tiny and runs first as a gate.
# Resume-safe: re-running skips the rebuild if done and skips finished parts.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
export PATH=/watson/rnalab/dzhu/.conda/envs/k2workflow/bin:$PATH
DB=/watson/rnalab/js/resource_files/k2_core_nt
SRC=00_source/selfloops.v1.1.fa.zst
OUT=01_kraken_filter/classified
NPROC=4
THREADS=16
CONF=0.1
mkdir -p "$OUT"
rm -f "$OUT/CLASSIFIED.DONE" "$OUT/CLASSIFIED.FAILED"
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }
die(){ say "FAILED: $*"; touch "$OUT/CLASSIFIED.FAILED"; exit 1; }

want_count(){ awk '/sequences classified/{print $1}' "01_kraken_filter/logs/$1.log"; }

# ---- rebuild ---------------------------------------------------------------
if [ ! -e "$OUT/.REBUILD_DONE" ]; then
    say "rebuilding classified records"
    zstd -dc "$SRC" | LC_ALL=C mawk -v out="$OUT" -v ud=01_kraken_filter/unclassified -v per=45000000 '
    function finish() { close(u); close(f); printf "%s\t%d\t%s\n", tag, cnt, (uh == "" ? "ok" : "LEFTOVER") > (out "/rebuild_counts.tsv") }
    function start(p) {
        tag = sprintf("part_%03d", p); u = ud "/unclass_" tag ".fa"; f = out "/" tag ".fa"; cnt = 0; uh = ""; us = ""
        if ((getline uh < u) > 0) getline us < u; else uh = ""
    }
    BEGIN { pp = -1 }
    NR % 2 == 1 { h = $0; next }
    {
        p = int((NR / 2 - 1) / per)
        if (p != pp) { if (pp >= 0) finish(); start(p); pp = p }
        if (h == uh && $0 == us) {
            if ((getline uh < u) > 0) getline us < u; else uh = ""
        } else { print h "\n" $0 > f; cnt++ }
    }
    END { finish() }'
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] || die "rebuild zstd=${st[0]} mawk=${st[1]}"
    while IFS=$'\t' read -r tag n flag; do
        [ "$flag" = ok ] || die "$tag unclassified records not exhausted"
        [ "$n" = "$(want_count "$tag")" ] || die "$tag count $n != $(want_count "$tag")"
    done < "$OUT/rebuild_counts.tsv"
    [ "$(wc -l < "$OUT/rebuild_counts.tsv")" = 21 ] || die "expected 21 parts"
    touch "$OUT/.REBUILD_DONE"
    say "rebuild done, all 21 part counts match"
fi

# ---- rerun -----------------------------------------------------------------
taxa(){ awk -F'\t' '$5 != 0 && $3 > 0 {print $5, $3}' "$1" | LC_ALL=C sort; }

classify_one(){
    b="$1"; fa="$OUT/$b.fa"
    [ -e "$OUT/$b.done" ] && return 0
    kraken2 --db "$DB" --memory-mapping --threads "$THREADS" --confidence "$CONF" \
            --report "$OUT/$b.report.txt" --output - "$fa" 2> "$OUT/$b.log" \
        | zstd -q -f -T4 -o "$OUT/$b.kout.zst"
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] || { echo "[FAIL] $b kraken=${st[0]} zstd=${st[1]}"; return 1; }
    n=$(awk '/sequences classified/{print $1}' "$OUT/$b.log")
    [ "$n" = "$(want_count "$b")" ] || { echo "[FAIL] $b reran classified $n != $(want_count "$b")"; return 1; }
    if ! cmp -s <(taxa "$OUT/$b.report.txt") <(taxa "01_kraken_filter/logs/report_$b.txt"); then
        echo "[FAIL] $b taxon counts differ from original report"; return 1
    fi
    zstd -q -f -T8 --rm "$fa" || { echo "[FAIL] $b compress"; return 1; }
    touch "$OUT/$b.done"; echo "[ok] $b $n records, report identical"
}
export -f classify_one want_count taxa; export DB THREADS CONF OUT

say "gate: part_020"
classify_one part_020 || die "gate part_020"
say "rerunning the rest, $NPROC x $THREADS threads"
ls "$OUT"/part_*.fa 2>/dev/null | xargs -r -n1 basename | sed 's/\.fa$//' \
    | xargs -P "$NPROC" -I{} bash -c 'classify_one "$@"' _ {}
rc=$?
[ "$rc" = 0 ] && [ "$(ls "$OUT"/part_*.done | wc -l)" = 21 ] || die "rerun rc=$rc"
touch "$OUT/CLASSIFIED.DONE"; say "ALL DONE"
