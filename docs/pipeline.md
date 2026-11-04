# The pipeline, stage by stage

Eight stages, run in order by `workflow/run_screen.sh`. Each one reads what
the previous one wrote under the work directory, checks it, writes its own
output and a `summary.txt`, and leaves a `DONE` marker. A stage with a
marker is skipped on the next run; delete the marker to run it again.

```
                       source archive (FASTA, every record two lines)
                                     |
  stage 1    Kraken2 ----------------+---------------- classified: dropped, call kept
                                     | unclassified/
  stage 2    closure label ----------+  every record, header tagged, circles trimmed
                                     | labelled/
  stage 3    length filter ----------+---------------- too_short/, too_long/: parked
                                     | in_range/
  stage 4    rod screen -------------+  chunks/ -> results/, one row per record
                                     |
  stage 5    results ----------------+  rods.csv, rods_with_ribozyme.csv, shortlist.csv
                                     |
  stage 6    package                 |  record_manifest.tsv.zst (rebuilds stages 1-3), MD5SUMS
  stage 7    dot-bracket ------------+  rods_dotbracket.tsv.zst
```

The work directory mirrors this:

```
work/
  00_source/           the archive
  01_kraken_filter/    unclassified/ calls/ reports/ logs/ counts/ summary.txt
  02_circular_overlap/ labelled/ counts/ summary.txt
  03_length_filter/    in_range/ too_short/ too_long/ counts/ summary.txt
  04_rod_screen/       chunks/ results/ logs/ summary.txt
  05_results/          rods.csv rods_with_ribozyme.csv shortlist.csv summary.txt
  06_package/          record_manifest.tsv.zst MD5SUMS summary.txt
  07_dotbracket/       parts/ folded/ rods_dotbracket.tsv.zst
```

Stages 1 to 3 keep the source's division into *parts* (`part_000.fa`,
`part_001.fa`, ...) of `[compute] records_per_part` records each. Stage 4
re-cuts the in-range records into *chunks* of `[compute] records_per_chunk`.
The record id is the same at every stage, so any two files can be joined on
it.

## Stage 0: source

Fetches `[source] url`, retrying and checking the size against
`[source] expected_bytes`. A local path is linked rather than copied.

## Stage 1: Kraken2 filter

Cuts the archive into parts and runs Kraken2 on each at
`[kraken] confidence` against `[kraken] database`. Records the database
names are dropped; the rest go on. Three things are kept per part: the
unclassified records (stage 2's input), every record's call (`C` or `U`,
id, taxid, length; what stage 6 needs), and Kraken2's taxonomy report.

Parts are classified in parallel with `--memory-mapping`, so the processes
share one copy of the database through the operating system's page cache.
Each part is deleted after its classification succeeds. Re-running skips
parts with a `.done` marker.

## Stage 2: circular overlap

For each record, reads the GFA self-links in the header and compares the
two ends of the sequence, then labels the record `circular`, `hairpin` or
`unmatched` and trims the duplicated `[overlap] length` bases from circular
ones. Everything is passed on; see `docs/methods.md` for why the hairpins
are kept. The rule is `topology.classify_closure`.

## Stage 3: length filter

Files each record by its trimmed length into `in_range`, `too_short` or
`too_long`, against `[length] min_nt` and `max_nt`. The parked records are
kept so a bound can be changed without redoing stage 1. The rule is
`filtering.length_bin`.

## Stage 4: rod screen

Concatenates the in-range parts, cuts them into chunks, and runs the
external classifier on each chunk. Per record it runs `getorf` on the
doubled sequence, `RNAfold --circ`, and `cmsearch` against the in-house
`dvr5` model and 18 Rfam ribozyme models, then a random forest calls `rod`
or `not_rod`. The output is one CSV per chunk with the call, its
confidence, and 43 feature columns.

A chunk is accepted only when its CSV has exactly one row per input record
(`validation.check_screen_output`). This is the only guard against
`RNAfold` stopping early on an oversized sequence, which it does silently
with exit status 0. Failed chunks are listed in `FAILED.txt` and retried on
re-run.

## Stage 5: results

Reads each chunk's FASTA and CSV side by side, checking that the ids line
up, and keeps the rows called `rod` with their sequence, SRA run and closure
class attached. Writes `rods.csv`, the subset with a ribozyme, and the
two-tier shortlist. `results.py` has the rules; `docs/methods.md` the
reasons.

## Stage 6: package

Builds the record manifest, one row per source record saying what stages 1
to 3 did with it, by walking the source, the Kraken2 calls and the stage 2
output together and checking they agree at every record. Then streams the
source again and proves that the manifest rebuilds every stage 1 to 3 file
byte for byte. Finally writes `MD5SUMS` over everything a run keeps.
`docs/reproducibility.md` explains what this buys.

## Stage 7: dot-bracket

Deals the rods into balanced parts, folds each with `RNAfold --circ --noPS`
(the command stage 4 used), checks every structure is as long as its
sequence, and merges the parts back into `rods.csv` order.

## Where the time goes

Stage 4 dominates: folding is cubic in sequence length, and on the November
2026 run its 161 million records took about 66 hours on 480 cores. Stage 1
is bound by Kraken2's database size and took 16 minutes on a machine that
could hold the 340 GB index in memory. Everything else is a pass or two
over the data and takes minutes to an hour. Stage 7 took about 3 hours on
460 cores.
