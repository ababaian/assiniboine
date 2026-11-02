#!/usr/bin/env bash
# Package the November 2026 run for s3://petadex/circs-results/run-2026-11/.
# Builds record_manifest, proves it rebuilds every stage 1 to 3 FASTA
# byte for byte, then stages everything that is kept under staging/run-2026-11/.
# Nothing is uploaded and nothing local is deleted except the temporary split.
#
# Resume-safe: each step leaves a marker in work/ and is skipped once done.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
P=06_package
W=$P/work
S=$P/staging/run-2026-11
SRC=00_source/selfloops.v1.1.fa.zst
NAME="k2-circ package"
mkdir -p "$W" "$S"
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }
die(){ say "FAILED: $*"; exit 1; }

# One push if /watson drops under 300 GiB while this runs.
( sent=0; while kill -0 $$ 2>/dev/null; do
    a=$(( $(df -B1 --output=avail /watson | tail -1) / 2**30 ))
    if [ "$sent" = 0 ] && [ "$a" -lt 300 ]; then
        ~/bin/notify.sh "$NAME: disk low" "Watson disk under 300 GiB free, job still running" 4; sent=1; fi
    sleep 60; done ) &

# ---- 1. split the source into the stage 1 parts ----------------------------------
say "1 split source"
$P/split_source.sh "$SRC" "$W/source_parts" || die "split"

# ---- 2. manifest ------------------------------------------------------------------
if [ ! -e "$W/MANIFEST.DONE" ]; then
    say "2 manifest: gate part_020"
    $P/build_manifest.sh "$W/source_parts" "$S/manifest" part_020 || die "manifest gate"
    say "2 manifest: all parts"
    todo=$(for i in $(seq -f '%03g' 0 19); do [ -s "$S/manifest/counts/part_$i.tsv" ] || echo part_$i; done)
    [ -z "$todo" ] || $P/build_manifest.sh "$W/source_parts" "$S/manifest" $todo || die "manifest"
    [ "$(ls "$S"/manifest/counts/part_*.tsv | wc -l)" = 21 ] || die "manifest counts missing"
    # Totals must equal the run's own stage summaries.
    cat "$S"/manifest/counts/part_*.tsv | tr '\t' '\n' | grep = | awk -F= '{s[$1]+=$2} END{for(k in s) print k, s[k]}' \
        | LC_ALL=C sort > "$W/manifest_totals.txt"
    # The C_ closure split is new information, so it is reported, not checked.
    grep '^C_' "$W/manifest_totals.txt" | sed 's/^/  /'
    want="C 305036299
U 595006157
U_circular 562743416
U_hairpin 32262741
U_unmatched 0
gt6000 269254
in_range 161292329
lt200 433444574"
    diff <(echo "$want") <(grep -v '^C_' "$W/manifest_totals.txt") || die "manifest totals differ from the run"
    # Per part: classified count equals the Kraken2 log for that part.
    for f in "$S"/manifest/counts/part_*.tsv; do
        p=$(basename "$f" .tsv)
        got=$(tr '\t' '\n' < "$f" | awk -F= '$1=="C"{print $2}')
        exp=$(awk '/sequences classified/{print $1}' 01_kraken_filter/logs/$p.log)
        [ "$got" = "$exp" ] || die "$p classified $got != $exp"
    done
    touch "$W/MANIFEST.DONE"; say "manifest totals match the run"
fi

# ---- 3. rebuild check -------------------------------------------------------------
local_md5(){
    p="$1"; w="$2"; o="$w/local_md5/$p.tsv"
    [ -s "$o" ] && return 0
    {
        printf '%s\tclassified\t%s\n' "$p" "$(zstd -dc 01_kraken_filter/classified/$p.fa.zst | md5sum | cut -d' ' -f1)"
        printf '%s\tunclassified\t%s\n' "$p" "$(md5sum < 01_kraken_filter/unclassified/unclass_$p.fa | cut -d' ' -f1)"
        printf '%s\tlabelled\t%s\n' "$p" "$(md5sum < 02_circular_overlap/labelled/unclass_$p.fa | cut -d' ' -f1)"
        for k in lt200 in_range gt6000; do
            printf '%s\t%s\t%s\n' "$p" "$k" "$(md5sum < 03_length_filter/$k/unclass_$p.fa | cut -d' ' -f1)"
        done
    } > "$o.tmp" && mv "$o.tmp" "$o"
}
export -f local_md5

if [ ! -e "$W/VERIFY.DONE" ]; then
    mkdir -p "$W/local_md5"
    say "3 rebuild check: gate part_020"
    $P/rebuild_stage.sh --md5 "$W/source_parts" "$S/manifest" "$W/rebuild" part_020 || die "rebuild gate"
    local_md5 part_020 "$W"
    cmp -s "$W/rebuild/md5/part_020.tsv" "$W/local_md5/part_020.tsv" || die "rebuild gate: part_020 differs"
    say "3 rebuild check: all parts, with local hashes alongside"
    seq -f 'part_%03g' 0 19 | xargs -P 20 -I{} bash -c 'local_md5 "$@"' _ {} "$W" &
    lpid=$!
    todo=$(for i in $(seq -f '%03g' 0 19); do [ -s "$W/rebuild/md5/part_$i.tsv" ] || echo part_$i; done)
    [ -z "$todo" ] || $P/rebuild_stage.sh --md5 "$W/source_parts" "$S/manifest" "$W/rebuild" $todo || die "rebuild"
    wait $lpid || die "local hashes"
    cat "$W"/rebuild/md5/part_*.tsv > "$W/rebuild_md5.tsv"
    cat "$W"/local_md5/part_*.tsv > "$W/local_md5.tsv"
    [ "$(wc -l < "$W/local_md5.tsv")" = 126 ] || die "expected 126 local hashes"
    cmp "$W/rebuild_md5.tsv" "$W/local_md5.tsv" || die "rebuilt files differ from the run's"
    # Stage 4 chunks are the in-range parts concatenated and re-split.
    a=$(cat 03_length_filter/in_range/unclass_part_*.fa | md5sum | cut -d' ' -f1)
    b=$(cat 04_rod_screen/chunks/chunk_* | md5sum | cut -d' ' -f1)
    [ "$a" = "$b" ] || die "chunks are not the in-range parts"
    echo "chunks_concat	$a" >> "$W/local_md5.tsv"
    touch "$W/VERIFY.DONE"; say "all 126 stage 1 to 3 files rebuilt byte for byte, chunks match"
fi

# ---- 4. stage what is kept -------------------------------------------------------
if [ ! -e "$W/STAGE.DONE" ]; then
    say "4 staging"
    mkdir -p "$S"/{source,kraken_filter/reports,summaries,rod_screen/results,results,code}
    ln -f "$SRC" "$S/source/selfloops.v1.1.fa.zst" || die "link source"
    cp 01_kraken_filter/logs/report_part_*.txt "$S/kraken_filter/reports/"
    cp 01_kraken_filter/SUMMARY_k2_filter.txt review/classified_taxa.csv review/target_taxa.csv \
       review/parts.csv review/step1_table_samples.md "$S/kraken_filter/"
    cp 00_source/total_records.txt 00_source/total_bytes.txt 02_circular_overlap/SUMMARY_overlap.txt \
       03_length_filter/SUMMARY_lenfilter.txt 03_length_filter/LENGTH_HIST.txt \
       04_rod_screen/SUMMARY_screen.txt 05_results/SUMMARY_results.txt "$S/summaries/"
    cp $P/split_source.sh $P/build_manifest.sh $P/rebuild_stage.sh "$S/code/"

    say "4 compress the 95 per-chunk results"
    ls 04_rod_screen/results/chunk_*.csv | xargs -P 24 -I{} bash -c \
        'f={}; o='"$S"'/rod_screen/results/$(basename $f).zst
         [ -s $o ] && exit 0
         zstd -q -19 -T4 -f -o $o.tmp $f && [ "$(md5sum < $f)" = "$(zstd -dc $o.tmp | md5sum)" ] && mv $o.tmp $o' \
        || die "compress results"
    [ "$(ls "$S"/rod_screen/results/chunk_*.csv.zst | wc -l)" = 95 ] || die "expected 95 compressed chunks"

    say "4 stage 5 tables"
    for t in rod_all rod_with_ribozyme; do
        zstd -q -19 -T16 -f 05_results/$t.csv -o "$S/results/$t.csv.zst" || die "compress $t"
    done
    cp 05_results/shortlist.csv "$S/results/"

    say "4 sequences for rod_with_ribozyme and the shortlist, as screened"
    mkdir -p "$W/fa"
    tail -n +2 05_results/rod_with_ribozyme.csv | cut -d, -f1 > "$W/fa/rwr.ids"
    tail -n +2 05_results/shortlist.csv | cut -d, -f1 > "$W/fa/short.ids"
    ls 04_rod_screen/chunks/chunk_* | xargs -P 32 -I{} bash -c \
        'LC_ALL=C mawk -v ids='"$W"'/fa/rwr.ids "BEGIN{while((getline l<ids)>0) k[\">\" l]=1}
          NR%2==1{split(\$0,a,\" \"); keep=(a[1] in k); h=\$0; next} keep{print h; print}" {} \
          > '"$W"'/fa/$(basename {}).fa' || die "extract sequences"
    cat "$W"/fa/chunk_*.fa > "$W/fa/rod_with_ribozyme.fa"
    n=$(grep -c '^>' "$W/fa/rod_with_ribozyme.fa"); want=$(wc -l < "$W/fa/rwr.ids")
    [ "$n" = "$want" ] || die "rod_with_ribozyme FASTA has $n records, expected $want"
    LC_ALL=C mawk -v ids="$W/fa/short.ids" 'BEGIN{while((getline l<ids)>0) k[">" l]=1}
        NR%2==1{split($0,a," "); keep=(a[1] in k); h=$0; next} keep{print h; print}' \
        "$W/fa/rod_with_ribozyme.fa" > "$S/results/shortlist.fa"
    n=$(grep -c '^>' "$S/results/shortlist.fa"); want=$(wc -l < "$W/fa/short.ids")
    [ "$n" = "$want" ] || die "shortlist FASTA has $n records, expected $want"
    zstd -q -19 -T16 -f "$W/fa/rod_with_ribozyme.fa" -o "$S/results/rod_with_ribozyme.fa.zst" || die "compress fa"
    touch "$W/STAGE.DONE"
fi

# ---- 5. checksums, then drop the temporary split -----------------------------------
if [ ! -e "$W/MD5.DONE" ]; then
    say "5 checksums"
    ( cd "$S" && find . -type f ! -name MD5SUMS -printf '%P\n' | LC_ALL=C sort \
        | xargs -P 32 -I{} md5sum {} | LC_ALL=C sort -k2 > MD5SUMS ) || die "md5"
    touch "$W/MD5.DONE"
fi
rm -rf "$W/source_parts" "$W/fa"
du -sh "$S" "$S"/* | sed 's/^/  /'
say "ALL DONE"
touch "$W/PACKAGE.DONE"
