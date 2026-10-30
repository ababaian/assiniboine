#!/usr/bin/env bash
# Environment for run_pipeline.py: ViennaRNA (RNAfold), Infernal (cmsearch),
# EMBOSS (getorf) and the Python stack. scikit-learn is pinned to 1.9.1 to
# match the version rodnotrod_model/model.pkl was written with.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
source /opt/miniconda3/etc/profile.d/conda.sh

rm -f "$ROOT/ENV.DONE" "$ROOT/ENV.FAILED"

# An if/else rather than `&& touch DONE || touch FAILED`: in the chain form a
# failing touch flips the verdict and marks a good build failed.
if conda create -y -n circpipe -c conda-forge -c bioconda \
       python=3.12 'scikit-learn==1.9.1' pandas numpy scipy zstandard \
       viennarna infernal emboss; then
    touch "$ROOT/ENV.DONE"
else
    touch "$ROOT/ENV.FAILED"
    exit 1
fi
