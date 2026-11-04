"""Settings: defaults, per-run overrides, and the hand-off to the shell.

Settings live in TOML files. ``config/defaults.toml`` defines every setting
and its default; a run file such as ``config/runs/2026-11.toml`` overrides
some of them. A run file may only override keys that exist in the defaults,
so a misspelt key is an error rather than a silently ignored one.

The workflow scripts are Bash. They get their settings by running
``assiniboine config export``, which prints ``export SECTION_KEY=value`` lines
that the shell evaluates. ``[length] min_nt = 200`` becomes ``LENGTH_MIN_NT=200``.
"""

from __future__ import annotations

import os
import shlex
import tomllib
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULTS_PATH = REPO_ROOT / "config" / "defaults.toml"

Config = dict[str, dict[str, Any]]


class ConfigError(Exception):
    """A settings file is missing, malformed, or names an unknown key."""


def read_toml(path: str | Path) -> Config:
    path = Path(path)
    if not path.exists():
        raise ConfigError(f"settings file not found: {path}")
    with open(path, "rb") as stream:
        try:
            return tomllib.load(stream)
        except tomllib.TOMLDecodeError as error:
            raise ConfigError(f"{path}: {error}") from error


def merge(defaults: Config, overrides: Config, source: str = "override") -> Config:
    """Return ``defaults`` with ``overrides`` applied, one section deep.

    Every section and key in ``overrides`` must already exist in ``defaults``.
    """
    merged = {section: dict(values) for section, values in defaults.items()}
    for section, values in overrides.items():
        if section not in merged:
            raise ConfigError(f"{source}: unknown section [{section}]")
        if not isinstance(values, dict):
            raise ConfigError(f"{source}: top-level key '{section}' must be inside a section")
        for key, value in values.items():
            if key not in merged[section]:
                raise ConfigError(f"{source}: unknown key '{key}' in section [{section}]")
            merged[section][key] = value
    return merged


def load_config(run_file: str | Path | None = None, defaults_path: str | Path = DEFAULTS_PATH) -> Config:
    """Load the defaults and apply one optional run file on top.

    When ``run_file`` is ``None`` the ``ASSINIBOINE_CONFIG`` environment
    variable is consulted, so every workflow script picks up the same run.
    """
    config = read_toml(defaults_path)
    if run_file is None:
        run_file = os.environ.get("ASSINIBOINE_CONFIG") or None
    if run_file:
        config = merge(config, read_toml(run_file), source=str(run_file))
    return config


def flatten(config: Config) -> dict[str, Any]:
    """``{"length": {"min_nt": 200}}`` becomes ``{"LENGTH_MIN_NT": 200}``."""
    flat = {}
    for section, values in config.items():
        for key, value in values.items():
            flat[f"{section}_{key}".upper()] = value
    return flat


def to_shell(config: Config) -> str:
    """Render the settings as ``export KEY=value`` lines for Bash to evaluate."""
    lines = []
    for name, value in flatten(config).items():
        if isinstance(value, bool):
            value = "true" if value else "false"
        lines.append(f"export {name}={shlex.quote(str(value))}")
    return "\n".join(lines) + "\n"


def render_value(value: Any) -> str:
    """Render one setting the way it would be written in TOML."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return f'"{value}"'
    return str(value)


def to_text(config: Config) -> str:
    """Render the settings as TOML-like text for people to read."""
    lines = []
    for section, values in config.items():
        lines.append(f"[{section}]")
        for key, value in values.items():
            lines.append(f"{key} = {render_value(value)}")
        lines.append("")
    return "\n".join(lines)
