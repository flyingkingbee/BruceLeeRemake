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
#include "game.h"

namespace {

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
void AddPose(Contact& hit, int pose, int sx, int sy, int row0, int row1) {
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
        const uint8_t* body = PoseBytes(pose, 0);
        const uint8_t* detail = PoseBytes(pose, 1);
        const bool both = ViewComposite();
        const int sole = (pose == kPosePunchLeft || pose == kPosePunchRight) ? 1 : 0;
        const uint8_t* only = both ? nullptr : PoseBytes(pose, sole);
        // Mode 0 clears the third column. Mode 1 ($51DA) shifts the second
        // source byte's high nibble into A and calls L_51FF, which begins
        // with LDA #0 and expands $1F. The two calls on the first byte have
        // already shifted $1F out, and the nibble in A is never stored, so
        // the third column is 0 on every row. Columns 16-23 are not in the scan.
        for (int x = 0; x < kHardwareColumns; ++x) {
            const int index = y * kSpriteRowBytes + x / 8;
            const uint8_t mask = static_cast<uint8_t>(0x80 >> (x & 7));
            const bool on = both ? ((body[index] & mask) != 0 || (detail[index] & mask) != 0)
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
            const uint8_t bg = g.charset[static_cast<size_t>(tile + half) * 8 + static_cast<size_t>(rowByte)];
            const uint8_t overlapped = static_cast<uint8_t>(cols[col] & bg);
            if (overlapped == 0) {
                continue;
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

}  // namespace

void AddCurrent(Contact& hit, int sx, int sy, int row0, int row1) {
    // overlap_actors scans the one library image already on screen.
    AddPose(hit, ViewPose(), sx, sy, row0, row1);
}

Contact Probe(int sx, int sy) {
    Contact hit;
    AddCurrent(hit, sx, sy, 0, kSpriteRows);
    return hit;
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
