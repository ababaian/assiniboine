#!/usr/bin/env bash
# Shard the deduped FASTA into the chunks step2_run.sh consumes.
#
# 3,409,272 lines is 1,704,636 records, because the file is exactly 2 lines per
# record (header + unwrapped sequence, verified over 9 GB in 00_source). At
# 545,483,299 records that gives 320 chunks: 319 full ones plus a remainder of
# 1,704,415.
#
# Chunking at 320 means a crash costs ~3.6 h of work rather than days. The
# count is not load-bearing: step2_run.sh reads whatever is in step2/chunks/.
#
# This is also where a previous run's bookkeeping is invalidated. Defining a
# new chunk set makes the old .done markers and claim dirs meaningless, and
# leaving them in place makes step2_run.sh skip every chunk and still report
# success.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
SRC=dedup_le6000.fa
LINES_PER_CHUNK=3409272

[ -s "$SRC" ] || { echo "missing $SRC; run 03_dedup/dedup_exact.sh first"; exit 1; }

# An odd value would split records across chunk boundaries.
if [ $(( LINES_PER_CHUNK % 2 )) -ne 0 ]; then
    echo "LINES_PER_CHUNK=$LINES_PER_CHUNK is odd; records are 2 lines each"
    exit 1
fi

if [ "$(ls step2/chunks/chunk_* 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "step2/chunks/ is not empty; refusing to overwrite"
    echo "remove it by hand if you mean to re-chunk"
    exit 1
fi

# Never delete result CSVs; they are the expensive output.
nres=$(ls step2/results/*.csv 2>/dev/null | wc -l)
if [ "$nres" -gt 0 ]; then
    echo "step2/results/ holds $nres CSVs from a previous run"
    echo "move or delete them before re-chunking, or their rows will be merged"
    echo "with the new run's output"
    exit 1
fi

# Bookkeeping from the old chunk set, which this re-chunk invalidates.
nstale=$(( $(ls step2/logs/*.done 2>/dev/null | wc -l) \
         + $(ls -d step2/claims/chunk_* 2>/dev/null | wc -l) ))
if [ "$nstale" -gt 0 ]; then
    echo "clearing $nstale stale markers and claims from the previous chunk set"
    rm -f step2/logs/*.done step2/MISMATCH.txt STEP2.DONE STEP2.INCOMPLETE
    rm -rf step2/claims/chunk_*
fi

mkdir -p step2/chunks step2/results step2/logs step2/claims step2/rfam
split -a3 -d -l "$LINES_PER_CHUNK" "$SRC" step2/chunks/chunk_
rc=$?
[ $rc -eq 0 ] || { echo "split failed rc=$rc"; exit $rc; }

# Every chunk must begin at a header. Given 2-line records that is enough to
# prove no record straddles a boundary, and it costs one byte per chunk rather
# than a full re-read of 156 GB. A header count would be tautological here:
# cat chunk_* is byte-identical to the source whether or not records survived.
bad=0
for c in step2/chunks/chunk_*; do
    [ "$(head -c1 "$c")" = ">" ] || { echo "chunk does not start at a header: $c"; bad=1; }
done
[ "$bad" -eq 0 ] || { echo "chunking is unsafe to screen; not proceeding"; exit 1; }

echo "chunks:         $(ls step2/chunks/chunk_* | wc -l)"
echo "lines per chunk: $LINES_PER_CHUNK ($(( LINES_PER_CHUNK / 2 )) records)"
echo "ok"
