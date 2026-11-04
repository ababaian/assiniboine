import pytest

from assiniboine import manifest
from assiniboine.filtering import LENGTH_BINS, split_by_length
from assiniboine.manifest import ManifestError, build_rows, read_manifest, verify_rebuild, write_manifest, write_rebuilt_files
from assiniboine.sequences import read_fasta, read_fasta_files, sorted_files
from assiniboine.topology import label_file

RECORDS_PER_PART = 200
METHOD = dict(overlap=30, min_length=200, max_length=6000)


@pytest.fixture
def run(tmp_path, source_fasta, stage1_dir):
    """Stages 1 to 3 of a synthetic run, laid out as the workflow lays them out."""
    labelled_dir = tmp_path / "02" / "labelled"
    length_dir = tmp_path / "03"
    labelled_dir.mkdir(parents=True)
    for part in sorted_files(stage1_dir / "unclassified", "part_*.fa"):
        label_file(part, labelled_dir / part.name)
        outputs = {}
        for name in LENGTH_BINS:
            (length_dir / name).mkdir(parents=True, exist_ok=True)
            outputs[name] = length_dir / name / part.name
        split_by_length(labelled_dir / part.name, outputs)
    return dict(source=source_fasta, calls_dir=stage1_dir / "calls", unclassified_dir=stage1_dir / "unclassified",
                labelled_dir=labelled_dir, length_dir=length_dir)


def rows_for(run):
    return build_rows(
        manifest.read_source(run["source"]),
        manifest.read_kraken_calls(sorted_files(run["calls_dir"], "part_*.tsv.zst")),
        read_fasta_files(sorted_files(run["labelled_dir"], "part_*.fa")),
        **METHOD,
    )


def test_manifest_has_one_row_per_source_record_in_order(run, tmp_path):
    path = tmp_path / "manifest.tsv.zst"
    counts = write_manifest(rows_for(run), path)
    rows = list(read_manifest(path))
    source_ids = [r.id for r in read_fasta(run["source"])]
    assert [r.id for r in rows] == source_ids
    assert counts["kraken"]["C"] + counts["kraken"]["U"] == 600
    assert counts["stage"]["classified"] == counts["kraken"]["C"]
    assert set(counts["closure"]) <= {"circular", "hairpin", "unmatched"}


def test_classified_rows_carry_a_taxid_and_unclassified_a_length_bin(run):
    for row in rows_for(run):
        if row.kraken == "C":
            assert row.taxid != "0" and row.stage == "classified"
        else:
            assert row.taxid == "0" and row.stage in LENGTH_BINS
        assert row.run == row.id.split("_")[0]


def test_build_detects_a_missing_stage2_record(run, tmp_path):
    part = sorted_files(run["labelled_dir"], "part_*.fa")[0]
    records = list(read_fasta(part))
    part.write_text("".join(r.as_fasta() for r in records[1:]))
    with pytest.raises(ManifestError, match="next stage 2 record"):
        list(rows_for(run))


def test_build_detects_leftover_kraken_calls(run, tmp_path):
    extra = run["calls_dir"] / "part_999.tsv"
    extra.write_text("U\tghost_1_circle_1\t0\t100\n")
    calls = manifest.read_kraken_calls(sorted_files(run["calls_dir"], "part_*.tsv*"))
    rows = build_rows(manifest.read_source(run["source"]), calls,
                      read_fasta_files(sorted_files(run["labelled_dir"], "part_*.fa")), **METHOD)
    with pytest.raises(ManifestError, match="left over"):
        list(rows)


def test_rebuild_reproduces_every_stage_file(run, tmp_path):
    path = tmp_path / "manifest.tsv.zst"
    write_manifest(rows_for(run), path)

    out = tmp_path / "rebuilt"
    parts = write_rebuilt_files(manifest.read_source(run["source"]), read_manifest(path), out, RECORDS_PER_PART, **METHOD)
    assert parts == 3
    for name in ("part_000.fa", "part_001.fa", "part_002.fa"):
        assert (out / "unclassified" / name).read_bytes() == (run["unclassified_dir"] / name).read_bytes()
        assert (out / "labelled" / name).read_bytes() == (run["labelled_dir"] / name).read_bytes()
        for stage in LENGTH_BINS:
            assert (out / stage / name).read_bytes() == (run["length_dir"] / stage / name).read_bytes()
    # classified sequences are rebuilt too, although stage 1 does not keep them
    classified = sum(1 for _ in read_fasta_files(sorted_files(out / "classified", "part_*.fa")))
    assert classified == sum(1 for r in read_manifest(path) if r.kraken == "C")


def test_verify_passes_on_the_run_and_reports_a_changed_file(run, tmp_path):
    path = tmp_path / "manifest.tsv.zst"
    write_manifest(rows_for(run), path)
    existing = {"unclassified": run["unclassified_dir"], "labelled": run["labelled_dir"]}
    for stage in LENGTH_BINS:
        existing[stage] = run["length_dir"] / stage

    assert verify_rebuild(manifest.read_source(run["source"]), read_manifest(path), existing, RECORDS_PER_PART, **METHOD) == []

    damaged = run["length_dir"] / "in_range" / "part_001.fa"
    damaged.write_text(damaged.read_text().lower())
    problems = verify_rebuild(manifest.read_source(run["source"]), read_manifest(path), existing, RECORDS_PER_PART, **METHOD)
    assert problems == [f"{damaged} differs from the rebuild"]
