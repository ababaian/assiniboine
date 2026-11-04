# Stage 5: the rod tables and the shortlist

    ./workflow/05_results/make_results.sh

Reads each chunk's FASTA and CSV side by side, keeps the records called
`rod`, and attaches their sequence, SRA run and closure class.

| output | rows |
|---|---|
| `rods.csv` | every rod |
| `rods_with_ribozyme.csv` | rods with at least one ribozyme hit |
| `shortlist.csv` | tier 1: ribozymes on both strands and a corroborated locus, in full; tier 2: both strands, confidence at or above `[shortlist] tier2_min_confidence`, ranked and cut to `tier2_max_rows` |
| `summary.txt` | the counts, including how many tier 2 candidates the row cap excluded |

Refuses to run until stage 4 has finished, since that is what proves no
chunk was truncated. Columns are listed in `docs/data_dictionary.md`.
