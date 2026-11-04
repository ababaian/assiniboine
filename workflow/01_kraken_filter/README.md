# Stage 1: drop what Kraken2 can already name

    ./workflow/01_kraken_filter/kraken_filter.sh

Runs Kraken2 at `[kraken] confidence` against `[kraken] database` and keeps
the records it cannot classify. Known organisms, host genomes, and anything
else the database names are dropped here, so they never reach the rod screen.
"Unclassified" only means the database could not name a record.

| output | what it is |
|---|---|
| `unclassified/part_NNN.fa` | the records kept; stage 2's input |
| `calls/part_NNN.tsv.zst` | every record's call: `C`/`U`, id, taxid, length |
| `reports/part_NNN.txt` | Kraken2's taxonomy report per part |
| `logs/part_NNN.log`, `.done` | Kraken2's output and the resume marker |
| `summary.txt` | classified and unclassified totals |

The source is cut into parts of `[compute] records_per_part` records and the
parts are classified `[compute] kraken_workers` at a time. Each part is
deleted once its classification succeeds. Re-running skips finished parts.

Needs `kraken2`, `zstd` and a Kraken2 database; see `docs/dependencies.md`.
