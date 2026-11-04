#!/usr/bin/env python3
"""Make small synthetic inputs so the pipeline can be run without the real data.

Three kinds of file can be made, each imitating the shape of a real one:

source
    a selfloops archive: circular records carrying the 30 nt terminal overlap,
    hairpin records whose terminal 30-mer is its own reverse complement, and a
    few unmatched ones, with lengths spread across the stage 3 bins
stage1
    what stage 1 would have written for a source: per-record Kraken2 calls and
    the unclassified FASTA, with a chosen fraction marked classified
screen
    what the external classifier would have written for a chunk: a CSV with
    the screen's 48 columns and random feature values

The values are random and mean nothing biologically. They exist so every
later stage has something of the right shape to work on. Usage::

    make_example_data.py source  OUT.fa.zst --records 5000 --seed 1
    make_example_data.py stage1  SOURCE.fa.zst OUT_DIR --records-per-part 1000
    make_example_data.py screen  CHUNK.fa OUT.csv
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
from pathlib import Path

from assiniboine.sequences import Record, open_text, read_fasta, reverse_complement
from assiniboine.topology import DEFAULT_OVERLAP

# The screen's 48 output columns, in the order the classifier writes them.
# Seven ribozyme columns appear twice; stage 5 drops the second copies.
SCREEN_COLUMNS = (
    "sample_name,length,predicted_class,confidence,below_confidence_floor,"
    "gc_content,keto_bias,orf_density_100aa_per_kb,orf_density_30aa_per_kb,mfe_per_nt,frac_paired,"
    "hairpin_density,n_stems_density,max_stem_len,mean_stem_len,n_multiloops_density,branching_degree,"
    "mean_hairpin_loop_size,n_ribozymes,n_ribozymes_plus,n_ribozymes_minus,n_ambiguous_loci,"
    "n_corroborated_loci,paired,same_family_paired,n_hammerhead,n_hairpin,n_hdv,n_varkud_satellite,"
    "n_glms,n_twister,n_twister_sister,n_pistol,n_hatchet,n_dvr5,n_other,tandem_repeat_flag,"
    "n_ribozymes,n_ribozymes_plus,n_ribozymes_minus,n_ambiguous_loci,n_corroborated_loci,paired,"
    "same_family_paired,ribozyme_families,strands_present,sources_detected,combination_detail"
).split(",")


def random_sequence(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def circular_record(index: int, length: int, rng: random.Random, overlap: int = DEFAULT_OVERLAP) -> Record:
    """A closed circle as Logan writes it: the first ``overlap`` bases repeated at the end."""
    body = random_sequence(length, rng)
    header = f"SRR{rng.randint(1_000_000, 9_999_999)}_{index}_circle_{index} ka:f:{rng.uniform(1, 50):.3f} L:-:{index}:- L:+:{index}:+"
    return Record(header, body + body[:overlap])


def hairpin_record(index: int, length: int, rng: random.Random, overlap: int = DEFAULT_OVERLAP) -> Record:
    """A linear contig capped by an inverted repeat: its last 30-mer is its own reverse complement."""
    half = random_sequence(overlap // 2, rng)
    palindrome = half + reverse_complement(half)
    body = random_sequence(length - len(palindrome), rng)
    link = rng.choice([f"L:+:{index}:-", f"L:-:{index}:+"])
    header = f"ERR{rng.randint(1_000_000, 9_999_999)}_{index}_circle_{index} ka:f:{rng.uniform(1, 50):.3f} {link}"
    return Record(header, body + palindrome)


def unmatched_record(index: int, length: int, rng: random.Random) -> Record:
    """Links say circular but the ends do not match."""
    header = f"DRR{rng.randint(1_000_000, 9_999_999)}_{index}_circle_{index} ka:f:{rng.uniform(1, 50):.3f} L:-:{index}:- L:+:{index}:+"
    return Record(header, random_sequence(length, rng))


def random_length(rng: random.Random) -> int:
    """Mostly short, some in range, a few too long, like the real archive."""
    draw = rng.random()
    if draw < 0.55:
        return rng.randint(60, 199)
    if draw < 0.97:
        return rng.randint(200, 2000)
    return rng.randint(6001, 8000)


def make_source(path: Path, n_records: int, seed: int) -> None:
    rng = random.Random(seed)
    with open_text(path, "w") as stream:
        for index in range(1, n_records + 1):
            draw = rng.random()
            if draw < 0.90:
                record = circular_record(index, random_length(rng), rng)
            elif draw < 0.995:
                record = hairpin_record(index, random_length(rng), rng)
            else:
                record = unmatched_record(index, random_length(rng), rng)
            stream.write(record.as_fasta())


def make_stage1(source: Path, out_dir: Path, records_per_part: int, classified_fraction: float, seed: int) -> None:
    """Imitate stage 1: cut the source into parts, mark some records classified."""
    rng = random.Random(seed)
    for name in ("unclassified", "calls", "counts", "reports", "logs"):
        (out_dir / name).mkdir(parents=True, exist_ok=True)

    records = list(read_fasta(source))
    for part_number, start in enumerate(range(0, len(records), records_per_part)):
        name = f"part_{part_number:03d}"
        counts = {"classified": 0, "unclassified": 0}
        with open_text(out_dir / "calls" / f"{name}.tsv.zst", "w") as calls, open(out_dir / "unclassified" / f"{name}.fa", "w") as kept:
            for record in records[start : start + records_per_part]:
                if rng.random() < classified_fraction:
                    calls.write(f"C\t{record.id}\t{rng.choice([9606, 10090, 3702, 562])}\t{len(record.sequence)}\n")
                    counts["classified"] += 1
                else:
                    calls.write(f"U\t{record.id}\t0\t{len(record.sequence)}\n")
                    kept.write(record.as_fasta())
                    counts["unclassified"] += 1
        with open(out_dir / "counts" / f"{name}.tsv", "w") as stream:
            for label, count in counts.items():
                stream.write(f"{label}\t{count}\n")
        (out_dir / "reports" / f"{name}.txt").write_text("synthetic data: no Kraken2 report\n")
        (out_dir / "logs" / f"{name}.done").touch()


def strands_label(n_plus: int, n_minus: int) -> str:
    """The classifier's strands_present value for a count of loci per strand."""
    if n_plus and n_minus:
        return "+;-"
    if n_plus:
        return "+"
    if n_minus:
        return "-"
    return "NONE"


def fake_screen_row(record: Record, rng: random.Random) -> list[str]:
    """One row of the screen's CSV with random but well-formed values."""
    length = len(record.sequence)
    is_rod = rng.random() < 0.3
    confidence = rng.uniform(0.5, 1.0)
    n_plus = rng.choice([0, 0, 0, 1, 2]) if is_rod else 0
    n_minus = rng.choice([0, 0, 1]) if is_rod else 0
    n_ribozymes = n_plus + n_minus
    corroborated = rng.choice([0, 0, 0, 1]) if n_ribozymes else 0
    strands = strands_label(n_plus, n_minus)
    families = "hammerhead" if n_ribozymes else "NONE"
    ribozyme_block = [n_ribozymes, n_plus, n_minus, 0, corroborated, bool(n_plus and n_minus), False]

    row = [
        record.id, length, "rod" if is_rod else "not_rod", f"{confidence:.4f}", False,
        f"{rng.uniform(30, 60):.3f}", f"{rng.uniform(40, 60):.3f}", f"{rng.uniform(0, 2):.4f}", f"{rng.uniform(0, 5):.4f}",
        f"{rng.uniform(-0.5, -0.1):.4f}", f"{rng.uniform(0.4, 0.8):.4f}", f"{rng.uniform(0.5, 3):.4f}",
        f"{rng.uniform(2, 8):.4f}", rng.randint(5, 20), f"{rng.uniform(3, 8):.4f}", f"{rng.uniform(0, 1):.4f}",
        f"{rng.uniform(1, 3):.4f}", f"{rng.uniform(3, 8):.4f}",
        *ribozyme_block,
        n_ribozymes, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  # n_hammerhead, then the other families
        False,
        *ribozyme_block,
        families, strands, "Rfam" if n_ribozymes else "NONE",
        "hammerhead(+):10-60[score=30.0,E=1.0e-05,source=Rfam]" if n_ribozymes else "NONE",
    ]
    assert len(row) == len(SCREEN_COLUMNS)
    return [str(value) for value in row]


def make_screen(chunk: Path, out_csv: Path, seed: int) -> None:
    rng = random.Random(seed)
    with open(out_csv, "w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(SCREEN_COLUMNS)
        for record in read_fasta(chunk):
            writer.writerow(fake_screen_row(record, rng))


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="kind", required=True)

    p = commands.add_parser("source", help="a synthetic selfloops archive")
    p.add_argument("output", type=Path)
    p.add_argument("--records", type=int, default=5000)
    p.add_argument("--seed", type=int, default=1)

    p = commands.add_parser("stage1", help="stage 1 outputs for a source, without Kraken2")
    p.add_argument("source", type=Path)
    p.add_argument("out_dir", type=Path)
    p.add_argument("--records-per-part", type=int, default=1000)
    p.add_argument("--classified-fraction", type=float, default=0.3)
    p.add_argument("--seed", type=int, default=1)

    p = commands.add_parser("screen", help="a screen result CSV for a chunk, without the classifier")
    p.add_argument("chunk", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--seed", type=int, default=1)

    args = parser.parse_args(argv)
    if args.kind == "source":
        make_source(args.output, args.records, args.seed)
    elif args.kind == "stage1":
        make_stage1(args.source, args.out_dir, args.records_per_part, args.classified_fraction, args.seed)
    else:
        make_screen(args.chunk, args.output, args.seed)
    print(f"wrote {args.output if args.kind != 'stage1' else args.out_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
