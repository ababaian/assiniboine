# Step 2 results — rod screen over 545M circles

Companion to the step-1 Kraken2 bundle in the parent prefix. Start with
`SUMMARY_step2.txt`, then `shortlist.csv`.

| file | size | what it is |
|---|---|---|
| `SUMMARY_step2.txt` | 3 KB | all headline numbers and verification |
| `METHOD.md` | 4 KB | what was run, and **7 caveats — read before quoting** |
| `shortlist.csv` | 796 KB | **start here.** 2,056 ranked candidates |
| `rod_with_ribozyme.csv.gz` | 4.7 MB | 46,432 rod circles with >=1 ribozyme |
| `rod_all.csv.gz` | 1.6 GB | all 25,222,331 rod calls, 48 columns |

## Headline

545,483,299 circles screened. 25,222,331 (4.62%) called rod. Of those, 46,432
also carry a detected ribozyme, and **16,757 carry ribozymes on both strands** —
the hallmark of rolling-circle replication.

## Where to start: `shortlist.csv`

Two tiers, ranked by confidence:

- **Tier 1 (56 rows)** — ribozymes on *both* strands AND a corroborated locus
  (independent CMs agreeing on the same site). All twister-P1, two ribozymes
  each, mostly 400-800 nt. Strongest hit `SRR6337267_1290199_circle_1290199`,
  726 nt, confidence 0.996.
- **Tier 2 (2,000 rows)** — both strands, confidence >=0.8, no corroboration.

## Columns

`sample_name` is `<SRA run>_<contig>_circle_<contig>`, so the accession is the
prefix. Then `length`, `predicted_class`, `confidence`,
`below_confidence_floor` (**always False — dead column, see METHOD.md**), 43
feature columns, and finally `ribozyme_families`, `strands_present`,
`sources_detected`, `combination_detail`.

Two parsing notes: `combination_detail` contains commas inside quotes, so use a
real CSV reader, not `awk -F,`. And four ribozyme column names appear twice in
the header; pandas suffixes the second copy `.1`.

## Not here

The 320 per-chunk result files (129 GB, the full 545M rows) are **not** in this
public prefix. They are in the private bucket `s3://petadex-tmp/circs-results/`
and on watson at `/watson/rnalab/dzhu/k2-circ-runs/step2/results/`.
