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

#include "savegame.h"

#include "config.h"
#include "game.h"
#include "room.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <sstream>

// ---- SaveFile ----

SaveFile::Section* SaveFile::Get(const std::string& section) {
    for (Section& s : sections_) {
        if (s.name == section) {
            return &s;
        }
    }
    return nullptr;
}

const SaveFile::Section* SaveFile::Get(const std::string& section) const {
    for (const Section& s : sections_) {
        if (s.name == section) {
            return &s;
        }
    }
    return nullptr;
}

void SaveFile::Set(const std::string& section, const std::string& key, const std::string& value) {
    Section* s = Get(section);
    if (s == nullptr) {
        sections_.push_back(Section{section, {}});
        s = &sections_.back();
    }
    for (auto& kv : s->keys) {
        if (kv.first == key) {
            kv.second = value;
            return;
        }
    }
    s->keys.emplace_back(key, value);
}

const std::string* SaveFile::Find(const std::string& section, const std::string& key) const {
    const Section* s = Get(section);
    if (s == nullptr) {
        return nullptr;
    }
    for (const auto& kv : s->keys) {
        if (kv.first == key) {
            return &kv.second;
        }
    }
    return nullptr;
}

bool SaveFile::HasSection(const std::string& section) const {
    return Get(section) != nullptr;
}

void SaveFile::Rename(const std::string& section, const std::string& from, const std::string& to) {
    Section* s = Get(section);
    if (s == nullptr) {
        return;
    }
    for (auto& kv : s->keys) {
        if (kv.first == from) {
            kv.first = to;
            return;
        }
    }
}

void SaveFile::RemoveSection(const std::string& section) {
    for (size_t i = 0; i < sections_.size(); ++i) {
        if (sections_[i].name == section) {
            sections_.erase(sections_.begin() + static_cast<std::ptrdiff_t>(i));
            return;
        }
    }
}

std::string SaveFile::Text(bool header) const {
    std::string out;
    if (header) {
        out += "; Bruce Lee Remake save game. Each section is the state of one part of the game.\r\n";
    }
    bool first = true;
    for (const Section& s : sections_) {
        if (!header && s.name == "Save") {
            continue;
        }
        if (!first) {
            out += "\r\n";
        }
        first = false;
        out += "[" + s.name + "]\r\n";
        for (const auto& kv : s.keys) {
            out += kv.first + "=" + kv.second + "\r\n";
        }
    }
    return out;
}

bool SaveFile::Parse(const std::string& text, std::string& error) {
    sections_.clear();
    std::string current;
    size_t pos = 0;
    int lineNo = 0;
    while (pos <= text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string::npos) {
            end = text.size();
        }
        std::string line = text.substr(pos, end - pos);
        pos = end + 1;
        ++lineNo;
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) {
            line.pop_back();
        }
        size_t lead = 0;
        while (lead < line.size() && (line[lead] == ' ' || line[lead] == '\t')) {
            ++lead;
        }
        line = line.substr(lead);
        if (lineNo == 1 && line.size() >= 3 && static_cast<unsigned char>(line[0]) == 0xEF) {
            line = line.substr(3);  // UTF-8 byte order mark
        }
        if (line.empty() || line[0] == ';' || line[0] == '#') {
            if (end == text.size()) {
                break;
            }
            continue;
        }
        if (line[0] == '[') {
            const size_t close = line.find(']');
            if (close == std::string::npos || close < 2) {
                error = "line " + std::to_string(lineNo) + " is not a section name";
                return false;
            }
            current = line.substr(1, close - 1);
            if (Get(current) == nullptr) {
                sections_.push_back(Section{current, {}});
            }
        } else {
            const size_t eq = line.find('=');
            if (eq == std::string::npos || eq == 0 || current.empty()) {
                error = "line " + std::to_string(lineNo) + " is not Key=Value inside a section";
                return false;
            }
            std::string key = line.substr(0, eq);
            while (!key.empty() && (key.back() == ' ' || key.back() == '\t')) {
                key.pop_back();
            }
            std::string value = line.substr(eq + 1);
            size_t v = 0;
            while (v < value.size() && (value[v] == ' ' || value[v] == '\t')) {
                ++v;
            }
            Set(current, key, value.substr(v));
        }
        if (end == text.size()) {
            break;
        }
    }
    return true;
}

// ---- SaveIO ----

std::string SaveIO::Where(const char* key) const {
    return "[" + section_ + "] " + key;
}

void SaveIO::Fail(const std::string& message) {
    if (error_.empty()) {
        error_ = message;
    }
}

void SaveIO::Section(const char* name) {
    section_ = name;
    if (!Saving() && !file_.HasSection(section_)) {
        Fail("The section [" + section_ + "] is missing.");
    }
}

const std::string* SaveIO::Read(const char* key) {
    if (!error_.empty()) {
        return nullptr;
    }
    const std::string* v = file_.Find(section_, key);
    if (v == nullptr) {
        Fail(Where(key) + " is missing.");
    }
    return v;
}

void SaveIO::Write(const char* key, const std::string& value) {
    file_.Set(section_, key, value);
}

bool SaveIO::ParseInt(const char* key, const std::string& text, long long& out) {
    const char* s = text.c_str();
    char* end = nullptr;
    errno = 0;
    if (text.size() > 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        out = std::strtoll(s + 2, &end, 16);
    } else {
        out = std::strtoll(s, &end, 10);
    }
    if (text.empty() || end == s || *end != 0 || errno != 0) {
        Fail(Where(key) + " is not a number: " + text);
        return false;
    }
    return true;
}

void SaveIO::Value(const char* key, bool& v) {
    if (Saving()) {
        Write(key, v ? "True" : "False");
        return;
    }
    const std::string* text = Read(key);
    if (text == nullptr) {
        return;
    }
    bool value;
    if (*text == "True" || *text == "1") {
        value = true;
    } else if (*text == "False" || *text == "0") {
        value = false;
    } else {
        Fail(Where(key) + " must be True or False: " + *text);
        return;
    }
    if (Loading()) {
        v = value;
    }
}

void SaveIO::Value(const char* key, int& v, int lo, int hi) {
    if (Saving()) {
        Write(key, std::to_string(v));
        return;
    }
    const std::string* text = Read(key);
    long long value = 0;
    if (text == nullptr || !ParseInt(key, *text, value)) {
        return;
    }
    if (value < lo || value > hi) {
        Fail(Where(key) + " is out of range: " + *text);
        return;
    }
    if (Loading()) {
        v = static_cast<int>(value);
    }
}

void SaveIO::Hex(const char* key, int& v, int lo, int hi) {
    if (Saving()) {
        char buf[16];
        std::snprintf(buf, sizeof buf, "0x%06X", static_cast<unsigned>(v));
        Write(key, buf);
        return;
    }
    Value(key, v, lo, hi);
}

void SaveIO::Value(const char* key, uint8_t& v) {
    int value = v;
    Value(key, value, 0, 255);
    if (Loading() && Ok()) {
        v = static_cast<uint8_t>(value);
    }
}

void SaveIO::Value(const char* key, int8_t& v) {
    int value = v;
    Value(key, value, -128, 127);
    if (Loading() && Ok()) {
        v = static_cast<int8_t>(value);
    }
}

namespace {

constexpr size_t kHexLine = 32;

int HexDigit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

std::string ToHex(const uint8_t* v, size_t n) {
    static const char kDigits[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(n * 2);
    for (size_t i = 0; i < n; ++i) {
        out += kDigits[v[i] >> 4];
        out += kDigits[v[i] & 15];
    }
    return out;
}

}  // namespace

void SaveIO::WriteHex(const char* key, const uint8_t* v, size_t n) {
    if (n <= kHexLine) {
        Write(key, ToHex(v, n));
        return;
    }
    for (size_t line = 0; line * kHexLine < n; ++line) {
        const size_t at = line * kHexLine;
        const size_t count = n - at < kHexLine ? n - at : kHexLine;
        Write((std::string(key) + "." + std::to_string(line)).c_str(), ToHex(v + at, count));
    }
}

bool SaveIO::ReadHexInto(const char* key, size_t n, std::vector<uint8_t>& out) {
    out.clear();
    out.reserve(n);
    const auto decode = [&](const char* name, const std::string& text, size_t want) {
        if (text.size() != want * 2) {
            Fail(Where(name) + " should hold " + std::to_string(want) + " bytes.");
            return false;
        }
        for (size_t i = 0; i < want; ++i) {
            const int hi = HexDigit(text[i * 2]);
            const int lo = HexDigit(text[i * 2 + 1]);
            if (hi < 0 || lo < 0) {
                Fail(Where(name) + " is not hex.");
                return false;
            }
            out.push_back(static_cast<uint8_t>(hi * 16 + lo));
        }
        return true;
    };
    if (n <= kHexLine) {
        const std::string* text = Read(key);
        return text != nullptr && decode(key, *text, n);
    }
    for (size_t line = 0; line * kHexLine < n; ++line) {
        const size_t at = line * kHexLine;
        const size_t count = n - at < kHexLine ? n - at : kHexLine;
        const std::string name = std::string(key) + "." + std::to_string(line);
        const std::string* text = Read(name.c_str());
        if (text == nullptr || !decode(name.c_str(), *text, count)) {
            return false;
        }
    }
    return true;
}

void SaveIO::Bytes(const char* key, uint8_t* v, size_t n) {
    if (Saving()) {
        WriteHex(key, v, n);
        return;
    }
    std::vector<uint8_t> bytes;
    if (!ReadHexInto(key, n, bytes)) {
        return;
    }
    if (Loading()) {
        for (size_t i = 0; i < n; ++i) {
            v[i] = bytes[i];
        }
    }
}

void SaveIO::Vector(const char* key, std::vector<uint8_t>& v, size_t size, size_t other) {
    const std::string sizeKey = std::string(key) + ".Size";
    if (Saving()) {
        Write(sizeKey.c_str(), std::to_string(v.size()));
        WriteHex(key, v.data(), v.size());
        return;
    }
    // Read the size here rather than through Value, which stores nothing
    // in a Check pass.
    const std::string* sizeText = Read(sizeKey.c_str());
    long long n = 0;
    if (sizeText == nullptr || !ParseInt(sizeKey.c_str(), *sizeText, n)) {
        return;
    }
    if (static_cast<size_t>(n) != size && static_cast<size_t>(n) != other) {
        Fail(Where(sizeKey.c_str()) + " is " + std::to_string(n) + ", which this program cannot use.");
        return;
    }
    std::vector<uint8_t> bytes;
    if (n > 0 && !ReadHexInto(key, static_cast<size_t>(n), bytes)) {
        return;
    }
    if (Loading()) {
        v = bytes;
    }
}

bool SaveIO::ReadInts(const char* key, std::vector<int>& out, int lo, int hi) {
    out.clear();
    const std::string* text = Read(key);
    if (text == nullptr) {
        return false;
    }
    std::istringstream in(*text);
    std::string word;
    while (in >> word) {
        long long value = 0;
        if (!ParseInt(key, word, value)) {
            return false;
        }
        if (value < lo || value > hi) {
            Fail(Where(key) + " has a value out of range: " + word);
            return false;
        }
        out.push_back(static_cast<int>(value));
    }
    return true;
}

void SaveIO::List(const char* key, std::vector<int>& v, size_t maxCount) {
    if (Saving()) {
        Ints(key, v.data(), v.size());
        return;
    }
    std::vector<int> values;
    if (!ReadInts(key, values, INT_MIN, INT_MAX)) {
        return;
    }
    if (values.size() > maxCount) {
        Fail(Where(key) + " holds too many numbers.");
        return;
    }
    if (Loading()) {
        v = values;
    }
}

void SaveIO::Ints(const char* key, int* v, size_t n, int lo, int hi) {
    if (Saving()) {
        std::string out;
        for (size_t i = 0; i < n; ++i) {
            if (i > 0) {
                out += ' ';
            }
            out += std::to_string(v[i]);
        }
        Write(key, out);
        return;
    }
    std::vector<int> values;
    if (!ReadInts(key, values, lo, hi)) {
        return;
    }
    if (values.size() != n) {
        Fail(Where(key) + " should hold " + std::to_string(n) + " numbers.");
        return;
    }
    if (Loading()) {
        for (size_t i = 0; i < n; ++i) {
            v[i] = values[i];
        }
    }
}

void SaveIO::Bools(const char* key, bool* v, size_t n) {
    std::vector<int> values(n);
    for (size_t i = 0; i < n; ++i) {
        values[i] = v[i] ? 1 : 0;
    }
    Ints(key, values.data(), n, 0, 1);
    if (Loading() && Ok()) {
        for (size_t i = 0; i < n; ++i) {
            v[i] = values[i] != 0;
        }
    }
}

void SaveIO::SBytes(const char* key, int8_t* v, size_t n) {
    std::vector<int> values(n);
    for (size_t i = 0; i < n; ++i) {
        values[i] = v[i];
    }
    Ints(key, values.data(), n, -128, 127);
    if (Loading() && Ok()) {
        for (size_t i = 0; i < n; ++i) {
            v[i] = static_cast<int8_t>(values[i]);
        }
    }
}

// ---- The whole game ----

namespace {

// The test log leaves out the settings a load does not take back, since
// they are not part of the game. A save file has them all.
bool gWriteAllOptions = true;

// Every setting is written, so a save shows what the game was played with.
// A load takes back only the three that change the play itself.
void SyncOptions(SaveIO& io) {
    io.Section("Options");
    io.Value("InfiniteLives", gConfig.infiniteLives);
    io.Value("EnemiesCantHitBruce", gConfig.enemiesCantHitBruce);
    io.Value("FixBugsInOriginal", gConfig.fixBugsInOriginal);
    if (!io.Saving() || !gWriteAllOptions) {
        return;
    }
    // Written for information only. A load leaves these as they are.
    io.Value("StartRoom", gConfig.startRoom);
    io.Value("ShowTitleScreen", gConfig.showTitleScreen);
    io.Value("FullScreen", gConfig.fullScreen);
    io.Value("ShowCRTFilter", gConfig.showCrtFilter);
    io.Value("CrtCurve", gConfig.crtCurve);
    io.Value("CrtScanlines", gConfig.crtScanlines);
    io.Value("CrtBlur", gConfig.crtBlur);
    io.Value("CrtVignette", gConfig.crtVignette);
    io.Value("Sound", gConfig.sound);
    io.Value("TopScore", gConfig.topScore);
    io.Value("PauseOnFocusLoss", gConfig.pauseOnFocusLoss);
}

void SyncAll(SaveIO& io) {
    SyncOptions(io);
    SyncGameState(io);
    SyncBruceState(io);
    SyncFighterState(io);
    SyncRoomState(io);
    SyncRoomFxState(io);
    SyncCollisionState(io);
    SyncDrawState(io);
    SyncStageState(io);
}

std::string SaveName() {
    SYSTEMTIME now{};
    GetLocalTime(&now);
    char buf[96];
    std::snprintf(buf, sizeof buf, "%04u-%02u-%02u %02u:%02u   Room %d   Completed %d",
                  now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, g.roomId, CompletedGames());
    return buf;
}

std::string SaveTime() {
    SYSTEMTIME now{};
    GetLocalTime(&now);
    char buf[32];
    std::snprintf(buf, sizeof buf, "%04u-%02u-%02uT%02u:%02u:%02u", now.wYear, now.wMonth, now.wDay,
                  now.wHour, now.wMinute, now.wSecond);
    return buf;
}

// Format 0 never shipped. It exists so the upgrade path is tested: the test
// writes a format 1 save with Score renamed to Points and Format=0, and the
// load must turn it back. A real step looks the same: rename, split, or add
// keys until the file reads as the next format.
void UpgradeFrom0To1(SaveFile& file) {
    file.Rename("Game", "Points", "Score");
}

using UpgradeStep = void (*)(SaveFile&);
// kUpgrades[n] turns format n into format n + 1.
constexpr UpgradeStep kUpgrades[] = {UpgradeFrom0To1};
static_assert(sizeof kUpgrades / sizeof kUpgrades[0] == kSaveFormat, "one upgrade step per older format");

bool UpgradeSave(SaveFile& file, int from, std::string& error) {
    if (from > kSaveFormat) {
        error = "This save was made by a newer version of Bruce Lee Remake (save format " +
                std::to_string(from) + "). This version reads up to format " + std::to_string(kSaveFormat) + ".";
        return false;
    }
    if (from < 0) {
        error = "The save format number is not valid.";
        return false;
    }
    for (int format = from; format < kSaveFormat; ++format) {
        kUpgrades[format](file);
    }
    file.Set("Save", "Format", std::to_string(kSaveFormat));
    return true;
}

}  // namespace

std::string SaveGameText(bool header) {
    SaveFile file;
    if (header) {
        file.Set("Save", "Format", std::to_string(kSaveFormat));
        file.Set("Save", "Program", "Bruce Lee Remake");
        file.Set("Save", "Name", SaveName());
        file.Set("Save", "Saved", SaveTime());
    }
    SaveIO io(file, SaveIO::Mode::Save);
    gWriteAllOptions = header;
    SyncAll(io);
    gWriteAllOptions = true;
    return file.Text(header);
}

bool ReadSaveGame(const std::string& text, SaveFile& file, std::string& error) {
    if (!file.Parse(text, error)) {
        error = "The save file is damaged: " + error + ".";
        return false;
    }
    const std::string* format = file.Find("Save", "Format");
    if (format == nullptr) {
        error = "This is not a Bruce Lee Remake save game. [Save] Format is missing.";
        return false;
    }
    char* end = nullptr;
    const long from = std::strtol(format->c_str(), &end, 10);
    if (format->empty() || *end != 0) {
        error = "The save format number is not valid.";
        return false;
    }
    if (!UpgradeSave(file, static_cast<int>(from), error)) {
        return false;
    }
    SaveIO check(file, SaveIO::Mode::Check);
    SyncAll(check);
    if (!check.Ok()) {
        error = "The save file is damaged. " + check.Error();
        return false;
    }
    return true;
}

void ApplySaveGame(SaveFile& file) {
    SaveIO io(file, SaveIO::Mode::Load);
    SyncAll(io);
}

// ---- Slots ----

namespace {
std::wstring gSaveFolder;
}  // namespace

void SetSaveFolder(const std::wstring& folder) {
    gSaveFolder = folder;
}

std::wstring SaveFolder() {
    if (!gSaveFolder.empty()) {
        return gSaveFolder;
    }
    return ConfigDirectory() + L"\\Saves";
}

std::wstring SlotPath(int slot) {
    if (slot <= 0) {
        return SaveFolder() + L"\\quick.sav";
    }
    return SaveFolder() + L"\\slot" + std::to_wstring(slot) + L".sav";
}

bool ReadTextFile(const std::wstring& path, std::string& text) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    std::ostringstream all;
    all << in.rdbuf();
    text = all.str();
    return true;
}

bool WriteTextFile(const std::wstring& path, const std::string& text, std::wstring& error) {
    // Write beside the file and then replace it, so a failed write never
    // leaves half a save in the slot.
    const std::wstring temp = path + L".tmp";
    {
        std::ofstream out(temp, std::ios::binary | std::ios::trunc);
        if (!out) {
            error = L"Could not write " + temp;
            return false;
        }
        out << text;
        out.close();
        if (!out) {
            error = L"Could not write " + temp;
            DeleteFileW(temp.c_str());
            return false;
        }
    }
    if (!MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        error = L"Could not write " + path;
        DeleteFileW(temp.c_str());
        return false;
    }
    return true;
}

bool SlotUsed(int slot) {
    return GetFileAttributesW(SlotPath(slot).c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring SlotName(int slot) {
    std::string text;
    if (!ReadTextFile(SlotPath(slot), text)) {
        return L"(empty)";
    }
    SaveFile file;
    std::string error;
    const std::string* name = nullptr;
    if (file.Parse(text, error)) {
        name = file.Find("Save", "Name");
    }
    if (name == nullptr || name->empty()) {
        return L"(unreadable)";
    }
    std::wstring wide;
    for (const char c : *name) {
        wide += static_cast<wchar_t>(static_cast<unsigned char>(c));
    }
    return wide;
}

bool SaveSlot(int slot, std::wstring& error) {
    const std::wstring folder = SaveFolder();
    if (!CreateDirectoryW(folder.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) {
        error = L"Could not create the folder " + folder;
        return false;
    }
    return WriteTextFile(SlotPath(slot), SaveGameText(true), error);
}

bool ReadSlot(int slot, SaveFile& file, std::wstring& error) {
    std::string text;
    if (!ReadTextFile(SlotPath(slot), text)) {
        error = L"Could not read " + SlotPath(slot);
        return false;
    }
    std::string why;
    if (!ReadSaveGame(text, file, why)) {
        error.assign(why.begin(), why.end());
        return false;
    }
    return true;
}
