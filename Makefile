# Luftkampf (Commodore VC20, 1982) - rebuild from reconstructed source
#   make          assemble build/LUFTKAMPF.prg and compare with the original
#   make disasm   regenerate src/luftkampf.s from the original + labels
#   make run      start the result in VICE (VC20 + 3K expansion)

BIN   ?= $(HOME)/.local/opt/root/usr/bin
CA65  := $(BIN)/ca65
LD65  := $(BIN)/ld65
DA65  := $(BIN)/da65
XVIC  ?= $(BIN)/xvic-local

ORIG  := original/LUFTKAMPF.prg
ENTRIES := 040F 09B7 09C3 09CF 09DB 0DAE 0E26 0E3F 11DB 1205 1215 1238 \
           0EE8 15A3 0EBF 0E9B 0F44 13BE 14E0 0BF1

all: build/LUFTKAMPF.prg
	@cmp $(ORIG) build/LUFTKAMPF.prg && echo "OK: build/LUFTKAMPF.prg is byte-identical to the original"

build/LUFTKAMPF.prg: src/luftkampf.s src/header.s src/luftkampf.cfg
	$(CA65) -o build/luftkampf.o src/luftkampf.s
	$(CA65) -o build/header.o src/header.s
	$(LD65) -C src/luftkampf.cfg -o $@ build/header.o build/luftkampf.o

disasm:
	tail -c +3 $(ORIG) > build/raw.bin
	python3 -I tools/trace.py $(ORIG) $(ENTRIES) | grep -E '^(code|data) [0-9A-F]' > build/ranges.txt
	python3 -I tools/gen_info.py build/ranges.txt src/labels.txt > build/luftkampf.info
	$(DA65) -i build/luftkampf.info
	python3 -I tools/postprocess.py src/luftkampf.s

run: build/LUFTKAMPF.prg
	./run.sh

.PHONY: all disasm run
