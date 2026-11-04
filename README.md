# Assiniboine

A pipeline that screens circular sequencing contigs for rod-like,
ribozyme-bearing RNAs: viroids, ribozyviruses, obelisks, ambiviruses and
anything resembling them.

The input is a FASTA of "selfloop" contigs, sequences an assembler found
joining back onto themselves. The output is a table of the contigs that fold
into a rod, annotated with the ribozymes they carry, with a shortlist of the
candidates whose ribozymes sit on both strands. The published runs screened
Logan's archive of every circular contig assembled from the Sequence Read
Archive, 900 million records; the pipeline is the same at any size.

## The pipeline

```
 0  fetch the source archive
 1  Kraken2 filter          drop every record matching reference database
 2  circular overlap        label how each record closes; trim the 30 nt overlap
 3  length filter           keep [200,6,000] nt contigs
 4  rod screen              fold, search for ribozymes, call rod or not (external classifier)
 5  results                 the rod tables and the shortlist
 6  package                 a record manifest that rebuilds stages 1 to 3, plus checksums
 7  dot-bracket             the folded structure of every rod
```

| stage | script | rule |
|---|---|---|
| 0 | `workflow/00_source/fetch_source.sh` | |
| 1 | `workflow/01_kraken_filter/kraken_filter.sh` | Kraken2 |
| 2 | `workflow/02_circular_overlap/label_overlap.sh` | `src/assiniboine/topology.py` |
| 3 | `workflow/03_length_filter/length_filter.sh` | `src/assiniboine/filtering.py` |
| 4 | `workflow/04_rod_screen/rod_screen.sh` | the Lebowski bundle (`docs/dependencies.md`) |
| 5 | `workflow/05_results/make_results.sh` | `src/assiniboine/results.py` |
| 6 | `workflow/06_package/package_run.sh` | `src/assiniboine/manifest.py` |
| 7 | `workflow/07_dotbracket/fold_rods.sh` | `src/assiniboine/dotbracket.py` |

## Quick start

```bash
conda env create -f environment.yml && conda activate assiniboine   # tools + the package
./scripts/ops/check_dependencies.sh                                 # what is in place
pytest                                                              # the tests
./scripts/ops/run_example.sh                                        # a miniature run on synthetic data, in seconds
```

For a real run, write a settings file naming your Kraken2 database and
sizing the parallelism to your machine, then run the stages in order:

```bash
cp config/runs/2026-11.toml config/runs/my_run.toml   # and edit it
export ASSINIBOINE_CONFIG=config/runs/my_run.toml
./workflow/run_screen.sh                              # or: ./workflow/run_screen.sh 2 3
```

Every stage writes under `work/`, is skipped once finished, and resumes
where it stopped. `docs/installation.md` covers the two external resources
stages 1 and 4 need: a Kraken2 database and the classifier bundle.

## Layout

```
config/           settings: defaults.toml defines everything, runs/*.toml override
src/assiniboine/  the rules each stage applies, as a Python package with a CLI
workflow/         one Bash script per stage, plus the driver run_screen.sh
scripts/          side analyses and helpers, including the synthetic example run
tests/            pytest suite over the package and the example run
docs/             how it works, how to configure, reproduce and extend it
docs/runs/        records of the published runs and where their data is
```

## Documentation

| document | what it covers |
|---|---|
| `docs/pipeline.md` | each stage's inputs, outputs and checks; the data flow |
| `docs/methods.md` | the scientific rules and the reasons behind them |
| `docs/installation.md` | environment, package, Kraken2 database, classifier bundle |
| `docs/configuration.md` | every setting, and which ones change the science |
| `docs/data_dictionary.md` | every file and column the pipeline reads or writes |
| `docs/reproducibility.md` | reproducing a run; the manifest and checksums |
| `docs/dependencies.md` | each tool, what it is used for, and the external data |
| `docs/coding_style.md` | the conventions this code follows, and how to add a stage |
| `docs/runs/2026-11.md` | the November 2026 run of Logan's archive and its data |
| `docs/runs/2026-10.md` | the October 2026 run, superseded, and its known defects |
