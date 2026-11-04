# Stage 4: fold, search for ribozymes, call rod or not

    ./workflow/04_rod_screen/rod_screen.sh      # runs make_chunks.sh first if needed

The screen is the external classifier in the Lebowski bundle
(`docs/dependencies.md`): per record, `getorf` on the doubled sequence so
junction-crossing ORFs are found, `RNAfold --circ`, `cmsearch` against
`dvr5.cm` and 18 Rfam ribozyme models, then the `rodnotrod` random forest.
`rod_screen.sh` feeds it chunks and checks what comes back.

| file | what it is |
|---|---|
| `chunks/chunk_NNN.fa` | the in-range records re-cut into `[compute] records_per_chunk` records |
| `results/chunk_NNN.csv` | one row per record: call, confidence and 43 feature columns (`docs/data_dictionary.md`) |
| `logs/chunk_NNN.log`, `.done` | the classifier's output and the resume marker |
| `FAILED.txt` | chunks whose output did not pass the check, if any |
| `summary.txt` | chunks completed and rows written |

A chunk is done only when its CSV has one row per input record. That is the
only thing that catches `RNAfold` stopping early on an oversized sequence,
since the classifier reports success regardless. Failed chunks are retried
when the script is re-run.

`[compute] screen_workers` chunks run at once, each with
`[compute] screen_threads` threads for `RNAfold` and `cmsearch`.
