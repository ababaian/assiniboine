#!/usr/bin/env bash
# Report which of the pipeline's tools and inputs are present.
#
#   ./scripts/ops/check_dependencies.sh
#
# Prints one line per item. Nothing is installed or changed.

cd "$(dirname "$0")/../.."
status=0

check_command() {
    # check_command NAME "used by"
    if command -v "$1" > /dev/null; then
        printf '  ok       %-12s %s\n' "$1" "$(command -v "$1")"
    else
        printf '  MISSING  %-12s needed by %s\n' "$1" "$2"
        status=1
    fi
}

echo "commands"
check_command assiniboine "every stage (pip install -e .)"
check_command python3 "stage 4 and the scripts"
check_command zstd "stages 1, 6 and 7"
check_command aws "stage 0, when the source is on S3"
check_command kraken2 "stage 1"
check_command getorf "stage 4"
check_command RNAfold "stages 4 and 7"
check_command cmsearch "stage 4"
check_command cmpress "stage 4"

echo "settings (config/defaults.toml plus \$ASSINIBOINE_CONFIG)"
if command -v assiniboine > /dev/null; then
    eval "$(assiniboine config export)"
    echo "  run          $RUN_NAME, work directory $RUN_WORK_DIR"
    if [ -n "$KRAKEN_DATABASE" ] && [ -e "$KRAKEN_DATABASE/hash.k2d" ]; then
        echo "  ok       Kraken2 database at $KRAKEN_DATABASE"
    else
        echo "  MISSING  Kraken2 database: [kraken] database is '${KRAKEN_DATABASE:-}' (stage 1 needs it)"
        status=1
    fi
    if [ -e "$SCREEN_LEBOWSKI_DIR/Scripts/run_pipeline.py" ] && [ -e "$SCREEN_LEBOWSKI_DIR/rodnotrod_model/model.pkl" ]; then
        echo "  ok       Lebowski bundle at $SCREEN_LEBOWSKI_DIR"
    else
        echo "  MISSING  Lebowski bundle at '$SCREEN_LEBOWSKI_DIR' (stage 4 needs it; see docs/dependencies.md)"
        status=1
    fi
fi

echo "python packages for the external classifier"
for module in sklearn pandas numpy scipy; do
    if python3 -c "import $module" 2> /dev/null; then
        printf '  ok       %-12s %s\n' "$module" "$(python3 -c "import $module; print(getattr($module, '__version__', ''))")"
    else
        printf '  MISSING  %-12s needed by stage 4\n' "$module"
        status=1
    fi
done

[ $status -eq 0 ] && echo "everything is in place" || echo "some items are missing; see docs/installation.md"
exit $status
