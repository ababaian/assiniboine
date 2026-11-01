# Step 1 tables: what each one contains

These three tables hold **counts**, not individual records. None of them has one row
per sequence. They summarise the 305,036,299 records Kraken2 classified, using its
reports, so they need no sequences.

| Table | One row is | Rows | Answers |
|---|---|---|---|
| `classified_taxa.csv` | one taxon, such as a species or family | 74,683 | What were the classified records? |
| `target_taxa.csv` | one of six clades of interest | 6 | How many known viroid-like and small circular records were removed? |
| `parts.csv` | one of the 21 input parts | 21 | How did each part split? Does each one add up? |

## classified_taxa.csv

| taxid | name | rank | records_in_clade | records_assigned_here | pct_of_classified | lineage (shortened) |
|---|---|---|---|---|---|---|
| 1 | root | R | 305,036,299 | 47,510,836 | 100.000000 | root |
| 2759 | Eukaryota | D | 232,188,594 | 6,126,194 | 76.118349 | root; cellular organisms; Eukaryota |
| 9606 | Homo sapiens | S | 79,072,262 | 79,072,262 | 25.922247 | ...Metazoa; ...Homo sapiens |
| 2 | Bacteria | D | 17,018,268 | 1,013,754 | 5.579096 | root; cellular organisms; Bacteria |
| 185751 | Pospiviroidae | F | 12,961 | 79 | 0.004249 | root; Viruses; Viruses incertae sedis; Pospiviroidae |
| 73494 | Apscaviroid fossulamali | S | 16 | 16 | 0.000005 | ...Pospiviroidae; Apscaviroid; Apscaviroid fossulamali |

| Column | Meaning |
|---|---|
| `taxid` | NCBI taxonomy ID |
| `name` | NCBI taxon name |
| `rank` | Level in the tree: `R` root, `D` domain, `K` kingdom, `F` family, `G` genus, `S` species. A number means a level below that one, so `R1` sits under `R` |
| `records_in_clade` | Records assigned to this taxon **plus everything below it** |
| `records_assigned_here` | Records Kraken2 stopped at **exactly** this taxon |
| `pct_of_classified` | `records_in_clade` as a percentage of 305,036,299 |
| `lineage` | Path from root to this taxon, separated by `;` |

**The two count columns differ like this.** Pospiviroidae has 12,961 records in total,
but only 79 stopped at family level. The other 12,882 went to a genus or species inside
the family. Human has the same number in both columns because nothing sits below it in
this table.

**Root is a real assignment.** Kraken2 assigns a record to the lowest point that fits
its matches, so 47,510,836 records match too broadly to place below root. They count as
classified and were dropped, but this table can't say what they are.

**Do not add up `records_in_clade`.** Each record counts at every level above it. Add
`records_assigned_here` instead, which totals 305,036,299.

## target_taxa.csv

The same columns as `classified_taxa.csv`, cut down to six clades.

| taxid | name | rank | records_in_clade | records_assigned_here | pct_of_classified |
|---|---|---|---|---|---|
| 185751 | Pospiviroidae | F | 12,961 | 79 | 0.004249 |
| 1910928 | Genomoviridae | F | 5,104 | 1,845 | 0.001673 |
| 687329 | Anelloviridae | F | 2,931 | 1,334 | 0.000961 |
| 39724 | Circoviridae | F | 2,832 | 127 | 0.000928 |
| 185752 | Avsunviroidae | F | 219 | 0 | 0.000072 |
| 2842242 | Ribozyviria | R2 | 54 | 0 | 0.000018 |

Read `records_in_clade` here. These are records Kraken2 could already name, so they
were removed at step 1 and never reached the rod screen. A 0 in `records_assigned_here`
means every record went to a lower level, not that none were found.

## parts.csv

The source was split into 21 parts of up to 45,000,000 records each.

| part | records | classified | unclassified | kout_bytes | classified_fa_bytes |
|---|---|---|---|---|---|
| part_000 | 45,000,000 | 16,810,987 | 28,189,013 | 774,951,530 | 2,148,727,203 |
| part_001 | 45,000,000 | 21,640,421 | 23,359,579 | 833,660,688 | 2,418,453,402 |

| Column | Meaning |
|---|---|
| `part` | Input part |
| `records` | Records in the part, `classified` + `unclassified` |
| `classified` | Records Kraken2 named, which were dropped |
| `unclassified` | Records it could not name, which go on to step 2 |
| `kout_bytes` | Compressed size of the part's per-record calls |
| `classified_fa_bytes` | Compressed size of the part's classified sequences |

Across all 21 parts, `records` adds up to 900,042,456.
