# Methods

The rules the pipeline applies, and why. Everything here is implemented in
`src/assiniboine/` or in the external classifier; the workflow scripts only
run it. Changing a rule is a scientific change and should be recorded in
the run's documentation.

## What is being looked for

Viroids, ribozyviruses (hepatitis delta-like agents), obelisks and
ambiviruses are small circular RNAs with two shared properties: they fold
into a long, highly base-paired, little-branched **rod**, and most carry
self-cleaving **ribozymes**, often on both strands, which is the hallmark
of rolling-circle replication. The screen looks for both properties in
sequences that an assembler found to be circular and that no reference
database can name.

## Stage 1: drop what can already be named

Kraken2 at `--confidence 0.1` against a comprehensive nucleotide database
(the published runs used a core_nt build). Records it classifies are
removed. The large majority of what it removes is host genome: in the
November 2026 run, human and mouse alone accounted for over 40% of the
classified third. The target families were almost absent from what the
database could name (Pospiviroidae 12,961 records, Ribozyviria 54, out of
305 million classified), which is the argument for screening the
unclassified remainder rather than the whole archive.

"Unclassified" means the database could not name the record. It does not
mean the record is novel, and short records are enriched among them because
they carry too few k-mers to accumulate classification evidence.

## Stage 2: how a record closes

Logan assembles at k = 31. A unitig that closes into a circle is emitted
with its first k - 1 = 30 nt repeated as its last 30 nt. On 100,000 raw
records, the fraction whose first K bases equal their last K was 62.8% at
K = 30 and 0% at every K from 31 to 36, so the overlap is exactly 30 nt
(`scripts/scan_overlap.py` reproduces the measurement).

Left in place, the overlap inflates every length by 30 nt, which stage 3
filters on, and once `RNAfold --circ` joins the last base to the first it
inserts a tandem copy of those 30 nt into the fold, so every structural
feature the classifier reads is computed on a sequence 30 nt longer than
the molecule. So the overlap is trimmed.

Not every selfloops record is a circle. The GFA self-links in the header
record how the assembler closed the unitig, and they separate three
classes:

| class | header links | sequence | action |
|---|---|---|---|
| circular | `L:-:x:-` and `L:+:x:+` | first 30 nt equal last 30 nt | trim 30 nt |
| hairpin | `L:+:x:-` or `L:-:x:+` | terminal 30-mer is its own reverse complement | none |
| unmatched | header and sequence disagree, or no link | | none |

A unitig whose terminal 30-mer is its own reverse complement is adjacent to
itself on the opposite strand, which creates a self-loop edge in the
assembly graph. That is a graph artifact, not a closed molecule: these are
linear contigs capped by an inverted repeat. On the measured sample the
palindrome held for 100% of the hairpin-linked records and 0% of the
circular-linked ones.

The header is the primary key and the sequence confirms it, because a
low-complexity AT- or CG-rich terminus is its own reverse complement by
accident and a sequence-only test would file such a circle as a hairpin.
Records whose header claims a circle but whose ends do not match are
labelled `unmatched` and left untrimmed rather than trimmed on a guess. On
real data this class is empty.

Hairpins are **labelled, not discarded**. Folding them with `--circ` joins
two ends that are not joined, so rod calls on that class should be read
with that in mind. They are kept because excluding them would remove a
substantial share of the input on a structural argument that has not been
tested, and because a terminal inverted repeat is a real feature worth screening. The
label travels in the header, so the classes can be separated downstream.
In the November 2026 run hairpins were called rod at twice the rate of
circles, with the excess entirely below 500 nt.

## Stage 3: length bounds

Two inclusive bounds for two different reasons.

The **200 nt floor** is biological. Nothing viroid-like is that small; the
smallest known agents are around 240 nt and the shortlist's shortest
candidate was 309 nt. Below it the unclassified set is dominated by
assembly fragments. In the October run, which had no floor, half of all rod
calls were under 200 nt but only 1.5% of the ribozyme-bearing ones.

The **6,000 nt ceiling** is a workaround for the folding tool. `RNAfold`
does not skip a sequence that exceeds its addressable range; it prints a
warning, emits nothing further, and exits 0, so every later record in the
batch is lost. Measured: 20,000 records in, 4,213 rows out, the 4,213 being
exactly the prefix up to a 44,528 nt record.

The ceiling is not lower because folding cost is cubic in length and the
0.15% of records above 3,000 nt carry 69% of the work, yet the targets live
in exactly that range: obelisks about 1,100 nt, ribozyviruses about
1,700 nt, ambiviruses about 5,000 nt. The records above 6,000 nt are parked,
not deleted; those up to about 20,000 nt would fold, slowly, in a separate
run.

## Stage 4: the rod screen

The external classifier (the Lebowski bundle, `docs/dependencies.md`)
computes per record:

| source | tool | features |
|---|---|---|
| composition | the sequence | GC content, keto bias |
| ORFs | `getorf` on the doubled sequence, so ORFs crossing the junction are found | ORF densities at 30 and 100 aa per kb |
| structure | `RNAfold --circ` | MFE per nt, fraction paired, hairpin and stem densities, stem lengths, multiloop density, branching degree, mean hairpin loop size |
| ribozymes | `cmsearch` against `dvr5.cm` and 18 Rfam ribozyme models | counts per strand and per family, corroboration between models at the same locus |

A random forest (500 trees, class-weight balanced) trained on 29,739
labelled sequences (20,344 `not_rod`, 9,395 `rod`: viroids, ribozyviruses,
obelisks, ambiviruses, DNA-virus genomes, host circRNAs from six species,
scrambled controls) returns a class and a confidence, the forest's vote
share for the winning class. Five-fold cross-validation gave accuracy and
F1 near 1.00; a label-shuffle baseline gave chance. That says the training
classes separate on these features, not how precise the calls are on
unknown circles from the SRA.

Structure features carry 82% of the forest's importance, composition 12%,
ORFs 5% and ribozymes 2%. A rod call therefore comes almost entirely from
fold shape; ribozyme hits are reported alongside it and drive the
shortlist, but hardly influence the call.

Two output columns need care. `below_confidence_floor` is always False:
the floor is 0.5 and a two-class winner is at least 0.5 by construction.
Threshold on `confidence` instead. And seven ribozyme columns appear twice
in the classifier's header; stage 5 checks the copies agree and drops the
second.

## Stage 5: the shortlist

Both tiers key on ribozymes on both strands, the rolling-circle hallmark.

* **Tier 1**: both strands and at least one corroborated locus, meaning
  the in-house and the Rfam models agree on the same site. Taken in full.
* **Tier 2**: both strands, no corroboration, confidence at or above
  `[shortlist] tier2_min_confidence` (0.8), ranked by confidence and cut
  to `tier2_max_rows` (2,000).

The cut is the part to be careful about. The qualifying pool is much
larger than the cap (12,259 in the November run), so the effective
confidence cut is whatever the last kept row carries, and it falls inside
a run of rows tied at confidence 1.000, so which of those are kept is
arbitrary. The stage's summary reports how many qualifying rows were cut.
Raise the cap to include more.

## Stage 7: structures

`RNAfold --circ --noPS`, the command stage 4 used, so the structures are
the ones the features were computed from. The MFE is in kcal/mol and
equals `mfe_per_nt * length` from the screen.

## Known limitations

* Hairpin-class records are folded as circles (see stage 2).
* Rod calls below a few hundred nt are plentiful and mostly uninformative;
  stratify on length and closure class before reading rates.
* The classifier was trained with one sequence for some classes
  (retroviroids) and will miss them.
* Duplicates across SRA runs are not collapsed: a circle recovered from
  fifty runs is fifty records. Logan deduplicates within a run only.
* The Kraken2 database defines "known". A different build gives a
  different unclassified set.
