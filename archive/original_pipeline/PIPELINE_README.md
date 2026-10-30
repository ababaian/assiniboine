# Logan selfloops → rod-like circle screen

Methods for screening every circular contig in the SRA for rod-like,
ribozyme-bearing circles — viroids, ribozyviruses, obelisks, ambiviruses and
anything resembling them.

**This repo holds code and methods only. All data lives in S3** — see
[Data](#data). A whitelist `.gitignore` makes it hard to commit data by accident.

## Result in one line

900,042,456 circles → 595,006,157 unnamed by core_nt → 545,483,299 screened →
**25,222,331 called rod**, of which **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands** (the rolling-circle hallmark). A ranked
shortlist of 2,056 is the practical starting point; its top tier is 56 circles.

## Pipeline

Each stage has a folder here with its runner script and a README covering
counts, method and gotchas.

| stage | folder | in → out | runtime |
|---|---|---|---|
| 0. fetch | [`00_source/`](00_source/) | → 900,042,456 circles (83 GiB zst) | 32 min |
| 1. drop the known | [`01_kraken_filter/`](01_kraken_filter/) | 900,042,456 → 595,006,157 | **16 min** |
| 2. split at 6000 nt | [`02_length_split/`](02_length_split/) | → 594,734,382 + 271,775 | 10 min |
| 3. exact dedup | [`03_dedup/`](03_dedup/) | → 545,483,299 | 32 min |
| 4. rod screen | [`step2/`](step2/) | → 545,483,299 scored rows | **65.7 h** |
| env | [`06_env/`](06_env/) | conda env `circpipe` | 5 min |

Stage 4 is named `step2/` because that is what it is called in the original
plan; renaming it mid-run would have broken the workers.

### What each stage actually runs

**1. Kraken2 filter** — core_nt, `--confidence 0.1`, keep everything
*unclassified*. 10 processes × 32 threads sharing one mmap'd 340 GB index via
the page cache. 16 min, not the 106 min a single process would take; the
benchmark table is in that folder's README.

**2. Length split** — a bug workaround, not a filter: it keeps 99.95%. RNAfold
*stops* rather than skips when handed an oversized circle (see
[Defects](#defects-found-the-hard-way)).

**3. Exact dedup** — GNU sort rather than `dedup_fasta.py`, which is
single-core Python with Booth's algorithm per record and would take days at
595M. Keeps a reversible map of every dropped id → the representative kept.
Verified duplicate-free with `sort -c -u`.

**4. Rod screen** — per circle: `getorf` on the doubled sequence (so ORFs
crossing the junction are found), `RNAfold --noPS --circ`, `cmsearch` against
an in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a 31-feature random
forest. 320 chunks × 16–20 workers × `-j30`.

## Defects found the hard way

**RNAfold stops, it does not skip.** Given a circle past its addressable range
it warns, emits nothing further, and exits 0. A 20,000-record test returned
4,213 rows — exactly the input prefix up to a 44,528-nt circle — and the
pipeline reported success. Mitigations: the ≤6000 nt split, and a gate that
marks a chunk done only when **output rows == input records**. All 320 chunks
passed. Keep that gate in any rerun.

**The Rfam library build is not concurrency-safe.**
`ribozyme_screen.build_combined_rfam_library()` unconditionally rewrites the
combined `.cm` and re-runs `cmpress`, so workers sharing a `--rfam-cache-dir`
collide — 4 of 8 died this way. Every worker gets a private cache dir.

**`below_confidence_floor` is always False.** The model's `confidence_floor` is
0.5 and a binary classifier's winning class is ≥0.5 by construction, so it can
never fire. Threshold on `confidence` yourself.

**RNAfold scales ~n², not n³, in this range.** Measured single-core with
`--circ`: 0.146 s at 250 nt, 0.540 s at 500, 1.956 s at 1000, 8.260 s at 2000.
`t = 0.0167 + 2.06e-6·n²` fits within 6%; an n³ fit is off by 2× at n=500.
ViennaRNA caps interior loops at 30 nt, which suppresses the cubic term. `n` is
the **circle length**, not the ORF length — `getorf` is ~0.4% of the compute.

## Data

Nothing here. Public, no credentials needed:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # stage 4 outputs

    aws s3 ls s3://petadex/circs-results/ --no-sign-request
    curl -O https://petadex.s3.amazonaws.com/circs-results/step2_rod_screen/shortlist.csv

Start with `shortlist.csv`. The 320 per-chunk result files (129 GB, all 545M
rows) are **not** public — they are in `s3://petadex-tmp/circs-results/` and on
watson at `/watson/rnalab/dzhu/k2-circ-runs/`.

## Reproducing

`06_env/make_env.sh` builds the conda env. scikit-learn is pinned to **1.9.1**
because the model pickle carries `_sklearn_version 1.9.1`; a different version
risks silently different predictions.

The pipeline itself (`run_pipeline.py`, `fold.py`, `prop-orf.py`,
`ribozyme_screen.py`, `circrna_classify.py`), the trained `rodnotrod` model and
the CM files come from a collaborator's drive and are **deliberately not in
this repo** — that code and model are theirs to publish. The scripts here wrap
them; they expect to find them under `Lebowski/`.

## Not done

- **271,775 circles >6000 nt** are unscreened (`02_length_split/gt6000/`).
  Up to ~20,000 nt they would fold, slowly; past that RNAfold refuses.
- **Circular dedup** (rotations + reverse complements) was never run. Exact
  dedup removed 8.28%; the same circle assembled from a different start
  position still appears as separate records.
- **Re-scoring with a retrained model.** The `--features-csv` path is validated
  (5,000/5,000 labels reproduced) and takes minutes, so a zeta-virus retrain
  can be applied to the rod table without refolding anything.
