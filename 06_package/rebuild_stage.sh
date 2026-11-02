#!/usr/bin/env bash
# Rebuild every stage 1 to 3 FASTA from the source archive and record_manifest.
# No Kraken2, no database: the manifest already says which records were
# classified and how each one closes.
#
#   rebuild_stage.sh [--md5] <selfloops.v1.1.fa.zst | split_dir> <record_manifest.tsv.zst | manifest_dir> <out_dir> [part ...]
#
# The manifest is either the single uploaded file, which is cut here into the 21
# parts of 45,000,000 rows that stage 1 used, or a directory of those parts.
#
# Writes, per part NNN, under <out_dir>:
#   01_kraken_filter/classified/part_NNN.fa             (stored by the run as .fa.zst)
#   01_kraken_filter/unclassified/unclass_part_NNN.fa
#   02_circular_overlap/labelled/unclass_part_NNN.fa    header + " ovl:<class> trim:<nt>", upper case, circular minus last 30 nt
#   03_length_filter/{lt200,in_range,gt6000}/unclass_part_NNN.fa
# Stage 4 chunks are `cat in_range/*.fa | split -d -a3 -l 3409272`.
#
# --md5 writes nothing but <out_dir>/md5/<part>.tsv, the md5 of each file it would
# have written, for comparing with an existing run.
set -uo pipefail
MODE=write
[ "${1:-}" = --md5 ] && { MODE=md5; shift; }
SRC=${1:?source .fa.zst or split dir}
MAN=${2:?manifest file or dir}
OUT=${3:?output dir}
shift 3
HERE=$(cd "$(dirname "$0")" && pwd)

if [ -f "$MAN" ]; then
    d=$OUT/manifest_parts
    if [ ! -e "$d/SPLIT.DONE" ]; then
        mkdir -p "$d"
        zstd -dc "$MAN" | tail -n +2 | split -d -a3 -l 45000000 \
            --filter='{ printf "id\trun\tlength\tkraken\ttaxid\tclosure\tstage\n"; cat; } | zstd -q -T4 -f -o "$FILE.tsv.zst"' \
            - "$d/part_" || { echo "manifest split failed"; exit 1; }
        touch "$d/SPLIT.DONE"
    fi
    MAN=$d
fi

if [ -d "$SRC" ]; then SPLIT=$SRC
else SPLIT=$OUT/source_parts; "$HERE/split_source.sh" "$SRC" "$SPLIT" || exit 1
fi

one() {
    p="$1"; split="$2"; man="$3"; out="$4"; mode="$5"
    if [ "$mode" = write ]; then
        mkdir -p "$out"/01_kraken_filter/classified "$out"/01_kraken_filter/unclassified \
                 "$out"/02_circular_overlap/labelled "$out"/03_length_filter/{lt200,in_range,gt6000}
    else
        mkdir -p "$out/md5/$p"
    fi
    zstd -dc "$split/$p.fa.zst" | LC_ALL=C mawk \
        -v mcmd="zstd -dc $man/$p.tsv.zst" -v part="$p" -v out="$out" -v mode="$mode" '
    function emit(key, rel, x) {
        if (mode == "write") print x > (out "/" rel)
        else {
            if (!(key in cmd)) cmd[key] = "md5sum | cut -d\" \" -f1 > " out "/md5/" part "/" key
            print x | cmd[key]
        }
    }
    function die(m) { print "[FAIL] " part ": " m > "/dev/stderr"; bad = 1; exit 2 }
    BEGIN {
        mcmd | getline hdr
        if (hdr != "id\trun\tlength\tkraken\ttaxid\tclosure\tstage") die("unexpected manifest header")
        u = "unclass_" part ".fa"
    }
    NR % 2 == 1 { h = $0; next }
    {
        if ((mcmd | getline row) <= 0) die("manifest ended early at record " NR / 2)
        split(row, f, "\t")
        id = substr(h, 2); sp = index(id, " "); if (sp) id = substr(id, 1, sp - 1)
        if (id != f[1]) die("record " id " but manifest says " f[1])
        if (f[4] == "C") { emit("classified", "01_kraken_filter/classified/" part ".fa", h "\n" $0); next }
        emit("unclassified", "01_kraken_filter/unclassified/" u, h "\n" $0)
        t = (f[6] == "circular") ? 30 : 0
        s = toupper($0); if (t) s = substr(s, 1, length(s) - t)
        r = h " ovl:" f[6] " trim:" t "\n" s
        emit("labelled", "02_circular_overlap/labelled/" u, r)
        L = length(s)
        st = (L < 200) ? "lt200" : ((L > 6000) ? "gt6000" : "in_range")
        if (st != f[7]) die(id " length " L " gives " st " but manifest says " f[7])
        emit(st, "03_length_filter/" st "/" u, r)
    }
    END {
        if (bad) exit 2
        if ((mcmd | getline row) > 0) die("manifest has rows left over")
        for (k in cmd) close(cmd[k])
    }'
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] || { echo "[FAIL] $p zstd=${st[0]} mawk=${st[1]}"; return 1; }
    if [ "$mode" = md5 ]; then
        # A file the run wrote empty is never opened here; record the empty hash.
        for k in classified unclassified labelled lt200 in_range gt6000; do
            [ -e "$out/md5/$p/$k" ] || md5sum < /dev/null | cut -d' ' -f1 > "$out/md5/$p/$k"
        done
        for k in classified unclassified labelled lt200 in_range gt6000; do
            printf '%s\t%s\t%s\n' "$p" "$k" "$(cat "$out/md5/$p/$k")"
        done > "$out/md5/$p.tsv"
    fi
    echo "[ok] $p"
}
export -f one

parts=("$@")
[ ${#parts[@]} -gt 0 ] || parts=($(ls "$SPLIT"/part_*.fa.zst | xargs -n1 basename | sed 's/\.fa\.zst$//'))
printf '%s\n' "${parts[@]}" | xargs -P 21 -I{} bash -c 'one "$@"' _ {} "$SPLIT" "$MAN" "$OUT" "$MODE"
