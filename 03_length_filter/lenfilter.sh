#!/usr/bin/env bash
# Keep the labelled circles between 200 and 6000 nt inclusive.
#
# The 6000 nt ceiling is a bug workaround, not a biological filter: RNAfold
# hits "exceeds addressable range" on an oversized circle and then STOPS,
# exiting 0, so every record after it in the batch is silently lost.
#
# The 200 nt floor IS a biological filter. Circles shorter than that are below
# the size of any known viroid-like agent and dominated by assembly fragments.
#
# Nothing is deleted. Out-of-range records go to lt200/ and gt6000/ so either
# bound can be revisited without re-running stage 1.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
IN=02_circular_overlap/labelled
MIN=200
MAX=6000
THREADS=12

nsrc=$(ls "$IN"/*.fa 2>/dev/null | wc -l)
[ "$nsrc" -gt 0 ] || { echo "no FASTAs in $IN/; run 02_circular_overlap first"; exit 1; }

mkdir -p 03_length_filter/lt200 03_length_filter/in_range 03_length_filter/gt6000

# -w 0 is required, not cosmetic. seqkit wraps sequences at 60 columns by
# default, and the chunker in 04_rod_screen splits on a fixed line count, so a
# wrapped FASTA would misalign every record after the first.
#
# seqkit prints "you may switch on flag -g/--remove-gaps" on every invocation
# regardless of input; these records are pure ACGTN with no gaps, so it is
# noise rather than a signal about the data.
#
# Three passes per file rather than one, which costs I/O the old single-pass
# awk did not. That is a deliberate trade for legibility: the stage reads
# ~170 G three times instead of once, against 65 h of folding downstream.
filter_one() {
    f="$1"; b=$(basename "$f" .fa)
    seqkit seq -w 0                   -M "$((MIN - 1))" "$f" > "03_length_filter/lt200/$b.fa"
    seqkit seq -w 0 -m "$MIN"         -M "$MAX"         "$f" > "03_length_filter/in_range/$b.fa"
    seqkit seq -w 0 -m "$((MAX + 1))"                   "$f" > "03_length_filter/gt6000/$b.fa"
}
export -f filter_one
export MIN MAX

ls "$IN"/*.fa | xargs -P "$THREADS" -I{} bash -c 'filter_one "$1"' _ {}

n_lt=$(cat 03_length_filter/lt200/*.fa    2>/dev/null | grep -c '^>')
n_in=$(cat 03_length_filter/in_range/*.fa 2>/dev/null | grep -c '^>')
n_gt=$(cat 03_length_filter/gt6000/*.fa   2>/dev/null | grep -c '^>')

{
  echo "Length filter  ($(date -u))"
  echo "range kept: ${MIN}-${MAX} nt inclusive"
  printf "under %-5d %12d\n" "$MIN" "$n_lt"
  printf "in range    %12d  <- goes on to the rod screen\n" "$n_in"
  printf "over  %-5d %12d\n" "$MAX" "$n_gt"
  printf "total       %12d\n" "$(( n_lt + n_in + n_gt ))"
} > 03_length_filter/SUMMARY_lenfilter.txt
cat 03_length_filter/SUMMARY_lenfilter.txt
touch 03_length_filter/LENFILTER.DONE
