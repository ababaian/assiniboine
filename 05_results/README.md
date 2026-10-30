# 05_results -- reduce the screen to the published tables

One row per screened circle becomes three tables.

    in                     04_rod_screen/results/chunk_*.csv
    rod_all.csv            predicted_class == rod
    rod_with_ribozyme.csv  rod AND n_ribozymes >= 1
    shortlist.csv          ranked candidates, two tiers

In the October 2026 run: 545,483,299 rows in, 25,222,331 rod (4.62%), 46,432
of those carrying a ribozyme, 16,757 with ribozymes on both strands, and a
2,056-row shortlist.

## Running

    ./05_results/make_results.sh

Refuses to run unless `04_rod_screen/SCREEN.DONE` exists, because that marker
is what proves no chunk was silently truncated. Writes
`SUMMARY_results.txt`.

## The shortlist rule

- **Tier 1**: ribozymes on both strands AND at least one corroborated locus,
  meaning independent CMs agree on the same site. Taken in full. 56 rows in
  the October run.
- **Tier 2**: both strands, no corroboration, confidence >= 0.8, ranked by
  confidence and **truncated** to `TOP_N` rows (2,000).

Tier 2 is the part to be careful about. In the October run the qualifying pool
was **13,399**, so the published cut landed at confidence **0.998** and
**11,399 candidates meeting the stated criteria are absent from the file.**
The published `DATA_README.md` describes tier 2 as "both strands, confidence
>= 0.8", which reads as complete and is not. Raise `TOP_N` to publish more.

## Columns

Of the screen's 48 columns the tables keep 41. Four ribozyme column names
appear twice in the pipeline's header, and the duplicate copies are dropped.

Two parsing notes for anyone consuming these files:

- `combination_detail` contains commas inside quotes, so use a real CSV
  reader, not `awk -F,`. The reduction itself only touches fields 3 and 19,
  both of which sit before that column, which is why the first two steps can
  use awk.
- `below_confidence_floor` is always False and carries no information.

## Lengths are as screened

If the overlap trim in `../02_circular_overlap/` was applied, lengths here are
the trimmed lengths. The October tables were produced without it, so every
length in them is 30 nt longer than the molecule, and any length-based cut
applied to those tables is shifted by 30.
