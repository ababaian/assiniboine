# archive

Superseded work, kept because the existing results depend on it.

## original_pipeline/

The pipeline as it stood for the October 2026 run, verbatim at commit
`2773b5d`. This is what produced everything in
`s3://petadex/circs-results/`, so it is the method record for that data and
should not be edited.

`original_pipeline/README.md` is the guide to it: the stages, the verification
checks, the commands as they ran, the headline result and where the data lives.
`PIPELINE_README.md` is the original top-level doc as written at the time.

It differs from the current pipeline in three ways:

- it had an exact-deduplication stage, `03_dedup/`, which collapsed 8.28% of
  records
- its length filter had a ceiling only, at 6000 nt, with no lower bound
- it had no terminal-overlap trim, so every length in its output is 30 nt
  longer than the molecule and the ~37% of records that are not circles were
  folded as if they were

### original_pipeline/_run_outputs/

What the October run actually produced, under the stage names it used at the
time:

| path | what it is |
|---|---|
| `00_source/` | download and record-count markers |
| `01_kraken_filter/` | 21 taxonomy reports, per-part logs, run accession lists, the `share/` bundle uploaded with it |
| `02_length_split/` | per-file length histogram shards and the cost table |
| `03_dedup/` | the dedup counts and cost measurement |
| `06_env/` | the conda build log and its success marker |
| `step2/` | 320 per-chunk logs and the ribozyme candidate table |
| `step3/` | the three output tables, the 320 per-chunk stats, and the 5,000-row rescore validation slice |

`step3/rod_all.csv` is the full 25,222,331-row rod table, 6.6 GB. The three
tables here are byte-identical in size to the copies in
`s3://petadex/circs-results/step2_rod_screen/`.

The bulk inputs are gone: the 83 GiB source archive, the 174 G of unclassified
FASTAs, the length-split halves, `dedup_le6000.fa` and its reversible
`dedup_map.tsv`, and the 320 chunk files. They were deleted in the October 2026
disk cleanup, which freed about 890 G. Losing `dedup_map.tsv` means a hit in
those tables can no longer be expanded back to every SRA run that carried that
circle.
