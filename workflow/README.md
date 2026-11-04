# workflow: the order the stages run in

One directory per stage, each with the script that runs it and a short
README. `run_screen.sh` runs them in order; `common.sh` is sourced by every
script and provides the settings and a few helpers.

| stage | script | reads | writes |
|---|---|---|---|
| 0 | `00_source/fetch_source.sh` | `[source] url` | the source archive |
| 1 | `01_kraken_filter/kraken_filter.sh` | the archive, a Kraken2 database | `unclassified/`, `calls/`, `reports/` |
| 2 | `02_circular_overlap/label_overlap.sh` | `unclassified/` | `labelled/` |
| 3 | `03_length_filter/length_filter.sh` | `labelled/` | `in_range/`, `too_short/`, `too_long/` |
| 4 | `04_rod_screen/rod_screen.sh` | `in_range/`, the Lebowski bundle | `chunks/`, `results/` |
| 5 | `05_results/make_results.sh` | `chunks/`, `results/` | `rods.csv`, `rods_with_ribozyme.csv`, `shortlist.csv` |
| 6 | `06_package/package_run.sh` | the archive, `calls/`, `labelled/` | `record_manifest.tsv.zst`, `MD5SUMS` |
| 7 | `07_dotbracket/fold_rods.sh` | `rods.csv` | `rods_dotbracket.tsv.zst` |

All of it lands under `[run] work_dir` (default `work/`), one subdirectory
per stage, with a `summary.txt` of the counts and a `DONE` marker when the
stage finished.

## Running

```bash
export ASSINIBOINE_CONFIG=config/runs/my_run.toml   # optional; defaults otherwise
./workflow/run_screen.sh          # everything
./workflow/run_screen.sh 2 3      # just stages 2 and 3
./workflow/02_circular_overlap/label_overlap.sh     # one stage directly
```

A stage whose `DONE` marker exists is skipped. To run it again, delete the
marker. Stages 1, 4 and 7 also keep a `.done` marker per part or chunk, so
an interrupted run resumes where it stopped.

## How the scripts are written

Every script has the same shape:

1. a header comment stating what goes in and what comes out,
2. `source common.sh`, which loads the settings and moves to the repo root,
3. checks that the inputs and tools exist, with a message saying what to do,
4. the work, usually `xargs -P` running one `assiniboine` command per part,
5. a summary and the `DONE` marker.

The scripts decide *when* things run and *how many at once*. *What* is done
to each record is in `src/assiniboine/`; a script never implements a rule
itself. Thread and worker counts come from the `[compute]` section of the
settings and change nothing about the result.
