# Logan selfloops rod-like circle screen

This pipeline screens every circular contig Logan assembled from the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them.

The input is Logan's selfloops archive, every circular contig assembled from
the SRA, one record per circle per sequencing run.

This repo holds code and methods only. All data lives in S3, see
[Data](#data). Commands for reproducing are available in [`REPRODUCING.md`](REPRODUCING.md).

## Pipeline

![Sankey of records through each pipeline stage](review/pipeline_flow_800dpi.png)

| stage | folder | what it does |
|---|---|---|
| 0 | [`00_source/`](00_source/) | fetch the Logan selfloops archive |
| 1 | [`01_kraken_filter/`](01_kraken_filter/) | drop anything core_nt can already name |
| 2 | [`02_circular_overlap/`](02_circular_overlap/) | trim the terminal 30-nt overlap, label circular or hairpin |
| 3 | [`03_length_filter/`](03_length_filter/) | keep 200 to 6000 nt |
| 4 | [`04_rod_screen/`](04_rod_screen/) | fold, search for ribozymes, classify rod |
| 5 | [`05_results/`](05_results/) | reduce to the annotated rod table |
| | [`model/`](model/) | the rodnotrod classifier: features, weights, S3 location |
| | [`env/`](env/) | the conda environment |
| | [`analysis/`](analysis/) | side analyses, not part of the screen |

## Result

Updated November 2026 run. Compared with the October run (tag `run-2026-10`),
this run trims Logan's 30 nt circular overlap, screens only 200 to 6,000 nt and
does not deduplicate.

See the [headline figure](#pipeline):

900,042,456 circles -> 595,006,157 unnamed by core_nt -> 161,292,329 screened -> **11,308,939 called rod** (7.01 %) -> **43,887 carry a ribozyme** -> **14,806 carry ribozymes on both strands**, 47 of them corroborated.

- The screened set is 70 % smaller than October's, mostly from the 200 nt floor, but rods with a ribozyme fell only 5.5 %.
- Hairpins are called rod at twice the circle rate (12.39 % vs 6.21 %), the excess all below 500 nt.

## Data

Data is stored on S3. Only the stage 5 rod table carries sequences. Stage 1 to 3
records are sequence-free and are rebuilt from the Source archive plus the record
manifest with [`06_package/rebuild_stage.sh`](06_package/rebuild_stage.sh).

**Source** (83 GB, Logan's bucket)

    s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst

**Stage 1: classified records** (2.5 GB)

    s3://petadex/circs-results/run-2026-11/01_kraken_filter/classified_records.tsv.zst

**Stage 1: unclassified records** (4.3 GB)

    s3://petadex/circs-results/run-2026-11/01_kraken_filter/unclassified_records.tsv.zst

**Stages 1 to 3: record manifest** (6.6 GB)

    s3://petadex/circs-results/run-2026-11/01-03_records/record_manifest.tsv.zst

**Stage 4: every screened circle** (4.4 GB)

    s3://petadex/circs-results/run-2026-11/04_rod_screen/screen.parquet

**Stage 5: every rod, annotated, with sequence** (956 MB)

    s3://petadex/circs-results/run-2026-11/05_results/rods.csv.zst

**Pipeline and model** (32 MB)

    s3://petadex/circs-results/model/

**List all files**

    aws s3 ls s3://petadex/circs-results/ --recursive --no-sign-request
