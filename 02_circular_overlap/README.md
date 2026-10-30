# 02_circular_overlap -- resolve the terminal overlap, split off the hairpins

Logan assembles at k=31. A unitig that closes into a circle is emitted with its
first k-1 = 30 nt repeated as its last 30 nt, so the closing overlap is written
out twice. This stage removes that duplication and, in the same pass,
separates the records that are not circles at all.

    in         01_kraken_filter/unclassified/*.fa
    circular/  overlap confirmed, trailing 30 nt trimmed  -> goes on to stage 3
    hairpin/   reverse-complement self-link, NOT a circle -> parked
    unmatched/ header and sequence disagree               -> parked, inspect

Nothing is dropped. The three counts sum to the input.

## Why the overlap has to go

Left in place it does two things:

- **Inflates every length by 30 nt.** Stage 3 filters on length, so the bounds
  would be applied to a number 30 larger than the molecule.
- **Corrupts the fold.** `RNAfold --circ` joins the last base to the first, so
  the duplicated 30-mer becomes a tandem repeat inserted into the circle.
  Every structural feature the classifier consumes is then computed on a
  sequence 30 nt longer than what exists.

## Why a third of the records are not circles

Only about 63% of selfloops records carry the overlap. The rest are not short
records failing a guard; they are longer on average. The GFA self-link
orientation in the header separates them:

| class | header links | share | terminal structure |
|---|---|---|---|
| circular | `L:-:x:-` and `L:+:x:+` | ~63% | first 30 == last 30 |
| hairpin | `L:-:x:+` or `L:+:x:-` | ~37% | terminal 30-mer is its own reverse complement, 100% of them |

A unitig whose terminal 30-mer is its own reverse complement is adjacent to
itself on the opposite strand, which creates a self-loop edge in the assembly
graph. That is a graph artifact, not a closed molecule: these are linear
contigs capped by an inverted repeat. They have no duplicated end to trim, and
folding them with `--circ` has no biological meaning, so they are parked rather
than screened. The October run folded all of them as circles.

Full measurements, including the K scan that pins the overlap at exactly 30 nt,
are in [`../analysis/circular_overlap/`](../analysis/circular_overlap/).

## Why classification keys on the header

Sequence alone is not safe. A low-complexity AT- or CG-rich terminus is its own
reverse complement by accident, so a sequence-only test files it as a hairpin
whatever its real topology. The header states how the assembler closed the
unitig, so that is the primary key and the sequence confirms it. Disagreements
go to `unmatched/` rather than being trimmed on a guess. On 20,000 real records
the two agree completely and `unmatched/` is empty.

This also means **anything that rewrites headers to bare IDs destroys the
classification.** Keep the `L:` fields.

## Running

    ./02_circular_overlap/trim_circular_overlap.sh \
        -o 02_circular_overlap 01_kraken_filter/unclassified

Takes a file, a directory, or `-` for stdin. Writes `SUMMARY_overlap.txt` with
the three counts.

Output stays at exactly two lines per record, header then unwrapped sequence,
because the chunker in `../04_rod_screen/` splits on a fixed line count and a
wrapped FASTA would misalign every record after the first.

## Verified

On 20,000 real selfloops records: 20,000 in, 20,000 out across the three
classes, 13,206 circular and 6,794 hairpin and 0 unmatched, every output two
lines per record, and **0 of the trimmed records still carry a 30-nt terminal
repeat.**
