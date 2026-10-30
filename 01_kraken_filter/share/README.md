# Kraken2 filter results -- share bundle

Four files, ~3 MB. Start with `SUMMARY_k2_filter.txt`.

| file | what it is |
|---|---|
| `SUMMARY_k2_filter.txt` | the headline numbers, 4 lines |
| `COMPOSITION.txt` | what the circles turned out to be, human-readable |
| `combined_report.tsv` | all 74,684 taxa, the 21 per-batch reports merged and summed |
| `METHOD.md` | exactly what was run, and 5 caveats to read before quoting any number |

## In one paragraph

Every circular contig Logan assembled from the SRA (900,042,456 of them) was
matched against core_nt with Kraken2 at confidence 0.1. 305,036,299 (33.89%)
matched something known and were discarded -- overwhelmingly host genomes, led
by human (79.1M) and mouse (49.1M). The remaining 595,006,157 (66.11%) could
not be named and are the candidate set now being screened for rod-like
structure and ribozymes. Counts were verified twice against independent
recounts of both input and output.

## `combined_report.tsv` columns

    pct_of_total   percentage of all 900,042,456 circles
    clade_reads    circles assigned to this taxon OR anything beneath it
    direct_reads   circles assigned to exactly this taxon
    rank           Kraken rank code (U unclassified, R root, D domain, K kingdom,
                   P phylum, C class, O order, F family, G genus, S species)
    taxid, name    NCBI taxon

Use `clade_reads` for "how much of the data is X", `direct_reads` for "what was
pinned at exactly this level". They are not interchangeable: `cellular
organisms` has 256.7M clade reads but only 7.4M direct.

## The full outputs, if anyone needs them

Not in this bundle -- 174 GB. On watson:

    /watson/rnalab/dzhu/k2-circ-runs/01_kraken_filter/unclassified/   # 21 FASTA, the kept circles
    /watson/rnalab/dzhu/k2-circ-runs/01_kraken_filter/reports/        # the 21 unmerged reports
    /watson/rnalab/dzhu/k2-circ-runs/01_kraken_filter/README.md       # full method + benchmarks

The screening reads a length-filtered version of these circles, 200 to 6000 nt,
produced by `../../02_length_split/`. The October 2026 run additionally
deduplicated it to 545,483,299 records; that stage has since been dropped,
because assembly does not fix where a circle starts so exact matching missed
most duplicates, and because one record per circle per run is the unit of
observation worth keeping.
