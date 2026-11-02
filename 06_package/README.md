# 06_package: the S3 upload set

Stages 1 to 3 write about 560 GB of FASTA, but every record in them is a record of
the source archive, dropped, trimmed or filed by a fixed rule. This step replaces them
with a one-row-per-record manifest, proves the manifest plus the source rebuilds every
stage 1 to 3 file byte for byte, and builds the files for
`s3://petadex/circs-results/run-2026-11/`.

Nothing is uploaded and nothing from the run is deleted.

```bash
setsid nohup ~/bin/watchjob -n "k2-circ package" -- 06_package/run_package.sh \
    > 06_package/run_package.log 2>&1 < /dev/null &      # manifest + rebuild check
setsid nohup ~/bin/watchjob -n "k2-circ upload set" -- 06_package/build_upload.sh \
    > 06_package/build_upload.log 2>&1 < /dev/null &     # the upload files
```

`run_package.sh` also stages an earlier per-chunk layout under `staging/`; only its
`manifest/` parts are used. `build_upload.sh` refuses to run until the rebuild check
has passed.

| script | job |
|---|---|
| `split_source.sh` | Cuts the archive into the 21 stage 1 parts (45,000,000 records each), temporarily |
| `build_manifest.sh` | Writes the manifest parts, checking every record against the Kraken2 calls and the stage 2 output |
| `rebuild_stage.sh` | Rebuilds stages 1 to 3 from source and manifest. `--md5` hashes instead of writing |
| `run_package.sh` | Runs the three above and compares every rebuilt file with the run's |
| `build_upload.sh` | Builds the upload set from the verified parts and the stage 4 and 5 output |

## The upload set

`upload/run-2026-11/`, one or two files per step. The source archive is already on
S3 (`s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst`)
and is not copied. Column definitions are in `upload/run-2026-11/README.md`, which
goes up with the data.

| file | rows | size |
|---|---:|---:|
| `01_kraken_filter/classified_records.tsv.zst` | 305,036,299 | 2.5 GB |
| `01_kraken_filter/unclassified_records.tsv.zst` | 595,006,157 | 4.3 GB |
| `01-03_records/record_manifest.tsv.zst` | 900,042,456 | 6.6 GB |
| `04_rod_screen/screen.parquet` | 161,292,329 | 4.4 GB |
| `05_results/rods.csv.zst` | 11,308,939 | 956 MB |

The record lists and the manifest are concatenated zstd frames, one per part. Any
zstd reader treats them as one file.

## Rebuilding stages 1 to 3

```bash
06_package/rebuild_stage.sh selfloops.v1.1.fa.zst record_manifest.tsv.zst out/
```

This writes the classified, unclassified, labelled and length-filtered FASTAs per part,
named as the run named them. Stage 4 chunks are
`cat out/03_length_filter/in_range/*.fa | split -d -a3 -l 3409272`.

Kraken2's per-record k-mer hit lists are not kept, only the taxid. Getting them back
means rerunning Kraken2 on `core_nt` built October 2025, at confidence 0.1.

## Checks

- **Manifest:** every source record matches, in order, either the next Kraken2 call (same id
  and length) or the next stage 2 record (same header plus its tag, length equal to
  source minus trim). Both streams are used up exactly.
- **Manifest totals:** they equal the run's stage summaries, and each part's classified count equals
  its Kraken2 log.
- **Rebuild:** all 126 stage 1 to 3 files rebuilt from source and manifest have the same md5 as
  the run's.
- **Chunks:** the concatenated stage 4 chunks have the same md5 as the concatenated in-range
  parts.
- **Single manifest:** it holds exactly the rows of the verified parts. The record lists
  have the expected row counts.
- **`screen.parquet`:** it has 161,292,329 rows and 11,308,939 rods. The seven repeated
  ribozyme columns in the pipeline header were identical in every row and are dropped.
- **`rods.csv`:** it reproduces the stage 5 counts (43,887 with a ribozyme, 14,806 on both
  strands), and every sequence length equals its `length`.
