#!/usr/bin/env bash
# Stage 6: package the run as a record manifest plus checksums.
#
#   in   the source archive, stage 1 calls/, stage 2 labelled/, stages 1 to 3 outputs
#   out  $WORK_DIR/06_package/record_manifest.tsv.zst  one row per source record
#        $WORK_DIR/06_package/summary.txt
#        $WORK_DIR/06_package/MD5SUMS                   checksums of what a run keeps
#
# Stages 1 to 3 write hundreds of gigabytes, but every record in them is a
# source record that was dropped, trimmed or filed by a fixed rule. The
# manifest records that outcome in one row per record, and the verify step
# proves that the source plus the manifest rebuild every stage 1 to 3 file
# byte for byte. After that, the FASTA files need not be kept or shared.
#
# Both steps stream the whole source once in a single process, so they take
# about as long as reading it. The rules are in src/assiniboine/manifest.py.

source "$(dirname "$0")/../common.sh"

SRC=$WORK_DIR/00_source/$SOURCE_FILENAME
OUT=$WORK_DIR/06_package
MANIFEST=$OUT/record_manifest.tsv.zst

if stage_is_done "$OUT"; then
    log "stage 6 already done, skipping"
    exit 0
fi
require_file "$SRC" "run stage 0 first"
require_done "$WORK_DIR/03_length_filter" "run stages 1 to 3 first"
mkdir -p "$OUT"

method_args=(--overlap "$OVERLAP_LENGTH" --min-length "$LENGTH_MIN_NT" --max-length "$LENGTH_MAX_NT")

if [ ! -e "$OUT/MANIFEST.done" ]; then
    log "building the record manifest"
    assiniboine manifest build --source "$SRC" \
        --calls-dir "$WORK_DIR/01_kraken_filter/calls" \
        --labelled-dir "$WORK_DIR/02_circular_overlap/labelled" \
        --output "$MANIFEST" "${method_args[@]}" | tee "$OUT/summary.txt"
    touch "$OUT/MANIFEST.done"
fi

if [ ! -e "$OUT/VERIFY.done" ]; then
    log "checking that the manifest rebuilds stages 1 to 3"
    assiniboine manifest verify --source "$SRC" --manifest "$MANIFEST" \
        --unclassified-dir "$WORK_DIR/01_kraken_filter/unclassified" \
        --labelled-dir "$WORK_DIR/02_circular_overlap/labelled" \
        --length-dir "$WORK_DIR/03_length_filter" \
        --records-per-part "$COMPUTE_RECORDS_PER_PART" "${method_args[@]}"
    touch "$OUT/VERIFY.done"
fi

# Checksums of the files a run keeps. Paths are relative to the work directory
# so the file can be checked after the data moves: md5sum -c 06_package/MD5SUMS
log "writing checksums"
kept_dirs=(01_kraken_filter/calls 01_kraken_filter/reports 04_rod_screen/results 05_results 07_dotbracket)
(
    cd "$WORK_DIR"
    {
        for dir in "${kept_dirs[@]}"; do
            [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f ! -name DONE
        done
        echo "06_package/record_manifest.tsv.zst"
    } | sort | xargs md5sum
) > "$OUT/MD5SUMS"
log "$(wc -l < "$OUT/MD5SUMS") files listed in $OUT/MD5SUMS"
mark_done "$OUT"
