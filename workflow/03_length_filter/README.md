# Stage 3: keep 200 to 6,000 nt

    ./workflow/03_length_filter/length_filter.sh

Files each record by its trimmed length against `[length] min_nt` and
`max_nt`, both inclusive. The floor is biological, the ceiling works around
`RNAfold` stopping on oversized input; `docs/methods.md` has the reasoning.

| output | what it is |
|---|---|
| `in_range/part_NNN.fa` | goes on to the rod screen |
| `too_short/part_NNN.fa` | parked, below any known viroid-like agent |
| `too_long/part_NNN.fa` | parked, beyond what RNAfold will fold |
| `counts/part_NNN.tsv`, `summary.txt` | records per bin |

Nothing is deleted, so either bound can be changed and the stage re-run
without touching stage 1.
