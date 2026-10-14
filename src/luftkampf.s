; ============================================================================
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
; da65 V2.18 - Ubuntu 2.19-1
; Created:    2026-10-14 01:39:59
; Input file: build/raw.bin
; Page:       1


        .setcpu "6502"
        .segment "CODE"

; ----------------------------------------------------------------------------
L0000           := $0000
VIC_HPOS        := $9000                        ; VIC: screen origin X
VIC_VPOS        := $9001
VIC_COLS        := $9002                        ; VIC: columns / screen address bit 9
VIC_ROWS        := $9003                        ; VIC: rows / char height
VIC_RASTER      := $9004
VIC_MEMPTR      := $9005                        ; VIC: screen + character memory location
VIC_VOICE1      := $900A
VIC_VOICE2      := $900B
VIC_VOICE3      := $900C
VIC_NOISE       := $900D
VIC_VOLUME      := $900E                        ; VIC: volume (low nibble) / aux colour
VIC_COLOR       := $900F                        ; VIC: background / border colour
VIA1_PRA        := $9111                        ; joystick up/down/left/fire
VIA1_DDRA       := $9113
VIA1_T2LO       := $9118
VIA1_T2HI       := $9119
VIA1_ACR        := $911B
VIA1_PCR        := $911C
VIA1_IFR        := $911D
VIA1_IER        := $911E
VIA2_PRB        := $9120                        ; keyboard column / joystick right (bit 7)
VIA2_PRA        := $9121
VIA2_DDRB       := $9122
BASIC_GETBYT    := $D79E
BASIC_LINPRT    := $DDCD                        ; print 16-bit number A/X
KERNAL_INITIO   := $E518
KERNAL_CLRSCR   := $E55F                        ; clear screen
KERNAL_CHROUT_SCREEN:= $E742
KERNAL_PUTCHAR  := $EAA1
KERNAL_SETCOLOR := $EAB2
KERNAL_RESTOR   := $FD52
KERNAL_RAMTAS   := $FD8D
KERNAL_IOINIT   := $FDF9
KERNAL_SETMSG   := $FF90
KERNAL_PLOT     := $FFF0
; ----------------------------------------------------------------------------
        .byte   $0D,$12,$0A,$00,$9E,$28,$31,$30 ; 0401 0D 12 0A 00 9E 28 31 30  .....(10
        .byte   $33,$39,$29,$00,$00,$00         ; 0409 33 39 29 00 00 00        39)...
; ----------------------------------------------------------------------------
; SYS 1039 lands here
entry:  jmp     start                           ; 040F 4C D0 04                 L..

; ----------------------------------------------------------------------------
; direction used by next_pos / try_dir (0=up 1=right 2=down 3=left)
move_dir:
        .byte   $00                             ; 0412 00                       .
spawn_dx:
        .byte   $00                             ; 0413 00                       .
spawn_dy:
        .byte   $00                             ; 0414 00                       .
spawn_dir:
        .byte   $00                             ; 0415 00                       .
spawn_speed:
        .byte   $00                             ; 0416 00                       .
spawn_x:.byte   $00                             ; 0417 00                       .
spawn_y:.byte   $00                             ; 0418 00                       .
; offset of the current object record (multiple of 7)
obj:    .byte   $00                             ; 0419 00                       .
idx_i:  .byte   $00                             ; 041A 00                       .
idx_j:  .byte   $00                             ; 041B 00                       .
; offset of the last enemy record
enemy_last:
        .byte   $00                             ; 041C 00                       .
tmp:    .byte   $00                             ; 041D 00                       .
tmp_dir:.byte   $00                             ; 041E 00                       .
; result of next_pos
next_x: .byte   $00                             ; 041F 00                       .
next_y: .byte   $00                             ; 0420 00                       .
shot_x: .byte   $00                             ; 0421 00                       .
shot_y: .byte   $00                             ; 0422 00                       .
; lives of the active pilot
lives:  .byte   $00                             ; 0423 00                       .
; lives per pilot (index 1..2)
lives_tab:
        .byte   $00,$00,$00                     ; 0424 00 00 00                 ...
turn_a: .byte   $00                             ; 0427 00                       .
turn_b: .byte   $00                             ; 0428 00                       .
; enemy: steps until next random decision
straight_count:
        .byte   $00                             ; 0429 00                       .
; active pilot 1/2
pilot:  .byte   $00                             ; 042A 00                       .
round:  .byte   $00                             ; 042B 00                       .
; rounds per game (5)
rounds: .byte   $00                             ; 042C 00                       .
; number of pilots 1/2
pilots: .byte   $00                             ; 042D 00                       .
unused_042E:
        .byte   $00                             ; 042E 00                       .
; fire button pressed
fire:   .byte   $00                             ; 042F 00                       .
joy_raw:.byte   $00                             ; 0430 00                       .
; joystick direction 0..3, 4 = centred
joy_dir:.byte   $00                             ; 0431 00                       .
; read_input jumps through this (joystick or demo)
input_vec:
        .byte   $AD,$14                         ; 0432 AD 14                    ..
unused_0434:
        .byte   $00,$00,$00,$00,$00,$00,$00     ; 0434 00 00 00 00 00 00 00     .......
expl_x: .byte   $00                             ; 043B 00                       .
expl_y: .byte   $00                             ; 043C 00                       .
; explosion sound/graphic countdown
expl_timer:
        .byte   $00                             ; 043D 00                       .
; sprite character pair (soft-sprites in charset)
chr_a:  .byte   $00                             ; 043E 00                       .
chr_b:  .byte   $00                             ; 043F 00                       .
; 16-bit score per pilot (pilot>>1<<1 indexed)
score:  .byte   $F0,$10,$85,$14                 ; 0440 F0 10 85 14              ....
bonus_msg_timer:
        .byte   $00                             ; 0444 00                       .
; player speed: frames per step (2..30)
player_delay:
        .byte   $00                             ; 0445 00                       .
; 0 = brake/reverse, 1 = accelerate, 2 = turn
stick_action:
        .byte   $00                             ; 0446 00                       .
; object table, 7 bytes per object: active
obj_active:
        .byte   $00                             ; 0447 00                       .
; column 0..21
obj_x:  .byte   $00                             ; 0448 00                       .
; row 0..21
obj_y:  .byte   $00                             ; 0449 00                       .
; pixel offset inside the cell 0..7
obj_shift:
        .byte   $00                             ; 044A 00                       .
; 0=up 1=right 2=down 3=left
obj_dir:.byte   $00                             ; 044B 00                       .
; delay reload value
obj_speed:
        .byte   $00                             ; 044C 00                       .
; delay counter
obj_delay:
        .byte   $00                             ; 044D 00                       .
; records: enemies 0..$38, player $3F, bullet $46
obj_table_rest:
        .byte   $03,$8E,$15,$03,$A9,$00,$85,$FD ; 044E 03 8E 15 03 A9 00 85 FD  ........
        .byte   $85,$FE,$A9,$80,$20,$90,$FF,$A9 ; 0456 85 FE A9 80 20 90 FF A9  .... ...
        .byte   $FF,$85,$16,$A9,$00,$85,$0F,$85 ; 045E FF 85 16 A9 00 85 0F 85  ........
        .byte   $0C,$85,$2F,$58,$00,$20,$99,$10 ; 0466 0C 85 2F 58 00 20 99 10  ../X. ..
        .byte   $68,$85,$05,$68,$85,$04,$68,$85 ; 046E 68 85 05 68 85 04 68 85  h..h..h.
        .byte   $03,$68,$85,$02,$68,$85,$01,$68 ; 0476 03 68 85 02 68 85 01 68  .h..h..h
        .byte   $85,$00,$BA,$86,$06,$38,$A5,$01 ; 047E 85 00 BA 86 06 38 A5 01  .....8..
        .byte   $E9,$02,$85,$01,$A5,$00,$E9,$00 ; 0486 E9 02 85 01 A5 00 E9 00  ........
        .byte   $85,$00,$A5,$16,$C9,$FF         ; 048E 85 00 A5 16 C9 FF        ......
hiscore:.byte   $F0,$1D                         ; 0494 F0 1D                    ..
engine_timer:
        .byte   $A6                             ; 0496 A6                       .
; explosion volume envelope (indexed by expl_timer)
expl_volume:
        .byte   $01,$02,$03,$04,$05,$06,$07,$08 ; 0497 01 02 03 04 05 06 07 08  ........
        .byte   $09,$0A,$0B,$0C,$0D,$0E,$0F,$0F ; 049F 09 0A 0B 0C 0D 0E 0F 0F  ........
        .byte   $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F ; 04A7 0F 0F 0F 0F 0F 0F 0F 0F  ........
        .byte   $0F,$0F,$0F,$0F,$0F,$0F,$0A,$00 ; 04AF 0F 0F 0F 0F 0F 0F 0A 00  ........
        .byte   $00,$00,$00,$0F,$0F,$0F,$0F,$0F ; 04B7 00 00 00 0F 0F 0F 0F 0F  ........
        .byte   $0F,$00,$00,$00,$00,$20,$8D,$FD ; 04BF 0F 00 00 00 00 20 8D FD  ..... ..
        .byte   $20,$52,$FD,$20,$F9,$FD,$20,$18 ; 04C7 20 52 FD 20 F9 FD 20 18   R. .. .
        .byte   $E5                             ; 04CF E5                       .
; ----------------------------------------------------------------------------
start:  lda     #$00                            ; 04D0 A9 00                    ..
        sta     hiscore                         ; 04D2 8D 94 04                 ...
        sta     hiscore+1                       ; 04D5 8D 95 04                 ...
        sta     bonus_msg_timer                 ; 04D8 8D 44 04                 .D.
title:  jsr     KERNAL_CLRSCR                   ; 04DB 20 5F E5                  _.
        lda     #$5B                            ; 04DE A9 5B                    .[
        sta     VIC_COLOR                       ; 04E0 8D 0F 90                 ...
        lda     #$F0                            ; 04E3 A9 F0                    ..
        sta     VIC_MEMPTR                      ; 04E5 8D 05 90                 ...
        lda     #$00                            ; 04E8 A9 00                    ..
        sta     $0286                           ; 04EA 8D 86 02                 ...
        ldx     #$02                            ; 04ED A2 02                    ..
        ldy     #$06                            ; 04EF A0 06                    ..
        jsr     print_texts                     ; 04F1 20 0C 0D                  ..
        jsr     delay                           ; 04F4 20 39 15                  9.
        jsr     delay                           ; 04F7 20 39 15                  9.
        jsr     use_joystick                    ; 04FA 20 90 0E                  ..
        jsr     pilot_menu                      ; 04FD 20 28 0C                  (.
        jsr     KERNAL_CLRSCR                   ; 0500 20 5F E5                  _.
new_game:
        lda     #$00                            ; 0503 A9 00                    ..
        sta     unused_0434                     ; 0505 8D 34 04                 .4.
        sta     fire                            ; 0508 8D 2F 04                 ./.
        sta     score                           ; 050B 8D 40 04                 .@.
        sta     score+1                         ; 050E 8D 41 04                 .A.
        sta     score+2                         ; 0511 8D 42 04                 .B.
        sta     score+3                         ; 0514 8D 43 04                 .C.
        ldx     #$07                            ; 0517 A2 07                    ..
L0519:  lda     #$FF                            ; 0519 A9 FF                    ..
        sta     sprite_chars+256,x              ; 051B 9D 00 1D                 ...
        lda     #$00                            ; 051E A9 00                    ..
        sta     charset_copy+256,x              ; 0520 9D 00 19                 ...
        dex                                     ; 0523 CA                       .
        bpl     L0519                           ; 0524 10 F3                    ..
        lda     #$08                            ; 0526 A9 08                    ..
        sta     lives_tab+1                     ; 0528 8D 25 04                 .%.
        sta     lives_tab+2                     ; 052B 8D 26 04                 .&.
        lda     #$01                            ; 052E A9 01                    ..
        sta     round                           ; 0530 8D 2B 04                 .+.
round_loop:
        cmp     rounds                          ; 0533 CD 2C 04                 .,.
        beq     L053D                           ; 0536 F0 05                    ..
        bcc     L053D                           ; 0538 90 03                    ..
        jmp     game_over                       ; 053A 4C CC 05                 L..

; ----------------------------------------------------------------------------
L053D:  lda     #$01                            ; 053D A9 01                    ..
        sta     pilot                           ; 053F 8D 2A 04                 .*.
pilot_loop:
        cmp     pilots                          ; 0542 CD 2D 04                 .-.
        beq     L054C                           ; 0545 F0 05                    ..
        bcc     L054C                           ; 0547 90 03                    ..
        jmp     L05C3                           ; 0549 4C C3 05                 L..

; ----------------------------------------------------------------------------
L054C:  ldx     pilot                           ; 054C AE 2A 04                 .*.
        lda     lives_tab,x                     ; 054F BD 24 04                 .$.
        sta     lives                           ; 0552 8D 23 04                 .#.
        sta     move_dir                        ; 0555 8D 12 04                 ...
        jsr     spawn_enemies                   ; 0558 20 9C 06                  ..
        jsr     show_pilot                      ; 055B 20 72 06                  r.
        jsr     draw_city                       ; 055E 20 23 08                  #.
        jsr     init_player                     ; 0561 20 0F 06                  ..
        lda     #$00                            ; 0564 A9 00                    ..
        jsr     add_score                       ; 0566 20 0C 15                  ..
; one frame: input, enemies, player, bullet, collisions
game_loop:
        lda     #$FE                            ; 0569 A9 FE                    ..
        cmp     $91                             ; 056B C5 91                    ..
        bne     L056F                           ; 056D D0 00                    ..
L056F:  jsr     read_input                      ; 056F 20 A0 15                  ..
        jsr     move_enemies                    ; 0572 20 ED 08                  ..
        jsr     player_control                  ; 0575 20 2F 0D                  /.
        jsr     fire_shot                       ; 0578 20 49 12                  I.
        jsr     update_explosion                ; 057B 20 E3 14                  ..
        jsr     bonus_msg_update                ; 057E 20 7C 15                  |.
        jsr     move_player_and_shot            ; 0581 20 BE 0F                  ..
        jsr     animate_objects                 ; 0584 20 90 0A                  ..
        jsr     check_collisions                ; 0587 20 1A 13                  ..
        bcc     game_loop                       ; 058A 90 DD                    ..
        lda     #$00                            ; 058C A9 00                    ..
        sta     VIC_VOLUME                      ; 058E 8D 0E 90                 ...
        ldx     pilot                           ; 0591 AE 2A 04                 .*.
        lda     lives                           ; 0594 AD 23 04                 .#.
        sta     lives_tab,x                     ; 0597 9D 24 04                 .$.
        lda     rounds                          ; 059A AD 2C 04                 .,.
        cmp     round                           ; 059D CD 2B 04                 .+.
        bne     L05A5                           ; 05A0 D0 03                    ..
        jmp     L05AB                           ; 05A2 4C AB 05                 L..

; ----------------------------------------------------------------------------
L05A5:  jsr     KERNAL_CLRSCR                   ; 05A5 20 5F E5                  _.
        jmp     L05BA                           ; 05A8 4C BA 05                 L..

; ----------------------------------------------------------------------------
L05AB:  clc                                     ; 05AB 18                       .
        lda     pilots                          ; 05AC AD 2D 04                 .-.
        cmp     pilot                           ; 05AF CD 2A 04                 .*.
        bne     L05B7                           ; 05B2 D0 03                    ..
        jmp     L05BA                           ; 05B4 4C BA 05                 L..

; ----------------------------------------------------------------------------
L05B7:  jsr     KERNAL_CLRSCR                   ; 05B7 20 5F E5                  _.
L05BA:  inc     pilot                           ; 05BA EE 2A 04                 .*.
        lda     pilot                           ; 05BD AD 2A 04                 .*.
        jmp     pilot_loop                      ; 05C0 4C 42 05                 LB.

; ----------------------------------------------------------------------------
L05C3:  inc     round                           ; 05C3 EE 2B 04                 .+.
        lda     round                           ; 05C6 AD 2B 04                 .+.
        jmp     round_loop                      ; 05C9 4C 33 05                 L3.

; ----------------------------------------------------------------------------
game_over:
        jsr     KERNAL_CLRSCR                   ; 05CC 20 5F E5                  _.
        lda     #$00                            ; 05CF A9 00                    ..
        sta     $0286                           ; 05D1 8D 86 02                 ...
        lda     #$F0                            ; 05D4 A9 F0                    ..
        sta     VIC_MEMPTR                      ; 05D6 8D 05 90                 ...
        ldx     #$F5                            ; 05D9 A2 F5                    ..
        ldy     #$05                            ; 05DB A0 05                    ..
        jsr     print_texts                     ; 05DD 20 0C 0D                  ..
        jsr     delay                           ; 05E0 20 39 15                  9.
        jsr     KERNAL_CLRSCR                   ; 05E3 20 5F E5                  _.
        jsr     show_scores                     ; 05E6 20 95 07                  ..
        jsr     delay                           ; 05E9 20 39 15                  9.
        jsr     delay                           ; 05EC 20 39 15                  9.
        jsr     delay                           ; 05EF 20 39 15                  9.
        jmp     title                           ; 05F2 4C DB 04                 L..

; ----------------------------------------------------------------------------
; screen texts: col,row,text,0 ... 0
txt_game_over:
        .byte   $05,$0A,$45,$4E,$44,$45,$20,$21 ; 05F5 05 0A 45 4E 44 45 20 21  ..ENDE !
        .byte   $20,$20,$20,$00,$00,$06,$0A,$4C ; 05FD 20 20 20 00 00 06 0A 4C     ....L
        .byte   $55,$46,$54,$4B,$41,$4D,$50,$46 ; 0605 55 46 54 4B 41 4D 50 46  UFTKAMPF
        .byte   $00,$00                         ; 060D 00 00                    ..
; ----------------------------------------------------------------------------
init_player:
        lda     #$BE                            ; 060F A9 BE                    ..
        sta     VIC_VOICE3                      ; 0611 8D 0C 90                 ...
        lda     #$3F                            ; 0614 A9 3F                    .?
        sta     obj                             ; 0616 8D 19 04                 ...
        tay                                     ; 0619 A8                       .
        lda     #$01                            ; 061A A9 01                    ..
        sta     obj_active,y                    ; 061C 99 47 04                 .G.
        lda     #$15                            ; 061F A9 15                    ..
        sta     obj_x,y                         ; 0621 99 48 04                 .H.
        lda     #$15                            ; 0624 A9 15                    ..
        sta     obj_y,y                         ; 0626 99 49 04                 .I.
        lda     #$03                            ; 0629 A9 03                    ..
        sta     obj_dir,y                       ; 062B 99 4B 04                 .K.
        lda     #$00                            ; 062E A9 00                    ..
        sta     obj_shift,y                     ; 0630 99 4A 04                 .J.
        lda     #$02                            ; 0633 A9 02                    ..
        sta     obj_speed,y                     ; 0635 99 4C 04                 .L.
        lda     #$01                            ; 0638 A9 01                    ..
        sta     obj_delay,y                     ; 063A 99 4D 04                 .M.
        lda     #$6A                            ; 063D A9 6A                    .j
        sta     $9E                             ; 063F 85 9E                    ..
        lda     #$06                            ; 0641 A9 06                    ..
        sta     $9F                             ; 0643 85 9F                    ..
        lda     #$00                            ; 0645 A9 00                    ..
        sta     $A6                             ; 0647 85 A6                    ..
        lda     #$1C                            ; 0649 A9 1C                    ..
        sta     $A7                             ; 064B 85 A7                    ..
        ldx     #$01                            ; 064D A2 01                    ..
        jmp     init_sprite                     ; 064F 4C 66 0F                 Lf.

; ----------------------------------------------------------------------------
; player plane bitmap, 4 directions x 8 bytes
gfx_player:
        .byte   $10,$10,$10,$10,$38,$7C,$7C,$44 ; 0652 10 10 10 10 38 7C 7C 44  ....8||D
        .byte   $00,$E0,$70,$7F,$70,$E0,$00,$00 ; 065A 00 E0 70 7F 70 E0 00 00  ..p.p...
        .byte   $22,$3E,$3E,$1C,$08,$08,$08,$08 ; 0662 22 3E 3E 1C 08 08 08 08  ">>.....
        .byte   $00,$00,$07,$0E,$FE,$0E,$07,$00 ; 066A 00 00 07 0E FE 0E 07 00  ........
; ----------------------------------------------------------------------------
; 'ACHTUNG ! PILOT n'
show_pilot:
        ldx     #$84                            ; 0672 A2 84                    ..
        ldy     #$06                            ; 0674 A0 06                    ..
        jsr     print_texts                     ; 0676 20 0C 0D                  ..
        lda     #$00                            ; 0679 A9 00                    ..
        ldx     pilot                           ; 067B AE 2A 04                 .*.
        jsr     BASIC_LINPRT                    ; 067E 20 CD DD                  ..
        jmp     delay                           ; 0681 4C 39 15                 L9.

; ----------------------------------------------------------------------------
txt_attention:
        .byte   $05,$0A,$41,$43,$48,$54,$55,$4E ; 0684 05 0A 41 43 48 54 55 4E  ..ACHTUN
        .byte   $47,$20,$21,$20,$00,$06,$0C,$50 ; 068C 47 20 21 20 00 06 0C 50  G ! ...P
        .byte   $49,$4C,$4F,$54,$20,$20,$00,$00 ; 0694 49 4C 4F 54 20 20 00 00  ILOT  ..
; ----------------------------------------------------------------------------
spawn_enemies:
        lda     #$03                            ; 069C A9 03                    ..
        sta     spawn_dx                        ; 069E 8D 13 04                 ...
        lda     #$00                            ; 06A1 A9 00                    ..
        sta     spawn_dy                        ; 06A3 8D 14 04                 ...
        lda     #$02                            ; 06A6 A9 02                    ..
        sta     spawn_dir                       ; 06A8 8D 15 04                 ...
        lda     #$03                            ; 06AB A9 03                    ..
        sta     spawn_speed                     ; 06AD 8D 16 04                 ...
        lda     #$00                            ; 06B0 A9 00                    ..
        sta     spawn_x                         ; 06B2 8D 17 04                 ...
        lda     #$00                            ; 06B5 A9 00                    ..
        sta     spawn_y                         ; 06B7 8D 18 04                 ...
        lda     #$00                            ; 06BA A9 00                    ..
        sta     obj                             ; 06BC 8D 19 04                 ...
spawn_clear_loop:
        cmp     #$46                            ; 06BF C9 46                    .F
        beq     L06C8                           ; 06C1 F0 05                    ..
        bcc     L06C8                           ; 06C3 90 03                    ..
        jmp     L06DE                           ; 06C5 4C DE 06                 L..

; ----------------------------------------------------------------------------
L06C8:  clc                                     ; 06C8 18                       .
        lda     obj                             ; 06C9 AD 19 04                 ...
        tay                                     ; 06CC A8                       .
        lda     #$00                            ; 06CD A9 00                    ..
        sta     obj_active,y                    ; 06CF 99 47 04                 .G.
        lda     #$07                            ; 06D2 A9 07                    ..
        clc                                     ; 06D4 18                       .
        adc     obj                             ; 06D5 6D 19 04                 m..
        sta     obj                             ; 06D8 8D 19 04                 ...
        jmp     spawn_clear_loop                ; 06DB 4C BF 06                 L..

; ----------------------------------------------------------------------------
L06DE:  lda     #$00                            ; 06DE A9 00                    ..
        sta     enemy_last                      ; 06E0 8D 1C 04                 ...
        lda     move_dir                        ; 06E3 AD 12 04                 ...
        sta     lives                           ; 06E6 8D 23 04                 .#.
        lda     #$00                            ; 06E9 A9 00                    ..
        sta     idx_i                           ; 06EB 8D 1A 04                 ...
        lda     #$01                            ; 06EE A9 01                    ..
        sta     obj                             ; 06F0 8D 19 04                 ...
spawn_loop:
        cmp     move_dir                        ; 06F3 CD 12 04                 ...
        beq     L06FD                           ; 06F6 F0 05                    ..
        bcc     L06FD                           ; 06F8 90 03                    ..
        jmp     spawn_done                      ; 06FA 4C 94 07                 L..

; ----------------------------------------------------------------------------
L06FD:  clc                                     ; 06FD 18                       .
        lda     #$A0                            ; 06FE A9 A0                    ..
        cmp     idx_i                           ; 0700 CD 1A 04                 ...
        bcc     L0708                           ; 0703 90 03                    ..
        jmp     L070B                           ; 0705 4C 0B 07                 L..

; ----------------------------------------------------------------------------
L0708:  jmp     spawn_done                      ; 0708 4C 94 07                 L..

; ----------------------------------------------------------------------------
L070B:  clc                                     ; 070B 18                       .
        clc                                     ; 070C 18                       .
        lda     idx_i                           ; 070D AD 1A 04                 ...
        tay                                     ; 0710 A8                       .
        lda     #$00                            ; 0711 A9 00                    ..
        cmp     obj_active,y                    ; 0713 D9 47 04                 .G.
        beq     L071B                           ; 0716 F0 03                    ..
        jmp     L0782                           ; 0718 4C 82 07                 L..

; ----------------------------------------------------------------------------
L071B:  clc                                     ; 071B 18                       .
        lda     enemy_last                      ; 071C AD 1C 04                 ...
        adc     #$07                            ; 071F 69 07                    i.
        sta     enemy_last                      ; 0721 8D 1C 04                 ...
        clc                                     ; 0724 18                       .
        lda     idx_i                           ; 0725 AD 1A 04                 ...
        tay                                     ; 0728 A8                       .
        lda     #$01                            ; 0729 A9 01                    ..
        sta     obj_active,y                    ; 072B 99 47 04                 .G.
        clc                                     ; 072E 18                       .
        lda     idx_i                           ; 072F AD 1A 04                 ...
        tay                                     ; 0732 A8                       .
        lda     spawn_x                         ; 0733 AD 17 04                 ...
        sta     obj_x,y                         ; 0736 99 48 04                 .H.
        clc                                     ; 0739 18                       .
        lda     idx_i                           ; 073A AD 1A 04                 ...
        tay                                     ; 073D A8                       .
        lda     spawn_y                         ; 073E AD 18 04                 ...
        sta     obj_y,y                         ; 0741 99 49 04                 .I.
        clc                                     ; 0744 18                       .
        lda     idx_i                           ; 0745 AD 1A 04                 ...
        tay                                     ; 0748 A8                       .
        lda     #$00                            ; 0749 A9 00                    ..
        sta     obj_shift,y                     ; 074B 99 4A 04                 .J.
        clc                                     ; 074E 18                       .
        lda     idx_i                           ; 074F AD 1A 04                 ...
        tay                                     ; 0752 A8                       .
        lda     spawn_dir                       ; 0753 AD 15 04                 ...
        sta     obj_dir,y                       ; 0756 99 4B 04                 .K.
        clc                                     ; 0759 18                       .
        lda     idx_i                           ; 075A AD 1A 04                 ...
        tay                                     ; 075D A8                       .
        lda     spawn_speed                     ; 075E AD 16 04                 ...
        sta     obj_speed,y                     ; 0761 99 4C 04                 .L.
        clc                                     ; 0764 18                       .
        lda     idx_i                           ; 0765 AD 1A 04                 ...
        tay                                     ; 0768 A8                       .
        lda     #$04                            ; 0769 A9 04                    ..
        sta     obj_delay,y                     ; 076B 99 4D 04                 .M.
        clc                                     ; 076E 18                       .
        lda     spawn_x                         ; 076F AD 17 04                 ...
        adc     spawn_dx                        ; 0772 6D 13 04                 m..
        sta     spawn_x                         ; 0775 8D 17 04                 ...
        clc                                     ; 0778 18                       .
        lda     spawn_y                         ; 0779 AD 18 04                 ...
        adc     spawn_dy                        ; 077C 6D 14 04                 m..
        sta     spawn_y                         ; 077F 8D 18 04                 ...
L0782:  clc                                     ; 0782 18                       .
        lda     idx_i                           ; 0783 AD 1A 04                 ...
        adc     #$07                            ; 0786 69 07                    i.
        sta     idx_i                           ; 0788 8D 1A 04                 ...
        inc     obj                             ; 078B EE 19 04                 ...
        lda     obj                             ; 078E AD 19 04                 ...
        jmp     spawn_loop                      ; 0791 4C F3 06                 L..

; ----------------------------------------------------------------------------
spawn_done:
        rts                                     ; 0794 60                       `

; ----------------------------------------------------------------------------
show_scores:
        ldx     #$E5                            ; 0795 A2 E5                    ..
        ldy     #$07                            ; 0797 A0 07                    ..
        jsr     print_texts                     ; 0799 20 0C 0D                  ..
        ldx     score                           ; 079C AE 40 04                 .@.
        lda     score+1                         ; 079F AD 41 04                 .A.
        jsr     update_hiscore                  ; 07A2 20 D2 07                  ..
        jsr     BASIC_LINPRT                    ; 07A5 20 CD DD                  ..
        lda     pilots                          ; 07A8 AD 2D 04                 .-.
        cmp     #$02                            ; 07AB C9 02                    ..
        bcc     L07C2                           ; 07AD 90 13                    ..
        ldx     #$F2                            ; 07AF A2 F2                    ..
        ldy     #$07                            ; 07B1 A0 07                    ..
        jsr     print_texts                     ; 07B3 20 0C 0D                  ..
        ldx     score+2                         ; 07B6 AE 42 04                 .B.
        lda     score+3                         ; 07B9 AD 43 04                 .C.
        jsr     update_hiscore                  ; 07BC 20 D2 07                  ..
        jsr     BASIC_LINPRT                    ; 07BF 20 CD DD                  ..
L07C2:  ldx     #$FF                            ; 07C2 A2 FF                    ..
        ldy     #$07                            ; 07C4 A0 07                    ..
        jsr     print_texts                     ; 07C6 20 0C 0D                  ..
        lda     hiscore+1                       ; 07C9 AD 95 04                 ...
        ldx     hiscore                         ; 07CC AE 94 04                 ...
        jmp     BASIC_LINPRT                    ; 07CF 4C CD DD                 L..

; ----------------------------------------------------------------------------
update_hiscore:
        cmp     hiscore+1                       ; 07D2 CD 95 04                 ...
        bcc     L07E4                           ; 07D5 90 0D                    ..
        bne     L07DE                           ; 07D7 D0 05                    ..
        cpx     hiscore                         ; 07D9 EC 94 04                 ...
        bcc     L07E4                           ; 07DC 90 06                    ..
L07DE:  sta     hiscore+1                       ; 07DE 8D 95 04                 ...
        stx     hiscore                         ; 07E1 8E 94 04                 ...
L07E4:  rts                                     ; 07E4 60                       `

; ----------------------------------------------------------------------------
txt_scores:
        .byte   $05,$04,$50,$49,$4C,$4F,$54,$20 ; 07E5 05 04 50 49 4C 4F 54 20  ..PILOT 
        .byte   $20,$31,$20,$00,$00,$05,$06,$50 ; 07ED 20 31 20 00 00 05 06 50   1 ....P
        .byte   $49,$4C,$4F,$54,$20,$20,$32,$20 ; 07F5 49 4C 4F 54 20 20 32 20  ILOT  2 
        .byte   $00,$00,$01,$09,$2A,$2A,$2A,$2A ; 07FD 00 00 01 09 2A 2A 2A 2A  ....****
        .byte   $2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A ; 0805 2A 2A 2A 2A 2A 2A 2A 2A  ********
        .byte   $2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A ; 080D 2A 2A 2A 2A 2A 2A 2A 2A  ********
        .byte   $00,$05,$0C,$4D,$41,$58,$50,$55 ; 0815 00 05 0C 4D 41 58 50 55  ...MAXPU
        .byte   $4E,$4B,$54,$45,$00,$00         ; 081D 4E 4B 54 45 00 00        NKTE..
; ----------------------------------------------------------------------------
; screen layout: 7x7 blocks of houses
draw_city:
        lda     #$6D                            ; 0823 A9 6D                    .m
        sta     VIC_COLOR                       ; 0825 8D 0F 90                 ...
        lda     #$FE                            ; 0828 A9 FE                    ..
        sta     VIC_MEMPTR                      ; 082A 8D 05 90                 ...
        jsr     copy_charset                    ; 082D 20 CF 08                  ..
        jsr     KERNAL_CLRSCR                   ; 0830 20 5F E5                  _.
        jsr     newline                         ; 0833 20 23 0C                  #.
        lda     #$12                            ; 0836 A9 12                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 0838 20 42 E7                  B.
        lda     #$07                            ; 083B A9 07                    ..
        sta     $0286                           ; 083D 8D 86 02                 ...
        lda     #$01                            ; 0840 A9 01                    ..
        sta     obj                             ; 0842 8D 19 04                 ...
L0845:  cmp     #$07                            ; 0845 C9 07                    ..
        beq     L084E                           ; 0847 F0 05                    ..
        bcc     L084E                           ; 0849 90 03                    ..
        jmp     L08A4                           ; 084B 4C A4 08                 L..

; ----------------------------------------------------------------------------
L084E:  lda     #$01                            ; 084E A9 01                    ..
        sta     idx_i                           ; 0850 8D 1A 04                 ...
L0853:  cmp     #$02                            ; 0853 C9 02                    ..
        beq     L085C                           ; 0855 F0 05                    ..
        bcc     L085C                           ; 0857 90 03                    ..
        jmp     L0893                           ; 0859 4C 93 08                 L..

; ----------------------------------------------------------------------------
L085C:  lda     #$01                            ; 085C A9 01                    ..
        sta     idx_j                           ; 085E 8D 1B 04                 ...
L0861:  cmp     #$07                            ; 0861 C9 07                    ..
        beq     L086A                           ; 0863 F0 05                    ..
        bcc     L086A                           ; 0865 90 03                    ..
        jmp     L0882                           ; 0867 4C 82 08                 L..

; ----------------------------------------------------------------------------
L086A:  lda     #$1D                            ; 086A A9 1D                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 086C 20 42 E7                  B.
        lda     #$20                            ; 086F A9 20                    . 
        jsr     KERNAL_CHROUT_SCREEN            ; 0871 20 42 E7                  B.
        lda     #$20                            ; 0874 A9 20                    . 
        jsr     KERNAL_CHROUT_SCREEN            ; 0876 20 42 E7                  B.
        inc     idx_j                           ; 0879 EE 1B 04                 ...
        lda     idx_j                           ; 087C AD 1B 04                 ...
        jmp     L0861                           ; 087F 4C 61 08                 La.

; ----------------------------------------------------------------------------
L0882:  jsr     newline                         ; 0882 20 23 0C                  #.
        lda     #$12                            ; 0885 A9 12                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 0887 20 42 E7                  B.
        inc     idx_i                           ; 088A EE 1A 04                 ...
        lda     idx_i                           ; 088D AD 1A 04                 ...
        jmp     L0853                           ; 0890 4C 53 08                 LS.

; ----------------------------------------------------------------------------
L0893:  jsr     newline                         ; 0893 20 23 0C                  #.
        lda     #$12                            ; 0896 A9 12                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 0898 20 42 E7                  B.
        inc     obj                             ; 089B EE 19 04                 ...
        lda     obj                             ; 089E AD 19 04                 ...
        jmp     L0845                           ; 08A1 4C 45 08                 LE.

; ----------------------------------------------------------------------------
L08A4:  lda     #$00                            ; 08A4 A9 00                    ..
        sta     obj                             ; 08A6 8D 19 04                 ...
L08A9:  cmp     #$15                            ; 08A9 C9 15                    ..
        beq     L08B2                           ; 08AB F0 05                    ..
        bcc     L08B2                           ; 08AD 90 03                    ..
        jmp     L08C4                           ; 08AF 4C C4 08                 L..

; ----------------------------------------------------------------------------
L08B2:  lda     #$A0                            ; 08B2 A9 A0                    ..
        ldx     #$00                            ; 08B4 A2 00                    ..
        jsr     KERNAL_PUTCHAR                  ; 08B6 20 A1 EA                  ..
        inc     $D3                             ; 08B9 E6 D3                    ..
        inc     obj                             ; 08BB EE 19 04                 ...
        lda     obj                             ; 08BE AD 19 04                 ...
        jmp     L08A9                           ; 08C1 4C A9 08                 L..

; ----------------------------------------------------------------------------
L08C4:  lda     #$92                            ; 08C4 A9 92                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 08C6 20 42 E7                  B.
        lda     #$01                            ; 08C9 A9 01                    ..
        sta     $0286                           ; 08CB 8D 86 02                 ...
        rts                                     ; 08CE 60                       `

; ----------------------------------------------------------------------------
; ROM chars -> $1800 (custom charset base, $9005=$FE)
copy_charset:
        ldx     #$00                            ; 08CF A2 00                    ..
L08D1:  lda     $8000,x                         ; 08D1 BD 00 80                 ...
        sta     charset_copy,x                  ; 08D4 9D 00 18                 ...
        lda     $8100,x                         ; 08D7 BD 00 81                 ...
        sta     charset_copy+256,x              ; 08DA 9D 00 19                 ...
        lda     gfx_planes,x                    ; 08DD BD 00 1A                 ...
        sta     gfx_planes,x                    ; 08E0 9D 00 1A                 ...
        lda     gfx_planes+256,x                ; 08E3 BD 00 1B                 ...
        sta     gfx_planes+256,x                ; 08E6 9D 00 1B                 ...
        inx                                     ; 08E9 E8                       .
        bne     L08D1                           ; 08EA D0 E5                    ..
        rts                                     ; 08EC 60                       `

; ----------------------------------------------------------------------------
move_enemies:
        lda     #$00                            ; 08ED A9 00                    ..
        sta     obj                             ; 08EF 8D 19 04                 ...
L08F2:  cmp     enemy_last                      ; 08F2 CD 1C 04                 ...
        beq     L08FC                           ; 08F5 F0 05                    ..
        bcc     L08FC                           ; 08F7 90 03                    ..
        jmp     L0935                           ; 08F9 4C 35 09                 L5.

; ----------------------------------------------------------------------------
L08FC:  clc                                     ; 08FC 18                       .
        clc                                     ; 08FD 18                       .
        lda     obj                             ; 08FE AD 19 04                 ...
        tay                                     ; 0901 A8                       .
        lda     #$00                            ; 0902 A9 00                    ..
        cmp     obj_active,y                    ; 0904 D9 47 04                 .G.
        bcc     L090C                           ; 0907 90 03                    ..
        jmp     L0929                           ; 0909 4C 29 09                 L).

; ----------------------------------------------------------------------------
L090C:  clc                                     ; 090C 18                       .
        clc                                     ; 090D 18                       .
        lda     obj                             ; 090E AD 19 04                 ...
        tay                                     ; 0911 A8                       .
        lda     #$07                            ; 0912 A9 07                    ..
        cmp     obj_shift,y                     ; 0914 D9 4A 04                 .J.
        beq     L091C                           ; 0917 F0 03                    ..
        jmp     L0929                           ; 0919 4C 29 09                 L).

; ----------------------------------------------------------------------------
L091C:  jsr     enemy_step                      ; 091C 20 36 09                  6.
        clc                                     ; 091F 18                       .
        lda     obj                             ; 0920 AD 19 04                 ...
        tay                                     ; 0923 A8                       .
        lda     #$00                            ; 0924 A9 00                    ..
        sta     obj_shift,y                     ; 0926 99 4A 04                 .J.
L0929:  lda     #$07                            ; 0929 A9 07                    ..
        clc                                     ; 092B 18                       .
        adc     obj                             ; 092C 6D 19 04                 m..
        sta     obj                             ; 092F 8D 19 04                 ...
        jmp     L08F2                           ; 0932 4C F2 08                 L..

; ----------------------------------------------------------------------------
L0935:  rts                                     ; 0935 60                       `

; ----------------------------------------------------------------------------
; move one enemy, maybe turn at random
enemy_step:
        jsr     move_obj                        ; 0936 20 92 09                  ..
        sta     next_y                          ; 0939 8D 20 04                 . .
        clc                                     ; 093C 18                       .
        lda     tmp                             ; 093D AD 1D 04                 ...
        tax                                     ; 0940 AA                       .
        lda     cell_shift_tab,x                ; 0941 BD 8C 0A                 ...
        sta     next_x                          ; 0944 8D 1F 04                 ...
        clc                                     ; 0947 18                       .
        lda     next_x                          ; 0948 AD 1F 04                 ...
        cmp     next_y                          ; 094B CD 20 04                 . .
        beq     L0953                           ; 094E F0 03                    ..
        jmp     L0956                           ; 0950 4C 56 09                 LV.

; ----------------------------------------------------------------------------
L0953:  jmp     enemy_turn                      ; 0953 4C E7 09                 L..

; ----------------------------------------------------------------------------
L0956:  lda     tmp                             ; 0956 AD 1D 04                 ...
        sta     move_dir                        ; 0959 8D 12 04                 ...
        lda     tmp                             ; 095C AD 1D 04                 ...
        sta     tmp_dir                         ; 095F 8D 1E 04                 ...
        dec     straight_count                  ; 0962 CE 29 04                 .).
        clc                                     ; 0965 18                       .
        lda     #$00                            ; 0966 A9 00                    ..
        cmp     straight_count                  ; 0968 CD 29 04                 .).
        beq     L0970                           ; 096B F0 03                    ..
        jmp     L0979                           ; 096D 4C 79 09                 Ly.

; ----------------------------------------------------------------------------
L0970:  jsr     rnd10                           ; 0970 20 D0 0B                  ..
        lda     tmp                             ; 0973 AD 1D 04                 ...
        sta     straight_count                  ; 0976 8D 29 04                 .).
L0979:  clc                                     ; 0979 18                       .
        lda     #$08                            ; 097A A9 08                    ..
        cmp     tmp                             ; 097C CD 1D 04                 ...
        bcc     L0984                           ; 097F 90 03                    ..
        jmp     L0987                           ; 0981 4C 87 09                 L..

; ----------------------------------------------------------------------------
L0984:  jmp     enemy_turn                      ; 0984 4C E7 09                 L..

; ----------------------------------------------------------------------------
L0987:  jsr     try_dir                         ; 0987 20 70 0A                  p.
        bcs     enemy_turn                      ; 098A B0 5B                    .[
        jsr     draw_block                      ; 098C 20 13 0C                  ..
        jmp     erase_behind                    ; 098F 4C 96 0B                 L..

; ----------------------------------------------------------------------------
; dispatch obj_dir via move_tab
move_obj:
        clc                                     ; 0992 18                       .
        lda     obj                             ; 0993 AD 19 04                 ...
        tax                                     ; 0996 AA                       .
        lda     obj_dir,x                       ; 0997 BD 4B 04                 .K.
        sta     tmp                             ; 099A 8D 1D 04                 ...
        lda     tmp                             ; 099D AD 1D 04                 ...
        asl     a                               ; 09A0 0A                       .
        tax                                     ; 09A1 AA                       .
        lda     move_tab,x                      ; 09A2 BD AF 09                 ...
        sta     L0000                           ; 09A5 85 00                    ..
        lda     move_tab+1,x                    ; 09A7 BD B0 09                 ...
        sta     $01                             ; 09AA 85 01                    ..
        jmp     (L0000)                         ; 09AC 6C 00 00                 l..

; ----------------------------------------------------------------------------
move_tab:
        .byte   $B7,$09,$C3,$09,$CF,$09,$DB,$09 ; 09AF B7 09 C3 09 CF 09 DB 09  ........
; ----------------------------------------------------------------------------
move_up:ldx     obj                             ; 09B7 AE 19 04                 ...
        ldy     obj_y,x                         ; 09BA BC 49 04                 .I.
        dey                                     ; 09BD 88                       .
        tya                                     ; 09BE 98                       .
        sta     obj_y,x                         ; 09BF 9D 49 04                 .I.
        rts                                     ; 09C2 60                       `

; ----------------------------------------------------------------------------
move_right:
        ldx     obj                             ; 09C3 AE 19 04                 ...
        ldy     obj_x,x                         ; 09C6 BC 48 04                 .H.
        iny                                     ; 09C9 C8                       .
        tya                                     ; 09CA 98                       .
        sta     obj_x,x                         ; 09CB 9D 48 04                 .H.
        rts                                     ; 09CE 60                       `

; ----------------------------------------------------------------------------
move_down:
        ldx     obj                             ; 09CF AE 19 04                 ...
        ldy     obj_y,x                         ; 09D2 BC 49 04                 .I.
        iny                                     ; 09D5 C8                       .
        tya                                     ; 09D6 98                       .
        sta     obj_y,x                         ; 09D7 9D 49 04                 .I.
        rts                                     ; 09DA 60                       `

; ----------------------------------------------------------------------------
move_left:
        ldx     obj                             ; 09DB AE 19 04                 ...
        ldy     obj_x,x                         ; 09DE BC 48 04                 .H.
        dey                                     ; 09E1 88                       .
        tya                                     ; 09E2 98                       .
        sta     obj_x,x                         ; 09E3 9D 48 04                 .H.
        rts                                     ; 09E6 60                       `

; ----------------------------------------------------------------------------
enemy_turn:
        jsr     rnd10                           ; 09E7 20 D0 0B                  ..
        clc                                     ; 09EA 18                       .
        lda     obj                             ; 09EB AD 19 04                 ...
        tax                                     ; 09EE AA                       .
        lda     obj_dir,x                       ; 09EF BD 4B 04                 .K.
        sta     tmp_dir                         ; 09F2 8D 1E 04                 ...
        clc                                     ; 09F5 18                       .
        lda     tmp_dir                         ; 09F6 AD 1E 04                 ...
        tax                                     ; 09F9 AA                       .
        lda     turn_tab_a,x                    ; 09FA BD 27 0A                 .'.
        sta     turn_a                          ; 09FD 8D 27 04                 .'.
        clc                                     ; 0A00 18                       .
        lda     tmp_dir                         ; 0A01 AD 1E 04                 ...
        tax                                     ; 0A04 AA                       .
        lda     turn_tab_b,x                    ; 0A05 BD 2B 0A                 .+.
        sta     turn_b                          ; 0A08 8D 28 04                 .(.
        jsr     try_turns                       ; 0A0B 20 33 0A                  3.
        bcs     L0A16                           ; 0A0E B0 06                    ..
        jsr     draw_block                      ; 0A10 20 13 0C                  ..
        jmp     erase_behind                    ; 0A13 4C 96 0B                 L..

; ----------------------------------------------------------------------------
L0A16:  clc                                     ; 0A16 18                       .
        lda     obj                             ; 0A17 AD 19 04                 ...
        tay                                     ; 0A1A A8                       .
        clc                                     ; 0A1B 18                       .
        lda     tmp_dir                         ; 0A1C AD 1E 04                 ...
        tax                                     ; 0A1F AA                       .
        lda     turn_tab_back,x                 ; 0A20 BD 2F 0A                 ./.
        sta     obj_dir,y                       ; 0A23 99 4B 04                 .K.
        rts                                     ; 0A26 60                       `

; ----------------------------------------------------------------------------
turn_tab_a:
        .byte   $01,$02,$03,$00                 ; 0A27 01 02 03 00              ....
turn_tab_b:
        .byte   $03,$00,$01,$02                 ; 0A2B 03 00 01 02              ....
turn_tab_back:
        .byte   $02,$03,$00,$01                 ; 0A2F 02 03 00 01              ....
; ----------------------------------------------------------------------------
try_turns:
        clc                                     ; 0A33 18                       .
        lda     #$05                            ; 0A34 A9 05                    ..
        cmp     tmp                             ; 0A36 CD 1D 04                 ...
        bcc     L0A3E                           ; 0A39 90 03                    ..
        jmp     L0A57                           ; 0A3B 4C 57 0A                 LW.

; ----------------------------------------------------------------------------
L0A3E:  lda     turn_a                          ; 0A3E AD 27 04                 .'.
        sta     move_dir                        ; 0A41 8D 12 04                 ...
        jsr     try_dir                         ; 0A44 20 70 0A                  p.
        bcc     L0A6E                           ; 0A47 90 25                    .%
        lda     turn_b                          ; 0A49 AD 28 04                 .(.
        sta     move_dir                        ; 0A4C 8D 12 04                 ...
        jsr     try_dir                         ; 0A4F 20 70 0A                  p.
        bcc     L0A6E                           ; 0A52 90 1A                    ..
        jmp     L0A6D                           ; 0A54 4C 6D 0A                 Lm.

; ----------------------------------------------------------------------------
L0A57:  lda     turn_b                          ; 0A57 AD 28 04                 .(.
        sta     move_dir                        ; 0A5A 8D 12 04                 ...
        jsr     try_dir                         ; 0A5D 20 70 0A                  p.
        bcc     L0A6E                           ; 0A60 90 0C                    ..
        lda     turn_a                          ; 0A62 AD 27 04                 .'.
        sta     move_dir                        ; 0A65 8D 12 04                 ...
        jsr     try_dir                         ; 0A68 20 70 0A                  p.
        bcc     L0A6E                           ; 0A6B 90 01                    ..
L0A6D:  rts                                     ; 0A6D 60                       `

; ----------------------------------------------------------------------------
L0A6E:  clc                                     ; 0A6E 18                       .
        rts                                     ; 0A6F 60                       `

; ----------------------------------------------------------------------------
; C=0: cell in move_dir is free -> obj_dir = move_dir
try_dir:jsr     next_pos                        ; 0A70 20 73 0B                  s.
        jsr     cell_blocked                    ; 0A73 20 C1 0B                  ..
        bcc     L0A7A                           ; 0A76 90 02                    ..
        sec                                     ; 0A78 38                       8
        rts                                     ; 0A79 60                       `

; ----------------------------------------------------------------------------
L0A7A:  jsr     check_bounds                    ; 0A7A 20 FE 0B                  ..
        bcs     L0A8B                           ; 0A7D B0 0C                    ..
        clc                                     ; 0A7F 18                       .
        lda     obj                             ; 0A80 AD 19 04                 ...
        tay                                     ; 0A83 A8                       .
        lda     move_dir                        ; 0A84 AD 12 04                 ...
        sta     obj_dir,y                       ; 0A87 99 4B 04                 .K.
        clc                                     ; 0A8A 18                       .
L0A8B:  rts                                     ; 0A8B 60                       `

; ----------------------------------------------------------------------------
cell_shift_tab:
        .byte   $00,$15,$15,$00                 ; 0A8C 00 15 15 00              ....
; ----------------------------------------------------------------------------
animate_objects:
        lda     #$00                            ; 0A90 A9 00                    ..
        sta     obj                             ; 0A92 8D 19 04                 ...
L0A95:  cmp     enemy_last                      ; 0A95 CD 1C 04                 ...
        beq     L0A9F                           ; 0A98 F0 05                    ..
        bcc     L0A9F                           ; 0A9A 90 03                    ..
        jmp     L0AFA                           ; 0A9C 4C FA 0A                 L..

; ----------------------------------------------------------------------------
L0A9F:  clc                                     ; 0A9F 18                       .
        clc                                     ; 0AA0 18                       .
        lda     obj                             ; 0AA1 AD 19 04                 ...
        tay                                     ; 0AA4 A8                       .
        lda     #$00                            ; 0AA5 A9 00                    ..
        cmp     obj_active,y                    ; 0AA7 D9 47 04                 .G.
        bne     L0AAF                           ; 0AAA D0 03                    ..
        jmp     L0AEE                           ; 0AAC 4C EE 0A                 L..

; ----------------------------------------------------------------------------
L0AAF:  clc                                     ; 0AAF 18                       .
        clc                                     ; 0AB0 18                       .
        lda     obj                             ; 0AB1 AD 19 04                 ...
        tay                                     ; 0AB4 A8                       .
        lda     #$00                            ; 0AB5 A9 00                    ..
        cmp     obj_delay,y                     ; 0AB7 D9 4D 04                 .M.
        bne     L0ABF                           ; 0ABA D0 03                    ..
        jmp     L0ADB                           ; 0ABC 4C DB 0A                 L..

; ----------------------------------------------------------------------------
L0ABF:  clc                                     ; 0ABF 18                       .
        lda     obj                             ; 0AC0 AD 19 04                 ...
        tax                                     ; 0AC3 AA                       .
        lda     obj_delay,x                     ; 0AC4 BD 4D 04                 .M.
        sta     tmp                             ; 0AC7 8D 1D 04                 ...
        dec     tmp                             ; 0ACA CE 1D 04                 ...
        clc                                     ; 0ACD 18                       .
        lda     obj                             ; 0ACE AD 19 04                 ...
        tay                                     ; 0AD1 A8                       .
        lda     tmp                             ; 0AD2 AD 1D 04                 ...
        sta     obj_delay,y                     ; 0AD5 99 4D 04                 .M.
        jmp     L0AEE                           ; 0AD8 4C EE 0A                 L..

; ----------------------------------------------------------------------------
L0ADB:  clc                                     ; 0ADB 18                       .
        lda     obj                             ; 0ADC AD 19 04                 ...
        tay                                     ; 0ADF A8                       .
        clc                                     ; 0AE0 18                       .
        lda     obj                             ; 0AE1 AD 19 04                 ...
        tax                                     ; 0AE4 AA                       .
        lda     obj_speed,x                     ; 0AE5 BD 4C 04                 .L.
        sta     obj_delay,y                     ; 0AE8 99 4D 04                 .M.
        jsr     animate_obj                     ; 0AEB 20 FB 0A                  ..
L0AEE:  lda     #$07                            ; 0AEE A9 07                    ..
        clc                                     ; 0AF0 18                       .
        adc     obj                             ; 0AF1 6D 19 04                 m..
        sta     obj                             ; 0AF4 8D 19 04                 ...
        jmp     L0A95                           ; 0AF7 4C 95 0A                 L..

; ----------------------------------------------------------------------------
L0AFA:  rts                                     ; 0AFA 60                       `

; ----------------------------------------------------------------------------
; scroll soft-sprite one pixel
animate_obj:
        clc                                     ; 0AFB 18                       .
        lda     obj                             ; 0AFC AD 19 04                 ...
        tax                                     ; 0AFF AA                       .
        lda     obj_shift,x                     ; 0B00 BD 4A 04                 .J.
        sta     tmp                             ; 0B03 8D 1D 04                 ...
        inc     tmp                             ; 0B06 EE 1D 04                 ...
        clc                                     ; 0B09 18                       .
        lda     obj                             ; 0B0A AD 19 04                 ...
        tay                                     ; 0B0D A8                       .
        lda     tmp                             ; 0B0E AD 1D 04                 ...
        sta     obj_shift,y                     ; 0B11 99 4A 04                 .J.
        clc                                     ; 0B14 18                       .
        lda     obj                             ; 0B15 AD 19 04                 ...
        tax                                     ; 0B18 AA                       .
        lda     obj_dir,x                       ; 0B19 BD 4B 04                 .K.
        sta     tmp                             ; 0B1C 8D 1D 04                 ...
        jsr     get_obj_pos                     ; 0B1F 20 B5 0B                  ..
        jsr     gotoxy                          ; 0B22 20 E7 0B                  ..
        ldx     #$03                            ; 0B25 A2 03                    ..
L0B27:  asl     tmp                             ; 0B27 0E 1D 04                 ...
        dex                                     ; 0B2A CA                       .
        bne     L0B27                           ; 0B2B D0 FA                    ..
        clc                                     ; 0B2D 18                       .
        clc                                     ; 0B2E 18                       .
        lda     obj                             ; 0B2F AD 19 04                 ...
        tax                                     ; 0B32 AA                       .
        lda     obj_shift,x                     ; 0B33 BD 4A 04                 .J.
        sta     tmp_dir                         ; 0B36 8D 1E 04                 ...
        lda     tmp_dir                         ; 0B39 AD 1E 04                 ...
        adc     tmp                             ; 0B3C 6D 1D 04                 m..
        adc     #$40                            ; 0B3F 69 40                    i@
        ldx     #$02                            ; 0B41 A2 02                    ..
        jsr     KERNAL_PUTCHAR                  ; 0B43 20 A1 EA                  ..
        lda     tmp_dir                         ; 0B46 AD 1E 04                 ...
        adc     tmp                             ; 0B49 6D 1D 04                 m..
        adc     #$60                            ; 0B4C 69 60                    i`
        sta     tmp_dir                         ; 0B4E 8D 1E 04                 ...
        clc                                     ; 0B51 18                       .
        lda     obj                             ; 0B52 AD 19 04                 ...
        tax                                     ; 0B55 AA                       .
        lda     obj_dir,x                       ; 0B56 BD 4B 04                 .K.
        sta     move_dir                        ; 0B59 8D 12 04                 ...
        jsr     try_dir                         ; 0B5C 20 70 0A                  p.
        ldx     next_x                          ; 0B5F AE 1F 04                 ...
        ldy     next_y                          ; 0B62 AC 20 04                 . .
        jsr     gotoxy                          ; 0B65 20 E7 0B                  ..
        lda     tmp_dir                         ; 0B68 AD 1E 04                 ...
        ldx     #$02                            ; 0B6B A2 02                    ..
        lda     tmp_dir                         ; 0B6D AD 1E 04                 ...
        jmp     KERNAL_PUTCHAR                  ; 0B70 4C A1 EA                 L..

; ----------------------------------------------------------------------------
; obj pos + step(move_dir) -> next_x/next_y
next_pos:
        jsr     get_obj_pos                     ; 0B73 20 B5 0B                  ..
next_pos_xy:
        tya                                     ; 0B76 98                       .
        ldy     move_dir                        ; 0B77 AC 12 04                 ...
        clc                                     ; 0B7A 18                       .
        adc     step_dy,y                       ; 0B7B 79 8E 0B                 y..
        pha                                     ; 0B7E 48                       H
        txa                                     ; 0B7F 8A                       .
        clc                                     ; 0B80 18                       .
        adc     step_dx,y                       ; 0B81 79 92 0B                 y..
        tax                                     ; 0B84 AA                       .
        pla                                     ; 0B85 68                       h
        tay                                     ; 0B86 A8                       .
        stx     next_x                          ; 0B87 8E 1F 04                 ...
        sty     next_y                          ; 0B8A 8C 20 04                 . .
        rts                                     ; 0B8D 60                       `

; ----------------------------------------------------------------------------
step_dy:.byte   $FF,$00,$01,$00                 ; 0B8E FF 00 01 00              ....
step_dx:.byte   $00,$01,$00,$FF                 ; 0B92 00 01 00 FF              ....
; ----------------------------------------------------------------------------
erase_behind:
        jsr     get_obj_pos                     ; 0B96 20 B5 0B                  ..
        tya                                     ; 0B99 98                       .
        ldy     tmp_dir                         ; 0B9A AC 1E 04                 ...
        clc                                     ; 0B9D 18                       .
        adc     back_dy,y                       ; 0B9E 79 B1 0B                 y..
        pha                                     ; 0BA1 48                       H
        txa                                     ; 0BA2 8A                       .
        clc                                     ; 0BA3 18                       .
        adc     back_dx,y                       ; 0BA4 79 AD 0B                 y..
        tax                                     ; 0BA7 AA                       .
        pla                                     ; 0BA8 68                       h
        tay                                     ; 0BA9 A8                       .
        jmp     clear_cell                      ; 0BAA 4C F4 0B                 L..

; ----------------------------------------------------------------------------
back_dx:.byte   $00,$FF,$00,$01                 ; 0BAD 00 FF 00 01              ....
back_dy:.byte   $01,$00,$FF,$00                 ; 0BB1 01 00 FF 00              ....
; ----------------------------------------------------------------------------
; X=col Y=row of obj
get_obj_pos:
        ldx     obj                             ; 0BB5 AE 19 04                 ...
        lda     obj_y,x                         ; 0BB8 BD 49 04                 .I.
        tay                                     ; 0BBB A8                       .
        lda     obj_x,x                         ; 0BBC BD 48 04                 .H.
        tax                                     ; 0BBF AA                       .
        rts                                     ; 0BC0 60                       `

; ----------------------------------------------------------------------------
; C=1 if screen cell is not a space
cell_blocked:
        jsr     gotoxy                          ; 0BC1 20 E7 0B                  ..
        ldy     $D3                             ; 0BC4 A4 D3                    ..
        lda     ($D1),y                         ; 0BC6 B1 D1                    ..
        cmp     #$20                            ; 0BC8 C9 20                    . 
        beq     L0BCE                           ; 0BCA F0 02                    ..
        sec                                     ; 0BCC 38                       8
        rts                                     ; 0BCD 60                       `

; ----------------------------------------------------------------------------
L0BCE:  clc                                     ; 0BCE 18                       .
        rts                                     ; 0BCF 60                       `

; ----------------------------------------------------------------------------
; tmp = INT(10*RND(1)) via BASIC GETBYT
rnd10:  lda     #$0B                            ; 0BD0 A9 0B                    ..
        sta     $7B                             ; 0BD2 85 7B                    .{
        lda     #$DF                            ; 0BD4 A9 DF                    ..
        sta     $7A                             ; 0BD6 85 7A                    .z
        jsr     BASIC_GETBYT                    ; 0BD8 20 9E D7                  ..
        stx     tmp                             ; 0BDB 8E 1D 04                 ...
        rts                                     ; 0BDE 60                       `

; ----------------------------------------------------------------------------
; tokenised BASIC '10*RND(1)'
basic_10rnd:
        .byte   $31,$30,$AC,$BB,$28,$31,$29,$00 ; 0BDF 31 30 AC BB 28 31 29 00  10..(1).
; ----------------------------------------------------------------------------
; X=col Y=row
gotoxy: clc                                     ; 0BE7 18                       .
        txa                                     ; 0BE8 8A                       .
        pha                                     ; 0BE9 48                       H
        tya                                     ; 0BEA 98                       .
        tax                                     ; 0BEB AA                       .
        pla                                     ; 0BEC 68                       h
        tay                                     ; 0BED A8                       .
        jmp     KERNAL_PLOT                     ; 0BEE 4C F0 FF                 L..

; ----------------------------------------------------------------------------
plot_unused:
        jmp     KERNAL_PLOT                     ; 0BF1 4C F0 FF                 L..

; ----------------------------------------------------------------------------
clear_cell:
        jsr     gotoxy                          ; 0BF4 20 E7 0B                  ..
        ldx     #$06                            ; 0BF7 A2 06                    ..
        lda     #$20                            ; 0BF9 A9 20                    . 
        jmp     KERNAL_PUTCHAR                  ; 0BFB 4C A1 EA                 L..

; ----------------------------------------------------------------------------
; C=1 if next_x/next_y off the 22x22 field
check_bounds:
        ldx     next_x                          ; 0BFE AE 1F 04                 ...
        bmi     L0C11                           ; 0C01 30 0E                    0.
        cpx     #$16                            ; 0C03 E0 16                    ..
        bcs     L0C11                           ; 0C05 B0 0A                    ..
        ldy     next_y                          ; 0C07 AC 20 04                 . .
        bmi     L0C11                           ; 0C0A 30 05                    0.
        cpy     #$16                            ; 0C0C C0 16                    ..
        bcs     L0C11                           ; 0C0E B0 01                    ..
        rts                                     ; 0C10 60                       `

; ----------------------------------------------------------------------------
L0C11:  sec                                     ; 0C11 38                       8
        rts                                     ; 0C12 60                       `

; ----------------------------------------------------------------------------
draw_block:
        ldx     next_x                          ; 0C13 AE 1F 04                 ...
        ldy     next_y                          ; 0C16 AC 20 04                 . .
        jsr     gotoxy                          ; 0C19 20 E7 0B                  ..
        lda     #$A0                            ; 0C1C A9 A0                    ..
        ldx     #$06                            ; 0C1E A2 06                    ..
        jmp     KERNAL_PUTCHAR                  ; 0C20 4C A1 EA                 L..

; ----------------------------------------------------------------------------
newline:lda     #$0D                            ; 0C23 A9 0D                    ..
        jmp     KERNAL_CHROUT_SCREEN            ; 0C25 4C 42 E7                 LB.

; ----------------------------------------------------------------------------
; title screen 'ANZAHL PILOTEN' 1/2
pilot_menu:
        sei                                     ; 0C28 78                       x
        lda     #$5A                            ; 0C29 A9 5A                    .Z
        sta     VIC_COLOR                       ; 0C2B 8D 0F 90                 ...
        lda     #$00                            ; 0C2E A9 00                    ..
        sta     $0286                           ; 0C30 8D 86 02                 ...
        jsr     KERNAL_CLRSCR                   ; 0C33 20 5F E5                  _.
        ldx     #$AC                            ; 0C36 A2 AC                    ..
        ldy     #$0C                            ; 0C38 A0 0C                    ..
        jsr     print_texts                     ; 0C3A 20 0C 0D                  ..
        lda     #$01                            ; 0C3D A9 01                    ..
        sta     $0286                           ; 0C3F 8D 86 02                 ...
        sta     $0278                           ; 0C42 8D 78 02                 .x.
        ldx     #$07                            ; 0C45 A2 07                    ..
        ldy     #$0C                            ; 0C47 A0 0C                    ..
        jsr     gotoxy                          ; 0C49 20 E7 0B                  ..
        lda     #$00                            ; 0C4C A9 00                    ..
        sta     $CC                             ; 0C4E 85 CC                    ..
        lda     #$01                            ; 0C50 A9 01                    ..
        sta     pilots                          ; 0C52 8D 2D 04                 .-.
        lda     #$01                            ; 0C55 A9 01                    ..
        sta     rounds                          ; 0C57 8D 2C 04                 .,.
        cli                                     ; 0C5A 58                       X
pilot_menu_loop:
        jsr     read_joystick                   ; 0C5B 20 A3 15                  ..
        lda     fire                            ; 0C5E AD 2F 04                 ./.
        cmp     #$00                            ; 0C61 C9 00                    ..
        beq     L0C68                           ; 0C63 F0 03                    ..
        jmp     L0C9D                           ; 0C65 4C 9D 0C                 L..

; ----------------------------------------------------------------------------
L0C68:  clc                                     ; 0C68 18                       .
        lda     #$03                            ; 0C69 A9 03                    ..
        cmp     joy_dir                         ; 0C6B CD 31 04                 .1.
        beq     L0C73                           ; 0C6E F0 03                    ..
        jmp     L0C83                           ; 0C70 4C 83 0C                 L..

; ----------------------------------------------------------------------------
L0C73:  jsr     cursor_off                      ; 0C73 20 FA 0C                  ..
        lda     #$07                            ; 0C76 A9 07                    ..
        sta     $D3                             ; 0C78 85 D3                    ..
        lda     #$01                            ; 0C7A A9 01                    ..
        sta     pilots                          ; 0C7C 8D 2D 04                 .-.
        lda     #$00                            ; 0C7F A9 00                    ..
        sta     $CC                             ; 0C81 85 CC                    ..
L0C83:  clc                                     ; 0C83 18                       .
        lda     #$01                            ; 0C84 A9 01                    ..
        cmp     joy_dir                         ; 0C86 CD 31 04                 .1.
        beq     L0C8E                           ; 0C89 F0 03                    ..
        jmp     L0C9A                           ; 0C8B 4C 9A 0C                 L..

; ----------------------------------------------------------------------------
L0C8E:  jsr     cursor_off                      ; 0C8E 20 FA 0C                  ..
        lda     #$0E                            ; 0C91 A9 0E                    ..
        sta     $D3                             ; 0C93 85 D3                    ..
        lda     #$02                            ; 0C95 A9 02                    ..
        sta     pilots                          ; 0C97 8D 2D 04                 .-.
L0C9A:  jmp     pilot_menu_loop                 ; 0C9A 4C 5B 0C                 L[.

; ----------------------------------------------------------------------------
L0C9D:  lda     #$01                            ; 0C9D A9 01                    ..
        sta     $CC                             ; 0C9F 85 CC                    ..
        lda     #$40                            ; 0CA1 A9 40                    .@
        sta     VIA1_IER                        ; 0CA3 8D 1E 91                 ...
        lda     #$05                            ; 0CA6 A9 05                    ..
        sta     rounds                          ; 0CA8 8D 2C 04                 .,.
        rts                                     ; 0CAB 60                       `

; ----------------------------------------------------------------------------
txt_menu:
        .byte   $07,$04,$41,$4E,$5A,$41,$48,$4C ; 0CAC 07 04 41 4E 5A 41 48 4C  ..ANZAHL
        .byte   $20,$20,$20,$00,$06,$06,$20,$20 ; 0CB4 20 20 20 00 06 06 20 20     ...  
        .byte   $20,$50,$49,$4C,$4F,$54,$45,$4E ; 0CBC 20 50 49 4C 4F 54 45 4E   PILOTEN
        .byte   $00,$06,$0B,$12,$1F,$20,$20,$20 ; 0CC4 00 06 0B 12 1F 20 20 20  .....   
        .byte   $92,$20,$20,$20,$20,$12,$20,$20 ; 0CCC 92 20 20 20 20 12 20 20  .    .  
        .byte   $20,$00,$06,$0C,$20,$05,$31,$1F ; 0CD4 20 00 06 0C 20 05 31 1F   ... .1.
        .byte   $20,$92,$20,$20,$20,$20,$12,$20 ; 0CDC 20 92 20 20 20 20 12 20   .    . 
        .byte   $05,$32,$1F,$20,$00,$06,$0D,$20 ; 0CE4 05 32 1F 20 00 06 0D 20  .2. ... 
        .byte   $20,$20,$92,$20,$20,$20,$20,$12 ; 0CEC 20 20 92 20 20 20 20 12    .    .
        .byte   $20,$20,$20,$92,$00,$00         ; 0CF4 20 20 20 92 00 00           ...
; ----------------------------------------------------------------------------
cursor_off:
        sei                                     ; 0CFA 78                       x
        lda     $CF                             ; 0CFB A5 CF                    ..
        beq     L0D0B                           ; 0CFD F0 0C                    ..
        lda     #$00                            ; 0CFF A9 00                    ..
        sta     $CF                             ; 0D01 85 CF                    ..
        lda     $CE                             ; 0D03 A5 CE                    ..
        ldx     $0278                           ; 0D05 AE 78 02                 .x.
        jmp     KERNAL_PUTCHAR                  ; 0D08 4C A1 EA                 L..

; ----------------------------------------------------------------------------
L0D0B:  rts                                     ; 0D0B 60                       `

; ----------------------------------------------------------------------------
; X/Y = pointer to text table (col,row,text,0 ... 0)
print_texts:
        stx     $7A                             ; 0D0C 86 7A                    .z
        sty     $7B                             ; 0D0E 84 7B                    .{
        ldy     #$FF                            ; 0D10 A0 FF                    ..
L0D12:  iny                                     ; 0D12 C8                       .
        lda     ($7A),y                         ; 0D13 B1 7A                    .z
        tax                                     ; 0D15 AA                       .
        beq     L0D2E                           ; 0D16 F0 16                    ..
        iny                                     ; 0D18 C8                       .
        tya                                     ; 0D19 98                       .
        pha                                     ; 0D1A 48                       H
        lda     ($7A),y                         ; 0D1B B1 7A                    .z
        tay                                     ; 0D1D A8                       .
        jsr     gotoxy                          ; 0D1E 20 E7 0B                  ..
        pla                                     ; 0D21 68                       h
        tay                                     ; 0D22 A8                       .
        iny                                     ; 0D23 C8                       .
L0D24:  lda     ($7A),y                         ; 0D24 B1 7A                    .z
        beq     L0D12                           ; 0D26 F0 EA                    ..
        jsr     KERNAL_CHROUT_SCREEN            ; 0D28 20 42 E7                  B.
        iny                                     ; 0D2B C8                       .
        bne     L0D24                           ; 0D2C D0 F6                    ..
L0D2E:  rts                                     ; 0D2E 60                       `

; ----------------------------------------------------------------------------
player_control:
        clc                                     ; 0D2F 18                       .
        lda     #$04                            ; 0D30 A9 04                    ..
        cmp     joy_dir                         ; 0D32 CD 31 04                 .1.
        beq     L0D3C                           ; 0D35 F0 05                    ..
        bcc     L0D3C                           ; 0D37 90 03                    ..
        jmp     L0D3D                           ; 0D39 4C 3D 0D                 L=.

; ----------------------------------------------------------------------------
L0D3C:  rts                                     ; 0D3C 60                       `

; ----------------------------------------------------------------------------
L0D3D:  clc                                     ; 0D3D 18                       .
        lda     #$3F                            ; 0D3E A9 3F                    .?
        tax                                     ; 0D40 AA                       .
        lda     obj_speed,x                     ; 0D41 BD 4C 04                 .L.
        sta     player_delay                    ; 0D44 8D 45 04                 .E.
        lda     #$3F                            ; 0D47 A9 3F                    .?
        sta     obj                             ; 0D49 8D 19 04                 ...
        clc                                     ; 0D4C 18                       .
        lda     #$3F                            ; 0D4D A9 3F                    .?
        tax                                     ; 0D4F AA                       .
        lda     obj_dir,x                       ; 0D50 BD 4B 04                 .K.
        sta     tmp_dir                         ; 0D53 8D 1E 04                 ...
        sec                                     ; 0D56 38                       8
        lda     tmp_dir                         ; 0D57 AD 1E 04                 ...
        sbc     joy_dir                         ; 0D5A ED 31 04                 .1.
        sta     tmp                             ; 0D5D 8D 1D 04                 ...
        lda     #$02                            ; 0D60 A9 02                    ..
        sta     stick_action                    ; 0D62 8D 46 04                 .F.
        clc                                     ; 0D65 18                       .
        lda     tmp_dir                         ; 0D66 AD 1E 04                 ...
        cmp     joy_dir                         ; 0D69 CD 31 04                 .1.
        beq     L0D71                           ; 0D6C F0 03                    ..
        jmp     L0D76                           ; 0D6E 4C 76 0D                 Lv.

; ----------------------------------------------------------------------------
L0D71:  lda     #$01                            ; 0D71 A9 01                    ..
        sta     stick_action                    ; 0D73 8D 46 04                 .F.
L0D76:  clc                                     ; 0D76 18                       .
        lda     #$02                            ; 0D77 A9 02                    ..
        cmp     tmp                             ; 0D79 CD 1D 04                 ...
        beq     L0D81                           ; 0D7C F0 03                    ..
        jmp     L0D86                           ; 0D7E 4C 86 0D                 L..

; ----------------------------------------------------------------------------
L0D81:  lda     #$00                            ; 0D81 A9 00                    ..
        sta     stick_action                    ; 0D83 8D 46 04                 .F.
L0D86:  clc                                     ; 0D86 18                       .
        lda     #$FE                            ; 0D87 A9 FE                    ..
        cmp     tmp                             ; 0D89 CD 1D 04                 ...
        beq     L0D91                           ; 0D8C F0 03                    ..
        jmp     L0D96                           ; 0D8E 4C 96 0D                 L..

; ----------------------------------------------------------------------------
L0D91:  lda     #$00                            ; 0D91 A9 00                    ..
        sta     stick_action                    ; 0D93 8D 46 04                 .F.
L0D96:  lda     stick_action                    ; 0D96 AD 46 04                 .F.
        asl     a                               ; 0D99 0A                       .
        tax                                     ; 0D9A AA                       .
        lda     stick_action_tab,x              ; 0D9B BD A8 0D                 ...
        sta     L0000                           ; 0D9E 85 00                    ..
        lda     stick_action_tab+1,x            ; 0DA0 BD A9 0D                 ...
        sta     $01                             ; 0DA3 85 01                    ..
        jmp     (L0000)                         ; 0DA5 6C 00 00                 l..

; ----------------------------------------------------------------------------
stick_action_tab:
        .byte   $AE,$0D,$26,$0E,$3F,$0E         ; 0DA8 AE 0D 26 0E 3F 0E        ..&.?.
; ----------------------------------------------------------------------------
brake_or_reverse:
        clc                                     ; 0DAE 18                       .
        lda     #$1E                            ; 0DAF A9 1E                    ..
        cmp     player_delay                    ; 0DB1 CD 45 04                 .E.
        beq     L0DB9                           ; 0DB4 F0 03                    ..
        jmp     L0E1A                           ; 0DB6 4C 1A 0E                 L..

; ----------------------------------------------------------------------------
L0DB9:  lda     #$08                            ; 0DB9 A9 08                    ..
        sec                                     ; 0DBB 38                       8
        ldx     #$3F                            ; 0DBC A2 3F                    .?
        sbc     obj_shift,x                     ; 0DBE FD 4A 04                 .J.
        sta     obj_shift,x                     ; 0DC1 9D 4A 04                 .J.
        jsr     move_obj                        ; 0DC4 20 92 09                  ..
        lda     joy_dir                         ; 0DC7 AD 31 04                 .1.
        ldx     obj                             ; 0DCA AE 19 04                 ...
        sta     obj_dir,x                       ; 0DCD 9D 4B 04                 .K.
        lda     sprite_chr_b+1                  ; 0DD0 AD 88 11                 ...
        sta     chr_b                           ; 0DD3 8D 3F 04                 .?.
        lda     sprite_chr_a+1                  ; 0DD6 AD 85 11                 ...
        sta     chr_a                           ; 0DD9 8D 3E 04                 .>.
        jsr     sprite_ptrs                     ; 0DDC 20 8D 11                  ..
        lda     #$01                            ; 0DDF A9 01                    ..
        sta     idx_i                           ; 0DE1 8D 1A 04                 ...
        jsr     sprite_gfx                      ; 0DE4 20 3D 11                  =.
        lda     sprite_chr_b+1                  ; 0DE7 AD 88 11                 ...
        sta     chr_a                           ; 0DEA 8D 3E 04                 .>.
        tay                                     ; 0DED A8                       .
        lda     sprite_chr_a+1                  ; 0DEE AD 85 11                 ...
        sta     chr_b                           ; 0DF1 8D 3F 04                 .?.
        sty     sprite_chr_a+1                  ; 0DF4 8C 85 11                 ...
        sta     sprite_chr_b+1                  ; 0DF7 8D 88 11                 ...
        jsr     sprite_ptrs                     ; 0DFA 20 8D 11                  ..
        ldy     #$07                            ; 0DFD A0 07                    ..
        lda     #$00                            ; 0DFF A9 00                    ..
L0E01:  sta     ($A6),y                         ; 0E01 91 A6                    ..
        dey                                     ; 0E03 88                       .
        bpl     L0E01                           ; 0E04 10 FB                    ..
        ldx     obj                             ; 0E06 AE 19 04                 ...
        lda     obj_shift,x                     ; 0E09 BD 4A 04                 .J.
        beq     L0E19                           ; 0E0C F0 0B                    ..
        sta     tmp                             ; 0E0E 8D 1D 04                 ...
L0E11:  jsr     shift_sprite                    ; 0E11 20 B6 11                  ..
        dec     tmp                             ; 0E14 CE 1D 04                 ...
        bne     L0E11                           ; 0E17 D0 F8                    ..
L0E19:  rts                                     ; 0E19 60                       `

; ----------------------------------------------------------------------------
L0E1A:  ldy     obj                             ; 0E1A AC 19 04                 ...
        lda     player_delay                    ; 0E1D AD 45 04                 .E.
        adc     #$01                            ; 0E20 69 01                    i.
        sta     obj_speed,y                     ; 0E22 99 4C 04                 .L.
        rts                                     ; 0E25 60                       `

; ----------------------------------------------------------------------------
accelerate:
        clc                                     ; 0E26 18                       .
        lda     #$02                            ; 0E27 A9 02                    ..
        cmp     player_delay                    ; 0E29 CD 45 04                 .E.
        beq     L0E31                           ; 0E2C F0 03                    ..
        jmp     L0E32                           ; 0E2E 4C 32 0E                 L2.

; ----------------------------------------------------------------------------
L0E31:  rts                                     ; 0E31 60                       `

; ----------------------------------------------------------------------------
L0E32:  ldy     obj                             ; 0E32 AC 19 04                 ...
        lda     player_delay                    ; 0E35 AD 45 04                 .E.
        sec                                     ; 0E38 38                       8
        sbc     #$01                            ; 0E39 E9 01                    ..
        sta     obj_speed,y                     ; 0E3B 99 4C 04                 .L.
        rts                                     ; 0E3E 60                       `

; ----------------------------------------------------------------------------
turn_player:
        clc                                     ; 0E3F 18                       .
        clc                                     ; 0E40 18                       .
        lda     obj                             ; 0E41 AD 19 04                 ...
        tay                                     ; 0E44 A8                       .
        lda     #$00                            ; 0E45 A9 00                    ..
        cmp     obj_shift,y                     ; 0E47 D9 4A 04                 .J.
        bne     L0E4F                           ; 0E4A D0 03                    ..
        jmp     L0E50                           ; 0E4C 4C 50 0E                 LP.

; ----------------------------------------------------------------------------
L0E4F:  rts                                     ; 0E4F 60                       `

; ----------------------------------------------------------------------------
L0E50:  lda     joy_dir                         ; 0E50 AD 31 04                 .1.
        sta     move_dir                        ; 0E53 8D 12 04                 ...
        ldy     obj                             ; 0E56 AC 19 04                 ...
        lda     obj_dir,y                       ; 0E59 B9 4B 04                 .K.
        pha                                     ; 0E5C 48                       H
        jsr     try_dir                         ; 0E5D 20 70 0A                  p.
        pla                                     ; 0E60 68                       h
        bcs     L0E8F                           ; 0E61 B0 2C                    .,
        sta     move_dir                        ; 0E63 8D 12 04                 ...
        jsr     next_pos                        ; 0E66 20 73 0B                  s.
        jsr     clear_cell                      ; 0E69 20 F4 0B                  ..
        ldy     obj                             ; 0E6C AC 19 04                 ...
        lda     joy_dir                         ; 0E6F AD 31 04                 .1.
        sta     obj_dir,y                       ; 0E72 99 4B 04                 .K.
        lda     sprite_chr_a+1                  ; 0E75 AD 85 11                 ...
        sta     chr_b                           ; 0E78 8D 3F 04                 .?.
        lda     sprite_chr_b+1                  ; 0E7B AD 88 11                 ...
        sta     chr_a                           ; 0E7E 8D 3E 04                 .>.
        jsr     sprite_ptrs                     ; 0E81 20 8D 11                  ..
        lda     #$01                            ; 0E84 A9 01                    ..
        sta     idx_i                           ; 0E86 8D 1A 04                 ...
        jsr     sprite_gfx                      ; 0E89 20 3D 11                  =.
        jmp     clear_cell                      ; 0E8C 4C F4 0B                 L..

; ----------------------------------------------------------------------------
L0E8F:  rts                                     ; 0E8F 60                       `

; ----------------------------------------------------------------------------
use_joystick:
        lda     #$A3                            ; 0E90 A9 A3                    ..
        sta     input_vec                       ; 0E92 8D 32 04                 .2.
        lda     #$15                            ; 0E95 A9 15                    ..
        sta     input_vec+1                     ; 0E97 8D 33 04                 .3.
        rts                                     ; 0E9A 60                       `

; ----------------------------------------------------------------------------
; unused: NMI timer for an attract mode
demo_timer_setup:
        lda     #$14                            ; 0E9B A9 14                    ..
        sta     tmp                             ; 0E9D 8D 1D 04                 ...
        lda     #$00                            ; 0EA0 A9 00                    ..
        sta     VIA1_PCR                        ; 0EA2 8D 1C 91                 ...
        lda     #$BF                            ; 0EA5 A9 BF                    ..
        sta     $0318                           ; 0EA7 8D 18 03                 ...
        lda     #$0E                            ; 0EAA A9 0E                    ..
        sta     $0319                           ; 0EAC 8D 19 03                 ...
        lda     #$A0                            ; 0EAF A9 A0                    ..
        sta     VIA1_IER                        ; 0EB1 8D 1E 91                 ...
        lda     #$FF                            ; 0EB4 A9 FF                    ..
        sta     VIA1_T2LO                       ; 0EB6 8D 18 91                 ...
        lda     #$FF                            ; 0EB9 A9 FF                    ..
        sta     VIA1_T2HI                       ; 0EBB 8D 19 91                 ...
        rts                                     ; 0EBE 60                       `

; ----------------------------------------------------------------------------
; unused
demo_nmi:
        pha                                     ; 0EBF 48                       H
        lda     #$FF                            ; 0EC0 A9 FF                    ..
        sta     VIA1_T2HI                       ; 0EC2 8D 19 91                 ...
        sta     VIA1_T2LO                       ; 0EC5 8D 18 91                 ...
        lda     VIA1_IFR                        ; 0EC8 AD 1D 91                 ...
        sta     VIA1_IFR                        ; 0ECB 8D 1D 91                 ...
        dec     tmp                             ; 0ECE CE 1D 04                 ...
        bne     L0EE7                           ; 0ED1 D0 14                    ..
        ldx     #$FF                            ; 0ED3 A2 FF                    ..
        txs                                     ; 0ED5 9A                       .
        lda     #$E8                            ; 0ED6 A9 E8                    ..
        sta     input_vec                       ; 0ED8 8D 32 04                 .2.
        lda     #$0E                            ; 0EDB A9 0E                    ..
        sta     input_vec+1                     ; 0EDD 8D 33 04                 .3.
        lda     #$01                            ; 0EE0 A9 01                    ..
        sta     $CC                             ; 0EE2 85 CC                    ..
        jmp     new_game                        ; 0EE4 4C 03 05                 L..

; ----------------------------------------------------------------------------
L0EE7:  rti                                     ; 0EE7 40                       @

; ----------------------------------------------------------------------------
; random joystick (unused attract mode)
demo_input:
        jsr     rnd10                           ; 0EE8 20 D0 0B                  ..
        lda     #$00                            ; 0EEB A9 00                    ..
        sta     fire                            ; 0EED 8D 2F 04                 ./.
        clc                                     ; 0EF0 18                       .
        lda     #$08                            ; 0EF1 A9 08                    ..
        cmp     tmp                             ; 0EF3 CD 1D 04                 ...
        bcc     L0EFB                           ; 0EF6 90 03                    ..
        jmp     L0F19                           ; 0EF8 4C 19 0F                 L..

; ----------------------------------------------------------------------------
L0EFB:  lda     #$1A                            ; 0EFB A9 1A                    ..
        sta     $7A                             ; 0EFD 85 7A                    .z
        lda     #$0F                            ; 0EFF A9 0F                    ..
        sta     $7B                             ; 0F01 85 7B                    .{
        jsr     BASIC_GETBYT                    ; 0F03 20 9E D7                  ..
        stx     joy_dir                         ; 0F06 8E 31 04                 .1.
        clc                                     ; 0F09 18                       .
        lda     #$04                            ; 0F0A A9 04                    ..
        cmp     joy_dir                         ; 0F0C CD 31 04                 .1.
        bcc     L0F14                           ; 0F0F 90 03                    ..
        jmp     L0F19                           ; 0F11 4C 19 0F                 L..

; ----------------------------------------------------------------------------
L0F14:  lda     #$01                            ; 0F14 A9 01                    ..
        sta     fire                            ; 0F16 8D 2F 04                 ./.
L0F19:  rts                                     ; 0F19 60                       `

; ----------------------------------------------------------------------------
basic_6rnd:
        .byte   $36,$AC,$BB,$28,$31,$29,$00     ; 0F1A 36 AC BB 28 31 29 00     6..(1).
; ----------------------------------------------------------------------------
rnd_bonus:
        lda     #$3D                            ; 0F21 A9 3D                    .=
        ldx     #$0F                            ; 0F23 A2 0F                    ..
        bne     L0F2B                           ; 0F25 D0 04                    ..
        lda     #$36                            ; 0F27 A9 36                    .6
        ldx     #$0F                            ; 0F29 A2 0F                    ..
L0F2B:  sta     $7A                             ; 0F2B 85 7A                    .z
        stx     $7B                             ; 0F2D 86 7B                    .{
        jsr     BASIC_GETBYT                    ; 0F2F 20 9E D7                  ..
        stx     tmp                             ; 0F32 8E 1D 04                 ...
        rts                                     ; 0F35 60                       `

; ----------------------------------------------------------------------------
basic_9rnd:
        .byte   $39,$AC,$BB,$28,$31,$29,$00,$34 ; 0F36 39 AC BB 28 31 29 00 34  9..(1).4
        .byte   $AC,$BB,$28,$31,$29,$00         ; 0F3E AC BB 28 31 29 00        ..(1).
; ----------------------------------------------------------------------------
; unused
clear_unused:
        lda     #$00                            ; 0F44 A9 00                    ..
        sta     idx_j                           ; 0F46 8D 1B 04                 ...
L0F49:  cmp     #$1F                            ; 0F49 C9 1F                    ..
        beq     L0F52                           ; 0F4B F0 05                    ..
        bcc     L0F52                           ; 0F4D 90 03                    ..
        jmp     L0F65                           ; 0F4F 4C 65 0F                 Le.

; ----------------------------------------------------------------------------
L0F52:  clc                                     ; 0F52 18                       .
        lda     idx_j                           ; 0F53 AD 1B 04                 ...
        tay                                     ; 0F56 A8                       .
        lda     #$FF                            ; 0F57 A9 FF                    ..
        sta     sprite_chars+48,y               ; 0F59 99 30 1C                 .0.
        inc     idx_j                           ; 0F5C EE 1B 04                 ...
        lda     idx_j                           ; 0F5F AD 1B 04                 ...
        jmp     L0F49                           ; 0F62 4C 49 0F                 LI.

; ----------------------------------------------------------------------------
L0F65:  rts                                     ; 0F65 60                       `

; ----------------------------------------------------------------------------
init_sprite:
        lda     sprite_chr_a,x                  ; 0F66 BD 84 11                 ...
        sta     chr_a                           ; 0F69 8D 3E 04                 .>.
        lda     sprite_chr_b,x                  ; 0F6C BD 87 11                 ...
        sta     chr_b                           ; 0F6F 8D 3F 04                 .?.
        lda     #$00                            ; 0F72 A9 00                    ..
        sta     idx_i                           ; 0F74 8D 1A 04                 ...
L0F77:  cmp     #$07                            ; 0F77 C9 07                    ..
        beq     L0F80                           ; 0F79 F0 05                    ..
        bcc     L0F80                           ; 0F7B 90 03                    ..
        jmp     L0F9B                           ; 0F7D 4C 9B 0F                 L..

; ----------------------------------------------------------------------------
L0F80:  ldy     idx_i                           ; 0F80 AC 1A 04                 ...
        lda     ($9E),y                         ; 0F83 B1 9E                    ..
        sta     ($A6),y                         ; 0F85 91 A6                    ..
        clc                                     ; 0F87 18                       .
        lda     idx_i                           ; 0F88 AD 1A 04                 ...
        adc     #$08                            ; 0F8B 69 08                    i.
        tay                                     ; 0F8D A8                       .
        lda     #$00                            ; 0F8E A9 00                    ..
        sta     ($A6),y                         ; 0F90 91 A6                    ..
        inc     idx_i                           ; 0F92 EE 1A 04                 ...
        lda     idx_i                           ; 0F95 AD 1A 04                 ...
        jmp     L0F77                           ; 0F98 4C 77 0F                 Lw.

; ----------------------------------------------------------------------------
L0F9B:  jsr     sprite_ptrs                     ; 0F9B 20 8D 11                  ..
        clc                                     ; 0F9E 18                       .
        lda     obj                             ; 0F9F AD 19 04                 ...
        tax                                     ; 0FA2 AA                       .
        lda     obj_shift,x                     ; 0FA3 BD 4A 04                 .J.
        sta     tmp                             ; 0FA6 8D 1D 04                 ...
L0FA9:  clc                                     ; 0FA9 18                       .
        lda     #$00                            ; 0FAA A9 00                    ..
        cmp     tmp                             ; 0FAC CD 1D 04                 ...
        bne     L0FB4                           ; 0FAF D0 03                    ..
        jmp     L0FBD                           ; 0FB1 4C BD 0F                 L..

; ----------------------------------------------------------------------------
L0FB4:  jsr     shift_sprite                    ; 0FB4 20 B6 11                  ..
        dec     tmp                             ; 0FB7 CE 1D 04                 ...
        jmp     L0FA9                           ; 0FBA 4C A9 0F                 L..

; ----------------------------------------------------------------------------
L0FBD:  rts                                     ; 0FBD 60                       `

; ----------------------------------------------------------------------------
move_player_and_shot:
        lda     #$00                            ; 0FBE A9 00                    ..
        sta     idx_i                           ; 0FC0 8D 1A 04                 ...
        lda     #$38                            ; 0FC3 A9 38                    .8
        sta     obj                             ; 0FC5 8D 19 04                 ...
L0FC8:  cmp     #$46                            ; 0FC8 C9 46                    .F
        beq     L0FD1                           ; 0FCA F0 05                    ..
        bcc     L0FD1                           ; 0FCC 90 03                    ..
        jmp     L113C                           ; 0FCE 4C 3C 11                 L<.

; ----------------------------------------------------------------------------
L0FD1:  clc                                     ; 0FD1 18                       .
        clc                                     ; 0FD2 18                       .
        lda     obj                             ; 0FD3 AD 19 04                 ...
        tay                                     ; 0FD6 A8                       .
        lda     #$00                            ; 0FD7 A9 00                    ..
        cmp     obj_active,y                    ; 0FD9 D9 47 04                 .G.
        bne     L0FE1                           ; 0FDC D0 03                    ..
        jmp     L112D                           ; 0FDE 4C 2D 11                 L-.

; ----------------------------------------------------------------------------
L0FE1:  ldx     obj_delay,y                     ; 0FE1 BE 4D 04                 .M.
        beq     L0FEE                           ; 0FE4 F0 08                    ..
        dex                                     ; 0FE6 CA                       .
        txa                                     ; 0FE7 8A                       .
        sta     obj_delay,y                     ; 0FE8 99 4D 04                 .M.
        jmp     L112D                           ; 0FEB 4C 2D 11                 L-.

; ----------------------------------------------------------------------------
L0FEE:  lda     engine_timer                    ; 0FEE AD 96 04                 ...
        bpl     L1005                           ; 0FF1 10 12                    ..
        lda     #$14                            ; 0FF3 A9 14                    ..
        sta     engine_timer                    ; 0FF5 8D 96 04                 ...
        lda     #$80                            ; 0FF8 A9 80                    ..
        eor     VIC_VOICE3                      ; 0FFA 4D 0C 90                 M..
        sta     VIC_VOICE3                      ; 0FFD 8D 0C 90                 ...
        lda     #$0F                            ; 1000 A9 0F                    ..
        sta     VIC_VOLUME                      ; 1002 8D 0E 90                 ...
L1005:  dec     engine_timer                    ; 1005 CE 96 04                 ...
        lda     obj_speed,y                     ; 1008 B9 4C 04                 .L.
        sta     obj_delay,y                     ; 100B 99 4D 04                 .M.
        ldx     obj_shift,y                     ; 100E BE 4A 04                 .J.
        inx                                     ; 1011 E8                       .
        txa                                     ; 1012 8A                       .
        sta     obj_shift,y                     ; 1013 99 4A 04                 .J.
        ldx     idx_i                           ; 1016 AE 1A 04                 ...
        lda     sprite_chr_a,x                  ; 1019 BD 84 11                 ...
        sta     chr_a                           ; 101C 8D 3E 04                 .>.
        clc                                     ; 101F 18                       .
        ldx     idx_i                           ; 1020 AE 1A 04                 ...
        lda     sprite_chr_b,x                  ; 1023 BD 87 11                 ...
        sta     chr_b                           ; 1026 8D 3F 04                 .?.
        jsr     sprite_ptrs                     ; 1029 20 8D 11                  ..
        jsr     shift_sprite                    ; 102C 20 B6 11                  ..
        ldy     obj                             ; 102F AC 19 04                 ...
        lda     obj_shift,y                     ; 1032 B9 4A 04                 .J.
        cmp     #$08                            ; 1035 C9 08                    ..
        bcs     L103C                           ; 1037 B0 03                    ..
        jmp     L10C7                           ; 1039 4C C7 10                 L..

; ----------------------------------------------------------------------------
L103C:  lda     #$00                            ; 103C A9 00                    ..
        sta     obj_shift,y                     ; 103E 99 4A 04                 .J.
        lda     #$46                            ; 1041 A9 46                    .F
        cmp     obj                             ; 1043 CD 19 04                 ...
        bne     L104B                           ; 1046 D0 03                    ..
        jmp     L10F9                           ; 1048 4C F9 10                 L..

; ----------------------------------------------------------------------------
L104B:  clc                                     ; 104B 18                       .
        lda     idx_i                           ; 104C AD 1A 04                 ...
        tax                                     ; 104F AA                       .
        lda     sprite_chr_b,x                  ; 1050 BD 87 11                 ...
        sta     tmp                             ; 1053 8D 1D 04                 ...
        clc                                     ; 1056 18                       .
        lda     idx_i                           ; 1057 AD 1A 04                 ...
        tay                                     ; 105A A8                       .
        clc                                     ; 105B 18                       .
        lda     idx_i                           ; 105C AD 1A 04                 ...
        tax                                     ; 105F AA                       .
        lda     sprite_chr_a,x                  ; 1060 BD 84 11                 ...
        sta     sprite_chr_b,y                  ; 1063 99 87 11                 ...
        clc                                     ; 1066 18                       .
        lda     idx_i                           ; 1067 AD 1A 04                 ...
        tay                                     ; 106A A8                       .
        lda     tmp                             ; 106B AD 1D 04                 ...
        sta     sprite_chr_a,y                  ; 106E 99 84 11                 ...
        lda     #$00                            ; 1071 A9 00                    ..
        sta     tmp                             ; 1073 8D 1D 04                 ...
        lda     #$46                            ; 1076 A9 46                    .F
        cmp     obj                             ; 1078 CD 19 04                 ...
        bne     L1080                           ; 107B D0 03                    ..
        jmp     L112D                           ; 107D 4C 2D 11                 L-.

; ----------------------------------------------------------------------------
L1080:  clc                                     ; 1080 18                       .
        lda     #$38                            ; 1081 A9 38                    .8
        cmp     obj                             ; 1083 CD 19 04                 ...
        bne     L108E                           ; 1086 D0 06                    ..
        jsr     enemy_step                      ; 1088 20 36 09                  6.
        jmp     L10A9                           ; 108B 4C A9 10                 L..

; ----------------------------------------------------------------------------
L108E:  ldx     #$3F                            ; 108E A2 3F                    .?
        cpx     obj                             ; 1090 EC 19 04                 ...
        bne     L10A9                           ; 1093 D0 14                    ..
        lda     obj_dir,x                       ; 1095 BD 4B 04                 .K.
        sta     move_dir                        ; 1098 8D 12 04                 ...
        jsr     move_obj                        ; 109B 20 92 09                  ..
        jsr     next_pos                        ; 109E 20 73 0B                  s.
        jsr     check_bounds                    ; 10A1 20 FE 0B                  ..
        bcc     L10A9                           ; 10A4 90 03                    ..
        jsr     enemy_turn                      ; 10A6 20 E7 09                  ..
L10A9:  jsr     erase_behind                    ; 10A9 20 96 0B                  ..
        jsr     next_pos                        ; 10AC 20 73 0B                  s.
        jsr     clear_cell                      ; 10AF 20 F4 0B                  ..
        ldx     idx_i                           ; 10B2 AE 1A 04                 ...
        lda     sprite_chr_a,x                  ; 10B5 BD 84 11                 ...
        sta     chr_b                           ; 10B8 8D 3F 04                 .?.
        lda     sprite_chr_b,x                  ; 10BB BD 87 11                 ...
        sta     chr_a                           ; 10BE 8D 3E 04                 .>.
        jsr     sprite_ptrs                     ; 10C1 20 8D 11                  ..
        jsr     sprite_gfx                      ; 10C4 20 3D 11                  =.
L10C7:  jsr     get_obj_pos                     ; 10C7 20 B5 0B                  ..
        jsr     gotoxy                          ; 10CA 20 E7 0B                  ..
        ldy     idx_i                           ; 10CD AC 1A 04                 ...
        lda     sprite_color,y                  ; 10D0 B9 8A 11                 ...
        tax                                     ; 10D3 AA                       .
        lda     sprite_chr_a,y                  ; 10D4 B9 84 11                 ...
        jsr     KERNAL_PUTCHAR                  ; 10D7 20 A1 EA                  ..
        ldy     obj                             ; 10DA AC 19 04                 ...
        lda     obj_dir,y                       ; 10DD B9 4B 04                 .K.
        sta     move_dir                        ; 10E0 8D 12 04                 ...
        jsr     next_pos                        ; 10E3 20 73 0B                  s.
        jsr     gotoxy                          ; 10E6 20 E7 0B                  ..
        ldy     idx_i                           ; 10E9 AC 1A 04                 ...
        lda     sprite_color,y                  ; 10EC B9 8A 11                 ...
        tax                                     ; 10EF AA                       .
        lda     sprite_chr_b,y                  ; 10F0 B9 87 11                 ...
        jsr     KERNAL_PUTCHAR                  ; 10F3 20 A1 EA                  ..
        jmp     L112D                           ; 10F6 4C 2D 11                 L-.

; ----------------------------------------------------------------------------
L10F9:  ldx     obj                             ; 10F9 AE 19 04                 ...
        lda     obj_dir,x                       ; 10FC BD 4B 04                 .K.
        sta     move_dir                        ; 10FF 8D 12 04                 ...
        jsr     move_obj                        ; 1102 20 92 09                  ..
        jsr     next_pos                        ; 1105 20 73 0B                  s.
        jsr     check_bounds                    ; 1108 20 FE 0B                  ..
        bcs     L1113                           ; 110B B0 06                    ..
        jsr     erase_behind                    ; 110D 20 96 0B                  ..
        jmp     L104B                           ; 1110 4C 4B 10                 LK.

; ----------------------------------------------------------------------------
L1113:  ldx     obj                             ; 1113 AE 19 04                 ...
        lda     #$00                            ; 1116 A9 00                    ..
        sta     obj_active,x                    ; 1118 9D 47 04                 .G.
        lda     obj_dir,x                       ; 111B BD 4B 04                 .K.
        sta     tmp_dir                         ; 111E 8D 1E 04                 ...
        jsr     erase_behind                    ; 1121 20 96 0B                  ..
        jsr     get_obj_pos                     ; 1124 20 B5 0B                  ..
        jsr     clear_cell                      ; 1127 20 F4 0B                  ..
        jmp     start_explosion                 ; 112A 4C B7 14                 L..

; ----------------------------------------------------------------------------
L112D:  inc     idx_i                           ; 112D EE 1A 04                 ...
        lda     #$07                            ; 1130 A9 07                    ..
        clc                                     ; 1132 18                       .
        adc     obj                             ; 1133 6D 19 04                 m..
        sta     obj                             ; 1136 8D 19 04                 ...
        jmp     L0FC8                           ; 1139 4C C8 0F                 L..

; ----------------------------------------------------------------------------
L113C:  rts                                     ; 113C 60                       `

; ----------------------------------------------------------------------------
sprite_gfx:
        lda     idx_i                           ; 113D AD 1A 04                 ...
        asl     a                               ; 1140 0A                       .
        asl     a                               ; 1141 0A                       .
        asl     a                               ; 1142 0A                       .
        sta     tmp                             ; 1143 8D 1D 04                 ...
        ldy     obj                             ; 1146 AC 19 04                 ...
        lda     obj_dir,y                       ; 1149 B9 4B 04                 .K.
        asl     a                               ; 114C 0A                       .
        clc                                     ; 114D 18                       .
        adc     tmp                             ; 114E 6D 1D 04                 m..
        tax                                     ; 1151 AA                       .
        lda     sprite_gfx_tab,x                ; 1152 BD 66 11                 .f.
        sta     $9E                             ; 1155 85 9E                    ..
        lda     sprite_gfx_tab+1,x              ; 1157 BD 67 11                 .g.
        sta     $9F                             ; 115A 85 9F                    ..
        ldy     #$07                            ; 115C A0 07                    ..
L115E:  lda     ($9E),y                         ; 115E B1 9E                    ..
        sta     ($A6),y                         ; 1160 91 A6                    ..
        dey                                     ; 1162 88                       .
        bpl     L115E                           ; 1163 10 F9                    ..
        rts                                     ; 1165 60                       `

; ----------------------------------------------------------------------------
sprite_gfx_tab:
        .byte   $D0,$8C,$44,$00,$11,$22,$44,$33 ; 1166 D0 8C 44 00 11 22 44 33  ..D.."D3
        .byte   $52,$06,$5A,$06,$62,$06,$6A,$06 ; 116E 52 06 5A 06 62 06 6A 06  R.Z.b.j.
        .byte   $F2,$12,$FA,$12,$02,$13,$0A,$13 ; 1176 F2 12 FA 12 02 13 0A 13  ........
        .byte   $10,$1C,$00,$1C,$20,$1C         ; 117E 10 1C 00 1C 20 1C        .... .
sprite_chr_a:
        .byte   $84,$80,$82                     ; 1184 84 80 82                 ...
sprite_chr_b:
        .byte   $85,$81,$83                     ; 1187 85 81 83                 ...
sprite_color:
        .byte   $00,$01,$01                     ; 118A 00 01 01                 ...
; ----------------------------------------------------------------------------
; chr_a/chr_b -> $9E/$A6 pointers into charset $1C00
sprite_ptrs:
        lda     chr_b                           ; 118D AD 3F 04                 .?.
        sec                                     ; 1190 38                       8
        sbc     #$80                            ; 1191 E9 80                    ..
        asl     a                               ; 1193 0A                       .
        asl     a                               ; 1194 0A                       .
        asl     a                               ; 1195 0A                       .
        clc                                     ; 1196 18                       .
        adc     #$00                            ; 1197 69 00                    i.
        sta     $A6                             ; 1199 85 A6                    ..
        lda     #$00                            ; 119B A9 00                    ..
        adc     #$1C                            ; 119D 69 1C                    i.
        sta     $A7                             ; 119F 85 A7                    ..
        lda     chr_a                           ; 11A1 AD 3E 04                 .>.
        sec                                     ; 11A4 38                       8
        sbc     #$80                            ; 11A5 E9 80                    ..
        asl     a                               ; 11A7 0A                       .
        asl     a                               ; 11A8 0A                       .
        asl     a                               ; 11A9 0A                       .
        clc                                     ; 11AA 18                       .
        adc     #$00                            ; 11AB 69 00                    i.
        sta     $9E                             ; 11AD 85 9E                    ..
        lda     #$00                            ; 11AF A9 00                    ..
        adc     #$1C                            ; 11B1 69 1C                    i.
        sta     $9F                             ; 11B3 85 9F                    ..
        rts                                     ; 11B5 60                       `

; ----------------------------------------------------------------------------
shift_sprite:
        clc                                     ; 11B6 18                       .
        lda     obj                             ; 11B7 AD 19 04                 ...
        tax                                     ; 11BA AA                       .
        lda     obj_dir,x                       ; 11BB BD 4B 04                 .K.
        sta     tmp_dir                         ; 11BE 8D 1E 04                 ...
        lda     tmp_dir                         ; 11C1 AD 1E 04                 ...
        asl     a                               ; 11C4 0A                       .
        tax                                     ; 11C5 AA                       .
        lda     shift_tab,x                     ; 11C6 BD D3 11                 ...
        sta     L0000                           ; 11C9 85 00                    ..
        lda     shift_tab+1,x                   ; 11CB BD D4 11                 ...
        sta     $01                             ; 11CE 85 01                    ..
        jmp     (L0000)                         ; 11D0 6C 00 00                 l..

; ----------------------------------------------------------------------------
shift_tab:
        .byte   $DB,$11,$05,$12,$15,$12,$38,$12 ; 11D3 DB 11 05 12 15 12 38 12  ......8.
; ----------------------------------------------------------------------------
shift_up:
        ldy     #$01                            ; 11DB A0 01                    ..
        ldx     #$06                            ; 11DD A2 06                    ..
L11DF:  lda     ($A6),y                         ; 11DF B1 A6                    ..
        dey                                     ; 11E1 88                       .
        sta     ($A6),y                         ; 11E2 91 A6                    ..
        iny                                     ; 11E4 C8                       .
        iny                                     ; 11E5 C8                       .
        dex                                     ; 11E6 CA                       .
        bpl     L11DF                           ; 11E7 10 F6                    ..
        ldy     #$00                            ; 11E9 A0 00                    ..
        lda     ($9E),y                         ; 11EB B1 9E                    ..
        ldy     #$07                            ; 11ED A0 07                    ..
        sta     ($A6),y                         ; 11EF 91 A6                    ..
        ldy     #$01                            ; 11F1 A0 01                    ..
        ldx     #$06                            ; 11F3 A2 06                    ..
L11F5:  lda     ($9E),y                         ; 11F5 B1 9E                    ..
        dey                                     ; 11F7 88                       .
        sta     ($9E),y                         ; 11F8 91 9E                    ..
        iny                                     ; 11FA C8                       .
        iny                                     ; 11FB C8                       .
        dex                                     ; 11FC CA                       .
        bpl     L11F5                           ; 11FD 10 F6                    ..
        dey                                     ; 11FF 88                       .
        lda     #$00                            ; 1200 A9 00                    ..
        sta     ($9E),y                         ; 1202 91 9E                    ..
        rts                                     ; 1204 60                       `

; ----------------------------------------------------------------------------
shift_right:
        ldy     #$07                            ; 1205 A0 07                    ..
L1207:  lda     ($9E),y                         ; 1207 B1 9E                    ..
        ror     a                               ; 1209 6A                       j
        sta     ($9E),y                         ; 120A 91 9E                    ..
        lda     ($A6),y                         ; 120C B1 A6                    ..
        ror     a                               ; 120E 6A                       j
        sta     ($A6),y                         ; 120F 91 A6                    ..
        dey                                     ; 1211 88                       .
        bpl     L1207                           ; 1212 10 F3                    ..
        rts                                     ; 1214 60                       `

; ----------------------------------------------------------------------------
shift_down:
        ldy     #$06                            ; 1215 A0 06                    ..
L1217:  lda     ($A6),y                         ; 1217 B1 A6                    ..
        iny                                     ; 1219 C8                       .
        sta     ($A6),y                         ; 121A 91 A6                    ..
        dey                                     ; 121C 88                       .
        dey                                     ; 121D 88                       .
        bpl     L1217                           ; 121E 10 F7                    ..
        ldy     #$07                            ; 1220 A0 07                    ..
        lda     ($9E),y                         ; 1222 B1 9E                    ..
        ldy     #$00                            ; 1224 A0 00                    ..
        sta     ($A6),y                         ; 1226 91 A6                    ..
        ldy     #$06                            ; 1228 A0 06                    ..
L122A:  lda     ($9E),y                         ; 122A B1 9E                    ..
        iny                                     ; 122C C8                       .
        sta     ($9E),y                         ; 122D 91 9E                    ..
        dey                                     ; 122F 88                       .
        dey                                     ; 1230 88                       .
        bpl     L122A                           ; 1231 10 F7                    ..
        iny                                     ; 1233 C8                       .
        tya                                     ; 1234 98                       .
        sta     ($9E),y                         ; 1235 91 9E                    ..
        rts                                     ; 1237 60                       `

; ----------------------------------------------------------------------------
shift_left:
        ldy     #$07                            ; 1238 A0 07                    ..
L123A:  clc                                     ; 123A 18                       .
        lda     ($9E),y                         ; 123B B1 9E                    ..
        rol     a                               ; 123D 2A                       *
        sta     ($9E),y                         ; 123E 91 9E                    ..
        lda     ($A6),y                         ; 1240 B1 A6                    ..
        rol     a                               ; 1242 2A                       *
        sta     ($A6),y                         ; 1243 91 A6                    ..
        dey                                     ; 1245 88                       .
        bpl     L123A                           ; 1246 10 F2                    ..
        rts                                     ; 1248 60                       `

; ----------------------------------------------------------------------------
fire_shot:
        lda     fire                            ; 1249 AD 2F 04                 ./.
        bne     L124F                           ; 124C D0 01                    ..
L124E:  rts                                     ; 124E 60                       `

; ----------------------------------------------------------------------------
L124F:  lda     #$46                            ; 124F A9 46                    .F
        sta     obj                             ; 1251 8D 19 04                 ...
        tax                                     ; 1254 AA                       .
        lda     obj_active,x                    ; 1255 BD 47 04                 .G.
        bne     L124E                           ; 1258 D0 F4                    ..
        lda     expl_timer                      ; 125A AD 3D 04                 .=.
        bne     L124E                           ; 125D D0 EF                    ..
        lda     #$0F                            ; 125F A9 0F                    ..
        sta     VIC_VOLUME                      ; 1261 8D 0E 90                 ...
        lda     #$FD                            ; 1264 A9 FD                    ..
        sta     VIC_NOISE                       ; 1266 8D 0D 90                 ...
        lda     obj                             ; 1269 AD 19 04                 ...
        tay                                     ; 126C A8                       .
        clc                                     ; 126D 18                       .
        lda     #$3F                            ; 126E A9 3F                    .?
        tax                                     ; 1270 AA                       .
        lda     obj_dir,x                       ; 1271 BD 4B 04                 .K.
        sta     obj_dir,y                       ; 1274 99 4B 04                 .K.
        lda     #$01                            ; 1277 A9 01                    ..
        sta     obj_active,y                    ; 1279 99 47 04                 .G.
        lda     obj                             ; 127C AD 19 04                 ...
        tay                                     ; 127F A8                       .
        clc                                     ; 1280 18                       .
        lda     #$3F                            ; 1281 A9 3F                    .?
        tax                                     ; 1283 AA                       .
        lda     obj_x,x                         ; 1284 BD 48 04                 .H.
        sta     obj_x,y                         ; 1287 99 48 04                 .H.
        clc                                     ; 128A 18                       .
        lda     obj                             ; 128B AD 19 04                 ...
        tay                                     ; 128E A8                       .
        clc                                     ; 128F 18                       .
        lda     #$3F                            ; 1290 A9 3F                    .?
        tax                                     ; 1292 AA                       .
        lda     obj_y,x                         ; 1293 BD 49 04                 .I.
        sta     obj_y,y                         ; 1296 99 49 04                 .I.
        clc                                     ; 1299 18                       .
        lda     obj                             ; 129A AD 19 04                 ...
        tay                                     ; 129D A8                       .
        lda     #$00                            ; 129E A9 00                    ..
        sta     obj_delay,y                     ; 12A0 99 4D 04                 .M.
        clc                                     ; 12A3 18                       .
        lda     obj                             ; 12A4 AD 19 04                 ...
        tay                                     ; 12A7 A8                       .
        lda     #$01                            ; 12A8 A9 01                    ..
        sta     obj_speed,y                     ; 12AA 99 4C 04                 .L.
        lda     #$07                            ; 12AD A9 07                    ..
        sta     obj_shift,y                     ; 12AF 99 4A 04                 .J.
        ldx     obj                             ; 12B2 AE 19 04                 ...
        lda     obj_dir,x                       ; 12B5 BD 4B 04                 .K.
        sta     move_dir                        ; 12B8 8D 12 04                 ...
        jsr     next_pos                        ; 12BB 20 73 0B                  s.
        jsr     next_pos_xy                     ; 12BE 20 76 0B                  v.
        jsr     check_bounds                    ; 12C1 20 FE 0B                  ..
        bcc     L12C9                           ; 12C4 90 03                    ..
        jmp     remove_shot                     ; 12C6 4C 7E 14                 L~.

; ----------------------------------------------------------------------------
L12C9:  jsr     next_pos                        ; 12C9 20 73 0B                  s.
        lda     next_x                          ; 12CC AD 1F 04                 ...
        ldx     obj                             ; 12CF AE 19 04                 ...
        sta     obj_x,x                         ; 12D2 9D 48 04                 .H.
        lda     next_y                          ; 12D5 AD 20 04                 . .
        sta     obj_y,x                         ; 12D8 9D 49 04                 .I.
        lda     sprite_chr_a+2                  ; 12DB AD 86 11                 ...
        sta     chr_a                           ; 12DE 8D 3E 04                 .>.
        lda     sprite_chr_b+2                  ; 12E1 AD 89 11                 ...
        sta     chr_b                           ; 12E4 8D 3F 04                 .?.
        jsr     sprite_ptrs                     ; 12E7 20 8D 11                  ..
        lda     #$02                            ; 12EA A9 02                    ..
        sta     idx_i                           ; 12EC 8D 1A 04                 ...
        jmp     sprite_gfx                      ; 12EF 4C 3D 11                 L=.

; ----------------------------------------------------------------------------
gfx_shot:
        .byte   $10,$10,$10,$10,$00,$00,$00,$00 ; 12F2 10 10 10 10 00 00 00 00  ........
        .byte   $00,$00,$00,$0F,$00,$00,$00,$00 ; 12FA 00 00 00 0F 00 00 00 00  ........
        .byte   $00,$00,$00,$00,$08,$08,$08,$08 ; 1302 00 00 00 00 08 08 08 08  ........
        .byte   $00,$00,$00,$00,$0F,$00,$00,$00 ; 130A 00 00 00 00 0F 00 00 00  ........
        .byte   $F2,$12,$FA,$12,$02,$13,$0A,$13 ; 1312 F2 12 FA 12 02 13 0A 13  ........
; ----------------------------------------------------------------------------
check_collisions:
        lda     #$00                            ; 131A A9 00                    ..
        sta     idx_i                           ; 131C 8D 1A 04                 ...
L131F:  cmp     #$03                            ; 131F C9 03                    ..
        beq     L1328                           ; 1321 F0 05                    ..
        bcc     L1328                           ; 1323 90 03                    ..
        jmp     L13B1                           ; 1325 4C B1 13                 L..

; ----------------------------------------------------------------------------
L1328:  lda     idx_i                           ; 1328 AD 1A 04                 ...
        sta     move_dir                        ; 132B 8D 12 04                 ...
        lda     #$3F                            ; 132E A9 3F                    .?
        sta     obj                             ; 1330 8D 19 04                 ...
        jsr     next_pos                        ; 1333 20 73 0B                  s.
        jsr     check_bounds                    ; 1336 20 FE 0B                  ..
        bcs     L13A8                           ; 1339 B0 6D                    .m
        jsr     gotoxy                          ; 133B 20 E7 0B                  ..
        jsr     KERNAL_SETCOLOR                 ; 133E 20 B2 EA                  ..
        ldy     $D3                             ; 1341 A4 D3                    ..
        lda     ($F3),y                         ; 1343 B1 F3                    ..
        sta     tmp                             ; 1345 8D 1D 04                 ...
        clc                                     ; 1348 18                       .
        lda     #$02                            ; 1349 A9 02                    ..
        cmp     tmp                             ; 134B CD 1D 04                 ...
        beq     L1353                           ; 134E F0 03                    ..
        jmp     L1356                           ; 1350 4C 56 13                 LV.

; ----------------------------------------------------------------------------
L1353:  jmp     player_crash                    ; 1353 4C B3 13                 L..

; ----------------------------------------------------------------------------
L1356:  clc                                     ; 1356 18                       .
        lda     #$00                            ; 1357 A9 00                    ..
        cmp     tmp                             ; 1359 CD 1D 04                 ...
        beq     L1361                           ; 135C F0 03                    ..
        jmp     L1364                           ; 135E 4C 64 13                 Ld.

; ----------------------------------------------------------------------------
L1361:  jmp     player_crash                    ; 1361 4C B3 13                 L..

; ----------------------------------------------------------------------------
L1364:  ldx     #$46                            ; 1364 A2 46                    .F
        lda     obj_active,x                    ; 1366 BD 47 04                 .G.
        beq     L13A8                           ; 1369 F0 3D                    .=
        stx     obj                             ; 136B 8E 19 04                 ...
        lda     obj_dir,x                       ; 136E BD 4B 04                 .K.
        sta     move_dir                        ; 1371 8D 12 04                 ...
        jsr     next_pos                        ; 1374 20 73 0B                  s.
        nop                                     ; 1377 EA                       .
        nop                                     ; 1378 EA                       .
        nop                                     ; 1379 EA                       .
        jsr     check_bounds                    ; 137A 20 FE 0B                  ..
        bcs     L13A8                           ; 137D B0 29                    .)
        jsr     gotoxy                          ; 137F 20 E7 0B                  ..
        jsr     KERNAL_SETCOLOR                 ; 1382 20 B2 EA                  ..
        ldy     $D3                             ; 1385 A4 D3                    ..
        lda     ($F3),y                         ; 1387 B1 F3                    ..
        sta     tmp                             ; 1389 8D 1D 04                 ...
        clc                                     ; 138C 18                       .
        lda     #$02                            ; 138D A9 02                    ..
        cmp     tmp                             ; 138F CD 1D 04                 ...
        beq     L1397                           ; 1392 F0 03                    ..
        jmp     L139A                           ; 1394 4C 9A 13                 L..

; ----------------------------------------------------------------------------
L1397:  jmp     shot_hit_enemy                  ; 1397 4C C0 13                 L..

; ----------------------------------------------------------------------------
L139A:  clc                                     ; 139A 18                       .
        lda     #$00                            ; 139B A9 00                    ..
        cmp     tmp                             ; 139D CD 1D 04                 ...
        beq     L13A5                           ; 13A0 F0 03                    ..
        jmp     L13A8                           ; 13A2 4C A8 13                 L..

; ----------------------------------------------------------------------------
L13A5:  jmp     shot_hit_target                 ; 13A5 4C 53 15                 LS.

; ----------------------------------------------------------------------------
L13A8:  inc     idx_i                           ; 13A8 EE 1A 04                 ...
        lda     idx_i                           ; 13AB AD 1A 04                 ...
        jmp     L131F                           ; 13AE 4C 1F 13                 L..

; ----------------------------------------------------------------------------
L13B1:  clc                                     ; 13B1 18                       .
        rts                                     ; 13B2 60                       `

; ----------------------------------------------------------------------------
player_crash:
        ldx     obj                             ; 13B3 AE 19 04                 ...
        jsr     kill_object                     ; 13B6 20 85 14                  ..
        jsr     delay                           ; 13B9 20 39 15                  9.
        sec                                     ; 13BC 38                       8
        rts                                     ; 13BD 60                       `

; ----------------------------------------------------------------------------
unused_sec_rts:
        sec                                     ; 13BE 38                       8
        rts                                     ; 13BF 60                       `

; ----------------------------------------------------------------------------
shot_hit_enemy:
        lda     #$00                            ; 13C0 A9 00                    ..
        sta     obj                             ; 13C2 8D 19 04                 ...
L13C5:  cmp     enemy_last                      ; 13C5 CD 1C 04                 ...
        beq     L13CF                           ; 13C8 F0 05                    ..
        bcc     L13CF                           ; 13CA 90 03                    ..
        jmp     L1479                           ; 13CC 4C 79 14                 Ly.

; ----------------------------------------------------------------------------
L13CF:  lda     obj                             ; 13CF AD 19 04                 ...
        tay                                     ; 13D2 A8                       .
        lda     #$00                            ; 13D3 A9 00                    ..
        cmp     obj_active,y                    ; 13D5 D9 47 04                 .G.
        bne     L13DD                           ; 13D8 D0 03                    ..
        jmp     L146D                           ; 13DA 4C 6D 14                 Lm.

; ----------------------------------------------------------------------------
L13DD:  lda     #$02                            ; 13DD A9 02                    ..
        sta     tmp_dir                         ; 13DF 8D 1E 04                 ...
        lda     obj                             ; 13E2 AD 19 04                 ...
        pha                                     ; 13E5 48                       H
        ldx     #$46                            ; 13E6 A2 46                    .F
        lda     obj_dir,x                       ; 13E8 BD 4B 04                 .K.
        sta     move_dir                        ; 13EB 8D 12 04                 ...
        stx     obj                             ; 13EE 8E 19 04                 ...
        jsr     next_pos                        ; 13F1 20 73 0B                  s.
        pla                                     ; 13F4 68                       h
        sta     obj                             ; 13F5 8D 19 04                 ...
        lda     next_x                          ; 13F8 AD 1F 04                 ...
        sta     shot_x                          ; 13FB 8D 21 04                 .!.
        lda     next_y                          ; 13FE AD 20 04                 . .
        sta     shot_y                          ; 1401 8D 22 04                 .".
        ldx     obj                             ; 1404 AE 19 04                 ...
        lda     obj_x,x                         ; 1407 BD 48 04                 .H.
        sta     next_x                          ; 140A 8D 1F 04                 ...
        lda     obj_y,x                         ; 140D BD 49 04                 .I.
        sta     next_y                          ; 1410 8D 20 04                 . .
L1413:  lda     shot_x                          ; 1413 AD 21 04                 .!.
        cmp     next_x                          ; 1416 CD 1F 04                 ...
        bne     L1426                           ; 1419 D0 0B                    ..
        lda     shot_y                          ; 141B AD 22 04                 .".
        cmp     next_y                          ; 141E CD 20 04                 . .
        bne     L1426                           ; 1421 D0 03                    ..
        jmp     L1437                           ; 1423 4C 37 14                 L7.

; ----------------------------------------------------------------------------
L1426:  dec     tmp_dir                         ; 1426 CE 1E 04                 ...
        beq     L146D                           ; 1429 F0 42                    .B
        lda     obj_dir,x                       ; 142B BD 4B 04                 .K.
        sta     move_dir                        ; 142E 8D 12 04                 ...
        jsr     next_pos                        ; 1431 20 73 0B                  s.
        jmp     L1413                           ; 1434 4C 13 14                 L..

; ----------------------------------------------------------------------------
L1437:  jsr     lose_life                       ; 1437 20 7B 14                  {.
        lda     #$0A                            ; 143A A9 0A                    ..
        jsr     add_score                       ; 143C 20 0C 15                  ..
        clc                                     ; 143F 18                       .
        lda     lives                           ; 1440 AD 23 04                 .#.
        beq     L1448                           ; 1443 F0 03                    ..
        jmp     L146B                           ; 1445 4C 6B 14                 Lk.

; ----------------------------------------------------------------------------
L1448:  lda     #$64                            ; 1448 A9 64                    .d
        jsr     add_score                       ; 144A 20 0C 15                  ..
        jsr     delay                           ; 144D 20 39 15                  9.
        lda     #$08                            ; 1450 A9 08                    ..
        sta     move_dir                        ; 1452 8D 12 04                 ...
        jsr     spawn_enemies                   ; 1455 20 9C 06                  ..
        jsr     KERNAL_CLRSCR                   ; 1458 20 5F E5                  _.
        jsr     show_pilot                      ; 145B 20 72 06                  r.
        jsr     draw_city                       ; 145E 20 23 08                  #.
        jsr     init_player                     ; 1461 20 0F 06                  ..
        lda     #$00                            ; 1464 A9 00                    ..
        jsr     add_score                       ; 1466 20 0C 15                  ..
        clc                                     ; 1469 18                       .
        rts                                     ; 146A 60                       `

; ----------------------------------------------------------------------------
L146B:  clc                                     ; 146B 18                       .
        rts                                     ; 146C 60                       `

; ----------------------------------------------------------------------------
L146D:  lda     #$07                            ; 146D A9 07                    ..
        clc                                     ; 146F 18                       .
        adc     obj                             ; 1470 6D 19 04                 m..
        sta     obj                             ; 1473 8D 19 04                 ...
        jmp     L13C5                           ; 1476 4C C5 13                 L..

; ----------------------------------------------------------------------------
L1479:  clc                                     ; 1479 18                       .
        rts                                     ; 147A 60                       `

; ----------------------------------------------------------------------------
lose_life:
        dec     lives                           ; 147B CE 23 04                 .#.
remove_shot:
        ldx     #$46                            ; 147E A2 46                    .F
        lda     #$00                            ; 1480 A9 00                    ..
        sta     obj_active,x                    ; 1482 9D 47 04                 .G.
kill_object:
        lda     obj                             ; 1485 AD 19 04                 ...
        pha                                     ; 1488 48                       H
        stx     obj                             ; 1489 8E 19 04                 ...
        lda     obj_dir,x                       ; 148C BD 4B 04                 .K.
        sta     move_dir                        ; 148F 8D 12 04                 ...
        jsr     get_obj_pos                     ; 1492 20 B5 0B                  ..
        jsr     clear_cell                      ; 1495 20 F4 0B                  ..
        pla                                     ; 1498 68                       h
        tay                                     ; 1499 A8                       .
        sta     obj                             ; 149A 8D 19 04                 ...
        lda     #$00                            ; 149D A9 00                    ..
        sta     obj_active,y                    ; 149F 99 47 04                 .G.
        jsr     get_obj_pos                     ; 14A2 20 B5 0B                  ..
        jsr     clear_cell                      ; 14A5 20 F4 0B                  ..
        ldx     obj                             ; 14A8 AE 19 04                 ...
        lda     obj_dir,x                       ; 14AB BD 4B 04                 .K.
        sta     move_dir                        ; 14AE 8D 12 04                 ...
        jsr     next_pos                        ; 14B1 20 73 0B                  s.
        jsr     clear_cell                      ; 14B4 20 F4 0B                  ..
start_explosion:
        ldx     obj                             ; 14B7 AE 19 04                 ...
        lda     obj_dir,x                       ; 14BA BD 4B 04                 .K.
        sta     move_dir                        ; 14BD 8D 12 04                 ...
        sta     tmp_dir                         ; 14C0 8D 1E 04                 ...
        lda     #$8D                            ; 14C3 A9 8D                    ..
        sta     VIC_NOISE                       ; 14C5 8D 0D 90                 ...
        jsr     get_obj_pos                     ; 14C8 20 B5 0B                  ..
        stx     expl_x                          ; 14CB 8E 3B 04                 .;.
        sty     expl_y                          ; 14CE 8C 3C 04                 .<.
        jsr     gotoxy                          ; 14D1 20 E7 0B                  ..
        lda     #$28                            ; 14D4 A9 28                    .(
        sta     expl_timer                      ; 14D6 8D 3D 04                 .=.
        lda     #$8A                            ; 14D9 A9 8A                    ..
        ldx     #$01                            ; 14DB A2 01                    ..
        jmp     KERNAL_PUTCHAR                  ; 14DD 4C A1 EA                 L..

; ----------------------------------------------------------------------------
unused_jsr:
        jsr     erase_behind                    ; 14E0 20 96 0B                  ..
update_explosion:
        lda     expl_timer                      ; 14E3 AD 3D 04                 .=.
        beq     L150B                           ; 14E6 F0 23                    .#
        ldy     expl_timer                      ; 14E8 AC 3D 04                 .=.
        lda     expl_volume,y                   ; 14EB B9 97 04                 ...
        sta     VIC_VOLUME                      ; 14EE 8D 0E 90                 ...
        dec     expl_timer                      ; 14F1 CE 3D 04                 .=.
        bne     L150B                           ; 14F4 D0 15                    ..
        lda     #$00                            ; 14F6 A9 00                    ..
        sta     VIC_NOISE                       ; 14F8 8D 0D 90                 ...
        ldx     expl_x                          ; 14FB AE 3B 04                 .;.
        ldy     expl_y                          ; 14FE AC 3C 04                 .<.
        jsr     gotoxy                          ; 1501 20 E7 0B                  ..
        lda     #$20                            ; 1504 A9 20                    . 
        ldx     #$06                            ; 1506 A2 06                    ..
        jsr     KERNAL_PUTCHAR                  ; 1508 20 A1 EA                  ..
L150B:  rts                                     ; 150B 60                       `

; ----------------------------------------------------------------------------
; A = points
add_score:
        tay                                     ; 150C A8                       .
        lda     pilot                           ; 150D AD 2A 04                 .*.
        lsr     a                               ; 1510 4A                       J
        asl     a                               ; 1511 0A                       .
        tax                                     ; 1512 AA                       .
        tya                                     ; 1513 98                       .
        clc                                     ; 1514 18                       .
        adc     score,x                         ; 1515 7D 40 04                 }@.
        sta     score,x                         ; 1518 9D 40 04                 .@.
        lda     #$00                            ; 151B A9 00                    ..
        adc     score+1,x                       ; 151D 7D 41 04                 }A.
        sta     score+1,x                       ; 1520 9D 41 04                 .A.
        ldx     #$06                            ; 1523 A2 06                    ..
        ldy     #$16                            ; 1525 A0 16                    ..
        jsr     gotoxy                          ; 1527 20 E7 0B                  ..
        lda     pilot                           ; 152A AD 2A 04                 .*.
        lsr     a                               ; 152D 4A                       J
        asl     a                               ; 152E 0A                       .
        tay                                     ; 152F A8                       .
        lda     score+1,y                       ; 1530 B9 41 04                 .A.
        ldx     score,y                         ; 1533 BE 40 04                 .@.
        jmp     BASIC_LINPRT                    ; 1536 4C CD DD                 L..

; ----------------------------------------------------------------------------
delay:  ldy     #$05                            ; 1539 A0 05                    ..
L153B:  jsr     delay_short                     ; 153B 20 42 15                  B.
        dey                                     ; 153E 88                       .
        bpl     L153B                           ; 153F 10 FA                    ..
        rts                                     ; 1541 60                       `

; ----------------------------------------------------------------------------
delay_short:
        ldx     #$00                            ; 1542 A2 00                    ..
        lda     #$00                            ; 1544 A9 00                    ..
L1546:  adc     #$01                            ; 1546 69 01                    i.
        bne     L1546                           ; 1548 D0 FC                    ..
        inx                                     ; 154A E8                       .
        bne     L1546                           ; 154B D0 F9                    ..
        rts                                     ; 154D 60                       `

; ----------------------------------------------------------------------------
; 10, 20, 50, 100, 200
bonus_points:
        .byte   $0A,$14,$32,$64,$C8             ; 154E 0A 14 32 64 C8           ..2d.
; ----------------------------------------------------------------------------
; random bonus
shot_hit_target:
        jsr     remove_shot                     ; 1553 20 7E 14                  ~.
        jsr     rnd_bonus                       ; 1556 20 21 0F                  !.
        ldx     #$11                            ; 1559 A2 11                    ..
        ldy     #$16                            ; 155B A0 16                    ..
        jsr     gotoxy                          ; 155D 20 E7 0B                  ..
        clc                                     ; 1560 18                       .
        lda     tmp                             ; 1561 AD 1D 04                 ...
        tax                                     ; 1564 AA                       .
        lda     bonus_points,x                  ; 1565 BD 4E 15                 .N.
        sta     tmp_dir                         ; 1568 8D 1E 04                 ...
        jsr     add_score                       ; 156B 20 0C 15                  ..
        ldx     tmp_dir                         ; 156E AE 1E 04                 ...
        lda     #$00                            ; 1571 A9 00                    ..
        jsr     BASIC_LINPRT                    ; 1573 20 CD DD                  ..
        lda     #$07                            ; 1576 A9 07                    ..
        sta     bonus_msg_timer                 ; 1578 8D 44 04                 .D.
        rts                                     ; 157B 60                       `

; ----------------------------------------------------------------------------
bonus_msg_update:
        clc                                     ; 157C 18                       .
        lda     #$00                            ; 157D A9 00                    ..
        cmp     bonus_msg_timer                 ; 157F CD 44 04                 .D.
        beq     L1587                           ; 1582 F0 03                    ..
        jmp     L1588                           ; 1584 4C 88 15                 L..

; ----------------------------------------------------------------------------
L1587:  rts                                     ; 1587 60                       `

; ----------------------------------------------------------------------------
L1588:  dec     bonus_msg_timer                 ; 1588 CE 44 04                 .D.
        beq     L1594                           ; 158B F0 07                    ..
        ldx     #$95                            ; 158D A2 95                    ..
        ldy     #$15                            ; 158F A0 15                    ..
        jsr     print_texts                     ; 1591 20 0C 0D                  ..
L1594:  rts                                     ; 1594 60                       `

; ----------------------------------------------------------------------------
txt_blank:
        .byte   $11,$16,$90,$12,$20,$20,$20,$20 ; 1595 11 16 90 12 20 20 20 20  ....    
        .byte   $20,$00,$00                     ; 159D 20 00 00                  ..
; ----------------------------------------------------------------------------
; jmp (input_vec)
read_input:
        jmp     (input_vec)                     ; 15A0 6C 32 04                 l2.

; ----------------------------------------------------------------------------
read_joystick:
        sei                                     ; 15A3 78                       x
        ldx     #$7F                            ; 15A4 A2 7F                    ..
        stx     VIA2_DDRB                       ; 15A6 8E 22 91                 .".
L15A9:  ldy     VIA2_PRB                        ; 15A9 AC 20 91                 . .
        cpy     VIA2_PRB                        ; 15AC CC 20 91                 . .
        bne     L15A9                           ; 15AF D0 F8                    ..
        ldx     #$FF                            ; 15B1 A2 FF                    ..
        stx     VIA2_DDRB                       ; 15B3 8E 22 91                 .".
        ldx     #$F7                            ; 15B6 A2 F7                    ..
        stx     VIA2_PRB                        ; 15B8 8E 20 91                 . .
        cli                                     ; 15BB 58                       X
L15BC:  lda     $911F                           ; 15BC AD 1F 91                 ...
        cmp     $911F                           ; 15BF CD 1F 91                 ...
        bne     L15BC                           ; 15C2 D0 F8                    ..
        pha                                     ; 15C4 48                       H
        and     #$1C                            ; 15C5 29 1C                    ).
        lsr     a                               ; 15C7 4A                       J
        cpy     #$80                            ; 15C8 C0 80                    ..
        bcc     L15CE                           ; 15CA 90 02                    ..
        ora     #$10                            ; 15CC 09 10                    ..
L15CE:  tay                                     ; 15CE A8                       .
        pla                                     ; 15CF 68                       h
        and     #$20                            ; 15D0 29 20                    ) 
        cmp     #$20                            ; 15D2 C9 20                    . 
        tya                                     ; 15D4 98                       .
        ror     a                               ; 15D5 6A                       j
        eor     #$8F                            ; 15D6 49 8F                    I.
        sta     joy_raw                         ; 15D8 8D 30 04                 .0.
        lda     #$04                            ; 15DB A9 04                    ..
        sta     joy_dir                         ; 15DD 8D 31 04                 .1.
        lda     #$00                            ; 15E0 A9 00                    ..
        sta     fire                            ; 15E2 8D 2F 04                 ./.
        clc                                     ; 15E5 18                       .
        lda     #$01                            ; 15E6 A9 01                    ..
        and     joy_raw                         ; 15E8 2D 30 04                 -0.
        sta     $01                             ; 15EB 85 01                    ..
        lda     #$00                            ; 15ED A9 00                    ..
        cmp     $01                             ; 15EF C5 01                    ..
        bne     L15F6                           ; 15F1 D0 03                    ..
        jmp     L15FB                           ; 15F3 4C FB 15                 L..

; ----------------------------------------------------------------------------
L15F6:  lda     #$00                            ; 15F6 A9 00                    ..
        sta     joy_dir                         ; 15F8 8D 31 04                 .1.
L15FB:  clc                                     ; 15FB 18                       .
        lda     #$02                            ; 15FC A9 02                    ..
        and     joy_raw                         ; 15FE 2D 30 04                 -0.
        sta     $01                             ; 1601 85 01                    ..
        lda     #$00                            ; 1603 A9 00                    ..
        cmp     $01                             ; 1605 C5 01                    ..
        bne     L160C                           ; 1607 D0 03                    ..
        jmp     L1611                           ; 1609 4C 11 16                 L..

; ----------------------------------------------------------------------------
L160C:  lda     #$02                            ; 160C A9 02                    ..
        sta     joy_dir                         ; 160E 8D 31 04                 .1.
L1611:  clc                                     ; 1611 18                       .
        lda     #$04                            ; 1612 A9 04                    ..
        and     joy_raw                         ; 1614 2D 30 04                 -0.
        sta     $01                             ; 1617 85 01                    ..
        lda     #$00                            ; 1619 A9 00                    ..
        cmp     $01                             ; 161B C5 01                    ..
        bne     L1622                           ; 161D D0 03                    ..
        jmp     L1627                           ; 161F 4C 27 16                 L'.

; ----------------------------------------------------------------------------
L1622:  lda     #$03                            ; 1622 A9 03                    ..
        sta     joy_dir                         ; 1624 8D 31 04                 .1.
L1627:  clc                                     ; 1627 18                       .
        lda     #$08                            ; 1628 A9 08                    ..
        and     joy_raw                         ; 162A 2D 30 04                 -0.
        sta     $01                             ; 162D 85 01                    ..
        lda     #$00                            ; 162F A9 00                    ..
        cmp     $01                             ; 1631 C5 01                    ..
        bne     L1638                           ; 1633 D0 03                    ..
        jmp     L163D                           ; 1635 4C 3D 16                 L=.

; ----------------------------------------------------------------------------
L1638:  lda     #$01                            ; 1638 A9 01                    ..
        sta     joy_dir                         ; 163A 8D 31 04                 .1.
L163D:  clc                                     ; 163D 18                       .
        lda     #$80                            ; 163E A9 80                    ..
        cmp     joy_raw                         ; 1640 CD 30 04                 .0.
        beq     L164A                           ; 1643 F0 05                    ..
        bcc     L164A                           ; 1645 90 03                    ..
        jmp     L164F                           ; 1647 4C 4F 16                 LO.

; ----------------------------------------------------------------------------
L164A:  lda     #$01                            ; 164A A9 01                    ..
        sta     fire                            ; 164C 8D 2F 04                 ./.
L164F:  rts                                     ; 164F 60                       `

; ----------------------------------------------------------------------------
free_ram:
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1650 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1658 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1660 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1668 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1670 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1678 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1680 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1688 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1690 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1698 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16A0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16A8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16B0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16B8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16C0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16C8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16D0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16D8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16E0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16E8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16F0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 16F8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1700 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1708 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1710 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1718 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1720 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1728 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1730 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1738 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1740 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1748 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1750 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1758 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1760 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1768 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1770 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1778 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1780 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1788 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1790 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1798 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17A0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17A8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17B0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17B8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17C0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17C8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17D0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17D8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17E0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17E8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17F0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 17F8 AA AA AA AA AA AA AA AA  ........
; ROM characters copied here at runtime
charset_copy:
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1800 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1808 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1810 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1818 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1820 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1828 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1830 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1838 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1840 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1848 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1850 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1858 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1860 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1868 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1870 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1878 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1880 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1888 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1890 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1898 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18A0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18A8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18B0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18B8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18C0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18C8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18D0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18D8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18E0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18E8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18F0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 18F8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1900 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1908 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1910 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1918 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1920 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1928 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1930 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1938 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1940 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1948 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1950 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1958 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1960 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1968 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1970 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1978 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1980 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1988 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1990 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1998 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19A0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19A8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19B0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19B8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19C0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19C8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19D0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19D8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19E0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19E8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19F0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 19F8 AA AA AA AA AA AA AA AA  ........
; plane bitmaps, 4 directions x 8 pixel phases
gfx_planes:
        .byte   $18,$18,$3C,$3C,$7E,$66,$C3,$81 ; 1A00 18 18 3C 3C 7E 66 C3 81  ..<<~f..
        .byte   $18,$3C,$3C,$7E,$66,$C3,$81,$00 ; 1A08 18 3C 3C 7E 66 C3 81 00  .<<~f...
        .byte   $3C,$3C,$7E,$66,$C3,$81,$00,$00 ; 1A10 3C 3C 7E 66 C3 81 00 00  <<~f....
        .byte   $3C,$7E,$66,$C3,$81,$00,$00,$00 ; 1A18 3C 7E 66 C3 81 00 00 00  <~f.....
        .byte   $7E,$66,$C3,$81,$00,$00,$00,$00 ; 1A20 7E 66 C3 81 00 00 00 00  ~f......
        .byte   $66,$C3,$81,$00,$00,$00,$00,$00 ; 1A28 66 C3 81 00 00 00 00 00  f.......
        .byte   $C3,$81,$00,$00,$00,$00,$00,$00 ; 1A30 C3 81 00 00 00 00 00 00  ........
        .byte   $81,$00,$00,$00,$00,$00,$00,$00 ; 1A38 81 00 00 00 00 00 00 00  ........
        .byte   $C0,$70,$3C,$1F,$1F,$3C,$70,$C0 ; 1A40 C0 70 3C 1F 1F 3C 70 C0  .p<..<p.
        .byte   $60,$38,$1E,$0F,$0F,$1E,$38,$60 ; 1A48 60 38 1E 0F 0F 1E 38 60  `8....8`
        .byte   $30,$1C,$0F,$07,$07,$0F,$1C,$30 ; 1A50 30 1C 0F 07 07 0F 1C 30  0......0
        .byte   $18,$0E,$07,$03,$03,$07,$0E,$18 ; 1A58 18 0E 07 03 03 07 0E 18  ........
        .byte   $0C,$07,$03,$01,$01,$03,$07,$0C ; 1A60 0C 07 03 01 01 03 07 0C  ........
        .byte   $06,$03,$01,$00,$00,$01,$03,$06 ; 1A68 06 03 01 00 00 01 03 06  ........
        .byte   $03,$01,$00,$00,$00,$00,$01,$03 ; 1A70 03 01 00 00 00 00 01 03  ........
        .byte   $01,$00,$00,$00,$00,$00,$00,$01 ; 1A78 01 00 00 00 00 00 00 01  ........
        .byte   $81,$C3,$66,$7E,$3C,$3C,$18,$18 ; 1A80 81 C3 66 7E 3C 3C 18 18  ..f~<<..
        .byte   $00,$81,$C3,$66,$7E,$3C,$3C,$18 ; 1A88 00 81 C3 66 7E 3C 3C 18  ...f~<<.
        .byte   $00,$00,$81,$C3,$66,$7E,$3C,$3C ; 1A90 00 00 81 C3 66 7E 3C 3C  ....f~<<
        .byte   $00,$00,$00,$81,$C3,$66,$7E,$3C ; 1A98 00 00 00 81 C3 66 7E 3C  .....f~<
        .byte   $00,$00,$00,$00,$81,$C3,$66,$7E ; 1AA0 00 00 00 00 81 C3 66 7E  ......f~
        .byte   $00,$00,$00,$00,$00,$81,$C3,$66 ; 1AA8 00 00 00 00 00 81 C3 66  .......f
        .byte   $00,$00,$00,$00,$00,$00,$81,$C3 ; 1AB0 00 00 00 00 00 00 81 C3  ........
        .byte   $00,$00,$00,$00,$00,$00,$00,$81 ; 1AB8 00 00 00 00 00 00 00 81  ........
        .byte   $03,$0E,$3C,$F8,$F8,$3C,$0E,$03 ; 1AC0 03 0E 3C F8 F8 3C 0E 03  ..<..<..
        .byte   $06,$1C,$78,$F0,$F0,$78,$1C,$06 ; 1AC8 06 1C 78 F0 F0 78 1C 06  ..x..x..
        .byte   $0C,$38,$F0,$E0,$E0,$F0,$38,$0C ; 1AD0 0C 38 F0 E0 E0 F0 38 0C  .8....8.
        .byte   $18,$70,$E0,$C0,$C0,$E0,$70,$18 ; 1AD8 18 70 E0 C0 C0 E0 70 18  .p....p.
        .byte   $30,$E0,$C0,$80,$80,$C0,$E0,$30 ; 1AE0 30 E0 C0 80 80 C0 E0 30  0......0
        .byte   $60,$C0,$80,$00,$00,$80,$C0,$60 ; 1AE8 60 C0 80 00 00 80 C0 60  `......`
        .byte   $C0,$80,$00,$00,$00,$00,$80,$C0 ; 1AF0 C0 80 00 00 00 00 80 C0  ........
        .byte   $80,$00,$00,$00,$00,$00,$00,$80 ; 1AF8 80 00 00 00 00 00 00 80  ........
        .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; 1B00 00 00 00 00 00 00 00 00  ........
        .byte   $00,$00,$00,$00,$00,$00,$00,$18 ; 1B08 00 00 00 00 00 00 00 18  ........
        .byte   $00,$00,$00,$00,$00,$00,$18,$18 ; 1B10 00 00 00 00 00 00 18 18  ........
        .byte   $00,$00,$00,$00,$00,$18,$18,$3C ; 1B18 00 00 00 00 00 18 18 3C  .......<
        .byte   $00,$00,$00,$00,$18,$18,$3C,$3C ; 1B20 00 00 00 00 18 18 3C 3C  ......<<
        .byte   $00,$00,$00,$18,$18,$3C,$3C,$7E ; 1B28 00 00 00 18 18 3C 3C 7E  .....<<~
        .byte   $00,$00,$18,$18,$3C,$3C,$7E,$66 ; 1B30 00 00 18 18 3C 3C 7E 66  ....<<~f
        .byte   $00,$18,$18,$3C,$3C,$7E,$66,$C3 ; 1B38 00 18 18 3C 3C 7E 66 C3  ...<<~f.
        .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; 1B40 00 00 00 00 00 00 00 00  ........
        .byte   $00,$00,$00,$80,$80,$00,$00,$00 ; 1B48 00 00 00 80 80 00 00 00  ........
        .byte   $00,$00,$00,$C0,$C0,$00,$00,$00 ; 1B50 00 00 00 C0 C0 00 00 00  ........
        .byte   $00,$00,$80,$E0,$E0,$80,$00,$00 ; 1B58 00 00 80 E0 E0 80 00 00  ........
        .byte   $00,$00,$C0,$F0,$F0,$C0,$00,$00 ; 1B60 00 00 C0 F0 F0 C0 00 00  ........
        .byte   $00,$80,$E0,$F8,$F8,$E0,$80,$00 ; 1B68 00 80 E0 F8 F8 E0 80 00  ........
        .byte   $00,$C0,$F0,$7C,$7C,$F0,$C0,$00 ; 1B70 00 C0 F0 7C 7C F0 C0 00  ...||...
        .byte   $80,$E0,$78,$3E,$3E,$78,$E0,$00 ; 1B78 80 E0 78 3E 3E 78 E0 00  ..x>>x..
        .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; 1B80 00 00 00 00 00 00 00 00  ........
        .byte   $18,$00,$00,$00,$00,$00,$00,$00 ; 1B88 18 00 00 00 00 00 00 00  ........
        .byte   $18,$18,$00,$00,$00,$00,$00,$00 ; 1B90 18 18 00 00 00 00 00 00  ........
        .byte   $3C,$18,$18,$00,$00,$00,$00,$00 ; 1B98 3C 18 18 00 00 00 00 00  <.......
        .byte   $3C,$3C,$18,$18,$00,$00,$00,$00 ; 1BA0 3C 3C 18 18 00 00 00 00  <<......
        .byte   $7E,$3C,$3C,$18,$18,$00,$00,$00 ; 1BA8 7E 3C 3C 18 18 00 00 00  ~<<.....
        .byte   $66,$7E,$3C,$3C,$18,$18,$00,$00 ; 1BB0 66 7E 3C 3C 18 18 00 00  f~<<....
        .byte   $C3,$66,$7E,$3C,$3C,$18,$18,$00 ; 1BB8 C3 66 7E 3C 3C 18 18 00  .f~<<...
        .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; 1BC0 00 00 00 00 00 00 00 00  ........
        .byte   $00,$00,$00,$01,$01,$00,$00,$00 ; 1BC8 00 00 00 01 01 00 00 00  ........
        .byte   $00,$00,$00,$03,$03,$00,$00,$00 ; 1BD0 00 00 00 03 03 00 00 00  ........
        .byte   $00,$00,$01,$07,$07,$01,$00,$00 ; 1BD8 00 00 01 07 07 01 00 00  ........
        .byte   $00,$00,$03,$0F,$0F,$03,$00,$00 ; 1BE0 00 00 03 0F 0F 03 00 00  ........
        .byte   $00,$01,$07,$1F,$1F,$07,$01,$00 ; 1BE8 00 01 07 1F 1F 07 01 00  ........
        .byte   $00,$03,$0F,$3E,$3E,$0F,$03,$00 ; 1BF0 00 03 0F 3E 3E 0F 03 00  ...>>...
        .byte   $01,$07,$1E,$7C,$7C,$1E,$07,$01 ; 1BF8 01 07 1E 7C 7C 1E 07 01  ...||...
; soft-sprite cells (chars $80..$BF)
sprite_chars:
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C00 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C08 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C10 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C18 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C20 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C28 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C30 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C38 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C40 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C48 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C50 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C58 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C60 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C68 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C70 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C78 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C80 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C88 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C90 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1C98 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CA0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CA8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CB0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CB8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CC0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CC8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CD0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CD8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CE0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CE8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CF0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1CF8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D00 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D08 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D10 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D18 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D20 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D28 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D30 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D38 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D40 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D48 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D50 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D58 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D60 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D68 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D70 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D78 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D80 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D88 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D90 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1D98 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DA0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DA8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DB0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DB8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DC0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DC8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DD0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DD8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DE0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DE8 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DF0 AA AA AA AA AA AA AA AA  ........
        .byte   $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA ; 1DF8 AA AA AA AA AA AA AA AA  ........
