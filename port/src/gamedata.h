#ifndef GAMEDATA_H
#define GAMEDATA_H

/* Data blocks taken unchanged from the original program (gamedata.c),
 * copied to their original addresses at start-up. */
struct data_block {
    unsigned short addr;
    unsigned short len;
    const unsigned char *data;
};
extern const struct data_block game_data[];

/* Own 8x8 font for screen codes 0-63, replaces the VC20 character ROM (font.c) */
extern const unsigned char font_rom[64][8];

#endif
