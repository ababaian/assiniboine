# model -- the rodnotrod classifier

The model that stage 4 ([`04_rod_screen/`](../04_rod_screen/)) uses to label
every circle `rod` or `not_rod`. Rod means rod-like: the long, highly
base-paired, little-branched fold of viroids, ribozyviruses, obelisks and
similar agents.

It is a scikit-learn `RandomForestClassifier` (500 trees,
`class_weight="balanced"`, `random_state=0`) wrapped in a `ClassifierBundle`
from `Lebowski/Scripts/circrna_classify.py`. It takes **31 numeric features**
per circle and returns a class and a confidence (the forest's vote share for
the winning class).

## Where it is

Public, no credentials needed:

    s3://petadex/circs-results/model/model.pkl               # 15.3 MB, the trained bundle
    s3://petadex/circs-results/model/lebowski_20261002.tar.gz  # model + scripts + CMs + training tables
    s3://petadex/circs-results/model/MANIFEST.md5

    aws s3 ls s3://petadex/circs-results/model/ --no-sign-request

Locally on watson it is `Lebowski/rodnotrod_model/`, which is gitignored: the
upstream code and model come from a collaborator's drive, so this repo
documents them and does not carry them.

Loading it needs `Lebowski/Scripts/` on `sys.path` (the pickle references
`circrna_classify`) and scikit-learn **1.9.1**, which `env/make_env.sh` pins.

## Features

Four sources. Each circle is folded and searched first, and the results are
reduced to these numbers.

| source | tool | features used |
|---|---|---|
| Composition | sequence only | `gc_content`, `keto_bias` |
| ORF | `getorf` on the doubled circle | `orf_density_100aa_per_kb`, `orf_density_30aa_per_kb` |
| Structure | `RNAfold --circ` | `mfe_per_nt`, `frac_paired`, `hairpin_density`, `n_stems_density`, `max_stem_len`, `mean_stem_len`, `n_multiloops_density`, `branching_degree`, `mean_hairpin_loop_size` |
| Ribozyme | `cmsearch` against `dvr5.cm` and 18 Rfam ribozyme CMs | `n_ribozymes`, `n_ribozymes_plus`, `n_ribozymes_minus`, `n_dvr5`, per-family counts (`n_hammerhead`, `n_hdv`, `n_twister`, `n_pistol`, `n_hatchet`, ...), and locus bookkeeping (`paired`, `same_family_paired`, `n_ambiguous_loci`, `n_corroborated_loci`) |

The output tables carry more columns than the model reads. `length`,
`periodicity_ratio`, `tandem_repeat_flag` and `orf_coverage_fraction` are
computed and sit in the training table, but are **not** among the model's 31
`feature_cols`.

`mfe_per_nt` is `RNAfold`'s MFE in kcal/mol divided by the contig length
(`run_pipeline.py:316`), so it is a plain division and the MFE is recoverable
as `mfe_per_nt * length`. A missing MFE is recorded as 0.

## What the model relies on

Impurity importance from the fitted forest; it sums to 1.

| source | share |
|---|---|
| Structure | 81.8% |
| Composition | 11.7% |
| ORF | 4.7% |
| Ribozyme | 1.8% |

Top features:

| feature | source | share |
|---|---|---|
| `mfe_per_nt` | Structure | 17.8% |
| `hairpin_density` | Structure | 15.6% |
| `frac_paired` | Structure | 11.1% |
| `n_multiloops_density` | Structure | 11.0% |
| `gc_content` | Composition | 10.7% |
| `n_stems_density` | Structure | 9.2% |
| `mean_hairpin_loop_size` | Structure | 6.6% |
| `branching_degree` | Structure | 5.9% |
| `orf_density_100aa_per_kb` | ORF | 3.2% |
| `orf_density_30aa_per_kb` | ORF | 1.6% |
| `keto_bias` | Composition | 1.0% |

The ribozyme block (18 features) is 1.8% in total: `n_dvr5` 0.51%,
`n_ribozymes` 0.46%, `n_ribozymes_plus` 0.30%, `n_ribozymes_minus` 0.26%, and
the rest at or near zero. A rod call therefore comes almost entirely from fold
shape. Ribozyme hits are reported alongside the call, and the shortlist in
`05_results/` ranks on them, but they hardly influence the call itself.

Read these as a guide, not a ranking. Impurity importance splits credit among
correlated features, and the four structure features near the top are likely
correlated, so their individual order is soft; the per-source totals are the
steadier numbers. Ribozyme counts are zero for most circles, which also holds
their importance down.

## Training and performance

- 29,739 labelled sequences: 20,344 `not_rod`, 9,395 `rod`
  (`Lebowski/rodnotrod_model/combined_features.csv`, built from the per-class
  tables in `Lebowski/clean_csv_folder/`). The class mix covers viroids,
  ribozyviruses, obelisks, ambiviruses, DNA-virus genomes, host circRNAs from
  six species and scrambled controls. The mapping of those classes onto
  `rod` / `not_rod` is made in the upstream training scripts and is not
  documented in this repo.
- 5-fold stratified cross-validation: accuracy and F1 about 1.00. Errors are
  54 `not_rod` called rod and 39 `rod` called not_rod.
- Label-shuffle baseline (10 permutations): accuracy about 0.60, macro-F1
  about 0.50, which is chance. The real score is far above it.
- Classes with very few training sequences (retroviroids have one) will be
  predicted poorly.

The cross-validated score says the training classes separate cleanly on these
features. It does not say how precise the calls are on the unknown circles in
the SRA, which is what the screen runs it on.

## Confidence

The bundle stores `confidence_floor = 0.5`. Training calibrates a floor from
held-out scrambled controls, but no scrambled-control rows reached the final
fit, so it fell back to the 0.5 default. With two classes the winning vote
share is always at least 0.5, so `below_confidence_floor` in the screen output
can never be True. Threshold on `confidence` instead. See
[`04_rod_screen/README.md`](../04_rod_screen/README.md).

## Provenance

Upstream code, CMs and the model are from the Logan_Circs drive, copied
2026-10-02. Scripts that built it: `combine_and_train.py`, `clean_features.py`
and `circrna_classify.py` in `Lebowski/Scripts/`. `Lebowski/notes.txt` is the
author's own orientation.
