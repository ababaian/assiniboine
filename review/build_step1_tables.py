#!/usr/bin/env python3
"""Step 1 review tables, from the Kraken2 reports only (no sequences needed).

classified_taxa.csv    one row per taxon, summed over all 21 parts
target_taxa.csv        the viroid-like and small circular clades
parts.csv              classified and unclassified counts per part
"""
import csv, glob, os, re

CLASSIFIED = 305036299
UNCLASSIFIED = 595006157
TARGETS = ['Pospiviroidae', 'Avsunviroidae', 'Ribozyviria', 'Anelloviridae',
           'Circoviridae', 'Genomoviridae']

taxa = {}
for path in sorted(glob.glob('01_kraken_filter/classified/part_*.report.txt')):
    stack = []
    for line in open(path):
        _, clade, direct, rank, taxid, raw = line.rstrip('\n').split('\t')
        depth = (len(raw) - len(raw.lstrip(' '))) // 2
        name = raw.strip()
        stack[depth:] = [name]
        t = taxa.setdefault(int(taxid), dict(name=name, rank=rank, clade=0,
                                             direct=0, lineage=';'.join(stack)))
        t['clade'] += int(clade)
        t['direct'] += int(direct)

assert sum(t['direct'] for t in taxa.values()) == CLASSIFIED
assert taxa[1]['clade'] == CLASSIFIED

def write_rows(path, rows):
    with open(path, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['taxid', 'name', 'rank', 'records_in_clade', 'records_assigned_here',
                    'pct_of_classified', 'lineage'])
        for taxid, t in rows:
            w.writerow([taxid, t['name'], t['rank'], t['clade'], t['direct'],
                        f"{100 * t['clade'] / CLASSIFIED:.6f}", t['lineage']])

ordered = sorted(taxa.items(), key=lambda kv: -kv[1]['clade'])
write_rows('review/classified_taxa.csv', ordered)
write_rows('review/target_taxa.csv',
           [(k, v) for k, v in ordered if v['name'] in TARGETS])

with open('review/parts.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['part', 'records', 'classified', 'unclassified', 'kout_bytes', 'classified_fa_bytes'])
    total_u = 0
    for line in open('01_kraken_filter/classified/rebuild_counts.tsv'):
        part, classified, status = line.split()
        assert status == 'ok'
        n = part.split('_')[1]
        first = open(f'01_kraken_filter/logs/report_part_{n}.txt').readline().split('\t')
        assert first[3] == 'U'
        u = int(first[1])
        total_u += u
        base = f'01_kraken_filter/classified/{part}'
        w.writerow([part, int(classified) + u, classified, u,
                    os.path.getsize(base + '.kout.zst'), os.path.getsize(base + '.fa.zst')])
assert total_u == UNCLASSIFIED
print(len(taxa), 'taxa; totals match')
