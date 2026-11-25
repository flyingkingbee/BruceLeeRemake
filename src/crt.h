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

#pragma once

#include <cstdint>
#include <vector>

// Which parts of the television to draw. ShowCRTFilter chooses whether ApplyCrt
// runs at all. A part that is off leaves that piece out of the resample.
struct CrtOptions {
    bool curve;
    bool scanlines;
    bool blur;
    bool vignette;
};

// Resample the 320 by 200 picture into the fitted window rectangle. With the
// curve on, corners outside the glass are black and the middle of each edge
// stays on the edge of the rectangle. src pixels are 0xAARRGGBB, the same
// packing as g.pixels.
void ApplyCrt(const uint32_t* src, int srcW, int srcH, uint32_t* dest, int destW, int destH,
              CrtOptions options);

struct CrtRect {
    int left;
    int top;
    int right;
    int bottom;
};

// The same picture as ApplyCrt, for a dest buffer that keeps last frame's
// result. Only the blocks that read a source pixel changed since the last call
// are shaded again, and the result lists the rectangles of dest that changed.
// A new dest, size, or set of options shades everything and returns the whole
// rectangle. Nothing changed returns no rectangles.
const std::vector<CrtRect>& ApplyCrtChanged(const uint32_t* src, int srcW, int srcH, uint32_t* dest, int destW,
                                            int destH, CrtOptions options);

// The dest buffer's contents can no longer be trusted, or whatever showed them
// was recreated. The next ApplyCrtChanged shades everything.
void ForgetCrtPicture();
