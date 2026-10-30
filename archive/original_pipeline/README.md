# original_pipeline -- the October 2026 run

The pipeline that produced everything in `s3://petadex/circs-results/`.
Preserved verbatim at commit `2773b5d`, so it is the method record for that
data and should not be edited. `PIPELINE_README.md` is its own top-level doc as
written at the time.

It screened every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them. Started 2026-10-02, finished 2026-10-05.

The current pipeline differs in three ways. See
[How this differs](#how-this-differs-from-the-current-pipeline).

## Pipeline

| stage | folder | what it did | runtime |
|---|---|---|---|
| 0 | `00_source/` | fetch the Logan selfloops archive | 32 min |
| 1 | `01_kraken_filter/` | drop anything core_nt could name | 16 min |
| 2 | `02_length_split/` | cut at 6000 nt, no lower bound | 10 min |
| 3 | `03_dedup/` | collapse exact duplicate sequences | 32 min |
| 4 | `step2/` | fold, search for ribozymes, classify rod | 65.7 h |
| 5 | `step3/` | reduce to the rod, ribozyme and shortlist tables | minutes |
| | `06_env/` | conda env `circpipe`, scikit-learn pinned to 1.9.1 | 5 min |

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

## Counts through the pipeline

Every step reconciles exactly against the one before it.

| step | records | % of input | kept from previous |
|---|---|---|---|
| fetched | 900,042,456 | 100% | |
| unclassified by core_nt | 595,006,157 | 66.11% | 66.11% |
| at most 6000 nt | 594,734,382 | 66.08% | 99.95% |
| exact-deduped | 545,483,299 | 60.61% | 91.72% |
| scored | 545,483,299 | 60.61% | 100% |
| called rod | 25,222,331 | 2.80% | 4.62% |
| rod with a ribozyme | 46,432 | 0.0052% | 0.18% |
| ribozymes on both strands | 16,757 | 0.0019% | 36.09% |
| shortlist | 2,056 | 0.00023% | 12.27% |

What was removed, and where it went:

| step | removed | why |
|---|---|---|
| 1 | 305,036,299 | classified, so already named by core_nt |
| 2 | 271,775 | over 6000 nt, parked in `02_length_split/gt6000/` |
| 3 | 49,251,083 | exact duplicate sequences, mapped in `dedup_map.tsv` |
| 4 | 520,260,968 | classified not_rod |
| 5 | 25,175,899 | rod but no ribozyme detected |
| 5 | 29,675 | ribozyme on one strand only |
| 5 | 14,701 | both strands but below the shortlist cut |

**The screen narrows hardest at two places.** The classifier rejects 95.38% of
what it scores, and of the rod calls that survive, 99.82% carry no detectable
ribozyme. Everything before stage 4 removes only a third of the input.

### Verification

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

### Composition of the discarded third

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

### Ribozyme families among the 46,432

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
is 2,056 rows in two tiers:

- **Tier 1**, 56 rows: both strands AND a corroborated locus, meaning
  independent CMs agree on the same site. Complete.
- **Tier 2**, 2,000 rows: both strands, confidence >= 0.8, ranked by
  confidence. **Truncated.** The qualifying pool was 13,399, so the real cut
  landed at confidence 0.998 and 11,399 candidates meeting the stated criteria
  are absent from the file. `step2/share/DATA_README.md` does not say this.

Strongest hit `SRR6337267_1290199_circle_1290199`, 726 nt, confidence 0.996,
twister-P1 on both strands.

Rod confidence averaged 0.6604; 998,131 at 0.9 or above. Rod by length: 500 nt
or less 24,040,832; 501 to 1200 966,855; 1201 to 2000 157,255; over 2000
57,389.

`below_confidence_floor` is always False and carries no information: the
model's floor is 0.5 and a binary classifier's winning class is at least 0.5
by construction.

## Data

Public, no credentials:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # stage 4 and 5 outputs

Local copies of the three published tables, the 320 per-chunk logs and stats,
the taxonomy reports and the run accession lists are in `_run_outputs/`. The
bulk inputs are gone, deleted in the October 2026 cleanup: the 83 GiB source
archive, the 174 G of unclassified FASTAs, the length-split halves,
`dedup_le6000.fa` and its `dedup_map.tsv`, and the 320 chunk files.

Losing `dedup_map.tsv` matters. Stage 3 was built to be reversible so a hit
could be expanded back to every SRA run carrying that circle, and that is no
longer possible for these tables.

## How this differs from the current pipeline

- **No terminal-overlap trim.** Logan writes a circle's first 30 nt again as
  its last 30, so every length in these tables is 30 nt too long and every
  fold included a spurious tandem repeat. Any length-based cut applied to this
  data is shifted by 30.
- **Non-circles were folded as circles.** About 37% of selfloops records
  self-link to their own reverse complement and are linear contigs capped by an
  inverted repeat. This run folded all of them with `--circ`.
- **Deduplication, since dropped.** It removed 8.28%, but duplication is
  signal, one record per circle per run being the input's own unit, and exact
  matching missed most duplicates anyway because assembly does not fix where a
  circle starts.
- **No lower length bound.** The current pipeline floors at 200 nt. Against
  this run's output that would have removed 12,487,733 of the 25,222,331 rod
  calls, 49.51%, but only 677 of the 46,432 ribozyme-bearing ones and nothing
  from the shortlist.
