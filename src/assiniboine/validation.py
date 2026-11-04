"""Checks that guard the hand-offs between stages.

Each check raises :class:`ValidationError` with a message that says what was
found and what was expected, so a failing stage stops with a reason rather
than passing a broken file downstream.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Iterable

from assiniboine.sequences import open_text


class ValidationError(Exception):
    """A file does not have the shape the next stage relies on."""


def check_two_line_fasta(path: str | Path) -> int:
    """Check that a FASTA file alternates header and sequence lines.

    Returns the number of records. Stage 4 shards its input with ``split``
    on a fixed line count, which is only safe when every record is exactly
    two lines.
    """
    line_count = 0
    with open_text(path) as stream:
        for line_count, line in enumerate(stream, start=1):
            is_header_line = line.startswith(">")
            expect_header = line_count % 2 == 1
            if is_header_line != expect_header:
                expected = "a header" if expect_header else "a sequence"
                raise ValidationError(f"{path}: line {line_count} should be {expected}; the file is not two lines per record")
    if line_count % 2 != 0:
        raise ValidationError(f"{path}: {line_count} lines is odd; the last record has no sequence line")
    return line_count // 2


def check_screen_output(chunk_fasta: str | Path, result_csv: str | Path) -> int:
    """Check that the rod screen wrote exactly one row per input record.

    This equality is the only thing that catches ``RNAfold`` stopping early on
    an oversized sequence: it exits 0 having emitted nothing further, and the
    screen reports success. Returns the number of records.
    """
    result_csv = Path(result_csv)
    if not result_csv.exists():
        raise ValidationError(f"{result_csv} was not written")

    records = 0
    with open_text(chunk_fasta) as stream:
        records = sum(1 for line in stream if line.startswith(">"))
    with open(result_csv) as stream:
        rows = sum(1 for _ in stream) - 1  # minus the header line

    if rows != records:
        raise ValidationError(
            f"{result_csv} has {rows} rows for {records} records in {chunk_fasta}; the screen output is truncated or duplicated"
        )
    return records


def sum_counts(paths: Iterable[str | Path]) -> Counter:
    """Add up the ``label<TAB>count`` files that stages write per part."""
    totals: Counter = Counter()
    for path in paths:
        with open(path) as stream:
            for line in stream:
                if not line.strip():
                    continue
                label, count = line.rstrip("\n").split("\t")
                totals[label] += int(count)
    return totals


def write_counts(path: str | Path, counts: Counter) -> None:
    """Write a ``label<TAB>count`` file in a stable order."""
    with open(path, "w") as stream:
        for label in counts:
            stream.write(f"{label}\t{counts[label]}\n")


def format_counts(counts: Counter) -> str:
    """Render counts as a small table with the share of the total."""
    total = sum(counts.values())
    width = max([len("label")] + [len(label) for label in counts])
    lines = [f"{'label':<{width}}  {'count':>14}  {'percent':>7}"]
    for label, count in counts.items():
        share = 100 * count / total if total else 0.0
        lines.append(f"{label:<{width}}  {count:>14,}  {share:>7.2f}")
    lines.append(f"{'total':<{width}}  {total:>14,}  {100.0 if total else 0.0:>7.2f}")
    return "\n".join(lines) + "\n"
