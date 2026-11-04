# Stage 6: the record manifest and checksums

    ./workflow/06_package/package_run.sh

Writes `record_manifest.tsv.zst`: one row per source record, in source
order, saying what stages 1 to 3 did with it (classified or not, taxid,
closure class, which length bin it ended in). Then proves that the source
archive plus this manifest rebuild every stage 1 to 3 file byte for byte.
After that the hundreds of gigabytes of intermediate FASTA need not be kept
or shared; `assiniboine manifest rebuild` recreates them on demand.

`MD5SUMS` lists checksums of the files a run keeps: the Kraken2 calls and
reports, the screen results, the stage 5 tables, the manifest, and the
dot-bracket structures if stage 7 has run. Check them later with
`cd work && md5sum -c 06_package/MD5SUMS`.

Both steps stream the whole source once in a single process.
