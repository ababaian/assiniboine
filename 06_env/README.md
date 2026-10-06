# 06_env -- the conda environment

`run_pipeline.py` needs ViennaRNA, Infernal and EMBOSS, none of which were on
this machine, plus a Python stack. `make_env.sh` builds env `circpipe`:

    source /opt/miniconda3/etc/profile.d/conda.sh && conda activate circpipe

| item | what it is |
|---|---|
| `make_env.sh` | the build |
| `make_env.log` | conda's output |
| `ENV.DONE` | success marker |

Contents: python 3.12, **scikit-learn pinned to 1.9.1**, pandas, numpy, scipy,
zstandard, viennarna (RNAfold), infernal (cmsearch/cmpress), emboss (getorf).

The sklearn pin is not cosmetic: `Lebowski/rodnotrod_model/model.pkl` carries
`_sklearn_version = 1.9.1`, and loading it under a different version risks
silently different behaviour or an outright unpickling failure.

Was already present system-wide: `getorf` at `/usr/bin/getorf`. Kraken2 and
Bracken live in a separate env, `k2workflow` (kraken2 2.17.1, bracken 3.0.1).
