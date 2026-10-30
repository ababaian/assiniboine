# 02_length_split -- split at 6000 nt

This is a **bug workaround, not a biological filter**. It keeps 99.95% of
records.

    in      595,006,157  (01_kraken_filter/unclassified/)
    le6000  594,734,382  99.95%  -> goes on to 03_dedup
    gt6000      271,775   0.05%  -> parked, not screened

## Why it exists

RNAfold does not skip a circle that exceeds its addressable range -- it
**stops**. It prints `[WARNING] sequence length of 44528 exceeds addressable
range`, emits nothing further, and exits 0. Measured: 20,000 records in, 4,213
rows out, and the 4,213 were exactly the input prefix up to a 44,528-nt circle
at position 4,214. `run_pipeline.py` reported "Done. Wrote 4213 result rows".

At `--batch-size 100000` (the value in run_pipeline's own usage block) a single
oversized circle can cost most of a batch, silently. `fold.py` has a `--max-len`
guard and the merge code refers to it, but `run_pipeline.py` exposes no such
flag -- which is what the author's `#CONSIDERATIONS: maybe include a max length`
note was pointing at.

## Items

| item | what it is |
|---|---|
| `le6000/unclass_part_000.fa` … `_020.fa` | 21 FASTA, 170 G, 594,734,382 records <=6000 nt |
| `gt6000/unclass_part_000.fa` … `_020.fa` | 21 FASTA, 4.6 G, 271,775 records >6000 nt |
| `LENGTH_HIST.txt` | the length distribution |
| `lenfilter.sh` | the parallel split |
| `lenhist.sh` | the histogram pass |
| `cost_by_cap.raw` | per-file sums behind the cost table below |
| `lenhist/*.hist` | per-file histogram shards |
| `lenhist/*.runs` | per-file distinct SRA run lists |

## Length distribution (595,006,157 records, mean 243 nt, max 437,661)

       <=500 nt   576,427,866   96.88%
     501-1000      13,017,310    2.19%
    1001-2000       3,575,322    0.60%
    2001-6000       1,713,884    0.29%
    6001-10000        156,845    0.03%
    10001-20000        48,111    0.01%
    20001-32000        11,251    0.00%
       >32000 nt       55,568    0.01%

## Why the cutoff is not lower

RNAfold is O(n^3), so folding cost sits almost entirely in the tail. Measured
exactly (sum of l^3 over the <=6000 set = 1.091e17):

    cap(nt)   records kept    % recs   % of folding cost
    300        521,934,523    87.76%     3.82%
    500        576,427,866    96.92%     6.30%
    1000       589,445,176    99.11%    10.15%
    2000       593,020,498    99.71%    19.57%
    3000       593,865,176    99.85%    30.94%
    6000       594,734,382   100.00%   100.00%

The 0.15% above 3000 nt carry 69% of all the work. Tempting -- but the targets
live in exactly that range: obelisks ~1100 nt, ribozyviruses ~1700 nt,
ambiviruses ~5000 nt. A 1000-nt cap would exclude the things being hunted, and
a ~17 h per-record floor caps the saving anyway (0.84 days at 500 nt vs 3.0
days for everything). So the full <=6000 set is being folded.

## gt6000 is unfinished business

The 271,775 parked circles are not junk -- just untested. Those up to ~20,000
nt will fold, slowly; past that RNAfold refuses outright. Worth a separate
low-priority run with its own cap.
