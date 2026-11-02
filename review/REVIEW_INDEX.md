# Review index: Logan selfloops rerun, October to November 2026

Files to include in a review of this run, by pipeline step. Paths are relative to
`~/k2-circ-runs` on watson. Last updated 2026-11-02, after the run finished.

Status: **ready** = exists now. **pending** = the pipeline writes it when it
finishes. **to build** = proposed review table, not made yet. Sizes marked `~` are
estimates.

The record ID is the same at every step (`DRR000091_3841_circle_3841`), and the part
before the first `_` is the SRA run. Any table below can be joined on it.

| Step | In | Out | Removed | State |
|---|---|---|---|---|
| 0 Source | | 900,042,456 | | Done |
| 1 Kraken2 | 900,042,456 | 595,006,157 | 305,036,299 classified | Done |
| 2 Overlap | 595,006,157 | 595,006,157 | 0 (labels only) | Done |
| 3 Length | 595,006,157 | 161,292,329 | 433,713,828 parked | Done |
| 4 Rod screen | 161,292,329 | 11,308,939 rod | 149,983,390 not rod | Done 11-02 05:34 |
| 5 Results | 11,308,939 | 2,047 shortlisted | | Done 11-02 05:37 |

`review/pipeline_flow.svg` is a Sankey of this flow with final counts. `review/build_flow_figure.py` rebuilds it.

## Step 0: source

| File | Status | Why it is in the review |
|---|---|---|
| `00_source/total_records.txt` | ready | The starting count, 900,042,456 |
| `00_source/total_bytes.txt` | ready | Uncompressed size, 330,990,107,900 bytes |
| `00_source/download.log` | ready | Shows the download finished |
| `00_source/selfloops_download.sh` | ready | Where the archive came from |

The archive itself (`selfloops.v1.1.fa.zst`, 83 GB) does not belong in the review.

## Step 1: Kraken2 filter

| File | Status | Why it is in the review |
|---|---|---|
| `01_kraken_filter/SUMMARY_k2_filter.txt` | ready | Database, confidence and the classified split |
| `review/classified_taxa.csv` | ready | What the classified records are: 74,683 taxa with name, rank, lineage and counts (18 MB) |
| `review/target_taxa.csv` | ready | Records in the six viroid-like and small circular clades |
| `review/parts.csv` | ready | Classified and unclassified counts for each of the 21 parts |
| `review/step1_table_samples.md` | ready | Sample rows from these tables and what each column means |
| `review/build_step1_tables.py` | ready | Rebuilds those three tables and checks them against the run totals |
| `01_kraken_filter/rerun_calls.log` | ready | Shows the per-record calls matched the original reports |
| `01_kraken_filter/classified/part_NNN.kout.zst` | ready | Reference only. Per-record calls, 305,036,299 lines in 21 files (12 GB) |
| `06_package/staging/run-2026-11/manifest/part_NNN.tsv.zst` | building | `record_manifest`, which replaces the two proposed per-record lists: one row per source record with ID, run, length, Kraken2 status and taxid, closure class and the stage it ended at. See `06_package/README.md` |
| `review/classified_by_run.csv` | to build | Classified share and top clade for each SRA run, to find runs that dominate the classified set |

Known viroids are removed here on purpose, so they never reach the rod screen.
Counts are in `review/target_taxa.csv`.

## Step 2: circular overlap

| File | Status | Why it is in the review |
|---|---|---|
| `02_circular_overlap/SUMMARY_overlap.txt` | ready | 562,743,416 circular, 32,262,741 hairpin, 0 unmatched |
| `02_circular_overlap/trim_circular_overlap.sh` | ready | The rule behind the labels |
| `review/overlap_class_flow.csv` | to build | Circular and hairpin counts at source, classified, unclassified and in range. Shows Kraken2 and the length filter do not treat the classes alike |

Each header carries its class (`ovl:circular trim:30`), so step 2 needs no separate
per-record list. It can be added as a column to `unclassified_records.tsv.zst`.

## Step 3: length filter

| File | Status | Why it is in the review |
|---|---|---|
| `03_length_filter/SUMMARY_lenfilter.txt` | ready | 433,444,574 under 200 nt, 161,292,329 in range, 269,254 over 6,000 nt |
| `03_length_filter/LENGTH_HIST.txt` | ready | Length distribution. Its finest bucket is 500 nt and below, so it cannot show the 200 nt floor |
| `review/length_by_class.csv` | to build | Length histogram by overlap class in steps fine enough to show the 200 nt floor |

`lt200/`, `in_range/` and `gt6000/` are a full split of step 2. They add up to the
same 170 GB, so they are a second copy of it and do not need to go in the review.

## Step 4: rod screen

| File | Status | Why it is in the review |
|---|---|---|
| `04_rod_screen/SUMMARY_screen.txt` | ready | Chunks completed, input records, result rows, unresolved mismatches |
| `04_rod_screen/SCREEN.DONE` | ready | Written only if every chunk's rows match its input |
| `04_rod_screen/MISMATCH.txt` | absent | Exists only if a chunk failed its row check. Never written |
| `run_all.log`, `run_finish.log` | ready | Full run history, including retries and the extra workers |
| `04_rod_screen/run.sh`, `run_extra.sh` | ready | Worker settings and the completion gate |
| `review/chunk_qc.csv` | ready | For each chunk: rows, rod, rod share, rod at confidence 0.8, rod with ribozyme, split by closure class. Rod share runs from 0.02% to 22.83% and tracks hairpin share (r = 0.79) |
| `review/rod_by_class_length.csv` | ready | Rod share by overlap class and length band. Hairpins under 500 nt are rod at 14.90%, against 6.05% for circles |
| `review/ribozyme_families.csv` | ready | Rod records by ribozyme family, and how many of them have ribozymes on both strands |
| `review/october_recall.csv` | ready | Each of the 2,056 October shortlist circles with its new call, ribozymes and shortlist tier. All are rod again, 2,052 keep a ribozyme, 1,097 are on this shortlist |
| `review/positive_controls.csv` | to build | Classifier calls on the known viroid-like records from step 1. These need a separate run because they never entered the screen |

`04_rod_screen/results/chunk_NNN.csv` is reference only (one row per screened circle,
48 columns, 37 GB). Seven column names appear twice in its header, `n_ribozymes` among
them. Step 5 drops all seven for the shortlist, taking 48 columns to 41, although the
comment in `make_results.sh` says four. `04_rod_screen/chunks/` is a third copy of the
in-range sequences.

## Step 5: results

| File | Status | Why it is in the review |
|---|---|---|
| `05_results/SUMMARY_results.txt` | ready | Rod, ribozyme and shortlist counts |
| `05_results/shortlist.csv` | ready | The main output |
| `05_results/rod_with_ribozyme.csv` | ready | Every rod call with at least one ribozyme |
| `05_results/rod_all.csv` | ready | Every rod call. Reference only because of its size |
| `05_results/make_results.sh` | ready | The shortlist rules |
| `review/shortlist_annotated.csv` | to build | Shortlist plus SRA run, overlap class and tier |
| `review/run_comparison.md` | to build | This run beside October, stating why they differ |

Tier 2 of the shortlist is cut at `TOP_N=2000`, so candidates can meet the criteria
and still be left out. `make_results.sh` prints how many under "NOT published":
10,259 in this run. The cut falls inside 2,210 circles tied at confidence 1.000, so
which 2,000 are kept is arbitrary.

## Supporting material

| File | Status | Why it is in the review |
|---|---|---|
| `README.md`, stage `README.md` files | ready | Pipeline description. **Stale:** they give a 37% hairpin share and call the input majority hairpin. In this run the in-range input is 87.0% circular and 13.0% hairpin |
| `NOTES.md` | ready | Decisions and the October record. Needs this run added |
| `model/README.md` | ready | The classifier. Merged in PR #7 |
| `env/README.md`, `env/make_env.sh` | ready | Software environment |
| `run_outputs_2026-10/step3/` | ready | October tables for comparison. Also in `s3://petadex/circs-results/run-2026-10/` |

The October counts are not directly comparable: that run deduplicated, skipped the
trim and had no 200 nt floor.

**Code state:** the run used commit `2626d37` plus scripts that are not committed yet:
`run_all.sh`, `run_finish.sh`, `disk_alert.sh`, `01_kraken_filter/rebuild_classified.sh`,
`01_kraken_filter/rerun_calls.sh`. Commit them before the review so the run can be
reproduced.
