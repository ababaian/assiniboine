# scripts: side analyses and helpers

Nothing here is part of the screen. These are the tools used to measure the
decisions the pipeline makes, and helpers for setting up and trying it out.
All of them need the package installed (`pip install -e .`).

| script | what it does |
|---|---|
| `scan_overlap.py` | measures the terminal overlap length and checks the closure classes on a selfloops FASTA; the evidence behind stage 2 |
| `length_histogram.py` | length distribution of FASTA files in the bands the stage 3 bounds fall in |
| `ops/check_dependencies.sh` | reports which tools, databases and bundles are present |
| `ops/make_example_data.py` | writes small synthetic inputs of the right shape, for stages that cannot run without large external resources |
| `ops/run_example.sh` | runs the whole pipeline on synthetic data in seconds, standing in for Kraken2 and the classifier |

Start with `ops/run_example.sh`: it leaves a complete miniature run under
`work/example/` to explore.
