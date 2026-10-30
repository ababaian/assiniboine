# Logan selfloops rod-like circle screen

Screens every circular contig in the SRA for rod-like, ribozyme-bearing
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
| | [`Archive/`](Archive/) | the pipeline that produced the published data |

Each stage folder has a README with its counts, method and gotchas.

**1. Kraken2 filter.** core_nt at `--confidence 0.1`, keeping everything
unclassified. 10 processes of 32 threads share one mmap'd 340 GB index through
the page cache, so RAM cost is one copy, not ten. Unclassified means core_nt
could not name it, not that it is novel.

**2. Circular overlap.** Logan assembles at k=31, so a unitig that closes into
a circle is written with its first 30 nt repeated as its last 30. That
duplication inflates every length by 30 and, once `RNAfold --circ` joins the
ends, inserts a spurious tandem repeat into the folded structure. This stage
trims it. It also splits off the roughly 37% of records whose self-link is to
their own reverse complement: those are linear contigs capped by an inverted
repeat, not circles, and they are parked rather than screened.

**3. Length filter.** Two bounds for two reasons. The 6000 nt ceiling is a bug
workaround, since RNAfold stops rather than skips on an oversized circle and
one long record silently truncates the rest of its batch. The 200 nt floor is a
biological filter, since circles that short are below any known viroid-like
agent. Out-of-range records are parked, not deleted.

**4. Rod screen.** Per circle: `getorf` on the doubled sequence so ORFs
crossing the junction are found, `RNAfold --noPS --circ` for structure,
`cmsearch` against an in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a
31-feature random forest labels rod or not_rod.

**5. Results.** Filter to rod calls, then to rod calls carrying a ribozyme,
then rank into a two-tier shortlist. Ribozymes on both strands is the
rolling-circle hallmark and is what the shortlist selects on.

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

# 5. reduce to the published tables
./05_results/make_results.sh
```

Thread counts, `-P` values and `-j30` are sized for the 480-core machine the
run used; they are not method parameters. Scale them down before running on
anything smaller, especially the 10 concurrent Kraken2 processes, which assume
the 340 GB index stays resident in page cache.

Two prerequisites are not in this repo:

- **`Lebowski/`**, the upstream pipeline (`run_pipeline.py`, `fold.py`,
  `prop-orf.py`, `ribozyme_screen.py`, `circrna_classify.py`), the trained
  `rodnotrod` model and the CM files. These come from a collaborator's drive
  and are theirs to publish.
- **a Kraken2 core_nt database.** Build one with `kraken2-build` or obtain a
  prebuilt index. The run used `/watson/rnalab/js/resource_files/k2_core_nt`,
  340 GB, built October 2025, which belongs to another user and is not ours to
  rely on.

## Result

From the October 2026 run, which used the archived pipeline rather than the one
above:

900,042,456 circles, 595,006,157 unnamed by core_nt, 545,483,299 screened,
**25,222,331 called rod**. Of those, **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands**. The published shortlist is 2,056 rows, whose
top tier is 56 circles.

Caveats that qualify those numbers are in
[`Archive/Pipeline/step2/share/METHOD.md`](Archive/Pipeline/step2/share/METHOD.md)
and
[`Archive/Pipeline/01_kraken_filter/share/METHOD.md`](Archive/Pipeline/01_kraken_filter/share/METHOD.md).
Read them before quoting any result.

## Data

Nothing in this repo. Public, no credentials needed:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # screen and results outputs

    aws s3 ls s3://petadex/circs-results/ --no-sign-request
    curl -O https://petadex.s3.amazonaws.com/circs-results/step2_rod_screen/shortlist.csv

Start with `shortlist.csv`. The per-chunk result files, 129 GB and all 545M
rows, are not public: they are in `s3://petadex-tmp/circs-results/`. Local
copies of the published tables are in
[`Archive/Pipeline/_run_outputs/step3/`](Archive/).

## What changed since the published run

The pipeline above is not the one that produced the numbers in
[Result](#result). Four changes, each with its reasoning in the relevant stage
README.

**Terminal overlap trimmed, and non-circles separated.** New stage 2. The
30-nt duplication was previously left in place, so every published length is
30 nt too long and every fold included a spurious tandem repeat. Separately,
about 37% of selfloops records turn out not to be circles at all: their
self-link is to their own reverse complement, and the terminal 30-mer is a
perfect inverted repeat in 100% of them. The October run folded all of those
as circles. Measurements in
[`analysis/circular_overlap/`](analysis/circular_overlap/).

**Deduplication dropped.** The old stage 3 collapsed exact duplicate
sequences, removing 8.28%. It is gone for two reasons. Duplication is signal:
one record per circle per sequencing run is the input's own unit, and a circle
recovered from 50 runs is 50 observations. And exact matching did not work
anyway, because assembly does not fix where a circle starts, so the same
circle usually differs by a rotation. Keeping the duplicates costs 3.4% more
folding time, not 8.28%, because the duplicates were mostly short.

**A 200 nt floor added.** Measured against the October output, it would have
removed 12,487,733 of 25,222,331 rod calls (49.51%) but only 677 of the 46,432
ribozyme-bearing ones (1.46%), and nothing from the shortlist, whose shortest
row is 309 nt. Nothing was called rod below 150 nt at all. Those figures are on
untrimmed lengths, so they shift once stage 2 is applied.

**Three reporting and safety fixes.** The screen's completion gate counted
every `.done` marker rather than those for the current chunk set, which let an
earlier run's markers declare a new run complete; chunk creation was never
scripted; and the shortlist's tier 2 is truncated to 2,000 rows out of a
qualifying pool of 13,399, which the published `DATA_README.md` does not say.
