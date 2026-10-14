/*
 * LUFTKAMPF - native port of the Commodore VC20 game (Commodore GmbH, 1982)
 *
 * The game logic is a routine-by-routine translation of the reconstructed
 * 6502 source (../../src/luftkampf.s); function and variable names follow
 * ../../src/labels.txt. Like the original, the game draws into a VC20 text
 * screen (22x23 characters, colour RAM, RAM character set with pixel-scrolled
 * "soft sprites"), so this file also contains a small model of the VIC chip
 * and of the few KERNAL/BASIC ROM routines the game calls.
 *
 * Timing: the original has no frame timer, its speed comes from the CPU time
 * each routine needs. Every routine therefore charges an estimate of its
 * 6502 cycles (cyc()), and a frame is shown each time a PAL frame's worth of
 * cycles (1108405 Hz / 50) has been used up.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "raylib.h"
#include "gamedata.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

typedef uint8_t u8;
typedef uint16_t u16;

/* ------------------------------------------------------------------------ */
/* Machine model                                                            */
/* ------------------------------------------------------------------------ */

#define CPU_HZ          1108405L          /* PAL VC20 */
#define FPS             50
#define CYC_PER_FRAME   (CPU_HZ / FPS)
#define SCREEN          0x1E00            /* screen RAM with 3K expansion */
#define COLRAM          0x9600
#define COLS            22
#define ROWS            23

static u8 mem[0x10000];                   /* VC20 address space (RAM parts) */

/* VIC registers the game writes */
static u8 vic_color = 0x1B;               /* $900F background/border */
static u8 vic_memptr = 0xF0;              /* $9005 character memory */
static volatile u8 vic_voice3, vic_noise, vic_volume;   /* $900C $900D $900E */
static int irq_enabled = 1;               /* VIA1 timer IRQ (KERNAL jiffy) */

/* KERNAL screen editor state */
static u8 crsr_col;                       /* $D3 */
static u8 crsr_row;                       /* $D6 */
static u8 txt_color = 6;                  /* $0286 */
static u8 rvs;                            /* $C7 */
static u8 blink_off = 1;                  /* $CC: 0 = cursor blinks */
static u8 blink_phase;                    /* $CF */
static u8 blink_char;                     /* $CE */
static u8 blink_color;                    /* $0287 */
static u8 z278;                           /* $0278, used as a colour by cursor_off */
static int blink_count = 20;              /* $CD */

static long cyc_acc;                      /* cycles not yet turned into a frame */
static long long cyc_total;               /* all cycles so far (statistics) */
static long frame_no;
static double jiffy_acc;

/* input state, set from keyboard / gamepad once per frame */
static int in_up, in_down, in_left, in_right, in_fire;

static void frame(void);

static void cyc(long n)
{
    cyc_acc += n;
    cyc_total += n;
    while (cyc_acc >= CYC_PER_FRAME) {
        cyc_acc -= CYC_PER_FRAME;
        frame();
    }
}

/* estimated 6502 cycle costs of ROM routines */
enum { C_PLOT = 45, C_PUT = 45, C_CHROUT = 120, C_SETCOLOR = 30,
       C_LINPRT = 2500, C_RND = 3600, C_CLRSCR = 11000 };

static int cell_off(void) { return crsr_row * COLS + crsr_col; }

/* KERNAL $FFF0 PLOT (set) - row, column */
static void k_plot(u8 row, u8 col)
{
    crsr_row = row;
    crsr_col = col;
    cyc(C_PLOT);
}

/* KERNAL $EAA1: put character a with colour x at the cursor (no advance).
 * Writes outside the screen are dropped (the original then writes to
 * whatever the line pointer points at). */
static void k_putchar(u8 a, u8 x)
{
    int o = cell_off();
    if (crsr_row < ROWS && o < COLS * ROWS) {
        mem[SCREEN + o] = a;
        mem[COLRAM + o] = x & 0x0F;
    }
    cyc(C_PUT);
}

static u8 k_screen_at_cursor(void)
{
    int o = cell_off();
    return (crsr_row < ROWS && o < COLS * ROWS) ? mem[SCREEN + o] : 0xFF;
}

/* KERNAL $EAB2 + LDA ($F3),Y: colour of the cell under the cursor. On the
 * VC20 only the low nibble of colour RAM exists. */
static u8 k_color_at_cursor(void)
{
    int o = cell_off();
    cyc(C_SETCOLOR);
    return (crsr_row < ROWS && o < COLS * ROWS) ? (mem[COLRAM + o] & 0x0F) : 0x0F;
}

static void k_scroll(void)
{
    memmove(&mem[SCREEN], &mem[SCREEN + COLS], COLS * (ROWS - 1));
    memmove(&mem[COLRAM], &mem[COLRAM + COLS], COLS * (ROWS - 1));
    memset(&mem[SCREEN + COLS * (ROWS - 1)], 0x20, COLS);
    memset(&mem[COLRAM + COLS * (ROWS - 1)], txt_color, COLS);
    crsr_row = ROWS - 1;
}

/* KERNAL $E55F: clear screen (colour RAM gets the current colour), home */
static void k_clrscr(void)
{
    memset(&mem[SCREEN], 0x20, COLS * ROWS);
    memset(&mem[COLRAM], txt_color, COLS * ROWS);
    crsr_row = crsr_col = 0;
    cyc(C_CLRSCR);
}

static void k_newline(void)
{
    crsr_col = 0;
    rvs = 0;
    if (++crsr_row >= ROWS)
        k_scroll();
}

/* KERNAL $E742: screen output of CHROUT */
static void k_chrout(u8 c)
{
    cyc(C_CHROUT);
    switch (c) {
    case 0x0D: k_newline(); return;
    case 0x12: rvs = 1; return;
    case 0x92: rvs = 0; return;
    case 0x1D:
        if (++crsr_col >= COLS) { crsr_col = 0; if (++crsr_row >= ROWS) k_scroll(); }
        return;
    case 0x93: k_clrscr(); return;
    case 0x13: crsr_row = crsr_col = 0; return;
    case 0x90: txt_color = 0; return;
    case 0x05: txt_color = 1; return;
    case 0x1C: txt_color = 2; return;
    case 0x9F: txt_color = 3; return;
    case 0x9C: txt_color = 4; return;
    case 0x1E: txt_color = 5; return;
    case 0x1F: txt_color = 6; return;
    case 0x9E: txt_color = 7; return;
    }
    u8 sc;                                 /* PETSCII -> screen code */
    if (c >= 0x20 && c < 0x40)      sc = c;
    else if (c >= 0x40 && c < 0x60) sc = c - 0x40;
    else if (c >= 0x60 && c < 0x80) sc = c - 0x20;
    else if (c >= 0xA0 && c < 0xC0) sc = c - 0x40;
    else if (c >= 0xC0)             sc = c - 0x80;
    else return;                           /* other control codes: ignored */
    if (rvs) sc |= 0x80;
    int o = cell_off();
    if (o < COLS * ROWS) {
        mem[SCREEN + o] = sc;
        mem[COLRAM + o] = txt_color;
    }
    if (++crsr_col >= COLS) {
        crsr_col = 0;
        if (++crsr_row >= ROWS) k_scroll();
    }
}

/* BASIC $DDCD LINPRT: print the unsigned number hi/lo as BASIC does (" 123") */
static void b_linprt(u8 hi, u8 lo)
{
    char buf[8];
    snprintf(buf, sizeof buf, " %u", (unsigned)(hi << 8 | lo));
    cyc(C_LINPRT - (long)strlen(buf) * C_CHROUT);
    for (char *p = buf; *p; p++)
        k_chrout((u8)*p);
}

/* BASIC: GETBYT on the tokenised expression 'n*RND(1)' -> INT(n*RND(1)) */
static u8 b_rnd(int n)
{
    cyc(C_RND);
    return (u8)(n * (rand() / ((double)RAND_MAX + 1.0)));
}

/* ------------------------------------------------------------------------ */
/* Game variables ($0412-$0496)                                             */
/* ------------------------------------------------------------------------ */

static u8 move_dir, spawn_dx, spawn_dy, spawn_dir, spawn_speed, spawn_x, spawn_y;
static u8 obj, idx_i, enemy_last, tmp, tmp_dir, next_x, next_y;
static u8 shot_x, shot_y;
static u8 lives;                 /* enemies left for the active pilot */
static u8 lives_tab[3];
static u8 turn_a, turn_b, straight_count;
static u8 pilot, round_no, rounds, pilots;
static u8 fire, joy_raw, joy_dir;
static u8 expl_x, expl_y, expl_timer;
static u8 chr_a, chr_b;          /* $043E/$043F */
static u8 score[4];              /* lo/hi per pilot */
static u8 bonus_msg_timer, player_delay, stick_action;
static u8 hiscore[2];
static u8 engine_timer = 0xA6;

/* object table: 7 bytes per object at offsets 0..$46 (enemies 0..$38,
 * player $3F, shot $46) - same layout as the original */
static u8 ot[0x50];
#define ACT(o)   ot[(o) + 0]
#define OX(o)    ot[(o) + 1]
#define OY(o)    ot[(o) + 2]
#define SHIFT(o) ot[(o) + 3]
#define DIR(o)   ot[(o) + 4]
#define SPEED(o) ot[(o) + 5]
#define DELAY(o) ot[(o) + 6]
#define PLAYER   0x3F
#define SHOT     0x46

/* soft-sprite tables ($1166-$118C); the char pairs are swapped at run time */
static const u16 sprite_gfx_tab[12] = {
    0x8CD0, 0x0044, 0x2211, 0x3344,          /* index 0 (object $38): unused */
    0x0652, 0x065A, 0x0662, 0x066A,          /* player: up right down left */
    0x12F2, 0x12FA, 0x1302, 0x130A,          /* shot */
};
static u8 sprite_chr_a[3] = { 0x84, 0x80, 0x82 };
static u8 sprite_chr_b[3] = { 0x85, 0x81, 0x83 };
static const u8 sprite_color[3] = { 0, 1, 1 };
static u16 p9e, pa6;                       /* zero page pointers $9E / $A6 */

/* small tables */
static const u8 step_dy[4] = { 0xFF, 0x00, 0x01, 0x00 };
static const u8 step_dx[4] = { 0x00, 0x01, 0x00, 0xFF };
static const u8 back_dx[4] = { 0x00, 0xFF, 0x00, 0x01 };
static const u8 back_dy[4] = { 0x01, 0x00, 0xFF, 0x00 };
static const u8 turn_tab_a[4] = { 1, 2, 3, 0 };
static const u8 turn_tab_b[4] = { 3, 0, 1, 2 };
static const u8 turn_tab_back[4] = { 2, 3, 0, 1 };
static const u8 cell_shift_tab[4] = { 0x00, 0x15, 0x15, 0x00 };
static const u8 bonus_points[5] = { 10, 20, 50, 100, 200 };

#define TXT_GAME_OVER  0x05F5
#define TXT_TITLE      0x0602
#define TXT_ATTENTION  0x0684
#define TXT_SCORE_P1   0x07E5
#define TXT_SCORE_P2   0x07F2
#define TXT_SCORE_MAX  0x07FF
#define TXT_MENU       0x0CAC
#define TXT_BLANK      0x1595

/* ------------------------------------------------------------------------ */
/* Helpers                                                                  */
/* ------------------------------------------------------------------------ */

/* gotoxy: X = column, Y = row */
static void gotoxy(u8 x, u8 y) { cyc(12); k_plot(y, x); }

static void delay(void) { cyc(1972000); }           /* 6 x 256 x 256 loop */

static void newline(void) { k_chrout(0x0D); }

/* print_texts: table of entries col,row,text...,0 ; terminated by 0 */
static void print_texts(u16 p)
{
    u8 y = 0xFF;
    for (;;) {
        u8 x = mem[(u16)(p + ++y)];
        cyc(20);
        if (x == 0) return;
        u8 row = mem[(u16)(p + ++y)];
        gotoxy(x, row);
        for (y++; mem[(u16)(p + y)] != 0; y++)
            k_chrout(mem[(u16)(p + y)]);
    }
}

/* get_obj_pos: col/row of obj */
static void get_obj_pos(u8 *x, u8 *y) { cyc(20); *y = OY(obj); *x = OX(obj); }

/* next_pos_xy: (x,y) + step(move_dir) -> next_x/next_y */
static void next_pos_xy(u8 x, u8 y)
{
    cyc(40);
    next_y = (u8)(y + step_dy[move_dir & 3]);
    next_x = (u8)(x + step_dx[move_dir & 3]);
}

static void next_pos(void)
{
    u8 x, y;
    get_obj_pos(&x, &y);
    next_pos_xy(x, y);
}

/* check_bounds: 1 if next_x/next_y lies outside the 22x22 playfield */
static int check_bounds(void)
{
    cyc(25);
    if (next_x & 0x80 || next_x >= 0x16) return 1;
    if (next_y & 0x80 || next_y >= 0x16) return 1;
    return 0;
}

/* cell_blocked: 1 if the screen cell next_x/next_y is not a space */
static int cell_blocked(void)
{
    gotoxy(next_x, next_y);
    cyc(15);
    return k_screen_at_cursor() != 0x20;
}

static void clear_cell(u8 x, u8 y)
{
    gotoxy(x, y);
    k_putchar(0x20, 6);
}

/* draw_block: reserve the cell ahead of an enemy (blue reverse space) */
static void draw_block(void)
{
    gotoxy(next_x, next_y);
    k_putchar(0xA0, 6);
}

/* erase_behind: clear the cell behind obj (relative to tmp_dir) */
static void erase_behind(void)
{
    u8 x, y;
    get_obj_pos(&x, &y);
    cyc(30);
    clear_cell((u8)(x + back_dx[tmp_dir & 3]), (u8)(y + back_dy[tmp_dir & 3]));
}

/* try_dir: 0 (carry clear) if the cell in move_dir is free -> obj_dir */
static int try_dir(void)
{
    next_pos();
    if (cell_blocked()) return 1;
    if (check_bounds()) return 1;
    DIR(obj) = move_dir;
    return 0;
}

/* move_obj: step obj one cell in its direction, returns the new coordinate */
static u8 move_obj(void)
{
    cyc(40);
    tmp = DIR(obj);
    switch (tmp & 3) {
    case 0: return --OY(obj);
    case 1: return ++OX(obj);
    case 2: return ++OY(obj);
    default: return --OX(obj);
    }
}

static void rnd10(void) { tmp = b_rnd(10); }

/* ------------------------------------------------------------------------ */
/* Soft sprites                                                             */
/* ------------------------------------------------------------------------ */

static u16 chr_addr(u8 c) { return (u16)(0x1C00 + (((c - 0x80) << 3) & 0xFF)); }

static void sprite_ptrs(void)
{
    cyc(50);
    pa6 = chr_addr(chr_b);
    p9e = chr_addr(chr_a);
}

static void sprite_gfx(void)
{
    cyc(110);
    tmp = (u8)(idx_i << 3);
    u8 x = (u8)((DIR(obj) << 1) + tmp);
    p9e = sprite_gfx_tab[(x >> 1) % 12];
    for (int y = 7; y >= 0; y--)
        mem[(u16)(pa6 + y)] = mem[(u16)(p9e + y)];
}

static void shift_up(void)
{
    for (int y = 1; y <= 7; y++) mem[pa6 + y - 1] = mem[pa6 + y];
    mem[pa6 + 7] = mem[p9e + 0];
    for (int y = 1; y <= 7; y++) mem[p9e + y - 1] = mem[p9e + y];
    mem[p9e + 7] = 0;
}

static void shift_right(int c)               /* carry chains from row to row */
{
    for (int y = 7; y >= 0; y--) {
        u8 a = mem[p9e + y];
        int nc = a & 1;
        mem[p9e + y] = (u8)(a >> 1 | c << 7);
        u8 b = mem[pa6 + y];
        c = b & 1;
        mem[pa6 + y] = (u8)(b >> 1 | nc << 7);
    }
}

static void shift_down(void)
{
    for (int y = 6; y >= 0; y--) mem[pa6 + y + 1] = mem[pa6 + y];
    mem[pa6 + 0] = mem[p9e + 7];
    for (int y = 6; y >= 0; y--) mem[p9e + y + 1] = mem[p9e + y];
    mem[p9e + 0] = 0;
}

static void shift_left(void)
{
    for (int y = 7; y >= 0; y--) {
        u8 a = mem[p9e + y];
        mem[p9e + y] = (u8)(a << 1);
        mem[pa6 + y] = (u8)(mem[pa6 + y] << 1 | a >> 7);
    }
}

static void shift_sprite(void)
{
    cyc(250);
    tmp_dir = DIR(obj);
    switch (tmp_dir & 3) {
    case 0: shift_up(); break;
    case 1: shift_right(0); break;            /* asl before the jump: C = 0 */
    case 2: shift_down(); break;
    default: shift_left(); break;
    }
}

/* init_sprite: X = sprite index; graphics at p9e, characters $80/$81 */
static void init_sprite(int x)
{
    chr_a = sprite_chr_a[x];
    chr_b = sprite_chr_b[x];
    for (idx_i = 0; idx_i <= 7; idx_i++) {
        mem[pa6 + idx_i] = mem[p9e + idx_i];
        mem[pa6 + idx_i + 8] = 0;
        cyc(60);
    }
    sprite_ptrs();
    for (tmp = SHIFT(obj); tmp != 0; tmp--)
        shift_sprite();
}

/* ------------------------------------------------------------------------ */
/* Sound, explosion, score                                                  */
/* ------------------------------------------------------------------------ */

static void start_explosion(void)
{
    u8 x, y;
    cyc(40);
    move_dir = tmp_dir = DIR(obj);
    vic_noise = 0x8D;
    get_obj_pos(&x, &y);
    expl_x = x; expl_y = y;
    gotoxy(x, y);
    expl_timer = 0x28;
    k_putchar(0x8A, 1);
}

static void update_explosion(void)
{
    cyc(15);
    if (!expl_timer) return;
    vic_volume = mem[0x0497 + expl_timer];
    if (--expl_timer) return;
    vic_noise = 0;
    gotoxy(expl_x, expl_y);
    k_putchar(0x20, 6);
}

/* kill_object: clear object X and obj (and the cell ahead of obj) */
static void kill_object(u8 x)
{
    u8 cx, cy, saved = obj;
    obj = x;
    move_dir = DIR(x);
    get_obj_pos(&cx, &cy); clear_cell(cx, cy);
    obj = saved;
    ACT(obj) = 0;
    get_obj_pos(&cx, &cy); clear_cell(cx, cy);
    move_dir = DIR(obj);
    next_pos(); clear_cell(next_x, next_y);
    start_explosion();
}

static void remove_shot(void) { ACT(SHOT) = 0; kill_object(SHOT); }

static void lose_life(void) { lives--; remove_shot(); }

/* add_score: A points for the active pilot, show the score */
static void add_score(u8 a)
{
    int x = (pilot >> 1) << 1;
    u16 s = (u16)(score[x] | score[x + 1] << 8) + a;
    score[x] = s & 0xFF; score[x + 1] = s >> 8;
    cyc(60);
    gotoxy(6, 22);
    b_linprt(score[x + 1], score[x]);
}

static void bonus_msg_update(void)
{
    cyc(12);
    if (!bonus_msg_timer) return;
    if (--bonus_msg_timer == 0)
        print_texts(TXT_BLANK);
}

/* ------------------------------------------------------------------------ */
/* Screens                                                                  */
/* ------------------------------------------------------------------------ */

static void copy_charset(void)
{
    memcpy(&mem[0x1800], &mem[0x8000], 0x200);      /* chars 0-63 from ROM */
    cyc(256 * 34);
}

static void draw_city(void)
{
    vic_color = 0x6D;
    vic_memptr = 0xFE;
    copy_charset();
    k_clrscr();
    newline();
    k_chrout(0x12);
    txt_color = 7;
    for (obj = 1; obj <= 7; obj++) {
        for (idx_i = 1; idx_i <= 2; idx_i++) {
            for (int j = 1; j <= 7; j++) {
                k_chrout(0x1D);
                k_chrout(0x20);
                k_chrout(0x20);
            }
            newline();
            k_chrout(0x12);
        }
        newline();
        k_chrout(0x12);
    }
    for (obj = 0; obj <= 0x15; obj++) {               /* black bar, row 22 */
        k_putchar(0xA0, 0);
        crsr_col++;
    }
    k_chrout(0x92);
    txt_color = 1;
}

static void show_pilot(void)
{
    print_texts(TXT_ATTENTION);
    b_linprt(0, pilot);
    delay();
}

static void update_hiscore(u8 *lo, u8 *hi)
{
    if (*hi < hiscore[1]) return;
    if (*hi == hiscore[1] && *lo < hiscore[0]) return;
    hiscore[1] = *hi;
    hiscore[0] = *lo;
}

static void show_scores(void)
{
    print_texts(TXT_SCORE_P1);
    update_hiscore(&score[0], &score[1]);
    b_linprt(score[1], score[0]);
    if (pilots >= 2) {
        print_texts(TXT_SCORE_P2);
        update_hiscore(&score[2], &score[3]);
        b_linprt(score[3], score[2]);
    }
    print_texts(TXT_SCORE_MAX);
    b_linprt(hiscore[1], hiscore[0]);
}

/* ------------------------------------------------------------------------ */
/* Input                                                                    */
/* ------------------------------------------------------------------------ */

static void read_joystick(void)
{
    cyc(160);
    joy_raw = (u8)((in_up ? 1 : 0) | (in_down ? 2 : 0) | (in_left ? 4 : 0) |
                   (in_right ? 8 : 0) | (in_fire ? 0x80 : 0));
    joy_dir = 4;
    fire = 0;
    if (joy_raw & 1) joy_dir = 0;
    if (joy_raw & 2) joy_dir = 2;
    if (joy_raw & 4) joy_dir = 3;
    if (joy_raw & 8) joy_dir = 1;
    if (joy_raw >= 0x80) fire = 1;
}

static void cursor_off(void)
{
    if (!blink_phase) return;
    blink_phase = 0;
    k_putchar(blink_char, z278);
}

/* pilot_menu: 'ANZAHL PILOTEN', choose 1/2 with the stick, start with fire */
static void pilot_menu(void)
{
    vic_color = 0x5A;
    txt_color = 0;
    k_clrscr();
    print_texts(TXT_MENU);
    txt_color = 1;
    z278 = 1;
    gotoxy(7, 12);
    blink_off = 0;
    pilots = 1;
    rounds = 1;
    for (;;) {
        read_joystick();
        cyc(80);
        if (fire) break;
        if (joy_dir == 3) { cursor_off(); crsr_col = 7; pilots = 1; blink_off = 0; }
        if (joy_dir == 1) { cursor_off(); crsr_col = 14; pilots = 2; }
    }
    blink_off = 1;
    irq_enabled = 0;           /* VIA1_IER = $40: KERNAL interrupt off */
    rounds = 5;
}

/* ------------------------------------------------------------------------ */
/* Enemies                                                                  */
/* ------------------------------------------------------------------------ */

static void spawn_enemies(void)
{
    spawn_dx = 3; spawn_dy = 0; spawn_dir = 2; spawn_speed = 3;
    spawn_x = 0; spawn_y = 0;
    for (obj = 0; obj <= 0x46; obj += 7) { ACT(obj) = 0; cyc(30); }
    enemy_last = 0;
    lives = move_dir;
    idx_i = 0;
    for (obj = 1; obj <= move_dir && idx_i <= 0xA0; obj++, idx_i += 7) {
        cyc(150);
        if (ACT(idx_i) != 0) continue;
        enemy_last += 7;
        ACT(idx_i) = 1;
        OX(idx_i) = spawn_x;
        OY(idx_i) = spawn_y;
        SHIFT(idx_i) = 0;
        DIR(idx_i) = spawn_dir;
        SPEED(idx_i) = spawn_speed;
        DELAY(idx_i) = 4;
        spawn_x += spawn_dx;
        spawn_y += spawn_dy;
    }
}

/* try_turns: try both 90 degree turns, random order; 0 = success */
static int try_turns(void)
{
    cyc(40);
    u8 first = tmp > 5 ? turn_a : turn_b;
    u8 second = tmp > 5 ? turn_b : turn_a;
    move_dir = first;
    if (!try_dir()) return 0;
    move_dir = second;
    return try_dir();
}

static void enemy_turn(void)
{
    rnd10();
    cyc(80);
    tmp_dir = DIR(obj);
    turn_a = turn_tab_a[tmp_dir & 3];
    turn_b = turn_tab_b[tmp_dir & 3];
    if (try_turns()) {
        DIR(obj) = turn_tab_back[tmp_dir & 3];   /* dead end: turn back */
        return;
    }
    draw_block();
    erase_behind();
}

/* enemy_step: enemy has scrolled through a whole cell - move on, maybe turn */
static void enemy_step(void)
{
    next_y = move_obj();
    cyc(30);
    next_x = cell_shift_tab[tmp & 3];
    if (next_x == next_y) { enemy_turn(); return; }     /* reached the edge */
    move_dir = tmp;
    tmp_dir = tmp;
    if (--straight_count == 0) {
        rnd10();
        straight_count = tmp;
    }
    cyc(30);
    if (tmp > 8) { enemy_turn(); return; }              /* random turn */
    if (try_dir()) { enemy_turn(); return; }            /* way blocked */
    draw_block();
    erase_behind();
}

static void move_enemies(void)
{
    for (obj = 0; obj <= enemy_last; obj += 7) {
        cyc(45);
        if (ACT(obj) != 0 && SHIFT(obj) == 7) {
            enemy_step();
            SHIFT(obj) = 0;
        }
    }
}

/* animate_obj: draw the enemy plane one pixel further (chars $40-$7F) */
static void animate_obj(void)
{
    u8 x, y;
    cyc(60);
    SHIFT(obj)++;
    tmp = DIR(obj);
    get_obj_pos(&x, &y);
    gotoxy(x, y);
    tmp = (u8)(tmp << 3);
    tmp_dir = SHIFT(obj);
    k_putchar((u8)(tmp_dir + tmp + 0x40), 2);
    tmp_dir = (u8)(tmp_dir + tmp + 0x60);
    move_dir = DIR(obj);
    try_dir();
    gotoxy(next_x, next_y);
    k_putchar(tmp_dir, 2);
}

static void animate_objects(void)
{
    for (obj = 0; obj <= enemy_last; obj += 7) {
        cyc(55);
        if (ACT(obj) == 0) continue;
        if (DELAY(obj) != 0) { DELAY(obj)--; continue; }
        DELAY(obj) = SPEED(obj);
        animate_obj();
    }
}

/* ------------------------------------------------------------------------ */
/* Player and shot                                                          */
/* ------------------------------------------------------------------------ */

static void init_player(void)
{
    vic_voice3 = 0xBE;
    obj = PLAYER;
    ACT(obj) = 1;
    OX(obj) = 0x15;
    OY(obj) = 0x15;
    DIR(obj) = 3;
    SHIFT(obj) = 0;
    SPEED(obj) = 2;
    DELAY(obj) = 1;
    p9e = 0x066A;
    pa6 = 0x1C00;
    cyc(120);
    init_sprite(1);
}

static void brake_or_reverse(void)
{
    cyc(20);
    if (player_delay != 0x1E) {
        /* slower; ADC #1 with the carry of the compare before it */
        SPEED(obj) = (u8)(player_delay + 1 + (0x1E >= player_delay ? 1 : 0));
        return;
    }
    /* minimum speed reached: reverse */
    SHIFT(PLAYER) = (u8)(8 - SHIFT(PLAYER));
    move_obj();
    DIR(obj) = joy_dir;
    chr_b = sprite_chr_b[1];
    chr_a = sprite_chr_a[1];
    sprite_ptrs();
    idx_i = 1;
    sprite_gfx();
    u8 a = sprite_chr_a[1], b = sprite_chr_b[1];
    chr_a = b;
    chr_b = a;
    sprite_chr_a[1] = b;
    sprite_chr_b[1] = a;
    sprite_ptrs();
    for (int y = 7; y >= 0; y--) mem[pa6 + y] = 0;
    for (tmp = SHIFT(obj); tmp != 0; tmp--)
        shift_sprite();
}

static void accelerate(void)
{
    cyc(20);
    if (player_delay == 2) return;
    SPEED(obj) = (u8)(player_delay - 1);
}

static void turn_player(void)
{
    cyc(20);
    if (SHIFT(obj) != 0) return;              /* only on a cell boundary */
    move_dir = joy_dir;
    u8 old = DIR(obj);
    if (try_dir()) return;
    move_dir = old;
    next_pos();
    clear_cell(next_x, next_y);
    DIR(obj) = joy_dir;
    chr_b = sprite_chr_a[1];
    chr_a = sprite_chr_b[1];
    sprite_ptrs();
    idx_i = 1;
    sprite_gfx();
    /* The original ends with JMP clear_cell while X/Y still hold the table
     * index and $FF (row 255), so that write goes off-screen; dropped here. */
}

static void player_control(void)
{
    cyc(60);
    if (joy_dir >= 4) return;
    player_delay = SPEED(PLAYER);
    obj = PLAYER;
    tmp_dir = DIR(PLAYER);
    tmp = (u8)(tmp_dir - joy_dir);
    stick_action = 2;
    if (tmp_dir == joy_dir) stick_action = 1;
    if (tmp == 2 || tmp == 0xFE) stick_action = 0;
    switch (stick_action) {
    case 0: brake_or_reverse(); break;
    case 1: accelerate(); break;
    default: turn_player(); break;
    }
}

static void fire_shot(void)
{
    cyc(30);
    if (!fire) return;
    obj = SHOT;
    if (ACT(SHOT)) return;
    if (expl_timer) return;
    vic_volume = 0x0F;
    vic_noise = 0xFD;
    DIR(SHOT) = DIR(PLAYER);
    ACT(SHOT) = 1;
    OX(SHOT) = OX(PLAYER);
    OY(SHOT) = OY(PLAYER);
    DELAY(SHOT) = 0;
    SPEED(SHOT) = 1;
    SHIFT(SHOT) = 7;
    cyc(100);
    move_dir = DIR(SHOT);
    next_pos();
    next_pos_xy(next_x, next_y);
    if (check_bounds()) { remove_shot(); return; }
    next_pos();
    OX(SHOT) = next_x;
    OY(SHOT) = next_y;
    chr_a = sprite_chr_a[2];
    chr_b = sprite_chr_b[2];
    sprite_ptrs();
    idx_i = 2;
    sprite_gfx();
}

/* draw the sprite pair of object obj (index idx_i) */
static void draw_sprite(void)
{
    u8 x, y;
    get_obj_pos(&x, &y);
    gotoxy(x, y);
    k_putchar(sprite_chr_a[idx_i], sprite_color[idx_i]);
    move_dir = DIR(obj);
    next_pos();
    gotoxy(next_x, next_y);
    k_putchar(sprite_chr_b[idx_i], sprite_color[idx_i]);
}

/* move_player_and_shot: objects $38 (unused), player, shot */
static void move_player_and_shot(void)
{
    for (idx_i = 0, obj = 0x38; obj <= 0x46; idx_i++, obj += 7) {
        cyc(50);
        if (ACT(obj) == 0) continue;
        if (DELAY(obj) != 0) { DELAY(obj)--; continue; }

        if (engine_timer & 0x80) {             /* engine sound on/off */
            engine_timer = 0x14;
            vic_voice3 ^= 0x80;
            vic_volume = 0x0F;
        }
        engine_timer--;
        DELAY(obj) = SPEED(obj);
        SHIFT(obj)++;
        chr_a = sprite_chr_a[idx_i];
        chr_b = sprite_chr_b[idx_i];
        sprite_ptrs();
        shift_sprite();
        if (SHIFT(obj) < 8) { draw_sprite(); continue; }

        /* scrolled through a whole cell: step to the next one */
        SHIFT(obj) = 0;
        if (obj == SHOT) {
            move_dir = DIR(obj);
            move_obj();
            next_pos();
            if (check_bounds()) {               /* shot leaves the field */
                u8 x, y;
                ACT(obj) = 0;
                tmp_dir = DIR(obj);
                erase_behind();
                get_obj_pos(&x, &y);
                clear_cell(x, y);
                start_explosion();
                return;
            }
            erase_behind();
        }
        u8 t = sprite_chr_b[idx_i];
        sprite_chr_b[idx_i] = sprite_chr_a[idx_i];
        sprite_chr_a[idx_i] = t;
        tmp = 0;
        cyc(60);
        if (obj == SHOT) continue;
        if (obj == 0x38) {
            enemy_step();
        } else if (obj == PLAYER) {
            move_dir = DIR(obj);
            move_obj();
            next_pos();
            if (check_bounds()) enemy_turn();   /* auto-turn at the edge */
        }
        erase_behind();
        next_pos();
        clear_cell(next_x, next_y);
        chr_b = sprite_chr_a[idx_i];
        chr_a = sprite_chr_b[idx_i];
        sprite_ptrs();
        sprite_gfx();
        draw_sprite();
    }
}

/* ------------------------------------------------------------------------ */
/* Collisions                                                               */
/* ------------------------------------------------------------------------ */

static int player_crash(void)
{
    kill_object(obj);
    delay();
    return 1;
}

/* shot_hit_target (colour 0): random bonus. No black objects ever appear
 * on the playfield, so this is not reached in practice. */
static int shot_hit_target(void)
{
    remove_shot();
    tmp = b_rnd(4);
    gotoxy(0x11, 0x16);
    tmp_dir = bonus_points[tmp];
    add_score(tmp_dir);
    b_linprt(0, tmp_dir);
    bonus_msg_timer = 7;
    return 0;
}

static void new_wave(void);

static int shot_hit_enemy(void)
{
    for (obj = 0; obj <= enemy_last; obj += 7) {
        cyc(40);
        if (ACT(obj) == 0) continue;
        tmp_dir = 2;
        u8 saved = obj;
        move_dir = DIR(SHOT);
        obj = SHOT;
        next_pos();
        obj = saved;
        shot_x = next_x;
        shot_y = next_y;
        next_x = OX(obj);
        next_y = OY(obj);
        for (;;) {
            cyc(30);
            if (shot_x == next_x && shot_y == next_y) {
                lose_life();
                add_score(10);
                if (lives == 0) new_wave();
                return 0;
            }
            if (--tmp_dir == 0) break;
            move_dir = DIR(obj);
            next_pos();
        }
    }
    return 0;
}

static void new_wave(void)
{
    add_score(100);
    delay();
    move_dir = 8;
    spawn_enemies();
    k_clrscr();
    show_pilot();
    draw_city();
    init_player();
    add_score(0);
}

/* check_collisions: 1 (carry set) when the player has been rammed */
static int check_collisions(void)
{
    for (idx_i = 0; idx_i <= 3; idx_i++) {
        cyc(30);
        move_dir = idx_i;
        obj = PLAYER;
        next_pos();
        if (check_bounds()) continue;
        gotoxy(next_x, next_y);
        tmp = k_color_at_cursor();
        if (tmp == 2 || tmp == 0) return player_crash();
        if (!ACT(SHOT)) continue;
        obj = SHOT;
        move_dir = DIR(SHOT);
        next_pos();
        if (check_bounds()) continue;
        gotoxy(next_x, next_y);
        tmp = k_color_at_cursor();
        if (tmp == 2) return shot_hit_enemy();
        if (tmp == 0) return shot_hit_target();
    }
    return 0;
}

/* ------------------------------------------------------------------------ */
/* Main program                                                             */
/* ------------------------------------------------------------------------ */

static void title(void)
{
    k_clrscr();
    vic_color = 0x5B;
    vic_memptr = 0xF0;
    txt_color = 0;
    print_texts(TXT_TITLE);
    delay();
    delay();
    pilot_menu();
    k_clrscr();
}

static void game_over(void)
{
    k_clrscr();
    txt_color = 0;
    vic_memptr = 0xF0;
    print_texts(TXT_GAME_OVER);
    delay();
    k_clrscr();
    show_scores();
    delay();
    delay();
    delay();
}

static void play(void)
{
    memset(score, 0, sizeof score);
    for (int x = 7; x >= 0; x--) {
        mem[0x1D00 + x] = 0xFF;                 /* char $A0: solid block */
        mem[0x1900 + x] = 0x00;                 /* char $20: blank */
    }
    lives_tab[1] = lives_tab[2] = 8;
    for (round_no = 1; round_no <= rounds; round_no++) {
        for (pilot = 1; pilot <= pilots; pilot++) {
            lives = move_dir = lives_tab[pilot];
            spawn_enemies();
            show_pilot();
            draw_city();
            init_player();
            add_score(0);
            long long loop_start = cyc_total;
            long loops = 0;
            do {
                loops++;
                cyc(150);
                read_joystick();
                move_enemies();
                player_control();
                fire_shot();
                update_explosion();
                bonus_msg_update();
                move_player_and_shot();
                animate_objects();
            } while (!check_collisions());
            if (getenv("LK_DEBUG"))
                fprintf(stderr, "round %d pilot %d: %ld loops, %.0f cycles/loop\n",
                        round_no, pilot, loops, (double)(cyc_total - loop_start) / loops);
            vic_volume = 0;
            lives_tab[pilot] = lives;
            if (!(rounds == round_no && pilots == pilot))
                k_clrscr();
        }
    }
}

/* ------------------------------------------------------------------------ */
/* Platform layer: window, rendering, sound, input                          */
/* ------------------------------------------------------------------------ */

#define BORDER_X  24
#define BORDER_Y  20
#define IMG_W     (COLS * 8 + 2 * BORDER_X)
#define IMG_H     (ROWS * 8 + 2 * BORDER_Y)
#define SCALE_X   4
#define SCALE_Y   3

static const Color palette[8] = {        /* VIC colours 0-7 (VICE "mike-pal") */
    {0x00, 0x00, 0x00, 255}, {0xFF, 0xFF, 0xFF, 255}, {0xB6, 0x1F, 0x21, 255},
    {0x4D, 0xF0, 0xFF, 255}, {0xB4, 0x3F, 0xFF, 255}, {0x44, 0xE2, 0x37, 255},
    {0x1A, 0x34, 0xFF, 255}, {0xDC, 0xD7, 0x1B, 255},
};

static Color pixels[IMG_W * IMG_H];
static Texture2D screen_tex;
static AudioStream stream;

static void render_pixels(void)
{
    Color border = palette[vic_color & 7];
    Color bg = palette[(vic_color >> 4) & 7];
    u16 charbase = (vic_memptr & 0x0F) < 8 ? 0x8000 + (vic_memptr & 7) * 0x400
                                           : (vic_memptr & 7) * 0x400;
    for (int i = 0; i < IMG_W * IMG_H; i++) pixels[i] = border;
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) {
            u8 ch = mem[SCREEN + r * COLS + c];
            Color fg = palette[mem[COLRAM + r * COLS + c] & 7];
            for (int y = 0; y < 8; y++) {
                u8 bits = mem[(u16)(charbase + ch * 8 + y)];
                Color *p = &pixels[(BORDER_Y + r * 8 + y) * IMG_W + BORDER_X + c * 8];
                for (int x = 0; x < 8; x++)
                    p[x] = (bits & (0x80 >> x)) ? fg : bg;
            }
        }
}

static int headless;                      /* test mode: no presentation */

static double t_pix, t_upload, t_draw, t_last_report;
static long frames_reported, skipped;
static double late_sum, work_sum, sleep_sum;     /* timing statistics */

static void render(void)
{
    double t0 = GetTime();
    render_pixels();
    if (headless) return;
    double t1 = GetTime();
    UpdateTexture(screen_tex, pixels);
    double t2 = GetTime();

    BeginDrawing();
    ClearBackground(BLACK);
    float sw = (float)GetScreenWidth(), sh = (float)GetScreenHeight();
    float aspect = (float)(IMG_W * SCALE_X) / (float)(IMG_H * SCALE_Y);
    float w = sw, h = sw / aspect;
    if (h > sh) { h = sh; w = sh * aspect; }
    DrawTexturePro(screen_tex, (Rectangle){0, 0, IMG_W, IMG_H},
                   (Rectangle){(sw - w) / 2, (sh - h) / 2, w, h}, (Vector2){0, 0}, 0, WHITE);
    EndDrawing();
    double t3 = GetTime();
    t_pix += t1 - t0; t_upload += t2 - t1; t_draw += t3 - t2;
    if (getenv("LK_TRACE") && (t3 - t2) > 0.040)
        fprintf(stderr, "frame %ld: draw+wait %.1f ms\n", frame_no, 1000 * (t3 - t2));
    if (getenv("LK_DEBUG") && t3 - t_last_report >= 2.0) {
        long n = frame_no - frames_reported;
        fprintf(stderr, "%ld skipped | %.1f fps | per frame: pixels %.2f ms, upload %.2f ms, draw+wait %.2f ms\n",
                skipped, n / (t3 - t_last_report), 1000 * t_pix / n, 1000 * t_upload / n, 1000 * t_draw / n);
        fprintf(stderr, "   avg late %.1f ms, work %.1f ms, sleep %.1f ms\n",
                1000 * late_sum / n, 1000 * work_sum / n, 1000 * sleep_sum / n);
        late_sum = work_sum = sleep_sum = 0;
        t_pix = t_upload = t_draw = 0;
        t_last_report = t3;
        frames_reported = frame_no;
    }
}

/* KERNAL interrupt: cursor blink (only used in the pilot menu) */
static void kernal_irq(void)
{
    if (blink_off || !irq_enabled) return;
    if (--blink_count) return;
    blink_count = 20;
    int o = cell_off();
    if (o >= COLS * ROWS) return;
    if (blink_phase) {
        blink_phase = 0;
        mem[SCREEN + o] ^= 0x80;
        mem[COLRAM + o] = blink_color;
    } else {
        blink_phase = 1;
        blink_char = mem[SCREEN + o];
        blink_color = mem[COLRAM + o];
        mem[SCREEN + o] = blink_char ^ 0x80;
        mem[COLRAM + o] = txt_color;
    }
}

static void poll_input(void)
{
    int gp = IsGamepadAvailable(0);
    float ax = gp ? GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_X) : 0;
    float ay = gp ? GetGamepadAxisMovement(0, GAMEPAD_AXIS_LEFT_Y) : 0;
    in_up = IsKeyDown(KEY_UP) || IsKeyDown(KEY_KP_8) || IsKeyDown(KEY_W) || ay < -0.5f ||
            (gp && IsGamepadButtonDown(0, GAMEPAD_BUTTON_LEFT_FACE_UP));
    in_down = IsKeyDown(KEY_DOWN) || IsKeyDown(KEY_KP_2) || IsKeyDown(KEY_S) || ay > 0.5f ||
              (gp && IsGamepadButtonDown(0, GAMEPAD_BUTTON_LEFT_FACE_DOWN));
    in_left = IsKeyDown(KEY_LEFT) || IsKeyDown(KEY_KP_4) || IsKeyDown(KEY_A) || ax < -0.5f ||
              (gp && IsGamepadButtonDown(0, GAMEPAD_BUTTON_LEFT_FACE_LEFT));
    in_right = IsKeyDown(KEY_RIGHT) || IsKeyDown(KEY_KP_6) || IsKeyDown(KEY_D) || ax > 0.5f ||
               (gp && IsGamepadButtonDown(0, GAMEPAD_BUTTON_LEFT_FACE_RIGHT));
    in_fire = IsKeyDown(KEY_SPACE) || IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL) ||
              IsKeyDown(KEY_KP_0) || IsKeyDown(KEY_ENTER) ||
              (gp && (IsGamepadButtonDown(0, GAMEPAD_BUTTON_RIGHT_FACE_DOWN) ||
                      IsGamepadButtonDown(0, GAMEPAD_BUTTON_RIGHT_FACE_RIGHT)));
    if (IsKeyPressed(KEY_F11) || (IsKeyPressed(KEY_ENTER) &&
        (IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT))))
        ToggleFullscreen();
}

/* Test mode (environment variables):
 *   LK_INPUT="200:F,215:-,400:U"  at frame N hold U/D/L/R/F ('-' = nothing)
 *   LK_SHOTS="200,400,600" + LK_SHOTDIR=dir  save frame N as dir/frame_N.png
 *   LK_FRAMES=N                    quit after N frames */
static void save_shot(const char *dir)
{
    char path[512];
    Image img = { pixels, IMG_W, IMG_H, 1, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };
    Image big = ImageCopy(img);
    ImageResizeNN(&big, IMG_W * 2, IMG_H * 2);
    snprintf(path, sizeof path, "%s/frame_%05ld.png", dir, frame_no);
    ExportImage(big, path);
    UnloadImage(big);
}

static void autotest(void)
{
    static int held_u, held_d, held_l, held_r, held_f, active = -1;
    const char *in = getenv("LK_INPUT"), *shots = getenv("LK_SHOTS");
    const char *dir = getenv("LK_SHOTDIR"), *frames = getenv("LK_FRAMES");
    if (active < 0) active = headless = (in || shots || frames);
    if (!active) return;
    for (const char *p = in; p && *p; ) {
        long f = strtol(p, (char **)&p, 10);
        if (*p == ':') p++;
        const char *keys = p;
        while (*p && *p != ',') p++;
        if (f == frame_no) {
            held_u = held_d = held_l = held_r = held_f = 0;
            for (const char *k = keys; k < p; k++) {
                if (*k == 'U') held_u = 1;
                if (*k == 'D') held_d = 1;
                if (*k == 'L') held_l = 1;
                if (*k == 'R') held_r = 1;
                if (*k == 'F') held_f = 1;
            }
        }
        if (*p == ',') p++;
    }
    in_up |= held_u; in_down |= held_d; in_left |= held_l; in_right |= held_r; in_fire |= held_f;
    for (const char *p = shots; p && *p; ) {
        long f = strtol(p, (char **)&p, 10);
        if (f == frame_no && dir) { render_pixels(); save_shot(dir); }
        if (*p == ',') p++; else break;
    }
    if (frames && frame_no >= atol(frames)) exit(0);
}

/* one PAL frame: interrupts, input, picture */
static void frame(void)
{
#ifndef __EMSCRIPTEN__
    /* (not in the browser: raylib's web WindowShouldClose() sleeps 16 ms) */
    if (!headless && WindowShouldClose()) {
        UnloadTexture(screen_tex);
        UnloadAudioStream(stream);
        CloseAudioDevice();
        CloseWindow();
        exit(0);
    }
#endif
    for (jiffy_acc += 60.0 / FPS; jiffy_acc >= 1.0; jiffy_acc -= 1.0)
        kernal_irq();
    poll_input();
    autotest();
    /* Frame skipping: if the display lags behind real time (e.g. the GPU is
     * busy with something else), keep the game at full speed and leave out
     * pictures - but show at least one every 0.25 s. */
    static double t_start = -1, t_shown;
    double now = GetTime(), due;
    if (t_start < 0) t_start = t_shown = now;
    due = t_start + (double)frame_no / FPS;
    late_sum += now - due;
    if (headless || now < due + 1.0 / FPS || now - t_shown > 0.25) {
        render();
        t_shown = GetTime();
        if (t_shown - due > 0.5) t_start += t_shown - due - 0.5;   /* don't catch up forever */
    } else {
        PollInputEvents();
        skipped++;
    }
    if (headless) PollInputEvents();
    frame_no++;
#ifdef __EMSCRIPTEN__
    /* Browser: hand control back (ASYNCIFY) until the next frame is due;
     * the browser shows the canvas in the meantime. */
    double wait = t_start + (double)frame_no / FPS - GetTime();
    static double t_woke;
    double t_sleep = GetTime();
    work_sum += t_sleep - t_woke;
    emscripten_sleep(wait > 0 ? (unsigned)(wait * 1000) : 0);
    t_woke = GetTime();
    sleep_sum += t_woke - t_sleep;
#endif
}

/* VIC sound: voice 3 (square) and noise, 4-bit master volume */
#define SAMPLE_RATE 44100
static void audio_callback(void *buffer, unsigned int frames)
{
    static double ph3, phn;
    static unsigned lfsr = 0x7FFF;
    static int noise_out;
    short *out = buffer;
    u8 v3 = vic_voice3, nz = vic_noise, vol = vic_volume & 0x0F;
    double f3 = (v3 & 0x80) ? 17320.0 / (127 - (v3 & 0x7F) + 1e-9) : 0;
    double fn = (nz & 0x80) ? 34640.0 / (127 - (nz & 0x7F) + 1e-9) : 0;
    for (unsigned i = 0; i < frames; i++) {
        int s = 0;
        if (f3 > 0 && f3 < SAMPLE_RATE / 2) {
            ph3 += f3 / SAMPLE_RATE;
            if (ph3 >= 1) ph3 -= (int)ph3;
            s += ph3 < 0.5 ? 1 : -1;
        }
        if (fn > 0) {
            phn += 2 * fn / SAMPLE_RATE;
            while (phn >= 1) {
                phn -= 1;
                unsigned bit = (lfsr ^ (lfsr >> 1)) & 1;
                lfsr = (lfsr >> 1) | (bit << 14);
                noise_out = lfsr & 1;
            }
            s += noise_out ? 1 : -1;
        }
        out[i] = (short)(s * vol * 700);
    }
}

int main(void)
{
    srand((unsigned)time(NULL));
    for (int c = 0; c < 64; c++)                 /* character ROM model */
        for (int y = 0; y < 8; y++) {
            u8 b = font_rom[c][y];
            mem[0x8000 + c * 8 + y] = b;
            mem[0x8400 + c * 8 + y] = (u8)~b;    /* chars 128-191: reverse */
            mem[0x8800 + c * 8 + y] = b;         /* second (lower case) set */
            mem[0x8C00 + c * 8 + y] = (u8)~b;
        }
    for (int i = 0x8200; i < 0x8400; i++) mem[i] = 0;      /* 64-127 */
    for (int i = 0x8600; i < 0x8800; i++) mem[i] = 0xFF;   /* 192-255 */
    for (const struct data_block *b = game_data; b->len; b++)
        memcpy(&mem[b->addr], b->data, b->len);

#ifndef __EMSCRIPTEN__
    SetConfigFlags(FLAG_WINDOW_RESIZABLE);
#endif
    InitWindow(IMG_W * SCALE_X, IMG_H * SCALE_Y, "Luftkampf");
    SetWindowMinSize(IMG_W * 2, IMG_H * 2);
#ifndef __EMSCRIPTEN__
    if (!getenv("LK_NOFPS")) SetTargetFPS(FPS);
#endif
    SetExitKey(KEY_ESCAPE);
    Image img = GenImageColor(IMG_W, IMG_H, BLACK);
    ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
    screen_tex = LoadTextureFromImage(img);
    UnloadImage(img);

    InitAudioDevice();
    SetAudioStreamBufferSizeDefault(1024);
    stream = LoadAudioStream(SAMPLE_RATE, 16, 1);
    SetAudioStreamCallback(stream, audio_callback);
    PlayAudioStream(stream);

    hiscore[0] = hiscore[1] = 0;
    bonus_msg_timer = 0;
    for (;;) {
        irq_enabled = 1;
        title();
        play();
        game_over();
    }
}
