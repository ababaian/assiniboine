#!/usr/bin/env python3
"""Length distribution of one or more FASTA files, in the bins the stage 3 bounds fall in.

Usage::

    scripts/length_histogram.py work/02_circular_overlap/labelled/part_*.fa

Prints the record count, total and mean length, the longest record, and the
share of records in each length band. Run it on stage 2's output to see
what the stage 3 floor and ceiling will do before running stage 3.
"""

from __future__ import annotations

import argparse
from collections import Counter

from assiniboine.sequences import read_fasta_files

BAND_EDGES = (200, 500, 1000, 2000, 6000, 10000, 20000)


def band_label(length: int) -> str:
    lower = 1
    for edge in BAND_EDGES:
        if length < edge:
            return f"{lower}-{edge - 1}"
        lower = edge
    return f">={lower}"


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("fasta", nargs="+")
    args = parser.parse_args(argv)

    bands: Counter = Counter()
    records = 0
    total_length = 0
    longest = 0
    for record in read_fasta_files(args.fasta):
        length = len(record.sequence)
        records += 1
        total_length += length
        longest = max(longest, length)
        bands[band_label(length)] += 1

    if records == 0:
        print("no records")
        return
    print(f"records      {records:,}")
    print(f"total nt     {total_length:,}")
    print(f"mean length  {total_length / records:.1f}")
    print(f"longest      {longest:,}\n")
    print(f"  {'band (nt)':<12} {'records':>14} {'%':>8}")
    labels = [band_label(edge - 1) for edge in BAND_EDGES] + [band_label(BAND_EDGES[-1])]
    for label in labels:
        print(f"  {label:<12} {bands[label]:>14,} {100 * bands[label] / records:>7.2f}%")


if __name__ == "__main__":
    main()
