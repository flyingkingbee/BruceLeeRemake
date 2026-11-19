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

// Result of the original overlap test at one sprite position.
// wall: $B6 bit 3. Nibbles 3, 7, and 11-15 on property 0. $1CC7 pushes him out.
// ground: $B6 bit 0. Nibbles 1, 4, 5, 6, 9, and 13, and nibble 7 except in the
// middle column when the property is not 0. The roof dots are 5.
// ladder: $B6 bit 2. Those same solid nibbles on any other property, including
// the ladder rails and the black line of a property-6 roof. Up and down climb.
// floor: bit 0 from a nibble that is not also bit 2.
// bit1: $B6 bit 1. Nibbles 2, 6, 8, 9, 10, 11, and 14. The lamp hanger is 2.
// Either ground or ladder stops a fall. Statue ink sets neither.
struct Contact {
    bool wall = false;
    bool ground = false;
    bool floor = false;
    bool ladder = false;
    bool bit1 = false;
};

// Test the picture already on screen at (sx, sy). overlap_actors scans that
// one library image. Jump, kick, punch, walk, and stand all use it.
Contact Probe(int sx, int sy);

// The last nonzero sprite-AND-glyph byte from the most recent Probe.
// overlap_actors stores that byte at $4E. -1 when the picture missed every cell.
int LastOverlapAnd();
int OverlapAnds();

// The same test, using only the bottom six sprite rows (15–20).
Contact ProbeFeet(int sx, int sy);

// Rows above the feet. $A7 is this result: the scan saved before the bottom
// six sprite rows. A fall nudges sideways when this still has ground.
Contact ProbeUpper(int sx, int sy);

// The overlap of one picture. Lamp checks use the pose already on screen,
// which is the sprite overlap_actors tested.
Contact ProbePose(int pose, int sx, int sy);

// Library $82, the picture spawn_ninja leaves in $4F50 for this frame's
// overlap. The stand pose is chosen later, after scan_specials.
Contact ProbeNinjaSpawn(int sx, int sy);
Contact ProbeNinjaSpawnUpper(int sx, int sy);

// Wall flag for one pose, ignoring what the rest of the walk cycle does.
// PlaceBruce and the end-of-frame shove use this on the picture just chosen.
bool PoseWall(int pose, int sx, int sy);

// scan_row reads glyphs from page $7C. enter_room changes $F2, and only
// irq_service at raster $FB copies $F2 into $7C. EnterRoom keeps the charset
// it is leaving. A door that leaves $7C on that old page for the next
// overlap calls UseLeftCharsetForNextOverlap, and CaptureFrameHits brackets
// that one overlap with BeginOverlapFrame and EndOverlapFrame.
void KeepLeftCharset();
void UseLeftCharsetForNextOverlap();
void BeginOverlapFrame();
void EndOverlapFrame();

// finish_exit's SEI holds off the interrupts while enter_room unpacks the
// room, then jumps to the next frame. TimeDoor estimates the raster of that
// SEI from what overlap_actors scanned on the door frame. irqs is how many
// times irq_service ran for that frame, including the one a pending $FB
// runs at the CLI. oldCharset is true when the next overlap still reads
// the page of the room just left. Call it after EnterRoom.
struct DoorTiming {
    bool oldCharset = false;
    int irqs = 0;
    // $FB was the armed line, so its interrupt runs at the CLI.
    bool cliIrq = false;
};
DoorTiming TimeDoor(int bruceXpos, const int* fighterXpos, int fighters);

// How many of the frame's $FB interrupts run before step_actors, from the
// same estimate of the overlap's cost. Also records that estimate for the
// frame clock.
int IrqsBeforeStep(int bruceXpos, const int* fighterXpos, int fighters);

// The raster the original frame begins on. EndFrameClock moves it to the
// next frame once this one's work is done. ResetFrameClock puts it back on
// a frame that waited, for a new room from a snapshot or a new game.
void EndFrameClock();
void ResetFrameClock();
// The raster this frame began on, by that estimate.
int FrameStartRaster();
