# 00_source -- the Logan v1.1 selfloops archive

Every circular contig Logan assembled from SRA (the Feb 2025 run). One record
per circle per sequencing run.

| item | what it is |
|---|---|
| `selfloops.v1.1.fa.zst` | the archive, 89,258,393,740 bytes (83.1 GiB) |
| `selfloops_download.sh` | the fetch, detached with retries + a size check |
| `selfloops_download.log` | `complete, 89258393740 bytes` |
| `selfloops.DONE` | written only after the size matched S3 |
| `total_records.txt` | 900042456 -- counted, not estimated |
| `total_bytes.txt` | 330990107900 -- 331 GB decompressed |
| `count.log`, `count.DONE` | the counting job |

Source: `s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst`
(no credentials needed; `--no-sign-request`). Fetched at ~50 MB/s in 32 min.
It is NOT in `s3://logan-pub/`; that bucket has no selfloops object.

## Record anatomy

    >SRR12604050_704504_circle_704504 ka:f:4.900 L:-:704504:- L:+:704504:+

- `SRR12604050` -- the SRA run it came from
- `704504_circle_704504` -- unitig id, flagged as a circle
- `ka:f:4.900` -- mean k-mer abundance (coverage)
- `L:-:...:- L:+:...:+` -- GFA links showing the unitig joins **to itself** on
  both strands. That self-link is what "selfloop" means.

Exactly 2 lines per record (header + unwrapped sequence), verified over 9 GB.
Single zstd frame, so decompression cannot be parallelised: ~590 MB/s, ~9.5 min
for the whole thing.

## Shape

- mean length 243 nt, 96.9% are <=500 nt, longest 437,661 nt
- 5,308,320 distinct SRA runs in the unclassified subset alone
  (4,325,803 SRR / 917,885 ERR / 64,632 DRR), ~112 unclassified circles per run

## Deduplication state as it arrives

Deduplicated **within** each run, not across runs. Of 194,324 duplicate groups
in a 5M-record slice, 100% spanned more than one run and 0% sat inside a single
run -- Logan collapses duplicates per assembly, so a circle recovered from 50
runs is 50 records. No identity clustering, and rotations/reverse complements
are not collapsed.

To regenerate the plain FASTA (nothing currently needs it):

    zstd -dc selfloops.v1.1.fa.zst > selfloops.v1.1.fa    # 331 GB, ~10 min
