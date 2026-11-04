# Dependencies

## Command-line tools

All installed by `environment.yml`. Versions are those of the November
2026 run; later versions should behave the same unless noted.

| tool | version used | stage | role |
|---|---|---|---|
| `zstd` | 1.5 | 1, 6, 7 | the archive, the Kraken2 calls and the manifest are Zstandard-compressed |
| `aws` (awscli) | 2 | 0 | fetches the archive from S3 without credentials |
| `kraken2` | 2.17.1 | 1 | classifies each record against the database |
| `getorf` (EMBOSS) | 6.6 | 4 | finds ORFs, on the doubled sequence |
| `RNAfold` (ViennaRNA) | 2.7.2 | 4, 7 | folds each record as a circle |
| `cmsearch`, `cmpress` (Infernal) | 1.1 | 4 | searches the ribozyme covariance models |
| `split`, `md5sum`, `xargs` (coreutils, findutils) | any | several | cutting files, checksums, parallelism |

## Python

The `assiniboine` package needs Python 3.11 or newer and nothing else.

The external classifier needs `pandas`, `numpy`, `scipy` and
`scikit-learn` **exactly 1.9.1**: its model is a pickled scikit-learn
object stamped with that version, and another version may unpickle to
something that behaves differently, or not at all. After any change to the
environment, check with `python -c "import sklearn; print(sklearn.__version__)"`.

## External data

### The source archive

Logan's v1.1 selfloops archive, every circular contig Logan assembled from
the SRA in its February 2025 run:

```
s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst
```

89,258,393,740 bytes, 900,042,456 records, 331 GB decompressed, one
Zstandard frame (so decompression is single-threaded, about ten minutes).
Public, no credentials. The format is in `docs/data_dictionary.md`.

### A Kraken2 database

Stage 1 needs one, set by `[kraken] database`. The published runs used a
core_nt index built in October 2025 (340 GB, 2.4 million taxonomy nodes).
Any Kraken2 database works; it defines what "already known" means for the
run.

### The classifier bundle

The rod classifier is a collaborator's pipeline, kept outside this
repository because its provenance is theirs. It is public:

```
s3://petadex/circs-results/model/lebowski_20261002.tar.gz   16 MB
s3://petadex/circs-results/model/MANIFEST.md5
s3://petadex/circs-results/model/model.pkl                  the model alone, 15 MB
```

`docs/installation.md` has the fetch commands. Inside, stage 4 uses:

| path | what it is |
|---|---|
| `Scripts/run_pipeline.py` | the entry point: FASTA in, feature and call CSV out, in batches |
| `Scripts/fold.py`, `prop-orf.py`, `ribozyme_screen.py`, `circrna_classify.py` | the RNAfold, getorf and cmsearch wrappers and the feature code it imports |
| `rodnotrod_model/model.pkl` | the random forest, md5 `b2e052da3e88d1802a5ed71ae34a8b9c` |
| `CM/dvr5.cm` | the in-house ribozyme covariance model |
| `CM/RF*.cm` | the 18 Rfam ribozyme models (RF00008, RF00094, RF00163, RF00173, RF00498, RF00502, RF00617, RF02275, RF02276, RF02277, RF02359, RF02684, RF03059, RF03152, RF03154, RF03160, RF04190, RF04191) |

The bundle also holds the training tables and scripts
(`combine_and_train.py`, `clean_features.py`) and the author's notes.
`docs/methods.md` describes what the classifier computes.

Two properties of the classifier shape how stage 4 calls it. It rebuilds
and re-indexes its combined Rfam library at every start, so each chunk
gets a private cache directory seeded with the `RF*.cm` files. And it
reports success even when `RNAfold` stopped early, so stage 4 counts the
rows it wrote.
