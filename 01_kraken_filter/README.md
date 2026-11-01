# 01_kraken_filter -- step 1: drop anything already known

Kraken2 against core_nt at `--confidence 0.1`; everything **unclassified** is
kept and goes on to the folding pipeline. 16 minutes wall. Unclassified means
core_nt could not name the record, not that it is novel.

    processed     900,042,456   (equals 00_source/total_records.txt exactly)
    classified    305,036,299   33.89%  -- discarded
    unclassified  595,006,157   66.11%  -- kept, this is the output

Database: `/watson/rnalab/js/resource_files/k2_core_nt` (core_nt, built Oct
2025, owned by `js`, world-readable, 340 GB hash). 2,388,823 taxonomy nodes.
It is NOT ours to delete -- removal needs `js` or an admin.

## Items

| item | what it is |
|---|---|
| `k2_filter.sh` | **the stage**: decompress and split the source into parts, then classify them 10 at a time |
| `k2_classify.sh` | classify-only runner; claims parts by atomic `mkdir` so copies can run together, and holds back the part `split` is still writing |
| `parts/part_NNN` | 45M-record slices of the source, each deleted after its own kraken2 exit 0 |
| `unclassified/unclass_part_NNN.fa` | **the output**, input to stage 2 |
| `logs/part_NNN.log` | per-part kraken2 stdout (counts, percentages) |
| `logs/report_part_NNN.txt` | per-part Kraken2 taxonomy report |
| `logs/part_NNN.done` | completion marker, the resume state |
| `claims/part_NNN` | atomic claim dir, presence means taken |
| `SUMMARY_k2_filter.txt` | the rollup of the counts |
| `K2_FILTER.DONE` | written when every part has completed |

The October run also has a `counts/` directory (an independent recount, and
5,308,320 distinct SRA run accessions) and per-file `.count` files. Those came
from ad hoc verification commands rather than from these scripts, and live in
`run_outputs_2026-10/` on watson.

## How it got to 16 minutes instead of 106

Benchmarked first, on watson (the raw benchmark files are not in the repo):

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
only after its own exit 0, which is why `parts/` ends empty.

## What the classified third was

Host genomes, overwhelmingly: human 79.1M, mouse 49.1M, *Arabidopsis* 4.3M,
guppy 3.0M, zebrafish 2.6M, *Drosophila* 2.2M. Bacteria 1.89%, Archaea 0.01%.

Viruses are only 693,256 records (0.08%), mostly phage (Caudoviricetes 380,359;
Microviridae 44,307). The hunted classes are vanishingly rare in what core_nt
can name -- Pospiviroidae 12,961, Genomoviridae 5,104, Anelloviridae 2,931,
Circoviridae 2,832, Avsunviroidae 219, **Ribozyviria 54** -- which is the whole
argument for screening the unclassified 66%.

## Rerunning

    ./01_kraken_filter/k2_filter.sh      # splits, classifies, resumes
    ./01_kraken_filter/k2_classify.sh    # classify only, if parts/ already holds slices

Both skip parts with a `logs/*.done` marker, so either can be re-run after an
interruption.
