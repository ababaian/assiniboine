#!/usr/bin/env bash
# Run the pipeline end to end on synthetic data, in a few seconds.
#
#   ./scripts/ops/run_example.sh [RUN_FILE]     default: config/runs/example.toml
#
# Stages 1 and 4 need Kraken2 with a database and the external classifier,
# neither of which a laptop has, so this script stands in for them with
# make_example_data.py: it writes files of the right shape in the places
# those stages would, then runs the real scripts for every other stage.
# Stage 7 runs only if RNAfold is installed.
#
# Everything lands under work/example/. The values are random; the point is
# to watch each stage run and to look at what it writes.

export ASSINIBOINE_CONFIG=${1:-config/runs/example.toml}
source "$(dirname "$0")/../../workflow/common.sh"

# The work directory is wiped below, so refuse to run as anything but the example.
[ "$RUN_NAME" = "example" ] || die "run_example.sh only runs a run named 'example'; $ASSINIBOINE_CONFIG names '$RUN_NAME'"

MAKE="python3 scripts/ops/make_example_data.py"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

log "synthetic source archive"
$MAKE source "$SOURCE_URL" --records 5000
./workflow/run_screen.sh 0

log "stage 1 stand-in: Kraken2 calls and unclassified records"
STAGE1=$WORK_DIR/01_kraken_filter
$MAKE stage1 "$SOURCE_URL" "$STAGE1" --records-per-part "$COMPUTE_RECORDS_PER_PART"
assiniboine sum-counts "$STAGE1"/counts/part_*.tsv | tee "$STAGE1/summary.txt"
mark_done "$STAGE1"

./workflow/run_screen.sh 2 3

log "stage 4 stand-in: chunks, then a synthetic screen result per chunk"
STAGE4=$WORK_DIR/04_rod_screen
./workflow/04_rod_screen/make_chunks.sh
for chunk in "$STAGE4"/chunks/chunk_*.fa; do
    name=$(basename "$chunk" .fa)
    $MAKE screen "$chunk" "$STAGE4/results/$name.csv"
    assiniboine validate screen "$chunk" "$STAGE4/results/$name.csv"
    touch "$STAGE4/logs/$name.done"
done
echo "chunks completed  $(ls "$STAGE4"/logs/*.done | wc -l)" > "$STAGE4/summary.txt"
mark_done "$STAGE4"

./workflow/run_screen.sh 5 6

if command -v RNAfold > /dev/null; then
    ./workflow/run_screen.sh 7
else
    log "RNAfold is not installed; skipping stage 7"
fi

log "example run finished; look under $WORK_DIR"
find "$WORK_DIR" -name summary.txt | sort | while read -r summary; do
    echo; echo "== $summary"; cat "$summary"
done
