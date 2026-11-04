import pytest

from assiniboine.filtering import IN_RANGE, LENGTH_BINS, TOO_LONG, TOO_SHORT, length_bin, split_by_length
from assiniboine.sequences import Record, read_fasta
from conftest import write_fasta


@pytest.mark.parametrize(
    "length, expected",
    [(199, TOO_SHORT), (200, IN_RANGE), (3000, IN_RANGE), (6000, IN_RANGE), (6001, TOO_LONG)],
)
def test_bounds_are_inclusive(length, expected):
    assert length_bin(length) == expected


def test_bounds_are_parameters():
    assert length_bin(50, min_length=10, max_length=40) == TOO_LONG
    assert length_bin(50, min_length=50, max_length=50) == IN_RANGE


def test_split_writes_every_record_to_exactly_one_file(tmp_path):
    records = [Record("short", "A" * 100), Record("ok", "A" * 500), Record("long", "A" * 7000), Record("ok2", "A" * 200)]
    source = write_fasta(tmp_path / "in.fa", records)
    outputs = {name: tmp_path / f"{name}.fa" for name in LENGTH_BINS}
    counts = split_by_length(source, outputs)
    assert counts == {TOO_SHORT: 1, IN_RANGE: 2, TOO_LONG: 1}
    assert [r.header for r in read_fasta(outputs[IN_RANGE])] == ["ok", "ok2"]
    assert [r.header for r in read_fasta(outputs[TOO_SHORT])] == ["short"]
    assert [r.header for r in read_fasta(outputs[TOO_LONG])] == ["long"]


def test_split_creates_empty_files_for_empty_bins(tmp_path):
    source = write_fasta(tmp_path / "in.fa", [Record("ok", "A" * 500)])
    outputs = {name: tmp_path / f"{name}.fa" for name in LENGTH_BINS}
    split_by_length(source, outputs)
    assert outputs[TOO_SHORT].read_text() == ""
    assert outputs[TOO_LONG].read_text() == ""


def test_split_requires_a_path_for_every_bin(tmp_path):
    with pytest.raises(ValueError):
        split_by_length(tmp_path / "in.fa", {IN_RANGE: tmp_path / "x.fa"})
