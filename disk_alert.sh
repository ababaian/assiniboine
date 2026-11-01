#!/bin/bash
# Push when /watson runs low while the screen is running. One push per level.
cd "$(dirname "$0")"
LOW=${LOW:-300}; FULL=${FULL:-10}; NAME="k2-circ rod screen"
avail() { echo $(( $(df -B1 --output=avail /watson | tail -1) / 2**30 )); }
sent_low=0
until [ -e RUN_ALL.DONE ]; do
    a=$(avail)
    if [ "$sent_low" = 0 ] && [ "$a" -lt "$LOW" ]; then
        ~/bin/notify.sh "$NAME: disk low" "Watson disk under ${LOW} GiB free, job still running" 4
        sent_low=1
    fi
    if [ "$a" -lt "$FULL" ]; then
        ~/bin/notify.sh "$NAME: disk full" "Watson disk under ${FULL} GiB free, job at risk" 5
        exit 0
    fi
    sleep 30
done
