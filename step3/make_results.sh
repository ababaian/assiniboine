#!/usr/bin/env bash
# Stage 5: reduce the per-chunk result CSVs to the published tables.
#
#   step2/results/chunk_*.csv   one row per screened circle, 48 columns
#     -> rod_all.csv            predicted_class == rod
#     -> rod_with_ribozyme.csv  rod AND n_ribozymes >= 1
#     -> shortlist.csv          ranked candidates, two tiers
#
# The October run produced 545,483,299 rows in, 25,222,331 rod, 46,432 of
# those carrying a ribozyme, and a 2,056-row shortlist.
#
# awk -F, is safe for the columns used here (3 = predicted_class,
# 19 = n_ribozymes) because they sit before combination_detail, the only field
# containing quoted commas. Anything touching the later columns must use a
# real CSV reader, which is why the shortlist step is Python.
set -uo pipefail
ROOT=/watson/rnalab/dzhu/k2-circ-runs
cd "$ROOT" || exit 1
OUT=step3
TOP_N=2000          # size of tier 2; the October run took 2000 of 13,399

nres=$(ls step2/results/chunk_*.csv 2>/dev/null | wc -l)
[ "$nres" -gt 0 ] || { echo "no CSVs in step2/results/; run step2_run.sh first"; exit 1; }
mkdir -p "$OUT"

# Refuse to run against an incomplete screen: the gate that proves no chunk
# was silently truncated lives in step2_run.sh.
if [ ! -e STEP2.DONE ]; then
    echo "STEP2.DONE is absent; the screen is incomplete or unverified"
    echo "finish step2_run.sh before reducing its output"
    exit 1
fi

echo "[1/3] rod calls from $nres chunk CSVs"
head -1 step2/results/chunk_000.csv > "$OUT/rod_all.csv"
awk -F, 'FNR>1 && $3=="rod"' step2/results/chunk_*.csv >> "$OUT/rod_all.csv"

echo "[2/3] rod calls carrying at least one ribozyme"
head -1 "$OUT/rod_all.csv" > "$OUT/rod_with_ribozyme.csv"
awk -F, 'FNR>1 && $19+0>=1' "$OUT/rod_all.csv" >> "$OUT/rod_with_ribozyme.csv"

echo "[3/3] shortlist"
TOP_N="$TOP_N" OUT="$OUT" python3 - <<'PY'
import os, pandas as pd
out, top_n = os.environ['OUT'], int(os.environ['TOP_N'])
r = pd.read_csv(f'{out}/rod_with_ribozyme.csv', low_memory=False)

# Four ribozyme column names appear twice in the pipeline's header; pandas
# suffixes the second copy .1. Dropping them takes 48 columns to 41.
r = r[[c for c in r.columns if not c.endswith('.1')]]

# Ribozymes on both strands is the rolling-circle hallmark.
both = r[r.strands_present == '+;-']

# Tier 1: independent CMs agreeing on the same locus. Taken in full.
tier1 = both[both.n_corroborated_loci > 0]

# Tier 2: the rest, ranked by model confidence and TRUNCATED to top_n. The
# qualifying pool is far larger than what is published, so the effective
# confidence cut is whatever the top_n-th row carries, not 0.8.
pool = both[(both.n_corroborated_loci == 0) & (both.confidence >= 0.8)]
tier2 = pool.sort_values('confidence', ascending=False).head(top_n)

pd.concat([tier1, tier2]).to_csv(f'{out}/shortlist.csv', index=False)

print(f"  both strands           {len(both)}")
print(f"  tier 1 (corroborated)  {len(tier1)}   complete")
print(f"  tier 2 pool            {len(pool)}")
print(f"  tier 2 published       {len(tier2)}   cut at confidence "
      f"{tier2.confidence.min():.3f}")
if len(pool) > top_n:
    print(f"  NOT published          {len(pool) - top_n} candidates meet the "
          f"tier 2 criteria but fall below the cut")
PY

{
  echo "Stage 5 summary  ($(date -u))"
  echo "chunk CSVs in:        $nres"
  echo "rod:                  $(( $(wc -l < "$OUT/rod_all.csv") - 1 ))"
  echo "rod with ribozyme:    $(( $(wc -l < "$OUT/rod_with_ribozyme.csv") - 1 ))"
  echo "shortlist:            $(( $(wc -l < "$OUT/shortlist.csv") - 1 ))"
} > SUMMARY_step3.txt
cat SUMMARY_step3.txt
