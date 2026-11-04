import csv

import pytest

import make_example_data
from assiniboine.results import (
    ResultsError,
    build_shortlist,
    pair_chunks_with_results,
    read_screened,
    reduce_screen,
    unique_columns,
)
from assiniboine.sequences import read_fasta
from assiniboine.topology import label_file, strip_label


@pytest.fixture
def screened_chunk(tmp_path, source_fasta):
    """A labelled chunk of 600 records and a synthetic screen result for it."""
    chunk = tmp_path / "chunk_000.fa"
    label_file(source_fasta, chunk)
    result = tmp_path / "chunk_000.csv"
    make_example_data.make_screen(chunk, result, seed=5)
    return chunk, result


def test_unique_columns_keeps_first_occurrences_and_pairs_repeats():
    keep, duplicates = unique_columns(["a", "b", "a", "c", "b"])
    assert keep == [0, 1, 3]
    assert duplicates == [(0, 2), (1, 4)]


def test_screen_columns_reduce_from_48_to_41():
    keep, duplicates = unique_columns(make_example_data.SCREEN_COLUMNS)
    assert len(make_example_data.SCREEN_COLUMNS) == 48
    assert len(keep) == 41
    assert len(duplicates) == 7


def test_read_screened_lines_records_up_with_rows(screened_chunk):
    chunk, result = screened_chunk
    pairs = list(read_screened(chunk, result))
    assert len(pairs) == 600
    for record, row in pairs:
        assert row["sample_name"] == record.id
        assert "n_ribozymes" in row and len(row) == 41


def test_read_screened_rejects_a_row_count_mismatch(screened_chunk):
    chunk, result = screened_chunk
    lines = result.read_text().splitlines(keepends=True)
    result.write_text("".join(lines[:-1]))
    with pytest.raises(ResultsError, match="same number of records"):
        list(read_screened(chunk, result))


def test_read_screened_rejects_misaligned_ids(screened_chunk):
    chunk, result = screened_chunk
    lines = result.read_text().splitlines(keepends=True)
    lines[1], lines[2] = lines[2], lines[1]
    result.write_text("".join(lines))
    with pytest.raises(ResultsError, match="does not line up"):
        list(read_screened(chunk, result))


def test_read_screened_rejects_duplicate_columns_that_disagree(screened_chunk):
    chunk, result = screened_chunk
    lines = result.read_text().splitlines(keepends=True)
    fields = lines[1].rstrip("\n").split(",")
    fields[37] = "99"  # the second copy of n_ribozymes
    lines[1] = ",".join(fields) + "\n"
    result.write_text("".join(lines))
    with pytest.raises(ResultsError, match="differs between its two copies"):
        list(read_screened(chunk, result))


def make_row(confidence, strands="+;-", corroborated=0, n_ribozymes=2):
    return {
        "sample_name": f"r{confidence}",
        "confidence": str(confidence),
        "strands_present": strands,
        "n_corroborated_loci": str(corroborated),
        "n_ribozymes": str(n_ribozymes),
    }


def test_shortlist_tiers():
    rows = [
        make_row(0.99, corroborated=1),  # tier 1
        make_row(0.95),  # tier 2
        make_row(0.85),  # tier 2
        make_row(0.70),  # below the floor
        make_row(0.99, strands="+"),  # one strand only
    ]
    shortlist, counts = build_shortlist(rows, tier2_min_confidence=0.8, tier2_max_rows=10)
    assert [(r["tier"], r["sample_name"]) for r in shortlist] == [("1", "r0.99"), ("2", "r0.95"), ("2", "r0.85")]
    assert counts["both_strands"] == 4
    assert counts["tier2_pool"] == 2 and counts["tier2_cut"] == 0


def test_shortlist_tier2_is_ranked_and_capped():
    rows = [make_row(c) for c in (0.81, 0.99, 0.9)]
    shortlist, counts = build_shortlist(rows, tier2_max_rows=2)
    assert [r["confidence"] for r in shortlist] == ["0.99", "0.9"]
    assert counts["tier2_cut"] == 1
    assert counts["tier2_lowest_confidence"] == 0.9


def test_reduce_screen_writes_the_fasta_and_the_three_tables(tmp_path, screened_chunk, source_fasta):
    chunk, result = screened_chunk
    out = tmp_path / "out"
    counts = reduce_screen([(chunk, result)], out)

    rods = list(csv.DictReader(open(out / "rods.csv", newline="")))
    assert counts["rod"] == len(rods) > 0
    assert list(rods[0])[:3] == ["sample_name", "run", "closure"]
    assert "sequence" not in rods[0]
    assert all(r["predicted_class"] == "rod" for r in rods)

    # rods.fa: one record per rods.csv row, same order, the source header
    # untouched and the screened (trimmed, upper-case) sequence.
    fasta = list(read_fasta(out / "rods.fa"))
    assert [r.id for r in fasta] == [r["sample_name"] for r in rods]
    source_headers = {r.id: r.header for r in read_fasta(source_fasta)}
    screened = {r.id: r for r in read_fasta(chunk)}
    for record in fasta:
        assert record.header == source_headers[record.id]
        assert record.header == strip_label(screened[record.id].header)
        assert record.sequence == screened[record.id].sequence
    assert all(len(r.sequence) == int(row["length"]) for r, row in zip(fasta, rods))
    assert all(r["run"] == r["sample_name"].split("_")[0] for r in rods)
    assert set(r["closure"] for r in rods) <= {"circular", "hairpin", "unmatched"}

    with_ribozyme = list(csv.DictReader(open(out / "rods_with_ribozyme.csv", newline="")))
    assert counts["rod_with_ribozyme"] == len(with_ribozyme)
    assert "sequence" not in with_ribozyme[0]
    assert all(int(r["n_ribozymes"]) >= 1 for r in with_ribozyme)

    shortlist = list(csv.DictReader(open(out / "shortlist.csv", newline="")))
    assert len(shortlist) == counts["tier1"] + counts["tier2_kept"]
    assert all(r["strands_present"] == "+;-" for r in shortlist)


def test_pair_chunks_with_results_demands_a_result_per_chunk(tmp_path):
    (tmp_path / "chunk_000.fa").write_text(">a\nAC\n")
    with pytest.raises(ResultsError, match="no screen result"):
        pair_chunks_with_results(tmp_path, tmp_path)
    (tmp_path / "chunk_000.csv").write_text("sample_name\na\n")
    assert pair_chunks_with_results(tmp_path, tmp_path) == [(tmp_path / "chunk_000.fa", tmp_path / "chunk_000.csv")]
