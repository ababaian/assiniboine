"""Reading and writing the FASTA records the pipeline works on.

Every FASTA file the pipeline writes is in *two-line* form: one header line,
then the whole sequence on the next line. Stage 4 shards its input with the
Unix ``split`` command, which cuts on line counts, so a wrapped sequence would
misalign every record after the first. The reader here accepts wrapped input
(the source archive is already two-line, but a student's own file may not be);
the writer always produces two-line output.

A Logan selfloops header looks like this::

    >SRR12604050_704504_circle_704504 ka:f:4.900 L:-:704504:- L:+:704504:+

* ``SRR12604050_704504_circle_704504`` is the record id. Its first part, up to
  the first underscore, is the SRA run the contig was assembled from.
* ``ka:f:4.900`` is the mean k-mer abundance (coverage).
* The ``L:`` fields are GFA links showing that the unitig joins to itself.
  Their strand signs are what stage 2 reads; see :mod:`assiniboine.topology`.
"""

from __future__ import annotations

import gzip
import subprocess
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, TextIO


@dataclass
class Record:
    """One FASTA record. ``header`` is the header line without its ``>``."""

    header: str
    sequence: str

    @property
    def id(self) -> str:
        """The first whitespace-delimited token of the header."""
        return record_id(self.header)

    @property
    def run_accession(self) -> str:
        """The SRA run the record was assembled from."""
        return run_accession(self.id)

    def as_fasta(self) -> str:
        return f">{self.header}\n{self.sequence}\n"


def record_id(header: str) -> str:
    """Return the record id: the header up to the first whitespace."""
    return header.split(maxsplit=1)[0]


def run_accession(identifier: str) -> str:
    """Return the SRA run accession, the id up to the first underscore."""
    return identifier.split("_", 1)[0]


COMPLEMENT = str.maketrans("ACGTN", "TGCAN")


def reverse_complement(sequence: str) -> str:
    """Reverse-complement an upper-case DNA sequence. Other letters become N."""
    cleaned = "".join(base if base in "ACGT" else "N" for base in sequence)
    return cleaned.translate(COMPLEMENT)[::-1]


# ---------------------------------------------------------------------------
# Opening files
# ---------------------------------------------------------------------------


@contextmanager
def open_text(path: str | Path, mode: str = "r") -> Iterator[TextIO]:
    """Open a text file, transparently handling ``.gz`` and ``.zst`` names.

    ``-`` means standard input (for reading) or standard output (for writing).
    Zstandard files go through the ``zstd`` command so the package needs no
    compression library of its own.
    """
    if mode not in ("r", "w"):
        raise ValueError(f"mode must be 'r' or 'w', not {mode!r}")
    path = str(path)

    if path == "-":
        yield sys.stdin if mode == "r" else sys.stdout
        return

    if path.endswith(".gz"):
        with gzip.open(path, mode + "t") as handle:
            yield handle
        return

    if path.endswith(".zst"):
        # zstd reads from or writes to a file we open ourselves, so symbolic
        # links to an archive work too (zstd skips them when given a name).
        if mode == "r":
            archive = open(path, "rb")
            process = subprocess.Popen(["zstd", "-dc"], stdin=archive, stdout=subprocess.PIPE, text=True)
            stream = process.stdout
        else:
            archive = open(path, "wb")
            process = subprocess.Popen(["zstd", "-q"], stdin=subprocess.PIPE, stdout=archive, text=True)
            stream = process.stdin
        try:
            yield stream
        finally:
            stream.close()
            process.wait()
            archive.close()
        if process.returncode != 0:
            raise RuntimeError(f"zstd failed on {path} with exit status {process.returncode}")
        return

    with open(path, mode) as handle:
        yield handle


# ---------------------------------------------------------------------------
# Reading and writing records
# ---------------------------------------------------------------------------


def parse_fasta(stream: Iterable[str]) -> Iterator[Record]:
    """Yield records from FASTA text. Wrapped sequences are joined."""
    header = None
    parts: list[str] = []
    for line in stream:
        line = line.rstrip("\n")
        if line.startswith(">"):
            if header is not None:
                yield Record(header, "".join(parts))
            header = line[1:]
            parts = []
        elif line:
            if header is None:
                raise ValueError("FASTA text does not start with a '>' header line")
            parts.append(line.strip())
    if header is not None:
        yield Record(header, "".join(parts))


def read_fasta(path: str | Path) -> Iterator[Record]:
    """Yield the records of a FASTA file (plain, ``.gz``, ``.zst`` or ``-``)."""
    with open_text(path) as stream:
        yield from parse_fasta(stream)


def read_fasta_files(paths: Iterable[str | Path]) -> Iterator[Record]:
    """Yield the records of several FASTA files, one file after another."""
    for path in paths:
        yield from read_fasta(path)


def write_fasta(stream: TextIO, records: Iterable[Record]) -> int:
    """Write records in two-line form. Returns how many were written."""
    count = 0
    for record in records:
        stream.write(record.as_fasta())
        count += 1
    return count


def count_records(path: str | Path) -> int:
    """Count the records of a FASTA file by counting header lines."""
    with open_text(path) as stream:
        return sum(1 for line in stream if line.startswith(">"))


def sorted_files(directory: str | Path, pattern: str) -> list[Path]:
    """The files in ``directory`` matching ``pattern``, in name order.

    Stages write one file per input part, named ``part_000.fa`` and so on.
    Sorting by name keeps the parts in source order, which the manifest in
    stage 6 relies on.
    """
    return sorted(Path(directory).glob(pattern))
