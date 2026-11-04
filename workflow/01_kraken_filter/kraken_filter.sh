#!/usr/bin/env bash
# Stage 1: drop every record Kraken2 can already name.
#
#   in   $WORK_DIR/00_source/$SOURCE_FILENAME
#   out  $WORK_DIR/01_kraken_filter/unclassified/part_NNN.fa   the records kept
#        $WORK_DIR/01_kraken_filter/calls/part_NNN.tsv.zst     every record's call
#        $WORK_DIR/01_kraken_filter/reports/part_NNN.txt       Kraken2 taxonomy report
#        $WORK_DIR/01_kraken_filter/summary.txt
#
# Kraken2 is run at [kraken] confidence against [kraken] database. A record it
# classifies is dropped; "unclassified" means the database could not name it,
# not that it is novel. The per-record calls (status, id, taxid, length) are
# kept so stage 6 can say what happened to every source record.
#
# The source is first decompressed and cut into parts of
# COMPUTE_RECORDS_PER_PART records. Parts are classified
# COMPUTE_KRAKEN_WORKERS at a time; with --memory-mapping they share one copy
# of the database through the page cache. Each part is deleted once its
# classification succeeds, which caps the disk the stage needs.
#
# Resume-safe: re-running skips the split if it finished and skips every part
# with a logs/part_NNN.done marker.

source "$(dirname "$0")/../common.sh"

SRC=$WORK_DIR/00_source/$SOURCE_FILENAME
OUT=$WORK_DIR/01_kraken_filter

if stage_is_done "$OUT"; then
    log "stage 1 already done, skipping"
    exit 0
fi
require_file "$SRC" "run stage 0 first"
require_setting KRAKEN_DATABASE "set [kraken] database in your run file"
require_file "$KRAKEN_DATABASE/hash.k2d" "[kraken] database must point at a Kraken2 database directory"
require_command kraken2 zstd
mkdir -p "$OUT"/{parts,unclassified,calls,reports,logs,counts}

# ---- 1. cut the source into parts -----------------------------------------
# Every record is two lines, so a part of N records is 2N lines.
if [ ! -e "$OUT/parts/SPLIT.done" ]; then
    log "splitting $SRC into parts of $COMPUTE_RECORDS_PER_PART records"
    rm -f "$OUT"/parts/part_*.fa
    zstd -dc < "$SRC" | split -d -a 3 -l $((2 * COMPUTE_RECORDS_PER_PART)) --additional-suffix=.fa - "$OUT/parts/part_"
    touch "$OUT/parts/SPLIT.done"
    log "split into $(ls "$OUT"/parts/part_*.fa | wc -l) parts"
fi

# ---- 2. classify each part ------------------------------------------------
classify_part() {
    local part=$1 name
    name=$(basename "$part" .fa)
    [ -e "$OUT/logs/$name.done" ] && return 0
    set -o pipefail

    # Kraken2 prints one call per record on stdout: status, id, taxid, length,
    # then the k-mer hits. Only the first four columns are kept.
    if kraken2 --db "$KRAKEN_DATABASE" --memory-mapping \
               --threads "$COMPUTE_KRAKEN_THREADS" --confidence "$KRAKEN_CONFIDENCE" \
               --unclassified-out "$OUT/unclassified/$name.fa" \
               --report "$OUT/reports/$name.txt" \
               "$part" 2> "$OUT/logs/$name.log" \
        | cut -f 1-4 | zstd -q -f -o "$OUT/calls/$name.tsv.zst"
    then
        # Kraken2's log ends with the classified and unclassified counts.
        awk '/sequences classified/   {print "classified\t" $1}
             /sequences unclassified/ {print "unclassified\t" $1}' "$OUT/logs/$name.log" > "$OUT/counts/$name.tsv"
        touch "$OUT/logs/$name.done"
        rm -f "$part"
        echo "ok   $name"
    else
        echo "FAIL $name (see $OUT/logs/$name.log)"
        return 1
    fi
}
export -f classify_part
export OUT KRAKEN_DATABASE KRAKEN_CONFIDENCE COMPUTE_KRAKEN_THREADS

log "classifying with $COMPUTE_KRAKEN_WORKERS workers x $COMPUTE_KRAKEN_THREADS threads"
ls "$OUT"/parts/part_*.fa 2> /dev/null \
    | xargs -P "$COMPUTE_KRAKEN_WORKERS" -I{} bash -c 'classify_part "$1"' _ {} \
    || die "some parts failed; re-run to retry them"

# ---- 3. summarise ---------------------------------------------------------
[ "$(ls "$OUT"/parts/part_*.fa 2> /dev/null | wc -l)" -eq 0 ] || die "parts remain unclassified; re-run to retry them"
assiniboine sum-counts "$OUT"/counts/part_*.tsv | tee "$OUT/summary.txt"
mark_done "$OUT"
