# Stage 0: fetch the source archive

Fetches `[source] url` to `work/00_source/`. The published runs used Logan's
v1.1 selfloops archive: every circular contig Logan assembled from the SRA,
one record per circle per sequencing run, 900,042,456 records, 83 GiB
compressed. No credentials are needed.

    ./workflow/00_source/fetch_source.sh

The download is retried up to five times and accepted only at the size given
by `[source] expected_bytes`. A local path in `[source] url` is linked instead
of downloaded, which is how `scripts/ops/run_example.sh` feeds in a small
synthetic archive.

The record format is described in `docs/data_dictionary.md`.
