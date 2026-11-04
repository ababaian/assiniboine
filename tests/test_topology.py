import pytest

from assiniboine.sequences import Record, read_fasta
from assiniboine.topology import (
    CIRCULAR,
    HAIRPIN,
    UNMATCHED,
    classify_closure,
    label_file,
    label_record,
    parse_label,
    strip_label,
)
from conftest import write_fasta


def test_circular_record_is_recognised_and_trimmed(circular):
    labelled, closure = label_record(circular)
    assert closure == CIRCULAR
    assert len(labelled.sequence) == len(circular.sequence) - 30
    assert labelled.sequence == circular.sequence[:-30]
    assert labelled.header.endswith(" ovl:circular trim:30")
    assert labelled.id == circular.id


def test_hairpin_record_is_recognised_and_left_alone(hairpin):
    labelled, closure = label_record(hairpin)
    assert closure == HAIRPIN
    assert labelled.sequence == hairpin.sequence
    assert labelled.header.endswith(" ovl:hairpin trim:0")


def test_header_claiming_a_circle_without_matching_ends_is_unmatched(unmatched):
    labelled, closure = label_record(unmatched)
    assert closure == UNMATCHED
    assert labelled.sequence == unmatched.sequence


def test_a_record_with_no_links_is_unmatched():
    sequence = "ACGT" * 20
    assert classify_closure("id ka:f:1.0", sequence) == (UNMATCHED, 0)


def test_one_same_strand_link_is_not_enough_for_circular():
    sequence = "ACGTTGCA" * 10
    assert classify_closure("id L:-:1:-", sequence) == (UNMATCHED, 0)


def test_matching_ends_do_not_override_a_hairpin_header():
    # The header is the primary key: an opposite-strand link means hairpin
    # even if the two ends happen to be identical.
    sequence = "A" * 100
    assert classify_closure("id L:+:1:-", sequence) == (HAIRPIN, 0)


def test_low_complexity_palindromic_ends_are_not_taken_for_a_hairpin():
    # ATATAT... is its own reverse complement, but the header says circular
    # and the ends match, so this is a circle.
    sequence = "AT" * 60
    assert classify_closure("id L:-:1:- L:+:1:+", sequence) == (CIRCULAR, 30)


def test_a_circle_shorter_than_twice_the_overlap_is_unmatched():
    sequence = "ACGTACGTAC" * 5  # 50 nt, ends match but it is under 60
    assert classify_closure("id L:-:1:- L:+:1:+", sequence) == (UNMATCHED, 0)


def test_overlap_length_is_a_parameter():
    body = "ACGGTTCAAGGCTTAACCGGTTAAGGCC"
    sequence = body + body[:5]
    assert classify_closure("id L:-:1:- L:+:1:+", sequence, overlap=5) == (CIRCULAR, 5)
    assert classify_closure("id L:-:1:- L:+:1:+", sequence, overlap=6) == (UNMATCHED, 0)


def test_sequences_are_upper_cased():
    labelled, _ = label_record(Record("id L:+:1:-", "acgt" * 10))
    assert labelled.sequence == "ACGT" * 10


def test_parse_and_strip_label():
    header = "id ka:f:1.0 L:+:1:- ovl:hairpin trim:0"
    assert parse_label(header) == ("hairpin", 0)
    assert strip_label(header) == "id ka:f:1.0 L:+:1:-"
    with pytest.raises(ValueError):
        parse_label("id ka:f:1.0 L:+:1:-")


def test_label_file_counts_every_record_once(tmp_path, circular, hairpin, unmatched):
    source = write_fasta(tmp_path / "in.fa", [circular, hairpin, unmatched, circular])
    counts = label_file(source, tmp_path / "out.fa")
    assert counts == {CIRCULAR: 2, HAIRPIN: 1, UNMATCHED: 1}
    records = list(read_fasta(tmp_path / "out.fa"))
    assert len(records) == 4
    assert [parse_label(r.header)[0] for r in records] == [CIRCULAR, HAIRPIN, UNMATCHED, CIRCULAR]
