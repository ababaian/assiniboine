import pytest

from assiniboine import config
from assiniboine.config import ConfigError, DEFAULTS_PATH, flatten, load_config, merge, to_shell


def test_the_defaults_file_loads_and_has_the_expected_sections():
    settings = load_config(run_file=None, defaults_path=DEFAULTS_PATH)
    assert set(settings) == {"run", "source", "kraken", "overlap", "length", "screen", "shortlist", "compute"}
    assert settings["length"]["min_nt"] == 200
    assert settings["overlap"]["length"] == 30


def test_a_run_file_overrides_only_what_it_names(tmp_path):
    run_file = tmp_path / "run.toml"
    run_file.write_text('[length]\nmax_nt = 3000\n[compute]\nscreen_workers = 1\n')
    settings = load_config(run_file)
    assert settings["length"] == {"min_nt": 200, "max_nt": 3000}
    assert settings["compute"]["screen_workers"] == 1


def test_an_unknown_key_is_an_error(tmp_path):
    run_file = tmp_path / "run.toml"
    run_file.write_text("[length]\nmaximum = 3000\n")
    with pytest.raises(ConfigError, match="unknown key 'maximum'"):
        load_config(run_file)


def test_an_unknown_section_is_an_error():
    with pytest.raises(ConfigError, match=r"unknown section \[nope\]"):
        merge({"a": {"x": 1}}, {"nope": {"x": 1}})


def test_the_environment_variable_selects_the_run_file(tmp_path, monkeypatch):
    run_file = tmp_path / "run.toml"
    run_file.write_text('[run]\nname = "from-env"\n')
    monkeypatch.setenv("ASSINIBOINE_CONFIG", str(run_file))
    assert load_config()["run"]["name"] == "from-env"


def test_flatten_and_shell_export():
    settings = {"length": {"min_nt": 200}, "kraken": {"database": "/my db", "flag": True}}
    assert flatten(settings) == {"LENGTH_MIN_NT": 200, "KRAKEN_DATABASE": "/my db", "KRAKEN_FLAG": True}
    shell = to_shell(settings)
    assert "export LENGTH_MIN_NT=200\n" in shell
    assert "export KRAKEN_DATABASE='/my db'\n" in shell
    assert "export KRAKEN_FLAG=true\n" in shell


def test_the_published_run_files_are_valid():
    for name in ("2026-11.toml", "example.toml"):
        load_config(config.REPO_ROOT / "config" / "runs" / name)
