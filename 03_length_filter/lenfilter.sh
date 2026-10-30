#!/usr/bin/env bash
# Keep the unclassified circles between 200 and 6000 nt inclusive.
#
# The 6000 nt ceiling is a bug workaround, not a biological filter: RNAfold
# hits "exceeds addressable range" on an oversized circle and then STOPS,
# exiting 0, so every record after it in the batch is silently lost.
#
# The 200 nt floor IS a biological filter. Circles shorter than that are below
# the size of any known viroid-like agent and dominated by assembly fragments.
# Kraken2's own caveat points the same way: short sequences carry too few
# k-mers to accumulate classification evidence, so the unclassified set is
# enriched for short junk rather than short novelty.
#
# Nothing is deleted. The out-of-range records are written to lt200/ and
# gt6000/ so either bound can be revisited without re-running stage 1.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
MIN=200
MAX=6000

mkdir -p 03_length_filter/lt200 03_length_filter/in_range 03_length_filter/gt6000

ls 02_circular_overlap/circular/*.fa | xargs -P12 -I{} sh -c '
  b=$(basename "$1" .fa)
  awk -v s="03_length_filter/lt200/$b.fa" -v u="03_length_filter/in_range/$b.fa" -v o="03_length_filter/gt6000/$b.fa" \
      -v min='"$MIN"' -v max='"$MAX"' "
    function flush(){ if (!h) return
      if (len < min)      print rec > s
      else if (len <= max) print rec > u
      else                 print rec > o }
    /^>/ { flush(); rec = \$0; len = 0; h = 1; next }
         { rec = rec \"\n\" \$0; len += length(\$0) }
    END  { flush() }" "$1"
' _ {}

n_lt=$(cat 03_length_filter/lt200/*.fa 2>/dev/null | grep -c '^>')
n_in=$(cat 03_length_filter/in_range/*.fa 2>/dev/null | grep -c '^>')
n_gt=$(cat 03_length_filter/gt6000/*.fa 2>/dev/null | grep -c '^>')
total=$(( n_lt + n_in + n_gt ))

{
  echo "Length filter  ($(date -u))"
  echo "range kept: ${MIN}-${MAX} nt inclusive"
  printf "under %-5d %12d\n" "$MIN" "$n_lt"
  printf "in range    %12d  <- goes on to the rod screen\n" "$n_in"
  printf "over  %-5d %12d\n" "$MAX" "$n_gt"
  printf "total       %12d\n" "$total"
} > 03_length_filter/SUMMARY_lenfilter.txt
cat 03_length_filter/SUMMARY_lenfilter.txt
touch 03_length_filter/LENFILTER.DONE
