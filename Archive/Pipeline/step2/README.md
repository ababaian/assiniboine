# step2 -- features + rod classification  (RUNNING)

The folding pipeline over every deduped unclassified circle: getorf, RNAfold
`--circ`, cmsearch against dvr5 + the combined Rfam ribozyme library, then the
`rodnotrod` model. Driven by `../step2_run.sh`.

    input   545,483,299 circles (03_dedup/dedup_le6000.fa)
    layout  320 chunks of ~1,704,636 records
    config  16 concurrent workers x -j30 and --cmsearch-cpu 30 (= all 480 cores)
    started 2026-10-02 23:52 UTC
    rate    ~3,654 rows/s measured
    ETA     ~2026-10-04 17:00 UTC

## Items

| item | what it is |
|---|---|
| `chunks/chunk_000` … `chunk_319` | the sharded input, ~0.5 G each, 157 G total |
| `results/chunk_NNN.csv` | **the output** -- 48 columns, one row per circle |
| `logs/chunk_NNN.log` | per-chunk stdout (fold progress, cmsearch commands) |
| `logs/chunk_NNN.done` | completion marker, contains the input record count |
| `claims/chunk_NNN/` | atomic claim dir -- presence means taken |
| `rfam/chunk_NNN/` | per-worker Rfam cache, created and deleted per chunk |
| `MISMATCH.txt` | **should not exist.** Any line is a chunk whose row count disagreed |

Output columns: `sample_name, length, predicted_class, confidence,
below_confidence_floor`, then 43 feature columns (GC, keto bias, ORF densities,
MFE/nt, structural features from the dot-bracket, and the ribozyme counts per
family).

## Monitoring

    ls step2/logs/*.done | wc -l                  # of 320
    cat step2/results/*.csv | grep -vc '^sample'  # rows so far
    cat step2/MISMATCH.txt                        # must stay absent
    tail ../step2_run.log

Rod rate is running ~0.98%, so expect roughly 5.3M rod candidates.

## Two guards worth knowing about

**Row-count equality.** A chunk is marked done only when output rows EQUAL
input records. This is the only thing that catches RNAfold's silent truncation
on an oversized circle -- it exits 0 having emitted nothing further, and
`run_pipeline.py` reports success. On mismatch the claim is released and the
chunk is retried on the next run.

**Private Rfam caches.** `build_combined_rfam_library()` unconditionally
rewrites the combined `.cm` and re-runs `cmpress`, so two workers sharing a
`--rfam-cache-dir` collide and one dies -- that killed 4 of 8 shards on the
first attempt. Each chunk gets its own cache, seeded from `Lebowski/CM/RF*.cm`
so Rfam is never re-downloaded.

## Resuming

    cd /watson/rnalab/dzhu/k2-circ-runs && ./step2_run.sh

Finished chunks are skipped, in-flight ones redone. Chunking at 320 means a
crash costs ~3.6 h of work, not days. Safe to kill and restart at any time.

## Config rationale

16-way was measured against 8-way and 48-way on identical data; see
`../05_benchmarks/README.md`. More processes did not help because the
single-threaded parts (getorf, the Python merge loop) already parallelise
across processes, while `-j8` starves folding on the long sequences.
