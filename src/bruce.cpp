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

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include "bruce.h"
#include <cstdio>

#include "collision.h"
#include "config.h"
#include "draw.h"
#include "fighter.h"
#include "game.h"
#include "pad.h"
#include "room.h"
#include "sound.h"
#include "ui.h"

// How many noise_byte calls the lamp reload made this frame. A long run of
// zero nibbles is what pushes a quiet, unaligned overlap past the stick IRQ.
int lampReloadBytes = 0;
int lampGroups = 0;

int StandPose() {
    return g.facing < 0 ? 1 : 0;
}

int WalkPose() {
    // $28D4. Library $0E is showing, so the next picture is $10. Any other
    // picture starts at $0E. A wall shove keeps $0E on screen, and the step
    // after it is $10. Facing right is $12, then $14.
    if (g.facing < 0) {
        return g.pose == 2 ? 3 : 2;
    }
    return g.pose == 4 ? 5 : 4;
}

int PlaneShift(int pose, int plane) {
    // Mode 1 pictures are 32 screen pixels wide. $25FD slides a left-facing
    // mode-1 body left by 8 VIC units, and $264B does the same for detail
    // libraries $05 (punch left), $19 (flying kick left, leg extended), and
    // $43 (duck right). 8 VIC units are 16 screen pixels. The torso stays
    // over the stand picture. The fist, the kicking leg, or the duck's
    // black plane hangs off that side.
    if (pose == kPosePunchLeft) {
        return -16;
    }
    if (pose == kPoseFlyLeftExtended && plane == 1) {
        return -16;
    }
    if (pose == kPoseDuckRight && plane == 1) {
        return -16;
    }
    // $3F is the late left knockdown's detail. $264B slides it with the
    // punch, the extended kick, and the duck.
    if (pose == kPoseKnockLeft1 && plane == 1) {
        return -16;
    }
    return 0;
}

namespace {

// Screen limits from the xpos/ypos checks. g.x = xpos * 2 - 24 and
// g.y = ypos - 21, with the visible screen starting at sprite coordinate 24, 50.
constexpr int kMinX = 2;     // xpos $0D. A step from here reaches x = 0.
constexpr int kMaxX = 302;   // xpos $A3. A step from 300 reaches here.
constexpr int kMinY = 25;    // ypos $2E
constexpr int kMaxY = 178;   // ypos $C7

int HoldFor(int state) {
    // $4A8C. Climb pauses three logic frames. Duck pauses one. The rest run
    // every logic frame.
    if (state == kClimbUp || state == kClimbDown) {
        return 3;
    }
    if (state == kDuck) {
        return 1;
    }
    return 0;
}

void SetState(int state, int timer) {
    g.action = state;
    g.actionTimer = timer;
    g.hold = HoldFor(state);
}

// Steps since the last check at $2E39. move_left increments $4F5D,
// move_right increments $4F60, and move_up increments $4F57. $30D4
// reads those when it decides an exit is open.
bool wentLeft = false;
bool wentRight = false;
bool wentUp = false;

// stop_move is JMP clear_state, and set_state ends in RTS, so the caller
// of a JSR continues. HaltMove records that clear_state. A script that
// keep_state's afterwards still runs. The wall rewind does too: the
// refused count is spent, the other directions still run, and the slide
// and the stuck state are not skipped.
bool halted = false;

// clear_state increments $4FDB when the state at the start of the frame was
// already 0. choose_pose then leaves the picture that is already showing.
bool skipPose = false;

void HaltMove() {
    if (g.prevState == 0) {
        skipPose = true;
    }
    g.action = 0;
    g.actionTimer = 0;
    g.hold = 0;
    halted = true;
}

// $4F57 up, $4F5A down, $4F5D left, $4F60 right, then the older copies.
// release_hold shifts a nonzero current set one generation toward $4FD8.
// $1CC7 reads the generation at $4F63. Ten generations fit before the spill
// that the shift writes and the reversal clears. One sideways count is one
// xpos, two screen pixels.
constexpr int kStepUp = 0;
constexpr int kStepDown = 1;
constexpr int kStepLeft = 2;
constexpr int kStepRight = 3;
constexpr int kStepGens = 11;
int hist[kStepGens][4] = {};

void ClearSteps() {
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            hist[gen][d] = 0;
        }
    }
}

void RememberSteps() {
    bool any = false;
    for (int d = 0; d < 4; ++d) {
        if (hist[0][d] != 0) {
            any = true;
        }
    }
    if (any) {
        for (int gen = kStepGens - 1; gen > 0; --gen) {
            for (int d = 0; d < 4; ++d) {
                hist[gen][d] = hist[gen - 1][d];
            }
        }
        // hold_done's copy loop leaves $4E at $FF. A quiet frame does not
        // touch it, so the overlap byte survives for the next noise read.
        NoisePoke(0x4E, 0xFF);
    }
    for (int d = 0; d < 4; ++d) {
        hist[0][d] = 0;
    }
}

// $24C6. The bytes from $4F63 through $4FD8. The current generation is not
// part of the test.
bool OlderSteps() {
    for (int gen = 1; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            if (hist[gen][d] != 0) {
                return true;
            }
        }
    }
    return false;
}

void StandStill() {
    g.action = 0;
    g.actionTimer = 0;
    g.hold = 0;
    g.repeat = 6;
    g.prevState = 0;
    g.fallSlide = 0;
    g.tick = 0;
    g.pose = StandPose();
}

void Land() {
    SetState(0, 0);
}

// One xpos step, two screen pixels. move_left and move_right refuse only the
// screen edge. A wall is $1CC7's job on the next frame. Facing stays as it
// was: the kick and the fall nudge are already aimed. State $17 uses
// MoveSideRaw, which also stores the facing.
bool TryStep(int dir) {
    if (dir < 0) {
        if (g.x < kMinX) {
            HaltMove();
            return false;
        }
        g.x -= 2;
        hist[0][kStepLeft] += 1;
        wentLeft = true;
    } else {
        if (g.x >= kMaxX) {
            HaltMove();
            return false;
        }
        g.x += 2;
        hist[0][kStepRight] += 1;
        wentRight = true;
    }
    return true;
}

// move_up. The screen edge refuses it. A wall does not.
void Rise(int pixels) {
    for (int i = 0; i < pixels; ++i) {
        if (g.y < kMinY) {
            HaltMove();
            return;
        }
        g.y -= 1;
        hist[0][kStepUp] += 1;
        wentUp = true;
    }
}

void Drop(int pixels) {
    for (int i = 0; i < pixels; ++i) {
        if (g.y >= kMaxY) {
            HaltMove();
            return;
        }
        g.y += 1;
        hist[0][kStepDown] += 1;
    }
}

// move_up at $1DF2. The screen edge refuses it. A wall does not.
void MoveUpRaw(int pixels, bool halt = false) {
    for (int i = 0; i < pixels; ++i) {
        if (g.y < kMinY) {
            if (halt) {
                HaltMove();
            }
            return;
        }
        g.y -= 1;
        hist[0][kStepUp] += 1;
        wentUp = true;
    }
}

// move_down at $1E39. Same edge rule, and no wall test.
void MoveDownRaw(int pixels, bool halt = false) {
    for (int i = 0; i < pixels; ++i) {
        if (g.y >= kMaxY) {
            if (halt) {
                HaltMove();
            }
            return;
        }
        g.y += 1;
        hist[0][kStepDown] += 1;
    }
}

// move_left at $1E86 and move_right at $1EC4. One xpos, and facing follows.
void MoveSideRaw(int dir, bool halt = false) {
    if (dir < 0) {
        if (g.x < kMinX) {
            if (halt) {
                HaltMove();
            }
            return;
        }
        g.x -= 2;
        hist[0][kStepLeft] += 1;
        wentLeft = true;
    } else {
        if (g.x >= kMaxX) {
            if (halt) {
                HaltMove();
            }
            return;
        }
        g.x += 2;
        hist[0][kStepRight] += 1;
        wentRight = true;
    }
    g.facing = dir;
}

// After $1CC7 has consumed $4F63, copy $4F6F..$4FD8 down onto $4F57 and
// clear the tail from $4FC3. That drops the generation just undone and the
// empty current one, and keeps the older copies.
void SlideAfterPush() {
    int next[kStepGens][4] = {};
    for (int gen = 0; gen <= 8; ++gen) {
        for (int d = 0; d < 4; ++d) {
            next[gen][d] = hist[gen + 2][d];
        }
    }
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            hist[gen][d] = next[gen][d];
        }
    }
    // The slide at $1D0A counts $4E from $23 and leaves it at $FF.
    NoisePoke(0x4E, 0xFF);
}

// $1CC7. Walk $4F63 back: up by moving down, down by moving up, left by
// moving right, right by moving left. $85 starts at 1 and shifts on each up
// or sideways undo. A down undo leaves it set. Still set, and $C2 is not
// the duck, goes back through hold_done for the next generation. $86 skips
// the facing nudge on the first pass. The slide at $1D1F clears the hold
// set_state stored on the last undo, and the extra step is a walk, so
// mark_stuck leaves the hold at 0. State $18, timer $40.
// One undo step. The count is decremented first, including the step the
// screen edge refuses. That refusal is clear_state, and its RTS returns to
// the same direction's loop. The other directions, the slide, and the stuck
// state still run. A successful step stores the climb or the walk, which
// hold_done then copies into $C2 when this generation continues.
bool UndoOne(int& count, int kind) {
    if (count <= 0) {
        return true;
    }
    count -= 1;
    if (kind == kStepUp) {
        if (g.y >= kMaxY) {
            return false;
        }
        g.y += 1;
        hist[0][kStepDown] += 1;
        g.action = kClimbDown;
        return true;
    }
    if (kind == kStepDown) {
        if (g.y < kMinY) {
            return false;
        }
        g.y -= 1;
        hist[0][kStepUp] += 1;
        wentUp = true;
        g.action = kClimbUp;
        return true;
    }
    if (kind == kStepLeft) {
        if (g.x >= kMaxX) {
            return false;
        }
        g.x += 2;
        hist[0][kStepRight] += 1;
        g.facing = 1;
        wentRight = true;
        g.action = kWalkRight;
        return true;
    }
    if (g.x < kMinX) {
        return false;
    }
    g.x -= 2;
    hist[0][kStepLeft] += 1;
    g.facing = -1;
    wentLeft = true;
    g.action = kWalkLeft;
    return true;
}

void UndoAll(int kind) {
    int& count = hist[1][kind];
    while (count > 0) {
        if (!UndoOne(count, kind)) {
            HaltMove();
        }
    }
}

void PushOut(const Contact& here) {
    int tries = 8;
    for (;;) {
        const int up = hist[1][kStepUp];
        const int left = hist[1][kStepLeft];
        const int right = hist[1][kStepRight];
        const bool keepGoing = up == 0 && left == 0 && right == 0;
        // $C2 is the state from the start of this generation. A refused
        // step clears the state afterwards, and the duck test still sees
        // the old one.
        const bool wasDuck = g.action == kDuck;
        UndoAll(kStepUp);
        UndoAll(kStepDown);
        UndoAll(kStepLeft);
        UndoAll(kStepRight);
        SlideAfterPush();
        // The slide overwrites the undo counts. The exit test reads these
        // flags, so a step the slide threw away must not open a door.
        wentLeft = false;
        wentRight = false;
        wentUp = false;
        g.hold = 0;
        tries -= 1;
        // $1D3A. DEC $86 counts the generations the rewind has used.
        NoisePoke(0x86, tries & 0xFF);
        if (tries < 0 || here.ladder) {
            break;
        }
        if (keepGoing && !wasDuck) {
            // hold_done stores 0 into $4FDB, then copies the state into $C2.
            skipPose = false;
            g.prevState = g.action;
            RememberSteps();
            continue;
        }
        if (tries != 7) {
            // The facing nudge is move_left or move_right. The edge is
            // clear_state, and the JMP mark_stuck after that JSR still runs.
            MoveSideRaw(g.facing < 0 ? 1 : -1, true);
        }
        break;
    }
    g.action = kStuck;
    g.actionTimer = 0x40;
}

// State $05 at $2903, read after keep_state has decremented the timer.
// $0F is library 8. $0C-$0E are $1E. $02-$0B are $20. 1 is $1E. 0 is 8.
int JumpPose() {
    const int t = g.actionTimer;
    if (t >= 0x0F || t <= 0) {
        return kPoseLegs;
    }
    if (t >= 0x0C || t == 1) {
        return 7;
    }
    return kPoseArms;
}

void ChoosePose(const Contact& here) {
    // $2780. A refused move from a stand, and every later idle frame, leaves
    // the picture already on screen. The next overlap reads that picture.
    if (skipPose) {
        return;
    }
    // `here` is the overlap from before this frame's step, which is the hit
    // choose_pose reads. A walk that leaves a ladder still shows the climb
    // picture for that frame.
    const bool climbNow = g.action == kClimbUp || g.action == kClimbDown
        || ((g.action == kWalkLeft || g.action == kWalkRight) && here.ladder)
        || (g.action == 0 && here.ladder);
    if (g.action != kWalkLeft && g.action != kWalkRight) {
        g.tick = 0;
    }

    if (g.action == kPunch) {
        g.pose = g.facing < 0 ? kPosePunchLeft : kPosePunchRight;
    } else if (g.action == kFlyLeft || g.action == kFlyRight) {
        const bool tucked = g.actionTimer >= 0x0A;
        if (g.action == kFlyLeft) {
            g.pose = tucked ? 15 : 16;
        } else {
            g.pose = tucked ? 17 : 18;
        }
    } else if (g.action == kSideLeft || g.action == kSideRight) {
        const bool tucked = g.actionTimer >= 0x0C || g.actionTimer < 3;
        if (g.action == kSideLeft) {
            g.pose = tucked ? 9 : 10;
        } else {
            g.pose = tucked ? 11 : 12;
        }
    } else if (g.action == kJump) {
        g.pose = JumpPose();
    } else if (g.action == kDuck) {
        g.pose = g.facing < 0 ? kPoseDuckLeft : kPoseDuckRight;
    } else if (g.action == kFall) {
        // Open air is library $44. Overlapping a wall (hit bit 3) is
        // library 8, the legs. Bruce's $44 matches the jump's pixels, and
        // it is stored on its own so a later stuck test can tell them apart.
        g.pose = here.wall ? kPoseLegs : kPoseFallAir;
    } else if (climbNow) {
        // States 1 and 2, and a walk that overlaps a ladder, flip $0A / $0C.
        // Standing on a ladder keeps the picture already showing.
        const bool stepping = g.action == kClimbUp || g.action == kClimbDown
            || g.action == kWalkLeft || g.action == kWalkRight;
        if (stepping) {
            g.pose = g.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
        } else if (g.pose != kPoseClimb0 && g.pose != kPoseClimb1) {
            g.pose = kPoseClimb0;
        }
        // The walk libraries are not showing, so the next stride on the
        // floor starts at the first picture.
        g.tick = 0;
    } else if (g.action == kWalkLeft || g.action == kWalkRight) {
        // $28D4. The library on screen picks the stride, not a counter that
        // restarts when the state leaves the walk.
        g.pose = WalkPose();
    } else if (g.action == kStuck) {
        // $27C1 keeps the picture already showing. Library $44, and any
        // picture with a nonzero mode byte, is replaced by library 8.
        if (StuckUsesLegs(0, g.pose)) {
            g.pose = kPoseLegs;
        }
    } else {
        g.pose = StandPose();
    }
}

// move_for_state copies the timer into $52. keep_state decrements it.
void KeepBruce() {
    g.actionTimer -= 1;
    NoisePoke(0x52, g.actionTimer & 0xFF);
}

// The timer in g.actionTimer is the value before this frame's decrement,
// which is Y in move_for_state.
void Script(const Contact& here) {
    const int t = g.actionTimer;
    NoisePoke(0x52, t & 0xFF);

    if (g.action == kJump) {
        if (here.ladder) {
            Land();
            return;
        }
        // Each rise or drop returns through set_state. The screen edge is
        // clear_state, and that RTS comes back for the next step. keep_state
        // stores state 5 again, so the edge does not end the jump.
        if (t < 0x0D && t >= 2) {
            if (t >= 8) {
                MoveUpRaw(t == 0x0C ? 4 : 2, false);
            } else if (here.ground) {
                Land();
                return;
            } else {
                MoveDownRaw(2, false);
            }
        }
        KeepBruce();
        return;
    }

    if (g.action == kSideLeft || g.action == kSideRight) {
        // States 6 and 7 at $20D2 and $2120. A ladder lands immediately.
        // Ground lands only while the timer is below 7. The steps themselves
        // never read the wall bit. The two sideways steps come before the
        // drop, so a lamp that the drop clears is not a wall on the next test.
        if (here.ladder) {
            Land();
            return;
        }
        const int dir = g.action == kSideLeft ? -1 : 1;
        // $20E5. A refused step returns. The sideways steps and keep_state
        // still run, and the state stays 6 or 7.
        if (t > 0x0A) {
            MoveUpRaw(2, false);
        } else if (t == 0x0A) {
            MoveUpRaw(1, false);
        } else if (t < 7) {
            if (here.ground) {
                Land();
                return;
            }
            MoveSideRaw(dir, false);
            MoveSideRaw(dir, false);
            // $2111 and $215C compare Y with 6, but move_left and move_right
            // have just returned through set_state, whose TAY leaves Y as the
            // walk state (3 or 4). The branch is never taken, so the descent
            // is two pixels on every count below 7, including 6.
            MoveDownRaw(2, false);
            KeepBruce();
            return;
        }
        MoveSideRaw(dir, false);
        MoveSideRaw(dir, false);
        KeepBruce();
        return;
    }

    if (g.action == kFlyLeft || g.action == kFlyRight) {
        if (here.ladder || here.wall) {
            Land();
            return;
        }
        // $2058 and $209D. The frame whose timer is still $0C, after a ladder
        // or a wall has cancelled the kick.
        if (t == 0x0C) {
            PlayEffect(0x84);
        }
        const int dir = g.action == kFlyLeft ? -1 : 1;
        // $2065. move_up and move_left both return. The edge skips that
        // pixel and keep_state leaves the kick running.
        if (t >= 0x0A) {
            MoveUpRaw(1, false);
            MoveSideRaw(dir, false);
        } else if (t >= 3) {
            MoveSideRaw(dir, false);
        } else if (here.ground) {
            Land();
            return;
        } else {
            MoveDownRaw(1, false);
            MoveSideRaw(dir, false);
        }
        KeepBruce();
        return;
    }

    if (g.action == kPunch) {
        if (here.ladder || here.wall) {
            Land();
            return;
        }
        // The frame whose timer is 1 ends the picture and leaves a recovery
        // of 3 ($06 shifted down once by $10D0 while the long timer is clear).
        if (t == 1) {
            // stand_down. Long or middle doubles the 6. A short visit halves it.
            g.action = 0;
            g.actionTimer = StandTimer(true);
            g.hold = 0;
            return;
        }
        KeepBruce();
        return;
    }

    // State 0 with a timer still running is the punch recovery. Nothing moves.
    if (g.actionTimer > 0) {
        KeepBruce();
    }
}

void StartFly(int dir) {
    g.facing = dir;
    SetState(dir < 0 ? kFlyLeft : kFlyRight, 0x0C);
}

void Walk(int dir, bool fire) {
    const int walk = dir < 0 ? kWalkLeft : kWalkRight;
    // The edge is checked before any step, so a kick cannot start there either.
    if ((dir < 0 && g.x < kMinX) || (dir > 0 && g.x >= kMaxX)) {
        HaltMove();
        return;
    }
    // $1E63 and $1EA4. One blip once the edge test has passed, before the
    // steps. A kick that replaces a step has already sounded.
    PlayEffect(0x80);
    if (g.prevState != walk) {
        g.tick = 0;
    }
    // $1E70. Two steps, or three once $CB has reached 0. The routine falls
    // through into the last step. A kick replaces whichever step sees a walk
    // already in $C2 and $CB below 4. Fire is $9B == 0. The kick does not
    // move until the next logic frame. A step into the screen edge clears
    // the state. That step returns, so a later one in the burst can still
    // become the kick. A wall does not refuse the step. The next frame's
    // $1CC7 walks it back if he is still inside.
    auto one = [&]() -> bool {
        if (g.prevState == walk && g.repeat < 4 && fire) {
            StartFly(dir);
            return true;
        }
        if ((dir < 0 && g.x < kMinX) || (dir > 0 && g.x >= kMaxX)) {
            Land();
            return false;
        }
        MoveSideRaw(dir);
        SetState(walk, 0);
        return false;
    };
    if (g.repeat == 0 && one()) {
        return;
    }
    if (one()) {
        return;
    }
    one();
}

void Climb(int dir) {
    // Two explicit steps plus the fall-through, so three pixels. The extra
    // step when $CB is 0 makes four. Hold is 3. Changing into the climb
    // reloads $CB, so that first burst is three; later bursts count down
    // and the one that reaches 0 is four. The ladder bit is the overlap from
    // the start of the frame, so every pixel of this burst is taken. Only
    // the screen edge refuses one, and a refused pixel clears the state the
    // way stop_move does.
    const int n = g.repeat == 0 ? 4 : 3;
    for (int i = 0; i < n; ++i) {
        if (dir < 0) {
            if (g.y < kMinY) {
                // The refused pixel returns. The later pixels are the same
                // edge, so they refuse too, and the state stays cleared.
                HaltMove();
                return;
            }
            g.y -= 1;
            hist[0][kStepUp] += 1;
            wentUp = true;
            SetState(kClimbUp, 0);
        } else {
            if (g.y >= kMaxY) {
                HaltMove();
                return;
            }
            g.y += 1;
            hist[0][kStepDown] += 1;
            SetState(kClimbDown, 0);
        }
    }
}

void Duck(int facing) {
    // The diagonal paths refuse the turn at the far edge: facing left at
    // xpos >= $A2, facing right at xpos < $10.
    if (facing < 0 && g.x >= 300) {
        Land();
        return;
    }
    if (facing > 0 && g.x < 8) {
        Land();
        return;
    }
    g.facing = facing;
    SetState(kDuck, 0);
}

void StartFall() {
    // $1DC4. One drop, then state $0E. A refused drop is clear_state, and
    // that RTS lands on the set_state, so the fall is stored. $C2 of 0
    // makes that clear_state skip the picture.
    g.fallSlide = 2;
    NoisePoke(0xB0, 2);
    const int y0 = g.y;
    MoveDownRaw(1, false);
    if (g.y == y0 && g.prevState == 0) {
        skipPose = true;
    }
    SetState(kFall, 0);
}

void ContinueFall(const Contact& here) {
    const Contact upper = FrameUpper(0);
    if (upper.ground) {
        // Torso still on a ledge: one nudge toward facing, then two drops.
        // The nudge is a JSR, so the edge returns into those drops.
        g.fallSlide >>= 1;
        NoisePoke(0xB0, g.fallSlide);
        if (g.fallSlide != 0) {
            MoveSideRaw(g.facing, false);
        }
        MoveDownRaw(2, false);
        SetState(kFall, 0);
    } else if (here.ground || here.ladder) {
        Land();
    } else {
        MoveDownRaw(2, false);
        SetState(kFall, 0);
    }
}

void OnGround(int stick, bool fire, const Contact& here) {
    if (stick == 0x0E) {
        // Up. Too close to ypos $2E clears the state. Bit 2 climbs. Bit 3
        // blocks the standing jump. The climb is three pixels, or four once
        // the repeat count has run out. $1DDC plays before that ladder test,
        // so the standing jump sounds as well. Below ypos $2E it does not.
        if (g.y < kMinY) {
            HaltMove();
        } else {
            PlayEffect(0x80);
            if (here.ladder) {
                Climb(-1);
            } else if (here.wall) {
                HaltMove();
            } else {
                SetState(kJump, 0x0F);
            }
        }
    } else if (stick == 0x0D) {
        if (here.ladder) {
            // $1E29. ypos $C7 refuses the step and does not blip.
            if (g.y < kMaxY) {
                PlayEffect(0x80);
            }
            Climb(1);
        } else if (here.ground) {
            Duck(g.facing);
        }
    } else if (stick == 0x0B) {
        Walk(-1, fire);
    } else if (stick == 0x07) {
        Walk(1, fire);
    } else if (stick == 0x0A || stick == 0x06) {
        // Up with left ($0A) or right ($06). A ladder cancels it.
        // $1F46 and $1F5C blip when the jump is taken.
        if (here.ladder) {
            HaltMove();
        } else {
            PlayEffect(0x80);
            const int dir = stick == 0x0A ? -1 : 1;
            g.facing = dir;
            SetState(dir < 0 ? kSideLeft : kSideRight, 0x0F);
        }
    } else if (stick == 0x09 || stick == 0x05) {
        if (here.ladder) {
            HaltMove();
        } else if (here.ground) {
            Duck(stick == 0x09 ? -1 : 1);
        } else {
            HaltMove();
        }
    } else if (stick == 0x0F && fire && !here.ladder) {
        SetState(kPunch, 4);
    } else {
        HaltMove();
    }
}

}  // namespace

void PlantBruceSteps(const uint8_t* ram) {
    // Generation 0 is the count hold_done has not shifted yet. The next
    // one is what push_out reads. An empty table makes a wedged fighter
    // re-enter the room.
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int dir = 0; dir < 4; ++dir) {
            hist[gen][dir] = ram[0x4F57 + dir * 3 + gen * 12];
        }
    }
}

namespace {

const uint8_t* viewFrames = nullptr;
int viewAction = -1;
int viewFacing = 1;
int viewPose = 0;
// build_sprites ORs library N+1 into library N for Bruce and Yamo. The ninja's
// odd libraries have a zero high byte at $1239, so that OR stores nothing.
bool viewComposite = true;

}  // namespace

void SetActorView(const uint8_t* frames, int action, int facing, int pose, bool composite) {
    viewFrames = frames;
    viewAction = action;
    viewFacing = facing;
    viewPose = pose;
    viewComposite = composite;
}

void ClearActorView() {
    viewFrames = nullptr;
    viewAction = -1;
    viewComposite = true;
}

bool ViewComposite() {
    return viewComposite;
}

int ViewAction() {
    return viewFrames ? viewAction : g.action;
}

int ViewFacing() {
    return viewFrames ? viewFacing : g.facing;
}

int ViewPose() {
    return viewFrames ? viewPose : g.pose;
}

const uint8_t* PoseBytes(int pose, int plane) {
    const uint8_t* base = viewFrames ? viewFrames : g.frames.data();
    return base + static_cast<size_t>(pose * 2 + plane) * kFrameBytes;
}

namespace {

// $AD. State $17 waits this many frames between stick steps.
int carryDelay = 0;

// A shock that has run out spends the life from inside move_for_state.
bool shockDeath = false;

void RespawnHere() {
    shockDeath = true;
    BruceFell();
    shockDeath = false;
}

int KnockPicture(bool early) {
    if (g.facing > 0) {
        return early ? kPoseKnockRight0 : kPoseKnockRight1;
    }
    return early ? kPoseKnockLeft0 : kPoseKnockLeft1;
}

// $242E and $2458. Two steps away from the way he faces, then the facing is
// put back. A step into the screen edge returns, so the second step and
// keep_state still run. The picture keeps looking at the fighter who hit him.
void SlideBack() {
    const int face = g.facing;
    const int back = face < 0 ? 1 : -1;
    MoveSideRaw(back, false);
    MoveSideRaw(back, false);
    g.facing = face;
    if (g.actionTimer > 0) {
        KeepBruce();
    }
}

// States $0F, $13, and $1B while the timer is still running. Bruce is not
// the fighter who stands up at timer 2. A negative $D1 is spent on the
// frame keep_state stores 0, which is the same frame as the last slide.
void HitReact() {
    NoisePoke(0x52, g.actionTimer & 0xFF);
    if (g.action == kFlinch) {
        SlideBack();
        g.action = kFlinch;
        g.pose = StandPose();
        return;
    }
    if (g.action == kKnock) {
        const Contact here = FrameContact(0);
        // A refused drop returns into the slide. keep_state stores $13.
        if (!here.ground && !here.ladder) {
            MoveDownRaw(1, false);
        }
        SlideBack();
        g.action = kKnock;
        // choose_pose reads the timer keep_state just stored.
        g.pose = KnockPicture(g.actionTimer >= 0x0A);
        if (g.actionTimer <= 0 && g.health < 0) {
            BruceFell();
        }
        return;
    }
    if (g.action == kStomp) {
        KeepBruce();
        g.pose = KnockPicture(g.actionTimer >= 4);
        // State $1B is not the $13/$19 guard in check_bruce_down. Negative
        // health is spent on this frame, after keep_state has run.
        if (g.health < 0) {
            BruceFell();
        }
    }
}

// $2187. A pure direction steps two pixels. Diagonals do not. move_up,
// move_down, move_left, and move_right ignore walls; $1CC7 undoes a step
// that is still inside one on the next frame. $60 == 1 then shoves two
// pixels with the scrolling floor. The climb picture alternates on his
// own step, which is $AA shifted to 0 before choose_pose.
void NetVerticalSteps() {
    // $2211. The ride cancels up against down and keeps the difference.
    // exit_allowed reads the up count, so a cancelled rise is not an exit.
    const int up = hist[0][kStepUp];
    const int down = hist[0][kStepDown];
    if (up >= down) {
        hist[0][kStepUp] = up - down;
        hist[0][kStepDown] = 0;
    } else {
        hist[0][kStepDown] = down - up;
        hist[0][kStepUp] = 0;
    }
    wentUp = hist[0][kStepUp] != 0;
}

void CarryMove(int stick) {
    // A refused pixel returns. own_step_taken and the surface shove still
    // run, and keep_state stores $17, so the edge does not end the ride.
    bool stepped = false;
    if (carryDelay > 0) {
        carryDelay -= 1;
    } else if (stick == 0x0E) {
        MoveUpRaw(2, false);
        stepped = true;
    } else if (stick == 0x0D) {
        MoveDownRaw(2, false);
        stepped = true;
    } else if (stick == 0x0B) {
        MoveSideRaw(-1, false);
        MoveSideRaw(-1, false);
        stepped = true;
    } else if (stick == 0x07) {
        MoveSideRaw(1, false);
        MoveSideRaw(1, false);
        stepped = true;
    }
    // $218F stores 1 in $AA, and own_step_taken shifts it to 0 ($21E5).
    // noise_byte reads it. Room 7's lamps read the 1.
    NoisePoke(0xAA, stepped ? 0 : 1);
    if (stepped) {
        carryDelay = 4;
        g.pose = g.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
        // $21EB. His own step, not the shove from the moving floor.
        PlayEffect(0x80);
    }
    const int shove = SurfaceShove();
    if (shove < 0) {
        MoveUpRaw(2, false);
    } else if (shove > 0) {
        MoveDownRaw(2, false);
    }
    NetVerticalSteps();
    g.action = kCarry;
}

void TakeLamp(int col, int tileRow) {
    const int tile = TileAt(col, tileRow);
    if (tile != 0x13 && tile != 0x14 && tile != 0x31) {
        return;
    }
    int mount = 0;
    // take_lamp stashes A=0, X=0 and the column before claim_lamp. A hit
    // then stashes the mount. claim_lamp leaves the column, the row, and
    // $5C = 1. noise_byte later reads all of those.
    NoisePoke(0x57, 0);
    NoisePoke(0x58, 0);
    NoisePoke(0x59, col & 0xFF);
    NoisePoke(0x5A, col & 0xFF);
    NoisePoke(0x5B, tileRow & 0xFF);
    NoisePoke(0x5C, 1);
    if (!ClaimLamp(col, tileRow, mount)) {
        return;
    }
    NoisePoke(0x57, mount & 0x7F);
    WriteTile(col, tileRow, mount);
    // $2F2D. $7D added to the low score byte. The digits show 125.
    AddScoreByte(2, 0x7D);
    PlayEffect(0x8E);
}

// flicker_lamps writes rows 2 and 3 of these glyphs in charset $A000, and
// the first three of them in $A800. The charsets stay in memory, so a room
// opens with whatever the last flicker in that charset left, and the
// overlap scan reads those bytes. The port loads each room's charset from
// its file, so it keeps the written bytes here and puts them back.
constexpr int kLampGlyphs[5] = {0x93, 0x86, 0xB1, 0x94, 0xE7};
uint8_t lampGlyphRow[2][5] = {};
bool lampGlyphSet[2][5] = {};

void PokeGlyph(int glyph, uint8_t value) {
    const size_t i = static_cast<size_t>(glyph) * 8 + 2;
    g.charset[i] = value;
    g.charset[i + 1] = value;
    if (g.charsetId == 0 || g.charsetId == 1) {
        for (int k = 0; k < 5; ++k) {
            if (kLampGlyphs[k] == glyph) {
                lampGlyphRow[g.charsetId][k] = value;
                lampGlyphSet[g.charsetId][k] = true;
            }
        }
    }
}

int ReloadLamp(int slot, int index) {
    int n = 0;
    do {
        n = NoiseByte(index);
        lampReloadBytes += 1;
    } while ((n & 0x0F) == 0);
    NoisePoke(slot, n & 0x0F);
    lampReloadBytes += 1;
    return NoiseByte(index);
}

void AnimateLamps() {
    lampReloadBytes = 0;
    lampGroups = 0;
    // $40BC. The counter lives in the zero page noise_byte reads, so the
    // reload and the picture byte are the same calls the spawn uses.
    // Charset $A000 keeps the mount and moves one dot. Charset $A800 stores
    // the mask on its own. Charset $B000, room 18, is not written here.
    const int index = CaptionNoiseY();
    if (NoiseCountdown(0x101)) {
        lampGroups += 1;
        const uint8_t bits = static_cast<uint8_t>(ReloadLamp(0x101, index) & 0x30);
        if (g.charsetId == 0) {
            const uint8_t row = static_cast<uint8_t>(bits | 0xCC);
            PokeGlyph(0x93, row);
            PokeGlyph(0x86, static_cast<uint8_t>(row & 0xB8));
        } else if (g.charsetId == 1) {
            PokeGlyph(0x93, bits);
        }
    }
    if (NoiseCountdown(0x102)) {
        lampGroups += 1;
        const uint8_t bits = static_cast<uint8_t>(ReloadLamp(0x102, index) & 0x30);
        if (g.charsetId == 0) {
            PokeGlyph(0xB1, static_cast<uint8_t>(bits | 0xCC));
        } else if (g.charsetId == 1) {
            PokeGlyph(0xB1, bits);
        }
    }
    if (NoiseCountdown(0x103)) {
        lampGroups += 1;
        const uint8_t bits = static_cast<uint8_t>(ReloadLamp(0x103, index) & 0x0C);
        if (g.charsetId == 0) {
            const uint8_t row = static_cast<uint8_t>(bits | 0x33);
            PokeGlyph(0x94, row);
            PokeGlyph(0xE7, static_cast<uint8_t>(row & 0x2E));
        } else if (g.charsetId == 1) {
            PokeGlyph(0x94, bits);
        }
    }
}

}  // namespace

void RestoreLampGlyphs() {
    if (g.charsetId != 0 && g.charsetId != 1) {
        return;
    }
    for (int k = 0; k < 5; ++k) {
        if (lampGlyphSet[g.charsetId][k]) {
            PokeGlyph(kLampGlyphs[k], lampGlyphRow[g.charsetId][k]);
        }
    }
}

void PlantLampGlyphs(const uint8_t* ram) {
    for (int id = 0; id < 2; ++id) {
        const int base = id == 0 ? 0xA000 : 0xA800;
        for (int k = 0; k < 5; ++k) {
            if (id == 1 && (kLampGlyphs[k] == 0x86 || kLampGlyphs[k] == 0xE7)) {
                continue;
            }
            lampGlyphRow[id][k] = ram[base + kLampGlyphs[k] * 8 + 2];
            lampGlyphSet[id][k] = true;
        }
    }
    RestoreLampGlyphs();
}

namespace {

// $2E39. The cells from his column across two more, on his tile row and the
// row below, are checked. Tiles 2-5 are the exits and are tested either way.
// A lamp needs bit 1. Room 13 adds 4 to ypos before the row is chosen.
// True means an exit fired and the caller should not move him this frame.
int lastScanRow = 0;
bool lastScanPrize = false;
int lastScanShifts = 7;

bool ScanSpecials() {
    const int xpos = (g.x + 24) / 2;
    const int ypos = g.y + 21;
    int rowY = ypos;
    if (g.roomId == 0x0D) {
        rowY += 4;
    }
    if (rowY < 0x0C) {
        return false;
    }
    // $1C3C subtracts $0C as a byte. xpos $0B becomes column $3F.
    const int col0 = ((xpos - 0x0C) & 0xFF) >> 2;
    const int row0 = (rowY - 0x0C) >> 4;
    // $1C40 stores the column. $2E63 increments the row after the first pass.
    NoteScanCell(0, col0, row0);
    const Contact pose = FrameContact(0);
    const bool prize = pose.bit1;
    const bool falling = g.action == kFall;
    // $2E59, then one ASL $53 per cell that reaches $2EB1. Doors, $62, and
    // $2D/$2E return before the shift. Bruce is last, so his byte remains.
    int shifts = 0;
    for (int dr = 0; dr < 2; ++dr) {
        for (int dc = 0; dc < 3; ++dc) {
            const int col = col0 + dc;
            const int row = row0 + dr;
            const int tile = TileScanned(row, col);
            if (tile < 0) {
                continue;
            }
            if (tile >= 2 && tile <= 5) {
                if (TakeExit(tile, xpos, ypos, wentLeft, wentRight, wentUp, falling)) {
                    NotePrizeGate(prize, shifts);
                    return true;
                }
                continue;
            }
            if (tile != 0x62 && tile != 0x2D && tile != 0x2E) {
                shifts += 1;
            }
            TouchRoomTile(tile, col, row, prize, pose.ladder);
            if (prize) {
                TakeLamp(col, row);
            }
        }
        if (dr == 0) {
            NoteScanCell(0, col0, row0 + 1);
        }
    }
    NotePrizeGate(prize, shifts);
    lastScanRow = row0 + 1;
    lastScanPrize = prize;
    lastScanShifts = shifts;
    return false;
}

// Tile row 13 of the row pointers is $8FE8, past the screen: sixteen unused
// bytes, the eight sprite pointers, then $9000-$900F, which every snapshot
// holds the same. The pointers change with the pictures, so these are the
// usual ones. Row 14 is $014D, in page 1.
int StaleTile(int row, int col) {
    static const uint8_t kRow13[40] = {
        0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC, 0xDC,
        0xDC, 0xDC, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x0F, 0x0F, 0x00, 0x00, 0x03, 0x03,
        0x03, 0x03, 0x00, 0x00, 0x03, 0xCF, 0xFF, 0x03, 0x03, 0x03, 0x0F, 0x0C};
    if (row <= 12) {
        return TileScanned(row, col);
    }
    if (row == 13) {
        return col >= 0 && col < 40 ? kRow13[col] & 0x7F : -1;
    }
    if (row == 14) {
        return NoisePeek(0x14D + col) & 0x7F;
    }
    return -1;
}

// finish_exit drops one return address for a fighter, but match_special
// reached the exit with a JMP, so the call from scan_specials into
// scan_special_row is still on the stack. A fighter who left on his first
// row leaves that return at $2E61. The actor loop's RTS then lands there
// with $51 at 0, so Bruce's row is incremented and scanned once more, one
// row for each such fighter. $53 keeps shifting from where his own scan
// left it. Room 0's bottom right reaches row 13, whose tile 3 sends him
// through slot 5 to room 1.
bool ScanStaleRows(int count) {
    const int xpos = (g.x + 24) / 2;
    const int ypos = g.y + 21;
    const int col0 = ((xpos - 0x0C) & 0xFF) >> 2;
    const bool falling = g.action == kFall;
    const Contact pose = FrameContact(0);
    int shifts = lastScanShifts;
    for (int k = 0; k < count; ++k) {
        const int row = lastScanRow + 1 + k;
        NoteScanCell(0, col0, row);
        for (int dc = 0; dc < 3; ++dc) {
            const int col = col0 + dc;
            const int tile = StaleTile(row, col);
            if (tile < 0) {
                continue;
            }
            if (tile >= 2 && tile <= 5) {
                if (TakeExit(tile, xpos, ypos, wentLeft, wentRight, wentUp, falling)) {
                    NotePrizeGate(lastScanPrize, shifts);
                    return true;
                }
                continue;
            }
            if (tile != 0x62 && tile != 0x2D && tile != 0x2E) {
                shifts += 1;
            }
            // ASL $53 empties the gate after seven shifts.
            const bool gate = lastScanPrize && shifts < 7;
            if (row <= 12) {
                TouchRoomTile(tile, col, row, gate, pose.ladder);
                if (gate) {
                    TakeLamp(col, row);
                }
            }
        }
    }
    NotePrizeGate(lastScanPrize, shifts);
    return false;
}

}  // namespace

int BruceCarryDelay() {
    return carryDelay;
}

void PlantBruceCarry(int delay) {
    carryDelay = delay;
}

bool spawnHit = false;

bool ConsumeSpawnHit() {
    if (!spawnHit) {
        return false;
    }
    spawnHit = false;
    return true;
}

void PlaceBruce() {
    // wake_actor, with $0104 clear, copies $4BAE and $4BC2 and leaves him
    // there. Facing starts at 1. A picture that overlaps a wall is push_out
    // on the next frame, not a walk up to a clear pixel.
    RoomSpawn(g.roomId, g.x, g.y);
    g.facing = 1;
    g.health = 0x24;
    StandStill();
    ResetFighters();
    ClearSteps();
    // $0A6D. The overlap has not run yet, so $B6 stays 1 through this frame.
    spawnHit = true;
    wentLeft = false;
    wentRight = false;
    wentUp = false;
}

// between_lives shows the PLAYER page before enter_room_at. The room stays
// as it was until that page's countdown reaches 0.
bool awaitingLife = false;

bool outOfLives = false;

bool demoFell = false;

void BruceFell() {
    // $181B. In the demo, silence_sid and then open_room. No fall is spent.
    if (DemoMode()) {
        SilenceSound();
        demoFell = true;
        return;
    }
    // $1818. silence_sid, before the life is spent. between_lives then
    // enter_room_at run before the next logic frame, so he is already on
    // the spawn when that frame begins. The PLAYER page is drawn in that
    // call and does not hold the actors for extra frames.
    SilenceSound();
    if (gConfig.infiniteLives) {
        g.lives = g.lifeStock;
    } else {
        g.lives -= 1;
        if (g.lives < 0) {
            outOfLives = true;
            return;
        }
    }
    // between_lives stores $24 in $D1-$D3 before enter_room_at, and
    // finish_exit then saves that health for each active fighter. A wound
    // does not carry over a lost life: room 4's Yamo came back with 20.
    RestoreLifeHealth();
    // No wait follows the death frame. Its $FB interrupts up to lose_life,
    // then three more around enter_room_at, advance $16 before the next
    // frame's lamps read it.
    NoteDeathIrqs(DeathFrameIrqs(shockDeath) + 3);
    // $183B. Two players and the partner still in: $03 flips before the
    // PLAYER page, so the page and the other joystick are his.
    HandTurn();
    ResumeAfterFall();
    g.actionTimer = 4;
    // init_hardware has stored 1 in $60 and $66. enter_room's hook then
    // sees that 1, so this same frame copies the floor.
    RestartSurfaceClock();
    EnterFrameHook();
    awaitingLife = true;
}

void ContinueWithPartner() {
    ClearOutOfLives();
    RestoreLifeHealth();
    HandTurn();
    ResumeAfterFall();
    g.actionTimer = 4;
    RestartSurfaceClock();
    EnterFrameHook();
}

void RespawnFromSnapshot() {
    // A snapshot taken in between_lives's wait ($0F47) has already spent
    // the fall and refilled the health. The wait ends, init_hardware
    // restarts the player word, and enter_room_at places him on the spawn,
    // all before the next logic frame.
    awaitingLife = false;
    ResetPlayerCaption();
    // $1856. $03 has already flipped, but two players still trade the
    // $439F block after the wait, so the room is the incoming player's.
    SwapWaitingPlayer();
    if (EnterRoom(g.roomId)) {
        PlaceBruce();
    }
    g.actionTimer = 4;
    RestartSurfaceClock();
    EnterFrameHook();
}

bool BetweenLives() {
    return awaitingLife;
}

bool TakeDemoFell() {
    const bool was = demoFell;
    demoFell = false;
    return was;
}

bool TakeBetweenLives() {
    const bool was = awaitingLife;
    awaitingLife = false;
    return was;
}

bool OutOfLives() {
    return outOfLives;
}

void ClearOutOfLives() {
    outOfLives = false;
    awaitingLife = false;
}

void ResumeAfterFall() {
    awaitingLife = false;
    // between_lives calls init_hardware, which restarts the player word.
    // The swap is after the PLAYER page, so $29 is the incoming player's room.
    ResetPlayerCaption();
    SwapWaitingPlayer();
    if (EnterRoom(g.roomId)) {
        PlaceBruce();
    }
    Compose();
}

int forcedStick = -1;
bool forcedFire = false;
// The other port in a trace: a human opponent's stick and button.
int forcedStick2 = 0x0F;
bool forcedFire2 = false;
// Stick and fire from the previous frame's raster. on_ground reads $98
// after the fighters have ticked. Raster $FB stores $98 once a screen, and
// the read is past that raster when a fighter runs hold_done, so the body
// sees the stick just stored for this frame. With neither fighter stepping,
// the read is still short of $FB and $98 is last frame's stick. Room 0
// frame 23 (ninja stepping) jumped on the same frame the stick went up.
// Room 1 frame 242 (both fighters off) walked one more frame, then jumped.
int stickShown = -1;
bool fireShown = false;

// A snapshot in refresh_top's score convert is just before step_actors, so
// the rest of its frame reads the stick before another interrupt can store
// one. Rooms 8, 9, 11, 13, and 15 all read the snapshot's own $98 there.
bool snapshotKeepsStick = false;

void PlantStickShown(int stick, bool fire, bool beforeStep) {
    stickShown = stick & 0x0F;
    fireShown = fire;
    snapshotKeepsStick = beforeStep;
}

void SetForcedStick(int stick, bool fire) {
    forcedStick = stick;
    forcedFire = fire;
}

// $1383 and $1384, one per player. 1 is right-handed, the stick as read.
// 0 is left-handed. The options page sets them with L and R, Shift for
// joystick 2, and nothing else clears them, so they last until the
// program ends.
bool leftHanded[2] = {false, false};

void SetLeftHanded(int player, bool left) {
    leftHanded[player & 1] = left;
}

bool LeftHanded(int player) {
    return leftHanded[player & 1];
}

// $16AE. A left-handed port shifts the nibble right by two and ORs in
// $4A85 indexed by its low two bits ($00, $08, $04, $0C). The joystick is
// held turned a quarter: up becomes right, right becomes down, down
// becomes left, and left becomes up.
int LeftHandedStick(int stick) {
    static const int kTurn[4] = {0x00, 0x08, 0x04, 0x0C};
    return ((stick & 0x0F) >> 2) | kTurn[stick & 3];
}

void SetForcedStick2(int stick, bool fire) {
    forcedStick2 = stick;
    forcedFire2 = fire;
}

void ReadPlayerStick(int player, int& stick, bool& fire) {
    if (forcedStick >= 0) {
        const bool other = player != gBrucePlayer;
        stick = (other ? forcedStick2 : forcedStick) & 0x0F;
        fire = other ? forcedFire2 : forcedFire;
        // A script holds the joystick itself, so $16AE still turns it.
        if (leftHanded[player & 1]) {
            stick = LeftHandedStick(stick);
        }
        return;
    }
    const PadInput pad = player == 0 ? ReadPad() : ReadPad2();
    const bool keys = !UiOwnsKeyboard();
    const auto down = [](int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; };
    bool left = false;
    bool right = false;
    bool up = false;
    bool downKey = false;
    bool button = false;
    if (player == 0) {
        left = keys && down(VK_LEFT);
        right = keys && down(VK_RIGHT);
        up = keys && down(VK_UP);
        downKey = keys && down(VK_DOWN);
        button = keys && down(VK_RCONTROL);
    } else {
        left = keys && down('A');
        right = keys && down('D');
        up = keys && down('W');
        downKey = keys && down('S');
        button = keys && down(VK_LCONTROL);
    }
    left = left || pad.left;
    right = right || pad.right;
    up = up || pad.up;
    downKey = downKey || pad.down;
    button = button || pad.fire;
    stick = 0x0F;
    if (up && !downKey) {
        stick &= ~0x01;
    }
    if (downKey && !up) {
        stick &= ~0x02;
    }
    if (left && !right) {
        stick &= ~0x04;
    }
    if (right && !left) {
        stick &= ~0x08;
    }
    if (leftHanded[player & 1]) {
        stick = LeftHandedStick(stick);
    }
    fire = button;
}

void Tick() {
    // Only the frame that finishes a snapshot's frame keeps its stick.
    const bool keepSnapshotStick = snapshotKeepsStick;
    snapshotKeepsStick = false;
    // Effects the last frame held for its wait are on their voices by now.
    BeginFxFrame();
    // $1BDF. Before the lamps. Paused frames never reach this Tick.
    ClipFighterHealth();
    // $1BEB. Before the room hook, and skipped in the original while $0105
    // is negative. This Tick is itself skipped while the port is paused.
    // The three screen interrupts of the previous wait have already run.
    AdvanceIrq();
    // A snapshot taken past the wait has already run timed_caption, which
    // is before the lamps. A second tick put the room 12 snapshot's word a
    // frame early, so flicker_lamps read noise with Y $40 where the original
    // had the $2F the print leaves.
    if (!SnapshotSkipsLamps()) {
        TickPlayerCaption();
    }

    // $17C4 runs on every logic frame, including a hold, and the raster
    // count in $87 does too. The value is applied where the stick is built.
    const bool treasure = g.roomId == 19;
    const int treasureStick = treasure ? Room19Stick() : 0;

    int stick = 0x0F;
    bool fire = false;
    // $16A2. Port 1 while $03 is 0, port 2 while $03 is 1.
    ReadPlayerStick(gBrucePlayer, stick, fire);

    // The wait's three interrupts run after this frame, including on the
    // returns below. place_sprites then sees the positions the frame left.
    struct WaitIrqs {
        int stick;
        bool fire;
        ~WaitIrqs() {
            int bruceX = 0;
            int yamoX = 0;
            int ninjaX = 0;
            bool yamoOn = false;
            bool ninjaOn = false;
            NoisePositions(bruceX, yamoX, ninjaX, yamoOn, ninjaOn);
            const int pending = TakeSnapshotIrqs();
            const int count = (pending < 0 ? 3 : pending) + TakeStompIrqs();
            for (int i = 0; i < count; ++i) {
                NoiseIrq(stick, bruceX, yamoX, ninjaX, yamoOn, ninjaOn, fire);
            }
            // enter_room clears $87 after those interrupts. The next body
            // does not count the wait finish_exit skipped.
            ConsumeExitClock();
            EndFrameClock();
            // The copy and check_bruce_down have both run. The next frame's
            // lamps read the Y those two left.
            FinishFrameNoise();
        }
    } wait{stick, fire};
    // Saved on the way out, including the early returns, so the next short
    // body reads this frame's stick. The wait above already copied the
    // value it will store.
    struct RememberStick {
        int presented;
        bool presentedFire;
        ~RememberStick() {
            stickShown = presented;
            fireShown = presentedFire;
        }
    } remember{stick, fire};

    // $40BC runs before the overlap, and a held pose still reaches it.
    // The lamp glyphs flicker in every room. The charset selects the bytes.
    // A snapshot taken after the lamps leaves those calls for the next
    // frame. Running them now would walk the noise pointer twice.
    if (!SnapshotSkipsLamps()) {
        PrepareNoise();
        MirrorNoiseActors();
        MirrorRasterBytes(FrameStartRaster());
        AnimateLamps();
    }

    // $1BFE flips $7B and $3A6F runs the current room's hook before the
    // special scan, so a door can be open on the same frame it is tested.
    if (AdvanceRoom()) {
        // WinGame has already run finish_exit through PlaceBruce. A second
        // reset would see the fighters off and throw away the resume.
        ClearSteps();
        wentLeft = false;
        wentRight = false;
        wentUp = false;
        StandStill();
        // hook_frame_19 leaves through enter_room_at and finish_exit, and
        // enter_room ($0A6F) stores state 0 and timer 4, the same as a door
        // or a respawn. Room 0 then waited four frames before the stick.
        g.actionTimer = 4;
        Compose();
        return;
    }

    // try_yamo and try_ninja run before the overlap, and the overlap runs
    // before the scan. A lamp is still in the picture this contact tests.
    WakeDueFighters();
    CaptureFrameHits();
    // overlap_actors has already scanned whoever is on. finish_exit, below,
    // skips the wait. The xpos of each actor scanned sets how long the scan
    // took, and so the raster a door's SEI lands on.
    const int xposAtScan = (g.x + 24) / 2;
    int fighterXpos[2] = {};
    const int fightersAtScan = AwakeFighterXpos(fighterXpos);
    // The effects this frame plays from here on reach play_sound after the
    // interrupts that already fired during the overlap.
    DeferFxUntilIrq(IrqsBeforeStep(xposAtScan, fighterXpos, fightersAtScan));

    // $2E39 walks actor 2, then 1, then Bruce, before the sprite hits.
    // A door or a hot floor retires that fighter. Bruce's scan can still
    // change rooms after that. It starts by storing 0 in $0100, which
    // clear_work_ram left at 1 for a new game's first frame.
    NoisePoke(0x100, 0);
    const int staleRows = ScanFighterSpecials();

    // $2E10 clears state $17, the timer, and the pose hold before the cells
    // are read, so the tile has to catch him again. A shock skips the scan,
    // which is the $19 test. $AD is left as it was.
    if (g.action == kCarry) {
        g.action = 0;
        g.actionTimer = 0;
        g.hold = 0;
    }
    if (g.action == kZap) {
        // No scan of his own. $53 is what the fighters left, taken as empty.
        lastScanRow = (g.y + 21 - 0x0C) >> 4;
        lastScanRow += 1;
        lastScanPrize = false;
        lastScanShifts = 7;
    }
    if ((g.action != kZap && ScanSpecials()) || (staleRows > 0 && ScanStaleRows(staleRows))) {
        // scan_special_row leaves $4C at $FF. The door returns before the
        // sprite-hit walk that would replace it with 0.
        NoisePoke(0x4C, 0xFF);
        // The step generations at $4F57-$4FD8 are not cleared. Only
        // release_hold writes them, so a jump through a door that lands in
        // a wall is pushed back out by the steps taken in the old room.
        // Room 9 into room 8 did that in VICE.
        wentLeft = false;
        wentRight = false;
        wentUp = false;
        // finish_exit does not store a library. The picture he was already
        // showing is what the next frame's overlap tests. A death respawn
        // is the other path: choose_pose still runs and picks the stand.
        const int kept = g.pose;
        StandStill();
        g.pose = kept;
        // enter_room ($0A6F) leaves state 0 and timer 4. Those frames count
        // down before the stick is read.
        g.actionTimer = 4;
        // The jump to frame can reach overlap_actors before irq_service has
        // copied the new room's $F2 into $7C. Room 10's door into room 3,
        // with both fighters on, scanned the walk picture against room
        // 10's tile $11 and read prize ink where room 3's glyph is ground.
        // The same raster says how many interrupts advanced $16: room 0's
        // door with both fighters on left $48 at 1, room 1's with the
        // ninja left it at 2, and room 14's with the ninja on a fine-2 xpos
        // ran a pending $FB at the CLI as well.
        const DoorTiming timing = TimeDoor(xposAtScan, fighterXpos, fightersAtScan);
        NoteExitIrqs(timing.irqs, timing.cliIrq);
        if (timing.oldCharset) {
            UseLeftCharsetForNextOverlap();
        }
        ResetFighters();
        // Same store as PlaceBruce. enter_room writes the 1 before the
        // next frame's overlap replaces it.
        spawnHit = true;
        // finish_exit retires the fighters, then enter_room jumps to the
        // hook. The step that counts the timer down is the next body.
        EnterFrameHook();
        Compose();
        return;
    }

    // scan_special_row counts $4C from 2 down through 0, and the last DEC
    // leaves $FF. read_sprite_hits replaces that when it runs.
    NoisePoke(0x4C, 0xFF);

    // Hits use the pictures already on screen. The fighters then step, and a
    // life lost here has already put Bruce back on the spawn. A connecting
    // blow stores hold 4 before this, and release_hold spends one of it
    // before the flinch slide or the stand. Whether they reach hold_done
    // decides if this frame's raster has stored $98 before Bruce reads it.
    const bool stepped = FighterStepping();
    if (TickFighters()) {
        Compose();
        return;
    }
    // $1C5D. release_hold stores 8 in $86 before it tests the hold.
    NoisePoke(0x86, 8);
    if (g.hold > 0) {
        // release_hold spends $0106 and returns. choose_pose still runs, but
        // $4FDB is still set, so the picture already on screen stays. A shock
        // during a climb hold keeps that climb picture until the hold ends.
        g.hold -= 1;
        Compose();
        return;
    }
    // With neither fighter stepping, on_ground usually reads $98 before the
    // raster IRQ stores this frame's stick: the room 1 walk and the room 2
    // stand both acted a frame later. A fighter who is stepping reaches the
    // store. Climbing is not enough on a fine-1 step: room 17's ladder read
    // the previous raster there. A fine-2 climb does land past the store.
    // Room 2's ladder step had thirteen lamp bytes and no hook cells, and
    // the read took the right just stored instead of jumping on the up from
    // the previous raster.
    const int fineX = (((g.x + 24) / 2) - 0x0C) & 3;
    bool pendingShift = false;
    for (int d = 0; d < 4; ++d) {
        if (hist[0][d] != 0) {
            pendingShift = true;
        }
    }
    wentLeft = false;
    wentRight = false;
    wentUp = false;
    // hold_done stores 0 into $4FDB before the step. A clear_state from a
    // stand sets it again, and choose_pose then keeps the old picture.
    // halted is only the stop_move inside this frame.
    skipPose = false;
    halted = false;

    // $CB counts down only on a frame that actually runs, and only while the
    // state is the same one $C2 remembered. A fresh state reloads 6. Walking
    // and climbing take two pixels until that count reaches 0, then three.
    // State $17 passes through here too: release_hold updates $CB before the
    // wall test, and the wall test runs before the mover.
    const int state = g.action;
    if (state == 0 || state != g.prevState) {
        g.repeat = 6;
    } else if (g.repeat > 0) {
        g.repeat -= 1;
    }
    g.prevState = state;

    RememberSteps();
    // The picture chosen last frame. overlap_actors tests that one pose.
    // A walk used to test both strides so a step could be refused early.
    const Contact shown = FrameContact(0);
    const Contact here = shown;
    // overlap_actors has just run, and on_ground reads $98 after that. The
    // unaligned shift puts a quiet read next to raster $FB. A long lamp
    // reload carries it past the store. So does a step-history shift when
    // two lamp groups reload. Two overlapping rows still used the previous
    // stick. A fine-2 walk crosses once seven background rows overlap: room
    // 3's walk had seven and took the down just stored. The same seven rows
    // on a fine-2 side jump stayed before the store. Six rows on room 9's
    // respawn walk stayed before it too. Sixteen rows cross on a fine-2
    // step, and on any other step once the hook has written ten cells.
    // Room 17's walk had seventeen rows and ten cells and took the down
    // just stored. Twenty-eight rows and no hook cells, on room 1's fine-3
    // walk, stayed before the store.
    // Six hook cells carry a fine-2 step past the store in room 17. A fine-1
    // step there still read the previous stick with eight cells, and crossed
    // once the hook wrote eleven. Room 9 wrote eight cells on a fine-2
    // respawn walk and the read was still raster 248, before the store at
    // 270, so those cells do not cross there. Room 7's beam and slide do that to every fine-2 step, so down ducks there
    // instead of repeating the previous left step. A fine-0 step in that
    // room still reads the previous stick. Room 8's two beams do the same
    // to a fine-2 step: the read was raster 278, after the store at 263,
    // with one lamp group and no hook cells. A fine-1 landing in that room
    // still read the previous stick. Room 5's beams do the same: the flinch
    // ended on a fine-2 step with one lamp group and no hook cells, and the
    // read took the stick just stored.
    const bool beamFine = (g.roomId == 5 || g.roomId == 7 || g.roomId == 8) && fineX == 2;
    const bool climbFine = (g.action == kClimbUp || g.action == kClimbDown) && fineX == 2;
    const bool walkFine = (g.action == kWalkLeft || g.action == kWalkRight) &&
        fineX == 2 && OverlapAnds() >= 7;
    const bool overlapCross = OverlapAnds() >= 16 && (fineX == 2 || HookTiles() >= 10);
    const bool hookCross = g.roomId != 9 && HookTiles() >= (fineX == 2 ? 6 : 11);
    // Sixteen cells cross on their own. Room 13's floors store that many on
    // the frames they move, and the stand there read raster 309, after the
    // store at 274. A frame that stores nothing in that room still reads
    // around raster 226, before the store. Room 9's eight cells do not.
    const bool heavyHook = HookTiles() >= 16;
    const bool slowOverlap = fineX != 0 && (lampReloadBytes >= 24 || heavyHook ||
        (pendingShift && ((lampGroups >= 2 && fineX == 2) || overlapCross || walkFine ||
            hookCross || beamFine || climbFine)));
    bool useShown = stickShown >= 0 && (keepSnapshotStick || (!stepped && !slowOverlap));
    // Sync= takes VICE's choice: whether the raster had stored this frame's
    // stick before on_ground read $98.
    const int syncedStick = SyncStickValue();
    if (syncedStick >= 0 && stickShown >= 0 && stickShown != (stick & 0x0F)) {
        if (syncedStick == (stick & 0x0F)) {
            SyncNoteStick(!useShown, true);
            useShown = false;
        } else if (syncedStick == stickShown) {
            SyncNoteStick(!useShown, false);
            useShown = true;
        } else {
            SyncNoteStickMismatch(stickShown, stick & 0x0F, syncedStick);
        }
    }
    if (useShown) {
        stick = stickShown;
        fire = fireShown;
    }
    // A human's button can change in the middle of a frame, so the script's
    // last value per frame is not always what on_ground read. Take VICE's.
    const int syncedFire = SyncFireValue();
    if (syncedFire >= 0) {
        fire = syncedFire == 0;
    }
    // $17C4. Room 19 throws away the stick just chosen, including the one a
    // quiet frame kept from the previous raster, and writes $0E or $0F from
    // $88. Fire is left as it was. The write is inside the actor step, so
    // on_ground reads it on this same frame.
    if (treasure) {
        stick = treasureStick;
    }
    // $24B7. The frame after a reversal that is clear of the wall drops the
    // $40 timer and does not read the stick. While he is still inside and
    // $24C6 finds no older steps, $24DB re-enters this room on the spawn.
    if (state == kStuck && g.actionTimer > 0 && !shown.wall) {
        // while_stuck stores 1 into $52 and keep_state decrements it.
        NoisePoke(0x52, 0);
        g.actionTimer = 0;
        ChoosePose(here);
        Compose();
        return;
    }
    // State $19 jumps to the timer test and does not push_out. A shock that
    // overlapped a wall still plays out where he is.
    if (state != kZap && shown.wall) {
        // $24DB. finish_exit places him on this room's spawn and does not
        // spend a life. State $19 is the path that does.
        if (state == kStuck && g.actionTimer > 0 && !OlderSteps()) {
            if (EnterRoom(g.roomId)) {
                PlaceBruce();
                // stuck_reenter is finish_exit. enter_room leaves timer 4
                // and then runs the hook.
                g.actionTimer = 4;
                EnterFrameHook();
            }
            ArmExitClock();
            Compose();
            return;
        }
        if (state == kStuck && g.actionTimer > 0) {
            // $24ED. undo_again stores the facing in $4C before it rewinds.
            NoisePoke(0x4C, g.facing < 0 ? 0 : 1);
        }
        PushOut(shown);
        // check_bruce_down protects only state $13 and $19 while the timer
        // remains. push_out has stored $18, so a negative $D1 is spent now.
        if (g.health < 0) {
            BruceFell();
            Compose();
            return;
        }
        ChoosePose(shown);
        Compose();
        return;
    }

    // State $19. Y is the timer before the decrement. 1 spends the life.
    // hold_done has already shifted the step counts. The wall test did not.
    if (state == kZap) {
        if (g.actionTimer > 0) {
            NoisePoke(0x52, g.actionTimer & 0xFF);
        }
        if (g.actionTimer <= 1) {
            RespawnHere();
        } else {
            KeepBruce();
            g.pose = kPoseLegs;
        }
        Compose();
        return;
    }

    // Timer 0 skips the mover. Negative health on a knockdown or any other
    // state is check_bruce_down, after the step. A running knockdown is not.
    if ((g.action == kKnock || g.action == kStomp) && g.health < 0 && g.actionTimer <= 0) {
        BruceFell();
        Compose();
        return;
    }
    if ((g.action == kFlinch || g.action == kKnock || g.action == kStomp) && g.actionTimer > 0) {
        // actor_tick stores $FF at $C5 before move_for_state.
        NoisePoke(0xC5, 0xFF);
        HitReact();
        Compose();
        return;
    }

    // State $17. The picture flips inside CarryMove, on his own step only.
    if (g.action == kCarry) {
        NoisePoke(0xC5, 0xFF);
        if (g.actionTimer > 0) {
            NoisePoke(0x52, g.actionTimer & 0xFF);
        }
        CarryMove(stick);
        Compose();
        return;
    }

    const bool supported = here.ground || here.ladder;
    NoisePoke(0xC5, 0xFF);
    if (g.actionTimer > 0) {
        Script(here);
    } else if (state == kFall) {
        ContinueFall(here);
    } else if (supported) {
        OnGround(stick, fire, here);
    } else {
        StartFall();
    }

    ChoosePose(here);
    // $1CC7 runs at the start of the next frame, from the picture chosen
    // here. Moving him back now would hide that overlap from the lamp test.
    Compose();
}
