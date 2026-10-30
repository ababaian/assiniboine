#!/usr/bin/env bash
# Length histogram over the 595M unclassified circles, one parallel pass.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
mkdir -p lenhist
ls unclassified/unclass_part_*.fa | xargs -P12 -I{} sh -c '
  awk "/^>/{if(l>0){n++;s+=l;
        if(l<=500)b1++; else if(l<=1000)b2++; else if(l<=2000)b3++;
        else if(l<=6000)b4++; else if(l<=10000)b5++; else if(l<=20000)b6++;
        else if(l<=32000)b7++; else b8++;
        if(l>mx)mx=l}
       l=0;next}
      {l+=length(\$0)}
      END{if(l>0){n++;s+=l; if(l<=500)b1++; else if(l<=1000)b2++; else if(l<=2000)b3++;
          else if(l<=6000)b4++; else if(l<=10000)b5++; else if(l<=20000)b6++;
          else if(l<=32000)b7++; else b8++; if(l>mx)mx=l}
       print n,s,b1+0,b2+0,b3+0,b4+0,b5+0,b6+0,b7+0,b8+0,mx+0}" "$1" > lenhist/$(basename "$1").hist
' _ {}
awk '{n+=$1;s+=$2;b1+=$3;b2+=$4;b3+=$5;b4+=$6;b5+=$7;b6+=$8;b7+=$9;b8+=$10; if($11>mx)mx=$11}
 END{printf "records      %d\ntotal nt     %d\nmean len     %.1f\nmax len      %d\n\n",n,s,s/n,mx;
     printf "   <=500 nt  %12d  %6.2f%%\n 501-1000    %12d  %6.2f%%\n1001-2000    %12d  %6.2f%%\n2001-6000    %12d  %6.2f%%\n",b1,100*b1/n,b2,100*b2/n,b3,100*b3/n,b4,100*b4/n;
     printf "6001-10000   %12d  %6.2f%%\n10001-20000  %12d  %6.2f%%\n20001-32000  %12d  %6.2f%%\n  >32000 nt  %12d  %6.2f%%\n\n",b5,100*b5/n,b6,100*b6/n,b7,100*b7/n,b8,100*b8/n;
     printf "kept at <=6000: %d (%.2f%%)   dropped: %d\n",b1+b2+b3+b4,100*(b1+b2+b3+b4)/n,b5+b6+b7+b8}' lenhist/*.hist > LENGTH_HIST.txt
cat LENGTH_HIST.txt
touch LENHIST.DONE
