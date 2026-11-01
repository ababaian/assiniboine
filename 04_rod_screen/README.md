# 04_rod_screen -- features and rod classification

The folding pipeline over every in-range circle: `getorf`, `RNAfold --circ`,
`cmsearch` against dvr5 plus the combined Rfam ribozyme library, then the
`rodnotrod` random forest. Chunked by `make_chunks.sh`, driven by `run.sh`.

Per circle: `getorf` on the doubled sequence so junction-crossing ORFs are
found, `RNAfold --noPS --circ`, `cmsearch` against an in-house `dvr5.cm` and 18
Rfam ribozyme CMs, then a 31-feature random forest labels rod or not_rod.

    input   03_length_filter/in_range/*.fa   (200 to 6000 nt, overlap trimmed)
    layout  chunks of 1,704,636 records, count follows the input size
    config  16 concurrent workers x -j30 and --cmsearch-cpu 30 (= all 480 cores)

The October 2026 run read a deduplicated, untrimmed set of 545,483,299 circles
as 320 chunks and took ~65.7 h. Deduplication has since been dropped and the
overlap trim added, so a rerun reads a different number of records and
produces a different number of chunks. The chunk count is not load-bearing:
the runners screen whatever is in `chunks/`.

## Items

| item | what it is |
|---|---|
| `chunks/chunk_NNN` | the sharded input, ~0.5 G each |
| `results/chunk_NNN.csv` | **the output**, 48 columns, one row per circle |
| `logs/chunk_NNN.log` | per-chunk stdout (fold progress, cmsearch commands) |
| `logs/chunk_NNN.done` | completion marker, contains the input record count |
| `claims/chunk_NNN/` | atomic claim dir, presence means taken |
| `rfam/chunk_NNN/` | per-worker Rfam cache, created and deleted per chunk |
| `MISMATCH.txt` | one line per chunk whose row count disagreed, with a UTC timestamp |
| `SCREEN.DONE` | written only when every chunk in the current set passed the gate |

Output columns: `sample_name, length, predicted_class, confidence,
below_confidence_floor`, then 43 feature columns (GC, keto bias, ORF densities,
MFE/nt, structural features from the dot-bracket, and the ribozyme counts per
family).

`below_confidence_floor` is always False. The model's floor is 0.5 and a
binary classifier's winning class is at least 0.5 by construction, so the flag
can never fire. Threshold on `confidence` instead.

## Running

    ./04_rod_screen/make_chunks.sh     # shard the in-range FASTAs
    ./04_rod_screen/run.sh             # 16 workers, -j30
    ./04_rod_screen/run_extra.sh       # 4 workers, -j22, alongside the above

Both runners are resume-safe: finished chunks are skipped, in-flight ones
redone. Safe to kill and restart at any time.

## Monitoring

    ls 04_rod_screen/logs/*.done | wc -l                  # of the chunk count
    cat 04_rod_screen/results/*.csv | grep -vc '^sample'  # rows so far
    cat 04_rod_screen/MISMATCH.txt                        # unresolved truncations
    tail 04_rod_screen/SUMMARY_screen.txt

## Three guards worth knowing about

**Row-count equality.** A chunk is marked done only when output rows EQUAL
input records. This is the only thing that catches RNAfold's silent truncation
on an oversized circle: it exits 0 having emitted nothing further, and
`run_pipeline.py` reports success. On mismatch the claim is released and the
chunk is retried on the next run.

**Private Rfam caches.** `build_combined_rfam_library()` unconditionally
rewrites the combined `.cm` and re-runs `cmpress`, so two workers sharing a
`--rfam-cache-dir` collide and one dies. That killed 4 of 8 shards on the
first attempt. Each chunk gets its own cache, seeded from `Lebowski/CM/RF*.cm`
so Rfam is never re-downloaded.

**Completion counted per chunk set.** `done_n` counts only markers belonging
to the chunks currently present. Counting every `*.done` in `logs/` let
markers from an earlier, differently sized chunk set satisfy the gate, which
produced a `SCREEN.DONE` over a run that screened nothing. `make_chunks.sh`
also clears the previous set's markers and claims when it defines a new one.

## Config rationale

16-way was measured against 8-way and 48-way on identical data. More processes
did not help, because the single-threaded parts (getorf, the Python merge
loop) already parallelise across processes, while `-j8` starves folding on the
long sequences.
