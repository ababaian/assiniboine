#!/usr/bin/env bash
# Stage 0: fetch the source archive.
#
#   in   [source] url            (config)
#   out  $WORK_DIR/00_source/$SOURCE_FILENAME
#
# An s3:// URL is fetched with the AWS CLI without credentials, an http(s)://
# URL with curl, and anything else is taken as a local path and linked, which
# is how a small test file stands in for the real archive. The download is
# retried a few times and, when [source] expected_bytes is set, accepted only
# at exactly that size.

source "$(dirname "$0")/../common.sh"

OUT=$WORK_DIR/00_source
DEST=$OUT/$SOURCE_FILENAME
ATTEMPTS=5

if stage_is_done "$OUT"; then
    log "stage 0 already done, skipping"
    exit 0
fi
mkdir -p "$OUT"

fetch_once() {
    case "$SOURCE_URL" in
        s3://*)
            require_command aws
            aws s3 cp --no-sign-request --only-show-errors "$SOURCE_URL" "$DEST"
            ;;
        http://* | https://*)
            require_command curl
            curl --fail --silent --show-error --location --output "$DEST" "$SOURCE_URL"
            ;;
        *)
            require_file "$SOURCE_URL" "set [source] url to an s3://, http(s):// URL or an existing file"
            ln -sf "$(realpath "$SOURCE_URL")" "$DEST"
            ;;
    esac
}

size_is_right() {
    [ "$SOURCE_EXPECTED_BYTES" -eq 0 ] && return 0
    local got
    got=$(stat -L -c %s "$DEST")
    if [ "$got" -ne "$SOURCE_EXPECTED_BYTES" ]; then
        log "size mismatch: got $got bytes, expected $SOURCE_EXPECTED_BYTES"
        return 1
    fi
}

for attempt in $(seq 1 "$ATTEMPTS"); do
    log "fetching $SOURCE_URL (attempt $attempt of $ATTEMPTS)"
    if fetch_once && size_is_right; then
        log "fetched $DEST, $(stat -L -c %s "$DEST") bytes"
        mark_done "$OUT"
        exit 0
    fi
    sleep 60
done
die "could not fetch $SOURCE_URL after $ATTEMPTS attempts"
