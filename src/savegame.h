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

#include <climits>
#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <utility>
#include <vector>

// A save game is a text file in the style of config.ini:
//
//   [Save]
//   Format=1
//   Name=2026-11-26 14:32   Room 5   Completed 1
//   [Game]
//   Score=0x00A3F2
//   ...
//
// [Save] says which format wrote the file. A newer program upgrades an
// older format in UpgradeSave before anything is read. Every other section
// is one source file's state, written and read by that file's Sync function.

// Bump this when a key is renamed, split, or given a new meaning, and add an
// upgrade step in savegame.cpp that turns the old keys into the new ones.
constexpr int kSaveFormat = 1;

// Sections in file order, each with its keys in file order.
class SaveFile {
public:
    void Set(const std::string& section, const std::string& key, const std::string& value);
    const std::string* Find(const std::string& section, const std::string& key) const;
    bool HasSection(const std::string& section) const;
    // Rename a key in place. Nothing happens when it is missing.
    void Rename(const std::string& section, const std::string& from, const std::string& to);
    void RemoveSection(const std::string& section);

    // header false leaves out [Save], which holds the time. The test log
    // compares the rest frame by frame.
    std::string Text(bool header = true) const;
    bool Parse(const std::string& text, std::string& error);

private:
    struct Section {
        std::string name;
        std::vector<std::pair<std::string, std::string>> keys;
    };
    Section* Get(const std::string& section);
    const Section* Get(const std::string& section) const;
    std::vector<Section> sections_;
};

// One pass over the state. Save writes each value into the file. Check reads
// and validates every value without storing any. Load stores them. A load
// runs Check first, so a damaged file changes nothing.
class SaveIO {
public:
    enum class Mode { Save, Check, Load };
    SaveIO(SaveFile& file, Mode mode) : file_(file), mode_(mode) {}

    bool Saving() const { return mode_ == Mode::Save; }
    // Load only. Code that turns a read value into something else, such as
    // an index back into a pointer, runs when this is true.
    bool Loading() const { return mode_ == Mode::Load; }
    bool Ok() const { return error_.empty(); }
    const std::string& Error() const { return error_; }

    void Section(const char* name);
    void Value(const char* key, bool& v);
    void Value(const char* key, int& v, int lo = INT_MIN, int hi = INT_MAX);
    void Value(const char* key, uint8_t& v);
    void Value(const char* key, int8_t& v);
    // Written as 0x plus six hex digits. Scores and marks read better that way.
    void Hex(const char* key, int& v, int lo = 0, int hi = 0xFFFFFF);

    // Byte arrays are hex, 32 bytes to a line. A longer array is split into
    // Key.0, Key.1, and so on.
    void Bytes(const char* key, uint8_t* v, size_t n);
    // Other arrays are one line of numbers separated by spaces.
    void Ints(const char* key, int* v, size_t n, int lo = INT_MIN, int hi = INT_MAX);
    void Bools(const char* key, bool* v, size_t n);
    void SBytes(const char* key, int8_t* v, size_t n);
    // A list whose length is part of the state, at most maxCount long.
    void List(const char* key, std::vector<int>& v, size_t maxCount);

    template <size_t N>
    void Array(const char* key, uint8_t (&v)[N]) { Bytes(key, v, N); }
    template <size_t N, size_t M>
    void Array(const char* key, uint8_t (&v)[N][M]) { Bytes(key, &v[0][0], N * M); }
    template <size_t N>
    void Array(const char* key, int (&v)[N]) { Ints(key, v, N); }
    template <size_t N, size_t M>
    void Array(const char* key, int (&v)[N][M]) { Ints(key, &v[0][0], N * M); }
    template <size_t N>
    void Array(const char* key, bool (&v)[N]) { Bools(key, v, N); }
    template <size_t N, size_t M>
    void Array(const char* key, bool (&v)[N][M]) { Bools(key, &v[0][0], N * M); }

    // A byte vector with Key.Size first. The size read back must be one of
    // the two given, so a picture is never shorter than the code expects.
    void Vector(const char* key, std::vector<uint8_t>& v, size_t size, size_t other = SIZE_MAX);

    // Report a problem the caller found itself, such as a bad combination.
    void Fail(const std::string& message);

private:
    const std::string* Read(const char* key);
    void Write(const char* key, const std::string& value);
    bool ParseInt(const char* key, const std::string& text, long long& out);
    bool ReadInts(const char* key, std::vector<int>& out, int lo, int hi);
    bool ReadHexInto(const char* key, size_t n, std::vector<uint8_t>& out);
    void WriteHex(const char* key, const uint8_t* v, size_t n);
    std::string Where(const char* key) const;

    SaveFile& file_;
    Mode mode_;
    std::string section_;
    std::string error_;
};

// Each source file keeps its own state private and writes it here.
void SyncGameState(SaveIO& io);       // game.cpp: g, the score marks, the waiting player
void SyncBruceState(SaveIO& io);      // bruce.cpp
void SyncFighterState(SaveIO& io);    // fighter.cpp: the ninja and Yamo
void SyncRoomFxState(SaveIO& io);     // roomfx.cpp: the room hooks, sound effects, noise memory
void SyncRoomState(SaveIO& io);       // room.cpp: lamps and room bonuses
void SyncCollisionState(SaveIO& io);  // collision.cpp: the frame clock
void SyncDrawState(SaveIO& io);       // draw.cpp
void SyncStageState(SaveIO& io);      // main.cpp: pause and the options-page tune

// The whole state as save text. header false leaves out [Save].
std::string SaveGameText(bool header = true);

// Parse, upgrade, and check a save without changing anything. On success
// file holds the upgraded text ready for ApplySave.
bool ReadSaveGame(const std::string& text, SaveFile& file, std::string& error);

// Store a checked save into the game. The gameplay options come back with
// it: InfiniteLives, EnemiesCantHitBruce, and FixBugsInOriginal. The other
// settings stay as they are.
void ApplySaveGame(SaveFile& file);

// Slot 0 is the quick save. Slots 1-8 are the menu's numbered slots.
constexpr int kSaveSlots = 8;
std::wstring SaveFolder();
// The tests keep their slots in their own folder.
void SetSaveFolder(const std::wstring& folder);
std::wstring SlotPath(int slot);
// The [Save] Name line, "(empty)" when there is no file, or "(unreadable)".
std::wstring SlotName(int slot);
bool SlotUsed(int slot);

bool WriteTextFile(const std::wstring& path, const std::string& text, std::wstring& error);
bool ReadTextFile(const std::wstring& path, std::string& text);

// Write the current game to the slot. False with a message on failure.
bool SaveSlot(int slot, std::wstring& error);
// Read and check a slot. Nothing changes yet.
bool ReadSlot(int slot, SaveFile& file, std::wstring& error);
