# Reproducing the screen

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
