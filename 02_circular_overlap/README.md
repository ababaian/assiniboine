# 02_circular_overlap -- trim the terminal overlap, label how each record closes

Logan assembles at k=31. A unitig that closes into a circle is emitted with its
first k-1 = 30 nt repeated as its last 30 nt, so the closing overlap is written
out twice. This stage removes that duplication and labels every record with how
it closes.

**This stage labels. It does not gate.** Every input record goes on to the
length filter, including the ones that are not circles. The label travels with
them so any class can be filtered, stratified or compared downstream.

    in                   01_kraken_filter/unclassified/*.fa
    labelled/*.fa        every record, trimmed where applicable, header tagged
    SUMMARY_overlap.txt  the counts

## Why the overlap has to go

Left in place it does two things:

- **Inflates every length by 30 nt.** Stage 3 filters on length, so the bounds
  would be applied to a number 30 larger than the molecule.
- **Corrupts the fold.** `RNAfold --circ` joins the last base to the first, so
  the duplicated 30-mer becomes a tandem repeat inserted into the circle.
  Every structural feature the classifier consumes is then computed on a
  sequence 30 nt longer than what exists.

Only the circular class carries that duplication, so only it is trimmed.

## The three classes

Most selfloops records carry the overlap, but not all. The rest are not short
records failing a guard; they are longer on average. The GFA self-link
orientation in the header separates them. Shares are from the November 2026
run, over all 900,042,456 source records and over the 595,006,157 that stage 1
keeps:

| class | header links | source | after stage 1 | terminal structure | trimmed |
|---|---|---:|---:|---|---|
| circular | `L:-:x:-` and `L:+:x:+` | 90.6% | 94.6% | first 30 == last 30 | 30 nt |
| hairpin | `L:-:x:+` or `L:+:x:-` | 9.4% | 5.4% | terminal 30-mer is its own reverse complement | no |
| unmatched | header and sequence disagree | 0 | 0 | none established | no |

An earlier version of this table gave about 63% and 37%. That came from a
sample drawn with near-equal classes, so it measured nothing about class shares.

A unitig whose terminal 30-mer is its own reverse complement is adjacent to
itself on the opposite strand, which creates a self-loop edge in the assembly
graph. That is a graph artifact, not a closed molecule: these are linear
contigs capped by an inverted repeat. They have no duplicated end to trim, and
folding them with `--circ` joins two ends that are not joined, so **treat rod
calls on the hairpin class with that in mind rather than reading them as
circles.** They are labelled, not discarded, because excluding them would
remove 37% of the input on a structural argument that has not been tested, and
because a terminal inverted repeat is a real feature worth screening.

On 1,000 records per class through the unchanged model the hairpin rod rate was
4.9% against 5.1% for circles, so the class is not enriched for rod calls and
was not inflating the October count.

Full measurements, including the K scan that pins the overlap at exactly 30 nt,
are in [`../analysis/circular_overlap/`](../analysis/circular_overlap/).

## Why classification keys on the header

Sequence alone is not safe. A low-complexity AT- or CG-rich terminus is its own
reverse complement by accident, so a sequence-only test files it as a hairpin
whatever its real topology. The header states how the assembler closed the
unitig, so that is the primary key and the sequence confirms it. Records whose
header claims a circle but whose ends do not match are labelled `unmatched` and
left untrimmed rather than trimmed on a guess. On 20,000 real records the two
agree completely and `unmatched` is empty.

This also means **anything that rewrites headers to bare IDs destroys the
classification.** Keep the `L:` fields.

## The label

The header gains `ovl:<class> trim:<nt>` after the existing fields:

    >DRR000001_40_circle_40 ka:f:78.719 L:-:40:- L:+:40:+ ovl:circular trim:30
    >DRR000002_393_circle_393 ka:f:13.200 L:+:393:- ovl:hairpin trim:0

`sample_name` in the screen's output comes from the first whitespace-delimited
token, which is untouched, so ids and joins are unaffected.

The screen's CSV keeps only `sample_name`, so to join a class onto the results,
recover the mapping from the headers:

    grep -h '^>' 02_circular_overlap/labelled/*.fa \
      | sed 's/^>\([^ ]*\).*ovl:\([a-z]*\).*/\1\t\2/'

## Running

    ./02_circular_overlap/trim_circular_overlap.sh \
        -o 02_circular_overlap 01_kraken_filter/unclassified

Takes a file, a directory, or `-` for stdin.

Output stays at exactly two lines per record, header then unwrapped sequence,
because the chunker in `../04_rod_screen/` splits on a fixed line count and a
wrapped FASTA would misalign every record after the first.

## Verified

On 20,000 real selfloops records: 20,000 in and 20,000 out, so nothing is
gated or duplicated; 13,206 circular and 6,794 hairpin and 0 unmatched;
`trim:30` on the circular class and `trim:0` on every other; every output two
lines per record; 0 of the trimmed records still carrying a 30-nt terminal
repeat; and 100 tagged records through `run_pipeline.py` produced clean
`sample_name` values with no tag leakage.
