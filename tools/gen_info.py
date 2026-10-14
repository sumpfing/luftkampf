#!/usr/bin/env python3
"""Build the da65 info file from the traced code ranges and labels.txt.

Usage: gen_info.py ranges.txt labels.txt > luftkampf.info
ranges.txt: lines "code|data AAAA-BBBB" (from trace.py)
labels.txt: "ADDR NAME [SIZE] ; comment"   (ADDR in hex, SIZE optional)
"""
import sys

ranges_file, labels_file = sys.argv[1:3]

print("""GLOBAL {
    INPUTNAME   "build/raw.bin";
    OUTPUTNAME  "src/luftkampf.s";
    STARTADDR   $0401;
    PAGELENGTH  0;
    CPU         "6502";
    COMMENTS    4;
};
""")

for line in open(ranges_file):
    kind, span = line.split()[:2]
    a, b = span.split("-")
    a, b = int(a, 16), int(b, 16)
    if kind == "code":
        print(f"RANGE {{ START ${a:04X}; END ${b:04X}; TYPE CODE; }};")
    else:
        # unused memory filled with $AA becomes .res, everything else bytes
        print(f"RANGE {{ START ${a:04X}; END ${b:04X}; TYPE BYTETABLE; }};")

for line in open(labels_file):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    comment = ""
    if ";" in line:
        line, comment = line.split(";", 1)
        comment = comment.strip().replace('"', "'")
    parts = line.split()
    addr, name = int(parts[0], 16), parts[1]
    size = f" SIZE {parts[2]};" if len(parts) > 2 else ""
    com = f' COMMENT "{comment}";' if comment else ""
    print(f'LABEL {{ ADDR ${addr:04X}; NAME "{name}";{size}{com} }};')
