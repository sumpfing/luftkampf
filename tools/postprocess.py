#!/usr/bin/env python3
"""Tidy da65 output: put it in segment CODE and fold $AA fill runs into .res."""
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
out, run = [], 0
def flush():
    global run
    if run:
        out.append(f"        .res    {run}, $AA  ; unused RAM (fill pattern of the dump)")
        run = 0
for l in lines:
    m = re.fullmatch(r"\s+\.byte\s+(.*)", l)
    vals = [v.strip() for v in m.group(1).split(",")] if m else None
    if vals and all(v == "$AA" for v in vals) and len(vals) >= 4:
        run += len(vals); continue
    flush()
    if l.strip() == '.setcpu "6502"':
        out.append(l); out.append('        .segment "CODE"'); continue
    out.append(l)
flush()
HEADER = """; ============================================================================
; LUFTKAMPF - Commodore VC20 (VIC-20), Commodore GmbH 1982, Art.-Nr. 130050
; Needs the 3K RAM expansion (BASIC start $0401, SYS 1039).
;
; Source reconstructed from the original tape image by disassembly
; (tools/trace.py + da65, names from src/labels.txt). Rebuilding with
; 'make' yields a file byte-identical to original/LUFTKAMPF.prg.
;
; Memory map
;   $0401-$040E  BASIC line: 10 SYS(1039)
;   $0412-$0496  variables, object table (7 bytes/object):
;                enemies at offsets $00..$38, player $3F, shot $46
;   $04D0-$164F  program
;   $1800-$19FF  copy of the ROM character set (VIC charset base $1800)
;   $1A00-$1BFF  plane graphics, 4 directions x 8 pixel phases
;   $1C00-$1DFF  soft-sprite characters $80-$BF (built at runtime)
;   $1E00        screen (22x23)
; ============================================================================
"""
out = HEADER.splitlines() + out
open(path, "w").write("\n".join(out) + "\n")
