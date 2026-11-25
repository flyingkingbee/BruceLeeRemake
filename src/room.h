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
// True when the last EnterRoom turned room 11 into room 13. enter_room then
// jumps to enter_room_at, so finish_exit runs a second time.
extern bool enteredThroughRoom11;
// enter_room's copy of the room's twenty bytes at the $4AA8 pointer to $0153.
void MirrorEntryColors(int roomId);
// The scratch pointers point_at_row and overlap_actors leave.
void MirrorPointAtRow(int row);
void MirrorPrintString(int id, int row, int col);
void MirrorBlitBuffer();
void ExtraBlitFlip();
void MirrorBruceOverlap(int xpos, int ypos);
// The room-entry bonus flags at $0300, from a snapshot's memory.
void PlantRoomBonus(const uint8_t* ram);
// $40, the finished-game count, from a snapshot.
// The charset bank in $7C, from $F2 at the last interrupt, 0 to 3, or -1 when
// room 18's flash has not run in this room. overlap_actors reads glyphs there.
int FlashCharsetBank();
void PlantDifficulty(int value);
void PlantWaitingDifficulty(int value);

// $176D. The idle handover stores $20 in $88, which test_visit then takes
// for a long visit.
void MarkLongVisit();

// $0104. clear_work_ram stores 1, and attract_demo halves it to 0 for the
// attract demo. While it is 0, noise_byte returns 1 without moving $16,
// the visit clock stands still, every wake uses the main spawn, the top
// score is not raised, and a fall goes back to the options page.
bool DemoMode();
void SetDemoMode(bool on);

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

// A snapshot's $2A table. Room 15's bridge prints when this count is already 0.
void PlantLampCounts(const uint8_t* ram);
// The waiting player's lamp counts, $43A1 + room in a snapshot's $439F
// block. His flags are stashed in a packed form; a full count has every
// lamp and a 0 count none, and those are the cases the tests plant.
void PlantWaitingLamps(const uint8_t* ram);

// copy_room_defaults and L_33CA. A finished game puts the lamps back.
void ResetCollectedLamps();

// The waiting player's copy of the lamp counts and taken flags. Snapshot
// copies the live tables. Between lives, swap_waiting_lamps exchanges them.
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
// Tiles and color cells the room hook stored before this frame's stick read.
int HookTiles();
// $0B40. enter_room jumps here after the picture is up. The frame that
// left already flipped $7B, so this call does not flip it again.
void EnterFrameHook();

// The three screen interrupts that finished the previous logic frame.
// $87/$88 advance in every room. $4F45 is refilled with 2 whenever its
// gate byte passes through 0.
void AdvanceIrq();

// noise_byte ($1159). $16 advances and ($16),Y is the byte. The raster
// interrupt advances $16 as well. Y belongs to the caller.
uint8_t NoiseByte(int index);
// The Y register noise_byte indexes with. copy_sprite_image leaves $40.
// timed_caption leaves $2F on the frame it prints. retire_actor, which
// runs after the copy, leaves the voice slot from $59AE and the next
// frame's lamps still hold that Y.
int NoiseIndex();
void NotePostBlitRetire(int kind);
void ClearPostBlitRetire();
void FinishFrameNoise();
// Oracle only. Records each noise_byte the way the VICE capture does:
// Y, the byte, $16, $17, and the logic frame about to be logged.
void BeginNoiseLog(const wchar_t* path);
// Copies the room hook's beam bytes $71-$79 and surface bytes $60-$66 into the
// noise memory.
void MirrorRoomHookBytes();
// Sync= in trace mode. Loads a VICE recording made with the logger's sync
// flag and writes the replay's events to logPath. SyncHitValue is VICE's
// $D01E for the current frame, or -1 when there is none to replay.
bool LoadSync(const char* path, const wchar_t* logPath);
bool SyncActive();
int SyncHitValue();
// Logs the port's own $D01E against VICE's when they differ.
void SyncNoteHit(int port, int vice);
// VICE's $98 when Bruce's on_ground read it this frame, or -1. The port
// logs where its own old-or-new stick choice disagreed, and takes a value
// that is neither stick, a stick that changed twice in one frame.
int SyncStickValue();
// VICE's $9B at that read (0 while held), or -1 when the trace has none.
int SyncFireValue();
// The raster interrupts VICE ran this frame, or -1. The wait runs that many.
int SyncIrqCount();
void SyncNoteStick(bool portNew, bool viceNew);
void SyncNoteStickMismatch(int oldStick, int newStick, int vice);
void EndSync();
void SetNoiseFrame(int frame);
void NoisePoke(int addr, int value);
// The noise model's copy of a zero-page or stack-page byte.
int NoisePeek(int addr);
// scan_specials stores hit bit 1 in $53, then ASL once per cell that is not
// a door, the scrolling ladder, or tile $2D/$2E. Six ordinary cells turn a
// set bit into $80. The last actor scanned leaves the byte noise_byte reads.
void NotePrizeGate(bool bit1, int shifts);
// retire_actor keeps every bit of $95,X except bit 0.
void NoiseAnd(int addr, int mask);
// $40BC's DEC. True when the counter landed on 0 and the caller reloads it.
bool NoiseCountdown(int addr);
// One irq_service ($15A8) for the noise pointer, the visit byte, and $98.
// xpos bytes are the ones place_sprites copies to $B9,X. An actor who is
// off keeps the byte he last wrote.
void NoiseIrq(int stick, int bruceX, int yamoX, int ninjaX, bool yamoOn, bool ninjaOn, bool fire = false);
// The idle pause. 32768 screens with no stick or button outside a pause and
// the original pauses itself and cycles the band colors until play resumes.
// $1628's count for screens that pass while the port is paused. True when
// the band colors changed, so the picture needs composing again.
bool PausedScreens(int screens);
// True once, after a screen of play has run the idle count out.
bool TakeIdlePause();
// Leaving any pause: $82 = 0, and the band colors come back if they were
// cycling. True when they did.
bool EndIdlePause();
// A killing landing repeats add_score until the health byte is positive.
// stash_scores is slow enough that the body runs past the usual three
// screens, and each extra screen still increments the noise pointer.
void NoteStompIrqs(int scoreAdds);
int TakeStompIrqs();
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
// maxReplay caps the interrupts replayed from $48: 3 for a frame's wait, more
// for between_lives's longer one.
bool PlantSnapshotNoise(const wchar_t* path, bool replayWait = true, int maxReplay = 3);

// Trace mode's Poke=ADDR:VAL, both hex: bytes changed in the snapshot's
// memory before anything is planted, for example $42CA for a human
// opponent or $40 for the second round.
void AddSnapshotPoke(int addr, int value);
void ApplySnapshotPokes(uint8_t* ram, size_t size);
// The last Poke= value for ADDR, or fallback when there is none.
int SnapshotPokeValue(int addr, int fallback);
// room00.vsf. $48 is 1 there, Yamo is off, and the ninja is on.
bool PlantRoom00Noise();
// clear_work_ram, after the options page: $03-$F5 are zeroed, which puts the
// noise pointer $16/$17 at the start of page 0, and $0100-$0107 and
// $014B-$0152 are set to 1.
void ClearWorkRamNoise();
// The interrupts between clear_work_ram and a new game's first frame, the
// six that leave $16 at 6 there.
void StartNoiseCounter();

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
// $014B-$0152, room 13's one-shot 500 for each height band, both players.
void PlantBandBonus(const uint8_t* ram);
// $7B as the snapshot holds it, before the next frame's flip.
void PlantGate(int gate);
// Room 19. $49/$4A are the raster countdown and $87/$88 the visit clock.
void PlantTreasure(int low, int high, int clockLo, int clockHi);

// The snapshot was taken after this frame's wake counts. The lamps stay
// put on the tick that finishes the frame. gate is $7B. irqs is $48.
void HoldRoomHook(int gate, int irqs);
bool SnapshotFrameOpen();
void EndSnapshotFrame();
// True while the first frame of a snapshot taken past flicker_lamps runs.
bool SnapshotSkipsLamps();
// Copy the scrolling floor's $60, $64, $65, and $66 into the noise memory.
void MirrorSurface();
// $44 and $F4 as the raster interrupts leave them at this raster.
void MirrorRasterBytes(int raster);
// -1 when this tick waits out the usual three. Otherwise the count once.
int TakeSnapshotIrqs();
// finish_exit skips the wait. count is the interrupts that already fired.
// enter_room then clears the visit clock, so those interrupts do not remain
// in $87, and the next body does not count a wait that never ran.
void NoteExitIrqs(int count, bool cliIrq = false);
// A lost life. irq_service runs count times before the next frame, and
// enter_room clears $87 before the last of them, which leaves it at 1.
void NoteDeathIrqs(int count);
void ArmExitClock();
// After this frame's interrupts. Clears the visit clock and skips the next
// body's visit advance. True when this frame was finish_exit.
bool ConsumeExitClock();

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
bool HoldNinjaWake(int index);
// The noise model's three effect voices: slot, priority, and delay each.
void DescribeFxVoices(int out[9]);
// The frame's effects wait for the $FB interrupts that ran before the step.
// BeginFxFrame starts a frame. DeferFxUntilIrq holds effects queued from now
// on until that many of the wait's interrupts have advanced the voices.
void BeginFxFrame();
void DeferFxUntilIrq(int irqs);

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
// $0816. A lost life stores 1 in $60 and $66 before enter_room's hook.
void RestartSurfaceClock();

// Room 18's two bolts. False when that bolt is off. shape is 21 rows of 3
// bytes, the sprite at $8340 / $8380.
bool BossSparkAt(int index, int& x, int& y, const uint8_t*& shape);
// $432E phase, $4330 delay, $4332 xpos, $4334 ypos, for bolts 0 and 1.
void PlantBolts(const uint8_t* ram);
void ReadBolts(int out[8]);
