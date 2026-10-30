# original_pipeline -- the October 2026 run

The pipeline that produced everything in `s3://petadex/circs-results/`.
Preserved verbatim at commit `2773b5d`, so it is the method record for that
data and should not be edited. `PIPELINE_README.md` is its own top-level doc as
written at the time.

It screened every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them. Started 2026-10-02, finished 2026-10-05.

## Pipeline

| stage | folder | what it did |
|---|---|---|
| 0 | `00_source/` | fetch the Logan selfloops archive |
| 1 | `01_kraken_filter/` | drop anything core_nt could name |
| 2 | `02_length_split/` | cut at 6000 nt, no lower bound |
| 3 | `03_dedup/` | collapse exact duplicate sequences |
| 4 | `step2/` | fold, search for ribozymes, classify rod |
| 5 | `step3/` | reduce to the rod, ribozyme and shortlist tables |
| | `06_env/` | conda env `circpipe`, scikit-learn pinned to 1.9.1 |

**1. Kraken2 filter.** core_nt at `--confidence 0.1`, keeping everything
unclassified. 10 processes of 32 threads shared one mmap'd 340 GB index through
the page cache, so 16 min rather than the 106 a single process needs.

**2. Length split.** A bug workaround, not a filter: it kept 99.95%. RNAfold
stops rather than skips on an oversized circle, so one long record silently
truncates the rest of its batch.

**3. Exact dedup.** GNU sort rather than `dedup_fasta.py`, which is
single-core Python and would have taken days at this scale. Reversible: every
dropped id was mapped to the representative kept.

**4. Rod screen.** Per circle: `getorf` on the doubled sequence so ORFs
crossing the junction are found, `RNAfold --noPS --circ`, `cmsearch` against an
in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a 31-feature random forest.
320 chunks, 16 to 20 workers.

**5. Results.** Filter to rod, then to rod carrying a ribozyme, then rank into
a two-tier shortlist.

## Verification

| check | result |
|---|---|
| stage 1 processed == independent `grep -c '^>'` of the source | 900,042,456, exact |
| stage 1 recount of output FASTAs | 595,006,157, exact |
| stage 3 kept + dropped == input | 594,734,382, exact |
| stage 3 output provably duplicate-free | `sort -c -u` exit 0 |
| stage 4 chunks completed | 320 / 320 |
| stage 4 rows out == records in, summed | 545,483,299 both sides |
| stage 4 row-count mismatches | 0, so RNAfold never silently truncated |
| distinct headers across the 320 result files | 1 |

## Composition of the discarded third

Host genome, overwhelmingly. Eukaryota 232,188,594; Bacteria 17,018,268;
Viruses 693,256; Archaea 100,769. Top named organisms: *H. sapiens* 79,072,262,
*M. musculus* 49,066,150, *A. thaliana* 4,302,106.

The target classes were almost absent from what core_nt could name, which is
the whole argument for screening the unnamed two-thirds:

    Microviridae    44,307      Circoviridae     2,832
    Inoviridae      13,609      Geminiviridae    1,085
    Pospiviroidae   12,961      Nanoviridae        412
    Genomoviridae    5,104      Avsunviroidae      219
    Anelloviridae    2,931      Ribozyviria         54

## Ribozyme families among the 46,432

    hhrbz_dv4  30,905    Hammerhead_3   630
    twister-P1  8,093    DVR4           609
    hairpin-meta 3,968   VS             137
    Hammerhead_1  805    HDV              1

One HDV-family hit in 545 million circles.

## Commands, as run

```bash
./06_env/make_env.sh
./00_source/selfloops_download.sh
./01_kraken_filter/k2_filter.sh      # split into 21 parts, classify 10 at a time
./02_length_split/lenfilter.sh       # cut at 6000 nt
./03_dedup/dedup_exact.sh            # exact-sequence dedup
./step2_run.sh                       # 16 workers, -j30
./step2_run_extra.sh                 # 4 more alongside, -j22
```

Stage 5 was ad-hoc commands, not a script. It is
`05_results/make_results.sh` in the current pipeline.

Paths are hardcoded to `/watson/rnalab/dzhu/k2-circ-runs`, and
`00_source/selfloops_download.sh` and `06_env/make_env.sh` point at `~/k2`, a
directory that no longer exists. Neither sets `-e`, so the downloader would
carry on past the failed `cd` and write 83 GiB into whatever directory it was
invoked from. Both are fixed in the current pipeline.

## Result

**25,222,331 called rod.** Of those, **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands**, the rolling-circle hallmark. The shortlist
is 2,056 rows.

## Data

Public, no credentials:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # stage 4 and 5 outputs

Local copies of the three output tables, the 320 per-chunk logs and stats,
the taxonomy reports and the run accession lists are in `_run_outputs/`. The
bulk inputs are gone, deleted in the October 2026 cleanup: the 83 GiB source
archive, the 174 G of unclassified FASTAs, the length-split halves,
`dedup_le6000.fa` and its `dedup_map.tsv`, and the 320 chunk files.

Losing `dedup_map.tsv` matters. Stage 3 was built to be reversible so a hit
could be expanded back to every SRA run carrying that circle, and that is no
longer possible for these tables.
