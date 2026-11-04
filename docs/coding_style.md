# Coding style

The conventions this repository follows. They exist so that a reader with
introductory Python and Bash can follow any file top to bottom, and so that
changing one thing does not require understanding everything.

## Who does what

| layer | holds | lives in |
|---|---|---|
| method | the rules: how a record is classified, filtered, ranked | `src/assiniboine/` (and the external classifier) |
| workflow | the order of stages, what runs in parallel, resume markers | `workflow/*.sh` |
| configuration | every number a user might change | `config/*.toml` |
| documentation | why the rules are what they are, what the files mean | `docs/` |
| run records | what one run produced and where it is | `docs/runs/`, `config/runs/` |

A workflow script never implements a rule: it calls an `assiniboine`
command. A Python module never decides how many processes to run: it does
one file's work and returns. Settings are read from the TOML files, never
hard-coded in a script. Machine-specific details (paths, notification
hooks, resource watchers) do not go in the repository at all.

## Python

* One module per stage, named for what it does (`topology`, `filtering`),
  with a docstring at the top that explains the stage in plain language
  before any code.
* Functions do one thing and say what it is: `classify_closure`,
  `split_by_length`, `check_screen_output`. A function that both decides
  and writes is two functions.
* Data flows through plain values: strings, tuples, `Record`,
  `NamedTuple` rows, `Counter` for counts. No class is introduced to hold a
  function.
* Streams, not loads. Every reader is a generator and every writer takes
  one, so a stage over 900 million records needs the same memory as one
  over 900.
* Constants are named and placed where they are used: `DEFAULT_OVERLAP`
  in `topology.py`, `LENGTH_BINS` in `filtering.py`.
* Errors say what was found and what was expected, with the record id or
  file name: `"{id}: stage 2 wrote 270 nt, expected 300"`. Each module has
  its own exception class so the CLI can tell a failed check from a crash.
* Only the standard library. `pandas` would not make a 44,000-row sort
  clearer, and every dependency is something a student must install.
* Type hints on every public function; `from __future__ import annotations`
  at the top of each module.
* Formatting: four-space indents, lines up to about 120 characters, one
  blank line between related functions and two between sections, double
  quotes.

## Bash

* `set -euo pipefail` through `common.sh`: an unset variable, a failing
  command or a failing pipe stops the script.
* The header comment lists what goes in, what comes out, and what the
  script decides. The body follows the same shape: checks, work, summary,
  marker.
* Parallelism is `xargs -P` over a list of files calling one command per
  file. A function passed to `xargs` is exported with `export -f` and
  called as `bash -c 'name "$1"' _ {}` so arguments with spaces survive.
* Every path is quoted. Variables from the settings are upper case
  (`$LENGTH_MIN_NT`); locals are lower case.
* A stage checks its inputs exist before starting and says which earlier
  stage provides them.

## Tests

* `tests/` mirrors `src/`: one test file per module, plus `test_cli.py`
  for the command line and the whole example run.
* Tests build their own inputs from `scripts/ops/make_example_data.py`;
  nothing depends on files outside the repository.
* A rule's edge cases get a test each: the inclusive bounds, the header
  overriding the sequence, the palindromic circle. A check gets a test
  that it passes on good input and a test that it fails, with the
  expected message, on bad input.
* `pytest` runs in seconds. If a test needs an external tool, it skips
  cleanly when the tool is absent.

## Adding a stage

1. Write the rule as functions in a new module under `src/assiniboine/`,
   with a module docstring explaining it, and tests.
2. Add a subcommand to `cli.py` that applies it to one file.
3. Add a directory under `workflow/` with a script in the usual shape and
   a README, and add the script to `STAGE_SCRIPTS` in `run_screen.sh`.
4. Add its settings to `config/defaults.toml`, its files to
   `docs/data_dictionary.md`, its reasoning to `docs/methods.md`, and a
   row to the table in `docs/pipeline.md`.

## Changing a rule

A change to anything above `[compute]` in the settings, or to a function
in `src/assiniboine/` that decides something about a record, changes the
science. Make it deliberately: update `docs/methods.md`, give the run that
uses it its own settings file and run record, and keep the tests that
pinned the old behaviour until the change is agreed.
