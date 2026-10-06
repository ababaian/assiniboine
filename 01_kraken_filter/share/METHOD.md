# Kraken2 filter -- method and caveats

**Purpose.** Discard circular contigs matching anything already in the
reference databases, so downstream structure screening only sees sequences
nothing could name.

**Input.** Logan v1.1 selfloops, every circular contig assembled from SRA
(Feb 2025 run): 900,042,456 records, 331 GB uncompressed. One record per
circle per sequencing run.
Source: `s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst`

**Database.** core_nt, built October 2025, 2,388,823 taxonomy nodes, 340 GB
index. Path on watson: `/watson/rnalab/js/resource_files/k2_core_nt`
(owned by `js`, world-readable).

**Command.** Kraken2 2.17.1, `--confidence 0.1 --memory-mapping`, 10 concurrent
processes x 32 threads over 21 input shards. 16 minutes wall.

    kraken2 --db k2_core_nt --memory-mapping --threads 32 --confidence 0.1 \
            --unclassified-out unclass_part_NNN.fa --output /dev/null \
            --report report_part_NNN.txt part_NNN

**Result.**

    processed      900,042,456
    classified     305,036,299   33.89%   discarded
    unclassified   595,006,157   66.11%   kept for screening

**Verification.** The processed count equals an independent `grep -c '^>'` of
the source (900,042,456), and a separate recount of the output FASTAs returns
595,006,157 -- both match exactly, so no records were dropped or double-counted.

## Caveats worth stating out loud

1. **"Unclassified" means core_nt could not name it, not that it is novel.**
   A circle fails to classify if it is genuinely new, if it is too short or
   low-complexity to carry 10% supporting k-mers, or if its source organism is
   simply absent from core_nt. All three land in the same 66%.

2. **`--confidence 0.1` is a deliberate choice.** A read is left unclassified
   unless at least 10% of its k-mers support one taxonomic path. Higher
   confidence keeps more sequences (fewer get named); lower discards more.
   This threshold was not tuned against a labelled set.

3. **Short sequences are at a structural disadvantage.** Mean length is 243 nt
   and 96.9% are under 500 nt, so there are few k-mers per circle to accumulate
   evidence from. Expect the unclassified fraction to be inflated for the
   shortest sequences relative to what a longer contig would achieve.

4. **Input is deduplicated within each sequencing run but not across runs.**
   Of 194,324 duplicate groups in a 5M-record sample, 100% spanned more than
   one run and none were inside a single run. A circle recovered from 50 runs
   is 50 records, so read counts here are not independent observations.

5. **Rare targets are rare in the classified fraction too.** Of the named
   305M, only 693,256 are viral, and the hunted classes barely register
   (Pospiviroidae 12,961; Ribozyviria 54). That is the argument for screening
   the unclassified remainder, not evidence about what is in it.
