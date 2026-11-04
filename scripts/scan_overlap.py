#!/usr/bin/env python3
"""Measure the terminal overlap in a selfloops FASTA, and check the closure classes.

This is the measurement behind two decisions in stage 2: that the overlap
Logan writes into circular records is exactly 30 nt, and that the self-link
orientation in the header predicts whether a record's ends match. It prints:

1. for K from 20 to 36, how many records have their first K bases equal to
   their last K bases. A sharp peak at one K is the overlap length.
2. per closure class, as read from the header: how many records there are,
   how many have matching ends, and how many have a terminal 30-mer that is
   its own reverse complement.

Usage::

    scripts/scan_overlap.py SELFLOOPS.fa [--max-records N] [--overlap 30]

Headers must be intact: the ``L:`` link fields are what the classification
reads. Measured on 100,000 records of the real archive, 62.8% matched at
K = 30 and none at any K above it; see docs/methods.md.
"""

from __future__ import annotations

import argparse
from collections import Counter

from assiniboine.sequences import read_fasta, reverse_complement
from assiniboine.topology import DEFAULT_OVERLAP, classify_closure

K_RANGE = range(20, 37)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("fasta")
    parser.add_argument("--max-records", type=int, default=0, help="stop after this many records (0 = all)")
    parser.add_argument("--overlap", type=int, default=DEFAULT_OVERLAP)
    args = parser.parse_args(argv)

    total = 0
    ends_match_at: Counter = Counter()
    per_class: dict[str, Counter] = {}
    total_length: Counter = Counter()

    for record in read_fasta(args.fasta):
        if args.max_records and total >= args.max_records:
            break
        total += 1
        sequence = record.sequence.upper()
        n = len(sequence)

        for k in K_RANGE:
            if n >= 2 * k and sequence[:k] == sequence[-k:]:
                ends_match_at[k] += 1

        closure, _ = classify_closure(record.header, sequence, args.overlap)
        counts = per_class.setdefault(closure, Counter())
        counts["records"] += 1
        total_length[closure] += n
        if n >= 2 * args.overlap:
            head, tail = sequence[: args.overlap], sequence[-args.overlap :]
            counts["ends_match"] += head == tail
            counts["head_is_palindrome"] += head == reverse_complement(head)
            counts["tail_is_palindrome"] += tail == reverse_complement(tail)

    print(f"records examined: {total:,}\n")
    print("K scan: records whose first K bases equal their last K")
    print(f"  {'K':>3} {'matched':>10} {'%':>8}")
    for k in K_RANGE:
        print(f"  {k:>3} {ends_match_at[k]:>10,} {100 * ends_match_at[k] / total:>7.2f}%")

    print(f"\nclosure class by header, checked against the sequence (overlap {args.overlap})")
    print(f"  {'class':<10} {'records':>10} {'share':>8} {'ends match':>11} {'head palin.':>12} {'tail palin.':>12} {'mean nt':>9}")
    for closure, counts in sorted(per_class.items()):
        print(
            f"  {closure:<10} {counts['records']:>10,} {100 * counts['records'] / total:>7.2f}%"
            f" {counts['ends_match']:>11,} {counts['head_is_palindrome']:>12,} {counts['tail_is_palindrome']:>12,}"
            f" {total_length[closure] / counts['records']:>9.1f}"
        )


if __name__ == "__main__":
    main()
