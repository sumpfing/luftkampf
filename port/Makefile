# Native port of Luftkampf (raylib)
#   make            Linux build (system gcc, this machine) -> build/linux/luftkampf
#   make linux-compat  Linux build for glibc >= 2.29 (zig) -> build/linux-compat/luftkampf
#   make windows    Windows build (zig) -> build/windows/luftkampf.exe
#   make web        browser build (emsdk) -> build/web/luftkampf.html (one file)
#   make dist       archives in dist/
#   make data       regenerate src/gamedata.c / src/font.c

RAYLIB_LINUX ?= third_party/raylib-5.5_linux_amd64
RAYLIB_WIN   ?= third_party/raylib-5.5_win64_mingw-w64
RAYLIB_WEB   ?= third_party/raylib-5.5_webassembly
EMSDK        ?= third_party/emsdk
ZIG          ?= $(firstword $(wildcard third_party/zig*/zig) zig)
SRC    := src/luftkampf.c src/gamedata.c src/font.c
CFLAGS := -std=c99 -O2 -Wall -Wextra -Wno-unused-parameter

linux: build/linux/luftkampf

build/linux/luftkampf: $(SRC) src/gamedata.h
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -I$(RAYLIB_LINUX)/include -o $@ $(SRC) \
	    $(RAYLIB_LINUX)/lib/libraylib.a -lm -lpthread -ldl -lrt

linux-compat: build/linux-compat/luftkampf

build/linux-compat/luftkampf: $(SRC) src/gamedata.h
	mkdir -p $(dir $@)
	$(ZIG) cc -target x86_64-linux-gnu.2.31 $(CFLAGS) -I$(RAYLIB_LINUX)/include -o $@ $(SRC) \
	    $(RAYLIB_LINUX)/lib/libraylib.a -lm -lpthread -ldl -lrt

windows: build/windows/luftkampf.exe

build/windows/luftkampf.exe: $(SRC) src/gamedata.h
	mkdir -p $(dir $@)
	$(ZIG) cc -target x86_64-windows-gnu $(CFLAGS) -I$(RAYLIB_WIN)/include -o $@ $(SRC) \
	    $(RAYLIB_WIN)/lib/libraylib.a -lgdi32 -lwinmm -lopengl32 -Wl,--subsystem,windows

web: build/web/luftkampf.html

build/web/luftkampf.html: $(SRC) src/gamedata.h web/shell.html
	mkdir -p $(dir $@)
	EM_CONFIG=$(CURDIR)/$(EMSDK)/.emscripten $(EMSDK)/upstream/emscripten/emcc -std=c99 -O2 -Wall -DPLATFORM_WEB \
	    -I$(RAYLIB_WEB)/include -o $@ $(SRC) $(RAYLIB_WEB)/lib/libraylib.a \
	    -sUSE_GLFW=3 -sASYNCIFY -sASYNCIFY_STACK_SIZE=65536 -sALLOW_MEMORY_GROWTH=1 \
	    -sSINGLE_FILE=1 -sEXPORTED_RUNTIME_METHODS=callMain,HEAPF32,HEAP16,HEAPU8,ENV --shell-file web/shell.html

dist: build/linux-compat/luftkampf build/windows/luftkampf.exe build/web/luftkampf.html
	rm -rf dist && mkdir -p dist/luftkampf-linux-x86_64 dist/luftkampf-windows-x64
	cp build/linux-compat/luftkampf LIESMICH.txt dist/luftkampf-linux-x86_64/
	cp build/windows/luftkampf.exe LIESMICH.txt dist/luftkampf-windows-x64/
	cd dist && tar czf luftkampf-linux-x86_64.tar.gz luftkampf-linux-x86_64
	cd dist && zip -qr luftkampf-windows-x64.zip luftkampf-windows-x64
	cp build/web/luftkampf.html dist/luftkampf.html

data:
	python3 -I tools/extract_data.py ../original/LUFTKAMPF.prg > src/gamedata.c
	python3 -I tools/make_font.py > src/font.c

clean:
	rm -rf build dist

.PHONY: linux linux-compat windows web dist data clean
