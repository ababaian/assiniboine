"""Stage 7: fold every rod again and keep its dot-bracket structure.

Stage 4 folds every screened record but keeps only numbers computed from the
structure (``mfe_per_nt``, ``frac_paired``, stem and loop counts). This stage
refolds the rods with the same command, ``RNAfold --circ --noPS``, and keeps
the structure strings.

Folding cost rises steeply with length, so the rods are sorted longest first
and dealt round-robin into parts: every part then carries the same mix of
lengths and the parts finish at about the same time. One ``RNAfold`` process
folds each part; the shell script runs the parts in parallel.

The output keeps the order of ``rods.csv``. Each rod is tagged with its row
number on the way out and the parts are merged back on that number.
"""

from __future__ import annotations

import csv
import heapq
import re
from array import array
from contextlib import ExitStack
from pathlib import Path
from typing import Iterable, Iterator, NamedTuple

from assiniboine.sequences import open_text

OUTPUT_COLUMNS = ("sample_name", "length", "mfe", "dot_bracket")

# RNAfold prints, per record, the header, the sequence, then the structure
# followed by the minimum free energy in parentheses: "((...)) ( -1.20)".
STRUCTURE_LINE = re.compile(r"^([.()]+)\s+\(\s*(-?\d+\.\d+)\)\s*$")


class FoldedRod(NamedTuple):
    index: int  # row number in rods.csv, counting from 0
    sample_name: str
    length: int
    mfe: float
    dot_bracket: str


class DotBracketError(Exception):
    """RNAfold output does not account for every rod it was given."""


# ---------------------------------------------------------------------------
# Splitting the rods into balanced parts
# ---------------------------------------------------------------------------


def read_lengths(rods_csv: str | Path) -> array:
    """First pass over ``rods.csv``: just the length of every rod."""
    lengths = array("L")
    with open(rods_csv, newline="") as stream:
        for row in csv.DictReader(stream):
            lengths.append(int(row["length"]))
    return lengths


def assign_parts(lengths: array, n_parts: int) -> array:
    """Deal the rods, longest first, round-robin into ``n_parts`` parts."""
    longest_first = sorted(range(len(lengths)), key=lambda index: lengths[index], reverse=True)
    part_of = array("L", [0] * len(lengths))
    for rank, index in enumerate(longest_first):
        part_of[index] = rank % n_parts
    return part_of


def split_rods(rods_csv: str | Path, parts_dir: str | Path, n_parts: int) -> int:
    """Write ``parts_dir/part_NNN.fa`` files for RNAfold. Returns the rod count.

    Each header is ``>index|sample_name|length`` so the structure can be
    matched back to its rod and checked against its length.
    """
    parts_dir = Path(parts_dir)
    parts_dir.mkdir(parents=True, exist_ok=True)
    part_of = assign_parts(read_lengths(rods_csv), n_parts)

    with ExitStack() as stack:
        streams = [stack.enter_context(open(parts_dir / f"part_{part:03d}.fa", "w")) for part in range(n_parts)]
        with open(rods_csv, newline="") as stream:
            for index, row in enumerate(csv.DictReader(stream)):
                streams[part_of[index]].write(f">{index}|{row['sample_name']}|{row['length']}\n{row['sequence']}\n")
    return len(part_of)


# ---------------------------------------------------------------------------
# Reading RNAfold output
# ---------------------------------------------------------------------------


def parse_rnafold(lines: Iterable[str]) -> Iterator[FoldedRod]:
    """Yield one :class:`FoldedRod` per three-line RNAfold block."""
    lines = iter(lines)
    for header in lines:
        header = header.rstrip("\n")
        if not header.startswith(">"):
            raise DotBracketError(f"expected a header line, got: {header[:60]}")
        index, sample_name, length = header[1:].split("|")
        sequence = next(lines, "").rstrip("\n")
        structure_line = next(lines, "").rstrip("\n")
        match = STRUCTURE_LINE.match(structure_line)
        if match is None:
            raise DotBracketError(f"{sample_name}: no structure line after the sequence, got: {structure_line[:60]}")
        dot_bracket, mfe = match.group(1), float(match.group(2))
        if len(sequence) != int(length) or len(dot_bracket) != int(length):
            raise DotBracketError(
                f"{sample_name}: length {length} but RNAfold echoed {len(sequence)} nt and a {len(dot_bracket)}-character structure"
            )
        yield FoldedRod(int(index), sample_name, int(length), mfe, dot_bracket)


def parse_part(fold_output: str | Path, out_tsv: str | Path, expected_rods: int | None = None) -> int:
    """Convert one part's RNAfold output to TSV sorted by row number. Returns the rod count."""
    with open(fold_output) as stream:
        folded = sorted(parse_rnafold(stream), key=lambda rod: rod.index)
    if expected_rods is not None and len(folded) != expected_rods:
        raise DotBracketError(f"{fold_output}: {len(folded)} structures for {expected_rods} rods")
    with open(out_tsv, "w") as stream:
        for rod in folded:
            stream.write(f"{rod.index}\t{rod.sample_name}\t{rod.length}\t{rod.mfe}\t{rod.dot_bracket}\n")
    return len(folded)


def read_part_tsv(path: str | Path) -> Iterator[FoldedRod]:
    with open(path) as stream:
        for line in stream:
            index, sample_name, length, mfe, dot_bracket = line.rstrip("\n").split("\t")
            yield FoldedRod(int(index), sample_name, int(length), float(mfe), dot_bracket)


def collect_parts(part_tsvs: Iterable[str | Path], out_path: str | Path, expected_rods: int | None = None) -> int:
    """Merge the per-part TSVs back into ``rods.csv`` order. Returns the rod count.

    Each part file is already sorted by row number, so a k-way merge keeps
    memory flat however many rods there are. Every row number from 0 up must
    appear exactly once.
    """
    readers = [read_part_tsv(path) for path in part_tsvs]
    count = 0
    with open_text(out_path, "w") as stream:
        stream.write("\t".join(OUTPUT_COLUMNS) + "\n")
        for rod in heapq.merge(*readers, key=lambda rod: rod.index):
            if rod.index != count:
                raise DotBracketError(f"rod {count} is missing from the folded parts (next is {rod.index})")
            stream.write(f"{rod.sample_name}\t{rod.length}\t{rod.mfe}\t{rod.dot_bracket}\n")
            count += 1
    if expected_rods is not None and count != expected_rods:
        raise DotBracketError(f"{count} structures collected for {expected_rods} rods")
    return count
