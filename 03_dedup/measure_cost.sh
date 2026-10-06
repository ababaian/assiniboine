#!/usr/bin/env bash
# Exact folding-cost budget (sum of l^3) for the deduped step-2 input.
cd /watson/rnalab/dzhu/k2-circ-runs
awk 'NR%2==0{n++; l=length($0); s+=l; c+=l*l*l
      if(l<=500){n5++;c5+=c5*0+l*l*l} }
     END{printf "deduped records=%d mean=%.1f sum_l3=%.4e\n",n,s/n,c}' dedup_le6000.fa > DEDUP_COST.txt 2>&1
echo done >> DEDUP_COST.txt
