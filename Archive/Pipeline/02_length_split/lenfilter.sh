#!/usr/bin/env bash
# Split the unclassified circles at 6000 nt.
# This is NOT a workload reduction (99.95% are kept) -- it exists because
# RNAfold hits "exceeds addressable range" on an oversized circle and then
# STOPS, exiting 0, so every record after it in the batch is silently lost.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
mkdir -p le6000 gt6000
ls unclassified/unclass_part_*.fa | xargs -P12 -I{} sh -c '
  b=$(basename "$1" .fa)
  awk -v u="le6000/$b.fa" -v o="gt6000/$b.fa" "
    function flush(){ if(!h) return; print (len<=6000? rec : rec) > (len<=6000? u : o) }
    /^>/{ flush(); rec=\$0; len=0; h=1; next }
    { rec=rec \"\n\" \$0; len+=length(\$0) }
    END{ flush() }" "$1"
' _ {}
echo "le6000: $(du -sh le6000 | cut -f1)  gt6000: $(du -sh gt6000 | cut -f1)"
touch LENFILTER.DONE
