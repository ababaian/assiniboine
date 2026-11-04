# Reproducibility

What it takes to get the same answer again, and what the pipeline does to
make that checkable.

## Reproducing a published run

1. Install as in `docs/installation.md`, with the same classifier bundle
   (`lebowski_20261002.tar.gz`, checked against its `MANIFEST.md5`) and a
   Kraken2 database equivalent to the one the run used.
2. Use the run's settings file, `config/runs/2026-11.toml`, scaling only
   the `[compute]` section to your machine.
3. Run `./workflow/run_screen.sh`.

Stages 2, 3, 5 and 6 are deterministic given their input. Stage 1 depends
on the database build: a different core_nt gives a different unclassified
set, and that difference carries through every later stage. Stage 4
depends on the tool versions in `environment.yml`; `RNAfold` and
`cmsearch` are deterministic for a given version, and the random forest
is a fixed pickled model. Stage 7 is deterministic.

Thread and worker counts never change the result. Chunk and part sizes
change only how the work is divided.

## What a run keeps

Stages 1 to 3 write a few hundred gigabytes of FASTA, but every record in
them is a source record that was dropped, trimmed or filed by a fixed rule.
Stage 6 replaces them with the record manifest, one row per source record,
and proves the replacement is lossless: it streams the source archive and
the manifest together and checks that what it would rewrite for stages 1
to 3 has the same MD5 as what the run wrote, file by file. After that the
run can keep:

| what | size for the 2026-11 run |
|---|---|
| the Kraken2 calls and reports | 5 GB |
| the record manifest | 7 GB |
| the screen results (every screened record, no sequences) | 37 GB as CSV |
| the stage 5 tables (every rod, with sequence) | 1 GB compressed |
| the dot-bracket structures | 0.5 GB compressed |

and discard the FASTA. To get any stage 1 to 3 file back:

```bash
assiniboine manifest rebuild --source selfloops.fa.zst --manifest record_manifest.tsv.zst \
    --out-dir rebuilt --records-per-part 45000000
```

`MD5SUMS` covers the kept files; `cd work && md5sum -c 06_package/MD5SUMS`
checks them after a move or a download.

## Checks built into the stages

| stage | check | what it catches |
|---|---|---|
| 0 | download size equals `expected_bytes` | a truncated archive |
| 4 | chunking only starts from two-line FASTA, and every chunk starts with a header | a record split across chunks |
| 4 | one result row per record of each chunk | `RNAfold` stopping early with exit status 0 |
| 5 | the id of each result row equals the id of the record beside it | a result file paired with the wrong chunk |
| 5 | the seven repeated columns agree in every row | a classifier version writing something other than copies |
| 6 | source, Kraken2 calls and stage 2 output agree at every record, and all three streams end together | a part lost, duplicated or reordered between stages |
| 6 | the rebuild has the same MD5 as the run's files | the manifest not being lossless |
| 7 | every structure is as long as its sequence, every rod appears exactly once | `RNAfold` skipping or truncating |

## Recording a run

A run that is worth keeping gets a settings file in `config/runs/` and a
page in `docs/runs/` with the counts from each stage's `summary.txt`,
where the data was put, and anything that differed from the method as
documented. `docs/runs/2026-11.md` is the model.
