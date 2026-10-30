# Terminal 30-nt overlap, and the 37% that are not circles

Side analysis, not part of the screen. It establishes two things the pipeline
depends on: that the overlap Logan writes into selfloops records is exactly
30 nt, and that about a third of those records are not circular at all.

Measured on 100,000 raw selfloops records (`scan_overlap.sh`).

## The overlap is exactly 30 nt

Fraction of records whose first K nt equal their last K nt, for K from 20 to 36:

     K   matched        %
    20         4     0.00%
    21-29    0-1     0.00%
    30     62801    62.80%
    31-36      0     0.00%

Sharp and exclusive. Logan assembles at k=31, and a unitig that closes on
itself is emitted with its k-1 = 30 nt closing overlap written out at both
ends, so 30 is the expected value and the measurement confirms it. The
handful of hits at K=20, 22, 26 and 29 are one to four records each, i.e.
coincidence. Zero records match at 31 or above, so no record carries a longer
overlap.

Left in place, that overlap does two things. It inflates every length by
30 nt, which matters because the pipeline filters on length. And once
`RNAfold --circ` joins the last base to the first, the duplicated 30-mer
becomes a tandem repeat inserted into the folded circle, so every structural
feature fed to the classifier is computed on a sequence 30 nt longer than the
molecule.

## The other 37% are reverse-complement self-links

Only 62.80% carry the overlap. The remainder are not short records failing a
length guard: they are *longer* on average, 432.5 nt against 321.0 nt, and no
record in the sample is under 60 nt.

The GFA self-link orientation in the header predicts the class almost
perfectly:

| class | header links | n | share | terminal structure |
|---|---|---|---|---|
| circular | `L:-:x:-` and `L:+:x:+` | 62,695 | 62.7% | first 30 == last 30 |
| hairpin C | `L:-:x:+` | 17,589 | 17.6% | first 30 nt is its own reverse complement |
| hairpin D | `L:+:x:-` | 19,716 | 19.7% | last 30 nt is its own reverse complement |

The palindrome holds for **100%** of both hairpin classes, 17,589 of 17,589
and 19,716 of 19,716, and for **0%** of the circular class. Cross-prediction
between header and sequence is 99.8% or better in both directions.

A unitig whose terminal 30-mer is its own reverse complement produces a
self-loop edge in the assembly graph, because that k-mer is adjacent to itself
on the opposite strand. That is a graph artifact, not a closed molecule. These
records are linear contigs capped by an inverted repeat, and the "selfloop"
label is misleading for them.

Two consequences:

- They must not be trimmed. There is no duplicated end to remove.
- Folding them with `--circ`, which joins base n to base 1, has no biological
  meaning. The October run did exactly that to all of them.

A terminal perfect inverted repeat is also, by construction, a strong hairpin,
which is the self-pairing a rod classifier keys on. Whether that biases the
rod rate is not settled here.

## Why classification keys on the header, not the sequence

Sequence alone is not safe. A low-complexity AT-rich or CG-rich terminus is
its own reverse complement by accident: `ATATATATAT` and `CGCGCGCGCG` both
are. A fixture built from those repeats was filed as a hairpin by a
sequence-only test even though it was neither class. The header states how the
assembler closed the unitig, so the pipeline keys on that and uses the
sequence to confirm it, sending any disagreement to `unmatched/` rather than
trimming on a guess.

On 20,000 real records the two agree completely: 13,206 circular, 6,794
hairpin, **0 unmatched**, and every input lands in exactly one output.

## Effect on the October results

Lengths in the published tables are untrimmed, so each is 30 nt too long for
the circular class. Any length-based cut applied to those tables is shifted by
30 nt, including the `rod under 200 nt` figures quoted in
`../../03_length_filter/README.md`.

## Reproducing

    ./scan_overlap.sh <selfloops.fa>          # the K scan and the class table

Needs a raw selfloops FASTA with headers intact. The `L:` fields are the whole
basis of the classification, so anything that rewrites headers to bare IDs
destroys it.
