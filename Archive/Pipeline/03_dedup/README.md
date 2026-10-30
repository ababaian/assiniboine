# 03_dedup -- collapse exact duplicate sequences

    in      594,734,382  (02_length_split/le6000/)
    kept    545,483,299  unique      -> this is the step-2 input
    dropped  49,251,083  8.28%       -> recorded in dedup_map.tsv, reversible

Folding the same sequence twice produces an identical feature row, so this is
pure waste removal. It is also **reversible**: every dropped id is mapped to the
representative that was kept, so a rod hit can be expanded back to every
accession that carried that circle.

## Items

| item | what it is |
|---|---|
| `dedup_le6000.fa` | **the output**: 156 G, 545,483,299 records, sorted by sequence |
| `dedup_map.tsv` | 49,251,083 lines, `dropped_id <TAB> kept_id` |
| `SUMMARY_dedup.txt`, `dedup_stats.txt` | the counts above |
| `DEDUP_COST.txt` | `records=545483299 mean=235.3 sum_l3=1.0554e+17` |
| `dedup_exact.sh` | the job |
| `measure_cost.sh` | the sum-of-l^3 pass that set the step-2 projection |

## Verified

- `kept + dropped == 594,734,382` exactly -- nothing vanished
- output record count `== 545,483,299`, map lines `== 49,251,083`
- `awk 'NR%2==0' dedup_le6000.fa | sort -c -u` exits 0, i.e. the output is
  **provably** sorted and duplicate-free

That last check mattered: one part alone (`part_000`, the earliest accessions)
holds 8,570,043 internal duplicates, 17% of the global total, which made 8.28%
look too low. It is not -- part_000 is simply unusually redundant.

## Method, and why not the obvious script

`Lebowski/Scripts/dedup_fasta.py` is the intended tool but is single-core pure
Python with Booth's algorithm per record and an in-memory dict, so at 595M
records it is a multi-day job by itself. This does the exact-duplicate pass with
GNU sort (C, parallel, external merge): flatten to `seq <TAB> header`, sort on
the sequence, keep the first of each run of equal keys, map the rest. ~32 min.

## What it does NOT do

Rotations and reverse complements are still separate records -- the same circle
assembled from a different start position survives this pass. That is what
`dedup_fasta.py --circular` adds, and it needs reimplementing (shard on a
rotation- and revcomp-invariant key, then canonicalise within shard) to run at
this scale. Not done; it is the largest remaining reduction available.
