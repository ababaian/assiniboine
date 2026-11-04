# Installation

Four things are needed: the conda environment with the command-line tools,
the `assiniboine` package, and, for stages 1 and 4 only, a Kraken2 database
and the classifier bundle. Stages 2, 3, 5 and 6 and the tests need just the
first two.

## 1. Environment and package

```bash
conda env create -f environment.yml
conda activate assiniboine
```

The environment installs the tools (`zstd`, `awscli`, `kraken2`,
`viennarna`, `infernal`, `emboss`), the Python stack the external
classifier needs (with `scikit-learn` pinned to 1.9.1, the version its
model was pickled with), and this package in editable mode, which puts the
`assiniboine` command on your path.

Without conda, the package alone installs with `pip install -e .` into any
Python 3.11 or newer. It has no dependencies of its own. The tools then have
to come from elsewhere; `scripts/ops/check_dependencies.sh` reports what is
missing.

Check:

```bash
./scripts/ops/check_dependencies.sh
pytest
./scripts/ops/run_example.sh      # stages 0, 2, 3, 5, 6 for real on synthetic data
```

## 2. A Kraken2 database (stage 1)

Point `[kraken] database` in your run file at a Kraken2 database
directory (one containing `hash.k2d`). The published runs used a core_nt
build from October 2025, 340 GB. Build one with `kraken2-build` or download
a prebuilt index from the Kraken2 maintainers; a smaller index works for
trying the pipeline, with a correspondingly smaller "known" set.

Kraken2 memory-maps the database, so the machine should have enough RAM to
hold it in the page cache for the stage to run at speed.

## 3. The classifier bundle (stage 4)

The rod classifier is a collaborator's pipeline, distributed as a bundle
named Lebowski that is not part of this repository. Fetch it to the
repository root (or anywhere, and set `[screen] lebowski_dir`):

```bash
aws s3 cp s3://petadex/circs-results/model/lebowski_20261002.tar.gz . --no-sign-request
aws s3 cp s3://petadex/circs-results/model/MANIFEST.md5 . --no-sign-request
tar xzf lebowski_20261002.tar.gz
(cd Lebowski && md5sum -c ../MANIFEST.md5)
```

Stage 4 reads four things from it: `Scripts/run_pipeline.py` with its
sibling modules, `rodnotrod_model/model.pkl` (md5
`b2e052da3e88d1802a5ed71ae34a8b9c`), `CM/dvr5.cm`, and the 18 `CM/RF*.cm`
Rfam models. `rod_screen.sh` checks for them before starting.

## 4. Settings

Copy `config/runs/2026-11.toml` to a new run file, set the database path,
and scale the `[compute]` section down to your machine. Then:

```bash
export ASSINIBOINE_CONFIG=config/runs/my_run.toml
./workflow/run_screen.sh
```

`docs/configuration.md` describes every setting.
