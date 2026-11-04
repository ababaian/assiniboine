"""Shared fixtures: small synthetic inputs built with scripts/ops/make_example_data.py."""

import random
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ops"))

import make_example_data  # noqa: E402  (needs the path above)

from assiniboine.sequences import Record  # noqa: E402


@pytest.fixture
def rng():
    return random.Random(7)


@pytest.fixture
def circular(rng) -> Record:
    """A 300 nt circle written with its 30 nt overlap, so 330 nt on disk."""
    return make_example_data.circular_record(1, 300, rng)


@pytest.fixture
def hairpin(rng) -> Record:
    return make_example_data.hairpin_record(2, 400, rng)


@pytest.fixture
def unmatched(rng) -> Record:
    return make_example_data.unmatched_record(3, 250, rng)


@pytest.fixture
def source_fasta(tmp_path) -> Path:
    """A synthetic archive of 600 records, compressed like the real one."""
    path = tmp_path / "source.fa.zst"
    make_example_data.make_source(path, 600, seed=3)
    return path


@pytest.fixture
def stage1_dir(tmp_path, source_fasta) -> Path:
    """Stage 1 outputs for ``source_fasta``: 3 parts of 200 records."""
    out = tmp_path / "01_kraken_filter"
    make_example_data.make_stage1(source_fasta, out, records_per_part=200, classified_fraction=0.3, seed=3)
    return out


def write_fasta(path: Path, records) -> Path:
    path.write_text("".join(record.as_fasta() for record in records))
    return path
