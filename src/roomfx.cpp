// Bruce Lee, a Windows port.
// Copyright (C) 2026 Jacob Marner
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// No copyright is claimed over the original game, which is copyright 1984 Datasoft, Inc.

#include "room.h"

#include "bruce.h"
#include "fighter.h"
#include "game.h"
#include "sound.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

// The room hook at $3A6F, and the enter hook at $4E9C. Each room in the
// original calls print_string, slides a beam, or rewrites a glyph. The
// addresses in the comments are the 6502 hooks this follows.

namespace {

#include "strings.inc"

// $4E97 through $4E9B. The enter hook clears them, then stores its own.
uint8_t t97 = 0;
uint8_t t98 = 0;
uint8_t t99 = 0;
uint8_t t9A = 0;
uint8_t t9B = 0;

// $7B. frame flips this before the hook. A hook that tests it runs when
// the stored value was 0, which is the value 0 after the flip.
int hookGate = 0;

// $71..$79. Beams and the sliding hazard keep these across a room change.
int8_t col71 = 0;
int8_t col72 = 0;
int8_t col73 = 0;
int row74 = 0;
int row75 = 0;
int row76 = 0;
int8_t tim77 = 0;
int8_t tim78 = 0;
int8_t tim79 = 0;
uint8_t slideCol = 0;
uint8_t slideRow = 0;
// Room 18's death flash stores $3E or $3C in $F2, and the interrupt turns
// that into $7C. It stays until enter_room stores the room's charset again.
// -1 is no flash.
int flashCharset = -1;
// $7C as irq_service last set it from $F2. The hook that changes $F2 runs
// after this frame's interrupts, so this frame's overlap still reads the
// bank the previous frame's flash chose.
int irqFlashCharset = -1;
// While enter_room runs the frame hook, Y is not the caption index that
// flicker_lamps leaves on other frames. -1 outside that call.
int entryNoiseY = -1;

int HookNoiseY() {
    return entryNoiseY >= 0 ? entryNoiseY : CaptionNoiseY();
}

// $71..$79 are zero page, so noise_byte can read them. Room 5's lamp reads
// took the beam column and timers from there.
void MirrorHookBytes() {
    NoisePoke(0x71, col71 & 0xFF);
    NoisePoke(0x72, col72 & 0xFF);
    NoisePoke(0x73, col73 & 0xFF);
    NoisePoke(0x74, row74 & 0xFF);
    NoisePoke(0x75, row75 & 0xFF);
    NoisePoke(0x76, row76 & 0xFF);
    NoisePoke(0x77, tim77 & 0xFF);
    NoisePoke(0x78, tim78 & 0xFF);
    NoisePoke(0x79, tim79 & 0xFF);
}

// $60..$66 and $4321. The scrolling floor in rooms 4, 5, 6, 8, 9, and 11.
// The opening snapshot starts on the first step.
uint8_t surfaceWait = 1;
uint8_t surfaceStep = 0;
uint8_t surfaceDown = 0;
uint8_t surfaceCount = 1;
uint8_t surfaceSlot = 7;
// Last step written into each charset bank. -1 means that bank is still
// the file image. Entering a room reloads the file, so the bank is painted
// back to this step before the next scroll.
int bankStep[3] = {-1, -1, -1};

// $4FDE. Three crumble slots. A count of 0 is free.
struct Crumble {
    uint8_t n = 0;
    uint8_t col = 0;
    uint8_t row = 0;
};
Crumble crumb[3];

// $4E95 and $4E96. Room 16 spends the counter for the player who is Bruce.
// It is not put back on a win, and it is not a gate: the fall is given
// every time. Entering the room prints the caption once that counter is 0.
int extraLives[2] = {5, 5};

// $40. A finished game increments the live byte. Room 13's movers read it.
// waitingDifficulty is the other player's $40, swapped with this between lives.
int difficulty = 0;
int waitingDifficulty = 0;

// $014B. Eight $01 bytes. Player 0 uses the first three height bands.
uint8_t bandBonus[8] = {1, 1, 1, 1, 1, 1, 1, 1};

// $010F..$014A. Nine movers. Room 13 fills them on entry.
struct Mover {
    uint8_t active = 0;
    uint8_t col = 0;
    uint8_t row = 0;
    uint8_t low = 0;
    uint8_t high = 0;
};
Mover mover[9];

// Room 18. Two sparks, sprites 6 and 7. phase 0 waits, then the bolt falls.
uint8_t boltX[2] = {0x50, 0x5E};
uint8_t boltY[2] = {0x37, 0x37};
uint8_t boltPhase[2] = {};
uint8_t boltDelay[2] = {0, 0x10};
bool boltOn[2] = {};
uint8_t boltShape[2][63] = {};

// $49/$4A. Room 19 counts 1112 raster ticks, one per interrupt in NoiseIrq.
int victory = 0;

// $87/$88. enter_room stores 0 in both. irq_service adds one to $87 on every
// raster, and adds one to $88 when $87 wraps, until bit 7 of $88 is set.
// step_actors reads $88 in room 19.
int play87 = 0;
int play88 = 0;
// finish_exit zeros $87 after the interrupts that already fired, then jumps
// to frame. The next body sees 0. The wait those interrupts belonged to
// does not run again.
bool wipeVisit = false;
bool skipVisit = false;
// $4EEC and $4F45. The irq refills the three landing charges when the gate
// byte is zero, then decrements it.
int stompGate = 0;
int stompLeft[3] = {2, 2, 2};

// Set when the hook itself changes the room, so Tick does not also move him.
bool relocated = false;

const uint8_t kSurfaceLow[24] = {
    0x0C, 0x33, 0x03, 0xCC, 0x03, 0x33, 0x0C, 0xC3,
    0xCC, 0xFF, 0x33, 0xFF, 0x3C, 0xFF, 0xF3, 0x3F,
    0x30, 0xCC, 0xC0, 0x33, 0xC0, 0xCC, 0x30, 0xC3,
};
const uint8_t kSurfaceHigh[24] = {
    0xC3, 0x30, 0x3F, 0x30, 0xC3, 0x00, 0xFF, 0x00,
    0xC3, 0xFF, 0x3C, 0xFF, 0xC3, 0xFF, 0x3C, 0xFF,
    0xC3, 0x0C, 0xFC, 0x0C, 0xC3, 0x00, 0xFF, 0x00,
};
const uint8_t kSurfaceDelay[8] = {0x84, 0x08, 0x06, 0x04, 0x02, 0x04, 0x06, 0x08};
const uint8_t kBoltMask[4] = {0x18, 0x3C, 0x3C, 0x18};

// $40 == 0, then $40 != 0. hook_enter_13 stores these nine slots.
const Mover kEasy[9] = {
    {0x02, 0x21, 0x07, 0x14, 0x21},
    {0x02, 0x13, 0x0A, 0x06, 0x13},
    {0x02, 0x02, 0x0C, 0x02, 0x21},
    {0x00, 0x00, 0x00, 0x00, 0x00},
    {0x02, 0x16, 0x0C, 0x02, 0x21},
    {0x82, 0x06, 0x05, 0x06, 0x22},
    {0x82, 0x16, 0x05, 0x06, 0x22},
    {0x82, 0x06, 0x07, 0x06, 0x14},
    {0x82, 0x14, 0x0A, 0x14, 0x22},
};
const Mover kHard[9] = {
    {0x02, 0x21, 0x07, 0x12, 0x21},
    {0x02, 0x15, 0x0A, 0x06, 0x15},
    {0x02, 0x02, 0x0C, 0x02, 0x25},
    {0x00, 0x00, 0x00, 0x00, 0x00},
    {0x02, 0x16, 0x0C, 0x02, 0x25},
    {0x82, 0x06, 0x05, 0x06, 0x26},
    {0x82, 0x16, 0x05, 0x06, 0x26},
    {0x82, 0x02, 0x07, 0x02, 0x12},
    {0x82, 0x16, 0x0A, 0x16, 0x26},
};

// raster_irq. $0A/$0B is the room's $480B pointer and $0C/$0D its $4833
// pointer. Twelve bytes from the first go to $0153 every raster.
const uint16_t kBandPtr[20] = {
    0x47C8, 0x47C8, 0x47C8, 0x47C8, 0x47D1, 0x47D1, 0x47D1, 0x47D4, 0x47D4, 0x47D4,
    0x47D7, 0x47DD, 0x47D7, 0x47E0, 0x47D7, 0x47E3, 0x47D7, 0x47EC, 0x47EF, 0x47F2,
};
const uint16_t kSplitPtr[20] = {
    0x47F9, 0x47FC, 0x47FF, 0x4802, 0x4805, 0x4805, 0x4805, 0x4805, 0x4805, 0x4805,
    0x4806, 0x4805, 0x4806, 0x4805, 0x4806, 0x4808, 0x4806, 0x4805, 0x4805, 0x4805,
};
const uint8_t kBandBytes[20][12] = {
    {0xFB, 0xF1, 0xFE, 0xFB, 0xF2, 0xF1, 0xFC, 0xF2, 0xF1, 0xF6, 0xFE, 0xF1},
    {0xFB, 0xF1, 0xFE, 0xFB, 0xF2, 0xF1, 0xFC, 0xF2, 0xF1, 0xF6, 0xFE, 0xF1},
    {0xFB, 0xF1, 0xFE, 0xFB, 0xF2, 0xF1, 0xFC, 0xF2, 0xF1, 0xF6, 0xFE, 0xF1},
    {0xFB, 0xF1, 0xFE, 0xFB, 0xF2, 0xF1, 0xFC, 0xF2, 0xF1, 0xF6, 0xFE, 0xF1},
    {0xF6, 0xFE, 0xF1, 0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB},
    {0xF6, 0xFE, 0xF1, 0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB},
    {0xF6, 0xFE, 0xF1, 0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB},
    {0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB},
    {0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB},
    {0xF8, 0xF9, 0xF1, 0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB},
    {0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB, 0xFE, 0xF6, 0xF1},
    {0xF4, 0xFE, 0xFB, 0xFE, 0xF6, 0xF1, 0xFE, 0xF6, 0xFB, 0xFC, 0xFE, 0xF1},
    {0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB, 0xFE, 0xF6, 0xF1},
    {0xFE, 0xF6, 0xF1, 0xFE, 0xF6, 0xFB, 0xFC, 0xFE, 0xF1, 0xFF, 0xF8, 0xFC},
    {0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB, 0xFE, 0xF6, 0xF1},
    {0xFE, 0xF6, 0xFB, 0xFC, 0xFE, 0xF1, 0xFF, 0xF8, 0xFC, 0xFC, 0xF8, 0xFB},
    {0xF6, 0xFE, 0xFB, 0xFC, 0xFE, 0xFB, 0xF4, 0xFE, 0xFB, 0xFE, 0xF6, 0xF1},
    {0xFC, 0xF8, 0xFB, 0xF0, 0xFE, 0xF4, 0xF6, 0xF2, 0xF1, 0x8A, 0x9A, 0xEA},
    {0xF0, 0xFE, 0xF4, 0xF6, 0xF2, 0xF1, 0x8A, 0x9A, 0xEA, 0xFD, 0x78, 0x97},
    {0xF6, 0xF2, 0xF1, 0x8A, 0x9A, 0xEA, 0xFD, 0x78, 0x97, 0xFD, 0x78, 0x97},
};
// enter_room copies twenty bytes from the $4AA8 pointer to $0153.
const uint8_t kEntryColors[20][20] = {
    {0x04, 0x00, 0x06, 0x88, 0x0E, 0x04, 0x00, 0x0A, 0x0E, 0x34, 0x06, 0x00, 0x0A, 0x0E, 0x34, 0x04, 0x00, 0x0A, 0x0E, 0x34},
    {0x04, 0x00, 0x06, 0x88, 0x0E, 0x04, 0x00, 0x0A, 0x0E, 0x34, 0x06, 0x00, 0x0A, 0x0E, 0x34, 0x04, 0x00, 0x0A, 0x0E, 0x34},
    {0x04, 0x00, 0x06, 0x88, 0x0E, 0x04, 0x00, 0x0A, 0x0E, 0x34, 0x06, 0x00, 0x0A, 0x0E, 0x34, 0x04, 0x00, 0x0A, 0x0E, 0x34},
    {0x04, 0x00, 0x06, 0x88, 0x0E, 0x04, 0x00, 0x0A, 0x0E, 0x34, 0x06, 0x00, 0x0A, 0x0E, 0x34, 0x04, 0x00, 0x0A, 0x0E, 0x34},
    {0x84, 0x00, 0x70, 0x0E, 0x60, 0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88},
    {0x84, 0x00, 0x70, 0x0E, 0x60, 0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88},
    {0x84, 0x00, 0x70, 0x0E, 0x60, 0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88},
    {0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88},
    {0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88},
    {0x34, 0x00, 0x32, 0x0E, 0x40, 0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88},
    {0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88, 0x66, 0x00, 0x8E, 0x02, 0x88},
    {0x66, 0x00, 0x8E, 0x02, 0x88, 0x96, 0x00, 0x00, 0x0E, 0x7C, 0x96, 0x00, 0x0E, 0x00, 0x7C, 0x86, 0x00, 0x60, 0x02, 0x7A},
    {0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88, 0x66, 0x00, 0x8E, 0x02, 0x88},
    {0x96, 0x00, 0x00, 0x0E, 0x7C, 0x96, 0x00, 0x0E, 0x00, 0x7C, 0x86, 0x00, 0x60, 0x02, 0x7A, 0x02, 0x00, 0x60, 0x0E, 0x7A},
    {0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88, 0x66, 0x00, 0x8E, 0x02, 0x88},
    {0x86, 0x00, 0x60, 0x02, 0x7A, 0x02, 0x00, 0x60, 0x0E, 0x7A, 0x04, 0x00, 0x60, 0x06, 0x7E, 0x08, 0x00, 0x2C, 0x04, 0x38},
    {0x74, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x0E, 0x04, 0x88, 0x08, 0x00, 0x2C, 0x04, 0x88, 0x66, 0x00, 0x8E, 0x02, 0x88},
    {0x08, 0x00, 0x2C, 0x04, 0x38, 0x08, 0x00, 0x2C, 0x04, 0x38, 0x00, 0x82, 0x82, 0x68, 0x8C, 0x84, 0x00, 0x70, 0x0F, 0x30},
    {0x00, 0x82, 0x82, 0x68, 0x8C, 0x84, 0x00, 0x70, 0x0F, 0x30, 0x84, 0x00, 0x70, 0x0F, 0x30, 0xF9, 0x09, 0x3E, 0x9D, 0x1B},
    {0x84, 0x00, 0x70, 0x0F, 0x30, 0x84, 0x00, 0x70, 0x0F, 0x30, 0xF9, 0x09, 0x3E, 0x9D, 0x1B, 0x82, 0xDD, 0x27, 0x11, 0x91},
};
// point_at_row. $04/$05 is the screen row, $08/$09 the color row. Rows past
// 19 read on into the next table, as the original does.
const uint16_t kRowScreen[32] = {
    0x8C00, 0x8C28, 0x8C78, 0x8CC8, 0x8D18, 0x8D68, 0x8DB8, 0x8E08,
    0x8E58, 0x8EA8, 0x8EF8, 0x8F48, 0x8F98, 0x8FE8, 0x014D, 0x850D,
    0x65FC, 0xA94D, 0x07D0, 0x8D1D, 0x008C, 0x008C, 0xA08C, 0xF08C,
    0x408D, 0x908D, 0xE08D, 0x308E, 0x808E, 0xD08E, 0x208E, 0x708F,
};
const uint16_t kRowColor[32] = {
    0xCE00, 0xCE00, 0x8CA0, 0x8CF0, 0x8D40, 0x8D90, 0x8DE0, 0x8E30,
    0x8E80, 0x8ED0, 0x8F20, 0x8F70, 0x8FC0, 0x9010, 0xAD0D, 0x0015,
    0x4E4E, 0xD0D0, 0x0F0F, 0xADAD, 0x00CE, 0x00CE, 0x008C, 0x008C,
    0x9C8D, 0x408D, 0x008D, 0x758E, 0x308E, 0x018E, 0x008F, 0x9C8F,
};
// L_55C5. overlap_actors points $04/$05 and $12/$13 at each row it scans.
const uint16_t kOverlapScreen[24] = {
    0x8C28, 0x8C50, 0x8C78, 0x8CA0, 0x8CC8, 0x8CF0, 0x8D18, 0x8D40,
    0x8D68, 0x8D90, 0x8DB8, 0x8DE0, 0x8E08, 0x8E30, 0x8E58, 0x8E80,
    0x8EA8, 0x8ED0, 0x8EF8, 0x8F20, 0x8F48, 0x8F70, 0x8F98, 0x8FC0,
};
const uint16_t kOverlapColor[24] = {
    0xD828, 0xD850, 0xD878, 0xD8A0, 0xD8C8, 0xD8F0, 0xD918, 0xD940,
    0xD968, 0xD990, 0xD9B8, 0xD9E0, 0xDA08, 0xDA30, 0xDA58, 0xDA80,
    0xDAA8, 0xDAD0, 0xDAF8, 0xDB20, 0xDB48, 0xDB70, 0xDB98, 0xDBC0,
};
// $10/$11 and $14/$15 as enter_room leaves them: the color pointer where
// the unpack stopped, and L_336E's pointer past the room's special list.
// Worked out by running the original's enter_room on the boot snapshot.
const uint8_t kEntryScratch[20][4] = {
    {0xE8, 0xDB, 0x0C, 0x4D}, {0xE8, 0xDB, 0x25, 0x4D}, {0xE8, 0xDB, 0x3E, 0x4D}, {0xE8, 0xDB, 0x67, 0x4D},
    {0xEA, 0xDB, 0x70, 0x4D}, {0xE8, 0xDB, 0x79, 0x4D}, {0xE8, 0xDB, 0xA2, 0x4D}, {0xEA, 0xDB, 0xC3, 0x4D},
    {0xE8, 0xDB, 0xF8, 0x4D}, {0xE8, 0xDB, 0x09, 0x4E}, {0xEA, 0xDB, 0x1E, 0x4E}, {0xE8, 0xDB, 0x2B, 0x4E},
    {0xE8, 0xDB, 0x38, 0x4E}, {0xEA, 0xDB, 0x45, 0x4E}, {0xE8, 0xDB, 0x4A, 0x4E}, {0xE8, 0xDB, 0x5B, 0x4E},
    {0xE8, 0xDB, 0x74, 0x4E}, {0xEA, 0xDB, 0x7D, 0x4E}, {0xEA, 0xDB, 0x86, 0x4E}, {0xE8, 0xDB, 0x8B, 0x4E},
};
// $43BE. The address of each string.
const uint16_t kStrAddr[0x65] = {
    0x4488, 0x448C, 0x4490, 0x4494, 0x4750, 0x4498, 0x449E, 0x44A6, 0x44CF, 0x44F4,
    0x4519, 0x457E, 0x458B, 0x453E, 0x44AA, 0x45BC, 0x45B6, 0x45B0, 0x45AA, 0x45C2,
    0x45C4, 0x45C6, 0x45C8, 0x45CD, 0x45CF, 0x45D4, 0x45D8, 0x45DC, 0x45DE, 0x45E4,
    0x45E6, 0x45E8, 0x45EA, 0x45EC, 0x45EF, 0x45F2, 0x45F5, 0x45F8, 0x45FB, 0x45FD,
    0x45FF, 0x4602, 0x4605, 0x4608, 0x460B, 0x460E, 0x4610, 0x4612, 0x4616, 0x461A,
    0x461E, 0x4622, 0x4626, 0x4628, 0x462A, 0x462C, 0x464B, 0x462E, 0x4668, 0x4654,
    0x4637, 0x4671, 0x4659, 0x463C, 0x4676, 0x465E, 0x4641, 0x467B, 0x4663, 0x4646,
    0x4680, 0x4685, 0x4689, 0x468D, 0x4691, 0x4695, 0x4699, 0x469D, 0x46A0, 0x46A3,
    0x46BF, 0x46E0, 0x46F5, 0x46FE, 0x45E0, 0x45E2, 0x472F, 0x4732, 0x4734, 0x4736,
    0x473A, 0x473E, 0x4742, 0x4746, 0x4749, 0x474D, 0x4766, 0x476E, 0x4770, 0x4782,
    0x4784,
};

int8_t Byte(int value) {
    return static_cast<int8_t>(value);
}

// Cells this hook stored. The stick read is a few rasters after it, and
// room 17's beam crosses that raster once six cells have been stored.
int hookTiles = 0;

}  // namespace

void MirrorPointAtRow(int row) {
    if (row < 0 || row >= 32) {
        return;
    }
    const int color = NoisePeek(0x100) != 0 ? 0xCE00 : kRowColor[row];
    NoisePoke(0x04, kRowScreen[row] & 0xFF);
    NoisePoke(0x05, kRowScreen[row] >> 8);
    NoisePoke(0x08, color & 0xFF);
    NoisePoke(0x09, color >> 8);
}

// Bruce is the last actor overlap_actors scans. $1B and $1C keep his fine
// x and y. The scan covers four cell rows and stops after row 23.
void MirrorBruceOverlap(int xpos, int ypos) {
    NoisePoke(0x1B, (xpos - 0x0C) & 0x03);
    NoisePoke(0x1C, (ypos - 0x1D) & 0x07);
    const int first = ((ypos - 0x1D) & 0xFF) >> 3;
    const int last = first >= 23 ? first : std::min(first + 3, 23);
    if (last < 24) {
        NoisePoke(0x04, kOverlapScreen[last] & 0xFF);
        NoisePoke(0x05, kOverlapScreen[last] >> 8);
        NoisePoke(0x12, kOverlapColor[last] & 0xFF);
        NoisePoke(0x13, kOverlapColor[last] >> 8);
    }
}

namespace {

void PrintString(int id, int row, int col) {
    if (id < 0 || id >= 0x65) {
        return;
    }
    const uint8_t* text = kStrBytes + kStrOff[id];
    const int count = kStrLen[id];
    hookTiles += count;
    // print_string leaves point_at_row's pointers in $04/$05 and $08/$09,
    // and the string's address less the column in $06/$07.
    MirrorPointAtRow(row);
    const int source = (kStrAddr[id] - col) & 0xFFFF;
    NoisePoke(0x06, source & 0xFF);
    NoisePoke(0x07, source >> 8);
    for (int i = 0; i < count; ++i) {
        WriteTile(col + i, row, text[i]);
    }
}

void PaintColor(int offset, int color) {
    if (offset < 0 || offset >= 1000) {
        return;
    }
    // A color store is one STA. It does not carry the stick read the way a
    // printed cell does. Room 17's ladder inks 28 of these on the wrap, and
    // that stand still read the previous stick.
    g.color[static_cast<size_t>(offset)] = static_cast<uint8_t>(color);
}

// A one-shot that starts at 0 fires once. One that starts at 1 fires twice.
// The test is BMI on the result, so $FF stops it.
bool Arm(uint8_t& timer) {
    if (timer & 0x80) {
        return false;
    }
    timer = static_cast<uint8_t>(timer - 1);
    return true;
}

// $3A8A. Three rows: blank, blank, and the lintel.
void OpenDoor(int row, int col) {
    // $3A8A. play_sound_8a, then the three rows.
    PlayEffect(0x8A);
    PrintString(0x13, row, col);
    PrintString(0x13, row + 1, col);
    PrintString(0x14, row + 2, col);
    // $3A8D stores the row in $6C and the column in $6D. L_3ACA increments
    // $6C after each string. The solid third row of $3AA0 and $3AAA steps
    // back one and forward one, so every door leaves row + 3.
    NoisePoke(0x6C, (row + 3) & 0xFF);
    NoisePoke(0x6D, col & 0xFF);
}

// $3AA0 and $3AAA. The third row is then a solid tile.
void OpenDoorSolid(int row, int col, int third) {
    OpenDoor(row, col);
    PrintString(third, row + 2, col);
}

// $3AB4. The later charset draws its door from tiles $07 and $0E.
void OpenLateDoor(int row, int col) {
    // $3AB4. The same effect as the early door.
    PlayEffect(0x8A);
    PrintString(0x63, row, col);
    PrintString(0x63, row + 1, col);
    PrintString(0x64, row + 2, col);
    // $3AB7. The same $6C and $6D as the early door.
    NoisePoke(0x6C, (row + 3) & 0xFF);
    NoisePoke(0x6D, col & 0xFF);
}

// $4086. base $1F is the first beam. base $26 is the beam that adds 7 first.
void AdvanceBeam(int8_t& timer, int8_t& col, int limit, int8_t resetTimer, int8_t resetCol,
                 int row, int base) {
    timer = Byte(timer + 1);
    if (timer < 0) {
        return;
    }
    int frame = timer;
    if (timer == 3) {
        if (col < limit) {
            PrintString(base + 6, row, col);
            col = Byte(col + 1);
            timer = 2;
            frame = 2;
        } else {
            frame = 3;
        }
    } else if (timer == 7) {
        timer = resetTimer;
        col = resetCol;
        return;
    }
    PrintString(base + frame, row, col);
}

// $404E writes tile $65 behind and $64 ahead. $4063 writes $67 and $66.
void PaintSlide(int row, int oldCol, int newCol, bool heavy) {
    // $4078. Both slide painters call it. One click per paint.
    PlayEffect(0x89);
    PrintString(heavy ? 0x55 : 0x1C, row, oldCol);
    PrintString(heavy ? 0x54 : 0x1B, row, newCol);
}

// $6E is the column the slide or mover now has, $6F its row, and $70 the
// column it left. noise_byte reads them. Room 7's lamps read $6E. The hooks
// step them, and in the original try_yamo and try_ninja run before the
// hook, so the bytes wait until after those reads, or the next frame's start.
static bool slidePending = false;
static int slidePendingRow = 0;
static int slidePendingOld = 0;
static int slidePendingNew = 0;

static void MirrorSlideBytes(int row, int oldCol, int newCol) {
    slidePending = true;
    slidePendingRow = row;
    slidePendingOld = oldCol;
    slidePendingNew = newCol;
}

static void FlushSlideBytes() {
    if (!slidePending) {
        return;
    }
    slidePending = false;
    NoisePoke(0x6E, slidePendingNew & 0xFF);
    NoisePoke(0x6F, slidePendingRow & 0xFF);
    NoisePoke(0x70, slidePendingOld & 0xFF);
}

void StepSlide(bool right, int limit, int wrap, bool heavy) {
    const int oldCol = slideCol;
    if (right) {
        slideCol = static_cast<uint8_t>(slideCol + 1);
        if (oldCol >= limit) {
            slideCol = static_cast<uint8_t>(wrap);
        }
    } else {
        slideCol = static_cast<uint8_t>(slideCol - 1);
        if (oldCol < limit) {
            slideCol = static_cast<uint8_t>(wrap);
        }
    }
    MirrorSlideBytes(slideRow, oldCol, slideCol);
    PaintSlide(slideRow, oldCol, slideCol, heavy);
}

// $2C70. Each pattern byte is stored twice, filling glyph $61 and its
// shadow $E1, then $62/$E2 and $63/$E3. A wait of $84 keeps bit 7 set and
// does not scroll on the short counts.
void CopySurfaceGlyphs() {
    const uint8_t* pattern = g.roomId < 10 ? kSurfaceLow : kSurfaceHigh;
    const int step = surfaceStep & 7;
    for (int glyph = 0; glyph < 3; ++glyph) {
        const int picture = (0x61 + glyph) * 8;
        const int shadow = (0xE1 + glyph) * 8;
        if (shadow + 8 > static_cast<int>(g.charset.size())) {
            continue;
        }
        for (int i = 0; i < 4; ++i) {
            const uint8_t low = pattern[glyph * 8 + ((step + i) & 7)];
            const uint8_t high = pattern[glyph * 8 + ((step + 4 + i) & 7)];
            g.charset[static_cast<size_t>(picture + i * 2)] = low;
            g.charset[static_cast<size_t>(picture + i * 2 + 1)] = low;
            g.charset[static_cast<size_t>(shadow + i * 2)] = high;
            g.charset[static_cast<size_t>(shadow + i * 2 + 1)] = high;
        }
    }
    if (g.charsetId >= 0 && g.charsetId < 3) {
        bankStep[g.charsetId] = step;
    }
}

// The packed charset is the step-0 picture. A bank that has already scrolled
// is put back on the step it was showing, without advancing $64.
void RestoreSurfaceGlyphs() {
    if (g.charsetId < 0 || g.charsetId > 2 || bankStep[g.charsetId] < 0) {
        return;
    }
    const uint8_t saved = surfaceStep;
    surfaceStep = static_cast<uint8_t>(bankStep[g.charsetId]);
    CopySurfaceGlyphs();
    surfaceStep = saved;
}

void AdvanceSurfaceSlot() {
    surfaceSlot = static_cast<uint8_t>(surfaceSlot - 1);
    if (surfaceSlot & 0x80) {
        surfaceSlot = 7;
        surfaceDown ^= 1;
    }
    surfaceWait = kSurfaceDelay[surfaceSlot];
    surfaceCount = 0x10;
}

void StepSurfaceIndex() {
    if (surfaceDown == 0) {
        surfaceStep = static_cast<uint8_t>(surfaceStep + 1);
        if (surfaceStep >= 8) {
            surfaceStep = 0;
        }
    } else {
        surfaceStep = static_cast<uint8_t>(surfaceStep - 1);
        if (surfaceStep & 0x80) {
            surfaceStep = 7;
        }
    }
}

// $60, $64, $65, and $66 are zero page, so noise_byte can read them.
void MirrorSurfaceBytes() {
    NoisePoke(0x60, surfaceWait);
    NoisePoke(0x64, surfaceStep);
    NoisePoke(0x65, surfaceDown);
    NoisePoke(0x66, surfaceCount);
}

static void AnimateSurfaceBody();

// The hook's surface bytes reach the noise memory after try_yamo and
// try_ninja, through MirrorRoomHookBytes, as for the beams.
void AnimateSurface() {
    AnimateSurfaceBody();
}

static void AnimateSurfaceBody() {
    if (surfaceWait & 0x80) {
        const uint8_t low = static_cast<uint8_t>((surfaceWait & 0x7F) - 1);
        if (low != 0) {
            surfaceWait = static_cast<uint8_t>(low | 0x80);
            return;
        }
        surfaceWait = kSurfaceDelay[surfaceSlot];
        surfaceCount = static_cast<uint8_t>(surfaceCount - 1);
        if ((surfaceCount & 0x80) == 0) {
            return;
        }
        AdvanceSurfaceSlot();
        StepSurfaceIndex();
        CopySurfaceGlyphs();
        return;
    }
    surfaceWait = static_cast<uint8_t>(surfaceWait - 1);
    if (surfaceWait != 0) {
        return;
    }
    // $2C92. The glyph pointer $7D/$7E is $42F1 below room $0A and $4309
    // from there on. The interrupt rewrites $7C from the charset anyway.
    NoisePoke(0x7D, g.roomId < 0x0A ? 0xF1 : 0x09);
    NoisePoke(0x7E, g.roomId < 0x0A ? 0x42 : 0x43);
    surfaceWait = kSurfaceDelay[surfaceSlot];
    surfaceCount = static_cast<uint8_t>(surfaceCount - 1);
    if (surfaceCount & 0x80) {
        AdvanceSurfaceSlot();
    }
    StepSurfaceIndex();
    CopySurfaceGlyphs();
}

// $3228. The count is the value before the increment.
void StepCrumble() {
    for (int slot = 0; slot < 3; ++slot) {
        Crumble& cell = crumb[slot];
        if (cell.n == 0) {
            continue;
        }
        const uint8_t shown = cell.n;
        cell.n = static_cast<uint8_t>(cell.n + 1);
        // $3239. The count leaving 8 is the first flame, and the only blip.
        if (shown == 0x08) {
            PlayEffect(0x8D);
        }
        if (shown == 0x08 || shown == 0x10) {
            PrintString(0x2F, cell.row, cell.col);
            PrintString(0x30, cell.row + 1, cell.col);
        } else if (shown == 0x0C) {
            PrintString(0x31, cell.row, cell.col);
            PrintString(0x32, cell.row + 1, cell.col);
        } else if (shown == 0x14) {
            PrintString(0x00, cell.row, cell.col);
            const int colorAt = (PictureRow(cell.row) + 2) * 40 + (cell.col + 1);
            PaintColor(colorAt, 0xF8);
            PrintString(0x33, cell.row + 1, cell.col);
        } else if (shown == 0x18) {
            cell.n = 0;
        }
    }
    // $32C4. The slot counter $4F counts 2, 1, 0 and leaves $FF.
    NoisePoke(0x4F, 0xFF);
}

void StartCrumble(int col, int row) {
    const int offset = PictureRow(row) * 40 + col;
    if (offset < 0 || offset >= 1000) {
        return;
    }
    // $306B points ($04) at color RAM, then stores $FD. The low three bits
    // become 5, so the next pass of this cell takes the skip. The screen
    // code is left as $60. That glyph is not a wall, and neither are the
    // flame tiles printed later.
    if ((g.color[static_cast<size_t>(offset)] & 7) == 5) {
        return;
    }
    for (int slot = 0; slot < 3; ++slot) {
        if (crumb[slot].n != 0) {
            continue;
        }
        crumb[slot].n = 1;
        crumb[slot].col = static_cast<uint8_t>(col - 1);
        crumb[slot].row = static_cast<uint8_t>(row - 1);
        PaintColor(offset, 0xFD);
        return;
    }
}

void Shock() {
    if (g.action == kZap) {
        return;
    }
    // shock_bruce stores state $19 and timer $10. It leaves $0106. A duck
    // reloads that hold to 1, and the next frame's release_hold spends it
    // and returns before the timer decrement, so the shock frame stays at
    // $10. Clearing the hold here made that frame count down to $0F.
    g.action = kZap;
    g.actionTimer = 0x10;
}

// $D01E. A spark pixel has to land on one of Bruce's sprite pixels. The
// box around the diamond is mostly empty, and that empty part does not shock.
bool BoltTouchesBruce(int index) {
    // Sprites are X-expanded, so each shape bit is two screen pixels. Bruce's
    // picture is already stored at that size. $D01E pairs them one to one.
    const int sx = static_cast<int>(boltX[index]) * 2 - 24;
    const int sy = static_cast<int>(boltY[index]) - 21;
    const uint8_t* shape = boltShape[index];
    for (int row = 0; row < kSpriteRows; ++row) {
        for (int col = 0; col < 24; ++col) {
            const uint8_t bits = shape[row * 3 + col / 8];
            if ((bits & static_cast<uint8_t>(0x80 >> (col & 7))) == 0) {
                continue;
            }
            const int py = sy + row;
            for (int half = 0; half < 2; ++half) {
                if (BruceCovers(sx + col * 2 + half, py)) {
                    return true;
                }
            }
        }
    }
    return false;
}

// $4201 and $4220. hit_sound is effect $86. The move below still runs
// on this frame, from the new $37.
void ArmBolt(int index) {
    boltX[index] = index == 0 ? 0x50 : 0x5E;
    boltY[index] = 0x37;
    boltPhase[index] = 1;
    boltOn[index] = true;
    PlayEffect(0x86);
}

// paint_sparks ($4133). The shape bytes are written before either spark
// is armed, eight noise_byte calls, Y = 0, 3, 6, 9 and each index twice.
// Arming spark 0 skips spark 1's delay for that frame. The Y add runs for
// both before either X step. A Y that reaches $E0 is kept off the sprite,
// and the color noise (Y = $FF after the step loop) is not taken.
void StepBolts() {
    const int target = (g.x + 24) / 2;
    for (int i = 0; i < 2; ++i) {
        // $D01E still holds the spark that was drawn last frame.
        if (boltOn[i] && g.action != kZap && BoltTouchesBruce(i)) {
            Shock();
        }
    }
    for (int row = 0; row < 4; ++row) {
        const uint8_t mask = kBoltMask[3 - row];
        const int index = row * 3;
        boltShape[0][index] = static_cast<uint8_t>(NoiseByte(index) & mask);
        boltShape[1][index] = static_cast<uint8_t>(NoiseByte(index) & mask);
    }
    bool skipSecond = false;
    if (boltPhase[0] == 0) {
        if (boltDelay[0] != 0) {
            boltDelay[0] = static_cast<uint8_t>(boltDelay[0] - 1);
        } else {
            ArmBolt(0);
            skipSecond = true;
        }
    }
    if (!skipSecond && boltPhase[1] == 0) {
        if (boltDelay[1] != 0) {
            boltDelay[1] = static_cast<uint8_t>(boltDelay[1] - 1);
        } else {
            ArmBolt(1);
        }
    }
    for (int i = 1; i >= 0; --i) {
        if (boltPhase[i] == 0) {
            continue;
        }
        const int nextY = static_cast<uint8_t>(boltY[i] + 5);
        if (nextY >= 0xE0) {
            boltPhase[i] = 0;
            boltDelay[i] = 2;
        } else {
            boltY[i] = static_cast<uint8_t>(nextY);
        }
    }
    for (int i = 1; i >= 0; --i) {
        if (boltPhase[i] == 0) {
            continue;
        }
        const int steps = boltY[i] < 0xA8 ? 3 : 2;
        for (int step = 0; step < steps; ++step) {
            if (boltX[i] < target) {
                boltX[i] = static_cast<uint8_t>(boltX[i] + 1);
            } else if (boltX[i] > target) {
                boltX[i] = static_cast<uint8_t>(boltX[i] - 1);
            }
        }
        NoiseByte(0xFF);
    }
}

void ResetBolts() {
    boltX[0] = 0x50;
    boltX[1] = 0x5E;
    boltY[0] = boltY[1] = 0x37;
    boltPhase[0] = boltPhase[1] = 0;
    boltDelay[0] = 0;
    boltDelay[1] = 0x10;
    boltOn[0] = boltOn[1] = false;
}

void StepMovers() {
    for (int i = 8; i >= 0; --i) {
        const uint8_t active = mover[i].active;
        if (active == 0) {
            continue;
        }
        const int oldCol = mover[i].col;
        const int row = mover[i].row;
        if (active & 0x80) {
            mover[i].col = static_cast<uint8_t>(mover[i].col + 1);
            if (mover[i].col >= mover[i].high) {
                mover[i].col = mover[i].low;
            }
        } else {
            mover[i].col = static_cast<uint8_t>(mover[i].col - 1);
            if (mover[i].col < mover[i].low) {
                mover[i].col = mover[i].high;
            }
        }
        // L_104B stores $70 and $6F before the step and $6E after it. The
        // column it left goes to $012D,X and the new one to $0119,X.
        MirrorSlideBytes(row, oldCol, mover[i].col);
        NoisePoke(0x012D + i, oldCol);
        NoisePoke(0x0119 + i, mover[i].col);
        PaintSlide(row, oldCol, mover[i].col, row == 5 || row == 0x0A);
    }
}

// True when a band was paid this frame.
bool HeightBonus() {
    const int ypos = g.y + 21;
    int band = -1;
    if (ypos >= 0x64 && ypos < 0x8A) {
        band = 0;
    } else if (ypos >= 0x8A && ypos < 0xB6) {
        band = 1;
    } else if (ypos >= 0xB6) {
        band = 2;
    }
    if (band < 0) {
        return false;
    }
    // $014B + player * 4. The other player's three flags are the next group.
    const int slot = (gBrucePlayer & 1) * 4 + band;
    if (bandBonus[slot] != 0) {
        bandBonus[slot] = static_cast<uint8_t>(bandBonus[slot] - 1);
        // $3EAF. $01 in the middle byte and $F4 in the low byte, 500.
        AddScoreByte(1, 0x01);
        AddScoreByte(2, 0xF4);
        return true;
    }
    return false;
}

void WinGame() {
    difficulty += 1;
    NoisePoke(0x40, difficulty & 0xFF);
    ResetCollectedLamps();
    RearmRoomBonus();
    // hook_frame_19 writes 1 into this player's four bytes only.
    const int base = (gBrucePlayer & 1) * 4;
    for (int i = 0; i < 4; ++i) {
        bandBonus[base + i] = 1;
    }
    EnterRoom(0);
    PlaceBruce();
    // enter_room_at ends in the per-frame hook. Room 0's blink can run
    // before the next body flips $7B again.
    EnterFrameHook();
    relocated = true;
}

void BlinkTile(uint8_t& timer, uint8_t& phase, int row, int col) {
    timer = static_cast<uint8_t>(timer - 1);
    if ((timer & 0x80) == 0) {
        return;
    }
    if (phase != 0) {
        phase = 0;
        PrintString(0x1E, row, col);
        timer = 5;
    } else {
        // $3654 and $36DD. The $1D string, not the $1E string.
        PlayEffect(0x81);
        phase = static_cast<uint8_t>(phase + 1);
        PrintString(0x1D, row, col);
    }
}

void Frame0() {
    if (LampsLeft(6) != 0 || hookGate != 0) {
        return;
    }
    BlinkTile(t97, t98, 9, 7);
}

void Frame1() {
    if (hookGate != 0 || (t97 & 0x80) != 0) {
        return;
    }
    if (LampsLeft(6) == 0 || LampsLeft(0) != 0 || LampsLeft(1) != 0 || LampsLeft(2) != 0) {
        return;
    }
    t97 = static_cast<uint8_t>(t97 - 1);
    // $3694. The step that leaves the count at 2.
    if (t97 == 2) {
        PlayEffect(0x8A);
    }
    PrintString(static_cast<uint8_t>(t97 + 0x10), 0x0C, 0x11);
}

void Frame2() {
    if (LampsLeft(6) == 0 && (t98 & 0x80) == 0) {
        t98 = static_cast<uint8_t>(t98 - 1);
        // $36BA. Every step of this countdown.
        PlayEffect(0x8A);
        PrintString(0x1A, 0x0B, 0x25);
        PrintString(0x07, 0x0C, 0x25);
    }
    if (LampsLeft(6) != 0 || hookGate != 0) {
        return;
    }
    BlinkTile(t99, t97, 9, 0x21);
}

void Frame3() {
    if (hookGate == 0 && (t97 & 0x80) == 0 && LampsLeft(3) == 0) {
        t97 = static_cast<uint8_t>(t97 - 1);
        // $3715. The step that leaves the count at 2.
        if (t97 == 2) {
            PlayEffect(0x8A);
        }
        PrintString(static_cast<uint8_t>(t97 + 0x10), 0x0C, 0x1D);
    }
    t99 = static_cast<uint8_t>(t99 - 1);
    if ((t99 & 0x80) == 0) {
        return;
    }
    t99 = 0x20;
    if (t98 != 0) {
        t98 = static_cast<uint8_t>(t98 - 1);
        PrintString(0x06, 6, 9);
        PrintString(0x60, 6, 0x15);
    } else {
        t98 = static_cast<uint8_t>(t98 + 1);
        PrintString(0x60, 6, 9);
        PrintString(0x06, 6, 0x15);
    }
}

void Frame4() {
    if (LampPresent(0x4D70)) {
        t99 = static_cast<uint8_t>(t99 + 1);
        if (t99 == 0x20) {
            PrintString(0x34, 4, 0x0B);
        } else if (t99 == 0x40) {
            t99 = 0;
            PrintString(0x36, 4, 0x0B);
        }
    } else if (Arm(t97)) {
        // $379A. Every successful count of this door.
        PlayEffect(0x8A);
        PrintString(0x16, 8, 0x0B);
        PrintString(0x16, 9, 0x0B);
        PrintString(0x25, row75, col72);
    }
    if (LampPresent(0x4D74)) {
        t9A = static_cast<uint8_t>(t9A + 1);
        if (t9A == 0x20) {
            PrintString(0x35, 4, 0x1C);
        } else if (t9A == 0x40) {
            t9A = 0;
            PrintString(0x37, 4, 0x1C);
        }
    } else if (Arm(t98)) {
        // $37F7. Every successful count of this door.
        PlayEffect(0x8A);
        surfaceDown = 0;
        surfaceSlot = 7;
        PrintString(0x16, 8, 0x19);
        PrintString(0x16, 9, 0x19);
        PrintString(0x25, row76, col73);
    }
    AdvanceBeam(tim77, col71, 0x03, Byte(0xA0), 0x01, row74, 0x26);
    if (LampPresent(0x4D70)) {
        AdvanceBeam(tim78, col72, 0x0C, Byte(0xE4), 0x0B, row75, 0x1F);
    }
    if (LampPresent(0x4D74)) {
        AdvanceBeam(tim79, col73, 0x1B, Byte(0xE4), 0x1A, row76, 0x1F);
    }
    AnimateSurface();
}

void Frame5() {
    if (!LampPresent(0x4D99) && Arm(t99)) {
        OpenDoor(0x0A, 0x19);
        OpenDoor(0x0A, 0x1A);
        PrintString(0x25, row75, col72);
    }
    if (!LampPresent(0x4D91) && Arm(t9A)) {
        OpenDoor(0x0A, 0);
        PrintString(0x15, 0x0B, 0);
    }
    const bool side = LampsLeft(6) == 0 &&
        (!LampPresent(0x4D81) || !LampPresent(0x4D89));
    if (side && Arm(t9B)) {
        PrintString(0x19, 2, 0x22);
        OpenDoor(3, 0x1E);
        OpenDoor(6, 0x20);
    }
    AdvanceBeam(tim77, col71, 0x1C, Byte(0xE0), 0x1B, row74, 0x1F);
    if (LampPresent(0x4D99)) {
        AdvanceBeam(tim78, col72, 0x1C, Byte(0xE0), 0x1B, row75, 0x1F);
    }
    AdvanceBeam(tim79, col73, 0x02, Byte(0xE2), 0x01, row76, 0x26);
    AnimateSurface();
}

void Frame6() {
    if (LampsLeft(6) == 0 && Arm(t97)) {
        OpenDoorSolid(5, 1, 0x17);
    }
    StepCrumble();
    AnimateSurface();
}

void Frame7() {
    StepCrumble();
    const bool upper = !LampPresent(0x4DC3) && !LampPresent(0x4DC7) &&
        !LampPresent(0x4DCB) && !LampPresent(0x4DCF) && !LampPresent(0x4DD3);
    if (upper && Arm(t97)) {
        OpenDoorSolid(2, 0x21, 0x17);
        return;
    }
    const bool lower = !LampPresent(0x4DD7) && !LampPresent(0x4DDB) &&
        !LampPresent(0x4DDF) && !LampPresent(0x4DE3) && !LampPresent(0x4DE7) &&
        !LampPresent(0x4DEB);
    if (lower && Arm(t98)) {
        OpenDoorSolid(5, 0x26, 0x17);
        return;
    }
    AdvanceBeam(tim77, col71, 0x24, Byte(0xE0), 0x22, row74, 0x26);
    const bool right = LampPresent(0x4DEF) || LampPresent(0x4DF3);
    if (right) {
        StepSlide(true, 0x23, 5, false);
    } else {
        StepSlide(false, 6, 0x24, false);
    }
}

void Frame8() {
    if (LampsLeft(7) == 0 && !LampPresent(0x4E00) && Arm(t99)) {
        OpenDoor(7, 0x0E);
    }
    if (!LampPresent(0x4DF8) && !LampPresent(0x4DFC) && Arm(t9A)) {
        if (LampPresent(0x4E04)) {
            surfaceDown = 1;
            surfaceSlot = 7;
        }
        OpenDoor(7, 0x19);
    }
    if (LampsLeft(8) == 0 && !LampPresent(0x4E11) && !LampPresent(0x4E15) && Arm(t9B)) {
        OpenDoorSolid(2, 0x26, 0x2D);
    }
    if (!LampPresent(0x4E00) && Arm(t97)) {
        OpenDoor(0x0A, 1);
    }
    if (LampsLeft(7) == 0 && LampsLeft(8) == 0 && Arm(t98)) {
        OpenDoor(0x0A, 0x26);
    }
    AdvanceBeam(tim77, col71, 0x0B, Byte(0xDA), 0x06, row74, 0x1F);
    AdvanceBeam(tim78, col72, 0x20, Byte(0xDA), 0x1B, row75, 0x1F);
    AnimateSurface();
}

void Frame9() {
    if ((t99 & 0x80) == 0 && !LampPresent(0x4E09)) {
        t99 = static_cast<uint8_t>(t99 - 1);
        surfaceDown = 1;
        surfaceSlot = 7;
    }
    if (!LampPresent(0x4E0D) && Arm(t97)) {
        OpenDoor(7, 0x17);
        surfaceDown = 0;
        surfaceSlot = 7;
    }
    if (LampsLeft(9) == 0 && Arm(t98)) {
        // $3BFA. The lamps-clear path. The door path sounds inside OpenDoor.
        PlayEffect(0x8A);
        surfaceDown = 0;
        surfaceSlot = 7;
        PrintString(0x18, 2, 0x23);
    }
    const bool left = !LampPresent(0x4E11) && !LampPresent(0x4E15);
    if (left) {
        StepSlide(false, 5, 0x18, false);
    } else {
        StepSlide(true, 0x18, 4, false);
    }
    AdvanceBeam(tim77, col71, 0x14, Byte(0xC0), 0x10, row74, 0x26);
    AdvanceBeam(tim78, col72, 0x14, Byte(0xC0), 0x10, row75, 0x26);
    AnimateSurface();
}

void Frame10() {
    if ((t97 & 0x80) == 0 && !LampPresent(0x4E1E) && !LampPresent(0x4E22)) {
        t97 = static_cast<uint8_t>(t97 - 1);
        OpenLateDoor(4, 0x26);
    }
    StepCrumble();
}

void Frame11() {
    if ((t97 & 0x80) == 0 && !LampPresent(0x4E33)) {
        t97 = static_cast<uint8_t>(t97 - 1);
        surfaceDown = 0;
        surfaceSlot = 7;
    }
    StepCrumble();
    AnimateSurface();
}

void Frame12() {
    if ((t97 & 0x80) == 0 && !LampPresent(0x4E40)) {
        t97 = static_cast<uint8_t>(t97 - 1);
        OpenLateDoor(0x0A, 0x26);
    }
    if ((t98 & 0x80) == 0 && LampsLeft(12) == 0 &&
        !LampPresent(0x4E52) && !LampPresent(0x4E56)) {
        t98 = static_cast<uint8_t>(t98 - 1);
        OpenLateDoor(7, 0x26);
    }
    StepCrumble();
}

void Frame13() {
    // pay_height ends in JMP add_score, which returns from the hook, so the
    // frame that pays a band skips the mover step at $3EBC.
    if (HeightBonus()) {
        return;
    }
    if (hookGate == 0) {
        StepMovers();
    }
}

void Frame14() {
    if ((t97 & 0x80) == 0 && !LampPresent(0x4E4A) && !LampPresent(0x4E4E)) {
        t97 = static_cast<uint8_t>(t97 - 1);
        OpenLateDoor(4, 0x26);
    }
    StepCrumble();
}

void Frame15() {
    if (!LampPresent(0x4E5B) && Arm(t97)) {
        PlayEffect(0x8A);
        PrintString(0x57, 3, 0x11);
        PrintString(0x58, 4, 0x11);
    }
    if (!LampPresent(0x4E5F) && !LampPresent(0x4E63) && !LampPresent(0x4E6B) && Arm(t98)) {
        PlayEffect(0x8A);
        PrintString(0x57, 3, 0x17);
        PrintString(0x58, 4, 0x17);
    }
    if (LampsLeft(15) == 0 && Arm(t99)) {
        // $3F05, $3F2D, and $3F54. Each arm of this room.
        PlayEffect(0x8A);
        PrintString(0x59, 9, 0x25);
        PrintString(0x5A, 8, 0x25);
        PrintString(0x5B, 7, 0x25);
    }
}

void Frame16() {
    if ((t97 & 0x80) == 0 && LampsLeft(16) == 0) {
        t97 = static_cast<uint8_t>(t97 - 1);
        OpenLateDoor(7, 1);
    }
    StepCrumble();
}

void Frame17() {
    t99 = static_cast<uint8_t>(t99 - 1);
    if (t99 & 0x80) {
        t99 = 0x0A;
        const int ink = (g.color[0x80] & 7) ^ 2;
        for (int i = 0; i < 28; ++i) {
            PaintColor(0x80 + i, ink | 0xF8);
        }
    }
    // $3F8C. A decrement that lands on 0 skips the shove. Any other
    // result shoves, and a wrap stores 1 first so the next frame skips.
    t9A = static_cast<uint8_t>(t9A - 1);
    if (t9A != 0) {
        if (t9A & 0x80) {
            t9A = 1;
        }
        StepSlide(true, 0x1B, 0x0B, false);
    }
    if (t97 != 0 && !LampPresent(0x4E7D)) {
        t97 = static_cast<uint8_t>(t97 - 1);
        PrintString(0x5D, 0x0A, 0x25);
    }
    if (t98 != 0 && !LampPresent(0x4E81)) {
        t98 = static_cast<uint8_t>(t98 - 1);
        PrintString(0x5C, 0x0A, 0x18);
    }
    StepCrumble();
    AdvanceBeam(tim77, col71, 0x23, Byte(0xC8), 0x08, row74, 0x1F);
    AdvanceBeam(tim78, col72, 0x25, Byte(0xCA), 0x08, row75, 0x1F);
    AdvanceBeam(tim79, col73, 0x25, Byte(0xCA), 0x08, row76, 0x1F);
}

// $3D4E. t9A selects the second body on the way up from 0, then the first.
void BossBody(int phase) {
    PrintString(0x38 + phase, 2, 0x10);
    int body = 0;
    if (t9A == 0) {
        t9A = 1;
        body = 6;
    } else {
        t9A = static_cast<uint8_t>(t9A - 1);
    }
    PrintString(0x3B + phase + body, 3, 0x12);
    PrintString(0x3E + phase + body, 4, 0x12);
}

int BossPhase() {
    const int xpos = (g.x + 24) / 2;
    if (xpos >= 0x76) {
        return 2;
    }
    if (xpos >= 0x3A) {
        return 1;
    }
    return 0;
}

// $3DCD. One ink across the wizard while the explosion counts down.
void BossFlash(int color) {
    for (int col = 0; col <= 0x11; ++col) {
        PaintColor(5 * 40 + 11 + col, color);
        PaintColor(6 * 40 + 11 + col, color);
        PaintColor(7 * 40 + 11 + col, color);
        PaintColor(8 * 40 + 11 + col, color);
        if (col >= 0x0C) {
            continue;
        }
        PaintColor(3 * 40 + 14 + col, color);
        PaintColor(4 * 40 + 14 + col, color);
        PaintColor(9 * 40 + 14 + col, color);
        PaintColor(10 * 40 + 14 + col, color);
        PaintColor(11 * 40 + 14 + col, color);
        PaintColor(12 * 40 + 14 + col, color);
    }
}

void Frame18() {
    if (t97 != 0) {
        if (!LampPresent(0x4E86)) {
            t97 = 0;
            boltOn[0] = boltOn[1] = false;
            PrintString(0x61, 0x0B, 0);
            // $3D00. $B8 in the low byte, then $0B in the middle byte, 3000.
            AddScoreByte(2, 0xB8);
            AddScoreByte(1, 0x0B);
            t9A = 0;
            t98 = 0x50;
            BossBody(1);
            return;
        }
        StepBolts();
        t98 = static_cast<uint8_t>(t98 - 1);
        if (t98 != 0) {
            return;
        }
        t98 = 8;
        BossBody(BossPhase());
        return;
    }
    if (t98 == 0) {
        PrintString(0x5E, 0x0B, 0x25);
        PrintString(0x5F, 0x0C, 0x26);
        return;
    }
    // $3DAF. The count is tested before it is decremented. A count of 1
    // consumes one noise byte and then forces the ink to 0. Any other
    // count consumes two, and the second byte's low three bits are the ink.
    // Y is whatever flicker_lamps left, which is the caption index.
    const int noiseY = HookNoiseY();
    const uint8_t shown = t98;
    int ink = 0xF8;
    if (shown == 1) {
        NoiseByte(noiseY);
    } else {
        NoiseByte(noiseY);
        ink = (NoiseByte(noiseY) & 7) | 0xF8;
    }
    // $3DF8. The charset byte $F2 becomes $3E. While the count was still
    // $11 or more, one more noise byte under $10 makes it $3C.
    flashCharset = 0x3E;
    if (shown >= 0x11 && NoiseByte(noiseY) < 0x10) {
        flashCharset = 0x3C;
    }
    NoisePoke(0xF2, flashCharset);
    // $3E0B. Every frame of the flash, while the count is still running.
    PlayEffect(0x8B);
    BossFlash(ink);
    t98 = static_cast<uint8_t>(t98 - 1);
    t9A ^= 1;
    PrintString(0x47 + t9A, 3, 0x0C);
    PrintString(0x49 + t9A, 3, 0x19);
    PrintString(0x4B + t9A, 6, 0x0E);
    PrintString(0x4D + t9A, 6, 0x17);
}

// $49/$4A in page 0, which noise_byte reads. The count stops at 0.
void MirrorVictory() {
    const int left = victory > 0 ? victory : 0;
    NoisePoke(0x49, left & 0xFF);
    NoisePoke(0x4A, (left >> 8) & 0xFF);
}

void Frame19() {
    if (victory <= 0) {
        WinGame();
        return;
    }
    static const int kRows[8] = {0x2AC, 0x2D4, 0x2FC, 0x324, 0x34C, 0x374, 0x39C, 0x3C4};
    // treasure_hold. One noise byte, Y still the caption index.
    const int ink = (NoiseByte(HookNoiseY()) & 7) | 0xF8;
    for (int row = 0; row < 8; ++row) {
        for (int col = 0; col < 29; ++col) {
            PaintColor(kRows[row] + col, ink);
        }
    }
}

void Enter1() { t97 = 3; }
void Enter3() { t97 = 3; }

void Enter4() {
    t9A = 0x1F;
    col71 = 1;
    row74 = 0x0B;
    col72 = 0x0B;
    row75 = 7;
    row76 = 7;
    col73 = 0x1A;
    tim77 = Byte(0xFF);
    tim78 = Byte(0xFF);
    tim79 = Byte(0xF4);
}

void Enter5() {
    for (int offset : {0x9A, 0x9B, 0x9C, 0xC2, 0xC3, 0xC4}) {
        PaintColor(offset, 0xFC);
    }
    col71 = col72 = 0x1B;
    col73 = 1;
    row74 = 9;
    row75 = 0x0A;
    row76 = 5;
    tim77 = Byte(0xFF);
    tim78 = Byte(0xFC);
    tim79 = Byte(0xF8);
}

void Enter7() {
    slideCol = 5;
    slideRow = 0x0B;
    // $3463. $6E and $70 both 5, $6F $0B.
    MirrorSlideBytes(slideRow, slideCol, slideCol);
    col71 = 0x22;
    row74 = 4;
    tim77 = Byte(0xFF);
}

void Enter8() {
    col71 = 6;
    col72 = 0x1B;
    row74 = row75 = 5;
    tim77 = Byte(0xFF);
    tim78 = Byte(0xF2);
}

void Enter9() {
    for (int col = 0; col < 4; ++col) {
        PaintColor(0x9B + col, 0xFA);
        PaintColor(0xC3 + col, 0xFA);
    }
    slideCol = 4;
    slideRow = 0x0C;
    // $349E. $6E and $70 both 4, $6F $0C.
    MirrorSlideBytes(slideRow, slideCol, slideCol);
    col71 = col72 = 0x10;
    row74 = 5;
    row75 = 6;
    tim77 = Byte(0xFC);
    tim78 = Byte(0xFF);
}

void Enter12() { t97 = 1; }

// The mover table is $010F active, $0119 column, $0123 row, $0137 low, and
// $0141 high, nine bytes each. It is in page 1, which noise_byte reads.
// Room 13's lamps read a column one step on from the snapshot's.
void MirrorMover(int i) {
    NoisePoke(0x010F + i, mover[i].active);
    NoisePoke(0x0119 + i, mover[i].col);
    NoisePoke(0x0123 + i, mover[i].row);
    NoisePoke(0x0137 + i, mover[i].low);
    NoisePoke(0x0141 + i, mover[i].high);
}

// hook_enter_13 writes only the active byte of slot 3 ($0112). Its column,
// row, low and high keep what boot left there. It also zeros $0118, the
// tenth active byte, and copies each column to $012D,X.
void Enter13() {
    const Mover* table = difficulty == 0 ? kEasy : kHard;
    for (int i = 0; i < 9; ++i) {
        mover[i] = table[i];
        if (i == 3) {
            NoisePoke(0x0112, 0);
            continue;
        }
        MirrorMover(i);
        NoisePoke(0x012D + i, mover[i].col);
    }
    NoisePoke(0x0118, 0);
}

void Enter14() { t97 = 1; }
void Enter15() { t97 = t98 = t99 = 1; }

void Enter16() {
    static const int kCells[8] = {0x31C, 0x31D, 0x344, 0x345, 0x36C, 0x36D, 0x394, 0x395};
    for (int cell : kCells) {
        PaintColor(cell, 0xFF);
    }
    if (extraLives[gBrucePlayer & 1] == 0) {
        PrintString(0x56, 0x0A, 0x24);
        PrintString(0x56, 0x0B, 0x24);
    }
}

void Enter17() {
    PaintColor(0x31E, 0xFF);
    t97 = 1;
    t98 = 1;
    col71 = col72 = col73 = 8;
    row74 = 3;
    slideRow = 5;
    row75 = 7;
    row76 = 9;
    slideCol = 0x0B;
    tim77 = Byte(0xF8);
    tim78 = Byte(0xF1);
    tim79 = Byte(0xEA);
}

void Enter18() {
    for (int offset = 0x78; offset < 1000; ++offset) {
        PaintColor(offset, 0xFE);
    }
    t97 = 1;
    t98 = 1;
    ResetBolts();
}

void Enter19() {
    victory = 0x0458;
    MirrorVictory();
    play87 = 0;
    play88 = 0;
}

}  // namespace

void MirrorEntryColors(int roomId) {
    if (roomId < 0 || roomId >= kRoomCount) {
        return;
    }
    for (int i = 0; i < 20; ++i) {
        NoisePoke(0x0153 + i, kEntryColors[roomId][i]);
    }
    NoisePoke(0x10, kEntryScratch[roomId][0]);
    NoisePoke(0x11, kEntryScratch[roomId][1]);
    NoisePoke(0x14, kEntryScratch[roomId][2]);
    NoisePoke(0x15, kEntryScratch[roomId][3]);
}

void MirrorRoomHookBytes() {
    MirrorHookBytes();
    MirrorSurfaceBytes();
    FlushSlideBytes();
    NoisePoke(0x7B, hookGate);
}

int FlashCharsetBank() {
    // $F2 is $38, $3A, $3C, or $3E, the banks at $A000, $A800, $B000, and
    // $B800. Room 18's flash is the only writer outside enter_room.
    return irqFlashCharset >= 0x38 ? (irqFlashCharset - 0x38) >> 1 : -1;
}

void PlantDifficulty(int value) {
    // $40 counts finished games. A snapshot taken after the ending holds 1,
    // and test_visit's callers shorten the fighters' waits for it.
    difficulty = value & 0xFF;
    NoisePoke(0x40, difficulty);
}

void MirrorSurface() {
    MirrorSurfaceBytes();
    MirrorHookBytes();
    FlushSlideBytes();
}

void MirrorRasterBytes(int raster) {
    // irq_service clears $44 at $FB. raster_open at $40 clears it again and
    // stores 3 in $F4. Each split of the room's list ($FD ends it) adds 3 to
    // $F4 and 1 to $44. At the usual frame start, just after $FB, $44 is 0
    // and $F4 is 3 plus 3 for each split. Room 2's two splits leave 9 there.
    int splits = 0;
    while (splits < 4 && g.splits[splits] != 0xFD) {
        ++splits;
    }
    int passed = splits;
    int count = 0;
    if (raster >= 0x40 && raster < 0xFB) {
        passed = 0;
        while (passed < splits && raster >= g.splits[passed]) {
            ++passed;
        }
        count = passed;
    }
    NoisePoke(0x44, count);
    NoisePoke(0xF4, 3 + 3 * passed);
}

void ResetRun() {
    // $40, $4E95, and $014B. A win leaves difficulty raised and does not
    // call this. Game over does, because open_room runs clear_work_ram.
    difficulty = 0;
    waitingDifficulty = 0;
    NoisePoke(0x40, 0);
    extraLives[0] = 5;
    extraLives[1] = 5;
    for (int i = 0; i < 8; ++i) {
        bandBonus[i] = 1;
    }
    victory = 0;
    play87 = 0;
    play88 = 0;
    stompGate = 0;
    stompLeft[0] = stompLeft[1] = stompLeft[2] = 2;
    hookGate = 0;
    flashCharset = -1;
    irqFlashCharset = -1;
    t97 = t98 = t99 = t9A = t9B = 0;
    col71 = col72 = col73 = 0;
    row74 = row75 = row76 = 0;
    tim77 = tim78 = tim79 = 0;
    slideCol = 0;
    slideRow = 0;
    // $60, $64, $66 and the delay slot, as init_hardware and enter_room leave them.
    surfaceWait = 1;
    surfaceStep = 0;
    surfaceDown = 0;
    surfaceCount = 1;
    surfaceSlot = 7;
    bankStep[0] = bankStep[1] = bankStep[2] = -1;
    for (int i = 0; i < 3; ++i) {
        crumb[i].n = 0;
    }
    for (int i = 0; i < 9; ++i) {
        mover[i] = {};
    }
    ResetBolts();
}

void PlantWaitingDifficulty(int value) {
    waitingDifficulty = value & 0xFF;
}

void CopyDifficulty() {
    waitingDifficulty = difficulty;
}

void ExchangeDifficulty() {
    const int saved = difficulty;
    difficulty = waitingDifficulty;
    waitingDifficulty = saved;
    NoisePoke(0x40, difficulty & 0xFF);
}

// Pages 0 and 1. ($16),Y with Y at $40 stays inside this buffer.
// clear_work_ram zeros $16, so the pointer walks this page for the whole game.
uint8_t noiseMem[0x200] = {};
// copy_sprite_image fills a 64-byte sprite and returns with Y at $40.
// check_bruce_down then retires a fighter and leaves Y on the voice slot.
int noiseIndex = 0x40;
int postBlitNoise[3] = {-1, -1, -1};

int VoiceSlot(int id) {
    // $59AE. L_0E21 subtracts 3 and reads this table. Room snapshots all
    // hold 04 00 01 02 03 01 02 04 08 10.
    static const uint8_t kSlot[] = {0x04, 0x00, 0x01, 0x02, 0x03, 0x01, 0x02, 0x04, 0x08, 0x10};
    const int index = (id - 3) & 0xFF;
    if (index >= static_cast<int>(sizeof kSlot)) {
        return 0xFF;
    }
    return kSlot[index];
}

int RetireNoiseY(int kind) {
    // $2770 is 01 03 FF: Bruce, Yamo, and the ninja's missing second image.
    // A nonzero $EC,X or $EF,X replaces that with the voice slot. The ninja's
    // $EE is 3, so the slot is $59AE and Y stays 4.
    const int actor = kind & 0xFF;
    int y = actor == 2 ? 0xFF : (actor == 1 ? 0x03 : 0x01);
    if (actor >= 0 && actor + 0xEF < static_cast<int>(sizeof noiseMem)) {
        const int ec = noiseMem[0xEC + actor];
        const int ef = noiseMem[0xEF + actor];
        if (ec != 0) {
            y = VoiceSlot(ec);
        }
        if (ef != 0) {
            y = VoiceSlot(ef);
        }
    }
    return y & 0xFF;
}

int NoiseIndex() {
    return noiseIndex;
}

void NotePostBlitRetire(int kind) {
    if (kind >= 1 && kind <= 2) {
        postBlitNoise[kind] = RetireNoiseY(kind);
    }
}

void ClearPostBlitRetire() {
    postBlitNoise[1] = -1;
    postBlitNoise[2] = -1;
}

void FinishFrameNoise() {
    // blit_sprites copied at least Bruce, so Y is $40 again. check_bruce_down
    // walks the ninja, then Yamo, and a retire after that copy is the Y the
    // next frame's lamps read.
    noiseIndex = 0x40;
    if (postBlitNoise[2] >= 0) {
        noiseIndex = postBlitNoise[2];
    }
    if (postBlitNoise[1] >= 0) {
        noiseIndex = postBlitNoise[1];
    }
    ClearPostBlitRetire();
}

int noiseLo = 0;
int noiseHi = 0;

struct NoiseDefaults {
    NoiseDefaults() {
        noiseMem[0x101] = 1;
        noiseMem[0x102] = 1;
        noiseMem[0x103] = 1;
        noiseMem[0x104] = 1;
    }
} noiseDefaults;

FILE* noiseLog = nullptr;
int noiseFrame = 0;

void BeginNoiseLog(const wchar_t* path) {
    if (noiseLog != nullptr) {
        std::fclose(noiseLog);
        noiseLog = nullptr;
    }
    FILE* file = nullptr;
    if (_wfopen_s(&file, path, L"w") != 0) {
        return;
    }
    noiseLog = file;
}

// Sync= replays what raster timing decides in the original, from a VICE
// recording made with the logger's sync flag: the noise pointer at every
// read, and the $D01E value read_sprite_hits takes. Everything else is still
// the port's own. A read whose byte differs is reported, unless the byte is
// one the raster samples, and VICE's byte is used so the replay goes on. A
// different Y or a different number of reads in a frame is a split in the
// game logic, which ends the replay.
namespace {
struct SyncRead {
    int y;
    int value;
    int lo;
    int hi;
};
std::vector<std::vector<SyncRead>> syncReads;
std::vector<int> syncHits;
std::vector<int> syncSticks;
std::vector<int> syncFires;
std::vector<int> syncIrqs;
long syncStickCount = 0;
bool syncOn = false;
bool syncSplit = false;
size_t syncPos = 0;
int syncFrame = 0;
long syncReadCount = 0;
long syncTimingCount = 0;
long syncValueCount = 0;
long syncHitCount = 0;
int syncSplitFrame = 0;
FILE* syncLog = nullptr;

// The bytes the raster interrupt samples, counts, or the VIC latches. Their
// values follow raster timing, so a difference there is expected. irq_service
// adds one to $7F ($1628), to $80/$81 ($163F), and to the visit clock
// $87/$88 on every raster.
// raster_split adds 3 to $F4 and 1 to $44 at each color split of the room.
// play_sound takes the first free voice, and a voice frees itself when its
// script ends, one command per raster, so which voice pointer ($F6, $F8,
// $FA) an effect lands in follows the interrupts too.
// The start delay at $0F47 counts $18, $19, and $1A down until the
// interrupts have run $48 out, so where those three stop is CPU time.
bool RasterSampled(int addr) {
    switch (addr & 0xFF) {
    case 0x18:
    case 0x19:
    case 0x1A:
    case 0xF6:
    case 0xF7:
    case 0xF8:
    case 0xF9:
    case 0xFA:
    case 0xFB:
    case 0x80:
    case 0x81:
    case 0x44:
    case 0xF4:
    case 0x7F:
    case 0x87:
    case 0x88:
    case 0x67:
    case 0xB9:
    case 0xBA:
    case 0xBB:
    case 0xBC:
    case 0xBD:
    case 0xBE:
        return (addr & 0xFF00) == 0;
    default:
        return false;
    }
}

void SyncSplit(const char* why) {
    if (syncSplit) {
        return;
    }
    syncSplit = true;
    syncSplitFrame = syncFrame;
    if (syncLog != nullptr) {
        std::fprintf(syncLog, "sync split %d %s\n", syncFrame, why);
        std::fflush(syncLog);
    }
}

// The previous frame must have made every read VICE made.
void CloseSyncFrame() {
    if (!syncOn || syncSplit || syncFrame <= 0) {
        return;
    }
    const size_t want = static_cast<size_t>(syncFrame) < syncReads.size() ? syncReads[syncFrame].size() : 0;
    if (syncPos < want) {
        SyncSplit("fewer reads");
    }
}
}  // namespace

bool LoadSync(const char* path, const wchar_t* logPath) {
    std::ifstream file(path);
    if (!file) {
        return false;
    }
    syncReads.clear();
    syncHits.clear();
    syncSticks.clear();
    syncFires.clear();
    syncIrqs.clear();
    syncStickCount = 0;
    std::string line;
    while (std::getline(file, line)) {
        if (line.size() < 3) {
            continue;
        }
        if (line[0] == 'n' && line[1] == 'b' && line[2] == ' ') {
            SyncRead r{};
            int frame = 0;
            if (sscanf_s(line.c_str() + 3, "%d %d %d %d %d", &r.y, &r.value, &r.lo, &r.hi, &frame) != 5 ||
                frame < 0) {
                continue;
            }
            if (static_cast<size_t>(frame) >= syncReads.size()) {
                syncReads.resize(static_cast<size_t>(frame) + 1);
            }
            syncReads[frame].push_back(r);
        } else if (line[0] == 'h' && line[1] == 'r' && line[2] == ' ') {
            int value = 0;
            int frame = 0;
            if (sscanf_s(line.c_str() + 3, "%d %d", &value, &frame) != 2 || frame < 0) {
                continue;
            }
            if (static_cast<size_t>(frame) >= syncHits.size()) {
                syncHits.resize(static_cast<size_t>(frame) + 1, -1);
            }
            syncHits[frame] = value;
        } else if (line[0] == 'i' && line[1] == 'r' && line[2] == ' ') {
            int count = 0;
            int frame = 0;
            if (sscanf_s(line.c_str() + 3, "%d %d", &count, &frame) != 2 || frame < 0) {
                continue;
            }
            if (static_cast<size_t>(frame) >= syncIrqs.size()) {
                syncIrqs.resize(static_cast<size_t>(frame) + 1, -1);
            }
            syncIrqs[frame] = count;
        } else if (line[0] == 's' && line[1] == 't' && line[2] == ' ') {
            // "st stick fire frame", or "st stick frame" from older traces.
            int a = 0;
            int b = 0;
            int c = 0;
            const int got = sscanf_s(line.c_str() + 3, "%d %d %d", &a, &b, &c);
            const int value = a;
            const int fire = got == 3 ? b : -1;
            const int frame = got == 3 ? c : b;
            if (got < 2 || frame < 0) {
                continue;
            }
            if (static_cast<size_t>(frame) >= syncSticks.size()) {
                syncSticks.resize(static_cast<size_t>(frame) + 1, -1);
                syncFires.resize(static_cast<size_t>(frame) + 1, -1);
            }
            syncSticks[frame] = value;
            syncFires[frame] = fire;
        }
    }
    if (syncLog != nullptr) {
        std::fclose(syncLog);
        syncLog = nullptr;
    }
    _wfopen_s(&syncLog, logPath, L"w");
    syncOn = true;
    syncSplit = false;
    syncPos = 0;
    syncFrame = 0;
    syncReadCount = 0;
    syncTimingCount = 0;
    syncValueCount = 0;
    syncHitCount = 0;
    syncSplitFrame = 0;
    return true;
}

bool SyncActive() {
    return syncOn && !syncSplit;
}

int SyncHitValue() {
    if (!SyncActive() || syncFrame < 0 || static_cast<size_t>(syncFrame) >= syncHits.size()) {
        return -1;
    }
    return syncHits[syncFrame];
}

int SyncStickValue() {
    if (!SyncActive() || syncFrame < 0 || static_cast<size_t>(syncFrame) >= syncSticks.size()) {
        return -1;
    }
    return syncSticks[syncFrame];
}

int SyncIrqCount() {
    if (!SyncActive() || syncFrame < 0 || static_cast<size_t>(syncFrame) >= syncIrqs.size()) {
        return -1;
    }
    return syncIrqs[syncFrame];
}

int SyncFireValue() {
    if (!SyncActive() || syncFrame < 0 || static_cast<size_t>(syncFrame) >= syncFires.size()) {
        return -1;
    }
    return syncFires[syncFrame];
}

void SyncNoteStick(bool portNew, bool viceNew) {
    if (portNew == viceNew) {
        return;
    }
    syncStickCount += 1;
    if (syncLog != nullptr) {
        std::fprintf(syncLog, "sync stick %d port %s vice %s\n", syncFrame, portNew ? "new" : "old",
                     viceNew ? "new" : "old");
        std::fflush(syncLog);
    }
}

// A read that saw neither the frame's old nor its new stick: a human's
// stick changed more than once in the raster. That is input timing, so it
// counts with the stick syncs, and the port takes VICE's value.
void SyncNoteStickMismatch(int oldStick, int newStick, int vice) {
    syncStickCount += 1;
    if (syncLog != nullptr) {
        std::fprintf(syncLog, "sync stick %d old %d new %d vice %d\n", syncFrame, oldStick, newStick, vice);
        std::fflush(syncLog);
    }
}

void SyncNoteHit(int port, int vice) {
    if (port == vice) {
        return;
    }
    syncHitCount += 1;
    if (syncLog != nullptr) {
        std::fprintf(syncLog, "sync hit %d port %02X vice %02X\n", syncFrame, port & 0xFF, vice & 0xFF);
        std::fflush(syncLog);
    }
}

void EndSync() {
    if (!syncOn) {
        return;
    }
    CloseSyncFrame();
    if (syncLog != nullptr) {
        if (syncSplit) {
            std::fprintf(syncLog, "sync summary reads %ld timing %ld hits %ld sticks %ld values %ld split %d\n",
                         syncReadCount, syncTimingCount, syncHitCount, syncStickCount, syncValueCount,
                         syncSplitFrame);
        } else {
            std::fprintf(syncLog, "sync summary reads %ld timing %ld hits %ld sticks %ld values %ld split none\n",
                         syncReadCount, syncTimingCount, syncHitCount, syncStickCount, syncValueCount);
        }
        std::fclose(syncLog);
        syncLog = nullptr;
    }
    syncOn = false;
}

void SetNoiseFrame(int frame) {
    CloseSyncFrame();
    noiseFrame = frame;
    syncFrame = frame;
    syncPos = 0;
}

uint8_t NoiseByte(int index) {
    // $115E. Before the game starts, flicker_lamps sees a steady 1.
    if (noiseMem[0x104] == 0) {
        return 1;
    }
    const SyncRead* sync = nullptr;
    if (SyncActive()) {
        const std::vector<SyncRead>* reads =
            static_cast<size_t>(syncFrame) < syncReads.size() ? &syncReads[syncFrame] : nullptr;
        if (reads == nullptr || syncPos >= reads->size()) {
            SyncSplit("more reads");
        } else if ((*reads)[syncPos].y != (index & 0xFF)) {
            SyncSplit("different y");
        } else {
            sync = &(*reads)[syncPos];
            syncPos += 1;
        }
    }
    if (sync != nullptr) {
        // VICE's pointer replaces however many interrupts landed since the
        // last read.
        noiseLo = sync->lo & 0xFF;
        noiseHi = sync->hi & 0xFF;
    } else {
        noiseLo = (noiseLo + 1) & 0xFF;
    }
    noiseMem[0x16] = static_cast<uint8_t>(noiseLo);
    const int addr = ((noiseHi & 0xFF) << 8 | noiseLo) + (index & 0xFF);
    uint8_t byte = 0;
    if (addr >= 0 && addr < static_cast<int>(sizeof noiseMem)) {
        byte = noiseMem[addr];
    }
    if (sync != nullptr) {
        syncReadCount += 1;
        if (byte != static_cast<uint8_t>(sync->value)) {
            const bool timing = RasterSampled(addr);
            if (timing) {
                syncTimingCount += 1;
            } else {
                syncValueCount += 1;
            }
            if (syncLog != nullptr) {
                std::fprintf(syncLog, "sync %s %d addr %04X port %u vice %d\n", timing ? "timing" : "value",
                             syncFrame, addr & 0xFFFF, byte, sync->value);
                std::fflush(syncLog);
            }
            byte = static_cast<uint8_t>(sync->value);
        }
    }
    if (noiseLog != nullptr) {
        std::fprintf(noiseLog, "nb %d %u %d %d %d\n", index & 0xFF, byte, noiseLo, noiseHi & 0xFF,
                     noiseFrame);
        std::fflush(noiseLog);
    }
    return byte;
}

bool DemoMode() {
    return noiseMem[0x104] == 0;
}

void ClearWorkRamNoise() {
    for (int addr = 0x03; addr <= 0xF5; ++addr) {
        noiseMem[addr] = 0;
    }
    for (int i = 0; i < 8; ++i) {
        noiseMem[0x100 + i] = 1;
        noiseMem[0x14B + i] = 1;
    }
    noiseLo = 0;
    noiseHi = 0;
}

void MirrorWorkBytes();

void StartNoiseCounter() {
    // The first frame's lamps read with the Y the start path left, $18.
    noiseIndex = 0x18;
    noiseLo = 6;
    noiseHi = 0;
    noiseMem[0x16] = 6;
    noiseMem[0x17] = 0;
    // $1628. The same six interrupts counted $7F.
    noiseMem[0x7F] = 6;
    // $076F. init_hardware stores $FF in $4B.
    noiseMem[0x4B] = 0xFF;
    // $074F. After enter_room, ($1D) points at $F300, the demo's stick bytes,
    // whether or not this is the demo.
    noiseMem[0x1D] = 0x00;
    noiseMem[0x1E] = 0xF3;
    // enter_room clears the visit clock, and four rasters have counted since.
    play87 = 4;
    play88 = 0;
    noiseMem[0x87] = 4;
    noiseMem[0x88] = 0;
    MirrorWorkBytes();
}

void SetDemoMode(bool on) {
    noiseMem[0x104] = on ? 0 : 1;
}

void MarkLongVisit() {
    play88 = 0x20;
    noiseMem[0x88] = 0x20;
}

int NoisePeek(int addr) {
    if (addr >= 0 && addr < static_cast<int>(sizeof noiseMem)) {
        return noiseMem[addr];
    }
    return 0;
}

void NoisePoke(int addr, int value) {
    if (addr >= 0 && addr < static_cast<int>(sizeof noiseMem)) {
        noiseMem[addr] = static_cast<uint8_t>(value);
    }
}

void NotePrizeGate(bool bit1, int shifts) {
    int value = bit1 ? 2 : 0;
    if (shifts >= 8) {
        value = 0;
    } else if (shifts > 0) {
        value = (value << shifts) & 0xFF;
    }
    NoisePoke(0x53, value);
}

void NoiseAnd(int addr, int mask) {
    if (addr >= 0 && addr < static_cast<int>(sizeof noiseMem)) {
        noiseMem[addr] = static_cast<uint8_t>(noiseMem[addr] & mask);
    }
}

bool NoiseCountdown(int addr) {
    if (addr < 0 || addr >= static_cast<int>(sizeof noiseMem)) {
        return false;
    }
    noiseMem[addr] = static_cast<uint8_t>(noiseMem[addr] - 1);
    return noiseMem[addr] == 0;
}

// Effect scripts $80-$8E, the bytes at $EC31 through the end of $8E.
// voice_1/2/3 copy the pointer into $F6, $F8, or $FA when bit 7 is set,
// then count the delay once per interrupt. The pointer stays after the
// script ends. Command 0 frees the slot. Commands 1-6 store the next
// byte as the delay and skip the rest of the command. Command 7 does not.
static const uint8_t kFxScript[] = {
        0x03, 0x01, 0x3D, 0x02, 0x81, 0x00, 0x04, 0x08, 0x0B, 0x04, 0x00, 0x41, 0x01, 0x10, 0x0D, 0x01,
        0x04, 0x0C, 0x01, 0x04, 0x0B, 0x00, 0x04, 0x01, 0x3D, 0x00, 0x02, 0x41, 0x02, 0x01, 0x46, 0x41,
        0x02, 0x01, 0x3E, 0x41, 0x02, 0x01, 0x4A, 0x41, 0x02, 0x01, 0x44, 0x41, 0x02, 0x01, 0x4D, 0x41,
        0x02, 0x01, 0x46, 0x41, 0x02, 0x01, 0x49, 0x41, 0x02, 0x01, 0x3D, 0x41, 0x02, 0x01, 0x4D, 0x41,
        0x02, 0x01, 0x46, 0x41, 0x02, 0x01, 0x44, 0x41, 0x00, 0x03, 0x01, 0x49, 0x06, 0x81, 0x01, 0x01,
        0x55, 0x01, 0x01, 0x54, 0x01, 0x01, 0x55, 0x01, 0x01, 0x31, 0x02, 0x01, 0x0D, 0x81, 0x00, 0x03,
        0x05, 0x26, 0x00, 0x81, 0x02, 0x04, 0x2B, 0x81, 0x02, 0x04, 0x2E, 0x81, 0x02, 0x01, 0x31, 0x81,
        0x02, 0x01, 0x35, 0x81, 0x02, 0x01, 0x39, 0x81, 0x02, 0x01, 0x3D, 0x81, 0x02, 0x01, 0x41, 0x81,
        0x02, 0x01, 0x44, 0x81, 0x02, 0x01, 0x49, 0x81, 0x02, 0x01, 0x55, 0x81, 0x00, 0x03, 0x01, 0x2E,
        0x00, 0x81, 0x02, 0x01, 0x2E, 0x81, 0x02, 0x01, 0x31, 0x81, 0x02, 0x01, 0x35, 0x81, 0x02, 0x01,
        0x39, 0x81, 0x02, 0x01, 0x3D, 0x81, 0x00, 0x03, 0x01, 0x55, 0x02, 0x81, 0x01, 0x01, 0x31, 0x01,
        0x01, 0x14, 0x02, 0x01, 0x0D, 0x81, 0x02, 0x01, 0x01, 0x81, 0x00, 0x03, 0x01, 0x25, 0x00, 0x11,
        0x02, 0x01, 0x29, 0x11, 0x02, 0x01, 0x2C, 0x11, 0x02, 0x01, 0x31, 0x11, 0x02, 0x01, 0x38, 0x11,
        0x02, 0x01, 0x3D, 0x11, 0x02, 0x01, 0x49, 0x11, 0x02, 0x01, 0x50, 0x11, 0x00, 0x04, 0x01, 0x4F,
        0x02, 0x04, 0x41, 0x02, 0x01, 0x4F, 0x40, 0x02, 0x01, 0x4A, 0x41, 0x02, 0x01, 0x4A, 0x40, 0x02,
        0x01, 0x47, 0x41, 0x02, 0x01, 0x47, 0x40, 0x02, 0x01, 0x43, 0x41, 0x02, 0x01, 0x43, 0x40, 0x02,
        0x01, 0x3E, 0x41, 0x02, 0x01, 0x3E, 0x40, 0x02, 0x01, 0x3B, 0x41, 0x02, 0x01, 0x3B, 0x40, 0x02,
        0x01, 0x37, 0x41, 0x02, 0x01, 0x37, 0x40, 0x02, 0x01, 0x32, 0x41, 0x02, 0x01, 0x32, 0x40, 0x02,
        0x02, 0x38, 0x41, 0x02, 0x02, 0x38, 0x40, 0x00, 0x04, 0x01, 0x3D, 0x0C, 0x12, 0x41, 0x00, 0x03,
        0x10, 0x00, 0x02, 0x00, 0x03, 0x02, 0x00, 0x02, 0x51, 0x01, 0x02, 0x00, 0x01, 0x02, 0x0C, 0x01,
        0x02, 0x0C, 0x01, 0x02, 0x0C, 0x01, 0x02, 0x0C, 0x01, 0x01, 0x0D, 0x01, 0x01, 0x0E, 0x02, 0x01,
        0x00, 0x51, 0x04, 0x2F, 0x48, 0x08, 0x08, 0x41, 0x02, 0x01, 0x48, 0x40, 0x00, 0x03, 0x01, 0x52,
        0x00, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01, 0x52, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01,
        0x52, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01, 0x52, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01,
        0x52, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01, 0x52, 0x81, 0x02, 0x01, 0x52, 0x51, 0x02, 0x01,
        0x29, 0x81, 0x02, 0x01, 0x22, 0x81, 0x00, 0x04, 0x01, 0x26, 0x00, 0x0A, 0x41, 0x06, 0x01, 0x25,
        0x0C, 0x41, 0x02, 0x01, 0x26, 0x51, 0x06, 0x01, 0x25, 0x0E, 0x41, 0x02, 0x01, 0x26, 0x51, 0x06,
        0x01, 0x25, 0x10, 0x41, 0x02, 0x01, 0x26, 0x51, 0x06, 0x01, 0x25, 0x10, 0x41, 0x02, 0x01, 0x26,
        0x51, 0x02, 0x01, 0x25, 0x51, 0x02, 0x01, 0x24, 0x51, 0x02, 0x01, 0x22, 0x51, 0x02, 0x01, 0x20,
        0x51, 0x02, 0x01, 0x1D, 0x51, 0x00, 0x03, 0x04, 0x10, 0x0A, 0x81, 0x01, 0x01, 0x34, 0x01, 0x01,
        0x4C, 0x01, 0x01, 0x28, 0x01, 0x60, 0x10, 0x00, 0x03, 0x01, 0x3C, 0x00, 0x21, 0x02, 0x01, 0x2B,
        0x21, 0x02, 0x01, 0x30, 0x21, 0x02, 0x01, 0x27, 0x21, 0x02, 0x01, 0x2B, 0x21, 0x02, 0x01, 0x3C,
        0x21, 0x02, 0x01, 0x2B, 0x21, 0x02, 0x01, 0x30, 0x21, 0x02, 0x01, 0x27, 0x21, 0x02, 0x01, 0x2B,
        0x21, 0x02, 0x01, 0x3A, 0x21, 0x02, 0x01, 0x29, 0x21, 0x02, 0x01, 0x2E, 0x21, 0x02, 0x01, 0x25,
        0x21, 0x02, 0x01, 0x29, 0x21, 0x02, 0x01, 0x3A, 0x21, 0x02, 0x01, 0x29, 0x21, 0x02, 0x01, 0x2E,
        0x21, 0x02, 0x01, 0x25, 0x21, 0x02, 0x01, 0x29, 0x21, 0x02, 0x01, 0x3C, 0x21, 0x02, 0x01, 0x2B,
        0x21, 0x02, 0x01, 0x30, 0x21, 0x02, 0x01, 0x27, 0x21, 0x02, 0x01, 0x2B, 0x21, 0x02, 0x01, 0x3C,
        0x21, 0x00,
};

static const int kFxOffset[] = {
    0, 6, 22, 73, 95, 141, 167, 187, 221, 296, 303, 349, 407, 470, 488,
};

struct FxVoice {
    uint8_t slot = 0;
    uint8_t priority = 0;
    uint8_t delay = 0;
    int index = 0;
    int origin = 0;
    int zp = 0;
};

FxVoice fxVoice[3] = {
    {0, 0, 0, 0, 0, 0xF6},
    {0, 0, 0, 0, 0, 0xF8},
    {0, 0, 0, 0, 0, 0xFA},
};

void AdvanceFxVoice(FxVoice& voice) {
    if (voice.slot == 0) {
        return;
    }
    if ((voice.slot & 0x80) != 0) {
        const int which = voice.slot & 0x0F;
        if (which > 14) {
            voice.slot = 0;
            return;
        }
        voice.origin = kFxOffset[which];
        const int abs = 0xEC31 + voice.origin;
        NoisePoke(voice.zp, abs & 0xFF);
        NoisePoke(voice.zp + 1, (abs >> 8) & 0xFF);
        voice.delay = 1;
        voice.slot = 1;
        voice.index = 0;
    }
    voice.delay = static_cast<uint8_t>(voice.delay - 1);
    if (voice.delay != 0) {
        return;
    }
    const int at = voice.origin + voice.index;
    if (at < 0 || at >= static_cast<int>(sizeof kFxScript)) {
        voice.slot = 0;
        return;
    }
    const int cmd = kFxScript[at];
    if (cmd == 0 || cmd > 7) {
        voice.slot = 0;
        return;
    }
    static const int kSize[] = {1, 3, 4, 5, 6, 5, 5, 2};
    if (cmd < 7 && at + 1 < static_cast<int>(sizeof kFxScript)) {
        voice.delay = kFxScript[at + 1];
    }
    voice.index += kSize[cmd];
}

void ApplyEffect(int id) {
    if (id < 0x80 || id > 0x8E) {
        return;
    }
    static const uint8_t kPrio[] = {11, 12, 10, 0, 8, 7, 9, 6, 0, 0, 1, 2, 3, 4, 5};
    const int prio = kPrio[id & 0x0F];
    int chosen = -1;
    for (int i = 0; i < 3; ++i) {
        if (fxVoice[i].slot == 0) {
            chosen = i;
            break;
        }
    }
    if (chosen < 0) {
        for (int i = 0; i < 3; ++i) {
            if (prio >= fxVoice[i].priority) {
                chosen = i;
                break;
            }
        }
    }
    if (chosen < 0) {
        return;
    }
    fxVoice[chosen].slot = static_cast<uint8_t>(id);
    fxVoice[chosen].priority = static_cast<uint8_t>(prio);
}

// play_sound runs inside the frame, and the frame is long enough that one
// or two of its three $FB interrupts have often already advanced the
// voices by then. The port runs all three after the frame, so an effect
// queued from the overlap on waits for that many of them. Room 16's walk
// with a fighter on kept the footstep's slot busy across the next dump.
std::vector<int> fxPending;
int fxDefer = 0;
int fxIrqIndex = 0;

void FlushFxPending() {
    for (const int id : fxPending) {
        ApplyEffect(id);
    }
    fxPending.clear();
}

void QueueEffect(int id) {
    if (fxDefer > fxIrqIndex) {
        fxPending.push_back(id);
        return;
    }
    ApplyEffect(id);
}

void BeginFxFrame() {
    FlushFxPending();
    fxDefer = 0;
    fxIrqIndex = 0;
}

void DeferFxUntilIrq(int irqs) {
    fxDefer = irqs;
}

void DescribeFxVoices(int out[9]) {
    for (int i = 0; i < 3; ++i) {
        out[i * 3] = fxVoice[i].slot;
        out[i * 3 + 1] = fxVoice[i].priority;
        out[i * 3 + 2] = fxVoice[i].delay;
    }
}

void SilenceEffects() {
    fxPending.clear();
    for (FxVoice& voice : fxVoice) {
        voice.slot = 0;
        voice.priority = 0;
        voice.delay = 0;
        voice.index = 0;
    }
}

int stompIrqs = 0;

void NoteStompIrqs(int scoreAdds) {
    // stash_scores is about 2500 cycles, and the mainline gets about one
    // screen every 16500. 53 adds, the ninja's health-4 landing, are the
    // eight interrupts past the usual three.
    if (scoreAdds <= 0) {
        return;
    }
    stompIrqs += (scoreAdds * 2500 + 8000) / 16500;
}

int TakeStompIrqs() {
    const int n = stompIrqs;
    stompIrqs = 0;
    return n;
}

void NoiseIrq(int stick, int bruceX, int yamoX, int ninjaX, bool yamoOn, bool ninjaOn, bool fire) {
    // raster_irq, before it calls irq_service. The room's band pointer goes
    // to $0A/$0B, its split pointer to $0C/$0D, and twelve band bytes to $0153.
    if (g.roomId >= 0 && g.roomId < kRoomCount) {
        NoisePoke(0x0A, kBandPtr[g.roomId] & 0xFF);
        NoisePoke(0x0B, kBandPtr[g.roomId] >> 8);
        NoisePoke(0x0C, kSplitPtr[g.roomId] & 0xFF);
        NoisePoke(0x0D, kSplitPtr[g.roomId] >> 8);
        for (int i = 0; i < 12; ++i) {
            NoisePoke(0x0153 + i, kBandBytes[g.roomId][i]);
        }
    }
    // $15EC. Every interrupt copies $F2 into $7C.
    irqFlashCharset = flashCharset;
    // $1678. $49/$4A count down once per interrupt and stop at 0.
    if (victory > 0) {
        victory -= 1;
        MirrorVictory();
    }
    if (fxIrqIndex >= fxDefer) {
        FlushFxPending();
    }
    fxIrqIndex += 1;
    for (FxVoice& voice : fxVoice) {
        AdvanceFxVoice(voice);
    }
    // $15B8, then count_visit and the stick store at $16BD.
    noiseLo = (noiseLo + 1) & 0xFF;
    noiseMem[0x16] = static_cast<uint8_t>(noiseLo);
    if (noiseMem[0x104] != 0 && (noiseMem[0x105] & 0x80) == 0) {
        noiseMem[0x87] = static_cast<uint8_t>(noiseMem[0x87] + 1);
        if (noiseMem[0x87] == 0 && noiseMem[0x88] < 0x80) {
            noiseMem[0x88] = static_cast<uint8_t>(noiseMem[0x88] + 1);
        }
    }
    // $1628. A wrap increments $82 while it is still positive, then always
    // increments $80. $173D clears $82 afterwards unless both sticks OR to
    // $0F and both buttons are up. $9C stays 0 until Yamo wakes, so the
    // clear holds $82 at 0 through that frame. The button bit is 0 when held.
    noiseMem[0x7F] = static_cast<uint8_t>(noiseMem[0x7F] + 1);
    if (noiseMem[0x7F] == 0) {
        if ((noiseMem[0x82] & 0x80) == 0) {
            noiseMem[0x82] = static_cast<uint8_t>(noiseMem[0x82] + 1);
        }
        noiseMem[0x80] = static_cast<uint8_t>(noiseMem[0x80] + 1);
        if (noiseMem[0x80] == 0) {
            noiseMem[0x81] = static_cast<uint8_t>(noiseMem[0x81] + 1);
        }
    }
    noiseMem[0x98] = static_cast<uint8_t>(stick);
    noiseMem[0x9B] = static_cast<uint8_t>(fire ? 0 : 1);
    MirrorOpponentStick();
    if (noiseMem[0x104] == 0 || (noiseMem[0x105] & 0x80) == 0) {
        const bool idle = (noiseMem[0x98] | noiseMem[0x99]) == 0x0F && (noiseMem[0x9B] & noiseMem[0x9C]) != 0;
        if (noiseMem[0x104] == 0 || !idle) {
            noiseMem[0x82] = 0;
        }
    }
    OpponentIrq();
    noiseMem[0xB9] = static_cast<uint8_t>(bruceX);
    if (yamoOn) {
        noiseMem[0xBA] = static_cast<uint8_t>(yamoX);
    }
    if (ninjaOn) {
        noiseMem[0xBB] = static_cast<uint8_t>(ninjaX);
    }
}

// $28 is the falls count and $2A-$3D the lamps left in each room. The port
// keeps them in g.lives and the room table, so copy them where noise_byte
// can read them.
void MirrorWorkBytes() {
    noiseMem[0x28] = static_cast<uint8_t>(g.lives & 0xFF);
    // $29 is the room number. Room 18's sparks read it.
    if (g.roomId >= 0 && g.roomId < kRoomCount) {
        noiseMem[0x29] = static_cast<uint8_t>(g.roomId);
    }
    for (int room = 0; room < kRoomCount; ++room) {
        noiseMem[0x2A + room] = static_cast<uint8_t>(LampsLeft(room));
    }
    // $15EC. Every interrupt turns the charset in $F2 into the high byte of
    // a pointer: $A0, $A8, or $B0 for the room charsets.
    static const uint8_t kCharsetHigh[3] = {0xA0, 0xA8, 0xB0};
    noiseMem[0x7C] = g.charsetId >= 0 && g.charsetId < 3 ? kCharsetHigh[g.charsetId] : 0xB8;
    // $0AAD. enter_room stores the charset as $38, $3A, or $3C in $F2.
    if (g.charsetId >= 0 && g.charsetId < 3) {
        noiseMem[0xF2] = static_cast<uint8_t>(0x38 + 2 * g.charsetId);
    }
    if (flashCharset >= 0) {
        noiseMem[0xF2] = static_cast<uint8_t>(flashCharset);
        noiseMem[0x7C] = static_cast<uint8_t>(0xA0 + (flashCharset - 0x38) * 4);
    }
    // $1653. The interrupt stores $FE while $82 is positive, which it is in play.
    noiseMem[0x84] = 0xFE;
    // $19EC. Each frame of play keeps only the pause bit of $0105 and counts
    // its lockout down. A frame that runs is not paused, so the
    // clear_work_ram 1 becomes 0 on the first one. The demo skips it.
    if (noiseMem[0x104] != 0) {
        noiseMem[0x105] = 0;
        // $1B2B. in_game_key stores 1 every frame of play.
        noiseMem[0x10E] = 1;
    }
    // $0B9D and $0BA7. wake_actor gives Bruce $59A8 and $59AB for actor 0,
    // 4 and 5, the same table in every room.
    noiseMem[0xEC] = 4;
    noiseMem[0xEF] = 5;
    // $09C9. enter_room keeps the actors' sprite mask in $47, Bruce's two
    // sprites, 3 in every snapshot of play.
    noiseMem[0x47] = 3;
    // $95 bit 0 is Bruce in the room, set in every snapshot of play.
    noiseMem[0x95] = 1;
}

void PrepareNoise() {
    MirrorWorkBytes();
    noiseMem[0x48] = 3;
    noiseMem[0x7B] = static_cast<uint8_t>(hookGate);
}

std::vector<std::pair<int, int>> snapshotPokes;

void AddSnapshotPoke(int addr, int value) {
    snapshotPokes.emplace_back(addr & 0xFFFF, value & 0xFF);
}

void ApplySnapshotPokes(uint8_t* ram, size_t size) {
    for (const auto& poke : snapshotPokes) {
        if (static_cast<size_t>(poke.first) < size) {
            ram[poke.first] = static_cast<uint8_t>(poke.second);
        }
    }
}

int SnapshotPokeValue(int addr, int fallback) {
    int value = fallback;
    for (const auto& poke : snapshotPokes) {
        if (poke.first == (addr & 0xFFFF)) {
            value = poke.second;
        }
    }
    return value;
}

bool PlantSnapshotNoise(const wchar_t* path, bool replayWait, int maxReplay) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    in.seekg(0, std::ios::end);
    const auto length = in.tellg();
    if (length < 0x200) {
        return false;
    }
    in.seekg(0, std::ios::beg);
    std::vector<uint8_t> file(static_cast<size_t>(length));
    in.read(reinterpret_cast<char*>(file.data()), length);
    if (!in) {
        return false;
    }
    const uint8_t tag[] = {'C', '6', '4', 'M', 'E', 'M'};
    size_t mark = file.size();
    for (size_t i = 0; i + 6 <= file.size(); ++i) {
        if (std::equal(tag, tag + 6, file.begin() + static_cast<std::ptrdiff_t>(i))) {
            mark = i;
            break;
        }
    }
    if (mark == file.size()) {
        return false;
    }
    const size_t base = mark + 26;
    if (base + 0x200 > file.size()) {
        return false;
    }
    ApplySnapshotPokes(file.data() + base, file.size() - base);
    std::copy(file.begin() + static_cast<std::ptrdiff_t>(base),
              file.begin() + static_cast<std::ptrdiff_t>(base + 0x200), noiseMem);
    noiseLo = noiseMem[0x16];
    noiseHi = noiseMem[0x17];
    // $43BD is the player-word timer. It sits far above the zero-page copy.
    // timed_caption leaves Y at $2F on the frame it reloads, and flicker_lamps
    // reads noise with that Y. A zero here made every lamp read use $40.
    int caption = 0x10;
    if (base + 0x43BE <= file.size()) {
        caption = file[base + 0x43BD];
    }
    SetCaptionTimer(caption);
    // Effect slots $EB00, $EF70, and $F070: id, script index, and delay,
    // with the priorities at $2581-$2583. play_sound picks a free slot
    // first, so a voice still busy in the snapshot sends the next effect to
    // another pointer. Room 12's snapshot has voices 1 and 2 running.
    static const int kSlotAt[3] = {0xEB00, 0xEF70, 0xF070};
    for (int i = 0; i < 3; ++i) {
        FxVoice& voice = fxVoice[i];
        const size_t at = base + static_cast<size_t>(kSlotAt[i]);
        if (at + 3 > file.size() || base + 0x2584 > file.size()) {
            continue;
        }
        voice.slot = file[at];
        voice.index = file[at + 1];
        voice.delay = file[at + 2];
        voice.priority = file[base + 0x2581 + static_cast<size_t>(i)];
        const int ptr = noiseMem[voice.zp] | (noiseMem[voice.zp + 1] << 8);
        voice.origin = ptr - 0xEC31;
    }
    // The snapshot is inside the wait. $48 is how many rasters are left
    // before the next $1BC2, and each one stores the unforced stick.
    const bool yamoOn = (noiseMem[0x96] & 1) != 0;
    const bool ninjaOn = (noiseMem[0x97] & 1) != 0;
    const int waiting = noiseMem[0x48];
    if (replayWait) {
        for (int i = 0; i < waiting && i < maxReplay; ++i) {
            NoiseIrq(0x0F, noiseMem[0x9E], noiseMem[0x9F], noiseMem[0xA0], yamoOn, ninjaOn);
        }
    }
    return true;
}

bool PlantRoom00Noise() {
    return PlantSnapshotNoise(LR"(referencematerial\emulatorsnapshots\room00.vsf)");
}

void AdvanceIrq() {
    // frame waits out three screens. count_visit and the landing refill
    // both run from that interrupt, including on a held pose. finish_exit
    // jumped to the next frame without that wait, so none of it runs.
    if (skipVisit) {
        skipVisit = false;
        return;
    }
    for (int i = 0; i < 3; ++i) {
        if (stompGate == 0) {
            stompLeft[0] = 2;
            stompLeft[1] = 2;
            stompLeft[2] = 2;
        }
        stompGate = (stompGate - 1) & 0xFF;
        // $1614. The demo does not advance the visit clock.
        if (DemoMode()) {
            continue;
        }
        play87 = (play87 + 1) & 0xFF;
        if (play87 == 0 && play88 < 0x80) {
            play88 += 1;
        }
    }
}

int HitRecoverTimer(bool bruce) {
    // $10D0. $88 >= $20 sets V. $88 >= $19 sets C and leaves V clear.
    const bool longVisit = play88 >= 0x20;
    const bool middle = play88 >= 0x19;
    if (bruce) {
        // $2B83 overwrites the $18. Long is $0A, middle is 8, short is 3.
        if (longVisit) {
            return 0x0A;
        }
        if (middle) {
            return 0x08;
        }
        return 3;
    }
    // $2B6B. Middle stores $0A. Long, or $40 on a short visit, stores 2 at
    // $2B7F, but nothing branches past Bruce's test at $2B83, so that test
    // runs as well and its value is the one kept: $0A on a long visit, 3 on
    // a short one. After a finished game, room 0's Yamo landed a kick on a
    // short visit and rested on timer 3.
    if (longVisit) {
        return 0x0A;
    }
    if (middle) {
        return 0x0A;
    }
    if (difficulty != 0) {
        return 3;
    }
    return 0x18;
}

int KickRecoverTimer() {
    const bool longVisit = play88 >= 0x20;
    const bool middle = play88 >= 0x19;
    if (longVisit) {
        return 1;
    }
    if (middle) {
        return 3;
    }
    if (difficulty != 0) {
        return 1;
    }
    return 0x18;
}

int StandTimer(bool bruce) {
    const bool longVisit = play88 >= 0x20;
    const bool middle = play88 >= 0x19;
    if (bruce) {
        return (longVisit || middle) ? 12 : 3;
    }
    if (longVisit) {
        return 1;
    }
    if (middle) {
        return 3;
    }
    if (difficulty != 0) {
        return 1;
    }
    return 6;
}

bool HoldNinjaWake(int index) {
    if (difficulty != 0 || gHumanOpponent || play88 >= 0x19) {
        return false;
    }
    const int nb = NoiseByte(index);
    return nb >= 0x19;
}

int WakeDelay(int count) {
    if (play88 >= 0x20) {
        return 3;
    }
    if (play88 >= 0x19) {
        return (count & 0xFF) >> 1;
    }
    if (difficulty != 0) {
        return 3;
    }
    return count & 0xFF;
}

int OpenWake(int count, bool humanYamo) {
    if (difficulty != 0) {
        count = 3;
    }
    if (humanYamo) {
        count = 8;
    }
    return count & 0xFF;
}

bool TakeStomp(int actor) {
    if (actor < 0 || actor > 2 || stompLeft[actor] <= 0) {
        return false;
    }
    stompLeft[actor] -= 1;
    return true;
}

int Room19Stick() {
    return play88 < 2 ? 0x0E : 0x0F;
}

bool snapshotFrame = false;
int snapshotIrqs = -1;

void HoldRoomHook(int gate, int irqs) {
    hookGate = gate;
    snapshotFrame = true;
    if (irqs < 0) {
        irqs = 0;
    }
    if (irqs > 3) {
        irqs = 3;
    }
    snapshotIrqs = irqs;
}

int TakeSnapshotIrqs() {
    const int n = snapshotIrqs;
    snapshotIrqs = -1;
    return n;
}

// The door's SEI left $FB pending, so irq_service runs at the CLI, after
// enter_room has cleared $87, and counts the new room's first tick.
bool exitCliIrq = false;

void ArmExitClock() {
    wipeVisit = true;
}

bool ConsumeExitClock() {
    if (!wipeVisit) {
        return false;
    }
    wipeVisit = false;
    noiseMem[0x87] = 0;
    noiseMem[0x88] = 0;
    play87 = 0;
    play88 = 0;
    // Room 5's second snapshot left through a door with $FB pending, and
    // the next frame's $87 was 1 in VICE.
    if (exitCliIrq && noiseMem[0x104] != 0 && (noiseMem[0x105] & 0x80) == 0) {
        noiseMem[0x87] = 1;
        play87 = 1;
    }
    exitCliIrq = false;
    skipVisit = true;
    return true;
}

void NoteExitIrqs(int count, bool cliIrq) {
    exitCliIrq = cliIrq;
    if (count < 0) {
        count = 0;
    }
    if (count > 3) {
        count = 3;
    }
    snapshotIrqs = count;
    ArmExitClock();
}

void NoteDeathIrqs(int count) {
    // Twelve deaths in VICE: the death frame's $FB interrupts up to
    // lose_life, two more after init_hardware before enter_room_at, and
    // one at or after the CLI once enter_room has cleared $87.
    exitCliIrq = true;
    snapshotIrqs = count < 0 ? 0 : count;
    ArmExitClock();
}

bool SnapshotSkipsLamps() {
    // A snapshot taken anywhere but the wait is past timed_caption and
    // flicker_lamps, including one in refresh_top's score convert.
    return snapshotFrame;
}

bool SnapshotFrameOpen() {
    return snapshotFrame;
}

void EndSnapshotFrame() {
    snapshotFrame = false;
}

void PlantSurface(int wait, int step, int down, int count, int slot) {
    surfaceWait = static_cast<uint8_t>(wait);
    surfaceStep = static_cast<uint8_t>(step);
    surfaceDown = static_cast<uint8_t>(down);
    surfaceCount = static_cast<uint8_t>(count);
    surfaceSlot = static_cast<uint8_t>(slot);
    CopySurfaceGlyphs();
}

void PlantHazard(int slide, int slideAt, int beam, int beam2) {
    slideCol = static_cast<uint8_t>(slide);
    slideRow = static_cast<uint8_t>(slideAt);
    tim77 = static_cast<int8_t>(beam);
    tim78 = static_cast<int8_t>(beam2);
}

void PlantMovers(const uint8_t* ram) {
    for (int i = 0; i < 9; ++i) {
        const uint8_t col = ram[0x0119 + i];
        if (mover[i].active != 0 && col != mover[i].col) {
            const int row = mover[i].row;
            PaintSlide(row, mover[i].col, col, row == 5 || row == 0x0A);
        }
        mover[i].active = ram[0x010F + i];
        mover[i].col = col;
        mover[i].row = ram[0x0123 + i];
        mover[i].low = ram[0x0137 + i];
        mover[i].high = ram[0x0141 + i];
    }
}

void PlantGate(int gate) {
    hookGate = gate;
}

void PlantTreasure(int low, int high, int clockLo, int clockHi) {
    victory = (high << 8) | (low & 0xFF);
    play87 = clockLo & 0xFF;
    play88 = clockHi & 0xFF;
}

void PlantCrumble(const uint8_t* ram) {
    for (int i = 0; i < 3; ++i) {
        crumb[i].n = ram[0x4FDE + i];
        crumb[i].col = ram[0x4FE1 + i];
        crumb[i].row = ram[0x4FE4 + i];
    }
}

void PlantBandBonus(const uint8_t* ram) {
    // A band already paid is 0. Room 15's snapshot had all three of player
    // 1's spent, and its door into room 13 paid nothing.
    for (int i = 0; i < 8; ++i) {
        bandBonus[i] = ram[0x14B + i];
    }
}

void PlantHooks(const uint8_t* ram) {
    t97 = ram[0x4E97];
    t98 = ram[0x4E98];
    t99 = ram[0x4E99];
    t9A = ram[0x4E9A];
    t9B = ram[0x4E9B];
    col71 = static_cast<int8_t>(ram[0x71]);
    col72 = static_cast<int8_t>(ram[0x72]);
    col73 = static_cast<int8_t>(ram[0x73]);
    row74 = ram[0x74];
    row75 = ram[0x75];
    row76 = ram[0x76];
    tim77 = static_cast<int8_t>(ram[0x77]);
    tim78 = static_cast<int8_t>(ram[0x78]);
    tim79 = static_cast<int8_t>(ram[0x79]);
}

void PlantSlideTiles(const uint8_t* ram) {
    if (g.room.size() < 1000) {
        return;
    }
    auto slideTile = [](int tile) {
        tile &= 0x7F;
        return tile == 0x64 || tile == 0x65 || tile == 0x66 || tile == 0x67;
    };
    for (int i = 0; i < 1000; ++i) {
        const int have = g.room[static_cast<size_t>(i)];
        const int live = ram[0x8C00 + i];
        if (slideTile(have) && slideTile(live) && (have & 0x7F) != (live & 0x7F)) {
            g.room[static_cast<size_t>(i)] = static_cast<uint8_t>(live & 0x7F);
        }
    }
}

int HookTiles() {
    return hookTiles;
}

void RunRoomHook() {
    // Count only this hook. Lamp flicker has already stored its own cells.
    hookTiles = 0;
    relocated = false;
    switch (g.roomId) {
    case 0: Frame0(); break;
    case 1: Frame1(); break;
    case 2: Frame2(); break;
    case 3: Frame3(); break;
    case 4: Frame4(); break;
    case 5: Frame5(); break;
    case 6: Frame6(); break;
    case 7: Frame7(); break;
    case 8: Frame8(); break;
    case 9: Frame9(); break;
    case 10: Frame10(); break;
    case 11: Frame11(); break;
    case 12: Frame12(); break;
    case 13: Frame13(); break;
    case 14: Frame14(); break;
    case 15: Frame15(); break;
    case 16: Frame16(); break;
    case 17: Frame17(); break;
    case 18: Frame18(); break;
    case 19: Frame19(); break;
    default: break;
    }
    // Tick copies $71-$79 to the noise memory after try_yamo and try_ninja:
    // those run before the hook in the original, and read last frame's bytes.
}

bool AdvanceRoom() {
    // A snapshot taken past the wait, in the overlap or in refresh_top, has
    // already run this frame's hook. Frame 1 is the rest of that frame.
    if (snapshotFrame) {
        return false;
    }
    // $1BFE flips $7B just before the hook, and the hook's reads see the new
    // value. try_yamo and try_ninja ran before the flip in the original but
    // run after the hook here, so they get the old value back, and
    // MirrorRoomHookBytes stores the new one after them.
    const uint8_t before = noiseMem[0x7B];
    if (hookGate == 0) {
        hookGate = 1;
    } else {
        hookGate -= 1;
    }
    noiseMem[0x7B] = static_cast<uint8_t>(hookGate);
    RunRoomHook();
    noiseMem[0x7B] = before;
    return relocated;
}

void EnterFrameHook() {
    // The frame that took the exit already flipped $7B. enter_room jumps
    // to the hook with that value still in place.
    // Y is what L_336E left: four times the records in the room's list at
    // $4CE2, as no enter hook touches Y. A hook's noise read takes that.
    static const int kEntryY[kRoomCount] = {
        24, 24, 40, 8, 8, 40, 32, 52, 16, 20, 12, 12, 12, 4, 16, 24, 8, 8, 4, 4,
    };
    entryNoiseY = g.roomId >= 0 && g.roomId < kRoomCount ? kEntryY[g.roomId] : -1;
    RunRoomHook();
    entryNoiseY = -1;
}

void BeginRoomEffects() {
    // $0A34. Every room starts the visit clock over. test_visit then
    // reports a short visit until this stay runs long enough. The same
    // bytes are what noise_byte reads, so the copy has to restart too.
    play87 = 0;
    play88 = 0;
    noiseMem[0x87] = 0;
    noiseMem[0x88] = 0;
    // $0A38 and $0A3C. Entering any room starts the scroll upward and
    // restarts the delay slot. The step and the countdown keep running,
    // so a long stay in the room is what reverses it.
    surfaceDown = 0;
    surfaceSlot = 7;
    t97 = t98 = t99 = t9A = t9B = 0;
    flashCharset = -1;
    irqFlashCharset = -1;
    // $0A73. The three crumble slots stop. A flame still counting in the
    // room just left would otherwise print its nozzle over this room's
    // tiles. Room 14's flames at columns 14 and 25 did that to room 12.
    for (int i = 0; i < 3; ++i) {
        crumb[i].n = 0;
    }
    switch (g.roomId) {
    case 1: Enter1(); break;
    case 3: Enter3(); break;
    case 4: Enter4(); break;
    case 5: Enter5(); break;
    case 7: Enter7(); break;
    case 8: Enter8(); break;
    case 9: Enter9(); break;
    case 12: Enter12(); break;
    case 13: Enter13(); break;
    case 14: Enter14(); break;
    case 15: Enter15(); break;
    case 16: Enter16(); break;
    case 17: Enter17(); break;
    case 18: Enter18(); break;
    case 19: Enter19(); break;
    default: break;
    }
    RestoreSurfaceGlyphs();
}

void ArmCrumble(int col, int row) {
    StartCrumble(col, row);
}

void TouchRoomTile(int tile, int col, int row, bool prize, bool ladder) {
    // $310C. Timer $10 and the pose hold cleared. $AD, the gap before the
    // next stick step, is not cleared.
    if (tile == 0x62 && ladder && g.action != kZap) {
        g.action = kCarry;
        g.actionTimer = 0x10;
        g.hold = 0;
        // $3125. catch_surface clears $AA as well.
        NoisePoke(0xAA, 0);
    }
    if ((tile == 0x2D || tile == 0x2E) && g.roomId == 16 && g.y + 21 >= 0xA0) {
        extraLives[gBrucePlayer & 1] -= 1;
        // $2FE5. The count is not checked. INC $28 wraps as one byte.
        GrantLife();
        // $2FEA. The ying-yang, not a score extra life.
        PlayEffect(0x8E);
        PrintString(0x56, 0x0A, 0x24);
        PrintString(0x56, 0x0B, 0x24);
    }
    if (!prize) {
        return;
    }
    const bool late = g.roomId >= 10 && tile == 0x66;
    const bool span = tile >= 0x54 && tile <= 0x5A && tile != 0x57;
    const bool hot = tile == 0x0F || tile == 0x40 || tile == 0x64 || late || span ||
        (tile >= 0x71 && tile <= 0x7C);
    if (hot && g.roomId != 18) {
        // $3057. Room 18's spark calls Shock and does not play this.
        PlayEffect(0x8C);
        Shock();
    }
    if (tile == 0x60) {
        StartCrumble(col, row);
    }
}

int SurfaceShove() {
    if (surfaceWait != 1) {
        return 0;
    }
    return surfaceDown == 0 ? -1 : 1;
}

void RestartSurfaceClock() {
    // init_hardware writes 1 to both. The hook enter_room jumps to then
    // sees $60 == 1, copies the floor, and leaves $66 at 0. $64 keeps
    // the step it already had.
    surfaceWait = 1;
    surfaceCount = 1;
}

void PlantBolts(const uint8_t* ram) {
    for (int i = 0; i < 2; ++i) {
        boltPhase[i] = ram[0x432E + i];
        boltDelay[i] = ram[0x4330 + i];
        boltX[i] = ram[0x4332 + i];
        boltY[i] = ram[0x4334 + i];
        // $D015 stays set through the two-frame pause after Y passes $E0.
        // The variable Y is then past $E0, while the sprite is still at the
        // last position that was copied. A delay of 1 or 2 is that pause.
        const bool paused = boltPhase[i] == 0 && (boltDelay[i] == 1 || boltDelay[i] == 2);
        boltOn[i] = boltPhase[i] != 0 || paused;
        const int src = i == 0 ? 0x8340 : 0x8380;
        for (int b = 0; b < 63; ++b) {
            boltShape[i][b] = ram[src + b];
        }
    }
}

void ReadBolts(int out[8]) {
    out[0] = boltPhase[0];
    out[1] = boltDelay[0];
    out[2] = boltX[0];
    out[3] = boltY[0];
    out[4] = boltPhase[1];
    out[5] = boltDelay[1];
    out[6] = boltX[1];
    out[7] = boltY[1];
}

bool BossSparkAt(int index, int& x, int& y, const uint8_t*& shape) {
    if (g.roomId != 18 || index < 0 || index > 1 || !boltOn[index]) {
        return false;
    }
    x = static_cast<int>(boltX[index]) * 2 - 24;
    y = static_cast<int>(boltY[index]) - 21;
    shape = boltShape[index];
    return true;
}
