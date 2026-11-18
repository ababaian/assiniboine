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
│   └─── control/     # Potentially useful GenBank sequence collections
│         └────────── `*.fa`                # Fasta file (see below)
│         └────────── `*.csv`               # assiniboine pipeline features
│
│   └─── lsc/         # Logan Simple Circles 
│         └────────── `LSC_v1.1.fa.zst`      # Complete Logan self-loops
│         └────────── `LSC-11M_v1.1.fa.zst`  # 11.3M random subset of LSC
│         └────────── `LSC-1M_v1.1.fa.zst`   # 1M random subset LSC
│         └────────── `LSC-100K_v1.1.fa.zst` # 100K random subset LSC1M
│         └────────── `LSC-1K_v1.1.fa.zst`   # 1K random subset LSC1M
│
│   └─── rod/         # Predicated Rod-like Elements (v1.1)
│         └────────── `ROD_v1.1.fa.zst`      # Rod-like Element set
│         └────────── `ROD-1M_v1.1.fa.zst`   # 1M randomly selected ROD
│         └────────── `ROD-100K_v1.1.fa.zst` # 100K randomly selected ROD1M
│         └────────── `ROD-1K_v1.1.fa.zst`   # 1K   randomly selected ROD100K
│         └────────── `ROD_v1.1.reorf.zst`   # RCE calculated ORFs for ROD
│         └────────── `ROD_v1.1.csv.zst`     # Assinibone features CSV
├── meta/             # SRA Meta-data
│   └─── `SRA-metadata.parquet`              # SRA Run Info and Metadata
│   └─── `ROD_v1.1_dotbracket.tsv.zst`       # RNAfold MFE and dotbracket
│   └─── `ROD_dust_masked_gt25pct.labels`    # Low-complexity contigs blacklist
└─────── README.md    # This README
```

```{bash}
# Assiniboine Bucket: s3://assiniboine/

## List the bucket
aws s3 ls s3://assiniboine/fa/

## AWS CLI Download
aws s3 cp s3://assiniboine/fa/control/obelisk_zheludev.fa ./

## WGET Download
wget https://s3.amazonaws.com/assiniboine/fa/control/obelisk_zheludev.fa

wget https://s3.amazonaws.com/assiniboine/fa/rod/ROD-1K_v1.1.fa.zst

```

### Notes
```{bash}
## `ROD_v1.1.reorf.zst`
## reorf calculation was performed with custom circular-aware ORF caller
## continuous ORFs are annotated with the following codes
# Ce     Continuous even (meaning ORF is multiple of 3 nt), has START
# Cem    Continuous even (meaning ORF is multiple of 3 nt), no START
# Co     Continuous odd (meaning ORF is not multiple of 3 nt so wraps around >1 times), has START
# Com    Continuous odd (meaning ORF is not multiple of 3 nt so wraps around >1 times), no START
```
```{bash}
# Low-complexity blacklist command
./bin/dustmasker -in uniques.fa -hard_masking -outfmt fasta -out ROD_dust_masked_gt25pct.labels
```


```{bash}
# File contents of s3://assiniboine/fa/control/
aws s3 ls s3://assiniboine/fa/control/
2026-11-03 21:25:49    2937889 ambivirus_SerratusID90.fa
2026-11-03 21:25:49       5595 ambivirus_features_gb260921.csv
2026-11-03 21:25:49      82544 ambivirus_gb260921.fa
2026-11-03 21:25:49    2725626 anellovirus_features_gb260921.csv
2026-11-03 21:25:49   25154568 anellovirus_gb260921.fa
2026-11-03 21:25:49    2031356 avsunviroid_features_gb260921.csv
2026-11-03 21:25:49    3456545 avsunviroid_gb260921.fa
2026-11-03 21:25:49    2849818 circovirus_features_gb260921.csv
2026-11-03 21:25:49   20076944 circovirus_gb260921.fa
2026-11-03 21:25:49    5767168 geminivirus_features_gb260921.csv
2026-11-03 21:25:49   55189040 geminivirus_gb260921.fa
2026-11-03 21:25:49     625166 genomovirus_features_gb260921.csv
2026-11-03 21:25:51    4372926 genomovirus_gb260921.fa
2026-11-03 21:25:51    4652567 hepadnavirus_features_gb260921.csv
2026-11-03 21:25:53   49820415 hepadnavirus_gb260921.fa
2026-11-03 21:25:55    2589423 humancirc_features_gb260921.csv
2026-11-03 21:25:57  268123564 humancirc_gb260921.fa
2026-11-03 21:25:57    1039565 nanovirus_features_gb260921.csv
2026-11-03 21:25:59    4487110 nanovirus_gb260921.fa
2026-11-03 21:25:59    4402505 obelisk_features_zheludev.csv
2026-11-03 21:26:02   15077004 obelisk_zheludev.fa
2026-11-03 21:26:02    2413326 papillomavirus_features_gb260921.csv
2026-11-03 21:26:06   46750263 papillomavirus_gb260921.fa
2026-11-03 21:26:13      21223 plasmidsub7000_features_gb260921.csv
2026-11-03 21:26:13   62604994 plasmidsub7000_gb260921.fa
2026-11-03 21:26:13     924898 polyomavirus_features_gb260921.csv
2026-11-03 21:26:14   14760466 polyomavirus_gb260921.fa
2026-11-03 21:26:14    1720283 pospiviroid_features_gb260921.csv
2026-11-03 21:26:21    3258006 pospiviroid_gb260921.fa
2026-11-03 21:26:24        847 retroviroid_features_gb260921.csv
2026-11-03 21:26:25     278567 ribozyvirus_features_gb260921.csv
2026-11-03 21:26:26    1613206 ribozyvirus_gb260921.fa
2026-11-03 21:26:27     277126 satellite_features_gb260921.csv
2026-11-03 21:26:27     932092 satellite_gb260921.fa
2026-11-03 21:26:27       2536 zetavirus_features_gb260921.csv
2026-11-03 21:26:28       4078 zetavirus_gb260921.fa
```


## Pipeline

```
./workflow/

 0  fetch the source data
 1  Kraken2 filter          drop every record matching reference database
 2  circular overlap        label how each record closes; trim the 30 nt overlap
 3  length filter           keep [200 to 6000] nt contigs
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
