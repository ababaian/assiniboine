#!/usr/bin/env bash
# Fetch the Logan v1.1 selfloops FASTA; detached so it survives terminal/VS Code reloads.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
# Stage 1 reads $ROOT/00_source/selfloops.v1.1.fa.zst, so the archive and its
# DONE/FAILED markers belong here and not in the repo root.
cd "$ROOT/00_source" || exit 1
unset AWS_PROFILE
SRC=s3://serratus-rayan/beetles/logan_feb12_run/circles-concat/selfloops.v1.1.fa.zst
WANT=89258393740
rm -f selfloops.DONE selfloops.FAILED
for i in 1 2 3 4 5; do
  rm -f selfloops.v1.1.fa.zst.????????
  if aws s3 cp --no-sign-request --only-show-errors "$SRC" . ; then
    got=$(stat -c %s selfloops.v1.1.fa.zst)
    if [ "$got" = "$WANT" ]; then echo "$(date -u) complete, $got bytes"; touch selfloops.DONE; exit 0; fi
    echo "size mismatch: $got != $WANT"
  fi
  echo "$(date -u) attempt $i failed, retrying in 60s"; sleep 60
done
touch selfloops.FAILED; exit 1
