#!/usr/bin/env bash
# Rebuild rods.v1.1.fa using original selfloops.fa headers
# and processed sequences from the rod.csv output of assiniboine
#
# Usage: ./make_rods_fa.sh [rods.csv] [selfloops.v1.1.fa.zst] [rods.v1.1.fa]
set -euo pipefail
csv=${1:-rods.csv}; fa=${2:-selfloops.v1.1.fa.zst}; out=${3:-rods.v1.1.fa}
AWK=$(command -v mawk || command -v awk)   # mawk is ~2-3x faster than gawk here

zstdcat "$fa" | "$AWK" -v csv="$csv" -v miss="${out%.fa}.missing.txt" '
BEGIN {
    while ((getline l < csv) > 0) {
        n = split(l, f, ",")
        if (n > 1 && f[1] != "sample_name") { seq[f[1]] = f[n]; total++ }
    }
    close(csv)
    print "loaded " total " rods from " csv > "/dev/stderr"
}
/^>/ {
    id = substr($1, 2)
    if (id in seq) { print; print seq[id]; found++; delete seq[id] }
}
END {
    print found " records written, " total - found " ids not found in fasta" > "/dev/stderr"
    for (id in seq) print id > miss
}' > "$out"
