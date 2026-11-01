#!/usr/bin/env python3
"""Sankey figure of the run, labelled by README stage number.

Band width is proportional to record count. Stages 0 to 3 are final. Update
SCREENED and rerun as stage 4 progresses.
"""
import sys
from html import escape

SCREENED = 148166244
FINISHED_CHUNKS, TOTAL_CHUNKS = 79, 95
DONE_ROWS, ROD, ROD_CONFIDENT, ROD_RIBOZYME = 134666244, 8579005, 1321128, 31553

SOURCE = 900042456
CLASSIFIED, UNCLASSIFIED = 305036299, 595006157
CIRCULAR, HAIRPIN = 562743416, 32262741
IN_RANGE, IN_CIRC, IN_HP = 161292329, 140330297, 20962032
TOP_CLASSES = [('Eukaryota', 232188594), ('Root only', 47510836), ('Bacteria', 17018268)]
OUT_OF_RANGE = 433713828
OUT_CIRC, OUT_HP = CIRCULAR - IN_CIRC, HAIRPIN - IN_HP
assert CLASSIFIED + UNCLASSIFIED == SOURCE
assert CIRCULAR + HAIRPIN == UNCLASSIFIED == IN_RANGE + OUT_OF_RANGE
assert IN_CIRC + IN_HP == IN_RANGE
assert OUT_CIRC + OUT_HP == OUT_OF_RANGE

SCALE = 340 / SOURCE
# Pass "dark" to build review/pipeline_flow_dark.svg for black backgrounds
DARK = 'dark' in sys.argv[1:]
GREY, SLATE, GREEN, TEAL, BLUE = '#b9b9b9', '#74909c', '#55c866', '#3c7f98', '#3a3ae0'
FILTER, PLAIN, RUNNING = '#f7d6d6', '#ececec', '#dcdcfa'
TEXT, LABEL, LABEL_OPACITY, DASH, NODE = '#1c1c1c', '#f2f2f2', '.92', '#8a9aa1', '#7d8a8f'
if DARK:
    GREY, SLATE, TEAL, BLUE = '#8c8c8c', '#a3bcc7', '#4fa8c9', '#7474f7'
    FILTER, PLAIN, RUNNING = '#5c2c31', '#2c3136', '#30307a'
    TEXT, LABEL, LABEL_OPACITY, DASH, NODE = '#f0f0f0', '#1e2327', '.9', '#9fadb3', '#a3b0b5'
out = []


def h(n):
    return n * SCALE


def ribbon(x0, t0, b0, x1, t1, b1, fill, extra=''):
    m = (x0 + x1) / 2
    out.append(f'<path d="M{x0} {t0:.2f}C{m} {t0:.2f} {m} {t1:.2f} {x1} {t1:.2f}'
               f'L{x1} {b1:.2f}C{m} {b1:.2f} {m} {b0:.2f} {x0} {b0:.2f}Z" fill="{fill}" {extra}/>')


def node(x, top, bottom, fill=NODE):
    out.append(f'<rect x="{x}" y="{top:.2f}" width="6" height="{bottom - top:.2f}" fill="{fill}"/>')


def label(x, y, lines, dashed=False, center=False):
    """lines holds (bold, regular) pairs. y is the top of the box."""
    width = max(len(b + r) * 8.6 for b, r in lines) + 20
    height = 22 * len(lines) + 10
    if center:
        y -= height / 2
    style = f'fill="none" stroke="{DASH}" stroke-dasharray="5 4"' if dashed else f'fill="{LABEL}" fill-opacity="{LABEL_OPACITY}"'
    out.append(f'<rect x="{x}" y="{y:.1f}" width="{width:.0f}" height="{height}" rx="7" {style}/>')
    for i, (b, r) in enumerate(lines):
        indent = 24 if r.startswith('- ') else 10
        out.append(f'<text x="{x + indent}" y="{y + 22 + 22 * i:.1f}"><tspan class="b">{escape(b)}</tspan>'
                   f'{escape(r)}</text>')


def stage(x, number, name, fill=PLAIN, funnel=False):
    """Header for one README stage."""
    text = f'{number}  {name}'
    width = len(text) * 8.8 + 22
    if funnel:
        out.append(f'<path d="M{x} 92h26l-10 12v11l-6 3v-14z" fill="#f2b8b8"/>')
        x += 32
    out.append(f'<rect x="{x}" y="90" width="{width:.0f}" height="30" rx="6" fill="{fill}"/>')
    out.append(f'<text class="b" x="{x + 11}" y="110">{escape(text)}</text>')


stage(16, 0, 'Source')
stage(270, 1, 'Kraken filter', FILTER, funnel=True)
stage(590, 2, 'Circular overlap')
stage(880, 3, 'Length filter', FILTER, funnel=True)
stage(1130, 4, 'Rod screen', RUNNING)
stage(1392, 5, 'Results')

# Stage 0
label(16, 410, [('Logan selfloops', ''), ('', f'{SOURCE:,}')], center=True)
out.append('<path d="M196 410L270 240V580Z" fill="url(#fan)"/>')

# Stage 1
node(270, 240, 580)
split = 240 + h(UNCLASSIFIED)
top2 = 170
ribbon(276, 240, split, 590, top2, top2 + h(UNCLASSIFIED), 'url(#unclassified)')
ribbon(276, split, 580, 560, 486, 486 + h(CLASSIFIED), GREY)
label(570, 544, [('Classified: ', f'{CLASSIFIED:,}')] + [('', f'- {name}: {n:,}') for name, n in TOP_CLASSES],
      center=True)
label(310, 190, [('Unclassified: ', f'{UNCLASSIFIED:,}')])

# Stage 2 labels records and removes none
circ, hp = h(CIRCULAR), h(HAIRPIN)
node(590, top2, top2 + circ + hp)
ribbon(596, top2, top2 + circ, 880, top2, top2 + circ, GREEN, 'opacity=".78"')
ribbon(596, top2 + circ, top2 + circ + hp, 880, top2 + circ, top2 + circ + hp, TEAL)
label(630, 230, [('Circular: ', f'{CIRCULAR:,}')])
label(630, top2 + circ + hp + 10, [('Hairpin: ', f'{HAIRPIN:,}')])

# Stage 3
node(880, top2, top2 + circ + hp)
ic, ih, oc, oh = h(IN_CIRC), h(IN_HP), h(OUT_CIRC), h(OUT_HP)
ribbon(886, top2, top2 + ic, 1130, 150, 150 + ic, GREEN, 'opacity=".78"')
ribbon(886, top2 + ic, top2 + ic + ih, 1130, 150 + ic, 150 + ic + ih, TEAL)
start = top2 + ic + ih
ribbon(886, start, start + oc, 1130, 420, 420 + oc, GREY)
ribbon(886, start + oc, start + oc + oh, 1130, 420 + oc, 420 + oc + oh, SLATE)
node(1130, 420, 420 + oc + oh)
label(1146, 420 + (oc + oh) / 2, [('Out of range: ', f'{OUT_OF_RANGE:,}'), ('', f'- Circular: {OUT_CIRC:,}'),
                                  ('', f'- Hairpin: {OUT_HP:,}')], center=True)
label(960, 232, [('In range: ', f'{IN_RANGE:,}'), ('', f'- Circular: {IN_CIRC:,}'), ('', f'- Hairpin: {IN_HP:,}')])

# Stage 4 is running: the bar fills as records are screened
band = h(IN_RANGE)
node(1130, 150, 150 + band, BLUE)
out.append(f'<rect x="1136" y="150" width="{226 * SCREENED / IN_RANGE:.1f}" height="{band:.2f}" fill="{BLUE}" opacity=".7"/>')
out.append(f'<rect x="1136" y="150" width="226" height="{band:.2f}" fill="none" stroke="{BLUE}" '
           'stroke-width="1.2" stroke-dasharray="4 3"/>')
label(1146, 150 + band / 2, [('Screening ongoing: ', f'{SCREENED / IN_RANGE:.1%}')], center=True)

label(1200, 222, [('Ongoing: ', f'{FINISHED_CHUNKS} of {TOTAL_CHUNKS} chunks finished'),
                  ('', f'- Screened: {DONE_ROWS:,}'), ('', f'- Rod: {ROD:,}'),
                  ('', f'- Rod with confidence \u2265 0.8: {ROD_CONFIDENT:,}'),
                  ('', f'- Rod with a ribozyme: {ROD_RIBOZYME:,}')])

# Stage 5 has not started
label(1392, 150 + band / 2, [('Pending', '')], dashed=True, center=True)

head = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1560 620" width="1560" height="620" role="img" aria-labelledby="t d">
<title id="t">k2-circ rod screen Sankey</title>
<desc id="d">Stage 0, {SOURCE:,} records. Stage 1 splits them into {CLASSIFIED:,} classified and {UNCLASSIFIED:,} unclassified. Stage 2 labels {CIRCULAR:,} circular and {HAIRPIN:,} hairpin. Stage 3 keeps {IN_RANGE:,} in range ({IN_CIRC:,} circular, {IN_HP:,} hairpin) and sets aside {OUT_OF_RANGE:,} ({OUT_CIRC:,} circular, {OUT_HP:,} hairpin). Stage 4 is ongoing at {SCREENED / IN_RANGE:.1%} screened. Stage 5 is pending.</desc>
<style>
text {{ font-family: "Noto Sans", "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 14px; fill: {TEXT}; }}
.b {{ font-weight: 700; }}
.title {{ font-size: 24px; font-weight: 700; }}
</style>
<defs>
<linearGradient id="fan"><stop offset="0" stop-color="{GREY}" stop-opacity=".15"/><stop offset="1" stop-color="{GREY}"/></linearGradient>
<linearGradient id="unclassified"><stop offset="0" stop-color="{GREEN}" stop-opacity=".35"/><stop offset="1" stop-color="{GREEN}" stop-opacity=".85"/></linearGradient>
</defs>
<text class="title" x="16" y="36">k2-circ rod screen</text>
'''
open('review/pipeline_flow_dark.svg' if DARK else 'review/pipeline_flow.svg', 'w').write(head + '\n'.join(out) + '</svg>\n')
print('ok')
