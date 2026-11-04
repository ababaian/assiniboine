"""The ``assiniboine`` command line.

Each subcommand does one unit of work on one file (or one set of files), so
the workflow scripts can run many of them in parallel with ``xargs``. Run
``assiniboine --help`` for the list, or ``assiniboine <command> --help`` for
one command's options.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from assiniboine import __version__, config, dotbracket, filtering, manifest, results, topology, validation
from assiniboine.sequences import sorted_files

# Any of these means "a check failed" rather than "the program crashed".
EXPECTED_ERRORS = (
    config.ConfigError,
    validation.ValidationError,
    results.ResultsError,
    manifest.ManifestError,
    dotbracket.DotBracketError,
    FileNotFoundError,
    ValueError,
    RuntimeError,
)


# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------


def cmd_config(args: argparse.Namespace) -> None:
    settings = config.load_config(args.run)
    if args.action == "export":
        sys.stdout.write(config.to_shell(settings))
    else:
        sys.stdout.write(config.to_text(settings))


# ---------------------------------------------------------------------------
# stage 2 and 3
# ---------------------------------------------------------------------------


def cmd_label_overlap(args: argparse.Namespace) -> None:
    counts = topology.label_file(args.input, args.output, args.overlap)
    if args.counts:
        validation.write_counts(args.counts, counts)
    sys.stderr.write(f"{args.input}: " + ", ".join(f"{name}={count}" for name, count in counts.items()) + "\n")


def cmd_length_filter(args: argparse.Namespace) -> None:
    out_dir = Path(args.out_dir)
    output_paths = {}
    for name in filtering.LENGTH_BINS:
        (out_dir / name).mkdir(parents=True, exist_ok=True)
        output_paths[name] = out_dir / name / f"{args.name}.fa"
    counts = filtering.split_by_length(args.input, output_paths, args.min_length, args.max_length)
    if args.counts:
        validation.write_counts(args.counts, counts)
    sys.stderr.write(f"{args.input}: " + ", ".join(f"{name}={count}" for name, count in counts.items()) + "\n")


def cmd_sum_counts(args: argparse.Namespace) -> None:
    sys.stdout.write(validation.format_counts(validation.sum_counts(args.files)))


# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------


def cmd_validate_fasta(args: argparse.Namespace) -> None:
    for path in args.files:
        records = validation.check_two_line_fasta(path)
        print(f"{path}\t{records}")


def cmd_validate_screen(args: argparse.Namespace) -> None:
    records = validation.check_screen_output(args.chunk, args.csv)
    print(f"{args.csv}: {records} rows, one per record")


# ---------------------------------------------------------------------------
# stage 5
# ---------------------------------------------------------------------------


def cmd_results(args: argparse.Namespace) -> None:
    pairs = results.pair_chunks_with_results(args.chunks_dir, args.results_dir)
    counts = results.reduce_screen(pairs, args.out_dir, args.tier2_min_confidence, args.tier2_max_rows)
    summary = results.format_summary(counts)
    Path(args.out_dir, "summary.txt").write_text(summary)
    sys.stdout.write(summary)


# ---------------------------------------------------------------------------
# stage 6
# ---------------------------------------------------------------------------


def cmd_manifest_build(args: argparse.Namespace) -> None:
    rows = manifest.build_rows(
        manifest.read_source(args.source),
        manifest.read_kraken_calls(sorted_files(args.calls_dir, "part_*.tsv*")),
        manifest.read_labelled_parts(sorted_files(args.labelled_dir, "part_*.fa")),
        args.overlap,
        args.min_length,
        args.max_length,
    )
    counts = manifest.write_manifest(rows, args.output)
    for group, group_counts in counts.items():
        sys.stdout.write(f"by {group}\n" + validation.format_counts(group_counts) + "\n")


def cmd_manifest_rebuild(args: argparse.Namespace) -> None:
    parts = manifest.write_rebuilt_files(
        manifest.read_source(args.source),
        manifest.read_manifest(args.manifest),
        args.out_dir,
        args.records_per_part,
        args.overlap,
        args.min_length,
        args.max_length,
    )
    print(f"rebuilt {parts} parts under {args.out_dir}")


def cmd_manifest_verify(args: argparse.Namespace) -> None:
    existing_dirs = {
        manifest.UNCLASSIFIED: args.unclassified_dir,
        manifest.LABELLED: args.labelled_dir,
    }
    for name in filtering.LENGTH_BINS:
        existing_dirs[name] = Path(args.length_dir) / name
    problems = manifest.verify_rebuild(
        manifest.read_source(args.source),
        manifest.read_manifest(args.manifest),
        existing_dirs,
        args.records_per_part,
        args.overlap,
        args.min_length,
        args.max_length,
    )
    if problems:
        sys.exit("the manifest does not rebuild the run's files:\n  " + "\n  ".join(problems))
    print("every stage 1 to 3 file is rebuilt byte for byte from the source and the manifest")


# ---------------------------------------------------------------------------
# stage 7
# ---------------------------------------------------------------------------


def cmd_dotbracket_split(args: argparse.Namespace) -> None:
    rods = dotbracket.split_rods(args.rods, args.parts_dir, args.parts)
    print(f"{rods} rods dealt into {args.parts} parts under {args.parts_dir}")


def cmd_dotbracket_parse(args: argparse.Namespace) -> None:
    rods = dotbracket.parse_part(args.fold_output, args.output, args.expected)
    print(f"{args.output}: {rods} structures")


def cmd_dotbracket_collect(args: argparse.Namespace) -> None:
    rods = dotbracket.collect_parts(args.parts, args.output, args.expected)
    print(f"{args.output}: {rods} structures, in rods.csv order")


# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------


def add_method_arguments(parser: argparse.ArgumentParser) -> None:
    """The three stage 2 and 3 parameters the manifest needs to replay them."""
    parser.add_argument("--overlap", type=int, default=topology.DEFAULT_OVERLAP, help="overlap trimmed from circular records")
    parser.add_argument("--min-length", type=int, default=filtering.DEFAULT_MIN_LENGTH, help="stage 3 floor, inclusive")
    parser.add_argument("--max-length", type=int, default=filtering.DEFAULT_MAX_LENGTH, help="stage 3 ceiling, inclusive")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="assiniboine", description=__doc__.split("\n\n")[0])
    parser.add_argument("--version", action="version", version=f"assiniboine {__version__}")
    commands = parser.add_subparsers(dest="command", required=True, metavar="<command>")

    # config
    p = commands.add_parser("config", help="show the settings, or export them for the shell")
    p.add_argument("action", choices=["show", "export"])
    p.add_argument("--run", help="a run file that overrides config/defaults.toml (default: $ASSINIBOINE_CONFIG)")
    p.set_defaults(func=cmd_config)

    # stage 2
    p = commands.add_parser("label-overlap", help="stage 2: label how each record closes and trim the overlap")
    p.add_argument("input", help="FASTA file (plain, .gz, .zst or - for stdin)")
    p.add_argument("output", help="labelled FASTA file to write")
    p.add_argument("--overlap", type=int, default=topology.DEFAULT_OVERLAP, help="overlap length in nt (default %(default)s)")
    p.add_argument("--counts", help="write label<TAB>count lines to this file")
    p.set_defaults(func=cmd_label_overlap)

    # stage 3
    p = commands.add_parser("length-filter", help="stage 3: file each record by length")
    p.add_argument("input", help="labelled FASTA file")
    p.add_argument("--out-dir", required=True, help="directory that gets too_short/, in_range/ and too_long/")
    p.add_argument("--name", required=True, help="base name of the output files, e.g. part_000")
    p.add_argument("--min-length", type=int, default=filtering.DEFAULT_MIN_LENGTH, help="floor, inclusive (default %(default)s)")
    p.add_argument("--max-length", type=int, default=filtering.DEFAULT_MAX_LENGTH, help="ceiling, inclusive (default %(default)s)")
    p.add_argument("--counts", help="write label<TAB>count lines to this file")
    p.set_defaults(func=cmd_length_filter)

    p = commands.add_parser("sum-counts", help="add up per-part count files into one summary table")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_sum_counts)

    # validate
    p = commands.add_parser("validate", help="check a hand-off between stages")
    checks = p.add_subparsers(dest="check", required=True, metavar="<check>")
    q = checks.add_parser("fasta", help="every record is exactly two lines")
    q.add_argument("files", nargs="+")
    q.set_defaults(func=cmd_validate_fasta)
    q = checks.add_parser("screen", help="a screen result has one row per record of its chunk")
    q.add_argument("chunk", help="chunk FASTA")
    q.add_argument("csv", help="the screen's result CSV for that chunk")
    q.set_defaults(func=cmd_validate_screen)

    # stage 5
    p = commands.add_parser("results", help="stage 5: reduce the screen output to the rod tables")
    p.add_argument("--chunks-dir", required=True, help="directory of chunk_NNN.fa files")
    p.add_argument("--results-dir", required=True, help="directory of chunk_NNN.csv files")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--tier2-min-confidence", type=float, default=results.DEFAULT_TIER2_MIN_CONFIDENCE)
    p.add_argument("--tier2-max-rows", type=int, default=results.DEFAULT_TIER2_MAX_ROWS)
    p.set_defaults(func=cmd_results)

    # stage 6
    p = commands.add_parser("manifest", help="stage 6: the record manifest and the rebuild it allows")
    actions = p.add_subparsers(dest="action", required=True, metavar="<action>")
    q = actions.add_parser("build", help="write one row per source record from the stage 1 and 2 outputs")
    q.add_argument("--source", required=True, help="the source archive (.zst is fine)")
    q.add_argument("--calls-dir", required=True, help="stage 1 calls/ directory")
    q.add_argument("--labelled-dir", required=True, help="stage 2 labelled/ directory")
    q.add_argument("--output", required=True, help="manifest TSV to write (.zst is fine)")
    add_method_arguments(q)
    q.set_defaults(func=cmd_manifest_build)
    q = actions.add_parser("rebuild", help="write the stage 1 to 3 files from the source and the manifest")
    q.add_argument("--source", required=True)
    q.add_argument("--manifest", required=True)
    q.add_argument("--out-dir", required=True)
    q.add_argument("--records-per-part", type=int, required=True, help="the stage 1 part size")
    add_method_arguments(q)
    q.set_defaults(func=cmd_manifest_rebuild)
    q = actions.add_parser("verify", help="check that the rebuild matches a run's files, without writing")
    q.add_argument("--source", required=True)
    q.add_argument("--manifest", required=True)
    q.add_argument("--unclassified-dir", required=True, help="stage 1 unclassified/ directory")
    q.add_argument("--labelled-dir", required=True, help="stage 2 labelled/ directory")
    q.add_argument("--length-dir", required=True, help="stage 3 directory holding too_short/, in_range/, too_long/")
    q.add_argument("--records-per-part", type=int, required=True)
    add_method_arguments(q)
    q.set_defaults(func=cmd_manifest_verify)

    # stage 7
    p = commands.add_parser("dotbracket", help="stage 7: refold the rods and keep their structures")
    actions = p.add_subparsers(dest="action", required=True, metavar="<action>")
    q = actions.add_parser("split", help="deal the rods into balanced FASTA parts for RNAfold")
    q.add_argument("rods", help="stage 5 rods.csv")
    q.add_argument("parts_dir")
    q.add_argument("--parts", type=int, required=True, help="how many parts to write")
    q.set_defaults(func=cmd_dotbracket_split)
    q = actions.add_parser("parse", help="turn one part's RNAfold output into a checked TSV")
    q.add_argument("fold_output", help="what RNAfold printed for one part")
    q.add_argument("output", help="TSV to write")
    q.add_argument("--expected", type=int, help="number of rods in the part")
    q.set_defaults(func=cmd_dotbracket_parse)
    q = actions.add_parser("collect", help="merge the part TSVs back into rods.csv order")
    q.add_argument("parts", nargs="+", help="the parsed part TSVs")
    q.add_argument("--output", required=True, help="final TSV (.zst is fine)")
    q.add_argument("--expected", type=int, help="total number of rods")
    q.set_defaults(func=cmd_dotbracket_collect)

    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    try:
        args.func(args)
    except EXPECTED_ERRORS as error:
        sys.exit(f"error: {error}")


if __name__ == "__main__":
    main()
