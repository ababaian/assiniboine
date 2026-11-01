#!/usr/bin/env bash
# Driver: wait for stage 0, then run stages 1-5 in order. Resume-safe (each stage is).
# Watched by ONE watchjob; also pushes if the kernel OOM-kills anything while it runs.
set -uo pipefail
cd /watson/rnalab/dzhu/k2-circ-runs
say(){ echo "[$(date -u +%F\ %H:%M:%S)] $*"; }
oom0=$(awk '/^oom_kill/{print $2}' /proc/vmstat)
( while sleep 60; do
    n=$(awk '/^oom_kill/{print $2}' /proc/vmstat)
    if [ "$n" -gt "$oom0" ]; then
      ~/bin/notify.sh "k2-circ rod screen" "OOM kill detected, job still running" 5 >/dev/null 2>&1; oom0=$n
    fi
  done ) & OOMW=$!
trap 'kill $OOMW 2>/dev/null' EXIT

say "waiting for stage 0"
dl_tries=0
while [ ! -e 00_source/selfloops.DONE ]; do
  if [ -e 00_source/selfloops.FAILED ]; then
    dl_tries=$((dl_tries+1)); [ $dl_tries -gt 3 ] && { say "stage 0 FAILED after $dl_tries rounds"; exit 1; }
    say "stage 0 failed, refetching (round $dl_tries)"
    [ $dl_tries = 1 ] && ~/bin/notify.sh "k2-circ rod screen" "stage 0 download failed, refetching" 5 >/dev/null 2>&1
    setsid nohup ./00_source/selfloops_download.sh >> 00_source/download.log 2>&1 < /dev/null &
    sleep 120
  fi
  sleep 30
done
say "stage 0 done"

# Kraken2 runs --memory-mapping: the 316 GiB db is shared page cache (already resident; k2_filter.sh
# re-warms it with cat at ~2 GB/s), so workers only need their own private RSS. Benchmarked 2026-10-30.
while [ "$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)" -lt 100 ]; do
  say "waiting for >=100 GiB MemAvailable (have $(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo))"; sleep 300; done

source /opt/miniconda3/etc/profile.d/conda.sh && conda activate circpipe
stepname(){ case "$1" in *k2_filter*) echo "stage 1 kraken";; *trim_circular*) echo "stage 2 trim";; *lenfilter*) echo "stage 3 length";;
  *make_chunks*) echo "stage 4 chunking";; *run.sh) echo "stage 4 screen";; *make_results*) echo "stage 5 results";; *) echo "step";; esac; }
step(){ nm=$(stepname "$1"); for t in 1 2 3; do say "== $* (try $t)"; "$@" && return 0; rc=$?; say "failed rc=$rc: $*"
          [ $t = 1 ] && ~/bin/notify.sh "k2-circ rod screen" "$nm failed (rc=$rc), retrying" 5 >/dev/null 2>&1
          sleep 300; done
        say "FAILED after 3 tries: $*"; exit 1; }
step ./01_kraken_filter/k2_filter.sh
[ -e 01_kraken_filter/K2_FILTER.DONE ] || { say "stage 1 not DONE"; exit 1; }
step ./02_circular_overlap/trim_circular_overlap.sh -o 02_circular_overlap 01_kraken_filter/unclassified
step ./03_length_filter/lenfilter.sh
step ./04_rod_screen/make_chunks.sh
step ./04_rod_screen/run.sh
step ./05_results/make_results.sh
say "ALL DONE"; touch RUN_ALL.DONE
