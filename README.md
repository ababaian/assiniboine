# Logan selfloops rod-like circle screen

This pipeline screens every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them.

The input is Logan's selfloops archive, every circular contig assembled from
the SRA, one record per circle per sequencing run. The output is a ranked
shortlist of candidates, with the full scored table behind it.

This repo holds code and methods only. All data lives in S3, see
[Data](#data). Commands for reproducing are available in [`REPRODUCING.md`](REPRODUCING.md).

## Pipeline

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="review/pipeline_flow_800dpi_transparent.png">
  <img alt="Sankey of records through each pipeline stage" src="review/pipeline_flow_800dpi.png">
</picture>

| stage | folder | what it does |
|---|---|---|
| 0 | [`00_source/`](00_source/) | fetch the Logan selfloops archive |
| 1 | [`01_kraken_filter/`](01_kraken_filter/) | drop anything core_nt can already name |
| 2 | [`02_circular_overlap/`](02_circular_overlap/) | trim the terminal 30-nt overlap, split off non-circles |
| 3 | [`03_length_filter/`](03_length_filter/) | keep 200 to 6000 nt |
| 4 | [`04_rod_screen/`](04_rod_screen/) | fold, search for ribozymes, classify rod |
| 5 | [`05_results/`](05_results/) | reduce to the rod, ribozyme and shortlist tables |
| | [`model/`](model/) | the rodnotrod classifier: features, weights, S3 location |
| | [`env/`](env/) | the conda environment |
| | [`analysis/`](analysis/) | side analyses, not part of the screen |

## Result

From the October 2026 run, which used an earlier version of this pipeline,
tagged `run-2026-10`:

900,042,456 circles, 595,006,157 unnamed by core_nt, 545,483,299 screened,
**25,222,331 called rod**. Of those, **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands**. The shortlist is 2,056 rows, whose
top tier is 56 circles.

The caveats that qualify those numbers, and the defects carried into that
run's output tables, are in [`NOTES.md`](NOTES.md). Read them before quoting
any result.

## Data

Data is stored on S3.

**Pipeline and model** (32 MB)

    s3://petadex/circs-results/model/

**Stage 1 outputs** (3.2 MB)

    s3://petadex/circs-results/run-2026-10/kraken_filter/

**Screen and result tables** (16.2 GB)

    s3://petadex/circs-results/run-2026-10/rod_screen/

**List all files** (12 files, 16.2 GB in total)

    aws s3 ls s3://petadex/circs-results/ --recursive --no-sign-request

**Download the shortlist** (814 KB)

    curl -O https://petadex.s3.amazonaws.com/circs-results/run-2026-10/rod_screen/shortlist.csv
