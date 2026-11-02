#!/usr/bin/env bash
# Build the upload set for s3://petadex/circs-results/run-2026-11/ from the
# verified manifest parts and the run's stage 4 and 5 output. One or two files
# per step; the source archive is already on S3 and is not copied.
#
#   01_kraken_filter/classified_records.tsv.zst    one row per classified record, with taxon name
#   01_kraken_filter/unclassified_records.tsv.zst  one row per unclassified record
#   01-03_records/record_manifest.tsv.zst          every record, source order; rebuild_stage.sh input
#   04_rod_screen/screen.parquet                   every screened circle, no sequences
#   05_results/rods.csv.zst                        every rod, annotated, with sequence
#
# Run after run_package.sh has written work/VERIFY.DONE.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
P=06_package
W=$P/work/upload
U=$P/upload/run-2026-11
MAN=$P/staging/run-2026-11/manifest
PY=/watson/rnalab/dzhu/.conda/envs/features/bin/python
mkdir -p "$W" "$U"/{01_kraken_filter,01-03_records,04_rod_screen,05_results}
say(){ echo "[$(date -u '+%m-%d %H:%M:%S')] $*"; }
die(){ say "FAILED: $*"; exit 1; }
[ -e $P/work/VERIFY.DONE ] || die "manifest not verified yet"
parts=$(seq -f 'part_%03g' 0 20)

# Each output is written as one zstd frame per part, then the frames are
# concatenated behind a header frame. Concatenated frames are a valid zstd file.
hdr(){ printf '%s\n' "$1" | zstd -q -19 -o "$2"; }

# ---- 1. record lists and the single manifest -------------------------------
if [ ! -e "$W/RECORDS.DONE" ]; then
    say "1 record lists"
    # Taxon name and rank by taxid; names can hold commas, so parse the CSV properly.
    python3 -c "
import csv, sys
w = csv.writer(sys.stdout, delimiter='\t', lineterminator='\n')
for r in csv.DictReader(open('review/classified_taxa.csv')):
    assert '\t' not in r['name']
    w.writerow([r['taxid'], r['name'], r['rank']])" > "$W/taxa.tsv" || die "taxa"
    one(){
        p=$1; man=$2; w=$3
        zstd -dc "$man/$p.tsv.zst" | tail -n +2 | zstd -q -19 -T8 -f -o "$w/man_$p.zst" || return 1
        zstd -dc "$man/$p.tsv.zst" | tail -n +2 | LC_ALL=C mawk -F'\t' -v OFS='\t' -v taxa="$w/taxa.tsv" \
            -v ucmd="zstd -q -19 -T8 -f -o $w/unc_$p.zst" '
            BEGIN { while ((getline l < taxa) > 0) { split(l, f, "\t"); name[f[1]] = f[2]; rank[f[1]] = f[3] } }
            $4 == "C" { if (!($5 in name)) { print "unknown taxid " $5 > "/dev/stderr"; bad = 1; exit 3 }
                        print $1, $2, $3, $5, name[$5], rank[$5], $6; next }
            { print $1, $2, $3, $6, $3 - ($6 == "circular" ? 30 : 0), $7 | ucmd }
            END { close(ucmd); if (bad) exit 3 }' | zstd -q -19 -T8 -f -o "$w/cls_$p.zst"
        st=("${PIPESTATUS[@]}"); [ "${st[2]}" = 0 ] && [ "${st[3]}" = 0 ] || { echo "[FAIL] $p ${st[*]}"; return 1; }
        echo "[ok] $p"
    }
    export -f one
    echo "$parts" | xargs -P 21 -I{} bash -c 'one "$@"' _ {} "$MAN" "$W" || die "record lists"
    hdr $'id\trun\tlength\tkraken\ttaxid\tclosure\tstage' "$W/man_hdr.zst"
    hdr $'id\trun\tlength\ttaxid\ttaxon_name\trank\tclosure' "$W/cls_hdr.zst"
    hdr $'id\trun\tlength\tclosure\ttrimmed_length\tstage' "$W/unc_hdr.zst"
    cat "$W/man_hdr.zst" $(for p in $parts; do echo "$W/man_$p.zst"; done) > "$U/01-03_records/record_manifest.tsv.zst"
    cat "$W/cls_hdr.zst" $(for p in $parts; do echo "$W/cls_$p.zst"; done) > "$U/01_kraken_filter/classified_records.tsv.zst"
    cat "$W/unc_hdr.zst" $(for p in $parts; do echo "$W/unc_$p.zst"; done) > "$U/01_kraken_filter/unclassified_records.tsv.zst"
    n=$(zstd -dc "$U/01-03_records/record_manifest.tsv.zst" | wc -l); [ "$n" = 900042457 ] || die "manifest rows $n"
    n=$(zstd -dc "$U/01_kraken_filter/classified_records.tsv.zst" | wc -l); [ "$n" = 305036300 ] || die "classified rows $n"
    n=$(zstd -dc "$U/01_kraken_filter/unclassified_records.tsv.zst" | wc -l); [ "$n" = 595006158 ] || die "unclassified rows $n"
    # The single manifest must hold exactly the rows the verified parts held.
    a=$(for p in $parts; do zstd -dc "$MAN/$p.tsv.zst" | tail -n +2; done | md5sum)
    b=$(zstd -dc "$U/01-03_records/record_manifest.tsv.zst" | tail -n +2 | md5sum)
    [ "$a" = "$b" ] || die "single manifest differs from the parts"
    touch "$W/RECORDS.DONE"; say "record lists done"
fi

# ---- 2. closure and rod sequences per screened circle ------------------------
if [ ! -e "$W/SEQ.DONE" ]; then
    say "2 closure and rod sequences from the chunks"
    ls 04_rod_screen/chunks/ | xargs -P 48 -I{} bash -c '
        LC_ALL=C mawk -F, -v ch=04_rod_screen/chunks/{} -v cl='"$W"'/cl_{}.tsv -v sq='"$W"'/sq_{}.tsv "
            FNR > 1 && \$3 == \"rod\" { rod[\$1] = 1 }
            END { OFS = \"\t\"
                  while ((getline h < ch) > 0) { getline s < ch
                      split(h, a, \" \"); id = substr(a[1], 2); match(h, /ovl:[a-z]+/)
                      print id, substr(h, RSTART + 4, RLENGTH - 4) > cl
                      if (id in rod) print id, s > sq } }" 04_rod_screen/results/{}.csv' || die "chunk scan"
    touch "$W/SEQ.DONE"
fi

# ---- 3. screen.parquet and rods.csv ----------------------------------------
if [ ! -e "$W/TABLES.DONE" ]; then
    say "3 screen.parquet and rods.csv"
    W="$W" U="$U" $PY - <<'PY' || die "tables"
import duckdb, os
W, U = os.environ['W'], os.environ['U']
c = duckdb.connect(f'{W}/tmp.duckdb')
c.execute("SET threads=64; SET memory_limit='200GB'; SET preserve_insertion_order=false")
c.execute(f"SET temp_directory='{W}/duck_tmp'")
dups = ['n_ribozymes', 'n_ribozymes_plus', 'n_ribozymes_minus', 'n_ambiguous_loci',
        'n_corroborated_loci', 'paired', 'same_family_paired']
c.execute("""CREATE TABLE s AS SELECT * FROM read_csv('04_rod_screen/results/chunk_*.csv',
             header=true, sample_size=-1, union_by_name=false)""")
bad = c.execute('SELECT ' + ', '.join(f'sum(({d} IS DISTINCT FROM {d}_1)::BIGINT)' for d in dups) + ' FROM s').fetchone()
assert all(x == 0 for x in bad), f'duplicate columns differ: {bad}'
c.execute(f"CREATE TABLE cl AS SELECT * FROM read_csv('{W}/cl_chunk_*.tsv', delim='\t', header=false, columns={{'id':'VARCHAR','closure':'VARCHAR'}})")
n, rod = c.execute("SELECT count(*), sum((predicted_class='rod')::BIGINT) FROM s").fetchone()
assert (n, rod) == (161292329, 11308939), (n, rod)
assert c.execute('SELECT count(*) FROM cl').fetchone()[0] == n
keep = [r[0] for r in c.execute('DESCRIBE s').fetchall() if not r[0].endswith('_1')]
assert keep[0] == 'sample_name'
rest = ', '.join(f's."{k}"' for k in keep[1:])
c.execute(f"""CREATE TABLE screen AS SELECT s.sample_name, split_part(s.sample_name, '_', 1) AS run,
              cl.closure, {rest} FROM s JOIN cl ON s.sample_name = cl.id""")
assert c.execute('SELECT count(*) FROM screen').fetchone()[0] == n, 'closure join lost rows'
c.execute(f"COPY screen TO '{U}/04_rod_screen/screen.parquet' (FORMAT parquet, COMPRESSION zstd, COMPRESSION_LEVEL 9, ROW_GROUP_SIZE 1000000)")

c.execute(f"CREATE TABLE sq AS SELECT * FROM read_csv('{W}/sq_chunk_*.tsv', delim='\t', header=false, columns={{'id':'VARCHAR','sequence':'VARCHAR'}})")
c.execute("CREATE TABLE sl AS SELECT sample_name, n_corroborated_loci FROM read_csv('05_results/shortlist.csv', header=true, sample_size=-1)")
c.execute("""CREATE TABLE rods AS
  SELECT r.sample_name, r.run, r.length, r.closure, r.confidence,
         r.n_ribozymes, r.n_ribozymes_plus, r.n_ribozymes_minus, r.strands_present,
         r.ribozyme_families, r.n_corroborated_loci,
         r.n_ribozymes >= 1 AS has_ribozyme,
         r.strands_present = '+;-' AS both_strands,
         (r.strands_present = '+;-' AND r.n_corroborated_loci = 0 AND r.confidence >= 0.8) AS tier2_pool,
         CASE WHEN sl.sample_name IS NULL THEN NULL WHEN sl.n_corroborated_loci > 0 THEN 1 ELSE 2 END AS shortlist_tier,
         sq.sequence
  FROM screen r JOIN sq ON r.sample_name = sq.id
  LEFT JOIN sl ON r.sample_name = sl.sample_name
  WHERE r.predicted_class = 'rod'""")
got = c.execute("""SELECT count(*), sum(has_ribozyme::BIGINT), sum(both_strands::BIGINT), sum(tier2_pool::BIGINT),
                   count(shortlist_tier), sum((shortlist_tier=1)::BIGINT), count(DISTINCT sample_name),
                   sum((length(sequence) = length)::BIGINT) FROM rods""").fetchone()
print('rods check', got)
assert got[:6] == (11308939, 43887, 14806, 12259, 2047, 47), got
assert got[6] == 11308939, 'duplicate ids'
assert got[7] == 11308939, 'sequence length differs from length column'
c.execute(f"COPY (SELECT * FROM rods ORDER BY sample_name) TO '{W}/rods.csv' (HEADER, DELIMITER ',')")
print('ok')
PY
    zstd -q -19 -T32 -f "$W/rods.csv" -o "$U/05_results/rods.csv.zst" || die "compress rods"
    touch "$W/TABLES.DONE"
fi

# ---- 4. checksums ------------------------------------------------------------
( cd "$U" && find . -type f ! -name MD5SUMS ! -name README.md -printf '%P\n' | LC_ALL=C sort \
    | xargs -P 8 -I{} md5sum {} > MD5SUMS ) || die "md5"
du -sh "$U"/*/* | sed 's/^/  /'
say "ALL DONE"
touch "$W/UPLOAD.DONE"
