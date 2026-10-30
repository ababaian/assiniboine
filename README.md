# Logan selfloops rod-like circle screen

Screens every circular contig in the SRA for rod-like, ribozyme-bearing
circles: viroids, ribozyviruses, obelisks, ambiviruses and anything resembling
them.

This repo holds code and methods only. All data lives in S3, see
[Data](#data). A whitelist `.gitignore` makes it hard to commit data by
accident.

## Result

The numbers below are from the October 2026 run. **That run is not what the
commands here now describe.** It included an exact-deduplication stage, since
removed, and it had no 200 nt floor. A rerun will produce different totals.

900,042,456 circles, 595,006,157 unnamed by core_nt, 545,483,299 screened,
**25,222,331 called rod**. Of those, **46,432 carry a ribozyme** and **16,757
carry ribozymes on both strands**, the rolling-circle hallmark. The published
shortlist is 2,056 rows.

### What the 200 nt floor changes

Measured against that run's own output, so these are the records the floor
would have excluded:

| | count | share |
|---|---|---|
| rod calls | 25,222,331 | |
| rod under 200 nt | 12,487,733 | 49.51% |
| rod with a ribozyme | 46,432 | |
| of those, under 200 nt | 677 | 1.46% |
| shortlist rows under 200 nt | 0 | shortest is 309 nt |

The floor removes about half of all rod calls, 1.5% of the ribozyme-bearing
ones, and nothing from the shortlist. Nothing was called rod below 150 nt at
all. So it discards overwhelmingly the rod calls that carry no ribozyme, which
is the intended effect.

## Pipeline

Each stage has a folder with its runner script and a README covering counts,
method and gotchas. `step2/` and `step3/` keep the names they had in the
original plan; renaming them mid-run would have broken the workers.

| stage | folder | in, out |
|---|---|---|
| 0. fetch | [`00_source/`](00_source/) | 900,042,456 circles (83 GiB zst) |
| 1. drop the known | [`01_kraken_filter/`](01_kraken_filter/) | 900,042,456 to 595,006,157 |
| 2. keep 200 to 6000 nt | [`02_length_split/`](02_length_split/) | in-range, plus two parked sets |
| 3. rod screen | [`step2/`](step2/) | one scored row per circle |
| 4. reduce to tables | [`step3/`](step3/) | rod, rod with ribozyme, shortlist |
| env | [`06_env/`](06_env/) | conda env `circpipe` |

**1. Kraken2 filter.** core_nt at `--confidence 0.1`, keeping everything
unclassified. 10 processes of 32 threads share one mmap'd 340 GB index through
the page cache, so RAM cost is one copy, not ten.

**2. Length filter.** Two bounds with different reasons. The 6000 nt ceiling
is a bug workaround: RNAfold stops rather than skips when handed an oversized
circle, so one long record silently truncates the rest of its batch. The 200 nt
floor is a biological filter, since circles that short are below any known
viroid-like agent and dominated by assembly fragments. Out-of-range records go
to `lt200/` and `gt6000/` rather than being deleted, so either bound can be
revisited without re-running stage 1.

**3. Rod screen.** Per circle: `getorf` on the doubled sequence so ORFs
crossing the junction are found, `RNAfold --noPS --circ`, `cmsearch` against an
in-house `dvr5.cm` and 18 Rfam ribozyme CMs, then a 31-feature random forest.

**4. Reduce to tables.** Filter the per-chunk CSVs to rod calls, then to rod
calls carrying a ribozyme, then rank into a shortlist.

### No deduplication

An earlier version collapsed exact duplicate sequences, removing 8.28%. That
stage is gone, for two reasons:

- **Duplication is signal.** One record per circle per sequencing run is the
  input's own unit. A circle recovered from 50 runs is 50 observations, and
  collapsing them discards the prevalence information that makes a hit
  interesting.
- **It did not work anyway.** Assembly does not fix where a circle starts, so
  the same circle recovered twice usually differs by a rotation and is not an
  exact duplicate. Exact matching caught only the subset that happened to share
  a start position, which is why the figure was as low as 8.28%.

Keeping the duplicates costs little compute: on the old set, deduplication cut
record count by 8.28% but the sum of cubed lengths, which is what folding time
tracks, by only 3.4%. The duplicates were mostly short.

## Commands

Everything below runs from the repo root. Each stage also has a wrapper script
that does the same work resume-safely and in parallel; the wrapper is named
under each block. The wrappers hardcode
`ROOT=/watson/rnalab/dzhu/k2-circ-runs`, so edit that line before running them
elsewhere.

Thread counts, `-P` values, `-j30` and `sort -S 200G --parallel=48` are sized
for the 480-core machine the run used, not method parameters. Scale them down
before running on anything smaller, especially the sort buffer and the 10
concurrent Kraken2 processes, which assume the 340 GB index stays resident in
page cache.

Two prerequisites are not in this repo:

- **`Lebowski/`**, the upstream pipeline (`run_pipeline.py`, `fold.py`,
  `prop-orf.py`, `ribozyme_screen.py`, `circrna_classify.py`), the trained
  `rodnotrod` model and the CM files. These come from a collaborator's drive
  and are theirs to publish.
- **a Kraken2 core_nt database.** Build one with `kraken2-build` or obtain a
  prebuilt index. The run used `/watson/rnalab/js/resource_files/k2_core_nt`,
  340 GB, built October 2025, which belongs to another user and is not ours to
  rely on.

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

### 2. Keep 200 to 6000 nt

Both bounds inclusive. Nothing is deleted: short and long records are written
to `lt200/` and `gt6000/`.

```bash
mkdir -p lt200 in_range gt6000
part=unclassified/unclass_part_000.fa
b=$(basename "$part" .fa)

awk -v s="lt200/$b.fa" -v u="in_range/$b.fa" -v o="gt6000/$b.fa" '
  function flush(){ if (!h) return
    if (len < 200)        print rec > s
    else if (len <= 6000) print rec > u
    else                  print rec > o }
  /^>/ { flush(); rec = $0; len = 0; h = 1; next }
       { rec = rec "\n" $0; len += length($0) }
  END  { flush() }' "$part"
```

Wrapper: `02_length_split/lenfilter.sh` (all 21 parts 12 at a time, and writes
`SUMMARY_lenfilter.txt` with the three counts)

### 3. Rod screen

Chunk the in-range FASTAs. 3,409,272 lines is 1,704,636 records per chunk:

```bash
mkdir -p step2/chunks step2/results step2/logs step2/claims step2/rfam
cat in_range/*.fa | split -a3 -d -l 3409272 - step2/chunks/chunk_
```

Wrapper: `step2/make_chunks.sh`. Prefer it over the bare `cat | split`.
Defining a new chunk set invalidates the previous run's `.done` markers and
claim dirs, and leaving those in place makes `step2_run.sh` skip every chunk
and still report success. The wrapper clears them, refuses to touch existing
result CSVs, checks each source file holds whole records, and checks every
chunk begins at a header.

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

The wrappers run every chunk 16 at a time, claim each with an atomic `mkdir`,
apply the row-count gate, and skip finished chunks on a restart. Safe to kill
and restart at any time.

```bash
./step2_run.sh          # 16 workers, -j30
./step2_run_extra.sh    # 4 workers, -j22, to add capacity alongside it
```

Monitoring:

```bash
ls step2/logs/*.done | wc -l                  # of the chunk count
cat step2/results/*.csv | grep -vc '^sample'  # rows so far
cat step2/MISMATCH.txt                        # unresolved truncations
tail step2_run.log
```

### 4. Reduce to the published tables

One row per screened circle becomes three tables. `awk -F,` is safe for the
columns used here, field 3 `predicted_class` and field 19 `n_ribozymes`,
because both sit before `combination_detail`, the only field holding quoted
commas.

```bash
# rod calls
head -1 step2/results/chunk_000.csv > step3/rod_all.csv
awk -F, 'FNR>1 && $3=="rod"' step2/results/chunk_*.csv >> step3/rod_all.csv

# rod calls carrying at least one ribozyme
head -1 step3/rod_all.csv > step3/rod_with_ribozyme.csv
awk -F, 'FNR>1 && $19+0>=1' step3/rod_all.csv >> step3/rod_with_ribozyme.csv
```

The shortlist needs a real CSV reader and is in the wrapper. Its rule, and the
one thing to know before quoting it:

- **Tier 1**, ribozymes on both strands AND at least one corroborated locus,
  where independent CMs agree on the same site. Taken in full. 56 rows in the
  October run.
- **Tier 2**, both strands, no corroboration, confidence >= 0.8, ranked by
  confidence and **truncated** to 2,000 rows. In the October run the
  qualifying pool was 13,399, so the published cut was at confidence 0.998 and
  **11,399 candidates meeting the stated criteria are not in the file.** Raise
  `TOP_N` in the wrapper to publish more of them.

Of 48 columns, the shortlist keeps 41: four ribozyme column names appear twice
in the pipeline's header, and the duplicate copies are dropped.

Wrapper: `step3/make_results.sh` (refuses to run unless `STEP2.DONE` exists,
since that marker is what proves no chunk was silently truncated)

Caveats that qualify the numbers are in
[`step2/share/METHOD.md`](step2/share/METHOD.md) and
[`01_kraken_filter/share/METHOD.md`](01_kraken_filter/share/METHOD.md). Read
them before quoting any result.

## Data

Nothing in this repo. Public, no credentials needed:

    s3://petadex/circs-results/                    # stage 1 outputs
    s3://petadex/circs-results/step2_rod_screen/   # stage 3 and 4 outputs

    aws s3 ls s3://petadex/circs-results/ --no-sign-request
    curl -O https://petadex.s3.amazonaws.com/circs-results/step2_rod_screen/shortlist.csv

Start with `shortlist.csv`. The per-chunk result files, 129 GB and all 545M
rows of the October run, are not public. They are in
`s3://petadex-tmp/circs-results/` and on watson under
`/watson/rnalab/dzhu/k2-circ-runs/`.
