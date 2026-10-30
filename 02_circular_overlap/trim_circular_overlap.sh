#!/usr/bin/env bash
# Trim the terminal 30-nt overlap Logan writes into selfloops records, and
# label every record with how it closes. This stage LABELS; it does not gate.
# Every input record goes downstream.
#
# Logan assembles at k=31, so a unitig that closes into a circle is emitted
# with its first k-1 = 30 nt repeated as its last 30 nt. Left in place that
# overlap inflates every length by 30 and, once RNAfold --circ joins the ends,
# inserts a spurious tandem copy of those 30 nt into the folded structure. So
# the circular class is trimmed. The other classes have no duplicated end and
# are passed through untouched.
#
# Classification keys on the GFA self-link orientation in the header, which is
# the assembler's own statement about how the unitig closes, and then verifies
# it against the sequence. Sequence alone is not safe: a low-complexity AT- or
# CG-rich terminus is its own reverse complement by accident.
#
#   circular    L:-:x:- and L:+:x:+, AND first 30 == last 30
#               -> trailing 30 nt trimmed
#   hairpin     L:-:x:+ or L:+:x:-; the terminal 30-mer is its own reverse
#               complement, so the self-loop is a graph artifact rather than a
#               closed molecule -> passed through untrimmed
#   unmatched   header says circular but the sequence disagrees, or no
#               recognisable link -> passed through untrimmed
#
# Outputs, all of which go on to the length filter:
#   labelled/*.fa         every record, trimmed where applicable, header tagged
#   overlap_class.tsv     id, class, nt trimmed -- join to results by sample_name
#   SUMMARY_overlap.txt   the counts
#
# The header gains `ovl:<class> trim:<nt>` after the existing fields. The
# pipeline takes sample_name from the first whitespace-delimited token, which
# is untouched, so ids and joins are unaffected.
#
# Usage:
#   trim_circular_overlap.sh [-k 30] [-o OUTDIR] [-j threads] <in.fa|dir|->
#
# See ../analysis/circular_overlap/ for the measurements behind k=30 and the
# three classes.
set -uo pipefail

K=30
OUTDIR=.
THREADS=12
while getopts "k:o:j:h" opt; do
  case $opt in
    k) K=$OPTARG ;;
    o) OUTDIR=$OPTARG ;;
    j) THREADS=$OPTARG ;;
    *) sed -n '2,40p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
IN=${1:--}

AWK=$(command -v mawk || command -v awk)
mkdir -p "$OUTDIR"/labelled "$OUTDIR"/class

# One record is two lines: header, then unwrapped sequence. Output keeps that
# shape, because the chunker in ../04_rod_screen/ splits on a fixed line count
# and a wrapped FASTA would misalign every record after the first.
label_one() {
  f="$1"; k="$2"; outdir="$3"; awkbin="$4"
  if [ "$f" = "-" ]; then b=stdin; else b=$(basename "$f"); b=${b%.fa}; b=${b%.fasta}; fi
  LC_ALL=C "$awkbin" -v k="$k" -v tag="$b" \
      -v fo="$outdir/labelled/$b.fa" \
      -v ft="$outdir/class/$b.tsv" '
    /^>/ { hdr = $0; next }
    {
      s = toupper($0); n = length(s)
      id = substr(hdr, 2); sub(/[ \t].*/, "", id)

      rev_link = (hdr ~ /L:\+:[0-9]+:-/ || hdr ~ /L:-:[0-9]+:\+/)
      fwd_link = (hdr ~ /L:-:[0-9]+:-/  && hdr ~ /L:\+:[0-9]+:\+/)

      if (rev_link && !fwd_link) {
        cls = "hairpin";   out = s;                     cut = 0
      } else if (fwd_link && n >= 2 * k && substr(s, 1, k) == substr(s, n - k + 1)) {
        cls = "circular";  out = substr(s, 1, n - k);   cut = k
      } else {
        cls = "unmatched"; out = s;                     cut = 0
      }

      print hdr " ovl:" cls " trim:" cut "\n" out > fo
      print id "\t" cls "\t" cut > ft
      c[cls]++
    }
    END { printf "%s\tcircular=%d\thairpin=%d\tunmatched=%d\n",
                 tag, c["circular"]+0, c["hairpin"]+0, c["unmatched"]+0 > "/dev/stderr" }' "$f"
}
export -f label_one

if [ -d "$IN" ]; then
    ls "$IN"/*.fa | xargs -P "$THREADS" -I{} bash -c \
        'label_one "$1" "$2" "$3" "$4"' _ {} "$K" "$OUTDIR" "$AWK"
else
    label_one "$IN" "$K" "$OUTDIR" "$AWK"
fi

cat "$OUTDIR"/class/*.tsv > "$OUTDIR/overlap_class.tsv" 2>/dev/null
rm -rf "$OUTDIR/class"

n_tot=$(wc -l < "$OUTDIR/overlap_class.tsv")
n_c=$(awk -F'\t' '$2=="circular"'  "$OUTDIR/overlap_class.tsv" | wc -l)
n_h=$(awk -F'\t' '$2=="hairpin"'   "$OUTDIR/overlap_class.tsv" | wc -l)
n_u=$(awk -F'\t' '$2=="unmatched"' "$OUTDIR/overlap_class.tsv" | wc -l)

{
  echo "Circular overlap labelling  ($(date -u))"
  echo "overlap length k-1: $K"
  echo "all classes go on to the length filter; this stage gates nothing"
  printf "circular  (trimmed %d nt) %12d\n" "$K" "$n_c"
  printf "hairpin   (untrimmed)    %12d\n" "$n_h"
  printf "unmatched (untrimmed)    %12d\n" "$n_u"
  printf "total                    %12d\n" "$n_tot"
} > "$OUTDIR/SUMMARY_overlap.txt"
cat "$OUTDIR/SUMMARY_overlap.txt"
