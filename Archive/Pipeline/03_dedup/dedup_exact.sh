#!/usr/bin/env bash
# Global exact-sequence dedup of the length-filtered unclassified circles.
#
# Why not Scripts/dedup_fasta.py: that is single-core pure Python with Booth's
# algorithm per record and an in-memory dict, so at 595M records it is a
# multi-day job on its own. This does the exact-duplicate pass with GNU sort
# (C, parallel, external merge) and keeps a duplicate map, so nothing is lost:
# every dropped id can be traced back to the representative that was kept.
#
# It does NOT collapse rotations or reverse complements -- that is what
# dedup_fasta.py --circular adds, and it needs a different implementation to
# run at this scale.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
export LC_ALL=C
mkdir -p dedup tmpsort
rm -f DEDUP.DONE DEDUP.FAILED

# seq <TAB> full-header, so the sort key is the sequence itself.
echo "[$(date -u +%H:%M:%S)] flattening to seq<TAB>header"
ls le6000/*.fa | xargs -P12 -I{} sh -c '
  awk "/^>/{if(h)print toupper(seq) \"\t\" hdr; hdr=substr(\$0,2); seq=\"\"; h=1; next}
       {seq=seq \$0}
       END{if(h)print toupper(seq) \"\t\" hdr}" "$1" > dedup/$(basename "$1" .fa).tsv
' _ {}
echo "[$(date -u +%H:%M:%S)] flattened: $(du -sh dedup | cut -f1)"

# One representative per distinct sequence, plus the map of everything dropped.
echo "[$(date -u +%H:%M:%S)] sorting + collapsing"
sort -t$'\t' -k1,1 -S 200G --parallel=48 -T tmpsort dedup/*.tsv \
 | awk -F'\t' -v OFS='\t' '
     $1 != prev { print ">" $2 > "dedup_le6000.fa"; print $1 > "dedup_le6000.fa"
                  prev = $1; keptid = $2; kept++; next }
     { split($2, a, " "); split(keptid, b, " "); print a[1], b[1] > "dedup_map.tsv"; dropped++ }
     END { printf "kept %d\ndropped %d\n", kept, dropped > "/dev/stderr" }' 2> dedup_stats.txt
rc=$?
if [ $rc -ne 0 ]; then echo "FAILED rc=$rc"; touch DEDUP.FAILED; exit 1; fi

{
  echo "Exact-sequence dedup  ($(date -u))"
  echo "input (unclassified, <=6000 nt): 594734382"
  cat dedup_stats.txt
  echo "unique FASTA: $(du -sh dedup_le6000.fa | cut -f1)"
} > SUMMARY_dedup.txt
cat SUMMARY_dedup.txt
rm -rf dedup tmpsort
touch DEDUP.DONE
echo "[$(date -u +%H:%M:%S)] done"
