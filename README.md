# Logan selfloops rod-like circle screen

Screens every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them.

This repo holds code and methods only. All data lives in S3, see
[Data](#data). A whitelist `.gitignore` makes it hard to commit data by
accident.

## Result

900,042,456 circles, 595,006,157 unnamed by core_nt, 545,483,299 screened,
**25,222,331 called rod**. Of those, **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands**, the rolling-circle hallmark. The practical
starting point is a ranked shortlist of 2,056, whose top tier is 56 circles.

## Pipeline

Each stage has a folder with its runner script and a README covering counts,
method and gotchas.

| stage | folder | in, out |
|---|---|---|
| 0. fetch | [`00_source/`](00_source/) | 900,042,456 circles (83 GiB zst) |
| 1. drop the known | [`01_kraken_filter/`](01_kraken_filter/) | 900,042,456 to 595,006,157 |
| 2. split at 6000 nt | [`02_length_split/`](02_length_split/) | 594,734,382 plus 271,775 |
| 3. exact dedup | [`03_dedup/`](03_dedup/) | 545,483,299 |
| 4. rod screen | [`step2/`](step2/) | 545,483,299 scored rows |
| env | [`06_env/`](06_env/) | conda env `circpipe` |

Stage 4 is called `step2/` because that is its name in the original plan.
Renaming it mid-run would have broken the workers.

**1. Kraken2 filter.** core_nt at `--confidence 0.1`, keeping everything
unclassified. 10 processes of 32 threads share one mmap'd 340 GB index through
the page cache, so RAM cost is one copy, not ten.

**2. Length split.** A bug workaround, not a filter: it keeps 99.95%. RNAfold
stops rather than skips when handed an oversized circle, so one long record
silently truncates the rest of its batch.

**3. Exact dedup.** GNU sort rather than `dedup_fasta.py`, which is single-core
Python with Booth's algorithm per record and would take days at 595M. Keeps a
reversible map from every dropped id to the representative kept.

**4. Rod screen.** Per circle: `getorf` on the doubled sequence so ORFs
crossing the junction are found, `RNAfold --noPS --circ`, `cmsearch` against an
in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a 31-feature random forest.

## Commands

Everything below runs from the repo root. Each stage also has a wrapper script
that does the same work resume-safely and in parallel; the wrapper is named
under each block. The wrappers hardcode
`ROOT=/watson/rnalab/dzhu/k2-circ-runs`, so edit that line before running them
elsewhere.

Two prerequisites are not in this repo:

- **`Lebowski/`**, the upstream pipeline (`run_pipeline.py`, `fold.py`,
  `prop-orf.py`, `ribozyme_screen.py`, `circrna_classify.py`), the trained
  `rodnotrod` model and the CM files. These come from a collaborator's drive
  and are theirs to publish.
- **a Kraken2 core_nt database.** The run used
  `/watson/rnalab/js/resource_files/k2_core_nt`, 340 GB, built October 2025.

### Environment

scikit-learn is pinned because `model.pkl` carries `_sklearn_version 1.9.1`.
Another version risks silently different predictions.

```bash
conda create -y -n circpipe -c conda-forge -c bioconda \
    python=3.12 'scikit-learn==1.9.1' pandas numpy scipy zstandard \
    viennarna infernal emboss
source /opt/miniconda3/etc/profile.d/conda.sh && conda activate circpipe
```

Kraken2 lives in a separate env, `k2workflow` (kraken2 2.17.1, bracken 3.0.1).

Wrapper: `06_env/make_env.sh`

### 0. Fetch the source

```bash
aws s3 cp --no-sign-request --only-show-errors \
    s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst .

stat -c %s selfloops.v1.1.fa.zst    # must be 89258393740
```

Wrapper: `00_source/selfloops_download.sh` (retries 5 times, checks the size)

### 1. Kraken2 filter

Decompress and split into 21 plain-FASTA parts. 90,000,000 lines is 45,000,000
records per part, since the file is exactly 2 lines per record.

```bash
mkdir -p parts unclassified logs
zstd -dc selfloops.v1.1.fa.zst | split -a3 -d -l 90000000 - parts/part_
```

Warm the index into the page cache once, so the first workers do not fault it
in:

```bash
DB=/watson/rnalab/js/resource_files/k2_core_nt
cat $DB/hash.k2d > /dev/null
cat $DB/taxo.k2d > /dev/null
```

Classify one part. `--memory-mapping` is what lets concurrent processes share
the one 340 GB index:

```bash
part=parts/part_000
b=$(basename "$part")

kraken2 --db "$DB" --memory-mapping --threads 32 --confidence 0.1 \
        --unclassified-out "unclassified/unclass_$b.fa" \
        --output /dev/null --report "logs/report_$b.txt" \
        "$part"
```

`--confidence 0.1` leaves a circle unclassified unless 10% of its k-mers
support one taxonomic path. `--unclassified-out` is the output that matters:
the kept 66%. On a rerun, point `--output` at a real file rather than
`/dev/null`, otherwise the per-record taxonomic assignment is discarded and
which circle got which taxid is unrecoverable.

All 21 parts, 10 at a time:

```bash
ls parts/part_* | xargs -P10 -I{} sh -c '
  b=$(basename "$1")
  kraken2 --db "$DB" --memory-mapping --threads 32 --confidence 0.1 \
          --unclassified-out "unclassified/unclass_$b.fa" \
          --output /dev/null --report "logs/report_$b.txt" \
          "$1" > "logs/$b.log" 2>&1 && rm -f "$1"
' _ {}
```

Per-part counts land in `logs/part_*.log`; the taxonomy reports in
`logs/report_part_*.txt`.

Wrappers: `01_kraken_filter/k2_filter.sh` (split plus classify),
`01_kraken_filter/k2_classify.sh` (classify only, claims parts with an atomic
`mkdir` so several copies can run at once)

### 2. Split at 6000 nt

```bash
mkdir -p le6000 gt6000
part=unclassified/unclass_part_000.fa
b=$(basename "$part" .fa)

awk -v u="le6000/$b.fa" -v o="gt6000/$b.fa" '
  function flush(){ if (!h) return; print rec > (len <= 6000 ? u : o) }
  /^>/ { flush(); rec = $0; len = 0; h = 1; next }
       { rec = rec "\n" $0; len += length($0) }
  END  { flush() }' "$part"
```

All 21, 12 at a time:

```bash
ls unclassified/unclass_part_*.fa | xargs -P12 -I{} sh -c '
  b=$(basename "$1" .fa)
  awk -v u="le6000/$b.fa" -v o="gt6000/$b.fa" "
    function flush(){ if (!h) return; print rec > (len <= 6000 ? u : o) }
    /^>/ { flush(); rec = \$0; len = 0; h = 1; next }
         { rec = rec \"\n\" \$0; len += length(\$0) }
    END  { flush() }" "$1"
' _ {}
```

Wrapper: `02_length_split/lenfilter.sh`

### 3. Exact dedup

Flatten each part to `sequence <TAB> header`, so the sort key is the sequence
itself:

```bash
mkdir -p dedup tmpsort
export LC_ALL=C

ls le6000/*.fa | xargs -P12 -I{} sh -c '
  awk "/^>/ { if (h) print toupper(seq) \"\t\" hdr; hdr = substr(\$0,2); seq = \"\"; h = 1; next }
             { seq = seq \$0 }
       END   { if (h) print toupper(seq) \"\t\" hdr }" "$1" > dedup/$(basename "$1" .fa).tsv
' _ {}
```

Sort on the sequence, keep the first of each run of equal keys, map the rest.
`-S 200G --parallel=48` is sized for a 480-core box with the spill directory on
local disk:

```bash
sort -t$'\t' -k1,1 -S 200G --parallel=48 -T tmpsort dedup/*.tsv \
 | awk -F'\t' -v OFS='\t' '
     $1 != prev { print ">" $2 > "dedup_le6000.fa"; print $1 > "dedup_le6000.fa"
                  prev = $1; keptid = $2; kept++; next }
                { split($2, a, " "); split(keptid, b, " ")
                  print a[1], b[1] > "dedup_map.tsv"; dropped++ }
     END        { printf "kept %d\ndropped %d\n", kept, dropped > "/dev/stderr" }' \
   2> dedup_stats.txt
```

`dedup_map.tsv` maps every dropped id to the representative kept, so a hit can
be expanded back to every accession carrying that circle. Keep it. Verify the
output is sorted and duplicate-free:

```bash
awk 'NR%2==0' dedup_le6000.fa | sort -c -u    # exits 0
```

Rotations and reverse complements are not collapsed by this pass.

Wrapper: `03_dedup/dedup_exact.sh`

### 4. Rod screen

Chunk the deduped FASTA. 3,409,272 lines is 1,704,636 records, which gives the
320 chunks of the original run:

```bash
mkdir -p step2/chunks step2/results step2/logs step2/claims step2/rfam
split -a3 -d -l 3409272 dedup_le6000.fa step2/chunks/chunk_
```

Wrapper: `step2/make_chunks.sh`. Prefer it over the bare `split`. Defining a
new chunk set invalidates the previous run's `.done` markers and claim dirs,
and leaving those in place makes `step2_run.sh` skip every chunk and still
report success. The wrapper clears them, refuses to touch existing result
CSVs, and checks that every chunk begins at a header.

Seed a private Rfam cache for the chunk, then run the pipeline. `--circular`
treats every input as a circle, `-j 30` and `--cmsearch-cpu 30` set the folding
and cmsearch parallelism:

```bash
c=step2/chunks/chunk_000
b=$(basename "$c")

mkdir -p "step2/rfam/$b" && cp Lebowski/CM/RF*.cm "step2/rfam/$b"/

python3 Lebowski/Scripts/run_pipeline.py \
    -i "$c" -o "step2/results/$b.csv" \
    --lib-dir Lebowski/Scripts --circular -j 30 \
    --model Lebowski/rodnotrod_model/model.pkl \
    --dvr5-cm Lebowski/CM/dvr5.cm --cmsearch-cpu 30 \
    --rfam-cache-dir "step2/rfam/$b" --batch-size 50000
```

Then check that the output row count equals the input record count:

```bash
nin=$(grep -c '^>' "$c")
nout=$(( $(wc -l < "step2/results/$b.csv") - 1 ))
[ "$nout" -eq "$nin" ] || echo "TRUNCATED: $b in=$nin out=$nout"
```

That check is not optional. RNAfold handed an oversized circle warns, emits
nothing further and exits 0, so `run_pipeline.py` reports success on a
truncated chunk. The `--rfam-cache-dir` must also be private per worker,
because `ribozyme_screen.build_combined_rfam_library()` rewrites the combined
`.cm` and re-runs `cmpress` unconditionally, so two workers sharing a cache
collide and one dies.

The wrappers run 320 chunks 16 at a time, claim each with an atomic `mkdir`,
apply the row-count gate, and skip finished chunks on a restart. Safe to kill
and restart at any time.

```bash
./step2_run.sh          # 16 workers, -j30
./step2_run_extra.sh    # 4 workers, -j22, to add capacity alongside it
```

Monitoring:

```bash
ls step2/logs/*.done | wc -l                  # of 320
cat step2/results/*.csv | grep -vc '^sample'  # rows so far
cat step2/MISMATCH.txt                        # must stay absent
tail step2_run.log
```

Caveats that qualify the numbers are in
[`step2/share/METHOD.md`](step2/share/METHOD.md) and
[`01_kraken_filter/share/METHOD.md`](01_kraken_filter/share/METHOD.md). Read
them before quoting any result.

## Data

Nothing in this repo. Public, no credentials needed:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # stage 4 outputs

    aws s3 ls s3://petadex/circs-results/ --no-sign-request
    curl -O https://petadex.s3.amazonaws.com/circs-results/step2_rod_screen/shortlist.csv

Start with `shortlist.csv`. The 320 per-chunk result files, 129 GB and all 545M
rows, are not public. They are in `s3://petadex-tmp/circs-results/` and on
watson under `/watson/rnalab/dzhu/k2-circ-runs/`.
