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

#include "collision.h"

// The other two fighters. Actor 1 is Yamo, the green fighter (active flag
// $81, sprite colors green and black). His knockout is 450. Actor 2 is the
// ninja (active flag $41). $2719 forces his sprite color to $F0, so he is
// drawn black, and his knockout is 200. The variables and the files
// ninja.bin and yamo.bin are named the other way around. Both use the same
// pose numbers as Bruce, including the spawn, strike, and knockdown pictures.

// Read data/ninja.bin and data/yamo.bin. False when either file is missing.
bool LoadFighters();

// Drop both fighters and arm an immediate spawn. PlaceBruce and a room
// change call this. A fighter who was on screen resumes at Bruce's arrival
// with the health he had. One who was not picks a spawn side.
void ResetFighters();

// Forget the sprite picture $D01E is still holding. EnterRoom and
// ResetFighters call this so the first hit test of a new room does not
// inherit the picture from the room he left.
void ClearHeldSprites();

// A new game. Nobody is carried into the first room.
void DropFighters();

// Stand both of them for one picture, then RestoreFighters puts them back.
// Coordinates are screen pixels, the same as g.x and g.y. Facing is -1 or +1.
void StandFighters(int ninjaX, int ninjaY, int ninjaFacing, int yamoX, int yamoY, int yamoFacing);
void RestoreFighters();

// $2E39 for the ninja, then Yamo. Bruce's own scan runs after this. A door
// or a hot tile retires that fighter. Tile $62 is the ladder ride.
void ScanFighterSpecials();
// cell_of_actor leaves the column in $E6,X. The row scan then increments
// $E9,X, so a finished scan stores the row below the actor.
void NoteScanCell(int actor, int col, int row);

// $1BDF. Yamo's health loses bit 6. The ninja keeps bits 0-2 and the sign.
// A wrapped landing is cut back on the next frame, and a negative byte stays negative.
void ClipFighterHealth();

// tick_wake_counts, then try_yamo and try_ninja. Both run before the overlap,
// so a fighter who wakes this frame is in that scan and steps the same frame.
void WakeDueFighters();

// overlap_actors, before scan_specials. A lamp taken in the scan is still in
// this contact. kind 0 is Bruce, 1 is Yamo, 2 is the ninja.
void CaptureFrameHits();
Contact FrameContact(int kind);
Contact FrameUpper(int kind);

// $D01E is the picture placed last frame. A fighter who woke this frame is
// not in it yet.
bool SpriteShown(int kind);

// One logic frame for both fighters, then the sprite hits. True when that
// hit spent one of Bruce's falls. The room is already the one he respawned in.
bool TickFighters();

// Actor 1 or actor 2 will run hold_done this frame, the long path in
// step_actors. A hold, a burial, or an inactive fighter returns without it.
// Sample this before TickFighters, which spends the hold.
bool FighterStepping();
// How many fighters overlap will scan. Sampled before a door retires them.
int AwakeFighters();

// between_lives stores $24 over both fighters before the room opens again.
void RestoreLifeHealth();

// A new game. Yamo is human again when the options page says OPPONENT,
// and the idle countdown starts over.
void ResetOpponentIdle();

// Paint whichever of them is in the room. Bruce is drawn after this, so he
// stays in front. That is sprites 0 and 1 above sprites 2-4.
void DrawFighters();

// room00.vsf, stopped at the frame wait. Yamo is off with delay $4E.
// The ninja is at xpos $7F ypos $90, walk-left, and his previous state
// was the fall. Delays stay above 0 so this tick does not spawn anyone.
void PlantRoom00Trace();

// Enter the snapshot's room and place all three actors from its zero page.
// Pages 0 and 1 also seed the noise walk. False when the file cannot be read.
bool PlantSnapshotTrace(const wchar_t* path);

// Bytes flicker_lamps can read before anyone moves: the delays and states.
void MirrorNoiseActors();
// try_yamo reads noise_byte after tick_wake_counts has decremented.
void NoteNoiseDelays();
// place_sprites' copies of xpos. Yamo is the kind-1 fighter.
void NoisePositions(int& bruceX, int& yamoX, int& ninjaX, bool& yamoOn, bool& ninjaOn);

// One actor after Tick. facing is 0 left and 1 right. hit is the
// start-of-frame overlap: bit 0 ground, bit 1 prize, bit 2 ladder, bit 3 wall.
struct TraceBody {
    bool on = false;
    int xpos = 0;
    int ypos = 0;
    int facing = 1;
    int action = 0;
    int timer = 0;
    int pose = 0;
    int hit = 0;
    int health = 0;
    int hold = 0;
};

TraceBody TraceBruce();
TraceBody TraceYamo();
TraceBody TraceNinja();
