# 03_length_filter -- keep 200 to 6000 nt

Two bounds, inclusive, for two different reasons. Nothing is deleted: the
out-of-range records are written out so either bound can be revisited without
re-running stage 1.

    in                     02_circular_overlap/labelled/  (all classes)
    lt200                  -> parked, below any known viroid-like agent
    in_range               -> goes on to the rod screen
    gt6000                 -> parked, RNAfold cannot address these

The October 2026 run used a ceiling only, at 6000 nt, and kept 594,734,382
records (99.95%), parking 271,775. The 200 nt floor was added afterwards, so
there is no measured in-range count for it yet: the finest bucket in
`LENGTH_HIST.txt` is `<=500`, the per-length `lenhist/*.hist` shards are gone,
and the source FASTAs were deleted in the October 2026 cleanup. The floor has
to be re-measured on a rerun.

## The floor bites unevenly across the overlap classes

The input arrives labelled by stage 2, and the two classes have different
length distributions, so the floor does not treat them alike. Measured on
10,000 real records:

    class      in     in range   kept
    circular  5,005     1,395   27.9%
    hairpin   4,995     3,724   74.6%

Circles are shorter to begin with and lose a further 30 nt to the overlap trim,
so the floor removes nearly three quarters of them while removing a quarter of
the hairpins. The screened set therefore comes out majority hairpin, which is
worth knowing before reading any aggregate rate off it. `ovl:` in the header
and `02_circular_overlap/overlap_class.tsv` are what to stratify on.

## Why the 6000 nt ceiling exists

RNAfold does not skip a circle that exceeds its addressable range, it
**stops**. It prints `[WARNING] sequence length of 44528 exceeds addressable
range`, emits nothing further, and exits 0. Measured: 20,000 records in, 4,213
rows out, and the 4,213 were exactly the input prefix up to a 44,528-nt circle
at position 4,214. `run_pipeline.py` reported "Done. Wrote 4213 result rows".

At `--batch-size 100000` (the value in run_pipeline's own usage block) a single
oversized circle can cost most of a batch, silently. `fold.py` has a `--max-len`
guard and the merge code refers to it, but `run_pipeline.py` exposes no such
flag, which is what the author's `#CONSIDERATIONS: maybe include a max length`
note was pointing at.

## Why the 200 nt floor exists

Unlike the ceiling, this one is a biological filter. Circles shorter than
200 nt are below the size of any known viroid-like agent and are dominated by
assembly fragments. Kraken2's own caveat points the same way: short sequences
carry too few k-mers to accumulate classification evidence, so the unclassified
set is enriched for short junk rather than short novelty.

Measured against the October run's output, which had no floor, these are the
records it would have excluded:

    rod calls                        25,222,331
    rod under 200 nt                 12,487,733   49.51%
    rod with a ribozyme                  46,432
      of those, under 200 nt                677    1.46%
    shortlist rows under 200 nt               0   shortest is 309 nt

So the floor discards about half of all rod calls while costing 1.5% of the
ribozyme-bearing ones and nothing from the shortlist. Nothing in that run was
called rod below 150 nt at all.

## Items

| item | what it is |
|---|---|
| `lt200/unclass_part_*.fa` | records under 200 nt, parked |
| `in_range/unclass_part_*.fa` | 200 to 6000 nt, the output that goes on |
| `gt6000/unclass_part_*.fa` | records over 6000 nt, parked |
| `SUMMARY_lenfilter.txt` | the three counts, written by the runner |
| `LENGTH_HIST.txt` | the October run's length distribution |
| `lenfilter.sh` | the parallel three-way split |
| `lenhist.sh` | the histogram pass |
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

Note the first bucket holds 96.88% of everything, which is why the 200 nt floor
is a large change rather than a trim, and why its exact cost is not recoverable
from this table.

## Why the ceiling is not lower

RNAfold is O(n^3), so folding cost sits almost entirely in the tail. Measured
exactly (sum of l^3 over the <=6000 set = 1.091e17):

    cap(nt)   records kept    % recs   % of folding cost
    300        521,934,523    87.76%     3.82%
    500        576,427,866    96.92%     6.30%
    1000       589,445,176    99.11%    10.15%
    2000       593,020,498    99.71%    19.57%
    3000       593,865,176    99.85%    30.94%
    6000       594,734,382   100.00%   100.00%

The 0.15% above 3000 nt carry 69% of all the work. Tempting, but the targets
live in exactly that range: obelisks ~1100 nt, ribozyviruses ~1700 nt,
ambiviruses ~5000 nt. A 1000-nt cap would exclude the things being hunted, and
a per-record floor caps the saving anyway. So the full in-range set is folded.

## gt6000 is unfinished business

The 271,775 parked circles are not junk, just untested. Those up to ~20,000 nt
will fold, slowly; past that RNAfold refuses outright. Worth a separate
low-priority run with its own cap.
