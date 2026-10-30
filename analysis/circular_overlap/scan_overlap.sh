#!/usr/bin/env bash
# Measure the terminal overlap length in a selfloops FASTA, and cross-tabulate
# the GFA self-link orientation against what the sequence actually shows.
#
# Produces the two tables in README.md:
#   1. fraction of records with first-K == last-K, for K = 20..36
#   2. class counts by header link, with the palindrome check per class
#
# Usage: ./scan_overlap.sh <selfloops.fa> [max_records]
#
# Needs headers intact. The L: fields are the basis of the classification.
set -uo pipefail
IN=${1:?usage: scan_overlap.sh <selfloops.fa> [max_records]}
LIMIT=${2:-0}
AWK=$(command -v mawk || command -v awk)

LC_ALL=C "$AWK" -v limit="$LIMIT" '
function rc(s,  i,c,o){ o=""
  for (i = length(s); i >= 1; i--) { c = substr(s, i, 1)
    o = o (c=="A"?"T":c=="T"?"A":c=="G"?"C":c=="C"?"G":"N") }
  return o }
/^>/ { hdr = $0; next }
{
  if (limit > 0 && tot >= limit) { nextfile }
  s = toupper($0); n = length(s); tot++

  for (k = 20; k <= 36; k++)
    if (n >= 2*k && substr(s,1,k) == substr(s,n-k+1)) hit[k]++

  rev = (hdr ~ /L:\+:[0-9]+:-/ || hdr ~ /L:-:[0-9]+:\+/)
  fwd = (hdr ~ /L:-:[0-9]+:-/  && hdr ~ /L:\+:[0-9]+:\+/)
  cls = (rev && !fwd) ? ((hdr ~ /L:-:[0-9]+:\+/) ? "hairpin C" : "hairpin D") \
                      : (fwd ? "circular" : "other")
  cnt[cls]++; len[cls] += n

  pre = substr(s,1,30); suf = substr(s,n-29)
  if (n >= 60) {
    if (pre == suf)        ov[cls]++
    if (pre == rc(pre))    pp[cls]++
    if (suf == rc(suf))    ps[cls]++
  }
}
END {
  printf "records examined: %d\n\n", tot
  print  "K scan: first K == last K"
  printf "  %3s %10s %8s\n", "K", "matched", "%"
  for (k = 20; k <= 36; k++)
    printf "  %3d %10d %7.2f%%\n", k, hit[k]+0, 100*(hit[k]+0)/tot

  printf "\nclass table (by header link, verified against sequence)\n"
  printf "  %-10s %9s %8s %10s %14s %14s\n", \
         "class", "n", "share", "first==last", "first30 selfrc", "last30 selfrc"
  for (c in cnt)
    printf "  %-10s %9d %7.2f%% %10d %14d %14d\n", \
           c, cnt[c], 100*cnt[c]/tot, ov[c]+0, pp[c]+0, ps[c]+0

  printf "\nmean length by class\n"
  for (c in cnt) printf "  %-10s %8.1f nt\n", c, len[c]/cnt[c]
}' "$IN"
