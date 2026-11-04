# Stage 2: label how each record closes, trim the overlap

    ./workflow/02_circular_overlap/label_overlap.sh

Every record gets `ovl:<class> trim:<nt>` appended to its header. Records
whose self-links say "circular" and whose first `[overlap] length` bases
equal their last ones lose those trailing bases; hairpin and unmatched
records pass through untrimmed. Nothing is discarded. The rule and its
reasons are in `src/assiniboine/topology.py` and `docs/methods.md`.

| output | what it is |
|---|---|
| `labelled/part_NNN.fa` | every input record, trimmed where applicable, header tagged |
| `counts/part_NNN.tsv`, `summary.txt` | records per closure class |

Output stays two lines per record because stage 4 cuts on line counts.
