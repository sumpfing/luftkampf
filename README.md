# Luftkampf – Commodore VC20 (1982)

Rekonstruierter, baubarer Quelltext des Commodore-Kassettenspiels **Luftkampf**
(Commodore GmbH, Art.-Nr. 130050, VC20 mit 3K-Speichererweiterung).

## Bauen und Starten

```
make          # baut build/LUFTKAMPF.prg und vergleicht mit dem Original
./run.sh      # startet das Spiel in VICE (VC20 + 3K)
make disasm   # erzeugt src/luftkampf.s neu (nach Änderungen an src/labels.txt)
```

Werkzeuge (ohne Root installiert unter `~/.local/opt/root/usr/bin`):
cc65 2.19 (`ca65`, `ld65`, `da65`) und VICE 3.7.1 (`xvic-local`, mit VC20-ROMs).

## Steuerung (in VICE: Ziffernblock = Joystick)

| Taste | Wirkung |
|---|---|
| 4 / 6 im Titelbild | 1 oder 2 Piloten wählen |
| 0 (Feuer) | Spiel starten / schießen |
| Richtung = Flugrichtung | schneller |
| Gegenrichtung | bremsen, bei Minimaltempo umkehren |
| 90° zur Flugrichtung | abbiegen (nur an Kreuzungen) |

Man fliegt durch die Straßen einer Stadt aus 7×7 Häuserblöcken und schießt
gegnerische Flugzeuge ab. Wer mit einem Gegner zusammenstößt, verliert ein Leben.
Ein Spiel dauert 5 Runden, danach folgen Punktestand und Höchstpunktzahl.

## Aufbau

| Datei | Inhalt |
|---|---|
| `original/LUFTKAMPF.prg` | Original (Quelle: lust-auf-nostalgie.de) |
| `src/luftkampf.s` | Assembler-Quelltext (ca65), kommentiert mit Adressen |
| `src/labels.txt` | Namen für Routinen, Variablen und Hardware-Register |
| `src/luftkampf.cfg`, `src/header.s` | Linker-Konfiguration, Ladeadresse |
| `tools/trace.py` | verfolgt den Programmfluss, trennt Code und Daten |
| `tools/gen_info.py`, `tools/postprocess.py` | erzeugen die da65-Steuerdatei / räumen die Ausgabe auf |
| `docs/` | Cover, Anleitung (Pappschuber), Screenshots |

Auffälligkeiten im Original:
- Zufallszahlen werden über den BASIC-Interpreter berechnet: Das Programm enthält
  den tokenisierten Ausdruck `10*RND(1)` und lässt ihn per GETBYT auswerten.
- Ein Demo-Modus (NMI-Timer, Zufalls-Joystick) ist vorhanden, wird aber nie aktiviert.
- Der Codestil (`clc` vor jedem Vergleich, Schleifen über Zähler im Speicher) deutet
  auf einen Compiler oder einen Makro-Assembler hin, nicht auf handoptimierten Code.

## Native Portierung (Linux / Windows)

Unter `port/` liegt eine Übersetzung des Spiels nach C mit raylib. Jede
6502-Routine ist eine C-Funktion gleichen Namens; Bildschirm, Zeichensatz und
Farbspeicher des VC20 werden nachgebildet, Grafiken und Texte stammen aus dem
Original. Das Tempo entspricht dem Original (gemessen: 5292 statt 5333 Takte
pro Spielschleife).

```
cd port
make               # Linux, dieser Rechner      -> build/linux/luftkampf
make linux-compat  # Linux ab glibc 2.29 (zig)  -> build/linux-compat/luftkampf
make windows       # Windows 10/11 (zig)         -> build/windows/luftkampf.exe
make web           # Browser (Emscripten)        -> build/web/luftkampf.html
make dist          # Archive + HTML in dist/
```

Die Browser-Version ist eine einzige HTML-Datei (WebAssembly eingebettet),
die ohne Server per Doppelklick läuft. Der Spielcode bleibt unverändert:
Emscripten-ASYNCIFY gibt in `frame()` nach jedem Bild die Kontrolle an den
Browser zurück.

Steuerung: Pfeiltasten/WASD/Ziffernblock, Feuer = Leertaste/Strg/Enter/0,
Gamepad, F11 = Vollbild, Esc = Ende (siehe `port/LIESMICH.txt`).

Testmodus ohne Fenster: `LK_INPUT="200:F,212:-" LK_SHOTS="300" LK_SHOTDIR=/tmp
LK_FRAMES=600 LK_DEBUG=1 ./build/linux/luftkampf` - Eingaben nach Bildnummer,
Screenshots als PNG, Takte pro Spielschleife auf stderr.
