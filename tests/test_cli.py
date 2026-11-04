"""The command line, and the whole workflow on synthetic data."""

import os
import shutil
import subprocess

import pytest

from assiniboine.cli import main
from conftest import REPO_ROOT


def run_cli(*args):
    main([str(a) for a in args])


def test_label_overlap_and_sum_counts(tmp_path, source_fasta, capsys):
    counts = tmp_path / "c.tsv"
    run_cli("label-overlap", source_fasta, tmp_path / "out.fa", "--counts", counts)
    assert counts.read_text().startswith("circular\t")
    run_cli("sum-counts", counts)
    assert "circular" in capsys.readouterr().out


def test_length_filter_writes_three_directories(tmp_path, source_fasta):
    run_cli("label-overlap", source_fasta, tmp_path / "lab.fa")
    run_cli("length-filter", tmp_path / "lab.fa", "--out-dir", tmp_path / "03", "--name", "part_000")
    for name in ("too_short", "in_range", "too_long"):
        assert (tmp_path / "03" / name / "part_000.fa").exists()


def test_validate_fasta_fails_loudly_on_wrapped_input(tmp_path):
    bad = tmp_path / "bad.fa"
    bad.write_text(">a\nAC\nGT\n")
    with pytest.raises(SystemExit) as exit_info:
        run_cli("validate", "fasta", bad)
    assert "not two lines per record" in str(exit_info.value)


def test_config_export_is_shell_syntax(capsys):
    run_cli("config", "export")
    out = capsys.readouterr().out
    assert "export LENGTH_MIN_NT=200\n" in out
    assert "export COMPUTE_SCREEN_WORKERS=" in out


@pytest.mark.skipif(shutil.which("assiniboine") is None, reason="the assiniboine command must be installed")
def test_the_example_run_goes_end_to_end(tmp_path):
    """scripts/ops/run_example.sh with a copy of its settings pointing at a temporary work directory."""
    run_file = tmp_path / "example.toml"
    text = (REPO_ROOT / "config" / "runs" / "example.toml").read_text()
    text = text.replace('work_dir = "work/example"', f'work_dir = "{tmp_path}/work"')
    text = text.replace('url = "work/example/example_source.fa.zst"', f'url = "{tmp_path}/work/example_source.fa.zst"')
    run_file.write_text(text)

    script = REPO_ROOT / "scripts" / "ops" / "run_example.sh"
    result = subprocess.run(["bash", str(script), str(run_file)], cwd=REPO_ROOT, capture_output=True, text=True, env=os.environ)
    assert result.returncode == 0, result.stdout + result.stderr

    work = tmp_path / "work"
    for stage in ("00_source", "01_kraken_filter", "02_circular_overlap", "03_length_filter", "04_rod_screen", "05_results", "06_package"):
        assert (work / stage / "DONE").exists(), stage
    assert (work / "05_results" / "rods.csv").stat().st_size > 0
    assert (work / "06_package" / "record_manifest.tsv.zst").exists()
    if shutil.which("RNAfold"):
        assert (work / "07_dotbracket" / "rods_dotbracket.tsv.zst").exists()
