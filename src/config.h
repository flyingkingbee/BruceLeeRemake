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

#include <string>

// Settings from config.ini in the user folder, with the command line
// applied on top.
struct Config {
    // True keeps FALLS on the full starting count for the whole game.
    bool infiniteLives = false;
    // True: the Ninja and Yamo still attack. A blow from either one never
    // lands on Bruce.
    bool enemiesCantHitBruce = false;
    // Off keeps the original landing loop. On pays 50 once, and one knockout.
    bool fixBugsInOriginal = false;
    int startRoom = 0;
    bool showTitleScreen = true;
    // Borderless window the size of the monitor. A double-click toggles it.
    // The maximize button turns it on.
    bool fullScreen = false;
    bool showCrtFilter = false;
    // Parts of the television filter. They apply while showCrtFilter is on.
    bool crtCurve = true;
    bool crtScanlines = true;
    bool crtBlur = true;
    bool crtVignette = true;
    // False leaves the rooms and the options page silent.
    bool sound = true;
    // Player 1's controller id from Settings. Empty uses the first gamepad
    // found. The word none is no controller. Nothing is read when that pad
    // is not connected and no other pad is free.
    std::wstring gamepad;
    // Player 2's controller, Yamo when the options page is set to Opponent.
    // Empty uses the second gamepad. The word none is no controller.
    std::wstring gamepad2;
    // $4388. The best score, shown as TOP. Written with the other settings
    // when the program closes. 0 until a score passes it.
    int topScore = 0;
    // True opens the welcome wizard before the game window. The wizard
    // writes false when it closes.
    bool firstTimeRun = true;
    // False leaves the game running when another program is in front.
    // Command line only. SaveConfig does not write it.
    bool pauseOnFocusLoss = true;
};

extern Config gConfig;

// Read config.ini from the user folder, %APPDATA%\Bruce Lee Remake, or the
// folder ConfigFolder=<dir> names. A player can always write there, even
// when the game is installed in Program Files. When the file is missing it
// starts as a copy of the template: config.local.ini or config.ini beside
// the exe, one folder up, or two folders up. The save games beside the
// template are copied too. Then apply Name=Value words from the command
// line. A trace run (Oracle=) reads no file, and SaveConfig writes none.
void LoadConfig(const wchar_t* commandLine);

// Start room clamped into 0 .. 19. 0 is the opening room.
int ClampedStartRoom();

// Write the live settings to config.ini in the user folder. Comments and
// blank lines stay. The template beside the exe is never written.
void SaveConfig();

// The user folder that holds config.ini and Saves, with no trailing slash.
std::wstring ConfigDirectory();
std::wstring UserDirectory();

// Where F12 puts screenshots: Pictures\Bruce Lee Remake. With ConfigFolder=,
// or in a trace run, the user folder instead, so tests stay out of Pictures.
std::wstring PicturesDirectory();

// Create a folder and its parents. True when it is there afterwards.
bool MakeDirectory(const std::wstring& folder);
