# 01_kraken_filter -- step 1: drop anything already known

Kraken2 against core_nt at `--confidence 0.1`; everything **unclassified** is
kept and goes on to the folding pipeline. 16 minutes wall.

    processed     900,042,456   (equals 00_source/total_records.txt exactly)
    classified    305,036,299   33.89%  -- discarded
    unclassified  595,006,157   66.11%  -- kept, this is the output

Database: `/watson/rnalab/js/resource_files/k2_core_nt` (core_nt, built Oct
2025, owned by `js`, world-readable, 340 GB hash). 2,388,823 taxonomy nodes.
It is NOT ours to delete -- removal needs `js` or an admin.

## Items

| item | what it is |
|---|---|
| `unclassified/unclass_part_000.fa` … `_020.fa` | **the output**: 21 FASTA, 174 G, 595,006,157 records |
| `unclassified/*.fa.count` | per-file header counts |
| `SUMMARY_k2_filter.txt` | the rollup above |
| `reports/report_part_*.txt` | 21 Kraken2 taxonomy reports |
| `logs/part_*.log` | per-chunk stdout (counts, percentages) |
| `logs/part_*.done` | completion markers (resume state) |
| `claims/part_*` | atomic claim dirs, one per chunk |
| `k2_classify.sh` | **the runner that did the work** |
| `k2_filter.sh` | the original 2-stage driver, superseded |
| `counts/unclassified_total.txt` | 595006157 -- independent recount, matches |
| `counts/all_runs.txt` | 5,308,320 distinct SRA run accessions |
| `counts/verify.log`, `VERIFY.DONE` | the verification pass |

## How it got to 16 minutes instead of 106

Benchmarked first (see `../05_benchmarks/README.md`):

- one process, 32-64 threads, warm db cache: 8.5M seq/min -> ~106 min
- 128 threads: *slower* (4.3M seq/min) -- contention
- 10 processes fed by a streaming `paste|split|tr` splitter: 94 MB/s, ~62 min,
  bound by the single-threaded plumbing, not by Kraken2
- **what ran**: decompress+split to 21 plain-FASTA parts (588 MB/s), then 10
  concurrent processes x 32 threads over those parts -> 16 min

The workers share one mmap'd copy of the 340 GB database through the page
cache (`--memory-mapping`), so ten of them cost one copy of RAM, not ten.
`k2_classify.sh` holds back the part `split` is still appending to, so
classification overlaps the decompression.

Resume-safe: chunks are claimed with an atomic `mkdir` and each part is deleted
only after its own exit 0, which is why `parts/` is now empty.

## What the classified third was

Host genomes, overwhelmingly: human 79.1M, mouse 49.1M, *Arabidopsis* 4.3M,
guppy 3.0M, zebrafish 2.6M, *Drosophila* 2.2M. Bacteria 1.89%, Archaea 0.01%.

Viruses are only 693,256 records (0.08%), mostly phage (Caudoviricetes 380,359;
Microviridae 44,307). The hunted classes are vanishingly rare in what core_nt
can name -- Pospiviroidae 12,961, Genomoviridae 5,104, Anelloviridae 2,931,
Circoviridae 2,832, Avsunviroidae 219, **Ribozyviria 54** -- which is the whole
argument for screening the unclassified 66%.

## Rerunning

    ./k2_classify.sh          # resumes; skips parts with a logs/*.done marker

Note it reads `parts/part_*`, which no longer exist; regenerate them from
`../00_source/` first (see `k2_filter.sh` stage 1).
