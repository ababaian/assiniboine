# Logan selfloops rod-like circle screen

This pipeline screens every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them.

The input is Logan's selfloops archive, every circular contig assembled from
the SRA, one record per circle per sequencing run. The output is a ranked
shortlist of candidates, with the full scored table behind it.

This repo holds code and methods only. All data lives in S3, see
[Data](#data). A whitelist `.gitignore` makes it hard to commit data by
accident.

## Pipeline

| stage | folder | what it does |
|---|---|---|
| 0 | [`00_source/`](00_source/) | fetch the Logan selfloops archive |
| 1 | [`01_kraken_filter/`](01_kraken_filter/) | drop anything core_nt can already name |
| 2 | [`02_circular_overlap/`](02_circular_overlap/) | trim the terminal 30-nt overlap, split off non-circles |
| 3 | [`03_length_filter/`](03_length_filter/) | keep 200 to 6000 nt |
| 4 | [`04_rod_screen/`](04_rod_screen/) | fold, search for ribozymes, classify rod |
| 5 | [`05_results/`](05_results/) | reduce to the rod, ribozyme and shortlist tables |
| | [`env/`](env/) | the conda environment |
| | [`analysis/`](analysis/) | side analyses, not part of the screen |

Each stage folder has a README with its counts, method and gotchas.

**1. Kraken2 filter.** core_nt at `--confidence 0.1`, keeping everything
unclassified, which means core_nt could not name it and not that it is novel.

**2. Circular overlap.** Logan assembles at k=31, so a closed circle is
written with its first 30 nt repeated as its last 30; trimming that corrects
both the inflated length and the spurious tandem repeat `--circ` would fold
into the junction. It also labels how each record closes: the roughly 37%
whose self-link is to their own reverse complement are linear contigs capped by
an inverted repeat rather than circles, and they are labelled rather than
withheld, so everything reaches the screen.

**3. Length filter.** Keep 200 to 6000 nt: the ceiling because RNAfold stops
rather than skips on an oversized circle and silently truncates the rest of its
batch, the floor because anything shorter is below every known viroid-like
agent. Out-of-range records are parked, not deleted.

**4. Rod screen.** Per circle: `getorf` on the doubled sequence so
junction-crossing ORFs are found, `RNAfold --noPS --circ`, `cmsearch` against
an in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a 31-feature random forest
labels rod or not_rod.

**5. Results.** Filter to rod, then to rod carrying a ribozyme, then rank into
a two-tier shortlist keyed on ribozymes on both strands, the rolling-circle
hallmark.

## Commands

Everything runs from the repo root. Each stage has a wrapper that does the work
resume-safely and in parallel; the explicit commands behind each one are in
that stage's README. The wrappers hardcode
`ROOT=/watson/rnalab/dzhu/k2-circ-runs`, so edit that line before running
elsewhere.

```bash
# environment: scikit-learn is pinned to 1.9.1 to match model.pkl
./env/make_env.sh
source /opt/miniconda3/etc/profile.d/conda.sh && conda activate circpipe

# 0. fetch the source, 83 GiB, with retries and a size check
./00_source/selfloops_download.sh

# 1. Kraken2 filter: splits into 21 parts, classifies 10 at a time, resume-safe
./01_kraken_filter/k2_filter.sh

# 2. trim the 30-nt overlap and separate the hairpins
./02_circular_overlap/trim_circular_overlap.sh \
    -o 02_circular_overlap 01_kraken_filter/unclassified

# 3. keep 200 to 6000 nt
./03_length_filter/lenfilter.sh

# 4. shard, then screen
./04_rod_screen/make_chunks.sh
./04_rod_screen/run.sh                 # 16 workers, -j30
./04_rod_screen/run_extra.sh           # optional, 4 more workers alongside

# 5. reduce to the output tables
./05_results/make_results.sh
```

Thread counts, `-P` values and `-j30` are sized for the 480-core machine the
run used; they are not method parameters. Scale them down before running on
anything smaller, especially the 10 concurrent Kraken2 processes, which assume
the 340 GB index stays resident in page cache.

Two prerequisites are not in this repo:

- **`Lebowski/`**, the upstream pipeline, the trained `rodnotrod` model and
  the CM files, which only stage 4 needs. Fetch it to the repo root:

      aws s3 cp s3://petadex/circs-results/model/lebowski_20261002.tar.gz . --no-sign-request
      aws s3 cp s3://petadex/circs-results/model/MANIFEST.md5 . --no-sign-request
      tar xzf lebowski_20261002.tar.gz
      (cd Lebowski && md5sum -c ../MANIFEST.md5)

  Stage 4 reads exactly four things from it: `Scripts/run_pipeline.py` and its
  sibling modules via `--lib-dir`, `rodnotrod_model/model.pkl` (md5
  `b2e052da3e88d1802a5ed71ae34a8b9c`), `CM/dvr5.cm`, and the 18 `CM/RF*.cm`
  Rfam models. `run.sh` checks for them before starting and refuses with a
  pointer if any is missing. The code and model originate from a
  collaborator's drive.
- **a Kraken2 core_nt database.** Build one with `kraken2-build` or obtain a
  prebuilt index. The run used `/watson/rnalab/js/resource_files/k2_core_nt`,
  340 GB, built October 2025, which belongs to another user and is not ours to
  rely on.

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

Nothing in this repo. Public, no credentials needed:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # screen and results outputs

    aws s3 ls s3://petadex/circs-results/ --no-sign-request
    curl -O https://petadex.s3.amazonaws.com/circs-results/step2_rod_screen/shortlist.csv

Start with `shortlist.csv`. The per-chunk result files, 129 GB and all 545M
rows, are not public: they are in `s3://petadex-tmp/circs-results/`. Local
copies of the run's output tables are in `run_outputs_2026-10/` on watson,
which is gitignored.
