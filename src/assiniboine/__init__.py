"""Assiniboine: screen circular sequencing contigs for rod-like, ribozyme-bearing RNAs.

The package holds the rules the pipeline applies and the small tools that
apply them. The order in which the stages run lives in ``workflow/``.

Modules
-------
config      load settings from TOML and hand them to the shell scripts
sequences   read and write the two-line FASTA records every stage uses
topology    stage 2: how a record closes (circular, hairpin, unmatched) and the overlap trim
filtering   stage 3: the length bounds
results     stage 5: reduce the screen output to the rod tables and the shortlist
manifest    stage 6: the one-row-per-record manifest and the rebuild it allows
dotbracket  stage 7: fold the rods again and keep their structures
validation  checks that guard hand-offs between stages
cli         the ``assiniboine`` command line
"""

__version__ = "1.0.0"
