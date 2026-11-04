# Stage 7: dot-bracket structures of every rod

    ./workflow/07_dotbracket/fold_rods.sh

Stage 4 keeps only numbers derived from each fold. This stage refolds the
rods in `rods.csv` with the command stage 4 used, `RNAfold --circ --noPS`,
and keeps the structures:

    rods_dotbracket.tsv.zst     sample_name, length, mfe (kcal/mol), dot_bracket

Rows are in `rods.csv` order. Folding cost rises steeply with length, so the
rods are dealt longest-first into `[compute] dotbracket_parts` files that
each carry the same mix of lengths, and folded `dotbracket_workers` parts at
a time. A part is accepted only when every rod came back with a structure as
long as its sequence. Finished parts are skipped on re-run.
