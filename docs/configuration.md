# Configuration

Settings are TOML. `config/defaults.toml` defines every setting and its
default. A run file in `config/runs/` overrides some of them, and may only
name keys that exist in the defaults: a misspelt key is an error, not a
silently ignored one.

```bash
export ASSINIBOINE_CONFIG=config/runs/my_run.toml   # which run file to apply
assiniboine config show                             # the merged settings
assiniboine config export                           # as shell variables
```

Every workflow script loads the settings through `config export`, so
`[length] min_nt = 200` is `$LENGTH_MIN_NT` in the shell. Relative paths
are relative to the repository root, which `workflow/common.sh` moves to.

## Method settings

These change the science. The defaults are the values of the published
runs; a run with different values is a different screen and should say so
in its run record.

| setting | default | meaning |
|---|---|---|
| `[source] url` | Logan's selfloops archive | what to screen |
| `[source] filename` | `selfloops.fa.zst` | the archive's name in the work directory |
| `[source] expected_bytes` | the archive's size | the download must be exactly this size; 0 disables the check |
| `[kraken] database` | (none) | Kraken2 database directory; defines what counts as "known" |
| `[kraken] confidence` | 0.1 | Kraken2's `--confidence` |
| `[overlap] length` | 30 | bases trimmed from circular records; Logan's k minus one |
| `[length] min_nt` | 200 | stage 3 floor, inclusive |
| `[length] max_nt` | 6000 | stage 3 ceiling, inclusive |
| `[screen] lebowski_dir` | `Lebowski` | where the classifier bundle is unpacked |
| `[shortlist] tier2_min_confidence` | 0.8 | confidence floor for tier 2 |
| `[shortlist] tier2_max_rows` | 2000 | row cap for tier 2 |

`[run] name` labels the run in logs; `[run] work_dir` is where everything
is written (default `work/`, ignored by git).

## Compute settings

Nothing in `[compute]` changes the result. They say how the same work is
divided and how much runs at once.

| setting | default | 2026-11 run | meaning |
|---|---|---|---|
| `records_per_part` | 45,000,000 | 45,000,000 | stage 1 part size; stages 2 and 3 keep the parts |
| `kraken_workers` | 1 | 10 | Kraken2 processes at once |
| `kraken_threads` | 8 | 32 | threads per Kraken2 process |
| `part_workers` | 4 | 12 | parts labelled or filtered at once |
| `records_per_chunk` | 1,000,000 | 1,704,636 | stage 4 chunk size; a crash costs one chunk |
| `screen_workers` | 2 | 16 | chunks screened at once |
| `screen_threads` | 8 | 30 | RNAfold jobs and cmsearch CPUs per chunk |
| `screen_batch_size` | 50,000 | 50,000 | records the classifier folds per batch |
| `dotbracket_parts` | 64 | 460 | files the rods are dealt into for stage 7 |
| `dotbracket_workers` | 8 | 460 | parts folded at once |

Sizing: Kraken2 workers share one memory-mapped copy of the database, so
`kraken_workers` is bounded by cores, not RAM, once the database fits in
the page cache. For the screen, `screen_workers * screen_threads` should be
about the core count; on the November machine sixteen workers beat both
eight and forty-eight. The classifier's single-threaded parts parallelise
across workers while `RNAfold` needs threads for the long sequences.

## Adding a setting

1. Add it to `config/defaults.toml` with a comment saying what it does.
2. Read it where it is used: `$SECTION_KEY` in a workflow script, or pass
   it to an `assiniboine` command as an option.
3. If it changes the science, say so in `docs/methods.md` and put it above
   `[compute]`; if it only changes speed, put it in `[compute]`.
