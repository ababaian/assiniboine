#!/usr/bin/env bash
# Build record_manifest: one row per source record, in source order, saying what
# stages 1 to 3 did to it. Together with the source archive it replaces every
# stage 1 to 3 FASTA (see rebuild_stage.sh).
#
#   build_manifest.sh <split_dir> <manifest_dir> [part ...]
#     -> <manifest_dir>/part_NNN.tsv.zst  and  <manifest_dir>/counts/part_NNN.tsv
#
# Columns:
#   id        first header token, e.g. DRR000091_3841_circle_3841
#   run       SRA run, the id up to the first _
#   length    source length in nt, before any trim
#   kraken    C = classified (dropped at stage 1), U = unclassified (kept)
#   taxid     Kraken2 taxid for C, 0 for U
#   closure   circular | hairpin | unmatched, by the stage 2 rule. For U it is
#             read from the stage 2 header; for C, which never reached stage 2,
#             the same rule is applied here. circular means 30 nt trimmed.
#   stage     classified | lt200 | in_range | gt6000, where the record ended
#
# Every source record must match, in order, either the next Kraken2 call or the
# next stage 2 record, and both of those must be used up exactly. For U the stage
# 2 header must equal the source header plus its ovl tag, and the stage 2 length
# must equal source length minus the trim.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
SPLIT=${1:?split dir}
MAN=${2:?manifest dir}
shift 2
mkdir -p "$MAN/counts"

one() {
    p="$1"; split="$2"; man="$3"
    zstd -dc "$split/$p.fa.zst" | LC_ALL=C mawk \
        -v kcmd="zstd -dc 01_kraken_filter/classified/$p.kout.zst" \
        -v lab="02_circular_overlap/labelled/unclass_$p.fa" \
        -v part="$p" -v cnt="$man/counts/$p.tsv" '
    function nextk(   f) {
        if ((kcmd | getline kl) > 0) { split(kl, f, "\t"); kid = f[2]; ktax = f[3]; klen = f[4] }
        else kid = ""
    }
    function nextl() {
        if ((getline lh < lab) > 0) {
            getline ls < lab
            lid = substr(lh, 2); sp = index(lid, " "); if (sp) lid = substr(lid, 1, sp - 1)
            if (!match(lh, / ovl:[a-z]+ trim:[0-9]+$/)) die("no ovl tag: " lh)
            tag = substr(lh, RSTART); lbase = substr(lh, 1, RSTART - 1)
            split(tag, g, /[ :]/); lcls = g[3]; ltrim = g[5] + 0
        } else lid = ""
    }
    function die(m) { print "[FAIL] " part ": " m > "/dev/stderr"; bad = 1; exit 2 }
    BEGIN { OFS = "\t"; print "id", "run", "length", "kraken", "taxid", "closure", "stage"; nextk(); nextl() }
    NR % 2 == 1 { if (substr($0, 1, 1) != ">") die("not a header at line " NR); h = $0; next }
    {
        id = substr(h, 2); sp = index(id, " "); if (sp) id = substr(id, 1, sp - 1)
        run = id; u = index(run, "_"); if (u) run = substr(run, 1, u - 1)
        n = length($0)
        if (id == kid) {
            if (klen + 0 != n) die("kraken length " klen " != " n " for " id)
            s = toupper($0)
            rev = (h ~ /L:\+:[0-9]+:-/ || h ~ /L:-:[0-9]+:\+/)
            fwd = (h ~ /L:-:[0-9]+:-/ && h ~ /L:\+:[0-9]+:\+/)
            if (rev && !fwd) cls = "hairpin"
            else if (fwd && n >= 60 && substr(s, 1, 30) == substr(s, n - 29)) cls = "circular"
            else cls = "unmatched"
            print id, run, n, "C", ktax, cls, "classified"
            c["C"]++; c["C_" cls]++
            nextk()
        } else if (id == lid) {
            if (lbase != h) die("stage 2 header differs for " id)
            if (ltrim != (lcls == "circular" ? 30 : 0)) die("trim " ltrim " for " lcls " " id)
            L = n - ltrim
            if (length(ls) != L) die("stage 2 length " length(ls) " != " L " for " id)
            st = (L < 200) ? "lt200" : ((L > 6000) ? "gt6000" : "in_range")
            print id, run, n, "U", 0, lcls, st
            c["U"]++; c["U_" lcls]++; c[st]++
            nextl()
        } else die("record " id " matches neither the next call (" kid ") nor the next stage 2 record (" lid ")")
    }
    END {
        if (bad) exit 2
        if (NR % 2) die("odd line count")
        if (kid != "") die("Kraken2 calls left over, next " kid)
        if (lid != "") die("stage 2 records left over, next " lid)
        printf "%s", part > cnt
        split("C U C_circular C_hairpin C_unmatched U_circular U_hairpin U_unmatched lt200 in_range gt6000", k, " ")
        for (i = 1; i <= 11; i++) printf "\t%s=%d", k[i], c[k[i]] + 0 > cnt
        printf "\n" > cnt
    }' | zstd -q -19 -T4 -f -o "$man/$p.tsv.zst"
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ] && [ "${st[2]}" = 0 ] \
        || { echo "[FAIL] $p zstd=${st[0]} mawk=${st[1]} zstd=${st[2]}"; rm -f "$man/counts/$p.tsv"; return 1; }
    echo "[ok] $p $(cut -f2- "$man/counts/$p.tsv")"
}
export -f one

parts=("$@")
[ ${#parts[@]} -gt 0 ] || parts=($(ls "$SPLIT"/part_*.fa.zst | xargs -n1 basename | sed 's/\.fa\.zst$//'))
printf '%s\n' "${parts[@]}" | xargs -P 21 -I{} bash -c 'one "$@"' _ {} "$SPLIT" "$MAN"
