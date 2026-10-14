#!/bin/sh
# Start Luftkampf in VICE (VC20 + 3K). Joystick = numeric keypad (8/4/6/2, fire 0).
cd "$(dirname "$0")"
PRG=${1:-build/LUFTKAMPF.prg}
exec "$HOME/.local/opt/root/usr/bin/xvic-local" -memory 3k -joydev1 1 \
     -autostartprgmode 1 -autostart "$(pwd)/$PRG"
