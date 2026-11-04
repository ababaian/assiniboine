"""Stage 2: how each record closes, and the overlap trim.

Logan assembles at k = 31. A unitig that closes into a circle is written out
with its first k - 1 = 30 nt repeated as its last 30 nt. Left in place that
overlap inflates every length by 30 nt and, once ``RNAfold --circ`` joins the
last base to the first, inserts a spurious tandem copy of those 30 nt into the
folded structure. So the circular class is trimmed.

Not every selfloops record is a circle. The GFA self-links in the header say
how the assembler closed the unitig:

circular
    ``L:-:x:-`` and ``L:+:x:+``, and the first 30 nt equal the last 30 nt.
    The trailing 30 nt are removed.
hairpin
    ``L:+:x:-`` or ``L:-:x:+``. The terminal 30-mer is its own reverse
    complement, so the self-loop is an assembly-graph artifact, not a closed
    molecule. Nothing is trimmed.
unmatched
    The header claims a circle but the sequence disagrees, or there is no
    recognisable link. Nothing is trimmed.

The header is the primary key and the sequence confirms it. Sequence alone is
not safe: a low-complexity AT- or CG-rich terminus is its own reverse
complement by accident.

This stage labels; it does not discard. Every record goes on to the length
filter with ``ovl:<class> trim:<nt>`` appended to its header, so any class can
be selected or compared downstream. The record id (the first token of the
header) is untouched, so ids and joins are unaffected.
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from assiniboine.sequences import Record, open_text, parse_fasta

DEFAULT_OVERLAP = 30

CIRCULAR = "circular"
HAIRPIN = "hairpin"
UNMATCHED = "unmatched"
CLOSURE_CLASSES = (CIRCULAR, HAIRPIN, UNMATCHED)

# The three link patterns the classification reads from the header.
MINUS_TO_MINUS = re.compile(r"L:-:\d+:-")
PLUS_TO_PLUS = re.compile(r"L:\+:\d+:\+")
OPPOSITE_STRAND = re.compile(r"L:\+:\d+:-|L:-:\d+:\+")

LABEL_PATTERN = re.compile(r" ovl:(\w+) trim:(\d+)$")


def classify_closure(header: str, sequence: str, overlap: int = DEFAULT_OVERLAP) -> tuple[str, int]:
    """Return ``(closure_class, bases_to_trim)`` for one record.

    ``sequence`` must be upper case; the comparison of the two ends is exact.
    """
    same_strand_links = bool(MINUS_TO_MINUS.search(header) and PLUS_TO_PLUS.search(header))
    opposite_strand_link = bool(OPPOSITE_STRAND.search(header))

    if opposite_strand_link and not same_strand_links:
        return HAIRPIN, 0

    long_enough = len(sequence) >= 2 * overlap
    if same_strand_links and long_enough and sequence[:overlap] == sequence[-overlap:]:
        return CIRCULAR, overlap

    return UNMATCHED, 0


def label_record(record: Record, overlap: int = DEFAULT_OVERLAP) -> tuple[Record, str]:
    """Classify one record and return ``(labelled_record, closure_class)``.

    The returned record has an upper-case sequence, the overlap removed if the
    record is circular, and ``ovl:<class> trim:<nt>`` appended to its header.
    """
    sequence = record.sequence.upper()
    closure, trim = classify_closure(record.header, sequence, overlap)
    if trim:
        sequence = sequence[:-trim]
    labelled = Record(f"{record.header} ovl:{closure} trim:{trim}", sequence)
    return labelled, closure


def parse_label(header: str) -> tuple[str, int]:
    """Read ``(closure_class, bases_trimmed)`` back from a labelled header."""
    match = LABEL_PATTERN.search(header)
    if match is None:
        raise ValueError(f"header carries no 'ovl:<class> trim:<nt>' label: {header}")
    return match.group(1), int(match.group(2))


def strip_label(header: str) -> str:
    """Return the header as it was before stage 2 labelled it."""
    return LABEL_PATTERN.sub("", header)


def label_file(input_path: str | Path, output_path: str | Path, overlap: int = DEFAULT_OVERLAP) -> Counter:
    """Label every record of one FASTA file. Returns the count per class."""
    counts: Counter = Counter({closure: 0 for closure in CLOSURE_CLASSES})
    with open_text(input_path) as input_stream, open_text(output_path, "w") as output_stream:
        for record in parse_fasta(input_stream):
            labelled, closure = label_record(record, overlap)
            output_stream.write(labelled.as_fasta())
            counts[closure] += 1
    return counts
