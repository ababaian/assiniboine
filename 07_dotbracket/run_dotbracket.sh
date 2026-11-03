#!/usr/bin/env bash
# Dot-bracket MFE structures for every rod in 05_results/rods.csv.zst, folded
# exactly as stage 4 folded them (RNAfold --circ --noPS, ViennaRNA 2.7.2, env
# circpipe). Stage 4 kept only features computed from the structures.
#
# Rods are sorted by length, longest first, and dealt round-robin into NPART
# parts, so every part gets the same mix of lengths; one single-threaded
# RNAfold per part. A part is done only when every rod came back with a
# structure the same length as its sequence. Resume-safe.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
D=$ROOT/07_dotbracket
RODS=$ROOT/06_package/upload/run-2026-11/05_results/rods.csv.zst
PY=/watson/rnalab/dzhu/.conda/envs/features/bin/python
NPART=${NPART:-460}
OUT=$D/rods_dotbracket.tsv.zst
cd "$D"
source /opt/miniconda3/etc/profile.d/conda.sh
conda activate circpipe
mkdir -p work/parts work/out
say(){ echo "[$(date '+%m-%d %H:%M:%S %Z')] $*"; }

if [ ! -e work/SPLIT.DONE ]; then
    say "extracting rods"
    $PY - "$RODS" work/rods.tsv <<'PYEOF'
import sys, duckdb
c = duckdb.connect(); c.execute("SET threads=64")
c.execute(f"""COPY (SELECT row_number() OVER () - 1 AS idx, * FROM (
    SELECT sample_name, length, sequence FROM read_csv('{sys.argv[1]}')))
  TO '{sys.argv[2]}' (FORMAT csv, DELIMITER '\t', HEADER false)""")
PYEOF
    sort -t$'\t' -k3,3nr -S 20G --parallel=32 work/rods.tsv \
      | gawk -F'\t' -v n="$NPART" '{ f=sprintf("work/parts/p%03d", (NR-1)%n);
            print ">"$1"|"$2"|"$3"\n"$4 > (f ".fa") }'
    rm -f work/rods.tsv
    touch work/SPLIT.DONE
fi

fold_part() {
    p=$1; b=$(basename "$p" .fa)
    [ -e "work/out/$b.done" ] && return 0
    RNAfold --circ --noPS --jobs=1 < "$p" > "work/out/$b.raw" 2> "work/out/$b.err" || { echo "FAIL $b rc"; return 1; }
    # record: >idx|sample_name|length / sequence / structure ( mfe)
    gawk -v part="$b" '
      NR%3==1 { split(substr($0,2), h, "|"); next }
      NR%3==2 { seqlen=length($0); next }
      { i=index($0," "); s=substr($0,1,i-1); m=substr($0,i); gsub(/[() ]/,"",m)
        if (length(s)!=h[3] || seqlen!=h[3]) { bad++ }
        print h[1]"\t"h[2]"\t"h[3]"\t"m"\t"s; n++ }
      END { if (bad || NR%3) { print part": bad="bad" lines="NR > "/dev/stderr"; exit 1 } }
    ' "work/out/$b.raw" > "work/out/$b.tsv" || { echo "FAIL $b parse"; return 1; }
    nin=$(grep -c '^>' "$p"); nout=$(wc -l < "work/out/$b.tsv")
    [ "$nin" -eq "$nout" ] || { echo "FAIL $b in=$nin out=$nout"; return 1; }
    rm -f "work/out/$b.raw"
    echo "$nout" > "work/out/$b.done"
}
export -f fold_part

if [ ! -e "$OUT" ]; then
    say "folding $NPART parts"
    ls work/parts/p*.fa | xargs -P "$NPART" -I{} bash -c 'fold_part {}'
    ndone=$(ls work/out/*.done 2>/dev/null | wc -l)
    [ "$ndone" -eq "$NPART" ] || { say "only $ndone of $NPART parts done"; exit 1; }

    say "assembling"
    $PY - "$OUT" <<'PYEOF' || exit 1
import sys, duckdb
c = duckdb.connect(); c.execute("SET threads=64")
c.execute("""CREATE TABLE t AS SELECT * FROM read_csv('work/out/p*.tsv', delim='\t', header=false,
   columns={'idx':'BIGINT','sample_name':'VARCHAR','length':'INTEGER','mfe':'DOUBLE','dot_bracket':'VARCHAR'})""")
n, nu, mn, mx = c.execute("SELECT count(*), count(DISTINCT idx), min(idx), max(idx) FROM t").fetchone()
assert n == nu == 11308939 and mn == 0 and mx == n - 1, (n, nu, mn, mx)
assert c.execute("SELECT count(*) FROM t WHERE length(dot_bracket) <> length OR mfe IS NULL").fetchone()[0] == 0
c.execute("COPY (SELECT sample_name, length, mfe, dot_bracket FROM t ORDER BY idx) TO 'work/rods_dotbracket.tsv' (FORMAT csv, DELIMITER '\t', HEADER true)")
print("rows", n)
PYEOF
    zstd -q -19 -T64 --rm work/rods_dotbracket.tsv -o "$OUT" || exit 1
fi
say "done: $(ls -l "$OUT" | awk '{print $5}') bytes"
touch "$D/DOTBRACKET.DONE"
