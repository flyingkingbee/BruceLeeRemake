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

#include "fighter.h"

#include "bruce.h"
#include "collision.h"
#include "config.h"
#include "game.h"
#include "load.h"
#include "room.h"
#include "sound.h"

#include <algorithm>
#include <fstream>
#include <vector>

namespace {

constexpr int kMinX = 2;
constexpr int kMaxX = 302;
constexpr int kMinY = 25;
constexpr int kMaxY = 178;
constexpr int kStepUp = 0;
constexpr int kStepDown = 1;
constexpr int kStepLeft = 2;
constexpr int kStepRight = 3;
constexpr int kStepGens = 11;

struct Fighter;
void Bury(Fighter& f, bool afterBlit = false);

// $135B. Reloaded into $5E. That is actor 1, Yamo. rooms.asm names this
// table the other way around; try_yamo at $0D20 is the instruction.
constexpr uint8_t kYamoReload[20] = {
    0xEE, 0xEE, 0xEE, 0x00, 0xEE, 0x60, 0xEE, 0xC0, 0x00, 0x00,
    0x30, 0x00, 0x20, 0xEE, 0x30, 0x50, 0x30, 0xEE, 0x00, 0x00};
// $131F. Reloaded into $5D. That is actor 2, the ninja. try_ninja at
// $0DE4 stores this byte.
constexpr uint8_t kNinjaReload[20] = {
    0xA0, 0xA0, 0xA0, 0x00, 0x70, 0x0C, 0x30, 0x18, 0x00, 0x00,
    0x0C, 0x00, 0x04, 0x08, 0x08, 0x08, 0x08, 0x08, 0x00, 0x00};
// $130B and $1347. The counts enter_room stores. They are not the reload
// tables, and test_visit does not touch them. $40 stores 3 over both, then
// a human opponent stores 8 over Yamo.
constexpr uint8_t kNinjaEnter[20] = {
    0x68, 0x78, 0x78, 0x00, 0x70, 0x18, 0x30, 0x50, 0x00, 0x00,
    0x08, 0x00, 0x04, 0x12, 0x08, 0x08, 0x08, 0x12, 0x00, 0x00};
constexpr uint8_t kYamoEnter[20] = {
    0xF0, 0xEE, 0xEE, 0x00, 0xC0, 0xC0, 0xA0, 0xB0, 0x00, 0x00,
    0x30, 0x00, 0x20, 0xC0, 0x20, 0x30, 0x20, 0xC0, 0x00, 0x00};
// $136F for the Ninja. $1333 is Yamo's first test; the sign still comes from $136F.
constexpr uint8_t kNinjaFlag[20] = {
    0x80, 0x80, 0x00, 0x00, 0x80, 0x02, 0x00, 0x80, 0x00, 0x00,
    0x80, 0x00, 0x80, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00};
constexpr uint8_t kYamoFlag[20] = {
    0x02, 0x02, 0x00, 0x00, 0x80, 0x80, 0x02, 0x02, 0x00, 0x00,
    0x02, 0x00, 0x80, 0x00, 0x02, 0x00, 0x80, 0x00, 0x00, 0x00};
constexpr uint8_t kMainX[20] = {
    0x1A, 0x18, 0x30, 0x20, 0x94, 0x22, 0x86, 0x1C, 0x14, 0x12,
    0x34, 0x40, 0x18, 0x98, 0x18, 0x1C, 0x18, 0x18, 0x18, 0x12};
constexpr uint8_t kMainY[20] = {
    0xC4, 0x62, 0xC4, 0xC0, 0xB4, 0x51, 0xB3, 0x44, 0x46, 0xC6,
    0x8C, 0x4C, 0x5C, 0x32, 0x5C, 0xC3, 0x5C, 0xB4, 0xC6, 0x95};
constexpr uint8_t kAltX[20] = {
    0x9F, 0x95, 0x96, 0x38, 0x96, 0x28, 0x81, 0x1F, 0x00, 0x00,
    0x96, 0x00, 0x70, 0x00, 0x92, 0x7A, 0x81, 0x00, 0x00, 0x00};
constexpr uint8_t kAltY[20] = {
    0x62, 0x92, 0xC4, 0xC4, 0xB4, 0xC2, 0x72, 0x74, 0x00, 0x00,
    0x5C, 0x00, 0x5C, 0x00, 0xBE, 0xC4, 0x8E, 0x00, 0x00, 0x00};
// $4C9E, copied into $7A when the room opens. A nonzero byte holds for the
// whole stay: the wake counts do not move, neither fighter is tried, the
// opponent-idle count freezes, and read_sprite_hits is skipped. Rooms 3, 8,
// 9, 11, 13, 17, 18, and 19. The enter delays are still stored.
constexpr uint8_t kHoldOff[20] = {
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF,
    0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF};

bool HoldOff() {
    const int room = g.roomId;
    return room >= 0 && room < 20 && kHoldOff[room] != 0;
}

// $5C33 for the Ninja's libraries. Poses 16, 18, and 33 swap the planes.
int NinjaInk(int pose, int plane) {
    const bool swap = pose == 16 || pose == 18 || pose == kPoseKnockLeft1;
    if (swap) {
        return plane == 0 ? 0 : 5;
    }
    return plane == 0 ? 5 : 0;
}

struct Fighter {
    int kind = 0;
    bool on = false;
    // Set once he has been in the room. Until then flicker_lamps must keep
    // the snapshot bytes instead of the default facing.
    bool placed = false;
    int delay = 0;
    int x = 0;
    int y = 0;
    int facing = 1;
    int pose = 0;
    int action = 0;
    int actionTimer = 0;
    int health = 0;
    int step = 0;
    int carryDelay = 0;  // $AD. Counts down between his own steps on the ladder.
    int carryMark = 0;   // $AA. Set while state $17 runs. A step shifts it to 0.
    int repeat = 6;      // $CB. A walk burst is two xpos, or three once this hits 0.
    int prevAction = 0;  // $C2. The state release_hold saw last frame.
    int hold = 0;        // $0106. A human climb waits 3, a duck waits 1.
    int fallSlide = 0;   // $B0. One sideways nudge on the second falling frame.
    int groundHit = 0;   // $B6,X. Stays until the next overlap. An actor who is off is not probed.
    // spawn_ninja stores library $82 for the overlap that runs before
    // choose_pose. Cleared once that overlap has been captured.
    bool spawnMask = false;
    // $8A,X / $8C,X / $8E,X. finish_exit stores Bruce's arrival and this
    // fighter's health when he was in the room. The next wake uses it once.
    bool resume = false;
    int resumeX = 0;
    int resumeY = 0;
    int resumeHealth = 0;
    int hist[kStepGens][4] = {};
    const uint8_t* frames = nullptr;
};

std::vector<uint8_t> ninjaBytes;
std::vector<uint8_t> yamoBytes;
// The same pictures as overlap_actors scans them. tools/extract_pictures.py
// writes both sets from the original libraries.
std::vector<uint8_t> bruceScan;
std::vector<uint8_t> ninjaScan;
std::vector<uint8_t> yamoScan;
Fighter ninja;
Fighter yamo;

// wake_actor rolls the seeded active byte three times. Carry in is clear:
// play_sound returns before the LDA that passes $80 or $40, and the trace
// of that roll is Y = 2 for Yamo.
int WakeIndex(int seeded) {
    int a = seeded | 1;
    int carry = 0;
    for (int i = 0; i < 3; ++i) {
        const int next = (a >> 7) & 1;
        a = ((a << 1) | carry) & 0xFF;
        carry = next;
    }
    return a & 3;
}

int XposOf(int x) {
    return (x + 24) / 2;
}

int YposOf(int y) {
    return y + 21;
}

// $2DDD. Bit 7 is the sign. The magnitude stops at $30.
int Packed(int mine, int his) {
    int d = mine - his;
    const bool neg = d < 0;
    if (neg) {
        d = -d;
    }
    if (d > 0x30) {
        d = 0x30;
    }
    return neg ? (d | 0x80) : d;
}

// range_to_bruce. The last fighter who measures this frame leaves $62 and $63.
void NoteRange(const Fighter& f) {
    NoisePoke(0x62, Packed(YposOf(f.y), YposOf(g.y)));
    NoisePoke(0x63, Packed(XposOf(f.x), XposOf(g.x)));
}

void Bind(const Fighter& f) {
    // Kind 2 is the ninja. His second library is not in the overlap picture.
    SetActorView(f.frames, f.action, f.facing, f.pose, f.kind != 2);
}

// The overlap from the start of the frame. scan_specials and the step both
// read it, so a tile the scan replaces is not what push_out tests.
struct FrameHit {
    bool valid = false;
    Contact full;
    Contact upper;
};

FrameHit frameHit[3];
bool spriteShown[3] = {true, false, false};

void CaptureOne(int kind, const uint8_t* frames, int action, int facing, int pose, int x, int y) {
    if (frames == nullptr) {
        return;
    }
    SetActorView(frames, action, facing, pose, kind != 2);
    frameHit[kind].full = Probe(x, y);
    frameHit[kind].upper = ProbeUpper(x, y);
    frameHit[kind].valid = true;
    ClearActorView();
}

// scan_row stores every nonzero AND at $4E. X runs from 2 down to 0, so
// Bruce's last byte wins when he touches anything. A miss leaves the
// earlier actor's byte, or whatever the previous frame left.
void StampOverlap(int kind, const uint8_t* frames, int action, int facing, int pose, int x, int y) {
    if (frames == nullptr) {
        return;
    }
    SetActorView(frames, action, facing, pose, kind != 2);
    Probe(x, y);
    const int byte = LastOverlapAnd();
    ClearActorView();
    if (byte >= 0) {
        NoisePoke(0x4E, byte);
    }
}

Contact At(const Fighter& f) {
    if (f.kind >= 0 && f.kind < 3 && frameHit[f.kind].valid) {
        return frameHit[f.kind].full;
    }
    Bind(f);
    const Contact hit = Probe(f.x, f.y);
    ClearActorView();
    return hit;
}

bool StepX(Fighter& f, int dir) {
    if (dir < 0) {
        if (f.x < kMinX) {
            return false;
        }
        f.x -= 2;
        f.hist[0][kStepLeft] += 1;
    } else {
        if (f.x >= kMaxX) {
            return false;
        }
        f.x += 2;
        f.hist[0][kStepRight] += 1;
    }
    f.facing = dir;
    return true;
}

bool StepY(Fighter& f, int dir) {
    if (dir < 0) {
        // move_up refuses ypos below $2E. ypos $2E itself still steps.
        if (f.y < kMinY) {
            return false;
        }
        f.y -= 1;
        f.hist[0][kStepUp] += 1;
    } else {
        if (f.y >= kMaxY) {
            return false;
        }
        f.y += 1;
        f.hist[0][kStepDown] += 1;
    }
    return true;
}

// clear_state. A refused step leaves the fighter idle and the rest of the
// burst does not run.
void ClearFighter(Fighter& f) {
    f.action = 0;
    f.actionTimer = 0;
    f.hold = 0;
}

// $1C77. A frame that stepped shifts the counters into the older slots.
// A frame that did not leaves those slots where they are.
void RememberSteps(Fighter& f) {
    bool any = false;
    for (int d = 0; d < 4; ++d) {
        if (f.hist[0][d] != 0) {
            any = true;
        }
    }
    if (any) {
        for (int gen = kStepGens - 1; gen > 0; --gen) {
            for (int d = 0; d < 4; ++d) {
                f.hist[gen][d] = f.hist[gen - 1][d];
            }
        }
        // Same $FF the copy loop leaves. Later actors who do not shift
        // keep it, which is what X = 2, 1, 0 does.
        NoisePoke(0x4E, 0xFF);
    }
    for (int d = 0; d < 4; ++d) {
        f.hist[0][d] = 0;
    }
}

bool OlderSteps(const Fighter& f) {
    for (int gen = 1; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            if (f.hist[gen][d] != 0) {
                return true;
            }
        }
    }
    return false;
}

void SlideAfterPush(Fighter& f) {
    int next[kStepGens][4] = {};
    for (int gen = 0; gen <= 8; ++gen) {
        for (int d = 0; d < 4; ++d) {
            next[gen][d] = f.hist[gen + 2][d];
        }
    }
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            f.hist[gen][d] = next[gen][d];
        }
    }
    NoisePoke(0x4E, 0xFF);
}

// $1CC7. The steps that put him in the wall are walked back: up by moving
// down, down by moving up, left by moving right, right by moving left.
// $85 shifts on up and sideways, not on down. Still set, and $C2 is not
// the duck, tries the next generation. The slide clears the hold, and the
// extra step is a walk, so state $18 starts with no pose hold.
// The count drops before the step, including the one the edge refuses.
// That refusal returns to this direction's loop. The slide still drops
// the generation, and mark_stuck still stores $18.
bool UndoOne(Fighter& f, int& count, int kind) {
    if (count <= 0) {
        return true;
    }
    count -= 1;
    bool moved = false;
    if (kind == kStepUp) {
        moved = StepY(f, 1);
        if (moved) {
            f.action = kClimbDown;
        }
    } else if (kind == kStepDown) {
        moved = StepY(f, -1);
        if (moved) {
            f.action = kClimbUp;
        }
    } else if (kind == kStepLeft) {
        moved = StepX(f, 1);
        if (moved) {
            f.action = kWalkRight;
        }
    } else {
        moved = StepX(f, -1);
        if (moved) {
            f.action = kWalkLeft;
        }
    }
    if (moved) {
        return true;
    }
    f.action = 0;
    f.actionTimer = 0;
    f.hold = 0;
    return false;
}

void UndoAll(Fighter& f, int kind) {
    int& count = f.hist[1][kind];
    while (count > 0) {
        UndoOne(f, count, kind);
    }
}

void PushOut(Fighter& f, const Contact& here) {
    int tries = 8;
    for (;;) {
        const int up = f.hist[1][kStepUp];
        const int left = f.hist[1][kStepLeft];
        const int right = f.hist[1][kStepRight];
        const bool keepGoing = up == 0 && left == 0 && right == 0;
        // $C2 is still the state from the start of this generation.
        const bool wasDuck = f.action == kDuck;
        UndoAll(f, kStepUp);
        UndoAll(f, kStepDown);
        UndoAll(f, kStepLeft);
        UndoAll(f, kStepRight);
        SlideAfterPush(f);
        f.hold = 0;
        tries -= 1;
        if (tries < 0 || here.ladder) {
            break;
        }
        if (keepGoing && !wasDuck) {
            RememberSteps(f);
            continue;
        }
        if (tries != 7) {
            // A refused nudge is clear_state, then JMP mark_stuck.
            StepX(f, f.facing < 0 ? 1 : -1);
        }
        break;
    }
    f.action = kStuck;
    f.actionTimer = 0x40;
}

void BeginFall(Fighter& f) {
    // L_1DC4, for every actor. One pixel, $B0 = 2, then state $0E.
    // X other than Bruce never reads $B0 on the frames after this.
    f.fallSlide = 2;
    NoisePoke(0xB0 + f.kind, 2);
    // A refused drop returns from clear_state into the set_state, so the
    // fall is stored at the bottom edge too.
    if (f.y < kMaxY) {
        f.y += 1;
        f.hist[0][kStepDown] += 1;
    }
    f.action = kFall;
    f.actionTimer = 0;
    f.hold = 0;
}

void ContinueFall(Fighter& f) {
    // X != 0. Supported: one xpos toward facing, and that move_left or
    // move_right stores the walk. Open air: two pixels down. Bruce's
    // upper-body nudge is not this path.
    const Contact here = At(f);
    if (here.ground || here.ladder) {
        const int dir = f.facing < 0 ? -1 : 1;
        const int x0 = f.x;
        StepX(f, dir);
        if (f.x == x0) {
            f.action = 0;
            f.actionTimer = 0;
            f.hold = 0;
            return;
        }
        f.action = dir < 0 ? kWalkLeft : kWalkRight;
        f.actionTimer = 0;
        f.hold = 0;
        return;
    }
    // Both drops are tried. A refused one returns, and state $0E is stored
    // after them either way.
    if (f.y < kMaxY) {
        f.y += 1;
        f.hist[0][kStepDown] += 1;
    }
    if (f.y < kMaxY) {
        f.y += 1;
        f.hist[0][kStepDown] += 1;
    }
    f.action = kFall;
    f.actionTimer = 0;
    f.hold = 0;
}

// L_1E6D and L_1EAE. Two xpos. The stick walk's third step is the entry
// before these labels, and the chase does not take it. keep_chase then
// cancels the timer decrement.
bool WalkBurst(Fighter& f) {
    // chase_walk and the sidestep enter at $1E6D and $1EAE. That is two
    // steps, past the extra one the stick walk takes when $CB is 0.
    // A refused step returns. keep_state still stores the chase or the
    // sidestep, so the edge does not end it.
    const int dir = f.facing < 0 ? -1 : 1;
    StepX(f, dir);
    StepX(f, dir);
    return true;
}

void StartSidestep(Fighter& f, int dx) {
    // $2327. Both positions are bytes. Subtracting $0F that lands on 0 falls
    // through into the add, so the target is $0F rather than 0.
    int dest = XposOf(g.x) & 0xFF;
    if (dx & 0x80) {
        dest = (dest - 0x0F) & 0xFF;
        if (dest == 0) {
            dest = 0x0F;
        }
    } else {
        dest = (dest + 0x0F) & 0xFF;
    }
    const int xpos = XposOf(f.x) & 0xFF;
    int dist = (dest - xpos) & 0xFF;
    if (xpos > dest) {
        dist = (-dist) & 0xFF;
    }
    if (dist < 5) {
        dist = 5;
    }
    f.action = 0x15;
    f.actionTimer = dist;
    f.hold = 0;
}

void Chase(Fighter& f) {
    const Contact here = At(f);
    if (!here.ground) {
        if (here.ladder) {
            if (WalkBurst(f)) {
                f.action = 0x14;
            }
            return;
        }
        BeginFall(f);
        return;
    }
    NoteRange(f);
    const int dy = Packed(YposOf(f.y), YposOf(g.y));
    const int dx = Packed(XposOf(f.x), XposOf(g.x));
    const int adx = dx & 0x7F;
    if ((dy & 0x7F) >= 0x10) {
        if (dy & 0x80) {
            if (WalkBurst(f)) {
                f.action = 0x14;
            }
            return;
        }
        // face_from_dx, then stand_down. The 6 is shortened once the visit
        // is no longer short, and $40 does that on a short visit too.
        f.facing = (dx & 0x80) ? 1 : -1;
        f.action = 0;
        f.actionTimer = StandTimer(false);
        f.hold = 0;
        return;
    }
    int faceTest = f.facing < 0 ? 0 : 1;
    if ((dx & 0x80) == 0) {
        faceTest ^= 1;
    }
    if (faceTest != 1) {
        if (adx >= 0x21) {
            f.facing = f.facing < 0 ? 1 : -1;
            if (WalkBurst(f)) {
                f.action = 0x14;
            }
            return;
        }
        StartSidestep(f, dx);
        return;
    }
    if (f.kind == 1) {
        if (adx < 5) {
            StartSidestep(f, dx);
            return;
        }
        if (adx < 0x0C) {
            // L_1F7E. A ladder is clear_state, and the chase then sees that
            // the punch did not start, so stand_down runs on this same frame.
            if (here.ladder) {
                f.action = 0;
                f.actionTimer = StandTimer(false);
                f.hold = 0;
                return;
            }
            f.action = kPunch;
            f.actionTimer = 4;
            return;
        }
        if (adx < 0x13) {
            f.action = f.facing < 0 ? kFlyLeft : kFlyRight;
            f.actionTimer = 0x0C;
            f.hold = 0;
            return;
        }
    } else if (adx >= 0x0B) {
        if (WalkBurst(f)) {
            f.action = 0x14;
        }
        return;
    } else if (adx < 5) {
        StartSidestep(f, dx);
        return;
    } else {
        f.action = 0x16;
        f.actionTimer = 0x13;
        return;
    }
    if (WalkBurst(f)) {
        f.action = 0x14;
    }
}

// move_for_state copies the timer into $52. keep_state decrements that
// byte and writes it back. A state that stores a new timer leaves $52.
void EnterMove(const Fighter& f) {
    NoisePoke(0x52, f.actionTimer & 0xFF);
}

void KeepTimer(Fighter& f) {
    f.actionTimer -= 1;
    NoisePoke(0x52, f.actionTimer & 0xFF);
}

void Sidestep(Fighter& f) {
    const Contact here = At(f);
    // $23D1. Bit 0 only. A ladder without a floor is a fall.
    if (!here.ground) {
        BeginFall(f);
        return;
    }
    if (f.actionTimer <= 1) {
        f.facing = f.facing < 0 ? 1 : -1;
        f.action = 0x14;
        f.actionTimer = 0x80;
        return;
    }
    if (!WalkBurst(f)) {
        return;
    }
    f.action = 0x15;
    KeepTimer(f);
}

void RecoverKick(Fighter& f) {
    // land at $2504. State 0 and timer 0. The $18 stand is enemy_turn on
    // the next frame, and only while he is still on the ground or a ladder.
    f.action = 0;
    f.actionTimer = 0;
    f.hold = 0;
}

void Fly(Fighter& f) {
    const Contact here = At(f);
    const int t = f.actionTimer;
    if (here.ladder || here.wall) {
        RecoverKick(f);
        return;
    }
    // $2058 and $209D. Shared with Bruce. Timer $0C is the first kick frame.
    if (t == 0x0C) {
        PlayEffect(0x84);
    }
    const int dir = f.action == kFlyLeft ? -1 : 1;
    // The edge returns to the next step. keep_state leaves the kick running.
    if (t >= 0x0A) {
        StepY(f, -1);
        StepX(f, dir);
    } else if (t >= 3) {
        StepX(f, dir);
    } else if (here.ground) {
        RecoverKick(f);
        return;
    } else {
        StepY(f, 1);
        StepX(f, dir);
    }
    // The last count stays in the kick. Timer 0 is on_ground or a fall,
    // on the next frame, and that is what leaves $C2 as the kick.
    KeepTimer(f);
}

void Punch(Fighter& f) {
    const Contact here = At(f);
    // $2270. A wall or a ladder is land, timer 0. Timer 1 is $228C: state 0
    // and a 6-frame stand, and only while the floor or a ladder is there.
    // A ladder or a wall is land, timer 0. Timer 1 is stand_down: state 0
    // and timer 6. That stand does not ask whether he is on the floor.
    if (here.ladder || here.wall) {
        f.action = 0;
        f.actionTimer = 0;
        return;
    }
    if (f.actionTimer <= 1) {
        f.action = 0;
        f.actionTimer = StandTimer(false);
        f.hold = 0;
        return;
    }
    KeepTimer(f);
}

void Flinch(Fighter& f) {
    // $2415. Under 2 the stand from $228C runs, timer 6.
    if (f.actionTimer < 2) {
        f.action = 0;
        f.actionTimer = StandTimer(false);
        f.hold = 0;
        return;
    }
    const int face = f.facing;
    const int back = face < 0 ? 1 : -1;
    // Both steps are tried. The edge returns, facing is restored, and
    // keep_state leaves the flinch running.
    StepX(f, back);
    StepX(f, back);
    f.facing = face;
    f.action = kFlinch;
    KeepTimer(f);
}

void Knock(Fighter& f) {
    // $244B. A living fighter leaves once the timer is under 2. Negative
    // health stays here until the count is gone, which is the knockdown.
    if (f.health >= 0 && f.actionTimer < 2) {
        f.action = 0;
        f.actionTimer = StandTimer(false);
        f.hold = 0;
        return;
    }
    if (f.actionTimer <= 0) {
        f.action = 0;
        return;
    }
    const Contact here = At(f);
    if (!here.ground && !here.ladder) {
        // A refused drop returns into the slide.
        StepY(f, 1);
    }
    const int face = f.facing;
    const int back = face < 0 ? 1 : -1;
    // $2462. The ninja, and only on count $0A, is thrown further. Eight
    // steps facing right, four facing left, then the two every knock takes.
    // A step into the screen edge returns. The rest still run.
    if (f.actionTimer == 0x0A && f.kind == 2) {
        const int extra = back < 0 ? 8 : 4;
        for (int i = 0; i < extra; ++i) {
            StepX(f, back);
        }
    }
    StepX(f, back);
    StepX(f, back);
    f.facing = face;
    f.action = kKnock;
    KeepTimer(f);
    // check_bruce_down runs after the step. Timer 0 and negative health
    // retires him on this frame, not the one after.
    if (f.actionTimer <= 0 && f.health < 0) {
        Bury(f, true);
    }
}

void StompPose(Fighter& f) {
    if (f.actionTimer <= 0) {
        f.action = 0;
        return;
    }
    f.action = kStomp;
    KeepTimer(f);
    // State $1B is outside the $13/$19 guard. Negative health is spent
    // on this frame, after keep_state.
    if (f.health < 0) {
        Bury(f, true);
    }
}

void Appear(Fighter& f) {
    if (f.action == 0x10) {
        if (f.actionTimer <= 1) {
            // $225D. The frame that leaves state $10.
            PlayEffect(0x81);
            f.facing = f.x >= g.x ? -1 : 1;
            f.action = 0x12;
            f.actionTimer = 0x10;
            return;
        }
        KeepTimer(f);
        return;
    }
    // $240B. keep_state until the timer is 0. The next frame is on_ground.
    KeepTimer(f);
}

void Strike(Fighter& f) {
    const Contact here = At(f);
    // $22C1. Bit 3 cancels it. Timer 1 is the same 6-frame stand as a punch.
    // Bit 3 is land, timer 0. Timer 1 is stand_down, timer 6, with no
    // ground test. A shorter stand is why he used to strike again at once.
    // The other frames only add a step to the push counter. xpos stays put.
    if (here.wall) {
        f.action = 0;
        f.actionTimer = 0;
        return;
    }
    // $22D0. Yamo's strike, the frame whose timer is still $0C.
    if (f.actionTimer == 0x0C) {
        PlayEffect(0x85);
    }
    if (f.actionTimer <= 1) {
        f.action = 0;
        f.actionTimer = StandTimer(false);
        f.hold = 0;
        return;
    }
    f.hist[0][f.facing < 0 ? kStepLeft : kStepRight] += 1;
    KeepTimer(f);
}

void Idle(Fighter& f) {
    // State 0 with a timer is the stand after a punch, a kick, or a spawn.
    // move_for_state only counts it down. The fall waits until it is 0.
    if (f.actionTimer > 0) {
        KeepTimer(f);
        return;
    }
    const Contact here = At(f);
    if (!here.ground && !here.ladder) {
        BeginFall(f);
        return;
    }
    if (f.action != 0) {
        // Stick $0F is clear_state. A walk left by the fall is this case.
        // enemy_turn arms the chase on the next frame, once the state is 0.
        f.action = 0;
        f.actionTimer = 0;
        f.hold = 0;
        return;
    }
    f.action = 0x14;
    f.actionTimer = 0x14;
    Chase(f);
}

// Hot tiles from match_special. $57 is the nozzle's neighbor and is not hot.
// $66 shocks only from room 10 on. Room 18's spark is a different path.
bool HotTile(int tile) {
    const bool late = g.roomId >= 10 && tile == 0x66;
    const bool span = tile >= 0x54 && tile <= 0x5A && tile != 0x57;
    return tile == 0x0F || tile == 0x40 || tile == 0x64 || late || span ||
        (tile >= 0x71 && tile <= 0x7C);
}

// $2E39 for one fighter. State $19 is skipped. State $17 is cleared first,
// then the same 3 by 2 window Bruce uses. A door retires him and the rest
// of his window is not read. A hot tile retires him and the window goes on,
// so a later nozzle can still crumble. Tile $62 puts the ladder ride back.
void ScanFighterTiles(Fighter& f) {
    if (!f.on || f.action == kZap) {
        return;
    }
    if (f.action == kCarry) {
        f.action = 0;
        f.actionTimer = 0;
        f.hold = 0;
    }
    const int xpos = XposOf(f.x);
    const int ypos = YposOf(f.y);
    int rowY = ypos;
    if (g.roomId == 0x0D) {
        rowY += 4;
    }
    if (rowY < 0x0C) {
        return;
    }
    const Contact pose = At(f);
    // $1C3C subtracts $0C as a byte. xpos $0B becomes column $3F.
    const int col0 = ((xpos - 0x0C) & 0xFF) >> 2;
    const int row0 = (rowY - 0x0C) >> 4;
    // $1C40 stores the column. $2E63 increments the row after the first pass.
    NoteScanCell(f.kind, col0, row0);
    const bool left = f.hist[0][kStepLeft] != 0;
    const bool right = f.hist[0][kStepRight] != 0;
    const bool up = f.hist[0][kStepUp] != 0;
    const bool falling = f.action == kFall;
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
                if (ExitClaims(tile, xpos, ypos, left, right, up, falling)) {
                    NotePrizeGate(pose.bit1, shifts);
                    Bury(f);
                    return;
                }
                continue;
            }
            if (tile != 0x62 && tile != 0x2D && tile != 0x2E) {
                shifts += 1;
            }
            if (tile == 0x62 && pose.ladder && f.action != kZap) {
                f.action = kCarry;
                f.actionTimer = 0x10;
                f.hold = 0;
                f.carryMark = 0;
            }
            if (!pose.bit1) {
                continue;
            }
            if (HotTile(tile) && g.roomId != 18) {
                PlayEffect(0x8C);
                Bury(f);
                continue;
            }
            if (tile == 0x60) {
                ArmCrumble(col, row);
            }
        }
        if (dr == 0) {
            NoteScanCell(f.kind, col0, row0 + 1);
        }
    }
    NotePrizeGate(pose.bit1, shifts);
}

// $2187. Bit 2 clear leaves the ladder. A computer fighter's stick is the way
// he is facing, right $07 or left $0B, and that step waits on $AD. $60 == 1
// then moves him two pixels with the surface, up when $65 is clear.
void CarryFighter(Fighter& f) {
    // Bit 2 was already required to get here, from the overlap before the
    // move. $1CC7, not this routine, deals with a wall. choose_pose reads
    // $AA after this and flips libraries $0A and $0C only when a step
    // shifted it back to 0.
    f.carryMark = 1;
    const int dir = f.facing < 0 ? -1 : 1;
    // $2191. Facing replaces the stick only when $42CA is clear. While a
    // human opponent is on, this fighter's stick stays the $0F the ride
    // stored, so he takes no step of his own. The surface shove still runs.
    const bool ownStep = !(gHumanOpponent && !gOpponentYielded);
    if (f.carryDelay > 0) {
        f.carryDelay -= 1;
    } else if (ownStep) {
        StepX(f, dir);
        StepX(f, dir);
        // $21EB. The same blip as Bruce's own step on the ladder.
        PlayEffect(0x80);
        f.carryMark >>= 1;
        f.carryDelay = 4;
    }
    const int shove = SurfaceShove();
    if (shove < 0) {
        StepY(f, -1);
        StepY(f, -1);
    } else if (shove > 0) {
        StepY(f, 1);
        StepY(f, 1);
    }
    // $2211. Up and down of this ride cancel. The scan reads what is left.
    const int up = f.hist[0][kStepUp];
    const int down = f.hist[0][kStepDown];
    if (up >= down) {
        f.hist[0][kStepUp] = up - down;
        f.hist[0][kStepDown] = 0;
    } else {
        f.hist[0][kStepDown] = down - up;
        f.hist[0][kStepUp] = 0;
    }
    f.action = kCarry;
}

void Act(Fighter& f) {
    // Timer 0 with the kick still showing. $C2 is the kick, so this is not
    // the fall continuation. Stick $0F clears him when the floor or a ladder
    // is there. Open air is the one-pixel fall.
    if ((f.action == kFlyLeft || f.action == kFlyRight) && f.actionTimer <= 0) {
        const Contact here = At(f);
        if (here.ground || here.ladder) {
            f.action = 0;
            f.actionTimer = 0;
            f.hold = 0;
        } else {
            BeginFall(f);
        }
        return;
    }
    // State $12 has counted out. Timer 0 skips the mover, so this is
    // on_ground: stick $0F clears him, and open air is the one-pixel fall.
    if (f.action == 0x12 && f.actionTimer <= 0) {
        const Contact here = At(f);
        if (here.ground || here.ladder) {
            f.action = 0;
            f.actionTimer = 0;
            f.hold = 0;
        } else {
            BeginFall(f);
        }
        return;
    }
    if (f.actionTimer > 0 && f.action != 0 && f.action != kFall) {
        EnterMove(f);
        switch (f.action) {
        case kFlyLeft:
        case kFlyRight:
            Fly(f);
            break;
        case kPunch:
            Punch(f);
            break;
        case kFlinch:
            Flinch(f);
            break;
        case kKnock:
            Knock(f);
            break;
        case kStomp:
            StompPose(f);
            break;
        case 0x10:
        case 0x12:
            Appear(f);
            break;
        case 0x14:
            Chase(f);
            break;
        case 0x15:
            Sidestep(f);
            break;
        case 0x16:
            Strike(f);
            break;
        default:
            KeepTimer(f);
            break;
        }
        return;
    }
    if (f.action == kFall) {
        ContinueFall(f);
        return;
    }
    Idle(f);
}

// $0E/$10 facing left, $12/$14 facing right. The picture already showing
// decides which one. Anything else starts at the first of the pair.
void WalkPicture(Fighter& f) {
    if (f.facing < 0) {
        f.pose = f.pose == 2 ? 3 : 2;
    } else {
        f.pose = f.pose == 4 ? 5 : 4;
    }
}

// flip_climb. Library $0A is showing, so the next one is $0C. Any other
// picture becomes $0A.
void FlipClimb(Fighter& f) {
    f.pose = f.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
}

void Choose(Fighter& f, const Contact& here) {
    const int t = f.actionTimer;
    if (f.action == kPunch) {
        f.pose = f.facing < 0 ? kPosePunchLeft : kPosePunchRight;
    } else if (f.action == kFlyLeft || f.action == kFlyRight) {
        const bool tucked = t >= 0x0A;
        f.pose = f.action == kFlyLeft ? (tucked ? 15 : 16) : (tucked ? 17 : 18);
    } else if (f.action == kFall) {
        // Library $44 in the air, library 8 in a wall. Yamo's $44 is the
        // legs picture. The ninja's $44 is pose 8 in his file.
        const int air = f.kind == 1 ? kPoseLegs : kPoseArms;
        f.pose = here.wall ? kPoseLegs : air;
    } else if (f.action == 0x10) {
        f.pose = kPoseSpawn;
    } else if (f.action == 0x12) {
        f.pose = f.facing < 0 ? kPoseAppearLeft : kPoseAppearRight;
    } else if (f.action == 0x16) {
        const bool early = t >= 0x0B;
        if (f.facing < 0) {
            f.pose = early ? kPoseStrikeLeft0 : kPoseStrikeLeft1;
        } else {
            f.pose = early ? kPoseStrikeRight0 : kPoseStrikeRight1;
        }
    } else if (f.action == kFlinch) {
        // $2879. State $0F is the stand picture. A ladder does not change it.
        f.pose = f.facing < 0 ? 1 : 0;
    } else if (f.action == kKnock || f.action == kStomp) {
        const bool early = f.action == kKnock ? t >= 0x0A : t >= 4;
        if (f.facing < 0) {
            f.pose = early ? kPoseKnockLeft0 : kPoseKnockLeft1;
        } else {
            f.pose = early ? kPoseKnockRight0 : kPoseKnockRight1;
        }
    } else if (f.action == kStuck) {
        // $27C1. The picture stays. Library $44 and a nonzero mode byte
        // become library 8. The jump, library $20, stays.
        if (StuckUsesLegs(f.kind, f.pose)) {
            f.pose = kPoseLegs;
        }
    } else if (f.action == kCarry) {
        // $2962. $AA still set keeps the picture already showing. Cleared,
        // the picture becomes $0A, or $0C when it was already $0A.
        if (f.carryMark == 0) {
            f.pose = f.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
        }
    } else if (f.action == 0x14 || f.action == 0x15 || f.action == kWalkLeft || f.action == kWalkRight) {
        // States 3, 4, $14, and $15. The ladder bit is the overlap from
        // before this step, so leaving a ladder still shows the climb.
        if (here.ladder) {
            FlipClimb(f);
        } else {
            WalkPicture(f);
        }
    } else if (f.action == kClimbUp || f.action == kClimbDown) {
        FlipClimb(f);
    } else if (f.action == 0 && here.ladder) {
        // pose_stand keeps $0A or $0C. Another picture becomes $0A.
        if (f.pose != kPoseClimb0 && f.pose != kPoseClimb1) {
            f.pose = kPoseClimb0;
        }
    } else {
        f.pose = f.facing < 0 ? 1 : 0;
    }
}

bool UseAlt(uint8_t flag, int index) {
    // $0C09. A zero flag, or a noise byte at $C0 or above, picks a side at random.
    // Otherwise bit 7 selects the alternate spawn.
    if (flag != 0 && NoiseByte(index) < 0xC0) {
        return (flag & 0x80) != 0;
    }
    return (NoiseByte(index) & 1) != 0;
}

bool AltSpawn(int kind) {
    const int room = g.roomId;
    const int index = WakeIndex(kind == 1 ? 0x80 : 0x40);
    // The ninja reads $1333 first. Zero, or a noise byte at $C0 or above, is a
    // coin toss. Otherwise the sign of $136F picks the spawn. Yamo reads $136F.
    if (kind == 2) {
        if (kYamoFlag[room] == 0 || NoiseByte(index) >= 0xC0) {
            return (NoiseByte(index) & 1) != 0;
        }
        return (kNinjaFlag[room] & 0x80) != 0;
    }
    return UseAlt(kNinjaFlag[room], index);
}

void Wake(Fighter& f) {
    // $10BA. Both spawns.
    PlayEffect(0x82);
    // wake_actor stores A|$01 into $95,X and 1 into $B6,X before the
    // side pick reads ($16),Y. Yamo's A is $80, so $96 becomes $81.
    if (f.kind == 1) {
        NoisePoke(0x96, 0x81);
        NoisePoke(0xB7, 1);
        // $98,X is $0F and $9B,X is 1, both before the side pick. Yamo is X=1.
        NoisePoke(0x99, 0x0F);
        NoisePoke(0x9C, 1);
        // $59AA and $59AD, the Y=2 column, land in $ED and $F0.
        NoisePoke(0xED, 6);
        NoisePoke(0xF0, 7);
        f.groundHit = 1;
    } else {
        NoisePoke(0x97, 0x41);
        NoisePoke(0xB8, 1);
        // Actor 2's stick is $9A. The room-0 snapshot already holds $0F.
        NoisePoke(0x9A, 0x0F);
        NoisePoke(0x9D, 1);
        // $59A9 and $59AC, the Y=1 column, land in $EE and $F1.
        NoisePoke(0xEE, 3);
        NoisePoke(0xF1, 0);
        f.groundHit = 1;
    }
    const int room = g.roomId;
    // wake_actor stores $24, then a nonzero $8A,X overwrites the position
    // and the health and clears that byte. A fresh spawn keeps $24.
    f.health = 0x24;
    f.facing = 1;
    if (f.resume) {
        f.x = f.resumeX;
        f.y = f.resumeY;
        f.health = f.resumeHealth;
        f.resume = false;
        // $0C49 clears the xpos byte it resumed from, so the next wake picks
        // a spawn side. Room 2's lamps later read 0 there, not Bruce's xpos.
        NoisePoke(0x8A + (f.kind == 1 ? 1 : 2), 0);
    } else {
        const bool alt = AltSpawn(f.kind);
        const int xpos = alt ? kAltX[room] : kMainX[room];
        const int ypos = alt ? kAltY[room] : kMainY[room];
        f.x = xpos * 2 - 24;
        f.y = ypos - 21;
    }
    f.pose = 0;
    f.step = 0;
    // wake_actor ($10BA) does not write $AD or $AA. The wait left by the
    // last ride is still there when he next catches tile $62.
    f.repeat = 6;
    f.prevAction = 0;
    f.hold = 0;
    f.fallSlide = 0;
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            f.hist[gen][d] = 0;
        }
    }
    f.on = true;
    f.placed = true;
    // The compare is unsigned. A health byte that has gone negative is above
    // the cap and comes back full. A wound that is still positive is kept.
    const int cap = f.kind == 1 ? 0x14 : 7;
    if ((f.health & 0xFF) >= cap) {
        f.health = cap;
    }
    if (f.kind == 1) {
        // $0CEA. State $10 is the materialize.
        f.action = 0x10;
        f.actionTimer = 0x0A;
        f.pose = kPoseSpawn;
    } else {
        // $0E17. He stands for $10 frames, facing Bruce.
        f.action = 0;
        f.actionTimer = 0x10;
        f.facing = f.x >= g.x ? -1 : 1;
        f.pose = f.facing < 0 ? 1 : 0;
        // $0E02. The overlap and the scan still see library $82. The stand
        // picture is stored by choose_pose, after both of those.
        f.spawnMask = true;
        // spawn_ninja measures Bruce before the step overwrites $62.
        NoteRange(f);
    }
}

int RoomDelay(int kind) {
    const int room = g.roomId;
    if (room < 0 || room >= 20) {
        return 0;
    }
    // Kind 1 is Yamo, and try_yamo reloads $135B. Kind 2 is the ninja,
    // and try_ninja reloads $131F.
    return kind == 1 ? kYamoReload[room] : kNinjaReload[room];
}

// Yamo is actor 1. The variable is named ninja because that is the file.
bool HumanYamo(const Fighter& f) {
    return f.kind == 1 && gHumanOpponent && !gOpponentYielded;
}

int OpenDelay(int kind) {
    const int room = g.roomId;
    if (room < 0 || room >= 20) {
        return 0;
    }
    const int table = kind == 1 ? kYamoEnter[room] : kNinjaEnter[room];
    return OpenWake(table, kind == 1 && HumanYamo(ninja));
}

void ArmDelay(Fighter& f) {
    // A human opponent reloads Yamo with $30, then test_visit still runs.
    // The room table is the computer. A long visit, or $40 on a short
    // visit, stores 3. A middle visit halves the byte.
    const int table = HumanYamo(f) ? 0x30 : RoomDelay(f.kind);
    f.delay = WakeDelay(table);
}

void Bury(Fighter& f, bool afterBlit) {
    // retire_actor ($3001) clears the active bit and reloads the wait.
    // The state and the timer are left as the step that retired him.
    // $96 is Yamo (kind 1). $97 is the ninja. Bit 0 drops, the rest stays,
    // and a later noise_byte can read that byte. After the blit, the Y
    // left in the voice slot is what the next frame's lamps index with.
    if (afterBlit) {
        NotePostBlitRetire(f.kind);
    }
    NoiseAnd(f.kind == 1 ? 0x96 : 0x97, 0xFE);
    f.on = false;
    f.spawnMask = false;
    ArmDelay(f);
}

void Spawn(Fighter& f) {
    if (f.on || f.frames == nullptr || f.delay > 0) {
        return;
    }
    Wake(f);
    ArmDelay(f);
}

struct Who {
    int kind = 0;
    Fighter* fighter = nullptr;
    int x = 0;
    int y = 0;
    int facing = 1;
    int action = 0;
    int timer = 0;
    int pose = 0;
    int health = 0;
    const uint8_t* frames = nullptr;
};

Who ReadBruce() {
    Who w;
    w.kind = 0;
    w.x = g.x;
    w.y = g.y;
    w.facing = g.facing;
    w.action = g.action;
    w.timer = g.actionTimer;
    w.pose = g.pose;
    w.health = g.health;
    w.frames = g.frames.data();
    return w;
}

Who ReadFighter(Fighter& f) {
    Who w;
    w.kind = f.kind;
    w.fighter = &f;
    w.x = f.x;
    w.y = f.y;
    w.facing = f.facing;
    w.action = f.action;
    w.timer = f.actionTimer;
    w.pose = f.pose;
    w.health = f.health;
    w.frames = f.frames;
    return w;
}

bool Pixel(const Who& w, int plane, int x, int y) {
    // The pose row is 32 screen pixels. Mode 1 uses all of them. Mode 0
    // uses the first 16, and the caller stops there. Rows at and past the
    // library height are cleared in the VIC sprite, so $D01E never sees them.
    if (!w.frames || x < 0 || y < 0 || x >= kSpriteCols || y >= SpriteRows(w.kind, w.pose, plane)) {
        return false;
    }
    const uint8_t* frame = w.frames + static_cast<size_t>(w.pose * 2 + plane) * kFrameBytes;
    return (frame[y * kSpriteRowBytes + x / 8] & static_cast<uint8_t>(0x80 >> (x & 7))) != 0;
}

// $25FD slides a left-facing mode-1 body. Bruce's copy of these libraries is
// mode 0, so PlaneShift leaves them put. The Ninja's extended kick and late
// knockdown, and three of Yamo's pictures, are mode 1.
// Bit 0 is plane 0 and bit 1 is plane 1, from $5CBF. Nonzero is the wide copy.
constexpr uint8_t kWidePlane[3][34] = {
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 0, 2, 0, 2, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2},
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 0, 3, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 3},
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1},
};

bool WidePlane(int kind, int pose, int plane) {
    if (kind < 0 || kind > 2 || pose < 0 || pose >= kFrames || plane < 0 || plane > 1) {
        return false;
    }
    return (kWidePlane[kind][pose] & (1 << plane)) != 0;
}

int PictureShift(int kind, int facing, int pose, int plane) {
    const int shift = PlaneShift(pose, plane);
    if (facing > 0) {
        return shift;
    }
    if (kind == 1 && plane == 0 && (pose == kPoseFlyLeftExtended || pose == kPoseKnockLeft1)) {
        return -16;
    }
    if (kind == 2 && plane == 0 &&
        (pose == kPoseStrikeLeft1 || pose == kPoseKnockLeft0 || pose == kPoseKnockLeft1)) {
        return -16;
    }
    return shift;
}

bool Covered(const Who& w, int sx, int sy) {
    // Actor 2 is the ninja. blit_sprites never copies his second image, so
    // $D01E cannot see that plane. The pose file already doubled each source
    // bit into one screen pixel. Mode 0 is the first 16. Mode 1 is both
    // source bytes, 32. Doubling those columns again reaches a step early.
    const int planes = w.kind == 2 ? 1 : 2;
    for (int plane = 0; plane < planes; ++plane) {
        const int columns = WidePlane(w.kind, w.pose, plane) ? kSpriteCols : kHardwareColumns;
        const int column = sx - (w.x + PictureShift(w.kind, w.facing, w.pose, plane));
        if (column < 0 || column >= columns) {
            continue;
        }
        const int y = sy - w.y;
        if (Pixel(w, plane, column, y)) {
            return true;
        }
    }
    return false;
}

bool PlaneCovers(const Who& w, int plane, int sx, int sy) {
    const int columns = WidePlane(w.kind, w.pose, plane) ? kSpriteCols : kHardwareColumns;
    const int column = sx - (w.x + PictureShift(w.kind, w.facing, w.pose, plane));
    if (column < 0 || column >= columns) {
        return false;
    }
    return Pixel(w, plane, column, sy - w.y);
}

bool PlanesTouch(const Who& a, int planeA, const Who& b, int planeB) {
    const int columns = WidePlane(a.kind, a.pose, planeA) ? kSpriteCols : kHardwareColumns;
    const int ox = a.x + PictureShift(a.kind, a.facing, a.pose, planeA);
    for (int y = 0; y < kSpriteRows; ++y) {
        for (int x = 0; x < columns; ++x) {
            if (!Pixel(a, planeA, x, y)) {
                continue;
            }
            if (PlaneCovers(b, planeB, ox + x, a.y + y)) {
                return true;
            }
        }
    }
    return false;
}

bool Touches(const Who& a, const Who& b) {
    const int planes = a.kind == 2 ? 1 : 2;
    for (int plane = 0; plane < planes; ++plane) {
        const int columns = WidePlane(a.kind, a.pose, plane) ? kSpriteCols : kHardwareColumns;
        const int ox = a.x + PictureShift(a.kind, a.facing, a.pose, plane);
        for (int y = 0; y < kSpriteRows; ++y) {
            for (int x = 0; x < columns; ++x) {
                if (!Pixel(a, plane, x, y)) {
                    continue;
                }
                if (Covered(b, ox + x, a.y + y)) {
                    return true;
                }
            }
        }
    }
    return false;
}

// $2C54. Positive means the victim is in front of the attacker. A negative
// distance, or one past $7F, is behind him or too far for this blow.
bool InFront(const Who& attacker, const Who& victim, int reach) {
    int d = XposOf(attacker.x) - XposOf(victim.x);
    if (attacker.facing > 0) {
        d = -d;
    }
    return d >= reach && d < 0x80;
}

bool Open(int action) {
    return action != kStuck && action != kDuck && action != kFlinch && action != kKnock &&
           action != kZap && action != kStomp;
}

// $BC for one actor. Bit 0 is a swing that connected. Bits 1, 2, 3, and 4 are
// the strike, the punch, the kick, and the landing he suffered. Bit 7 is set
// when actor 0 landed one of those last three, and every score test reads it.
struct HitByte {
    Who who;
    bool on = false;
    int bc = 0;
};

void FaceAway(HitByte& victim, const Who& attacker) {
    const int face = attacker.facing > 0 ? -1 : 1;
    victim.who.facing = face;
    if (victim.who.kind == 0) {
        g.facing = face;
    } else if (victim.who.fighter != nullptr) {
        victim.who.fighter->facing = face;
    }
}

// L_2B3E. The attacker leaves the swing. A landing does not come here, so a
// stomp does not turn him around or end his fall.
void MarkSwing(HitByte& attacker, HitByte& victim) {
    attacker.bc |= 0x01;
    FaceAway(victim, attacker.who);
}

// $2BF9. Bit 4 still set, so a killing punch or kick falls in here too.
// FixBugsInOriginal pays the 50 and the 5 once. The byte wrap is the bug.
void ApplyLanding(HitByte& victim) {
    if ((victim.bc & 0x10) == 0) {
        return;
    }
    const bool scored = (victim.bc & 0x80) != 0;
    if (gConfig.fixBugsInOriginal) {
        if (scored) {
            AddScoreByte(2, 0x32);
        }
        const int before = victim.who.health;
        victim.who.health -= 5;
        if (victim.who.health < 0) {
            victim.who.action = kKnock;
            victim.who.timer = 0x0C;
            if (scored && before >= 0 && victim.who.kind != 0) {
                AddKnockout(victim.who.kind);
            }
        } else {
            victim.who.action = kStomp;
            victim.who.timer = 8;
        }
        return;
    }
    victim.who.health = ApplyStomp(victim.who.health, victim.who.kind, scored);
    victim.who.action = kStomp;
    victim.who.timer = 8;
}

// $2C24. State $13 for $0C frames, then the landing test. Bit 4 clear
// returns. Bit 4 set is the loop that wraps a killing landing.
void ForceKnockdown(HitByte& victim) {
    if ((victim.bc & 0x80) != 0 && victim.who.kind != 0) {
        AddKnockout(victim.who.kind);
    }
    victim.who.action = kKnock;
    victim.who.timer = 0x0C;
    ApplyLanding(victim);
}

// $2B9A. Strike, punch, and kick, in that order. A negative health jumps to
// the knockdown and does not test the blows after the one that killed him.
// The landing test still runs, because that is where the jump lands.
void ApplyBlows(HitByte& victim) {
    if ((victim.bc & 0x02) != 0) {
        victim.who.health -= 2;
        if (victim.who.health < 0) {
            ForceKnockdown(victim);
            return;
        }
        victim.who.action = kFlinch;
        victim.who.timer = 3;
    }
    if ((victim.bc & 0x04) != 0) {
        if ((victim.bc & 0x80) != 0) {
            AddScoreByte(2, 0x64);
        }
        victim.who.health -= 3;
        if (victim.who.health < 0) {
            ForceKnockdown(victim);
            return;
        }
        victim.who.action = kFlinch;
        victim.who.timer = 4;
    }
    if ((victim.bc & 0x08) != 0) {
        if ((victim.bc & 0x80) != 0) {
            AddScoreByte(2, 0x4B);
        }
        victim.who.health -= 7;
        if (victim.who.health < 0) {
            ForceKnockdown(victim);
            return;
        }
        victim.who.action = kKnock;
        victim.who.timer = 0x0C;
    }
    ApplyLanding(victim);
}

void CommitHit(const HitByte& actor, int hold) {
    Who w = actor.who;
    if (w.kind == 0) {
        g.health = w.health;
        g.facing = w.facing;
        g.action = w.action;
        g.actionTimer = w.timer;
        if (hold >= 0) {
            g.hold = hold;
        }
        return;
    }
    if (w.fighter == nullptr) {
        return;
    }
    w.fighter->health = w.health;
    w.fighter->facing = w.facing;
    w.fighter->action = w.action;
    w.fighter->actionTimer = w.timer;
    if (hold >= 0) {
        w.fighter->hold = hold;
    }
}

int BlowOf(const Who& attacker, const Who& victim) {
    // $2A84, $2AA7, $2ADD. The reach is stored before the test, hit or miss.
    if (attacker.action == 0x16 && attacker.timer < 8) {
        NoisePoke(0x61, 4);
        if (InFront(attacker, victim, 4)) {
            return 2;
        }
    }
    if (attacker.action == kPunch) {
        NoisePoke(0x61, 6);
        if (InFront(attacker, victim, 6)) {
            const int dy = YposOf(attacker.y) - YposOf(victim.y);
            if (dy < 0x16 && dy > -0x16) {
                return 4;
            }
        }
    }
    if ((attacker.action == kFlyLeft || attacker.action == kFlyRight) && attacker.timer < 0x0A) {
        NoisePoke(0x61, 6);
        if (InFront(attacker, victim, 6)) {
            return 8;
        }
    }
    if (attacker.action == kFall) {
        // $2AFA. The compare is a byte. BMI reads the high bit of
        // (drop - $0A), so $0A through $89 connect and a longer fall does not.
        // A kick or a punch still spends the charge. That reject is after it.
        const int drop = (YposOf(victim.y) - YposOf(attacker.y)) & 0xFF;
        if (drop >= 0x0A && drop <= 0x89) {
            return 16;
        }
    }
    return 0;
}

// The picture read_sprite_hits tested on the previous logic frame. $D01E
// still holds one draw of it: blit_sprites writes the new pictures into the
// buffer that is not showing, and place_sprites does not publish that buffer
// until the raster IRQ has run. The pointer store at $2690 lands on raster
// $0A of the next screen, so the sprites are drawn once more from the old
// pointers. Keeping only that old hit drops a punch the new picture reaches.
struct HeldSprite {
    bool on = false;
    Who who{};
};

HeldSprite heldSprite[3];

void DropHeldSprites() {
    for (HeldSprite& held : heldSprite) {
        held.on = false;
    }
}

// $D01E. Bruce is sprites 0 and 1, Yamo is 2 and 3, the ninja is 4.
// A sprite's own two images set each other's bits when their pixels meet.
int SpriteHitMask(const HeldSprite* shown) {
    struct Spr {
        const Who* who;
        int plane;
        int bit;
    };
    Spr spr[5];
    int n = 0;
    for (int i = 0; i < 3; ++i) {
        if (!shown[i].on) {
            continue;
        }
        const Who& w = shown[i].who;
        const int base = w.kind == 0 ? 0 : w.kind == 1 ? 2 : 4;
        const int planes = w.kind == 2 ? 1 : 2;
        for (int plane = 0; plane < planes; ++plane) {
            spr[n].who = &w;
            spr[n].plane = plane;
            spr[n].bit = base + plane;
            n += 1;
        }
    }
    int mask = 0;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (!PlanesTouch(*spr[i].who, spr[i].plane, *spr[j].who, spr[j].plane)) {
                continue;
            }
            mask |= 1 << spr[i].bit;
            mask |= 1 << spr[j].bit;
        }
    }
    return mask;
}

void AddSpriteGroups(bool group[3], const HeldSprite* shown) {
    for (int i = 0; i < 3; ++i) {
        if (!shown[i].on) {
            continue;
        }
        // $D01E sets a sprite's bit when it touches any other sprite, including
        // the actor's own second image. The pair test only asks whether each
        // actor's bits are nonzero, so a kick connects with whoever else is
        // touching anything while the kicker's two images overlap.
        if (shown[i].who.kind != 2 && PlanesTouch(shown[i].who, 0, shown[i].who, 1)) {
            group[i] = true;
        }
        for (int j = i + 1; j < 3; ++j) {
            if (!shown[j].on || !Touches(shown[i].who, shown[j].who)) {
                continue;
            }
            group[i] = true;
            group[j] = true;
        }
    }
}

// $29C3 then $2B4E. The pictures already on screen decide the overlap. A
// swing that connects ends on the attacker: state 0, hold 4, and the
// recovery timer. The victim's blows are applied afterwards, and a killing
// one skips the blow tests that follow it. Two attackers can both land.
bool Resolve() {
    HitByte actor[3];
    actor[0].who = ReadBruce();
    actor[0].on = true;
    if (ninja.on && SpriteShown(1)) {
        actor[1].who = ReadFighter(ninja);
        actor[1].on = true;
    }
    if (yamo.on && SpriteShown(2)) {
        actor[2].who = ReadFighter(yamo);
        actor[2].on = true;
    }
    // $D01E sets a bit for each sprite that touched any other sprite. It does
    // not record which one. The three pair masks are the AND of those groups,
    // so two fighters who both touch the third count as touching each other.
    // The register is the OR of the picture still showing from last frame and
    // the picture chosen last tick. Pairs are taken after that OR, so a touch
    // against the third fighter counts across the two pictures.
    HeldSprite shown[3];
    for (int i = 0; i < 3; ++i) {
        shown[i].on = actor[i].on;
        if (actor[i].on) {
            shown[i].who = actor[i].who;
        }
    }
    bool group[3] = {};
    AddSpriteGroups(group, heldSprite);
    AddSpriteGroups(group, shown);
    // A zero register leaves $67 alone. The next noise_byte can still read it.
    const int d01e = SpriteHitMask(heldSprite) | SpriteHitMask(shown);
    if (d01e != 0) {
        NoisePoke(0x67, d01e);
    }
    for (int i = 0; i < 3; ++i) {
        heldSprite[i] = shown[i];
    }
    bool paired[3][3] = {};
    if (group[0] && group[1]) {
        paired[0][1] = paired[1][0] = true;
    }
    if (group[0] && group[2]) {
        paired[0][2] = paired[2][0] = true;
    }
    // A nonzero $D01E falls into the blow walk. Five shifts of $B3 leave
    // $4C at 0, because the recorded bits sit below bit 5. No contact
    // returns first and the scan's $FF stays.
    if (group[0] || group[1] || group[2]) {
        NoisePoke(0x4C, 0);
    }
    if (group[1] && group[2]) {
        paired[1][2] = paired[2][1] = true;
    }
    // read_sprite_hits clears $B3,X, then ORs a pair mask when both
    // sprite groups in $D01E are set. $08/$02 is Bruce and Yamo, $10/$02
    // is Bruce and the ninja, and $10/$08 is the two fighters.
    int b3 = 0;
    int b4 = 0;
    int b5 = 0;
    if (paired[0][1]) {
        b3 |= 0x08;
        b4 |= 0x02;
    }
    if (paired[0][2]) {
        b3 |= 0x10;
        b5 |= 0x02;
    }
    if (paired[1][2]) {
        b4 |= 0x10;
        b5 |= 0x08;
    }
    NoisePoke(0xB3, b3);
    NoisePoke(0xB4, b4);
    NoisePoke(0xB5, b5);
    // $2A21 walks $B5, $B4, then $B3, shifting bits 0-4 out of each. $2A36
    // stores the bit number in $52 for every set bit, and each branch that
    // follows reloads Y from $52 and goes on, so the last set bit of that
    // walk is what step_actors and the next lamps see. Bruce standing on the
    // fallen ninja in room 12 left $10 in $B3, and $52 was 4.
    {
        const int walk[3] = {b5, b4, b3};
        int last = -1;
        for (const int bits : walk) {
            for (int y = 0; y < 5; ++y) {
                if ((bits >> y) & 1) {
                    last = y;
                }
            }
        }
        if (last >= 0) {
            NoisePoke(0x52, last);
        }
    }
    // Victims from actor 2 down to 0, matching the pass that reads $B3,X.
    for (int v = 2; v >= 0; --v) {
        if (!actor[v].on || !Open(actor[v].who.action)) {
            continue;
        }
        for (int a = 0; a < 3; ++a) {
            if (a == v || !actor[a].on || actor[a].who.action == kStomp) {
                continue;
            }
            // The trainer never records Bruce's contact, so he does not flinch
            // and the swing is not a connect either.
            if (v == 0 && gConfig.enemiesCantHitBruce && a != 0) {
                continue;
            }
            if (!paired[a][v]) {
                continue;
            }
            const int blow = BlowOf(actor[a].who, actor[v].who);
            if (blow == 0) {
                continue;
            }
            if (blow == 16) {
                // $2B06. The charge is spent before the bit and the state
                // tests, so a kick, a punch, or a second landing still uses it.
                if (!TakeStomp(a)) {
                    continue;
                }
                if ((actor[v].bc & 0x10) != 0 || (actor[a].bc & 0x10) != 0) {
                    continue;
                }
                if (actor[v].who.action == kFlyLeft || actor[v].who.action == kFlyRight ||
                    actor[v].who.action == kPunch) {
                    continue;
                }
                actor[v].bc |= 0x10;
                if (a == 0) {
                    actor[v].bc |= 0x80;
                }
                PlayEffect(0x86);
                continue;
            }
            if (blow == 2) {
                actor[v].bc |= 0x02;
                PlayEffect(0x87);
            } else if (blow == 4) {
                actor[v].bc |= 0x04;
                if (a == 0) {
                    actor[v].bc |= 0x80;
                }
                PlayEffect(0x86);
            } else if (blow == 8) {
                actor[v].bc |= 0x08;
                if (a == 0) {
                    actor[v].bc |= 0x80;
                }
                PlayEffect(0x86);
            }
            MarkSwing(actor[a], actor[v]);
        }
    }
    for (int x = 2; x >= 0; --x) {
        if (!actor[x].on || actor[x].bc == 0) {
            continue;
        }
        int hold = -1;
        if ((actor[x].bc & 0x01) != 0) {
            actor[x].who.action = 0;
            actor[x].who.timer = HitRecoverTimer(x == 0);
            hold = 4;
        }
        ApplyBlows(actor[x]);
        CommitHit(actor[x], hold);
    }
    return false;
}

void SetHumanState(Fighter& f, int state, int timer) {
    f.action = state;
    f.actionTimer = timer;
    f.hold = 0;
    if (state == kClimbUp || state == kClimbDown) {
        f.hold = 3;
    } else if (state == kDuck) {
        f.hold = 1;
    }
}

void LandHuman(Fighter& f) {
    SetHumanState(f, 0, 0);
}

// move_left and move_right. The screen edge refuses the step. A wall does not.
bool TryStepHuman(Fighter& f, int dir) {
    if (!StepX(f, dir)) {
        ClearFighter(f);
        return false;
    }
    return true;
}

// move_up. The screen edge refuses it. A wall does not. A refusal is
// clear_state, and the rest of the move does not run.
bool RiseHuman(Fighter& f, int pixels) {
    for (int i = 0; i < pixels; ++i) {
        if (!StepY(f, -1)) {
            ClearFighter(f);
            return false;
        }
    }
    return true;
}

bool DropHuman(Fighter& f, int pixels) {
    for (int i = 0; i < pixels; ++i) {
        if (!StepY(f, 1)) {
            ClearFighter(f);
            return false;
        }
    }
    return true;
}

void StartFlyHuman(Fighter& f, int dir) {
    f.facing = dir;
    SetHumanState(f, dir < 0 ? kFlyLeft : kFlyRight, 0x0C);
}

void WalkHuman(Fighter& f, int dir, bool fire) {
    const int walk = dir < 0 ? kWalkLeft : kWalkRight;
    if ((dir < 0 && f.x < kMinX) || (dir > 0 && f.x >= kMaxX)) {
        LandHuman(f);
        return;
    }
    PlayEffect(0x80);
    if (f.prevAction != walk) {
        f.step = 0;
    }
    // $1E70. Two steps, or three once $CB has reached 0. Fire during a walk
    // whose repeat is below 4 replaces that step with the flying kick.
    const auto one = [&]() -> bool {
        if (f.prevAction == walk && f.repeat < 4 && fire) {
            StartFlyHuman(f, dir);
            return true;
        }
        if ((dir < 0 && f.x < kMinX) || (dir > 0 && f.x >= kMaxX)) {
            LandHuman(f);
            return false;
        }
        StepX(f, dir);
        SetHumanState(f, walk, 0);
        return false;
    };
    if (f.repeat == 0 && one()) {
        return;
    }
    if (one()) {
        return;
    }
    one();
}

void ClimbHuman(Fighter& f, int dir) {
    const int n = f.repeat == 0 ? 4 : 3;
    for (int i = 0; i < n; ++i) {
        if (dir < 0) {
            if (f.y < kMinY) {
                LandHuman(f);
                continue;
            }
            f.y -= 1;
            f.hist[0][kStepUp] += 1;
            SetHumanState(f, kClimbUp, 0);
        } else {
            if (f.y >= kMaxY) {
                LandHuman(f);
                continue;
            }
            f.y += 1;
            f.hist[0][kStepDown] += 1;
            SetHumanState(f, kClimbDown, 0);
        }
    }
}

void DuckHuman(Fighter& f, int facing) {
    if (facing < 0 && f.x >= 300) {
        LandHuman(f);
        return;
    }
    if (facing > 0 && f.x < 8) {
        LandHuman(f);
        return;
    }
    f.facing = facing;
    SetHumanState(f, kDuck, 0);
}

void StartFallHuman(Fighter& f) {
    BeginFall(f);
}

void HumanScript(Fighter& f, const Contact& here) {
    const int t = f.actionTimer;
    EnterMove(f);
    if (f.action == kJump) {
        if (here.ladder) {
            LandHuman(f);
            return;
        }
        // A refused rise returns. keep_state stores the jump again.
        if (t < 0x0D && t >= 2) {
            if (t >= 8) {
                const int n = t == 0x0C ? 4 : 2;
                for (int i = 0; i < n; ++i) {
                    StepY(f, -1);
                }
            } else if (here.ground) {
                LandHuman(f);
                return;
            } else {
                StepY(f, 1);
                StepY(f, 1);
            }
        }
        KeepTimer(f);
        return;
    }
    if (f.action == kSideLeft || f.action == kSideRight) {
        if (here.ladder) {
            LandHuman(f);
            return;
        }
        const int dir = f.action == kSideLeft ? -1 : 1;
        // A refused step returns. The rest of the arc, and the timer, still run.
        if (t > 0x0A) {
            StepY(f, -1);
            StepY(f, -1);
            StepX(f, dir);
            StepX(f, dir);
        } else if (t == 0x0A) {
            StepY(f, -1);
            StepX(f, dir);
            StepX(f, dir);
        } else if (t < 7) {
            if (here.ground) {
                LandHuman(f);
                return;
            }
            StepX(f, dir);
            StepX(f, dir);
            // set_state's TAY overwrites Y, so the timer-6 skip never fires.
            StepY(f, 1);
            StepY(f, 1);
        } else {
            StepX(f, dir);
            StepX(f, dir);
        }
        KeepTimer(f);
        return;
    }
    if (f.action == kFlyLeft || f.action == kFlyRight) {
        if (here.ladder || here.wall) {
            LandHuman(f);
            return;
        }
        if (t == 0x0C) {
            PlayEffect(0x84);
        }
        const int dir = f.action == kFlyLeft ? -1 : 1;
        if (t >= 0x0A) {
            StepY(f, -1);
            StepX(f, dir);
        } else if (t >= 3) {
            StepX(f, dir);
        } else if (here.ground) {
            LandHuman(f);
            return;
        } else {
            StepY(f, 1);
            StepX(f, dir);
        }
        KeepTimer(f);
        return;
    }
    if (f.action == kPunch) {
        if (here.ladder || here.wall) {
            LandHuman(f);
            return;
        }
        if (t == 1) {
            f.action = 0;
            f.actionTimer = 3;
            f.hold = 0;
            return;
        }
        KeepTimer(f);
        return;
    }
    if (f.actionTimer > 0) {
        KeepTimer(f);
    }
}

void OnGroundHuman(Fighter& f, int stick, bool fire, const Contact& here) {
    if (stick == 0x0E) {
        if (f.y < kMinY) {
            LandHuman(f);
        } else {
            PlayEffect(0x80);
            if (here.ladder) {
                ClimbHuman(f, -1);
            } else if (here.wall) {
                LandHuman(f);
            } else {
                SetHumanState(f, kJump, 0x0F);
            }
        }
    } else if (stick == 0x0D) {
        if (here.ladder) {
            if (f.y < kMaxY) {
                PlayEffect(0x80);
            }
            ClimbHuman(f, 1);
        } else if (here.ground) {
            DuckHuman(f, f.facing);
        }
    } else if (stick == 0x0B) {
        WalkHuman(f, -1, fire);
    } else if (stick == 0x07) {
        WalkHuman(f, 1, fire);
    } else if (stick == 0x0A || stick == 0x06) {
        if (here.ladder) {
            LandHuman(f);
        } else {
            PlayEffect(0x80);
            const int dir = stick == 0x0A ? -1 : 1;
            f.facing = dir;
            SetHumanState(f, dir < 0 ? kSideLeft : kSideRight, 0x0F);
        }
    } else if (stick == 0x09 || stick == 0x05) {
        if (here.ladder) {
            LandHuman(f);
        } else if (here.ground) {
            DuckHuman(f, stick == 0x09 ? -1 : 1);
        }
    } else if (stick == 0x0F && fire && !here.ladder) {
        SetHumanState(f, kPunch, 4);
    } else {
        LandHuman(f);
    }
}

void HumanMove(Fighter& f, int stick, bool fire, const Contact& here) {
    if (f.actionTimer > 0) {
        HumanScript(f, here);
    } else if (f.action == kFall) {
        // Actor 1, including a human Yamo, uses the ninja's fall.
        ContinueFall(f);
    } else if (here.ground || here.ladder) {
        OnGroundHuman(f, stick, fire, here);
    } else {
        StartFallHuman(f);
    }
}

int JumpPoseHuman(const Fighter& f) {
    const int t = f.actionTimer;
    if (t >= 0x0F || t <= 0) {
        return kPoseLegs;
    }
    if (t >= 0x0C || t == 1) {
        return 7;
    }
    return kPoseArms;
}

void HumanChoose(Fighter& f, const Contact& here) {
    const bool climbNow = f.action == kClimbUp || f.action == kClimbDown ||
                          ((f.action == kWalkLeft || f.action == kWalkRight) && here.ladder) ||
                          (f.action == 0 && here.ladder);
    if (f.action != kWalkLeft && f.action != kWalkRight) {
        f.step = 0;
    }
    if (f.action == kPunch) {
        f.pose = f.facing < 0 ? kPosePunchLeft : kPosePunchRight;
    } else if (f.action == kFlyLeft || f.action == kFlyRight) {
        const bool tucked = f.actionTimer >= 0x0A;
        f.pose = f.action == kFlyLeft ? (tucked ? 15 : 16) : (tucked ? 17 : 18);
    } else if (f.action == kSideLeft || f.action == kSideRight) {
        const bool tucked = f.actionTimer >= 0x0C || f.actionTimer < 3;
        if (f.action == kSideLeft) {
            f.pose = tucked ? 9 : 10;
        } else {
            f.pose = tucked ? 11 : 12;
        }
    } else if (f.action == kJump) {
        f.pose = JumpPoseHuman(f);
    } else if (f.action == kDuck) {
        f.pose = f.facing < 0 ? kPoseDuckLeft : kPoseDuckRight;
    } else if (f.action == kFall) {
        // A human Yamo. His library $44 is the same bitmap as library 8.
        f.pose = kPoseLegs;
    } else if (climbNow) {
        const bool stepping = f.action == kClimbUp || f.action == kClimbDown || f.action == kWalkLeft ||
                              f.action == kWalkRight;
        if (stepping) {
            f.pose = f.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
        } else if (f.pose != kPoseClimb0 && f.pose != kPoseClimb1) {
            f.pose = kPoseClimb0;
        }
        f.step = 0;
    } else if (f.action == kWalkLeft || f.action == kWalkRight) {
        const int stride = f.step & 1;
        f.pose = f.facing < 0 ? (2 + stride) : (4 + stride);
        f.step += 1;
    } else if (f.action == kStuck) {
        if (StuckUsesLegs(f.kind, f.pose)) {
            f.pose = kPoseLegs;
        }
    } else {
        f.pose = f.facing < 0 ? 1 : 0;
    }
}

// $2187 for a human opponent. The stick is kept. A pure direction steps two
// pixels. Diagonals do not. Up and down are allowed, which a computer
// fighter never stores.
void HumanCarry(Fighter& f, int stick) {
    bool stepped = false;
    if (f.carryDelay > 0) {
        f.carryDelay -= 1;
    } else if (stick == 0x0E) {
        StepY(f, -1);
        StepY(f, -1);
        stepped = true;
    } else if (stick == 0x0D) {
        StepY(f, 1);
        StepY(f, 1);
        stepped = true;
    } else if (stick == 0x0B) {
        StepX(f, -1);
        StepX(f, -1);
        stepped = true;
    } else if (stick == 0x07) {
        StepX(f, 1);
        StepX(f, 1);
        stepped = true;
    }
    if (stepped) {
        f.carryDelay = 4;
        f.pose = f.pose == kPoseClimb0 ? kPoseClimb1 : kPoseClimb0;
        PlayEffect(0x80);
    }
    const int shove = SurfaceShove();
    if (shove < 0) {
        StepY(f, -1);
        StepY(f, -1);
    } else if (shove > 0) {
        StepY(f, 1);
        StepY(f, 1);
    }
    const int up = f.hist[0][kStepUp];
    const int down = f.hist[0][kStepDown];
    if (up >= down) {
        f.hist[0][kStepUp] = up - down;
        f.hist[0][kStepDown] = 0;
    } else {
        f.hist[0][kStepDown] = down - up;
        f.hist[0][kStepUp] = 0;
    }
    f.action = kCarry;
}

// A human Yamo's walk and climb pictures. Spawn, flinch, knock, and stomp
// stay on the shared chooser.
void ShowPose(Fighter& f, bool human, const Contact& here) {
    if (human && f.action != kFlinch && f.action != kKnock && f.action != kStomp && f.action != 0x10 &&
        f.action != 0x12) {
        HumanChoose(f, here);
        return;
    }
    Choose(f, here);
}

// $1C9D. State 0, or a state that just changed, reloads the burst count.
void NoteState(Fighter& f) {
    if (f.action == 0 || f.action != f.prevAction) {
        f.repeat = 6;
    } else if (f.repeat > 0) {
        f.repeat -= 1;
    }
    f.prevAction = f.action;
}

void EnterActorTick(const Fighter& f) {
    // actor_tick stores $FF at $C5,X before the mover. It stays after he leaves.
    NoisePoke(0xC5 + (f.kind == 1 ? 1 : 2), 0xFF);
}

// True when he is wedged in a wall with no steps left to undo. $24DB then
// re-enters the room on Bruce's spawn.
bool StepFighter(Fighter& f) {
    if (!f.on) {
        // $1BF3. A held-off room never reaches try_yamo or try_ninja, and
        // step_actors does not spawn on its own. A delay of 0 stays asleep.
        if (!HoldOff()) {
            Spawn(f);
        }
        return false;
    }
    // Knock and stomp with time left still step. check_bruce_down runs
    // after that. A knockdown whose timer remains is spared. A stomp is not.
    if (f.health < 0 && !((f.action == kKnock || f.action == kStomp) && f.actionTimer > 0)) {
        Bury(f, true);
        return false;
    }
    const bool human = HumanYamo(f);
    // $0106. Every actor. Climb leaves 3. The wall rewind clears it. A blow
    // leaves that count alone, and a connecting attack stores 4 over it.
    if (f.hold > 0) {
        f.hold -= 1;
        return false;
    }
    RememberSteps(f);
    NoteState(f);
    // The overlap from the picture already showing. push_out reads that,
    // and it runs instead of the chase, the strike, or the ladder ride.
    const Contact shown = At(f);
    if (f.action == kStuck && f.actionTimer > 0) {
        if (!shown.wall) {
            NoisePoke(0x52, 0);
            f.actionTimer = 0;
        } else if (!OlderSteps(f)) {
            return true;
        } else {
            PushOut(f, shown);
            // push_out stored $18. check_bruce_down then spends a negative $D1.
            if (f.health < 0) {
                Bury(f, true);
                return false;
            }
        }
        ShowPose(f, human, shown);
        return false;
    }
    if (shown.wall) {
        PushOut(f, shown);
        if (f.health < 0) {
            Bury(f, true);
            return false;
        }
        ShowPose(f, human, shown);
        return false;
    }
    if (f.action == kStuck) {
        // Timer 0 keeps state $18 through release_hold, then actor_tick
        // reads the stick. A human Yamo's stick is $99. A computer
        // fighter's $98 is still $0F, and that nibble with the button up
        // is clear_state.
        f.action = 0;
        f.actionTimer = 0;
        if (!human) {
            ShowPose(f, human, shown);
            return false;
        }
    }
    if (f.action == kCarry) {
        EnterActorTick(f);
        if (human) {
            int stick = 0x0F;
            bool fire = false;
            ReadPlayerStick(gBrucePlayer ^ 1, stick, fire);
            HumanCarry(f, stick);
        } else {
            CarryFighter(f);
            Choose(f, shown);
        }
        return false;
    }
    // Spawn, flinch, knock, and stomp stay on the shared actor path. Every
    // other state of a human Yamo is the same stick table Bruce uses.
    if (human && f.action != kFlinch && f.action != kKnock && f.action != kStomp && f.action != 0x10 &&
        f.action != 0x12) {
        EnterActorTick(f);
        int stick = 0x0F;
        bool fire = false;
        ReadPlayerStick(gBrucePlayer ^ 1, stick, fire);
        const Contact here = At(f);
        HumanMove(f, stick, fire, here);
        HumanChoose(f, here);
        return false;
    }
    EnterActorTick(f);
    Act(f);
    Choose(f, shown);
    return false;
}

}  // namespace

const uint8_t* ScanFrames(const uint8_t* frames) {
    if (!g.frames.empty() && frames == g.frames.data() && !bruceScan.empty()) {
        return bruceScan.data();
    }
    if (!ninjaBytes.empty() && frames == ninjaBytes.data() && !ninjaScan.empty()) {
        return ninjaScan.data();
    }
    if (!yamoBytes.empty() && frames == yamoBytes.data() && !yamoScan.empty()) {
        return yamoScan.data();
    }
    return frames;
}

namespace {

bool DrawnPixel(const uint8_t* frames, int pose, int plane, int x, int y) {
    const uint8_t* frame = frames + static_cast<size_t>(pose * 2 + plane) * kFrameBytes;
    return (frame[y * kSpriteRowBytes + x / 8] & static_cast<uint8_t>(0x80 >> (x & 7))) != 0;
}

void DrawOne(const Fighter& f) {
    if (!f.on || f.frames == nullptr) {
        return;
    }
    // The ninja has no second hardware sprite. Yamo's two pictures both show.
    const int planes = f.kind == 2 ? 1 : 2;
    for (int plane = 0; plane < planes; ++plane) {
        const int ink = f.kind == 1 ? NinjaInk(f.pose, plane) : 0;
        const int origin = f.x + PictureShift(f.kind, f.facing, f.pose, plane);
        // One stored bit is one screen pixel. Mode 0 fills the first 16
        // and the rest of the row is empty. Mode 1 uses all 32.
        for (int y = 0; y < kSpriteRows; ++y) {
            for (int x = 0; x < kSpriteCols; ++x) {
                if (!DrawnPixel(f.frames, f.pose, plane, x, y)) {
                    continue;
                }
                const int px = origin + x;
                const int py = f.y + y;
                if (px >= 0 && py >= 0 && px < kWidth && py < kHeight) {
                    g.pixels[static_cast<size_t>(py * kWidth + px)] = kPalette[ink];
                }
            }
        }
    }
}

}  // namespace

namespace {

int RowLimit(int kind, int pose, int plane, bool sprite) {
    // $5B61 at library base + PoseLibrary, and the next library for plane 1.
    // Mode 0 starts writing at byte height*3, so that row is in the sprite.
    // Mode 1 drops two bytes first and the same height stops one row earlier.
    static const uint8_t kRows[3][34][2] = {
        {
            {11, 20}, {11, 20}, {12, 20}, {12, 20}, {12, 20}, {12, 20}, {11, 20}, {13, 19},
            {11, 20}, {11, 20}, {11, 20}, {11, 20}, {11, 20}, {12, 20}, {12, 20}, {14, 18},
            {11, 18}, {14, 18}, {11, 18}, {12, 20}, {12, 20}, {20, 20}, {20, 20}, {11, 20},
            {11, 20}, {11, 20}, {11, 20}, {11, 20}, {11, 20}, {11, 20}, {12, 20}, {20, 20},
            {13, 20}, {20, 20},
        },
        {
            {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17},
            {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {21, 16}, {21, 16}, {20, 16},
            {17, 20}, {20, 16}, {16, 20}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17},
            {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {20, 17}, {21, 21},
            {20, 17}, {21, 21},
        },
        {
            {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0},
            {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {0, 0}, {0, 0}, {20, 0},
            {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0},
            {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0}, {20, 0},
            {20, 0}, {20, 0},
        },
    };
    // $5CBF. Nonzero selects the two-byte copy, which omits the last row
    // a one-byte copy of the same height would keep.
    static const uint8_t kWide[3][34][2] = {
        {
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {1, 1}, {1, 1}, {0, 0},
            {0, 1}, {0, 0}, {0, 1}, {0, 0}, {0, 0}, {0, 1}, {0, 1}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 1},
            {0, 0}, {0, 1},
        },
        {
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {1, 1}, {1, 1}, {0, 0},
            {1, 1}, {0, 0}, {1, 1}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {1, 0},
            {0, 0}, {1, 1},
        },
        {
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
            {0, 0}, {0, 0}, {0, 0}, {1, 0}, {0, 0}, {1, 0}, {1, 0}, {1, 0},
            {1, 0}, {1, 0},
        },
    };
    if (kind < 0 || kind > 2 || pose < 0 || pose >= 34 || plane < 0 || plane > 1) {
        return kSpriteRows;
    }
    int rows = kRows[kind][pose][plane];
    // expand_library copies height+1 rows either way. The sprite copy
    // includes that last row only when $5CBF is zero.
    if (!sprite || kWide[kind][pose][plane] == 0) {
        rows += 1;
    }
    if (rows < 0) {
        return 0;
    }
    return rows > kSpriteRows ? kSpriteRows : rows;
}

}  // namespace

int SpriteRows(int kind, int pose, int plane) {
    return RowLimit(kind, pose, plane, true);
}

bool BruceCovers(int screenX, int screenY) {
    if (g.frames.empty()) {
        return false;
    }
    for (int plane = 0; plane < 2; ++plane) {
        const int columns = WidePlane(0, g.pose, plane) ? kSpriteCols : kHardwareColumns;
        const int lx = screenX - (g.x + PictureShift(0, g.facing, g.pose, plane));
        const int ly = screenY - g.y;
        if (lx < 0 || lx >= columns || ly < 0 || ly >= SpriteRows(0, g.pose, plane)) {
            continue;
        }
        const uint8_t* frame = g.frames.data() + static_cast<size_t>(g.pose * 2 + plane) * kFrameBytes;
        if ((frame[ly * kSpriteRowBytes + lx / 8] & static_cast<uint8_t>(0x80 >> (lx & 7))) != 0) {
            return true;
        }
    }
    return false;
}

void NoteScanCell(int actor, int col, int row) {
    if (actor < 0 || actor > 2) {
        return;
    }
    NoisePoke(0xE6 + actor, col & 0xFF);
    NoisePoke(0xE9 + actor, row & 0xFF);
}

void ClearHeldSprites() {
    DropHeldSprites();
}

bool LoadFighters() {
    const size_t bytes = static_cast<size_t>(kFrames) * 2 * kFrameBytes;
    ninjaBytes = LoadFile(L"ninja.bin", bytes);
    yamoBytes = LoadFile(L"yamo.bin", bytes);
    bruceScan = LoadFile(L"bruce_scan.bin", bytes);
    ninjaScan = LoadFile(L"ninja_scan.bin", bytes);
    yamoScan = LoadFile(L"yamo_scan.bin", bytes);
    if (ninjaBytes.empty() || yamoBytes.empty() || bruceScan.empty() || ninjaScan.empty() ||
        yamoScan.empty()) {
        return false;
    }
    ninja.kind = 1;
    ninja.frames = ninjaBytes.data();
    yamo.kind = 2;
    yamo.frames = yamoBytes.data();
    return true;
}

Fighter gSavedNinja;
Fighter gSavedYamo;
bool gFightersHeld = false;

void StandFighters(int ninjaX, int ninjaY, int ninjaFacing, int yamoX, int yamoY, int yamoFacing) {
    if (!gFightersHeld) {
        gSavedNinja = ninja;
        gSavedYamo = yamo;
        gFightersHeld = true;
    }
    const auto stand = [](Fighter& fighter, int x, int y, int facing) {
        fighter.on = true;
        fighter.placed = true;
        fighter.x = x;
        fighter.y = y;
        fighter.facing = facing < 0 ? -1 : 1;
        fighter.pose = facing < 0 ? 1 : 0;
        fighter.action = 0;
        fighter.actionTimer = 0;
    };
    stand(ninja, ninjaX, ninjaY, ninjaFacing);
    stand(yamo, yamoX, yamoY, yamoFacing);
}

void RestoreFighters() {
    if (!gFightersHeld) {
        return;
    }
    ninja = gSavedNinja;
    yamo = gSavedYamo;
    gFightersHeld = false;
}

void CaptureResume(Fighter& f) {
    // finish_exit. Active: Bruce's arrival and this health, at $8A,X /
    // $8C,X / $8E,X. Inactive: the xpos and ypos bytes are cleared, so the
    // next wake picks a spawn side. The health byte stays.
    const int actor = f.kind == 1 ? 1 : 2;
    if (f.on) {
        f.resume = true;
        f.resumeX = g.x;
        f.resumeY = g.y;
        f.resumeHealth = f.health;
        NoisePoke(0x8E + actor, f.health & 0xFF);
        NoisePoke(0x8A + actor, XposOf(g.x) & 0xFF);
        NoisePoke(0x8C + actor, YposOf(g.y) & 0xFF);
        return;
    }
    f.resume = false;
    NoisePoke(0x8A + actor, 0);
    NoisePoke(0x8C + actor, 0);
}

void DropFighters() {
    ninja.on = false;
    ninja.resume = false;
    yamo.on = false;
    yamo.resume = false;
}

void RestoreLifeHealth() {
    ninja.health = 0x24;
    yamo.health = 0x24;
}

void ResetFighters() {
    // The arrival picture is new. A hit latched from the room he left would
    // land on the first frame here.
    ClearHeldSprites();
    // $2FA5, then the wake counts. Bruce is already on the arrival spot.
    CaptureResume(ninja);
    CaptureResume(yamo);
    // $0A48. Entering a held-off room clears both saved xpos bytes, so the
    // next wake uses a spawn side. The delays below are still loaded.
    if (HoldOff()) {
        ninja.resume = false;
        yamo.resume = false;
        // $0A48. A held-off room clears both saved xpos bytes.
        NoisePoke(0x8B, 0);
        NoisePoke(0x8C, 0);
    }
    // retire_actor clears active bit 0. enter_room then reloads both waits.
    // State, timer, hold, carry, and the strike repeat stay where the step
    // that retired him left them. wake_actor replaces those when he appears.
    // $1347, then $40, then 8 when a human opponent is on. $130B for the ninja.
    ninja.on = false;
    ninja.delay = OpenDelay(1);
    yamo.on = false;
    yamo.delay = OpenDelay(2);
    // retire_actor clears bit 0 of $96 and $97. The kind bit stays, and a
    // later noise_byte can read the byte.
    NoiseAnd(0x96, 0xFE);
    NoiseAnd(0x97, 0xFE);
}

int gOpponentIdle = 0;

void ResetOpponentIdle() {
    gOpponentIdle = 0;
}

// $2D7C. Both fighters are armed before either moves. State 0 with a
// finished timer, standing on ground or a ladder, becomes the chase.
// A human Yamo stays on his own stick. Negative health is left to bury.
void ArmChase(Fighter& f) {
    if (!f.on || HumanYamo(f) || f.health < 0) {
        return;
    }
    if (f.action != 0 || f.actionTimer != 0) {
        return;
    }
    const Contact ground = At(f);
    if (!(ground.ground || ground.ladder)) {
        return;
    }
    // $2DC0. The kick landed last frame, or the frame before that. The
    // stand replaces the chase. test_visit may cut $18 down to 3 or 1.
    if (f.prevAction == kFlyLeft || f.prevAction == kFlyRight) {
        f.action = 0;
        f.actionTimer = KickRecoverTimer();
        f.hold = 0;
        return;
    }
    f.action = 0x14;
    f.actionTimer = 0x14;
    f.hold = 0;
}

void ClipFighterHealth() {
    // $1BDF, before the lamps and the hits. The compare later is the sign
    // bit, so a masked byte at $80 or above stays a negative health.
    auto mask = [](int health, int bits) {
        const int masked = health & bits & 0xFF;
        return (masked & 0x80) != 0 ? masked - 256 : masked;
    };
    // Actor 1 is the variable named ninja. Actor 2 is the variable named yamo.
    ninja.health = mask(ninja.health, 0xBF);
    yamo.health = mask(yamo.health, 0x87);
}

void WakeDueFighters() {
    // $D01E still shows last frame. Remember that before a count reaches 0.
    spriteShown[0] = true;
    spriteShown[1] = ninja.on;
    spriteShown[2] = yamo.on;
    if (ninja.frames == nullptr) {
        return;
    }
    // The snapshot was taken after this frame's counts. They stay put.
    if (SnapshotFrameOpen()) {
        EndSnapshotFrame();
        return;
    }
    // $1BF1. $7A set: the counts stay, and neither try runs. A delay of 0
    // would otherwise wake on this tick. Rooms 13 and 17 keep $12 and $C0.
    if (HoldOff()) {
        return;
    }
    // $0DA4. A count of 0 stays 0, and both move while the fighter is on screen.
    if (yamo.delay > 0) {
        yamo.delay -= 1;
    }
    if (ninja.delay > 0) {
        ninja.delay -= 1;
    }
    // The spawn's noise_byte runs after the decrement.
    NoteNoiseDelays();
    // try_yamo, then try_ninja. The overlap below sees whoever just woke.
    const bool yamoWasOn = ninja.on;
    Spawn(ninja);
    // try_ninja reads one noise byte when its count is already 0 and Yamo
    // is on, including a Yamo try_yamo has just woken. $19 or more stores
    // $10 and leaves the ninja asleep. The lamps left Y at $40 or $2F, but
    // spawn_yamo returns with Y = $2770,X, which is 3 for actor 1. Room
    // 16's Yamo woke on frame 54 and the ninja's read used Y = 3.
    const bool yamoWoke = !yamoWasOn && ninja.on;
    if (yamoWoke) {
        // spawn_yamo stores state $10 and timer $0A before try_ninja reads.
        NoisePoke(0xC0, ninja.action);
        NoisePoke(0xCF, ninja.actionTimer);
    }
    const int holdY = yamoWoke ? 3 : CaptionNoiseY();
    if (yamo.delay == 0 && ninja.on && HoldNinjaWake(holdY)) {
        yamo.delay = 0x10;
        NoisePoke(0x5D, yamo.delay);
    }
    Spawn(yamo);
}

int HitBits(const Contact& hit);

void CaptureFrameHits() {
    // Every scan of this walk adds the same $7C, including a stale one.
    BeginOverlapFrame();
    struct EndOverlap {
        ~EndOverlap() { EndOverlapFrame(); }
    } endOverlap;
    frameHit[0].valid = false;
    frameHit[1].valid = false;
    frameHit[2].valid = false;
    if (!g.frames.empty()) {
        CaptureOne(0, g.frames.data(), g.action, g.facing, g.pose, g.x, g.y);
        // overlap_actors writes $B6 before the next frame's lamps read it.
        if (frameHit[0].valid) {
            NoisePoke(0xB6, HitBits(frameHit[0].full));
            // $53F4. Flags from the rows above the feet. The fall reads bit 0.
            NoisePoke(0xA7, HitBits(frameHit[0].upper));
        }
    }
    if (ninja.on) {
        CaptureOne(1, ninja.frames, ninja.action, ninja.facing, ninja.pose, ninja.x, ninja.y);
        ninja.groundHit = HitBits(frameHit[1].full);
        NoisePoke(0xB7, ninja.groundHit);
        NoisePoke(0xA8, HitBits(frameHit[1].upper));
    }
    // Kept for the $4E stamp below. The capture itself clears the flag.
    const bool ninjaSpawn = yamo.on && yamo.spawnMask;
    if (yamo.on) {
        if (ninjaSpawn) {
            // Library $82, not the stand pose Wake just stored.
            frameHit[2].full = ProbeNinjaSpawn(yamo.x, yamo.y);
            frameHit[2].upper = ProbeNinjaSpawnUpper(yamo.x, yamo.y);
            frameHit[2].valid = true;
        } else {
            CaptureOne(2, yamo.frames, yamo.action, yamo.facing, yamo.pose, yamo.x, yamo.y);
        }
        yamo.spawnMask = false;
        yamo.groundHit = HitBits(frameHit[2].full);
        NoisePoke(0xB8, yamo.groundHit);
        NoisePoke(0xA9, HitBits(frameHit[2].upper));
    }
    // overlap_actors walks X from 2 to 0. $4E is the last AND of that walk.
    if (yamo.on) {
        if (ninjaSpawn) {
            ProbeNinjaSpawn(yamo.x, yamo.y);
            const int byte = LastOverlapAnd();
            if (byte >= 0) {
                NoisePoke(0x4E, byte);
            }
        } else {
            StampOverlap(2, yamo.frames, yamo.action, yamo.facing, yamo.pose, yamo.x, yamo.y);
        }
    }
    if (ninja.on) {
        StampOverlap(1, ninja.frames, ninja.action, ninja.facing, ninja.pose, ninja.x, ninja.y);
    }
    if (!g.frames.empty()) {
        StampOverlap(0, g.frames.data(), g.action, g.facing, g.pose, g.x, g.y);
    }
    // The third band stores $18 only when (ypos - $1D) & 7 is 4 or more.
    // A smaller alignment hits the sprite end first and leaves the second
    // band's $10. Bruce is last. A later mover overwrites this.
    const int fineY = (YposOf(g.y) - 0x1D) & 7;
    NoisePoke(0x52, fineY >= 4 ? 0x18 : 0x10);
    // $5214 stores X in $50 for every actor, on or off, and the walk ends
    // on Bruce. A snapshot taken inside the walk holds another value.
    NoisePoke(0x50, 0);
}

Contact FrameContact(int kind) {
    if (kind >= 0 && kind < 3 && frameHit[kind].valid) {
        return frameHit[kind].full;
    }
    return Probe(g.x, g.y);
}

Contact FrameUpper(int kind) {
    if (kind >= 0 && kind < 3 && frameHit[kind].valid) {
        return frameHit[kind].upper;
    }
    return ProbeUpper(g.x, g.y);
}

bool SpriteShown(int kind) {
    return kind >= 0 && kind < 3 && spriteShown[kind];
}

void ScanFighterSpecials() {
    if (ninja.frames == nullptr) {
        return;
    }
    // Actor 2, then actor 1. The variable names are the other way around.
    // Bruce's scan runs after both of these.
    ScanFighterTiles(yamo);
    ScanFighterTiles(ninja);
}

bool Stepping(const Fighter& f) {
    if (!f.on || f.hold > 0) {
        return false;
    }
    // The same early out as StepFighter. A dead fighter is buried and does
    // not reach the mover.
    if (f.health < 0 && !((f.action == kKnock || f.action == kStomp) && f.actionTimer > 0)) {
        return false;
    }
    return true;
}

bool FighterStepping() {
    return Stepping(yamo) || Stepping(ninja);
}

int AwakeFighters() {
    return (ninja.on ? 1 : 0) + (yamo.on ? 1 : 0);
}

int AwakeFighterXpos(int out[2]) {
    int n = 0;
    if (ninja.on) {
        out[n++] = XposOf(ninja.x);
    }
    if (yamo.on) {
        out[n++] = XposOf(yamo.x);
    }
    return n;
}

bool TickFighters() {
    if (ninja.frames == nullptr) {
        return false;
    }
    // The original IRQ counts while Yamo's stick is neutral and his button
    // is up. Seven wraps of a byte, once per screen, is 1792 screens. This
    // port's logic frame is three PAL screens, so 3 is one screen's worth.
    // At the end $42CA clears for this game only, effect $8A plays, and
    // five falls come off $28 and off $439F. A count already below zero
    // stays there. The stick is the port that is not Bruce. The options
    // page keeps OPPONENT.
    // $173F. $7A skips the idle count and the stick that would clear it.
    // The count continues from the same value in the next room that runs it.
    if (!HoldOff()) {
        if (gHumanOpponent && !gOpponentYielded) {
            int stick = 0x0F;
            bool fire = false;
            ReadPlayerStick(gBrucePlayer ^ 1, stick, fire);
            if (stick != 0x0F || fire) {
                gOpponentIdle = 0;
            } else {
                gOpponentIdle += 3;
                if (gOpponentIdle >= 1792) {
                    gOpponentIdle = 0;
                    gOpponentYielded = true;
                    PlayEffect(0x8A);
                    if (!gConfig.infiniteLives) {
                        PenalizeBothFalls(5);
                    }
                }
            }
        } else {
            gOpponentIdle = 0;
        }
    }
    // $1C1E. The same byte skips read_sprite_hits. Bolts are the room hook.
    if (!HoldOff() && Resolve()) {
        return true;
    }
    // $24DB. A fighter still inside a wall, with no steps left to walk back,
    // re-enters this room on Bruce's spawn.
    // step_actors walks actor 2, then 1, then Bruce. enemy_turn has
    // already armed both chases. The variable names are swapped.
    ArmChase(yamo);
    ArmChase(ninja);
    if (StepFighter(yamo) || StepFighter(ninja)) {
        if (EnterRoom(g.roomId)) {
            PlaceBruce();
            g.actionTimer = 4;
            EnterFrameHook();
        }
        ArmExitClock();
        return true;
    }
    return false;
}

void DrawFighters() {
    DrawOne(yamo);
    DrawOne(ninja);
}

void ClearHist(Fighter& f) {
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int d = 0; d < 4; ++d) {
            f.hist[gen][d] = 0;
        }
    }
}

int PoseLibrary(int pose) {
    static const int kLibrary[] = {
        0x02, 0x00, 0x0E, 0x10, 0x12, 0x14, 0x08, 0x1E, 0x20, 0x22, 0x24, 0x26, 0x28,
        0x05, 0x07, 0x16, 0x18, 0x1A, 0x1C, 0x0A, 0x0C, 0x40, 0x42, 0x2A, 0x2C, 0x2E,
        0x30, 0x32, 0x34, 0x36, 0x38, 0x3A, 0x3C, 0x3E,
    };
    if (pose < 0 || pose >= 34) {
        return kLibrary[0];
    }
    return kLibrary[pose];
}

// blit_sprites calls load_library twice for Bruce and Yamo. The second
// call uses library+1 and is the value left in $E0,X. Actor 2 stops
// after the first image. The tables are $5B61 and $5CBF at that index.
void MirrorBlitNoise(int actor, int pose, bool on) {
    static const uint8_t kSpriteHeight[3][34] = {
        {20, 20, 20, 20, 20, 20, 20, 19, 20, 20, 20, 20, 20, 20, 11, 18, 18, 18, 18,
            20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20},
        {17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 16, 20, 16, 20, 16, 20,
            17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 21, 17, 21},
        {20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 0, 0, 20, 20, 20, 20,
            20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20},
    };
    static const uint8_t kMode[3][34] = {
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 1, 0, 1},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 85, 0, 85, 85, 85, 85, 85},
    };
    static const uint8_t kMode2[2][34] = {
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0,
            0, 0, 0, 0, 0, 1, 0, 1},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 1},
    };
    static const uint8_t kColor2[2][34] = {
        {0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
            0xF0, 0xF7, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
            0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0},
        {0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
            0xF0, 0xF5, 0xF0, 0xF5, 0xF0, 0xF5, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
            0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF5},
    };
    if (!on || actor < 0 || actor > 2 || pose < 0 || pose >= 34) {
        return;
    }
    NoisePoke(0xE0 + actor, kSpriteHeight[actor][pose]);
    NoisePoke(0xD4 + actor, kMode[actor][pose]);
    if (actor < 2) {
        NoisePoke(0xD7 + actor, kMode2[actor][pose]);
        NoisePoke(0xDD + actor, kColor2[actor][pose]);
    }
}

void MirrorNoiseActors() {
    MirrorSurface();
    // $9E-$A3 are xpos and ypos. They stay when the fighter is off, and
    // flicker_lamps reads them before this frame's step. $A4-$A6 are facing.
    NoisePoke(0x9E, XposOf(g.x));
    NoisePoke(0xA1, YposOf(g.y));
    NoisePoke(0xA4, g.facing < 0 ? 0 : 1);
    NoisePoke(0x106, g.hold);
    // An actor who has not entered keeps the bytes enter_room left. Writing
    // the default facing turned a later lamp read from 0 into 1.
    NoisePoke(0xAD, BruceCarryDelay() & 0xFF);
    // $AA,X and $AD,X: the surface step mark and its wait. Room 5's lamps
    // read the ninja's mark after his own step had cleared it.
    if (ninja.placed) {
        NoisePoke(0xAB, ninja.carryMark & 0xFF);
        NoisePoke(0xAE, ninja.carryDelay & 0xFF);
    }
    if (yamo.placed) {
        NoisePoke(0xAC, yamo.carryMark & 0xFF);
        NoisePoke(0xAF, yamo.carryDelay & 0xFF);
    }
    if (ninja.placed) {
        NoisePoke(0x9F, XposOf(ninja.x));
        NoisePoke(0xA2, YposOf(ninja.y));
        NoisePoke(0xA5, ninja.facing < 0 ? 0 : 1);
        NoisePoke(0x107, ninja.hold);
    }
    if (yamo.placed) {
        NoisePoke(0xA0, XposOf(yamo.x));
        NoisePoke(0xA3, YposOf(yamo.y));
        NoisePoke(0xA6, yamo.facing < 0 ? 0 : 1);
        NoisePoke(0x108, yamo.hold);
    }
    // $5E is Yamo, the variable named ninja. $5D is the ninja.
    NoisePoke(0x5E, ninja.delay);
    NoisePoke(0x5D, yamo.delay);
    NoisePoke(0xBF, g.action);
    NoisePoke(0xC2, g.prevState);
    // $C2,X. Actor 1 is $C3, actor 2 is $C4. The lamps read the byte
    // release_hold stored, including after he has left the room.
    // $CE,X is the move timer. $D1,X is health. Wake stores both before
    // the next frame's lamps. An actor who has never entered keeps the
    // snapshot.
    NoisePoke(0xCB, g.repeat);
    NoisePoke(0xCE, g.actionTimer);
    NoisePoke(0xD1, g.health);
    if (ninja.placed) {
        NoisePoke(0xC3, ninja.prevAction & 0xFF);
        if (ninja.on) {
            NoisePoke(0xCC, ninja.repeat);
        }
        NoisePoke(0xCF, ninja.actionTimer);
        NoisePoke(0xD2, ninja.health);
    }
    if (yamo.placed) {
        NoisePoke(0xC4, yamo.prevAction & 0xFF);
        if (yamo.on) {
            NoisePoke(0xCD, yamo.repeat);
        }
        NoisePoke(0xD0, yamo.actionTimer);
        NoisePoke(0xD3, yamo.health);
    }
    // blit_sprites stores $5C33[library + base] at $DA,X. Yamo's base is
    // $46. Libraries $18, $1C, and $3E are $F0. The rest of his poses are
    // $F5. The byte stays after he leaves. Bruce stays $F7 and the ninja
    // is forced to $F0, which the snapshot already holds. $E0, $D4, and
    // the second image are the other bytes that blit leaves behind.
    if (ninja.on) {
        const bool pale = ninja.pose == 16 || ninja.pose == 18 || ninja.pose == kPoseKnockLeft1;
        NoisePoke(0xDB, pale ? 0xF0 : 0xF5);
    }
    MirrorBlitNoise(0, g.pose, true);
    MirrorBlitNoise(1, ninja.pose, ninja.on);
    MirrorBlitNoise(2, yamo.pose, yamo.on);
    if (ninja.on) {
        NoisePoke(0xC0, ninja.action);
    }
    if (yamo.on) {
        NoisePoke(0xC1, yamo.action);
    }
}

void NoteNoiseDelays() {
    NoisePoke(0x5E, ninja.delay);
    NoisePoke(0x5D, yamo.delay);
}

void NoisePositions(int& bruceX, int& yamoX, int& ninjaX, bool& yamoOn, bool& ninjaOn) {
    bruceX = XposOf(g.x);
    yamoOn = ninja.on;
    yamoX = XposOf(ninja.x);
    ninjaOn = yamo.on;
    ninjaX = XposOf(yamo.x);
}

// $4F48 is the library choose_pose stored, before the actor base is added.
// The order is the pose index in the fighter pictures.
int PoseIndex(int library) {
    for (int i = 0; i < 34; ++i) {
        if (PoseLibrary(i) == library) {
            return i;
        }
    }
    return 0;
}

void PlantOne(Fighter& fighter, const uint8_t* ram, int actor, int delayAddr) {
    fighter.on = (ram[0x95 + actor] & 1) != 0;
    fighter.placed = fighter.on;
    fighter.x = ram[0x9E + actor] * 2 - 24;
    fighter.y = ram[0xA1 + actor] - 21;
    fighter.facing = ram[0xA4 + actor] == 0 ? -1 : 1;
    fighter.pose = PoseIndex(ram[0x4F48 + actor]);
    fighter.action = ram[0xBF + actor];
    fighter.actionTimer = ram[0xCE + actor];
    fighter.prevAction = ram[0xC2 + actor];
    fighter.repeat = ram[0xCB + actor];
    fighter.hold = ram[0x106 + actor];
    const int health = ram[0xD1 + actor];
    fighter.health = health >= 0x80 ? health - 256 : health;
    fighter.fallSlide = ram[0xB0 + actor];
    fighter.groundHit = ram[0xB6 + actor];
    fighter.carryDelay = ram[0xAD + actor];
    fighter.carryMark = ram[0xAA + actor];
    fighter.delay = ram[delayAddr];
    // $8A,X nonzero is a resume. Actor 1 is $8B/$8D/$8F. Actor 2 is
    // $8C/$8E/$90. wake_actor copies those over the spawn side.
    const int resumeX = ram[0x8A + actor];
    fighter.resume = resumeX != 0;
    fighter.resumeX = resumeX * 2 - 24;
    fighter.resumeY = ram[0x8C + actor] - 21;
    const int resumeHealth = ram[0x8E + actor];
    fighter.resumeHealth = resumeHealth >= 0x80 ? resumeHealth - 256 : resumeHealth;
    // Same table as Bruce, one byte over for this actor. push_out undoes
    // generation 1 after hold_done shifts generation 0 into it.
    for (int gen = 0; gen < kStepGens; ++gen) {
        for (int dir = 0; dir < 4; ++dir) {
            fighter.hist[gen][dir] = ram[0x4F57 + dir * 3 + gen * 12 + actor];
        }
    }
}

bool PlantSnapshotTrace(const wchar_t* path) {
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
    const size_t base = mark + 26;
    if (mark == file.size() || base + 0x200 > file.size()) {
        return false;
    }
    const uint8_t* ram = file.data() + base;
    PlantRoomBonus(ram);
    if (!EnterRoom(ram[0x29])) {
        return false;
    }
    const uint8_t cpuTag[] = {'M', 'A', 'I', 'N', 'C', 'P', 'U'};
    size_t cpu = file.size();
    for (size_t i = 0; i + 7 <= file.size(); ++i) {
        if (std::equal(cpuTag, cpuTag + 7, file.begin() + static_cast<std::ptrdiff_t>(i))) {
            cpu = i;
            break;
        }
    }
    int pc = 0x1C34;
    if (cpu + 36 <= file.size()) {
        pc = file[cpu + 34] | (file[cpu + 35] << 8);
    }
    const bool atWait = pc == 0x1C32 || pc == 0x1C34 || pc == 0x1C36;
    // A snapshot in the score convert is finished by the capture before its
    // frame 1, so the interrupts still left in $48 come before that frame,
    // like a snapshot taken at the wait. Room 9's lamp reads were three
    // counts short of VICE's until they were.
    const bool scoreConvert = pc >= 0x32DC && pc <= 0x330D;
    // between_lives waits at $0F47 for the rest of $48 before the respawn.
    // Room 18's snapshot has 59 interrupts left there.
    const bool betweenLives = pc >= 0x0F47 && pc <= 0x0F71;
    if (!PlantSnapshotNoise(path, atWait || scoreConvert || betweenLives, betweenLives ? 0xFF : 3)) {
        return false;
    }
    g.x = ram[0x9E] * 2 - 24;
    g.y = ram[0xA1] - 21;
    g.facing = ram[0xA4] == 0 ? -1 : 1;
    g.pose = PoseIndex(ram[0x4F48]);
    g.action = ram[0xBF];
    g.actionTimer = ram[0xCE];
    g.prevState = ram[0xC2];
    g.repeat = ram[0xCB];
    g.hold = ram[0x106];
    const int health = ram[0xD1];
    g.health = health >= 0x80 ? health - 256 : health;
    g.fallSlide = ram[0xB0];
    PlantBruceSteps(ram);
    PlantBruceCarry(ram[0xAD]);
    // Actor 1 is the variable ninja (Yamo). Actor 2 is the variable yamo.
    PlantOne(ninja, ram, 1, 0x5E);
    PlantOne(yamo, ram, 2, 0x5D);
    // Entering the room restarts the scroll. These bytes are where it was.
    PlantSurface(ram[0x60], ram[0x64], ram[0x65], ram[0x66], ram[0x4321]);
    PlantHazard(ram[0x6E], ram[0x6F], ram[0x77], ram[0x78]);
    PlantMovers(ram);
    PlantSlideTiles(ram);
    PlantCrumble(ram);
    PlantHooks(ram);
    PlantBolts(ram);
    // The room file is the unvisited map, plus the lamps EnterRoom just
    // painted. A snapshot taken after a door opened, a beam stepped, or a
    // floor crumbled already has those tiles, and the next hook will not
    // put the old wall back. Bit 7 on an even character row is the lower
    // charset half. The probe adds that from the row, so the stored code
    // is the low 7 bits. $DC marks the score cells the probe skips; a
    // blank $20 there stays $DC.
    if (g.room.size() >= 1000) {
        for (int i = 0; i < 1000; ++i) {
            const int live = ram[0x8C00 + i] & 0x7F;
            if (g.room[static_cast<size_t>(i)] == 0xDC && live == 0x20) {
                continue;
            }
            g.room[static_cast<size_t>(i)] = static_cast<uint8_t>(live);
        }
    }
    PlantLampCounts(ram);
    PlantGate(ram[0x7B]);
    PlantProgress(ram);
    PlantDifficulty(ram[0x40]);
    if (ram[0x29] == 19) {
        PlantTreasure(ram[0x49], ram[0x4A], ram[0x87], ram[0x88]);
    }
    // The wait is the start of the next frame. Anywhere else, the lamps
    // and the wake counts have already run. NoteSnapshotPc says whether
    // the room hook has too.
    NoteSnapshotPc(pc);
    ResetFrameClock();
    if (betweenLives) {
        RespawnFromSnapshot();
    } else if (!atWait) {
        // The score convert's frame 1 is a whole frame with its own three.
        HoldRoomHook(ram[0x7B], scoreConvert ? 3 : ram[0x48]);
    }
    return true;
}

void PlantRoom00Trace() {
    PlantRoom00Noise();
    // Actor 1 is the variable ninja. He is off. $5E is still $4E.
    ninja.on = false;
    ninja.delay = 0x4E;
    ninja.action = 0;
    ninja.actionTimer = 0;
    ninja.hold = 1;
    ClearHist(ninja);
    // Actor 2 is the variable yamo. Walk left, and $C2 is still the fall.
    yamo.on = true;
    yamo.placed = true;
    yamo.x = 0x7F * 2 - 24;
    yamo.y = 0x90 - 21;
    yamo.facing = -1;
    yamo.pose = 2;
    yamo.action = kWalkLeft;
    yamo.actionTimer = 0;
    yamo.prevAction = kFall;
    yamo.repeat = 0;
    yamo.hold = 0;
    yamo.fallSlide = 2;
    yamo.health = 7;
    yamo.delay = 0x66;
    yamo.carryDelay = 0;
    yamo.carryMark = 0;
    ClearHist(yamo);
}

int HitBits(const Contact& hit) {
    return (hit.ground ? 1 : 0) | (hit.bit1 ? 2 : 0) | (hit.ladder ? 4 : 0) | (hit.wall ? 8 : 0);
}

TraceBody TraceOf(bool on, int x, int y, int facing, int action, int timer, int pose, int kind) {
    TraceBody body;
    body.on = on;
    body.xpos = XposOf(x) & 0xFF;
    body.ypos = YposOf(y) & 0xFF;
    body.facing = facing < 0 ? 0 : 1;
    body.action = action;
    body.timer = timer;
    body.pose = pose;
    // $B6,X is written by the overlap of a step. An actor who did not step
    // keeps the byte, so the log must not substitute Bruce's probe.
    if (kind == 1 && !frameHit[1].valid) {
        body.hit = ninja.groundHit;
    } else if (kind == 2 && !frameHit[2].valid) {
        body.hit = yamo.groundHit;
    } else {
        body.hit = HitBits(FrameContact(kind));
    }
    if (kind == 0) {
        body.health = g.health & 0xFF;
        body.hold = g.hold;
    } else if (kind == 1) {
        body.health = ninja.health & 0xFF;
        body.hold = ninja.hold;
    } else {
        body.health = yamo.health & 0xFF;
        body.hold = yamo.hold;
    }
    return body;
}

TraceBody TraceBruce() {
    TraceBody body = TraceOf(true, g.x, g.y, g.facing, g.action, g.actionTimer, g.pose, 0);
    if (ConsumeSpawnHit()) {
        body.hit = 1;
    }
    return body;
}

TraceBody TraceYamo() {
    return TraceOf(ninja.on, ninja.x, ninja.y, ninja.facing, ninja.action, ninja.actionTimer, ninja.pose, 1);
}

TraceBody TraceNinja() {
    return TraceOf(yamo.on, yamo.x, yamo.y, yamo.facing, yamo.action, yamo.actionTimer, yamo.pose, 2);
}
