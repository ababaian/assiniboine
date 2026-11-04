# Data dictionary

Every file the pipeline reads or writes, and every column. Paths are under
the work directory. The record id is the same in every file, so any two can
be joined on it.

## The source record

```
>SRR12604050_704504_circle_704504 ka:f:4.900 L:-:704504:- L:+:704504:+
ACGT...
```

| field | meaning |
|---|---|
| `SRR12604050_704504_circle_704504` | the record id: SRA run, unitig number, and `circle` |
| `SRR12604050` | the SRA run the contig was assembled from (the id up to its first `_`) |
| `ka:f:4.900` | mean k-mer abundance, a coverage estimate |
| `L:-:704504:- L:+:704504:+` | GFA links: the unitig joins to itself. The strand signs give the closure class (`docs/methods.md`) |

Every record is exactly two lines, header then unwrapped sequence, and the
pipeline keeps it that way. The archive is deduplicated within each SRA
run only: a circle recovered from fifty runs is fifty records.

## Stage 1: `01_kraken_filter/`

| file | contents |
|---|---|
| `unclassified/part_NNN.fa` | the records Kraken2 could not name, unchanged |
| `calls/part_NNN.tsv.zst` | one line per record of the part, in order: `C` or `U`, id, taxid (0 for `U`), sequence length. Kraken2's k-mer hit list is dropped |
| `reports/part_NNN.txt` | Kraken2's report: per taxon, the records assigned to it and its clade |
| `counts/part_NNN.tsv`, `summary.txt` | `classified` and `unclassified` counts |

## Stage 2: `02_circular_overlap/`

`labelled/part_NNN.fa` holds every input record with the header extended:

```
>SRR12604050_704504_circle_704504 ka:f:4.900 L:-:704504:- L:+:704504:+ ovl:circular trim:30
```

| tag | values |
|---|---|
| `ovl:` | `circular`, `hairpin` or `unmatched` |
| `trim:` | bases removed from the end: the overlap length for `circular`, 0 otherwise |

Sequences are upper-cased. Anything that rewrites headers to bare ids
destroys both the `L:` fields and this label.

## Stage 3: `03_length_filter/`

`in_range/`, `too_short/` and `too_long/` each hold a `part_NNN.fa` per
part, records unchanged from stage 2. `summary.txt` gives the three counts.

## Stage 4: `04_rod_screen/`

`chunks/chunk_NNN.fa` are the in-range records re-cut. `results/chunk_NNN.csv`
has one row per record of the chunk, in the same order, with 48 columns as
the classifier writes them:

| column | meaning |
|---|---|
| `sample_name` | the record id |
| `length` | nt, as screened (after the trim) |
| `predicted_class` | `rod` or `not_rod` |
| `confidence` | the forest's vote share for the winning class, 0.5 to 1 |
| `below_confidence_floor` | always False; the floor is 0.5 and the winner is at least that |
| `gc_content`, `keto_bias` | composition, in percent |
| `orf_density_100aa_per_kb`, `orf_density_30aa_per_kb` | ORFs longer than 100 and 30 aa per kb, found on the doubled sequence |
| `mfe_per_nt` | RNAfold's minimum free energy in kcal/mol divided by length |
| `frac_paired` | fraction of bases paired in the MFE structure |
| `hairpin_density`, `n_stems_density`, `n_multiloops_density` | hairpins, stems and multiloops per 100 nt |
| `max_stem_len`, `mean_stem_len` | stem lengths in base pairs |
| `branching_degree` | mean branches per multiloop |
| `mean_hairpin_loop_size` | nt |
| `n_ribozymes`, `n_ribozymes_plus`, `n_ribozymes_minus` | ribozyme loci, total and per strand |
| `n_ambiguous_loci` | loci where models of different families overlap |
| `n_corroborated_loci` | loci where the dvr5 and an Rfam model agree |
| `paired` | ribozymes on both strands (True/False) |
| `same_family_paired` | the same family on both strands |
| `n_hammerhead`, `n_hairpin`, `n_hdv`, `n_varkud_satellite`, `n_glms`, `n_twister`, `n_twister_sister`, `n_pistol`, `n_hatchet`, `n_dvr5`, `n_other` | loci per family |
| `tandem_repeat_flag` | the sequence looks like a tandem repeat |
| (seven repeats) | `n_ribozymes` through `same_family_paired` appear a second time with the same values |
| `ribozyme_families` | families found, `;`-separated, or `NONE` |
| `strands_present` | `+`, `-`, `+;-` or `NONE` |
| `sources_detected` | `dvr5`, `Rfam`, both, or `NONE` |
| `combination_detail` | each locus with position, score, E-value and source; contains commas inside quotes |

The 31 feature columns the model reads are those from `gc_content` through
`n_other`, except that `length`, `tandem_repeat_flag` and the text columns
are reported but not used.

## Stage 5: `05_results/`

`rods.fa` holds every rod's sequence as screened (upper case, overlap
trimmed) under its original Logan selfloops header, in `rods.csv` row order.

`rods.csv`, `rods_with_ribozyme.csv` and `shortlist.csv` hold no sequences
and share these columns:

| column | meaning |
|---|---|
| `sample_name` | the record id |
| `run` | the SRA run |
| `closure` | the stage 2 class |
| the 40 remaining screen columns | as above, each once |

`shortlist.csv` has `tier` (1 or 2) as its first column. `summary.txt`
gives the counts, including how many tier 2 candidates the row cap
excluded.

## Stage 6: `06_package/`

`record_manifest.tsv.zst`, one row per source record in source order:

| column | meaning |
|---|---|
| `id` | the record id |
| `run` | the SRA run |
| `length` | source length in nt, before any trim |
| `kraken` | `C` classified (dropped at stage 1), `U` unclassified (kept) |
| `taxid` | Kraken2 taxon id for `C`, 0 for `U` |
| `closure` | `circular`, `hairpin` or `unmatched`, by the stage 2 rule; applied here for `C` records, which never reached stage 2 |
| `stage` | `classified`, `too_short`, `in_range` or `too_long`: where the record ended |

`MD5SUMS` lists checksums of the kept files, relative to the work
directory.

## Stage 7: `07_dotbracket/`

`rods_dotbracket.tsv.zst`, in `rods.csv` order:

| column | meaning |
|---|---|
| `sample_name` | the record id |
| `length` | nt |
| `mfe` | minimum free energy, kcal/mol |
| `dot_bracket` | the MFE structure, one character per base: `(` and `)` paired, `.` unpaired |
