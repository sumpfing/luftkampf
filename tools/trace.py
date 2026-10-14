#!/usr/bin/env python3
"""Recursive-descent 6502 code tracer for LUFTKAMPF.prg.

Finds which bytes are reachable code starting from the given entry points
and prints code/data ranges (used to build the da65 info file).
Usage: trace.py PRG [entry ...]   (entries in hex, e.g. 040F)
"""
import sys

# mode -> instruction length
LEN = {"imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2, "izx": 2,
       "izy": 2, "rel": 2, "abs": 3, "abx": 3, "aby": 3, "ind": 3}

OPS = {}
def op(code, mn, mode):
    OPS[code] = (mn, mode)

for base, mn in ((0x00, "ora"), (0x20, "and"), (0x40, "eor"), (0x60, "adc"),
                 (0x80, "sta"), (0xA0, "lda"), (0xC0, "cmp"), (0xE0, "sbc")):
    for off, mode in ((0x01, "izx"), (0x05, "zp"), (0x09, "imm"), (0x0D, "abs"),
                      (0x11, "izy"), (0x15, "zpx"), (0x19, "aby"), (0x1D, "abx")):
        if not (mn == "sta" and mode == "imm"):
            op(base + off, mn, mode)
for base, mn in ((0x00, "asl"), (0x20, "rol"), (0x40, "lsr"), (0x60, "ror")):
    op(base + 0x06, mn, "zp"); op(base + 0x0A, mn, "acc"); op(base + 0x0E, mn, "abs")
    op(base + 0x16, mn, "zpx"); op(base + 0x1E, mn, "abx")
for code, mn, mode in (
    (0xC6, "dec", "zp"), (0xCE, "dec", "abs"), (0xD6, "dec", "zpx"), (0xDE, "dec", "abx"),
    (0xE6, "inc", "zp"), (0xEE, "inc", "abs"), (0xF6, "inc", "zpx"), (0xFE, "inc", "abx"),
    (0x86, "stx", "zp"), (0x8E, "stx", "abs"), (0x96, "stx", "zpy"),
    (0x84, "sty", "zp"), (0x8C, "sty", "abs"), (0x94, "sty", "zpx"),
    (0xA2, "ldx", "imm"), (0xA6, "ldx", "zp"), (0xAE, "ldx", "abs"), (0xB6, "ldx", "zpy"), (0xBE, "ldx", "aby"),
    (0xA0, "ldy", "imm"), (0xA4, "ldy", "zp"), (0xAC, "ldy", "abs"), (0xB4, "ldy", "zpx"), (0xBC, "ldy", "abx"),
    (0xE0, "cpx", "imm"), (0xE4, "cpx", "zp"), (0xEC, "cpx", "abs"),
    (0xC0, "cpy", "imm"), (0xC4, "cpy", "zp"), (0xCC, "cpy", "abs"),
    (0x24, "bit", "zp"), (0x2C, "bit", "abs"),
    (0x4C, "jmp", "abs"), (0x6C, "jmp", "ind"), (0x20, "jsr", "abs"),
    (0x00, "brk", "imp"), (0x40, "rti", "imp"), (0x60, "rts", "imp"), (0xEA, "nop", "imp"),
):
    op(code, mn, mode)
for code, mn in ((0x10, "bpl"), (0x30, "bmi"), (0x50, "bvc"), (0x70, "bvs"),
                 (0x90, "bcc"), (0xB0, "bcs"), (0xD0, "bne"), (0xF0, "beq")):
    op(code, mn, "rel")
for code, mn in ((0x08, "php"), (0x28, "plp"), (0x48, "pha"), (0x68, "pla"),
                 (0x88, "dey"), (0xA8, "tay"), (0xC8, "iny"), (0xE8, "inx"),
                 (0x18, "clc"), (0x38, "sec"), (0x58, "cli"), (0x78, "sei"),
                 (0xB8, "clv"), (0xD8, "cld"), (0xF8, "sed"), (0x8A, "txa"),
                 (0x9A, "txs"), (0xAA, "tax"), (0xBA, "tsx"), (0xCA, "dex"), (0x98, "tya")):
    op(code, mn, "imp")


def main():
    data = open(sys.argv[1], "rb").read()
    load = 0x0401  # file header says $1201, but SYS 1039 needs the 3K-expanded BASIC start
    mem = data[2:]
    end = load + len(mem)
    entries = [int(e, 16) for e in sys.argv[2:]] or [0x040F]
    code = set()      # addresses that are instruction bytes
    starts = set()    # instruction start addresses
    ext = set()       # external call/jump targets (ROM etc.)
    work = list(entries)
    while work:
        pc = work.pop()
        while load <= pc < end and pc not in starts:
            o = mem[pc - load]
            if o not in OPS:
                print(f"; WARN illegal opcode {o:02X} at {pc:04X}", file=sys.stderr)
                break
            mn, mode = OPS[o]
            n = LEN[mode]
            starts.add(pc)
            code.update(range(pc, pc + n))
            arg = mem[pc - load + 1] | (mem[pc - load + 2] << 8) if n == 3 else None
            if mode == "rel":
                d = mem[pc - load + 1]
                work.append(pc + 2 + (d - 256 if d > 127 else d))
            if mn in ("jsr", "jmp") and mode == "abs":
                if load <= arg < end:
                    work.append(arg)
                else:
                    ext.add(arg)
            if mn in ("rts", "rti", "brk") or mn == "jmp":
                break
            pc += n
    # ranges
    ranges, cur = [], None
    for a in range(load, end):
        kind = "code" if a in code else "data"
        if cur and cur[0] == kind:
            cur[2] = a
        else:
            cur = [kind, a, a]
            ranges.append(cur)
    for kind, a, b in ranges:
        print(f"{kind} {a:04X}-{b:04X} ({b - a + 1})")
    print("external targets:", " ".join(f"{e:04X}" for e in sorted(ext)))
    print(f"code bytes: {len(code)} of {len(mem)}")


main()
