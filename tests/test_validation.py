from collections import Counter

import pytest

from assiniboine.validation import (
    ValidationError,
    check_screen_output,
    check_two_line_fasta,
    format_counts,
    sum_counts,
    write_counts,
)


def test_two_line_fasta_passes_and_counts(tmp_path):
    path = tmp_path / "ok.fa"
    path.write_text(">a\nACGT\n>b\nGG\n")
    assert check_two_line_fasta(path) == 2


def test_wrapped_fasta_is_rejected(tmp_path):
    path = tmp_path / "wrapped.fa"
    path.write_text(">a\nACGT\nACGT\n>b\nGG\n")
    with pytest.raises(ValidationError, match="line 3"):
        check_two_line_fasta(path)


def test_fasta_with_a_dangling_header_is_rejected(tmp_path):
    path = tmp_path / "odd.fa"
    path.write_text(">a\nACGT\n>b\n")
    with pytest.raises(ValidationError, match="odd"):
        check_two_line_fasta(path)


def test_screen_output_must_have_one_row_per_record(tmp_path):
    chunk = tmp_path / "chunk.fa"
    chunk.write_text(">a\nACGT\n>b\nGG\n")
    csv = tmp_path / "chunk.csv"
    csv.write_text("sample_name,x\na,1\nb,2\n")
    assert check_screen_output(chunk, csv) == 2

    csv.write_text("sample_name,x\na,1\n")
    with pytest.raises(ValidationError, match="1 rows for 2 records"):
        check_screen_output(chunk, csv)


def test_missing_screen_output_is_reported(tmp_path):
    chunk = tmp_path / "chunk.fa"
    chunk.write_text(">a\nACGT\n")
    with pytest.raises(ValidationError, match="not written"):
        check_screen_output(chunk, tmp_path / "missing.csv")


def test_counts_round_trip_and_sum(tmp_path):
    write_counts(tmp_path / "a.tsv", Counter({"x": 1, "y": 2}))
    write_counts(tmp_path / "b.tsv", Counter({"x": 10}))
    assert sum_counts([tmp_path / "a.tsv", tmp_path / "b.tsv"]) == {"x": 11, "y": 2}


def test_format_counts_shows_shares():
    text = format_counts(Counter({"kept": 3, "dropped": 1}))
    assert "kept" in text and "75.00" in text and "total" in text
