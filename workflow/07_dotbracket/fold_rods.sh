#!/usr/bin/env bash
# Stage 7: fold every rod again and keep its dot-bracket structure.
#
#   in   $WORK_DIR/05_results/rods.csv
#   out  $WORK_DIR/07_dotbracket/rods_dotbracket.tsv.zst   sample_name, length, mfe, dot_bracket
#
# Stage 4 keeps only numbers derived from each fold. This stage refolds the
# rods with the same command, RNAfold --circ --noPS, and keeps the structure
# strings, in the order of rods.csv.
#
# The rods are dealt longest-first into COMPUTE_DOTBRACKET_PARTS files so
# every part carries the same mix of lengths, then folded
# COMPUTE_DOTBRACKET_WORKERS parts at a time with one single-threaded RNAfold
# each. A part is done only when every rod came back with a structure as long
# as its sequence. Resume-safe: finished parts are skipped.

source "$(dirname "$0")/../common.sh"

RODS=$WORK_DIR/05_results/rods.csv
OUT=$WORK_DIR/07_dotbracket
RESULT=$OUT/rods_dotbracket.tsv.zst

if stage_is_done "$OUT"; then
    log "stage 7 already done, skipping"
    exit 0
fi
require_done "$WORK_DIR/05_results" "run stage 5 first"
require_command RNAfold
mkdir -p "$OUT"/{parts,folded}

if [ ! -e "$OUT/parts/SPLIT.done" ]; then
    log "dealing the rods into $COMPUTE_DOTBRACKET_PARTS parts"
    assiniboine dotbracket split "$RODS" "$OUT/parts" --parts "$COMPUTE_DOTBRACKET_PARTS"
    touch "$OUT/parts/SPLIT.done"
fi

fold_part() {
    local part=$1 name
    name=$(basename "$part" .fa)
    [ -e "$OUT/folded/$name.done" ] && return 0
    if RNAfold --circ --noPS --jobs=1 < "$part" > "$OUT/folded/$name.fold" 2> "$OUT/folded/$name.err" \
        && assiniboine dotbracket parse "$OUT/folded/$name.fold" "$OUT/folded/$name.tsv" \
               --expected "$(grep -c '^>' "$part")"
    then
        rm -f "$OUT/folded/$name.fold"
        touch "$OUT/folded/$name.done"
    else
        echo "FAIL $name (see $OUT/folded/$name.err)"
    fi
}
export -f fold_part
export OUT

total=$(ls "$OUT"/parts/part_*.fa | wc -l)
log "folding $total parts, $COMPUTE_DOTBRACKET_WORKERS at a time"
ls "$OUT"/parts/part_*.fa | xargs -P "$COMPUTE_DOTBRACKET_WORKERS" -I{} bash -c 'fold_part "$1"' _ {}

done_count=$(ls "$OUT"/folded/part_*.done 2> /dev/null | wc -l)
[ "$done_count" -eq "$total" ] || die "$((total - done_count)) parts are not done; re-run to retry them"

log "collecting the structures in rods.csv order"
assiniboine dotbracket collect "$OUT"/folded/part_*.tsv --output "$RESULT" \
    --expected "$(( $(wc -l < "$RODS") - 1 ))"
mark_done "$OUT"
