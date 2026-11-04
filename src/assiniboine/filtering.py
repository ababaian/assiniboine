"""Stage 3: keep the records whose length is within bounds.

Two bounds, inclusive, for two different reasons:

* The **floor** (200 nt by default) is a biological filter. Circles shorter
  than that are below the size of any known viroid-like agent and are
  dominated by assembly fragments.
* The **ceiling** (6,000 nt by default) is a workaround for the folding
  tool. ``RNAfold`` does not skip a sequence that exceeds its addressable
  range; it prints a warning, emits nothing further and exits 0, so every
  record after it in a batch would be silently lost.

Nothing is deleted. Out-of-range records are written to their own files so
either bound can be revisited without re-running the earlier stages.

Lengths are measured after stage 2 trimmed the overlap, so they are the
lengths of the molecules, not of the assembler's output.
"""

from __future__ import annotations

from collections import Counter
from contextlib import ExitStack
from pathlib import Path

from assiniboine.sequences import open_text, parse_fasta

DEFAULT_MIN_LENGTH = 200
DEFAULT_MAX_LENGTH = 6000

TOO_SHORT = "too_short"
IN_RANGE = "in_range"
TOO_LONG = "too_long"
LENGTH_BINS = (TOO_SHORT, IN_RANGE, TOO_LONG)


def length_bin(length: int, min_length: int = DEFAULT_MIN_LENGTH, max_length: int = DEFAULT_MAX_LENGTH) -> str:
    """Return which bin a sequence of ``length`` falls in. Bounds are inclusive."""
    if length < min_length:
        return TOO_SHORT
    if length > max_length:
        return TOO_LONG
    return IN_RANGE


def split_by_length(
    input_path: str | Path,
    output_paths: dict[str, str | Path],
    min_length: int = DEFAULT_MIN_LENGTH,
    max_length: int = DEFAULT_MAX_LENGTH,
) -> Counter:
    """Write each record of ``input_path`` to the file for its length bin.

    ``output_paths`` maps each of :data:`LENGTH_BINS` to a file path. All three
    files are created, even when empty, so later stages can rely on them.
    Returns the count per bin.
    """
    missing = set(LENGTH_BINS) - set(output_paths)
    if missing:
        raise ValueError(f"no output path for bins: {sorted(missing)}")

    counts: Counter = Counter({name: 0 for name in LENGTH_BINS})
    with ExitStack() as stack:
        outputs = {name: stack.enter_context(open_text(path, "w")) for name, path in output_paths.items()}
        input_stream = stack.enter_context(open_text(input_path))
        for record in parse_fasta(input_stream):
            name = length_bin(len(record.sequence), min_length, max_length)
            outputs[name].write(record.as_fasta())
            counts[name] += 1
    return counts
