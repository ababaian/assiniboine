#!/usr/bin/env bash
# Shared setup for every workflow script. Source it; do not run it.
#
#   source "$(dirname "$0")/../common.sh"
#
# It moves to the repository root, loads the settings as shell variables
# (LENGTH_MIN_NT, COMPUTE_KRAKEN_THREADS, ...; see docs/configuration.md) and
# defines a few helpers. Settings come from config/defaults.toml plus the run
# file named by ASSINIBOINE_CONFIG, if any.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

if ! command -v assiniboine > /dev/null; then
    echo "error: the 'assiniboine' command is not installed." >&2
    echo "       run 'pip install -e .' in $REPO_ROOT (see docs/installation.md)" >&2
    exit 1
fi

# Settings become shell variables: [length] min_nt -> LENGTH_MIN_NT.
eval "$(assiniboine config export)"

WORK_DIR=$RUN_WORK_DIR

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    for name in "$@"; do
        command -v "$name" > /dev/null || die "'$name' is not on PATH (see docs/installation.md)"
    done
}

require_file() {
    [ -e "$1" ] || die "$1 does not exist. $2"
}

require_setting() {
    # require_setting KRAKEN_DATABASE "set [kraken] database in your run file"
    [ -n "${!1:-}" ] || die "setting $1 is empty. $2"
}

# Each stage writes DONE in its own directory when it finishes. The driver
# skips a stage whose marker exists; delete the marker to run it again.
stage_is_done() {
    [ -e "$1/DONE" ]
}

mark_done() {
    date -u '+%Y-%m-%d %H:%M:%S' > "$1/DONE"
    log "done: $1"
}

require_done() {
    stage_is_done "$1" || die "$1 has no DONE marker. $2"
}

# Stages 1 to 3 write one file per part of the source, part_000, part_001...
# List the part names of a directory, one per line, in order.
part_names() {
    ls "$1" | grep -E '^part_[0-9]+\.fa$' | sed 's/\.fa$//' | sort
}
