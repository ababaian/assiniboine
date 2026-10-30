#!/usr/bin/env bash
# Shard the in-range FASTAs into the chunks 04_rod_screen/run.sh consumes.
#
# 3,409,272 lines is 1,704,636 records, because every FASTA here is exactly 2
# lines per record (header + unwrapped sequence, verified over 9 GB in
# 00_source). Chunking at roughly this size means a crash costs ~3.6 h of work
# rather than days. The chunk COUNT is not load-bearing: 04_rod_screen/run.sh screens
# whatever is in 04_rod_screen/chunks/.
#
# This is also where a previous run's bookkeeping is invalidated. Defining a
# new chunk set makes the old .done markers and claim dirs meaningless, and
# leaving them in place makes 04_rod_screen/run.sh skip every chunk and still report
# success.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
SRC_DIR=03_length_filter/in_range
LINES_PER_CHUNK=3409272

nsrc=$(ls "$SRC_DIR"/*.fa 2>/dev/null | wc -l)
if [ "$nsrc" -eq 0 ]; then
    echo "no FASTAs in $SRC_DIR/; run 03_length_filter/lenfilter.sh first"
    exit 1
fi

# An odd value would split records across chunk boundaries.
if [ $(( LINES_PER_CHUNK % 2 )) -ne 0 ]; then
    echo "LINES_PER_CHUNK=$LINES_PER_CHUNK is odd; records are 2 lines each"
    exit 1
fi

# Each source file must itself hold whole records, or concatenating them
# misaligns every record after the first short file.
for f in "$SRC_DIR"/*.fa; do
    if [ $(( $(wc -l < "$f") % 2 )) -ne 0 ]; then
        echo "odd line count in $f; not 2 lines per record"
        exit 1
    fi
done

if [ "$(ls 04_rod_screen/chunks/chunk_* 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "04_rod_screen/chunks/ is not empty; refusing to overwrite"
    echo "remove it by hand if you mean to re-chunk"
    exit 1
fi

# Never delete result CSVs; they are the expensive output.
nres=$(ls 04_rod_screen/results/*.csv 2>/dev/null | wc -l)
if [ "$nres" -gt 0 ]; then
    echo "04_rod_screen/results/ holds $nres CSVs from a previous run"
    echo "move or delete them before re-chunking, or their rows will be merged"
    echo "with the new run's output"
    exit 1
fi

# Bookkeeping from the old chunk set, which this re-chunk invalidates.
nstale=$(( $(ls 04_rod_screen/logs/*.done 2>/dev/null | wc -l) \
         + $(ls -d 04_rod_screen/claims/chunk_* 2>/dev/null | wc -l) ))
if [ "$nstale" -gt 0 ]; then
    echo "clearing $nstale stale markers and claims from the previous chunk set"
    rm -f 04_rod_screen/logs/*.done 04_rod_screen/MISMATCH.txt 04_rod_screen/SCREEN.DONE 04_rod_screen/SCREEN.INCOMPLETE
    rm -rf 04_rod_screen/claims/chunk_*
fi

mkdir -p 04_rod_screen/chunks 04_rod_screen/results 04_rod_screen/logs 04_rod_screen/claims 04_rod_screen/rfam
cat "$SRC_DIR"/*.fa | split -a3 -d -l "$LINES_PER_CHUNK" - 04_rod_screen/chunks/chunk_
st=("${PIPESTATUS[@]}")
if [ "${st[0]}" != 0 ] || [ "${st[1]}" != 0 ]; then
    echo "chunking failed: cat=${st[0]} split=${st[1]}"
    exit 1
fi

# Every chunk must begin at a header. Given 2-line records that is enough to
# prove no record straddles a boundary, and it costs one byte per chunk rather
# than a full re-read. A header count would be tautological here: the chunks
# concatenate back to the input whether or not records survived.
bad=0
for c in 04_rod_screen/chunks/chunk_*; do
    [ "$(head -c1 "$c")" = ">" ] || { echo "chunk does not start at a header: $c"; bad=1; }
done
[ "$bad" -eq 0 ] || { echo "chunking is unsafe to screen; not proceeding"; exit 1; }

echo "source files:    $nsrc in $SRC_DIR/"
echo "chunks:          $(ls 04_rod_screen/chunks/chunk_* | wc -l)"
echo "lines per chunk: $LINES_PER_CHUNK ($(( LINES_PER_CHUNK / 2 )) records)"
echo "ok"
