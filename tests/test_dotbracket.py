from array import array

import pytest

from assiniboine.dotbracket import DotBracketError, assign_parts, collect_parts, parse_part, parse_rnafold, split_rods
from assiniboine.sequences import open_text, read_fasta


def fake_rnafold(fasta_path, out_path):
    """Imitate RNAfold --circ --noPS: echo header and sequence, then a structure line."""
    with open(out_path, "w") as out:
        for record in read_fasta(fasta_path):
            n = len(record.sequence)
            structure = "(" * (n // 3) + "." * (n - 2 * (n // 3)) + ")" * (n // 3)
            out.write(f">{record.header}\n{record.sequence}\n{structure} ({-0.1 * n:6.2f})\n")


@pytest.fixture
def rods_fa(tmp_path):
    path = tmp_path / "rods.fa"
    with open(path, "w") as stream:
        for i, length in enumerate([300, 1200, 250, 900, 600, 400, 2000]):
            stream.write(f">rod{i} ka:f:1.000 L:-:{i}:- L:+:{i}:+\n{'A' * length}\n")
    return path


def test_assign_parts_deals_longest_first_round_robin():
    lengths = array("L", [300, 1200, 250, 900])
    # longest first: 1200 (idx 1) -> part 0, 900 (idx 3) -> part 1, 300 (idx 0) -> part 0, 250 (idx 2) -> part 1
    assert list(assign_parts(lengths, 2)) == [0, 0, 1, 1]


def test_split_and_collect_round_trip_in_rods_order(tmp_path, rods_fa):
    parts_dir = tmp_path / "parts"
    assert split_rods(rods_fa, parts_dir, n_parts=3) == 7
    part_files = sorted(parts_dir.glob("part_*.fa"))
    assert len(part_files) == 3

    tsvs = []
    for part in part_files:
        fold = part.with_suffix(".fold")
        fake_rnafold(part, fold)
        tsv = part.with_suffix(".tsv")
        expected = sum(1 for _ in read_fasta(part))
        assert parse_part(fold, tsv, expected_rods=expected) == expected
        tsvs.append(tsv)

    out = tmp_path / "rods_dotbracket.tsv.zst"
    assert collect_parts(tsvs, out, expected_rods=7) == 7
    with open_text(out) as stream:
        lines = stream.read().splitlines()
    assert lines[0] == "sample_name\tlength\tmfe\tdot_bracket"
    names = [line.split("\t")[0] for line in lines[1:]]
    assert names == [f"rod{i}" for i in range(7)]
    for line in lines[1:]:
        _, length, mfe, structure = line.split("\t")
        assert len(structure) == int(length)
        assert float(mfe) == pytest.approx(-0.1 * int(length), abs=0.01)


def test_parse_rejects_a_structure_of_the_wrong_length():
    text = ">0|rod0|5\nACGUA\n(...)) ( -1.00)\n"
    with pytest.raises(DotBracketError, match="6-character structure"):
        list(parse_rnafold(text.splitlines(keepends=True)))


def test_parse_rejects_a_missing_structure_line():
    text = ">0|rod0|5\nACGUA\n>1|rod1|5\nACGUA\n(....) ( -1.00)\n"
    with pytest.raises(DotBracketError, match="no structure line"):
        list(parse_rnafold(text.splitlines(keepends=True)))


def test_collect_rejects_a_missing_rod(tmp_path):
    tsv = tmp_path / "p.tsv"
    tsv.write_text("0\trod0\t3\t-1.0\t...\n2\trod2\t3\t-1.0\t...\n")
    with pytest.raises(DotBracketError, match="rod 1 is missing"):
        collect_parts([tsv], tmp_path / "out.tsv")
