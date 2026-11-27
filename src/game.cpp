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

#include "game.h"

#include "collision.h"
#include "config.h"
#include "room.h"
#include "savegame.h"

#include <cstdint>

// Colodore palette
const uint32_t kPalette[16] = {
    0xFF000000u, 0xFFFFFFFFu, 0xFF96282Eu, 0xFF5BD6CEu,
    0xFF9F2DADu, 0xFF41B936u, 0xFF2724C4u, 0xFFEFF347u,
    0xFF9F4815u, 0xFF5E3500u, 0xFFDA5F66u, 0xFF474747u,
    0xFF787878u, 0xFF91FF84u, 0xFF6864FFu, 0xFFAEAEAEu,
};

Game g;

// $03. Player 1 is Bruce until a two-player fall flips it.
int gBrucePlayer = 0;

namespace {

// $4392. clear_work_ram copies $438B, which is 00 9C 40.
// $4395 is the other player's mark, swapped with it in between_lives.
int lifeMark = 0x009C40;
int waitingMark = 0x009C40;
// $438B-$438D, the mark clear_work_ram copies into a new game. A bug in
// the original changes its high byte. top_replace at $31B8 copies four
// bytes from $41 into $4388, so a new top score also stores $44, the
// raster split index, over $438B. The next game's first extra fall is
// then at $xx9C40, not 40000. room01.vsf holds 02 9C 40 there, which is
// 171072. Nothing clears it, so it lasts until the program restarts.
// FixBugsInOriginal keeps 00 9C 40.
int firstMark = 0x009C40;
// refresh_top runs once a frame, after the blows. The adds of a frame are
// compared there, so a top that moved this frame is stored there too.
bool topMoved = false;
// $439F, $41, and $29 of the waiting player. Falls below zero means he is out.
int waitingLives = 4;
int waitingScore = 0;
int waitingRoom = 0;
// $438E. Added into the mark after each extra fall. 00 75 30.
constexpr int kLifeStep = 0x007530;
// $43BD. $10 is the state init_hardware leaves, with the word showing.
int captionTimer = 0x10;

bool MarkReached(int score, int mark) {
    for (int shift = 16; shift >= 0; shift -= 8) {
        const int have = (score >> shift) & 0xFF;
        const int need = (mark >> shift) & 0xFF;
        if (have < need) {
            return false;
        }
    }
    return true;
}

}  // namespace

void GrantLife() {
    // The trainer's LDA patch covers this INC and the one in room 16.
    if (gConfig.infiniteLives) {
        g.lives = g.lifeStock;
        return;
    }
    g.lives = (g.lives + 1) & 0xFF;
}

void SyncLives() {
    if (gConfig.infiniteLives) {
        g.lives = g.lifeStock;
    }
}

void MirrorScore();

void ResetScore() {
    g.score = 0;
    lifeMark = gConfig.fixBugsInOriginal ? 0x009C40 : firstMark;
    MirrorScore();
}

void RefreshTopMark() {
    if (!topMoved) {
        return;
    }
    topMoved = false;
    if (gConfig.fixBugsInOriginal) {
        return;
    }
    firstMark = (SplitIndexAt(RefreshTopRaster()) << 16) | (firstMark & 0xFFFF);
}

void PlantProgress(const uint8_t* ram) {
    // $28 is a signed fall count. $FF is already out. The score and the
    // extra-life mark travel with the snapshot, or the next fall can
    // grant a life on one side only.
    const int lives = ram[0x28];
    g.lives = lives >= 0x80 ? lives - 256 : lives;
    g.score = (ram[0x41] << 16) | (ram[0x42] << 8) | ram[0x43];
    lifeMark = (ram[0x4392] << 16) | (ram[0x4393] << 8) | ram[0x4394];
    firstMark = (ram[0x438B] << 16) | (ram[0x438C] << 8) | ram[0x438D];
    topMoved = false;
    const int waiting = ram[0x439F];
    waitingLives = waiting >= 0x80 ? waiting - 256 : waiting;
    MirrorScore();
}

int WaitingLives() {
    return waitingLives;
}

void PlantWaitingPlayer(const uint8_t* ram) {
    // $42C9 two players, $03 whose turn it is, and the $439F block, which
    // is $28-$43 of the player who waits: $43A0 his room, $43A1 his lamp
    // counts, $43B7 his difficulty, and $43B8-$43BA his score. $4395 is
    // his extra-fall mark.
    gTwoPlayers = ram[0x42C9] != 0;
    gBrucePlayer = ram[0x03] & 1;
    waitingRoom = ram[0x43A0];
    waitingScore = (ram[0x43B8] << 16) | (ram[0x43B9] << 8) | ram[0x43BA];
    waitingMark = (ram[0x4395] << 16) | (ram[0x4396] << 8) | ram[0x4397];
    PlantWaitingLamps(ram);
    PlantWaitingDifficulty(ram[0x43B7]);
}

namespace {

// $1781. A byte already negative is the player who is out. Subtracting would
// still leave the sign bit set, so the count stays negative. A smaller
// non-negative count becomes 0, which is still a life.
void TakeIdleFalls(int& lives, int count) {
    if (lives < 0 || count <= 0) {
        return;
    }
    if (lives < count) {
        lives = 0;
        return;
    }
    lives -= count;
}

}  // namespace

void MirrorScore() {
    // $41 $42 $43. noise_byte reads these when the pointer walks across them.
    NoisePoke(0x41, (g.score >> 16) & 0xFF);
    NoisePoke(0x42, (g.score >> 8) & 0xFF);
    NoisePoke(0x43, g.score & 0xFF);
}

void SnapshotWaitingPlayer() {
    waitingLives = g.lives;
    waitingScore = g.score;
    waitingRoom = g.roomId;
    waitingMark = lifeMark;
    CopyCollectedLamps();
    CopyDifficulty();
}

bool PartnerStillIn() {
    return gTwoPlayers && waitingLives >= 0;
}

bool HandTurn() {
    if (!PartnerStillIn()) {
        return false;
    }
    gBrucePlayer ^= 1;
    return true;
}

void SwapWaitingPlayer() {
    if (!PartnerStillIn()) {
        return;
    }
    const int lives = g.lives;
    g.lives = waitingLives;
    waitingLives = lives;
    const int score = g.score;
    g.score = waitingScore;
    waitingScore = score;
    MirrorScore();
    const int room = g.roomId;
    g.roomId = waitingRoom;
    waitingRoom = room;
    const int mark = lifeMark;
    lifeMark = waitingMark;
    waitingMark = mark;
    ExchangeCollectedLamps();
    ExchangeDifficulty();
}

void PenalizeBothFalls(int count) {
    TakeIdleFalls(g.lives, count);
    TakeIdleFalls(waitingLives, count);
}

int TopScore() {
    return gConfig.topScore;
}

void ResetTopScore() {
    gConfig.topScore = g.score & 0xFFFFFF;
}

void TickPlayerCaption() {
    captionTimer -= 1;
    if (captionTimer == 0) {
        captionTimer = 0x20;
        // $1AA5 prints string 0, three spaces, at row 0, column $2C.
        MirrorPrintString(0, 0, 0x2C);
    } else if (captionTimer == 0x10) {
        // $1AB7 prints string $03+1, the player's word.
        MirrorPrintString(gBrucePlayer + 1, 0, 0x2C);
    }
}

void SetCaptionTimer(int timer) {
    captionTimer = timer & 0xFF;
}

int CaptionNoiseY() {
    // $1A9B and $1AAF both print, and print_string stops on the marker
    // with Y still at $2F. The reload is the only way the count is $20.
    // A frame that does not print keeps the Y the previous blit or retire left.
    if (captionTimer == 0x20 || captionTimer == 0x10) {
        return 0x2F;
    }
    return NoiseIndex();
}

void ResetPlayerCaption() {
    captionTimer = 0x11;
    TickPlayerCaption();
}

bool PlayerCaptionOn() {
    // Tick reloads 0 to $20, so the blank half is $11-$20 and the word is $01-$10.
    return captionTimer <= 0x10;
}

void FormatFalls(int lives, char out[3]) {
    int value = lives & 0xFF;
    int tens = 0;
    while (value >= 10) {
        value -= 10;
        tens += 1;
    }
    const int packed = static_cast<int>(static_cast<uint8_t>(tens << 4)) | value;
    const int hi = (packed >> 4) & 0x0F;
    const int lo = packed & 0x0F;
    auto glyph = [](int nibble) -> char {
        if (nibble < 10) {
            return static_cast<char>('0' + nibble);
        }
        return static_cast<char>('A' + (nibble - 10));
    };
    out[0] = glyph(hi);
    out[1] = glyph(lo);
    out[2] = '\0';
}

void AddScoreByte(int slot, int amount) {
    if (slot < 0 || slot > 2) {
        return;
    }
    // $3175. add_score clears the addend $25-$27, then stores the amount in
    // $25,X. apply_score only reads them, so they stay for noise_byte.
    NoisePoke(0x25, 0);
    NoisePoke(0x26, 0);
    NoisePoke(0x27, 0);
    NoisePoke(0x25 + slot, amount & 0xFF);
    const int add = (amount & 0xFF) << ((2 - slot) * 8);
    g.score = (g.score + add) & 0xFFFFFF;
    MirrorScore();
    // $313A. High byte first. A lower byte that is still under its pair
    // waits, even when the total is already past the mark.
    if (MarkReached(g.score, lifeMark)) {
        lifeMark = (lifeMark + kLifeStep) & 0xFFFFFF;
        GrantLife();
    }
    // refresh_top only compares in play. The demo redraws the score.
    if (gConfig.topScore < g.score && !DemoMode()) {
        gConfig.topScore = g.score;
        topMoved = true;
    }
}

void AddKnockout(int victimKind) {
    if (victimKind == 1) {
        AddScoreByte(1, 0x01);
        AddScoreByte(2, 0xC2);
        return;
    }
    if (victimKind != 0) {
        AddScoreByte(2, 0xC8);
    }
}

// Intentional bug, kept so a killing landing scores the way the original
// does. force_knockdown at $2C51 jumps back to this test at $2BF9 while the
// landing bit is still set, so 50 and the knockout repeat until the health
// byte is positive again. FixBugsInOriginal pays that landing once instead.
int ApplyStomp(int health, int victimKind, bool scored) {
    int h = health & 0xFF;
    int adds = 0;
    for (;;) {
        if (scored) {
            AddScoreByte(2, 0x32);
            adds += 1;
        }
        h = (h - 5) & 0xFF;
        if ((h & 0x80) == 0) {
            NoteStompIrqs(adds);
            return h;
        }
        if (scored) {
            AddKnockout(victimKind);
            adds += victimKind == 1 ? 2 : (victimKind != 0 ? 1 : 0);
        }
    }
}

void SyncGameState(SaveIO& io) {
    // Not saved: g.charset is, but g.frames is bruce.bin as loaded, and
    // g.pixels is redrawn by Compose after a load.
    io.Section("Game");
    io.Value("X", g.x);
    io.Value("Y", g.y);
    io.Value("Facing", g.facing, -1, 1);
    io.Value("Pose", g.pose, 0, kFrames - 1);
    io.Value("Tick", g.tick);
    io.Value("Action", g.action);
    io.Value("ActionTimer", g.actionTimer);
    io.Value("Hold", g.hold);
    io.Value("Repeat", g.repeat);
    io.Value("PrevState", g.prevState);
    io.Value("FallSlide", g.fallSlide);
    io.Hex("Score", g.score);
    io.Value("Lives", g.lives);
    io.Value("LifeStock", g.lifeStock);
    io.Value("Health", g.health);
    io.Value("Room", g.roomId, 0, 19);
    io.Value("CharsetId", g.charsetId, 0, 3);
    io.Array("Bands", g.bands);
    io.Array("Splits", g.splits);
    io.Vector("Charset", g.charset, g.charset.size());
    io.Vector("Screen", g.room, g.room.size());
    io.Vector("Color", g.color, g.color.size());
    io.Value("TwoPlayers", gTwoPlayers);
    io.Value("HumanOpponent", gHumanOpponent);
    io.Value("OpponentYielded", gOpponentYielded);
    io.Value("BrucePlayer", gBrucePlayer, 0, 1);
    io.Hex("LifeMark", lifeMark);
    io.Hex("WaitingMark", waitingMark);
    io.Hex("FirstMark", firstMark);
    io.Value("TopMoved", topMoved);
    io.Value("WaitingLives", waitingLives, -128, 255);
    io.Hex("WaitingScore", waitingScore);
    io.Value("WaitingRoom", waitingRoom, 0, 19);
    io.Value("CaptionTimer", captionTimer, 0, 255);
}
