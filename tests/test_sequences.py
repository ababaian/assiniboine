import io

import pytest

from assiniboine import sequences
from assiniboine.sequences import Record, open_text, parse_fasta, read_fasta, reverse_complement, write_fasta

HEADER = "SRR12604050_704504_circle_704504 ka:f:4.900 L:-:704504:- L:+:704504:+"


def test_record_id_and_run_come_from_the_header():
    record = Record(HEADER, "ACGT")
    assert record.id == "SRR12604050_704504_circle_704504"
    assert record.run_accession == "SRR12604050"


def test_as_fasta_is_two_lines():
    assert Record("x y", "ACGT").as_fasta() == ">x y\nACGT\n"


def test_parse_fasta_joins_wrapped_sequences():
    text = ">a\nACG\nTTT\n>b desc\nGG\n"
    records = list(parse_fasta(io.StringIO(text)))
    assert [(r.header, r.sequence) for r in records] == [("a", "ACGTTT"), ("b desc", "GG")]


def test_parse_fasta_rejects_text_without_a_header():
    with pytest.raises(ValueError):
        list(parse_fasta(io.StringIO("ACGT\n")))


def test_reverse_complement():
    assert reverse_complement("AACGT") == "ACGTT"
    assert reverse_complement("ACGX") == "NCGT"


def test_round_trip_through_plain_gzip_and_zstd(tmp_path):
    records = [Record("a", "ACGT"), Record("b c", "GGCC")]
    for name in ("x.fa", "x.fa.gz", "x.fa.zst"):
        path = tmp_path / name
        with open_text(path, "w") as stream:
            assert write_fasta(stream, records) == 2
        assert list(read_fasta(path)) == records
        assert sequences.count_records(path) == 2


def test_zstd_reads_through_a_symbolic_link(tmp_path):
    path = tmp_path / "x.fa.zst"
    with open_text(path, "w") as stream:
        write_fasta(stream, [Record("a", "ACGT")])
    link = tmp_path / "link.fa.zst"
    link.symlink_to(path)
    assert list(read_fasta(link)) == [Record("a", "ACGT")]


def test_sorted_files_keeps_parts_in_name_order(tmp_path):
    for name in ("part_002.fa", "part_000.fa", "part_001.fa"):
        (tmp_path / name).write_text("")
    assert [p.name for p in sequences.sorted_files(tmp_path, "part_*.fa")] == ["part_000.fa", "part_001.fa", "part_002.fa"]
