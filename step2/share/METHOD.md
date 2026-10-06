# Step 2 — rod screen: method and caveats

**Purpose.** Screen every circle that Kraken2 could not name for rod-like
structure and self-cleaving ribozymes — the viroid / ribozyvirus / obelisk
signature.

**Input.** 545,483,299 circles: the 595,006,157 unclassified from step 1, cut
to <=6000 nt (99.95% kept) and exact-duplicate deduplicated (8.28% removed,
reversibly). See `../SUMMARY_k2_filter.txt` for step 1.

**Per circle.** All inputs treated as circular throughout.
- `getorf` on the doubled sequence, so ORFs crossing the end->start junction
  are found, then de-duplicated back onto the circle
- `RNAfold --noPS --circ` for MFE structure; structural features derived from
  the dot-bracket
- `cmsearch` against an in-house `dvr5.cm` (E<=1e-3) and against 18 Rfam
  ribozyme CMs (`--cut_ga`)
- a scikit-learn random forest (`rodnotrod`, 31 features) labels rod / not_rod

Run on 480 cores for ~65.7 h as 320 chunks x 16-20 workers.
ViennaRNA 2.x, Infernal 1.1.x, EMBOSS 6.6, scikit-learn pinned to 1.9.1 to
match the model pickle.

**Verification.** Every one of 320 chunks produced output rows exactly equal to
its input record count; summed, 545,483,299 in and 545,483,299 out, zero
mismatches. This check is not ceremonial — see caveat 1.

## Caveats. Read these before quoting any number.

1. **RNAfold stops, it does not skip.** Handed a circle beyond its addressable
   range it prints a warning, emits nothing further, and exits 0. A 20,000-record
   test returned 4,213 rows — exactly the input prefix up to a 44,528-nt circle —
   and the pipeline reported success. Hence the <=6000 nt cut and the
   rows-out == records-in gate on every chunk. Anyone rerunning this must keep
   that gate.

2. **`below_confidence_floor` is always False. The column is dead.** The model's
   `confidence_floor` is 0.5 and a binary classifier's winning class is >=0.5 by
   construction, so the flag can never fire. The scrambled-control calibration
   never took effect. Threshold on `confidence` yourself.

3. **4.6% rod at mean confidence 0.66 is a soft signal.** The defensible subset
   is the 998,131 at >=0.9, and more defensible still is the intersection with a
   detected ribozyme (46,432) and with ribozymes on both strands (16,757).
   Do not treat "rod" alone as a discovery.

4. **The two ribozyme detectors disagree by four orders of magnitude.** The
   in-house `hhrbz_dv4` model hit 30,905 circles; Rfam's `HDV_ribozyme` hit
   exactly 1 in 545 million. That gap needs explaining — different thresholds
   (`-E 1e-3` vs Rfam `--cut_ga`) versus genuinely different sensitivity —
   before any claim about HDV-like agents rests on it.

5. **Counts are not independent observations.** The source is deduplicated
   within each sequencing run but not across runs, and exact dedup here removed
   only identical sequences. Rotations and reverse complements of the same
   circle survive as separate records, so one biological circle may appear many
   times.

6. **Not screened: 271,775 circles >6000 nt.** Those up to ~20,000 nt would
   fold, slowly; past that RNAfold refuses. Ambiviruses (~5000 nt) are inside
   the screened range; anything larger is not.

7. **`length` is the circle length.** RNAfold cost scales with it as ~n^2 in
   this range (measured: 0.146 s at 250 nt, 8.26 s at 2000 nt, single core),
   not n^3 — ViennaRNA caps interior loops at 30 nt, which suppresses the cubic
   term.
