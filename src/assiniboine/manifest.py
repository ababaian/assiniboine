"""Stage 6: the record manifest, and rebuilding stages 1 to 3 from it.

Stages 1 to 3 write hundreds of gigabytes of FASTA, yet every record in them
is a record of the source archive that was dropped, trimmed or filed by a
fixed rule. The manifest records that rule's outcome for every source record
in one row, in source order::

    id       first header token, e.g. DRR000091_3841_circle_3841
    run      the SRA run, the id up to its first underscore
    length   source length in nt, before any trim
    kraken   C = classified (dropped at stage 1), U = unclassified (kept)
    taxid    Kraken2 taxon id for C, 0 for U
    closure  circular | hairpin | unmatched, by the stage 2 rule; for C
             records, which never reached stage 2, the rule is applied here
    stage    classified | too_short | in_range | too_long: where it ended

Source archive plus manifest rebuild every stage 1 to 3 file byte for byte,
so the manifest is what gets kept and shared instead of the FASTA.

Building the manifest is also a check. Every source record must match, in
order, the next Kraken2 call and, if unclassified, the next stage 2 record,
and all three streams must end together.
"""

from __future__ import annotations

import hashlib
from collections import Counter
from contextlib import ExitStack
from itertools import groupby, zip_longest
from pathlib import Path
from typing import Iterable, Iterator, NamedTuple

from assiniboine.filtering import LENGTH_BINS, length_bin
from assiniboine.sequences import Record, open_text, parse_fasta, read_fasta_files
from assiniboine.topology import CIRCULAR, classify_closure, parse_label, strip_label

MANIFEST_COLUMNS = ("id", "run", "length", "kraken", "taxid", "closure", "stage")
CLASSIFIED = "classified"
UNCLASSIFIED = "unclassified"
LABELLED = "labelled"
REBUILT_FILES = (CLASSIFIED, UNCLASSIFIED, LABELLED) + LENGTH_BINS


class ManifestError(Exception):
    """The source, the Kraken2 calls and the stage 2 output disagree."""


class ManifestRow(NamedTuple):
    id: str
    run: str
    length: int
    kraken: str
    taxid: str
    closure: str
    stage: str


class KrakenCall(NamedTuple):
    status: str  # C or U
    id: str
    taxid: str
    length: int


# ---------------------------------------------------------------------------
# Reading the inputs
# ---------------------------------------------------------------------------


def read_kraken_calls(paths: Iterable[str | Path]) -> Iterator[KrakenCall]:
    """Yield the per-record calls Kraken2 wrote, from one file after another.

    Only the first four tab-separated columns are read: status, id, taxid and
    sequence length. Stage 1 keeps exactly those.
    """
    for path in paths:
        with open_text(path) as stream:
            for line in stream:
                status, identifier, taxid, length = line.rstrip("\n").split("\t")[:4]
                yield KrakenCall(status, identifier, taxid, int(length))


def read_manifest(path: str | Path) -> Iterator[ManifestRow]:
    with open_text(path) as stream:
        header = next(stream, "").rstrip("\n").split("\t")
        if tuple(header) != MANIFEST_COLUMNS:
            raise ManifestError(f"{path} does not start with the manifest header {MANIFEST_COLUMNS}")
        for line in stream:
            fields = line.rstrip("\n").split("\t")
            yield ManifestRow(fields[0], fields[1], int(fields[2]), fields[3], fields[4], fields[5], fields[6])


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------


def build_rows(
    source_records: Iterable[Record],
    calls: Iterable[KrakenCall],
    labelled_records: Iterable[Record],
    overlap: int,
    min_length: int,
    max_length: int,
) -> Iterator[ManifestRow]:
    """Merge the three streams into manifest rows, checking them as it goes."""
    calls = iter(calls)
    labelled_records = iter(labelled_records)
    next_call = next(calls, None)
    next_labelled = next(labelled_records, None)

    for record in source_records:
        if next_call is None:
            raise ManifestError(f"the Kraken2 calls ended before the source did, at record {record.id}")
        if next_call.id != record.id:
            raise ManifestError(f"source record {record.id} but the next Kraken2 call is for {next_call.id}")
        length = len(record.sequence)
        if next_call.length != length:
            raise ManifestError(f"{record.id}: Kraken2 saw {next_call.length} nt, the source has {length}")
        call = next_call
        next_call = next(calls, None)

        if call.status == "C":
            closure, _ = classify_closure(record.header, record.sequence.upper(), overlap)
            yield ManifestRow(record.id, record.run_accession, length, "C", call.taxid, closure, CLASSIFIED)
            continue
        if call.status != "U":
            raise ManifestError(f"{record.id}: Kraken2 status {call.status!r} is neither C nor U")

        if next_labelled is None:
            raise ManifestError(f"the stage 2 output ended before the unclassified records did, at {record.id}")
        if next_labelled.id != record.id:
            raise ManifestError(f"unclassified record {record.id} but the next stage 2 record is {next_labelled.id}")
        if strip_label(next_labelled.header) != record.header:
            raise ManifestError(f"{record.id}: the stage 2 header is not the source header plus a label")
        closure, trim = parse_label(next_labelled.header)
        if trim != (overlap if closure == CIRCULAR else 0):
            raise ManifestError(f"{record.id}: trim {trim} does not fit closure class {closure}")
        trimmed_length = length - trim
        if len(next_labelled.sequence) != trimmed_length:
            raise ManifestError(f"{record.id}: stage 2 wrote {len(next_labelled.sequence)} nt, expected {trimmed_length}")
        next_labelled = next(labelled_records, None)

        stage = length_bin(trimmed_length, min_length, max_length)
        yield ManifestRow(record.id, record.run_accession, length, "U", call.taxid, closure, stage)

    if next_call is not None:
        raise ManifestError(f"Kraken2 calls are left over after the source ended, next is {next_call.id}")
    if next_labelled is not None:
        raise ManifestError(f"stage 2 records are left over after the source ended, next is {next_labelled.id}")


def write_manifest(rows: Iterable[ManifestRow], path: str | Path) -> dict[str, Counter]:
    """Write the rows as TSV. Returns the counts by Kraken2 status, closure class and stage."""
    counts = {"kraken": Counter(), "closure": Counter(), "stage": Counter()}
    with open_text(path, "w") as stream:
        stream.write("\t".join(MANIFEST_COLUMNS) + "\n")
        for row in rows:
            stream.write("\t".join(str(value) for value in row) + "\n")
            counts["kraken"][row.kraken] += 1
            counts["closure"][row.closure] += 1
            counts["stage"][row.stage] += 1
    return counts


# ---------------------------------------------------------------------------
# Rebuilding
# ---------------------------------------------------------------------------


def rebuild_records(
    source_records: Iterable[Record],
    rows: Iterable[ManifestRow],
    overlap: int,
    min_length: int,
    max_length: int,
) -> Iterator[tuple[int, str, Record]]:
    """Replay stages 1 to 3 from the source and the manifest.

    Yields ``(source_index, destination, record)`` where ``destination`` is one
    of :data:`REBUILT_FILES`. An unclassified record is yielded three times:
    as stage 1 wrote it, as stage 2 labelled it, and in its stage 3 length bin.
    """
    for index, (record, row) in enumerate(zip_longest(source_records, rows)):
        if record is None:
            raise ManifestError(f"the manifest has more rows than the source has records, next is {row.id}")
        if row is None:
            raise ManifestError(f"the source has more records than the manifest has rows, next is {record.id}")
        if record.id != row.id:
            raise ManifestError(f"source record {record.id} but manifest row {row.id}")

        if row.kraken == "C":
            yield index, CLASSIFIED, record
            continue

        yield index, UNCLASSIFIED, record
        trim = overlap if row.closure == CIRCULAR else 0
        sequence = record.sequence.upper()
        if trim:
            sequence = sequence[:-trim]
        labelled = Record(f"{record.header} ovl:{row.closure} trim:{trim}", sequence)
        yield index, LABELLED, labelled

        stage = length_bin(len(sequence), min_length, max_length)
        if stage != row.stage:
            raise ManifestError(f"{row.id}: {len(sequence)} nt falls in {stage} but the manifest says {row.stage}")
        yield index, stage, labelled


def part_name(part_number: int) -> str:
    return f"part_{part_number:03d}"


def rebuild_by_part(
    source_records: Iterable[Record],
    rows: Iterable[ManifestRow],
    records_per_part: int,
    overlap: int,
    min_length: int,
    max_length: int,
) -> Iterator[tuple[int, Iterator[tuple[str, Record]]]]:
    """Group the rebuilt records by the stage 1 part they belong to.

    Stage 1 cut the source into parts of ``records_per_part`` records, and
    stages 2 and 3 kept that division, so a source record's part is its index
    divided by the part size. Yields ``(part_number, (destination, record)...)``.
    """
    rebuilt = rebuild_records(source_records, rows, overlap, min_length, max_length)
    for part_number, group in groupby(rebuilt, key=lambda item: item[0] // records_per_part):
        yield part_number, ((destination, record) for _, destination, record in group)


def write_rebuilt_files(
    source_records: Iterable[Record],
    rows: Iterable[ManifestRow],
    out_dir: str | Path,
    records_per_part: int,
    overlap: int,
    min_length: int,
    max_length: int,
) -> int:
    """Write the stage 1 to 3 files under ``out_dir``. Returns the part count."""
    out_dir = Path(out_dir)
    parts_written = 0
    for part_number, items in rebuild_by_part(source_records, rows, records_per_part, overlap, min_length, max_length):
        with ExitStack() as stack:
            streams = {}
            for destination in REBUILT_FILES:
                directory = out_dir / destination
                directory.mkdir(parents=True, exist_ok=True)
                streams[destination] = stack.enter_context(open(directory / f"{part_name(part_number)}.fa", "w"))
            for destination, record in items:
                streams[destination].write(record.as_fasta())
        parts_written += 1
    return parts_written


def md5_of_file(path: str | Path) -> str:
    digest = hashlib.md5()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_rebuild(
    source_records: Iterable[Record],
    rows: Iterable[ManifestRow],
    existing_dirs: dict[str, str | Path],
    records_per_part: int,
    overlap: int,
    min_length: int,
    max_length: int,
) -> list[str]:
    """Check that the rebuilt files equal the ones a run wrote, without writing.

    ``existing_dirs`` maps a destination (``unclassified``, ``labelled``,
    ``too_short``, ...) to the directory holding that stage's ``part_NNN.fa``
    files. Returns a list of mismatch descriptions; empty means every file
    the run wrote is reproduced byte for byte.
    """
    problems = []
    for part_number, items in rebuild_by_part(source_records, rows, records_per_part, overlap, min_length, max_length):
        digests = {destination: hashlib.md5() for destination in existing_dirs}
        for destination, record in items:
            if destination in digests:
                digests[destination].update(record.as_fasta().encode())
        for destination, directory in existing_dirs.items():
            existing = Path(directory) / f"{part_name(part_number)}.fa"
            if not existing.exists():
                problems.append(f"{existing} is missing")
            elif md5_of_file(existing) != digests[destination].hexdigest():
                problems.append(f"{existing} differs from the rebuild")
    return problems


def read_labelled_parts(paths: Iterable[str | Path]) -> Iterator[Record]:
    return read_fasta_files(paths)


def read_source(path: str | Path) -> Iterator[Record]:
    with open_text(path) as stream:
        yield from parse_fasta(stream)
