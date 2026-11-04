"""Stage 5: reduce the screen output to the rod tables and the shortlist.

Stage 4 writes one CSV per chunk with one row per screened record, in the
order of the chunk's FASTA. Reading the two side by side attaches each
record's sequence and closure class to its row without holding anything in
memory, and lets the ids be compared record by record as a check.

Three tables come out:

rods.csv
    every record the classifier called ``rod``, with its sequence
rods_with_ribozyme.csv
    the rods that carry at least one ribozyme hit
shortlist.csv
    ranked candidates in two tiers, both keyed on ribozymes on both strands,
    the hallmark of rolling-circle replication:

    * tier 1: ribozymes on both strands and at least one corroborated locus,
      where independent covariance models agree on the same site. Taken in
      full.
    * tier 2: both strands, no corroboration, confidence at or above a floor,
      ranked by confidence and cut to a fixed number of rows. The cut can
      fall inside a run of tied confidences, so which tied rows are kept is
      arbitrary; the summary reports how many qualifying rows were cut.

The screen's header names seven ribozyme columns twice. Every row is checked
to carry the same value in both copies, and the second copy is dropped.
"""

from __future__ import annotations

import csv
from itertools import zip_longest
from pathlib import Path
from typing import Iterator

from assiniboine.sequences import Record, read_fasta
from assiniboine.topology import parse_label

DEFAULT_TIER2_MIN_CONFIDENCE = 0.8
DEFAULT_TIER2_MAX_ROWS = 2000

ROD = "rod"
BOTH_STRANDS = "+;-"
ADDED_COLUMNS = ("run", "closure")


class ResultsError(Exception):
    """A screen result file does not line up with its chunk."""


def unique_columns(header: list[str]) -> tuple[list[int], list[tuple[int, int]]]:
    """Split a header into the indices to keep and the duplicate pairs to check.

    Returns ``(keep, duplicates)``: ``keep`` lists the index of the first
    occurrence of each name, and ``duplicates`` lists ``(first, repeat)`` index
    pairs for every repeated name.
    """
    first_index: dict[str, int] = {}
    keep: list[int] = []
    duplicates: list[tuple[int, int]] = []
    for index, name in enumerate(header):
        if name in first_index:
            duplicates.append((first_index[name], index))
        else:
            first_index[name] = index
            keep.append(index)
    return keep, duplicates


def read_screened(chunk_fasta: str | Path, result_csv: str | Path) -> Iterator[tuple[Record, dict[str, str]]]:
    """Yield ``(record, row)`` pairs for one chunk, row as a dict of unique columns."""
    with open(result_csv, newline="") as stream:
        reader = csv.reader(stream)
        header = next(reader, None)
        if header is None:
            raise ResultsError(f"{result_csv} is empty")
        keep, duplicates = unique_columns(header)
        names = [header[index] for index in keep]
        sample_column = header.index("sample_name")

        for record, row in zip_longest(read_fasta(chunk_fasta), reader):
            if record is None or row is None:
                raise ResultsError(f"{result_csv} and {chunk_fasta} do not have the same number of records")
            if row[sample_column] != record.id:
                raise ResultsError(
                    f"{result_csv} row for {row[sample_column]} does not line up with record {record.id} in {chunk_fasta}"
                )
            for first, repeat in duplicates:
                if row[first] != row[repeat]:
                    raise ResultsError(
                        f"{result_csv}: column {header[first]!r} differs between its two copies for {record.id}"
                    )
            yield record, dict(zip(names, (row[index] for index in keep)))


def rod_table_row(record: Record, screen_row: dict[str, str]) -> dict[str, str]:
    """Build an output row: id, run, closure, the screen's columns, sequence."""
    closure, _ = parse_label(record.header)
    row = {"sample_name": record.id, "run": record.run_accession, "closure": closure}
    for name, value in screen_row.items():
        if name != "sample_name":
            row[name] = value
    row["sequence"] = record.sequence
    return row


def has_ribozyme(row: dict[str, str]) -> bool:
    return int(row["n_ribozymes"]) >= 1


def has_ribozymes_on_both_strands(row: dict[str, str]) -> bool:
    return row["strands_present"] == BOTH_STRANDS


def is_corroborated(row: dict[str, str]) -> bool:
    return int(row["n_corroborated_loci"]) > 0


def build_shortlist(
    rows: list[dict[str, str]],
    tier2_min_confidence: float = DEFAULT_TIER2_MIN_CONFIDENCE,
    tier2_max_rows: int = DEFAULT_TIER2_MAX_ROWS,
) -> tuple[list[dict[str, str]], dict[str, int | float]]:
    """Rank the rod rows into the two shortlist tiers.

    Returns the shortlist rows, each with a ``tier`` entry, and the counts
    that describe how the tiers were formed.
    """
    both_strands = [row for row in rows if has_ribozymes_on_both_strands(row)]
    tier1 = [row for row in both_strands if is_corroborated(row)]
    tier2_pool = [
        row for row in both_strands if not is_corroborated(row) and float(row["confidence"]) >= tier2_min_confidence
    ]
    tier2_pool.sort(key=lambda row: float(row["confidence"]), reverse=True)
    tier2 = tier2_pool[:tier2_max_rows]

    shortlist = [{"tier": "1", **row} for row in tier1] + [{"tier": "2", **row} for row in tier2]
    counts = {
        "both_strands": len(both_strands),
        "tier1": len(tier1),
        "tier2_pool": len(tier2_pool),
        "tier2_kept": len(tier2),
        "tier2_cut": len(tier2_pool) - len(tier2),
        "tier2_lowest_confidence": float(tier2[-1]["confidence"]) if tier2 else 0.0,
    }
    return shortlist, counts


def write_table(path: str | Path, rows: list[dict[str, str]], columns: list[str]) -> None:
    with open(path, "w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def reduce_screen(
    chunk_pairs: list[tuple[Path, Path]],
    out_dir: str | Path,
    tier2_min_confidence: float = DEFAULT_TIER2_MIN_CONFIDENCE,
    tier2_max_rows: int = DEFAULT_TIER2_MAX_ROWS,
) -> dict[str, int | float]:
    """Write the three result tables from ``(chunk_fasta, result_csv)`` pairs.

    ``rods.csv`` is streamed straight to disk. The rods carrying a ribozyme
    are a small fraction, so they are kept in memory for the other two tables.
    Returns the summary counts.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    columns: list[str] = []
    with_ribozyme: list[dict[str, str]] = []
    screened = 0
    rods = 0

    with open(out_dir / "rods.csv", "w", newline="") as rods_stream:
        writer = None
        for chunk_fasta, result_csv in chunk_pairs:
            for record, screen_row in read_screened(chunk_fasta, result_csv):
                screened += 1
                if screen_row["predicted_class"] != ROD:
                    continue
                row = rod_table_row(record, screen_row)
                if writer is None:
                    columns = list(row)
                    writer = csv.DictWriter(rods_stream, fieldnames=columns)
                    writer.writeheader()
                writer.writerow(row)
                rods += 1
                if has_ribozyme(row):
                    with_ribozyme.append(row)

    if writer is None:
        raise ResultsError("no rod was called in any chunk; nothing to reduce")

    write_table(out_dir / "rods_with_ribozyme.csv", with_ribozyme, columns)
    shortlist, counts = build_shortlist(with_ribozyme, tier2_min_confidence, tier2_max_rows)
    write_table(out_dir / "shortlist.csv", shortlist, ["tier"] + columns)

    return {"screened": screened, "rod": rods, "rod_with_ribozyme": len(with_ribozyme), **counts}


def format_summary(counts: dict[str, int | float]) -> str:
    """Render the stage 5 counts for ``summary.txt``."""
    lines = [
        f"screened                 {counts['screened']:>14,}",
        f"rod                      {counts['rod']:>14,}",
        f"rod with ribozyme        {counts['rod_with_ribozyme']:>14,}",
        f"ribozymes on both strands{counts['both_strands']:>14,}",
        f"shortlist tier 1         {counts['tier1']:>14,}   corroborated, taken in full",
        f"shortlist tier 2 pool    {counts['tier2_pool']:>14,}",
        f"shortlist tier 2 kept    {counts['tier2_kept']:>14,}   lowest confidence kept {counts['tier2_lowest_confidence']:.3f}",
        f"shortlist tier 2 cut     {counts['tier2_cut']:>14,}   qualify but fall below the row cap",
    ]
    return "\n".join(lines) + "\n"


def pair_chunks_with_results(chunks_dir: str | Path, results_dir: str | Path) -> list[tuple[Path, Path]]:
    """Match ``chunk_NNN.fa`` with ``chunk_NNN.csv``; every chunk must have a result."""
    pairs = []
    for chunk in sorted(Path(chunks_dir).glob("chunk_*.fa")):
        result = Path(results_dir) / (chunk.stem + ".csv")
        if not result.exists():
            raise ResultsError(f"no screen result for {chunk.name}: expected {result}")
        pairs.append((chunk, result))
    if not pairs:
        raise ResultsError(f"no chunk_*.fa files in {chunks_dir}")
    return pairs
