# 07_dotbracket: MFE structures of every rod

Stage 4 folds every screened circle but keeps only features computed from each
structure (`mfe_per_nt`, `frac_paired`, stem and loop counts); the dot-bracket
strings are discarded with each batch. This step refolds the 11,308,939 rods in
`05_results` with the command stage 4 used, `RNAfold --circ --noPS` (ViennaRNA
2.7.2, env `circpipe`), and keeps the structures.

    in    06_package/upload/run-2026-11/05_results/rods.csv.zst
    out   rods_dotbracket.tsv.zst   sample_name, length, mfe, dot_bracket

Rows are in the same order as `rods.csv`. `mfe` is in kcal/mol.

## Running

```bash
setsid nohup ~/bin/watchjob -n "k2-circ dotbracket" \
    -s 'test -e 07_dotbracket/DOTBRACKET.DONE' -- 07_dotbracket/run_dotbracket.sh \
    > 07_dotbracket/run_dotbracket.log 2>&1 < /dev/null &
```

Rods are sorted longest first and dealt round-robin into 460 parts, one
single-threaded RNAfold each, so every part carries the same mix of lengths.
`NPART` sets the part count. Resume-safe: finished parts are skipped.

Folding cost rises steeply with length: about 0.1 s per rod at 200 to 400 nt and
63 s at 5,000 to 6,000 nt. The 83% of rods under 400 nt cost a quarter of the
total, about 1,000 CPU-hours. On 460 cores of watson it took 2 h 47 min
(2026-11-03).

## Checks

- **Per part:** every rod in comes out with a structure and an MFE, and each
  structure is as long as its sequence and its `length`.
- **Assembly:** 11,308,939 rows, each rod exactly once, none missing.
- **Output:** re-read after compression, every `dot_bracket` length equals `length`.

## Data

    s3://petadex/circs-results/run-2026-11/07_dotbracket/rods_dotbracket.tsv.zst   (548 MB)
