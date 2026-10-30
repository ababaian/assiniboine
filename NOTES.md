# Notes

Running record for this repo: decisions, and the results of runs that the
current README no longer describes.

## The October 2026 run

The screen was run once end to end, 2026-10-02 to 2026-10-05, with an earlier
version of this pipeline. Its outputs are in
`s3://petadex/circs-results/`, and local copies of the tables, per-chunk logs,
taxonomy reports and run accession lists are in `run_outputs_2026-10/` on
watson, which is gitignored.

**The pipeline that produced it is tagged `run-2026-10`** (commit `29946fe`,
the first commit on `main`). To read or run it:

    git show run-2026-10 --stat
    git worktree add ../k2-oct2026 run-2026-10

It predates the overlap trim, the 200 nt floor and the removal of the dedup
stage, so its outputs carry the defects listed below.

### Result

545,483,299 circles screened. **25,222,331 called rod** (4.62%), of which
**46,432 carry a ribozyme** and **16,757 carry ribozymes on both strands**,
the rolling-circle hallmark. Shortlist 2,056 rows.

### Verification

| check | result |
|---|---|
| stage 1 processed == independent `grep -c '^>'` of the source | 900,042,456, exact |
| stage 1 recount of output FASTAs | 595,006,157, exact |
| dedup kept + dropped == input | 594,734,382, exact |
| dedup output provably duplicate-free | `sort -c -u` exit 0 |
| screen chunks completed | 320 / 320 |
| screen rows out == records in, summed | 545,483,299 both sides |
| screen row-count mismatches | 0, so RNAfold never silently truncated |
| distinct headers across the 320 result files | 1 |

### Composition of the discarded third

Host genome, overwhelmingly. Eukaryota 232,188,594; Bacteria 17,018,268;
Viruses 693,256; Archaea 100,769. Top named organisms: *H. sapiens* 79,072,262,
*M. musculus* 49,066,150, *A. thaliana* 4,302,106.

The target classes were almost absent from what core_nt could name, which is
the whole argument for screening the unnamed two-thirds:

    Microviridae    44,307      Circoviridae     2,832
    Inoviridae      13,609      Geminiviridae    1,085
    Pospiviroidae   12,961      Nanoviridae        412
    Genomoviridae    5,104      Avsunviroidae      219
    Anelloviridae    2,931      Ribozyviria         54

### Ribozyme families among the 46,432

    hhrbz_dv4  30,905    Hammerhead_3   630
    twister-P1  8,093    DVR4           609
    hairpin-meta 3,968   VS             137
    Hammerhead_1  805    HDV              1

One HDV-family hit in 545 million circles.

### Defects in that run, carried into its outputs

- **Lengths are 30 nt too long** and every fold contained a spurious tandem
  repeat, because the terminal overlap was not trimmed. Any length-based cut
  applied to those tables is shifted by 30.
- **The shortlist's tier 2 is truncated** to 2,000 rows out of a qualifying
  pool of 13,399, so the effective cut is confidence 0.998 rather than the 0.8
  its `DATA_README.md` states, and 11,399 candidates meeting the stated
  criteria are absent from the file.
- **The completion gate counted every `.done` marker** rather than those for
  the current chunk set, so an earlier run's markers could declare a new run
  complete. Chunk creation was also never scripted, and with an empty chunk
  directory the gate passed and wrote the DONE marker over a run that screened
  nothing. Both fixed.
- **`below_confidence_floor` is always False** and carries no information: the
  model's floor is 0.5 and a binary classifier's winning class is at least 0.5
  by construction. Threshold on `confidence`.
- **`dedup_map.tsv` is gone**, deleted in the October 2026 cleanup. The dedup
  stage was built to be reversible so a hit could be expanded back to every SRA
  run carrying that circle; that is no longer possible for these tables.

## Decisions

**2026-10-30, no archive folders.** An `archive/Pipeline/` copy of the October
pipeline was briefly added so past versions would not have to be dug out of
history. That is what git already does, so it was removed and the commit
tagged `run-2026-10` instead. Version history goes in git, run records go
here.
