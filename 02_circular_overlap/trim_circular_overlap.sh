#!/usr/bin/env bash
# Resolve the terminal 30-nt overlap that Logan writes into selfloops records,
# and separate true circles from reverse-complement self-links.
#
# Logan assembles at k=31, so a unitig that closes into a circle is emitted
# with its first k-1 = 30 nt repeated as its last 30 nt. Left in place that
# overlap inflates every length by 30 and, once RNAfold --circ joins the ends,
# inserts a spurious tandem copy of those 30 nt into the folded structure.
#
# Classification keys on the GFA self-link orientation in the header, which is
# the assembler's own statement about how the unitig closes, and then verifies
# it against the sequence. Sequence alone is not safe: a low-complexity AT- or
# CG-rich terminus is its own reverse complement by accident.
#
#   circular/  L:-:x:- and L:+:x:+, AND first 30 == last 30
#              -> trailing 30 trimmed, goes on to the length filter
#   hairpin/   L:-:x:+ or L:+:x:-  (terminal 30-mer is its own reverse
#              complement) -> NOT a circle, parked untrimmed
#   unmatched/ header says circular but the sequence does not agree, or no
#              recognisable link -> parked untrimmed, inspect
#
# Nothing is dropped. Every input record lands in exactly one output, and the
# three counts sum to the input.
#
# Usage:
#   trim_circular_overlap.sh [-k 30] [-o OUTDIR] [-j threads] <in.fa|dir|->
#     -k  overlap length (default 30, the measured value)
#     -o  output directory (default .)
#     -j  parallel workers when given a directory (default 12)
#
# See ../analysis/circular_overlap/ for the measurements behind k=30 and the
# three-class split.
set -uo pipefail

K=30
OUTDIR=.
THREADS=12
while getopts "k:o:j:h" opt; do
  case $opt in
    k) K=$OPTARG ;;
    o) OUTDIR=$OPTARG ;;
    j) THREADS=$OPTARG ;;
    *) sed -n '2,33p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
IN=${1:--}

AWK=$(command -v mawk || command -v awk)
mkdir -p "$OUTDIR"/circular "$OUTDIR"/hairpin "$OUTDIR"/unmatched

# One record is two lines: header, then unwrapped sequence. Output keeps that
# shape, because the chunker in ../04_rod_screen/ splits on a fixed line count
# and a wrapped FASTA would misalign every record after the first.
trim_one() {
  f="$1"; k="$2"; outdir="$3"; awkbin="$4"
  if [ "$f" = "-" ]; then b=stdin; else b=$(basename "$f"); b=${b%.fa}; b=${b%.fasta}; fi
  LC_ALL=C "$awkbin" -v k="$k" -v tag="$b" \
      -v fc="$outdir/circular/$b.fa" \
      -v fh="$outdir/hairpin/$b.fa" \
      -v fu="$outdir/unmatched/$b.fa" '
    /^>/ { hdr = $0; next }
    {
      s = toupper($0); n = length(s)

      # the assembler says how it closes
      rev_link = (hdr ~ /L:\+:[0-9]+:-/ || hdr ~ /L:-:[0-9]+:\+/)
      fwd_link = (hdr ~ /L:-:[0-9]+:-/  && hdr ~ /L:\+:[0-9]+:\+/)

      if (rev_link && !fwd_link) {
        print hdr "\n" s > fh; nh++
      } else if (fwd_link && n >= 2 * k && substr(s, 1, k) == substr(s, n - k + 1)) {
        print hdr "\n" substr(s, 1, n - k) > fc; nc++
      } else {
        print hdr "\n" s > fu; nu++
      }
    }
    END { printf "%s\tcircular=%d\thairpin=%d\tunmatched=%d\n",
                 tag, nc+0, nh+0, nu+0 > "/dev/stderr" }' "$f"
}
export -f trim_one

if [ -d "$IN" ]; then
    ls "$IN"/*.fa | xargs -P "$THREADS" -I{} bash -c \
        'trim_one "$1" "$2" "$3" "$4"' _ {} "$K" "$OUTDIR" "$AWK"
else
    trim_one "$IN" "$K" "$OUTDIR" "$AWK"
fi

# Count without tripping over a class that produced no files.
count_fa() {
  local d="$1" n=0 f
  for f in "$d"/*.fa; do
    [ -e "$f" ] || continue
    n=$(( n + $(grep -c '^>' "$f") ))
  done
  echo "$n"
}
n_c=$(count_fa "$OUTDIR/circular")
n_h=$(count_fa "$OUTDIR/hairpin")
n_u=$(count_fa "$OUTDIR/unmatched")

{
  echo "Circular overlap resolution  ($(date -u))"
  echo "overlap length k-1: $K"
  printf "circular  (trimmed)   %12d  -> goes on to the length filter\n" "$n_c"
  printf "hairpin   (untrimmed) %12d  -> parked, not circular\n" "$n_h"
  printf "unmatched (untrimmed) %12d  -> parked, inspect\n" "$n_u"
  printf "total                 %12d\n" "$(( n_c + n_h + n_u ))"
} > "$OUTDIR/SUMMARY_overlap.txt"
cat "$OUTDIR/SUMMARY_overlap.txt"
