#!/usr/bin/env bash
# Run the screen end to end, or just the stages named on the command line.
#
#   ./workflow/run_screen.sh            # stages 0 to 7 in order
#   ./workflow/run_screen.sh 2 3        # only stages 2 and 3
#
# Every stage is resume-safe: one that has already finished (its DONE marker
# exists) is skipped, and the expensive stages (1, 4, 7) also skip the parts
# they have already completed. Settings come from config/defaults.toml and
# the run file named by ASSINIBOINE_CONFIG; see docs/configuration.md.

source "$(dirname "$0")/common.sh"

STAGE_SCRIPTS=(
    "00_source/fetch_source.sh"
    "01_kraken_filter/kraken_filter.sh"
    "02_circular_overlap/label_overlap.sh"
    "03_length_filter/length_filter.sh"
    "04_rod_screen/rod_screen.sh"
    "05_results/make_results.sh"
    "06_package/package_run.sh"
    "07_dotbracket/fold_rods.sh"
)

stages=("$@")
if [ ${#stages[@]} -eq 0 ]; then
    stages=(0 1 2 3 4 5 6 7)
fi

log "run '$RUN_NAME', work directory $WORK_DIR"
for stage in "${stages[@]}"; do
    script=${STAGE_SCRIPTS[$stage]:-}
    [ -n "$script" ] || die "there is no stage $stage; stages are 0 to 7"
    log "== stage $stage: $script"
    "workflow/$script"
done
log "all requested stages finished"
