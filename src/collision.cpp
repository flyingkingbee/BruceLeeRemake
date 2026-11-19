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

#include "collision.h"

#include "bruce.h"
#include "fighter.h"
#include "game.h"

// Probe() records the last nonzero AND. scan_row ($5388, $53A2, $53BC)
// stores that byte at $4E, and the next frame's noise_byte can read it.
static bool noteOverlap = false;
static int lastOverlap = -1;
static int overlapAnds = 0;

// The charset bank and split list of the room EnterRoom left. The bank's
// bytes are whatever that room last showed, scrolled floor included.
static std::vector<uint8_t> leftCharset;
static int leftCharsetId = -1;
static uint8_t leftSplits[4] = {0xFD, 0xFD, 0xFD, 0xFD};
// Set by a door for the next overlap, and live only inside that overlap.
static bool leftPending = false;
static bool leftActive = false;

void KeepLeftCharset() {
    leftCharset = g.charset;
    leftCharsetId = g.charsetId;
    for (int i = 0; i < 4; ++i) {
        leftSplits[i] = g.splits[i];
    }
    leftPending = false;
}

void UseLeftCharsetForNextOverlap() {
    leftPending = !leftCharset.empty();
}

void BeginOverlapFrame() {
    leftActive = leftPending;
    leftPending = false;
}

void EndOverlapFrame() {
    leftActive = false;
}

// Raster the current frame began on. frame waits for three $FB interrupts
// ($48), and irq_service ends about 18 rasters after $FB, so a frame that
// waited begins near raster 269. A frame whose work ran past its third
// interrupt does not wait, and the next one begins where it stopped. Two
// fighters often do that, and the start then drifts from frame to frame:
// room 16's door into room 14 began its frame at raster 1.
static int frameStart = 269;
static int scanElapsed = -1;
static int scanFighters = 0;

// Rasters from the frame start to the first $FB, then every 312.
static int FirstIrq() {
    return frameStart < 0xFB ? 0xFB - frameStart : 0xFB + 312 - frameStart;
}

// How many $FB interrupts fall in (from, to], counted from the frame start.
static int IrqsBetween(int from, int to) {
    int n = 0;
    for (int at = FirstIrq(); at <= to; at += 312) {
        if (at > from) {
            n += 1;
        }
    }
    return n;
}

// Rasters from the start of the frame to Bruce's cell scan, the last one in
// scan_specials. overlap_actors has scanned every actor that is on by then,
// and the shift loops of its sprite buffer cost the most. A least-squares
// fit over 4128 VICE frames in rooms 0, 1, 2, 9, 10, 12, 14, and 16: 144,
// plus 23, 53, or 37 when Bruce's (xpos - $0C) & 3 is 1, 2, or 3, plus 156,
// 171, 212, or 184 for each fighter that is on, by that fighter's fine
// shift, plus 47 for each $FB interrupt that ran before the scan. The
// median miss was 12 rasters and nine frames in ten were within 30. The
// port does not count cycles, so this estimates the original's raster.
static int ScanElapsed(int bruceXpos, const int* fighterXpos, int fighters) {
    static const int kBruceFine[4] = {0, 23, 53, 37};
    static const int kFighterFine[4] = {156, 171, 212, 184};
    int work = 144 + kBruceFine[(bruceXpos - 0x0C) & 3];
    for (int i = 0; i < fighters; ++i) {
        work += kFighterFine[(fighterXpos[i] - 0x0C) & 3];
    }
    int elapsed = work;
    for (int pass = 0; pass < 4; ++pass) {
        const int next = work + 47 * IrqsBetween(0, elapsed);
        if (next == elapsed) {
            break;
        }
        elapsed = next;
    }
    return elapsed;
}

int FrameStartRaster() {
    return frameStart;
}

void ResetFrameClock() {
    frameStart = 269;
    scanElapsed = -1;
}

int IrqsBeforeStep(int bruceXpos, const int* fighterXpos, int fighters) {
    scanElapsed = ScanElapsed(bruceXpos, fighterXpos, fighters);
    scanFighters = fighters;
    // Bruce's step is the last one in step_actors. In VICE his footstep,
    // effect $80, reached play_sound a median 91 rasters after his scan with
    // no fighter on, 117 with one, and 137 with two.
    const int step = scanElapsed + 91 + 23 * fighters;
    int irqs = 0;
    for (int at = FirstIrq(); at <= step && irqs < 3; at += 312) {
        irqs += 1;
    }
    return irqs;
}

void EndFrameClock() {
    if (scanElapsed == -2) {
        // TimeDoor has already placed the next start after the CLI.
        scanElapsed = -1;
        return;
    }
    if (scanElapsed < 0) {
        // The frame did not reach the overlap. Assume it waited.
        frameStart = 269;
        return;
    }
    // From Bruce's scan to check_bruce_down: 128, plus 61 for each fighter
    // on, plus 33 for each $FB interrupt on the way, over 1908 VICE frames.
    // The median miss was 10 rasters.
    const int work = 128 + 61 * scanFighters;
    int end = scanElapsed + work;
    for (int pass = 0; pass < 4; ++pass) {
        const int next = scanElapsed + work + 33 * IrqsBetween(scanElapsed, end);
        if (next == end) {
            break;
        }
        end = next;
    }
    end += 5;
    const int third = FirstIrq() + 624;
    frameStart = end > third + 18 ? (frameStart + end) % 312 : 269;
    scanElapsed = -1;
}

DoorTiming TimeDoor(int bruceXpos, const int* fighterXpos, int fighters) {
    const int elapsed = ScanElapsed(bruceXpos, fighterXpos, fighters);
    // The door code from the scan to the SEI at $2FC5 took 58 rasters on
    // room 10's door into room 3 and 78 on room 3's floor into room 10.
    // Those two SEIs were at rasters 46 and 167; this sum puts them at 32
    // and 168 from a start at 269. Room 16's door into room 14 began at
    // raster 0 and took its SEI at 102.
    const int sei = elapsed + 65;
    DoorTiming timing;
    // irq_service runs from the $FB interrupt and is the only one that
    // advances $16 and copies $F2 into $7C.
    for (int at = FirstIrq(); at <= sei; at += 312) {
        timing.irqs += 1;
    }
    // The line armed when the SEI ran is the one pending at the CLI ($2FD2).
    // raster_irq at $FB arms raster_open at $40. raster_open arms the first
    // split of the list raster_irq copied to $47F5, still the old room's,
    // and the last split arms $FB. $FD ends the list. A pending $FB runs
    // irq_service at the CLI: one more count, and $7C is the new room's.
    // Anything else runs first and reaches $FB only after the jump to frame
    // has passed overlap_actors. Forced doors in VICE at rasters 0-311
    // agreed for 10 to 3, 3 to 10, and 17 to 18.
    const int raster = (frameStart + sei) % 312;
    bool fbPending = raster >= 0x40 && raster < 0xFB;
    for (int i = 0; i < 4 && fbPending; ++i) {
        const int split = leftSplits[i];
        if (split == 0xFD) {
            break;
        }
        if (raster < split) {
            fbPending = false;
        }
    }
    if (fbPending) {
        timing.irqs += 1;
        timing.cliIrq = true;
    }
    if (timing.irqs > 3) {
        timing.irqs = 3;
    }
    // $0A9B gives each bank its own $D018 value, so a door between rooms of
    // the same bank leaves $7C right either way.
    timing.oldCharset = !fbPending && leftCharsetId >= 0 && leftCharsetId != g.charsetId;
    // enter_room and blit_sprites ran under the SEI. The CLI came 100 to 132
    // rasters after it on the natural doors, and frame begins right after.
    frameStart = (raster + 130) % 312;
    scanElapsed = -2;
    return timing;
}

// Fold one pose into `hit`. overlap_actors copies the even library's
// expansion. build_sprites ($512F) has already OR'd library N+1 into that
// buffer, at the same origin. place_sprites may draw the second library
// 16 pixels to the left. That shift is the picture and the sprite-hit
// register. It is not this scan. The ninja's odd libraries have no
// expansion page, so his scan is the even library alone. Each character
// column under the image is ANDed with that column's glyph byte. The
// two nibbles of the AND are what the original scan at $537E records.
// $5592 rolls $4F3F in first, so that counter is bit 3 and $4F3C is bit 0.
// Bit 0 is nibbles 1, 4, 5, 6, 9, and 13, and nibble 7. The middle column's
// ladder slot for nibble 7, $4F15, is not in that list, so a property other
// than 0 leaves bit 0 clear there. The roof dots are nibble 5.
// Bit 3 is nibbles 3, 7, and 11-15 on property 0: $1CC7 pushes the move out.
// On any other property those nibbles are bit 2, a climb. The ladder rails
// and the black line of a property-6 roof are that case, so a climb passes
// through them and up or down rides them instead of jumping.
// Bit 1 is nibbles 2, 6, 8, 9, 10, and also 11 and 14 on either property.
// spawn_ninja writes $82 over $4F50 before overlap_actors. choose_pose
// does not replace it until step_actors, which is after the scan. The
// bytes are the built page at $C3C0: library $82 with $83 OR'd in.
// Column 2 of that page is empty, so the 16-pixel scan is the whole mask.
constexpr uint8_t kNinjaSpawnRows[kSpriteRows * kSpriteRowBytes] = {
    0x00, 0x03, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0xFF, 0x00, 0x00, 0x03, 0xFF, 0x00, 0x00,
    0x03, 0xFF, 0x00, 0x00, 0x03, 0xFF, 0x00, 0x00, 0x03, 0xFF, 0x00, 0x00, 0x03, 0xFF, 0x00, 0x00,
    0x03, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x0F, 0xFF, 0x00, 0x00, 0x3F, 0xFF, 0x00, 0x00,
    0x3F, 0xFF, 0x00, 0x00, 0xF3, 0xFF, 0x00, 0x00, 0xC3, 0xFF, 0x00, 0x00, 0xC3, 0xFF, 0x00, 0x00,
    0x03, 0xFF, 0x00, 0x00, 0x03, 0x3C, 0x00, 0x00, 0x03, 0x30, 0x00, 0x00, 0x33, 0xF0, 0x00, 0x00,
    0x0F, 0xC0, 0x00, 0x00,
};

// The scan's copy of PoseBytes(pose, plane). The drawn pictures stop where
// copy_sprite_image stops. overlap_actors scans expand_library's page, which
// has one more row for a mode-1 library.
static const uint8_t* ScanPlane(int pose, int plane) {
    const size_t offset = static_cast<size_t>(pose * 2 + plane) * kFrameBytes;
    return ScanFrames(PoseBytes(pose, plane) - offset) + offset;
}

static void AddPose(Contact& hit, int pose, int sx, int sy, int row0, int row1, const uint8_t* pixels = nullptr) {
    // (xpos - $0C) is one byte. $1B is its low two bits and the column is
    // the rest. At xpos $0B that byte is $FF, so the window is columns
    // $3F and $40, which are the next screen row. The third column is an
    // empty glyph once its cursor has left $28. A wall there is not the
    // wall under his picture.
    const int xpos = (sx + 24) / 2;
    const int raw = (xpos - 0x0C) & 0xFF;
    const int fine = raw & 3;
    const int col0 = raw >> 2;
    for (int y = row0; y < row1; ++y) {
        const int py = sy + y;
        uint8_t cols[96] = {};
        bool used[96] = {};
        // $4F4E is the even library. Its buffer already holds library N+1,
        // except for the ninja. Punch stores that even library as plane 1.
        const uint8_t* body = nullptr;
        const uint8_t* detail = nullptr;
        const uint8_t* only = nullptr;
        bool both = false;
        int sole = 0;
        if (pixels == nullptr) {
            body = ScanPlane(pose, 0);
            detail = ScanPlane(pose, 1);
            both = ViewComposite();
            sole = (pose == kPosePunchLeft || pose == kPosePunchRight) ? 1 : 0;
            only = both ? nullptr : ScanPlane(pose, sole);
        }
        // Mode 1's expand loads the second source byte's high nibble into A
        // and calls L_51FF, which begins with LDA #0 and shifts $1F. That
        // nibble is discarded, so the third collision column is stored as
        // zero. The built page for library $40 confirms it. Those columns
        // in the pose file are the second source byte, which copy_sprite_image
        // does put in the VIC sprite. scan_row's $CB20 test therefore sees
        // nothing, and a duck at xpos $A0 reads ground there. The wall scan
        // stays on the first two columns.
        for (int x = 0; x < kHardwareColumns; ++x) {
            const int index = y * kSpriteRowBytes + x / 8;
            const uint8_t mask = static_cast<uint8_t>(0x80 >> (x & 7));
            const bool on = pixels != nullptr ? (pixels[index] & mask) != 0
                            : both ? ((body[index] & mask) != 0 || (detail[index] & mask) != 0)
                                   : (only[index] & mask) != 0;
            if (!on) {
                continue;
            }
            // $1B of 0, 1, or 2 shifts the row right by that many pairs of
            // bits. $1B of 3 inserts a blank column and shifts left by two,
            // which lands six pixels into the window. Bits past the third
            // column are not tested.
            const int wp = x + fine * 2;
            if (wp >= 24 || py < 0 || py >= kHeight) {
                continue;
            }
            const int memCol = col0 + wp / 8;
            // $535A stores 0 when the third column's cursor has left $28.
            if (wp >= 16 && memCol >= 40) {
                continue;
            }
            if (memCol < 0 || memCol >= 96) {
                continue;
            }
            cols[memCol] |= static_cast<uint8_t>(0x80 >> (wp & 7));
            used[memCol] = true;
        }
        if (py < 0 || py >= kHeight) {
            continue;
        }
        const int rowByte = py & 7;
        for (int col = 0; col < 96; ++col) {
            if (!used[col]) {
                continue;
            }
            const int cell = (py / 8) * 40 + col;
            if (cell < 0 || cell >= static_cast<int>(g.room.size()) ||
                cell >= static_cast<int>(g.color.size())) {
                continue;
            }
            const int glyphRow = cell / 40;
            const int half = (glyphRow & 1) == 0 ? 128 : 0;
            const uint8_t tile = g.room[static_cast<size_t>(cell)];
            if (tile == 0xDC) {
                continue;
            }
            // $5330 adds $7C, the page irq_service last copied from $F2.
            const std::vector<uint8_t>& glyphs = leftActive ? leftCharset : g.charset;
            const size_t glyphAt = static_cast<size_t>(tile + half) * 8 + static_cast<size_t>(rowByte);
            if (glyphAt >= glyphs.size()) {
                continue;
            }
            const uint8_t bg = glyphs[glyphAt];
            const uint8_t overlapped = static_cast<uint8_t>(cols[col] & bg);
            if (overlapped == 0) {
                continue;
            }
            if (noteOverlap) {
                lastOverlap = overlapped;
                overlapAnds += 1;
            }
            const int prop = g.color[static_cast<size_t>(cell)] & 7;
            const int scanCol = col - col0;
            const int nibbles[2] = {overlapped >> 4, overlapped & 0x0F};
            for (const int v : nibbles) {
                if (v == 0) {
                    continue;
                }
                // Each row is swapped before it is scanned, and
                // flags_from_nibbles swaps back when the column is still in
                // ladder mode. A solid nibble therefore keeps the property
                // of its own cell: 0 is bit 3, anything else is bit 2.
                // Nibbles 3, 7, and 11-15 are that solid set. Nothing here
                // exempts tile $13, $14, or $31.
                const bool solid = v == 3 || v == 7 || v >= 11;
                // Nibble 7 on a ladder is ground in columns 0 and 2. Column
                // 1's twin slot is left out of $4F3C, so that case is not.
                const bool bit0 = v == 1 || v == 4 || v == 5 || v == 6 || v == 9 || v == 13 ||
                    (v == 7 && !(scanCol == 1 && prop != 0));
                if (solid && prop == 0) {
                    hit.wall = true;
                }
                if (solid && prop != 0) {
                    hit.ladder = true;
                }
                if (bit0) {
                    hit.ground = true;
                    if (!(solid && prop != 0)) {
                        hit.floor = true;
                    }
                }
                // $4F3D, rolled into $B6 as bit 1. $2E39 collects a lamp only
                // while this bit is set. 11 and 14 are in that list too.
                if (v == 2 || v == 6 || v == 8 || v == 9 || v == 10 || v == 11 || v == 14) {
                    hit.bit1 = true;
                }
            }
        }
    }
}

void AddCurrent(Contact& hit, int sx, int sy, int row0, int row1) {
    // overlap_actors scans the one library image already on screen.
    AddPose(hit, ViewPose(), sx, sy, row0, row1);
}

Contact Probe(int sx, int sy) {
    noteOverlap = true;
    lastOverlap = -1;
    overlapAnds = 0;
    Contact hit;
    AddCurrent(hit, sx, sy, 0, kSpriteRows);
    noteOverlap = false;
    return hit;
}

int LastOverlapAnd() {
    return lastOverlap;
}

int OverlapAnds() {
    return overlapAnds;
}

Contact ProbeFeet(int sx, int sy) {
    Contact hit;
    // Sprite rows 15-20. $4F38 snapshots $A7 on the row before this.
    AddCurrent(hit, sx, sy, 15, kSpriteRows);
    return hit;
}

Contact ProbeUpper(int sx, int sy) {
    Contact hit;
    AddCurrent(hit, sx, sy, 0, kSpriteRows - 6);
    return hit;
}

Contact ProbeNinjaSpawn(int sx, int sy) {
    noteOverlap = true;
    lastOverlap = -1;
    overlapAnds = 0;
    Contact hit;
    AddPose(hit, 0, sx, sy, 0, kSpriteRows, kNinjaSpawnRows);
    noteOverlap = false;
    return hit;
}

Contact ProbeNinjaSpawnUpper(int sx, int sy) {
    Contact hit;
    AddPose(hit, 0, sx, sy, 0, kSpriteRows - 6, kNinjaSpawnRows);
    return hit;
}

Contact ProbePose(int pose, int sx, int sy) {
    Contact hit;
    AddPose(hit, pose, sx, sy, 0, kSpriteRows);
    return hit;
}

bool PoseWall(int pose, int sx, int sy) {
    Contact hit;
    AddPose(hit, pose, sx, sy, 0, kSpriteRows);
    return hit.wall;
}
