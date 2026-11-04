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


## Assiniboine Data Directory
```
S3 Bucket

⦿ s3://assiniboine/
├── fa/               # Source Fasta Files
│   └─── ctrl/        # Potentially useful GenBank sequence collections
│         └────────── `*.fa`                # Fasta file
│         └────────── `*.csv`               # assiniboine pipeline features
│
│   └─── lsc/         # Logan Simple Circles 
│         └────────── `LSC_v1.1.fa.zst`      # Complete Logan self-loops
│         └────────── `LSC-1M_v1.1.fa.zst`   # 1M random subset LSC
│         └────────── `LSC-100K_v1.1.fa.zst` # 100K random subset LSC1M
│         └────────── `LSC-1K_v1.1.fa.zst`   # 1K random subset LSC1M
│
│   └─── rod/         # Predicated Rod-like Elements (v1.1)
│         └────────── `ROD_v1.1.fa.zst`      # Rod-like Element set
│         └────────── `ROD-1M_v1.1.fa.zst`   # 1M randomly selected ROD
│         └────────── `ROD-100K_v1.1.fa.zst` # 100K randomly selected ROD1M
│         └────────── `ROD-1K_v1.1.fa.zst`   # 1K   randomly selected ROD100K
│         └────────── `ROD_v1.1.csv.zst`     # Assinibone features CSV
├── meta/             # SRA Meta-data
│   └─── `SRA-metadata.parquet`              # SRA Run Info and Metadata
└─────── README.md    # This README
```

```{bash}
# Assiniboine Bucket: s3://assiniboine/

## List the bucket
aws s3 ls s3://assiniboine/fa/

## AWS CLI Download
aws s3 cp s3://assiniboine/fa/ctrl/obelisk_zheludev.fa ./

## WGET Download
wget https://s3.amazonaws.com/assiniboine/fa/ctrl/obelisk_zheludev.fa

wget https://s3.amazonaws.com/assiniboine/fa/rod/ROD-1K_v1.1.fa.zst

```

## Pipeline

```
./workflow/

 0  fetch the source data
 1  Kraken2 filter          drop every record matching reference database
 2  circular overlap        label how each record closes; trim the 30 nt overlap
 3  length filter           keep [200,6,000] nt contigs
 4  rod screen              fold, search for ribozymes, call rod or not (external classifier)
 5  results                 the rod tables and the shortlist
 6  package                 a record manifest that rebuilds stages 1 to 3, plus checksums
 7  dot-bracket             the folded structure of every rod
```

## Quick start

```bash
# Initialize
conda env create -f environment.yml && conda activate assiniboine   # tools + the package
./scripts/ops/check_dependencies.sh                                 # what is in place

# Run test code
pytest                                                              # the tests
./scripts/ops/run_example.sh                                        # a miniature run on synthetic data, in seconds

# Configure toml file for run parameters
cp config/defaults.toml config/runs/run_<YYMMDD>.toml
# Set-up run.toml for your system

# Run Assiniboine
export ASSINIBOINE_CONFIG=config/runs/my_run.toml
./workflow/assiniboine.sh  
```

`assiniboine.sh` stages write to `work/`. Stages are skipped once finished, and resumes
where it stopped. `docs/installation.md` covers the two external resources
stages 1 and 4 need: a Kraken2 database and the classifier bundle.

## Repository Layout

```
.assiniboine/
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
