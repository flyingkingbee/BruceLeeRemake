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

constexpr int kRoomCount = 20;

// Load room 0..19. The screen, the colors, and the charset are the expanded
// bytes described in referencematerial/asm/rooms.asm. Lamps already taken in this room are
// painted as the bare mount. Returns false when a data file is missing.
// Asking for room 11 loads room 13 once rooms 12, 14, and 16 are clear.
bool EnterRoom(int roomId);

// Put roomId's picture in place of the one on screen. RestoreRoomPicture puts
// the previous picture back. No score, sound, or enter hook.
bool ShowRoomPicture(int roomId);
void RestoreRoomPicture();

// wake_actor's cold-start position for this room, in screen pixels.
// g.x = xpos * 2 - 24 and g.y = ypos - 21.
void RoomSpawn(int roomId, int& x, int& y);

// Character row of a tile row. Tile row 2 is character row 3. Each tile row
// after that is the picture row and the shadow row under it.
inline int PictureRow(int tileRow) {
    return 3 + (tileRow - 2) * 2;
}

// The tile on this column and tile row, with the shadow bit cleared.
// -1 when the cell is outside the playfield.
int TileAt(int col, int tileRow);

// match_special's LDA ($04),Y. Y is the column byte, and it is not limited
// to $27, so a wrapped column reads the following row. -1 when that byte
// is outside the screen.
int TileScanned(int tileRow, int memCol);

// Write a tile on both rows of the pair. Lamps, beams, and the trap door
// all paint through this.
void WriteTile(int col, int tileRow, int tile);

// Write one byte on the picture row only. The shadow row is left alone.
void WritePicture(int col, int tileRow, int tile);

// $4CE2 flag. True while that lamp is still in the room. A taken flag is 0.
bool LampPresent(int address);

// $2A + room. Lamps still to take in that room.
int LampsLeft(int room);

// copy_room_defaults and L_33CA. A finished game puts the lamps back.
void ResetCollectedLamps();

// The waiting player's copy of the lamp counts and taken flags. Snapshot
// copies the live tables. Between lives, L_0FED exchanges them.
void CopyCollectedLamps();
void ExchangeCollectedLamps();

// clear_work_ram's visit flags. The next room entry arms them again.
void ResetRoomBonus();

// $10E0. The treasure ending sets this player's room-entry flags, then
// clears room 0 so the opening room does not pay again.
void RearmRoomBonus();

// clear_work_ram and the hardware init that follows game over. Difficulty,
// the room 16 lanterns, the scroll, and the visit clock go back to a cold start.
void ResetRun();

// $40 sits in the block between_lives swaps. The waiting player's copy is
// the difficulty he will meet on his next life.
void CopyDifficulty();
void ExchangeDifficulty();

// True when (col, row) is an untaken lamp in the current room. The mount
// tile is returned and the lamp stays taken if the room is entered again.
bool ClaimLamp(int col, int row, int& mount);

// Tiles 2, 3, 4, and 5, from $2E89. left, right, and up are the steps taken
// since the previous check. falling is state $0E. On success the new room
// is loaded and g.x / g.y are the arrival spot.
bool TakeExit(int tile, int xpos, int ypos, bool left, bool right, bool up, bool falling);

// The same door test as TakeExit, without loading the room. A fighter who
// passes it is retired. Bruce is the actor who actually changes rooms.
bool ExitClaims(int tile, int xpos, int ypos, bool left, bool right, bool up, bool falling);

// Tile $60. The first free flame slot is armed and the cell's ink becomes 5.
void ArmCrumble(int col, int row);

// One logic frame of the hook at $3A6F. $1BFE flips $7B first. Doors, beams,
// the scrolling floor, and the boss run here, before the special scan.
// True means the hook moved him to another room, the way an exit does.
bool AdvanceRoom();

// The three screen interrupts that finished the previous logic frame.
// $87/$88 advance in every room. $4F45 is refilled with 2 whenever its
// gate byte passes through 0.
void AdvanceIrq();

// noise_byte ($1159). $16 advances and ($16),Y is the byte. The raster
// interrupt advances $16 as well. Y belongs to the caller.
uint8_t NoiseByte(int index);
void NoisePoke(int addr, int value);
// retire_actor keeps every bit of $95,X except bit 0.
void NoiseAnd(int addr, int mask);
// $40BC's DEC. True when the counter landed on 0 and the caller reloads it.
bool NoiseCountdown(int addr);
// One irq_service ($15A8) for the noise pointer, the visit byte, and $98.
// xpos bytes are the ones place_sprites copies to $B9,X. An actor who is
// off keeps the byte he last wrote.
void NoiseIrq(int stick, int bruceX, int yamoX, int ninjaX, bool yamoOn, bool ninjaOn);
// play_sound. The first free voice wins. voice_2's pointer is what the
// lamps later read at $F8. silence_sid clears the slots and leaves the pointer.
void QueueEffect(int id);
void SilenceEffects();
// frame stores 3 into $48 before the lamps, and $7B is still last frame's.
void PrepareNoise();
// Copy pages 0 and 1 from a snapshot, then the rasters still left in $48.
// Those run before the next $1BC2. Active bits $96 and $97 say which
// fighter positions the interrupt stores.
// replayWait is the rasters still left in the wait. A snapshot taken
// during the frame has not reached that wait, so those rasters belong
// to the tick that finishes the frame.
bool PlantSnapshotNoise(const wchar_t* path, bool replayWait = true);
// room00.vsf. $48 is 1 there, Yamo is off, and the ninja is on.
bool PlantRoom00Noise();

// $60, $64, $65, $66, and $4321, then the glyphs those bytes are showing.
void PlantSurface(int wait, int step, int down, int count, int slot);
// $6E, $6F, $77, and $78. The slide and the beam timers survive the
// enter hook, which restarts them.
void PlantHazard(int slide, int slideAt, int beam, int beam2);
// Room 13's nine movers. The enter hook has already filled the start
// columns, and this paints each floor across to the snapshot column.
void PlantMovers(const uint8_t* ram);
// The packed picture leaves the whole slide track as the hot tile. A
// snapshot has already painted the trail behind the block.
void PlantSlideTiles(const uint8_t* ram);
// $4FDE, $4FE1, and $4FE4. The three nozzle slots. The screen already
// shows the flame those counts have reached; the next hook steps them.
void PlantCrumble(const uint8_t* ram);
// $4E97-$4E9B, the beam columns and rows, and $79. The enter hook
// restarts these; a snapshot is wherever that room has since moved them.
void PlantHooks(const uint8_t* ram);
// $7B as the snapshot holds it, before the next frame's flip.
void PlantGate(int gate);
// Room 19. $49/$4A are the raster countdown and $87/$88 the visit clock.
void PlantTreasure(int low, int high, int clockLo, int clockHi);

// The snapshot was taken after this frame's wake counts and room hook.
// The next tick finishes that frame: it does not run either again.
// gate is $7B.
// irqs is $48, the rasters still to run before the next frame.
void HoldRoomHook(int gate, int irqs);
bool SnapshotFrameOpen();
void EndSnapshotFrame();
// -1 when this tick waits out the usual three. Otherwise the count once.
int TakeSnapshotIrqs();
// finish_exit skips the wait. count is the interrupts that already fired.
void NoteExitIrqs(int count);

// Room 19, from step_actors at $17C4. Below 2 the stick is $0E, up. From 2
// on it is $0F. The fire button is not touched. AdvanceIrq has already run.
int Room19Stick();

// test_visit at $10D0, then the timer resolve_blows stores over $18.
// Bruce is actor 0. A fighter keeps $18 on a short visit with $40 clear.
int HitRecoverTimer(bool bruce);

// $2DC0. The frame after a fighter's kick has landed. A long visit stores
// 1. A middle visit stores 3. A short visit stores 1 when $40 is set, and
// keeps $18 otherwise. The middle test runs before $40.
int KickRecoverTimer();

// stand_down at $228C. The 6 is doubled for Bruce on a long or middle
// visit and halved on a short one. A fighter stores 1 on a long visit or
// when $40 is set on a short visit, halves the 6 on a middle visit, and
// keeps 6 on a short visit with $40 clear.
int StandTimer(bool bruce);

// load_wake_counts. Long visit stores 3. Middle halves the table byte.
// A short visit stores 3 when $40 is set. The caller has already replaced
// the table byte with $30 when Yamo is a human opponent.
int WakeDelay(int count);

// try_ninja ($0DCB). Yamo is on, $40 is clear, the opponent is the computer,
// and the visit is still short. One noise byte. True when it is $19 or
// more, which reloads the ninja's count with $10 and skips the spawn.
// A smaller byte is consumed and the spawn still runs.
bool HoldNinjaWake();

// enter_room. $40 stores 3 over the table byte. A human Yamo then stores
// 8, and that 8 replaces the 3. The visit clock was just cleared.
int OpenWake(int count, bool humanYamo);

// A landing consumes one charge from $4F45,X. False when that actor has
// none left. The irq refills all three with 2.
bool TakeStomp(int actor);

// The enter hook at $4E9C, after taken lamps are painted.
void BeginRoomEffects();

// match_special for the tiles that are not lamps or doors. prize is hit bit
// 1. ladder is hit bit 2. A beam or a hot floor sets the shock state.
void TouchRoomTile(int tile, int col, int row, bool prize, bool ladder);

// $60 == 1 shoves him with the scrolling floor. -1 is up, +1 is down.
int SurfaceShove();

// Room 18's two bolts. False when that bolt is off. shape is 21 rows of 3
// bytes, the sprite at $8340 / $8380.
bool BossSparkAt(int index, int& x, int& y, const uint8_t*& shape);
