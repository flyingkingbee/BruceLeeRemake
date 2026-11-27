# Bruce Lee remake

This is a Windows port of the first room of the Commodore 64 game. It is a C++ rewrite of the rules, not an emulator. The pictures and the collision test come from the original bytes.

A frame is one pass through `Tick` in `src/bruce.cpp`, then the window copies `g.pixels` to the screen. A call is due every 59.852ms, three PAL screens of 19656 cycles at 985248 Hz, the count the game stores in `$48`. `FramePacer` in `src/main.cpp` waits on a high-resolution timer for a deadline that moves on by that much each call, so the logic and the paint come out of the frame instead of adding to it. A late frame is made up by a shorter wait, and a loop held for more than a frame, by a dialog or a window drag, restarts the deadline from now. The controller list is read on the game thread and takes tens of ms, so it is read only at start and after a `WM_DEVICECHANGE`, a few times over the next seconds (`NotePadDevicesChanged` in `src/pad.cpp`). The window opens on the title picture. A double-click toggles a borderless full screen, and the maximize button turns it on. Space or Enter opens the options page. F3 and F5 change the two options there, and F7 opens the PLAYER page, which holds and then starts the room. Arrow keys move Bruce. Up jumps. On a ladder, up and down climb. Down on a floor ducks. Space punches while he is standing, and flying-kicks once a walk has already been going. Escape leaves full screen and closes Settings. It does not close the program. F12, and File > Take Screenshot, save a picture of the render window as `ScreenShotXX.png` in `Pictures\Bruce Lee Remake`. The two digits are the first number from 00 through 99 that is not already a file. A camera flash then shows in the upper right of the picture for a moment. P pauses, and so does the menu button on a gamepad. The view button opens Settings, and closes it when Settings is already open. The game also pauses when another program takes the keyboard. Settings is this program, so opening it leaves the game running. `PauseOnFocusLoss=False` on the command line leaves the game running when another program is in front, and that switch is not written back to config.ini. A click on the picture or the caption, P, or the menu button resumes. While paused, a blue band across the picture reads PAUSED in the PLAYER 1 letters, and the actors, the countdowns, and the sound hold. A gamepad is read only while this program owns the foreground window.

The settings live in `%APPDATA%\Bruce Lee Remake\config.ini`, so the game never writes to the folder it is installed in. When that file is missing, `LoadConfig` copies the template into place first: `config.local.ini` or `config.ini` beside the exe, then one folder up, then two folders up, the first one found. The `*.sav` files in a `Saves` folder beside the template are copied too. `ConfigFolder=<folder>` uses another folder instead of AppData. A trace run (`Oracle=`) reads no config file and writes none, so it runs on the defaults and the command line alone. `Name=Value` on the command line overrides the file. The Settings window changes these while the game is running, and the program writes them back to the AppData file when it closes. The template is never written. The names and the defaults are the commented lines in the root `config.ini`. `ShowTitleScreen` chooses the title picture, the options page, and the PLAYER page. `FullScreen` starts borderless over the monitor. A double-click toggles it, and the maximize button turns it on. `ShowCRTFilter` redraws that picture into the same rectangle. `CrtCurve`, `CrtScanlines`, `CrtBlur`, and `CrtVignette` each keep one part of that filter. They apply while `ShowCRTFilter` is on. Off leaves the nearest-neighbor scale.

## How a frame runs

1. `main.cpp` loads the room files into `g`. With `ShowTitleScreen` on, it paints `title.bin` and waits for Space or Enter. That opens the options page in `front.bin`. F7 then shows the PLAYER page. Then `PlaceBruce` stands him on the floor to the right of the lamp. `ShowTitleScreen` off skips those three pages.
2. Each logic frame, `Tick` reads the arrow keys and space. Opposite directions cancel. Space is read as a level, so holding it repeats once the move allows it.
3. If the pose hold is running, it counts down and the stick is not read. Climb holds for 3 logic frames. Duck holds for 1. Every other Bruce move holds for 0.
4. Otherwise the repeat count reloads to 6 when the state is idle or has just changed, and counts down while the same state continues. Left or right walks two xpos steps (4 screen pixels) until that count reaches 0, then three steps (6 pixels). The two stride pictures alternate every logic frame. The screen edge clears the walk. A wall refuses the step and leaves the walk in place.
5. Up on a floor, with no ladder and no wall in the overlap, starts the standing jump (state `$05`, timer 15). That frame does not move. Three counts stay still, one count rises 4 pixels, four counts rise 2, six counts drop 2, and the last count stays still. The top of the hop is 12 pixels. A ladder overlap cancels the jump. A wall overlap refuses to start it. Up with left or right starts the sideways jump (states `$06` and `$07`, timer 15): 4 screen pixels sideways on each of the 15 counts, rising 11 pixels and then dropping 11. On a ladder that stick clears the state.
6. Space during a walk, once the repeat count is below 4, starts the flying kick (states `$0C` and `$0D`, timer 12) instead of the next step. The kick waits until the following logic frame to move. It then rises 1 pixel on each of three counts, travels flat for seven, and drops 1 on each of the last two. Every one of those 12 counts also steps 2 screen pixels. A ladder or a wall cancels it. If he is still in the air when the timer ends, he falls. Space with no direction, and no ladder, is the punch (state `$11`): 4 logic frames of the punch picture, then 4 frames of standing while the stick is ignored. Up with space jumps. Down with space ducks.
7. Down on a floor ducks (state `$1A`). Down-left and down-right turn him to face that way, except at the far screen edge. He does not walk while the duck is held. On a ladder, down climbs and a diagonal clears the state.
8. Up or down on a ladder climbs 3 pixels, or 4 once the repeat count has run out, then holds for 3 logic frames. The two climb pictures alternate while he climbs or walks across a ladder. Standing on a ladder keeps the climb picture already showing. Only an overlap counts: he does not reach below his feet. The screen edge is the only thing that cuts a burst short.
9. With neither ground nor a ladder under him, the first airborne frame drops 1 pixel. Later falling frames drop 2. The second falling frame also steps one xpos toward the way he faces when his torso is still on a ledge. The next frame lands him if his feet overlap ground or a ladder, so he rests in the first ground pixels. Open air shows the arms-out jump. Overlapping a wall shows the legs together.
10. The picture is chosen after the step, from the overlap taken before it. The standing jump, sideways jump, and flying kick follow the timers above. A fresh move shows its first picture on the frame it starts, and moves on the frame after.
11. If that new picture sits inside a wall, he is pushed sideways until it does not.
12. `Compose` paints the room, Bruce, and the score line into `g.pixels`. The window shows that buffer scaled up with nearest-neighbor filtering. `ShowCRTFilter` resamples the same rectangle. Curve, scanlines, blur, and vignette can each be left out. The filter shades every window pixel on the CPU, so `ApplyCrtChanged` keeps last frame's result: it compares `g.pixels` with the last picture in 8 by 8 tiles and reshades only the 64 by 16 blocks whose source reach (the blur's columns and the beam's rows) touches a changed tile, and `Paint` uploads only those rectangles. A new size, new options, or a new bitmap shades everything. Each part of the filter is a template switch, and an AVX2 path does eight pixels at a time with the same float operations in the same order, so every path gives the same bytes. The work is shared with the Windows thread pool in blocks.

Before the move, the overlap is tested for a lamp. Bit 1 of that test is nibble 2, the hanger, and the same bit on a floor. The cells looked at are his column and the two to the right, on his tile row and the row below. A cell tiled `$13`, `$14`, or `$31` that is in this room's lamp list is replaced with the bare mount (`$12` or `$1F` on both rows of the pair) and 125 is added to the score. The six lamps are columns 31 and 38 of tile row 7, and columns 2, 25, 29, and 38 of tile row 10.

The lamp flicker is `$40BC`, once per logic frame, before that test. Three counters each reload to a count from 1 to 15. Tile `$31` rewrites rows 2 and 3 of shadow glyph `$B1`, and tile `$14` does the same to glyph `$94`. The new byte keeps the mount and moves one dot through the four multicolor pairs: background, `$D022`, `$D023`, and the ink. Every lamp that uses that tile changes on the same frame. The bare mount is a different glyph, so a taken lamp stays still. The same pass also writes glyphs `$93` and `$86`, and glyph `$E7`. This room does not show those three.

`g.x` and `g.y` are the top-left of his sprite in screen pixels. The screen is 320 by 200. A character cell is 8 by 8 pixels, and there are 40 columns and 25 rows.

## Source files

| File | Role |
| --- | --- |
| `src/game.h`, `src/game.cpp` | Screen size, the C64 palette, and the `Game` state every other file shares |
| `src/load.cpp` | `LoadFile` reads one data file. It looks beside the exe, then in `data\` one directory up, then in `data\` beside the exe. A missing file or a short read comes back empty |
| `src/config.cpp` | `LoadConfig` reads `config.ini` from `%APPDATA%\Bruce Lee Remake`, seeding it from the template beside the exe or the workspace on the first start, then applies the command line. `SaveConfig` writes it back. `PicturesDirectory` is where screenshots go |
| `src/ui.cpp` | The menu bar, the Settings window, and the About box |
| `src/scene.cpp` | Turns one screen pixel into a color. `BandAt` is the raster split (background, `$D022`, `$D023`). `PixelColor` returns a palette index, or -1 where the cell is empty or the same as the background |
| `src/collision.cpp` | The original overlap test. `Probe` reports wall and floor for the pose he is about to use. `PoseWall` asks the same question for one picture only |
| `src/bruce.cpp` | Which picture to show, where he starts, and `Tick` |
| `src/draw.cpp` | `Compose` fills `g.pixels`. `ComposeTitle` paints `title.bin` |
| `src/crt.cpp` | `ApplyCrt` resamples `g.pixels` when `ShowCRTFilter` is on, and `ApplyCrtChanged` reshades only what changed since the last frame |
| `src/front.cpp` | `ComposeMenu` and `ComposePlayerUp` paint the two pages in `front.bin` |
| `src/main.cpp` | The window, Direct2D, and the message loop |

`StandPose` and `WalkPose` return an index into `bruce.bin`. `PoseBytes` points at one of the two pictures inside that pose: plane 0 is the yellow body, plane 1 is the black detail drawn on top.

## Palette

`kPalette` is the Colodore C64 palette, the one VICE 3.10 displays, packed as `0xAARRGGBB`. Indexes used by this room:

| Index | Color | Where it shows up |
| --- | --- | --- |
| 0 | black | sprite detail, score text, collision ink `$08` |
| 1 | white | upper raster colors |
| 2 | red | middle and lower `$D022` |
| 7 | yellow | Bruce's body |
| 11 (`$0B`) | dark grey | background above raster `$97` |
| 12 (`$0C`) | grey | background from raster `$97` down |
| 14 (`$0E`) | light blue | top `$D023`, and collision ink `$0E` |
| 15 | light grey | the score bar |

Screen y 0 is raster line 50. `BandAt` changes colors at raster `$78` and `$97`.

## Character cells

The screen is 40 columns by 25 rows of cells. Each cell is 8 by 8 screen pixels. `charset.bin` holds the pictures. `room0.bin` holds a tile number for every cell, and that number picks a picture.

One tile number is written into two cells, one above the other, so that number covers 8 by 16 pixels. The two cells use different glyphs:

- The odd row draws glyph N, the primary half.
- The even row under it draws glyph N+128, the shadow half.

Each of those glyphs is its own 8 by 8 picture. Tile 11, the floor, is the clear case: glyph 11 is empty, so row 23 is blank, and glyph 139 is the stripe, so row 24 is the line you see.

The shadow name comes from the original loader. It writes the tile into the top cell and the same number with bit 7 set into the bottom cell. Bit 7 selects the upper 1KB of the character set, which is the other half of that picture. Each row keeps its own byte and its own 8 pixel rows. The next pair starts on the following row.

The pairs in this room are (3, 4), (5, 6), and so on through (23, 24). Both bytes of a pair hold the same tile number. Rows 0–2 are the score area and are empty (`$DC`) in `room0.bin`. The score text is drawn over row 0.

The packed game data stored each tile once. This file is the expanded screen, so the number is already in both cells. Rendering just reads the cell.

A hardware cell is only 8 pixels tall, so a taller picture is two cells stacked. In multicolor mode one colored dot is two screen dots wide and one screen dot tall, which makes it look flat. The artwork is 8 of those rows. Painting each row twice makes the dot square and the picture 16 screen lines tall: 8 in the primary cell and 8 in the shadow cell.

Multicolor mode is on for the whole screen, and a cell can still opt out. Bit 3 of its color byte selects the wide dots. The room bytes are `$08` and `$0E`, so the level is 160 dots across. The score digits leave that bit clear. Each bit is one screen dot, and a digit is 8 dots wide. Those shapes are the ordinary Commodore font.

The level art is 22 character rows, 176 screen lines. With every art row painted twice, that is 88 unique rows. The level is 160 by 88 dots. The other 24 screen lines are the score row and the two blank rows under it.

## Data files

The running game loads the first four for the room. `title.bin` is the original title picture, drawn when `ShowTitleScreen` is on.

### `data/charset.bin` — 2048 bytes

The room's character set, 256 glyphs of 8 bytes. A byte is one row of a glyph. Bit 7 is the leftmost pixel.

The file is two halves of 1024 bytes:

- Glyphs 0–127 are the primary half. Odd character rows use these.
- Glyphs 128–255 are the shadow half. Even character rows use these.

The room file stores a tile number without the extra 128. `PixelColor` and the collision test add 128 on even rows. Each half of a glyph is four source rows, and each of those rows is stored twice, which is the vertical doubling described above. Rows 2 and 3 of glyphs `$93`, `$94`, `$B1`, `$86`, and `$E7` are rewritten each time a lamp timer elapses, so those bytes in memory drift away from the file.

Pixels are multicolor. A byte holds four dots, two bits each, from the top of the byte:

| Bits | Meaning |
| --- | --- |
| `00` | the band background from `BandAt` |
| `01` | the band's `$D022` color |
| `10` | the band's `$D023` color |
| `11` | the ink in `room0.col` |

Each dot is drawn as two screen pixels, so a cell is 8 pixels wide.

The byte for screen pixel `(x, y)` is:

```
tile = room0[(y / 8) * 40 + (x / 8)]
half = 128 on an even character row, else 0
byte = charset[(tile + half) * 8 + (y & 7)]
```

Tile `$DC` is an empty cell. It has no ink and no collision.

### `data/room0.bin` — 1000 bytes

The expanded screen, 25 rows by 40 columns, one byte per cell. Byte `row * 40 + col` is the tile number. In each pair, the odd row and the even row under it store the same number. Rows 0–2 are `$DC`.

### `data/room0.col` — 1000 bytes

Color RAM, one byte per cell, same index as `room0.bin`.

The low three bits are the collision property. Bit 3 turns multicolor on. The values in this room are `$08` and `$0E`:

| Byte | Property (`byte & 7`) | Drawn ink | What collision does with a solid pattern |
| --- | --- | --- | --- |
| `$08` | 0 | black | wall. A walk or a jump into it is rejected |
| `$0E` | 6 | blue | floor or climb, from the nibble. It does not stop a walk |

The drawn ink is the low three bits. `$08` is black and `$0E` is light blue.

### `data/bruce.bin` — 5712 bytes

`tools/extract_pictures.py` writes this file, `ninja.bin`, and `yamo.bin` from the original sprite libraries in a VICE snapshot, along with `bruce_scan.bin`, `ninja_scan.bin`, and `yamo_scan.bin`. The plain files are what the hardware sprite shows. The `_scan` files are what the overlap test scans. The original copies a mode-1 library into the sprite with `$5B61,X` rows, but `expand_library` builds the page that `overlap_actors` scans with `$5B61,X + 1` rows, so the scanned picture of a punch, an extended kick, a duck, or a late knockdown has one more row. That row is the source bytes just past the picture, and it never shows on screen. Drawing reads the plain files and the collision code reads the `_scan` files.

Thirty-four poses. Poses 0–22 are listed below. Poses 23–33 are the open-air fall, the spawn pictures, the strikes, and the knockdowns. Each pose is two planes, and each plane is 21 rows of 4 bytes (32 pixels). Bit 7 is the leftmost pixel. One sprite bit is one screen pixel. Left and right are separate drawings; nothing is mirrored.

The walk and the standing jump use one source byte per row (library mode 0). After the VIC doubles it, the ink is 16 pixels and the other 16 in the row are empty. The punch, and the black plane of each extended flying kick, use two source bytes per row (mode 1), so the ink can reach all 32 pixels.

```
offset = (pose * 2 + plane) * 84
plane 0 = yellow body
plane 1 = black hair, eyes, and legs
row byte = offset + y * 4 + (x / 8)
```

| Pose | Picture |
| --- | --- |
| 0 | stand, facing right |
| 1 | stand, facing left |
| 2, 3 | walk left, the two strides |
| 4, 5 | walk right, the two strides |
| 6 | legs together: a fall that overlaps a wall, and jump count 15 |
| 7 | jump tuck, counts 12–14 and 1 |
| 8 | jump, arms out, counts 2–11. Also a fall in open air |
| 9, 10 | sideways jump left, tucked then extended |
| 11, 12 | sideways jump right, tucked then extended |
| 13 | punch left |
| 14 | punch right |
| 15, 16 | flying kick left, tucked then extended |
| 17, 18 | flying kick right, tucked then extended |
| 19, 20 | climb, the two steps |
| 21 | duck, facing left |
| 22 | duck, facing right |

The two strides alternate every logic frame. While he is walking, both strides are tested, so the wider one cannot step into a wall that the next stride could not leave. Every other state uses the picture already chosen.

Punch left is drawn 16 pixels left of `g.x`. The black plane of flying kick left, extended, and the black plane of the right-facing duck, are shifted the same way. That is the original adjustment of `$9E` by -8, so the torso stays where the stand picture was and the fist, the leg, or the duck's detail hangs off that side.

These are the original library images, in order: 2/3, 0/1, `$0E`/`$0F`, `$10`/`$11`, `$12`/`$13`, `$14`/`$15`, 8/9, `$1E`/`$1F`, `$20`/`$21`, `$22`/`$23`, `$24`/`$25`, `$26`/`$27`, `$28`/`$29`, 5/4, 7/6, `$16`/`$17`, `$18`/`$19`, `$1A`/`$1B`, `$1C`/`$1D`, `$0A`/`$0B`, `$0C`/`$0D`, `$40`/`$41`, `$42`/`$43`. The first of each pair is the yellow plane and the second is the black detail, except the punch: libraries 4 and 6 are black (`$F0`) and 5 and 7 are yellow (`$F7`), so those pairs are stored yellow first. Library 8 is the legs-together picture. The jump the player sees for most of the arc is library `$20`. The sideways jump is libraries `$22`–`$29`. The punch is libraries 4–7. The flying kick is libraries `$16`–`$1D`. The climb is libraries `$0A`–`$0D`. The duck is libraries `$40`–`$43`.

### `data/title.bin` — 8000 bytes

The title picture, copied from address `$2000` in the title snapshot. It is a multicolor bitmap, not a row of 320 pixels followed by the next row. The VIC chip stores 25 rows of 40 cells, and each cell is eight bytes, one byte per pixel row of that 8 by 8 cell. Each byte holds four pixel pairs.

```
byte = ((y / 8) * 40 + (x / 8)) * 8 + (y & 7)
pair = (byte >> (6 - ((x & 7) / 2) * 2)) & 3
```

`$D011` is `$3B` and `$D016` is `$18`, so multicolor bitmap mode is on. `$D018` is `$18`: the bitmap is `$2000` and the video matrix is `$0400`. Every matrix byte is `$1E`, and color RAM is `$0C`. `$D021` is black. Pair `00` is that background, `01` is the high nibble (white), `10` is the low nibble (light blue), and `11` is color RAM (grey). `$D020` is the light blue border and is not part of the picture. The bitmap paints that same light blue along its outer edge, so on the Commodore it continues the border. Those pixels are drawn in the grey of the picture field. Light blue inside the picture is the buildings and the frame. `ShowTitleScreen` paints it and waits for Space or Enter. That opens the options page. `ShowTitleScreen=False` skips the picture, the options page, and the PLAYER page, and opens the room.

### `data/front.bin` — 5136 bytes

The options page and the PLAYER page, copied from the menu snapshot. 2048 bytes are the charset at `$8000`, then 2048 bytes of the charset at `$8800`, then the 1000 screen codes at `$8C00`, then the 32 player-line glyphs at `$4A5D`, then the 8 digit glyphs at `$4A7D`. The stored screen has 1 PLAYER and COMPUTER highlighted. F3 and F5 run `flip_menu_a` and `flip_menu_b`. F7 shows PLAYER 1, which `between_rooms` holds for `$40` PAL frames, or `$80` when two players are selected.

## Collision

`Probe` is the test the original runs before it will keep a move. It ORs the yellow and black planes into one mask, then ANDs that mask with the character bytes underneath. Each AND byte is split into two 4-bit values.

`$5592` rolls `$4F3F` in first, so that counter is bit 3 and `$4F3C` is bit 0. `$1DCA` keeps him from falling when bit 0 or bit 2 is set (`and #$05`). Bit 3 is the push-out at `$1CC7`. A wall does not hold him up.

Bit 0 is the same nibbles on every property. The solid nibbles are bit 3 on property 0 and bit 2 on any other property. The swap is `$55E6`, `$5658`, and `$56CA`. Bit 2 is a climb. Up and down on that overlap climb, including where bit 0 is set as well. Down on bit 0 with no bit 2 ducks.

| AND nibble | Flags | Result |
| --- | --- | --- |
| 1, 4, or 5 | bit 0 | floor. The roof dots are nibble 5 |
| 6 or 9 | bits 0 and 1 | floor. Bit 1 is not a Bruce floor test |
| 2, 8, or 10 | bit 1 | neither. He falls through these |
| 7 or 13 | bit 0, plus bit 3 or bit 2 | floor. A wall on property 0, a climb on any other property |
| 3, 11, 12, 14, or 15 | bit 3 or bit 2 | a wall on property 0, a climb otherwise. Not a floor |
| anything else | none | ignored |

A pixel past the edge of the 320 by 200 screen counts as a wall.

The roof tile `$2A` is `00 00 00 00 55 55 FF FF` on its shadow half. `$55` is nibble 5, so a fall steps onto that first dotted row and stays. The brown row under the sole stays visible. `$FF` is nibble 15. On a property-6 cell that is a climb, which is the black line capping the hole, so up and down there climb. On property 0 the same line is a wall and blocks a sideways step. The floor tile `$11` is `00 00 55 55 AA AA FF FF`. `$AA` is nibble 10, so he falls through it and stops on the `$55`. The statue's other patterns are not in the table, so he runs through that art.

The ladder rails are climb nibbles on property 6, so overlapping one sticks and does not push him out. He climbs through the rails and walks off the top. The same test is what makes the property-6 roof line climbable. A climb burst does not stop on the floor underneath; the next logic frame sees the ladder bit clear and the move ends.

## Audio

`data/sound.bin` is the 64K RAM from the room snapshot. The effect scripts and the options tune are the bytes at `$2509`, `$EB03`, and `$E000`. The port runs those bytes on a 6581 clocked at the PAL rate. A voice, or the tune, advances once per PAL frame. Effects play in the rooms. The options page plays the tune. The title picture, the PLAYER page, and the game-over screen are silent. `Sound=False` in config.ini turns it off.

## Testing against the original

The regression tests compare the port with the original game frame by frame. Both sides write the same trace. One block per logic frame starts with `frame N`, and its `bruce`, `yamo`, and `ninja` lines give each body's position, facing, state, timer, and collision bits. `yamo` also starts with the active bit. The port adds the pose to those lines, plus `room`, `hp`, `hold`, `clock`, `visit`, `fx`, and `input` lines for debugging. The tests compare only the shared fields.

### The port's trace mode

`Oracle=roomNN` on the command line runs the port without a window, one logic frame per step, and writes the trace. `Frames=N` sets the length. `Script=FILE` feeds the stick, one line per frame: a hex stick nibble, then the fire bit, 1 for pressed. A third and fourth column are the other joystick and its button, which a human opponent plays Yamo with. `Seed=N` draws the sticks from a seeded generator instead. `Snap=FILE` loads a VICE snapshot in place of the room's own: the fighters, the room's moving parts, the score, the noise memory, and Bruce's stand scan page (`PlantSnapshotTrace` in `src/fighter.cpp`). `Poke=ADDR:VAL`, both hex and repeatable, changes a byte of the snapshot first: `Poke=42CA:1` is a human opponent, `Poke=40:1` the harder second round, and `Poke=42C9:1` two players. `Demo=1` starts the attract demo from a cold start in room 0 instead, as `attract_demo` does, with `Script=` holding `0 1`, the zeros the demo reads from `$F300`. `Start=1` is a new game left from the options page with the button: the page's memory from `boot02_menu.vsf`, then `clear_work_ram` and room 0, through the same `StartNewGame` the window uses after the PLAYER page. `Poke=` then sets the options, `42C9` two players, `42CA` a human opponent, and `1383`/`1384` 0 for a left-handed joystick. `Keys=F3,F5,L,R,SL,SR` presses those keys on the port's options page first, in order, through `PressMenuKey`, the handler the window's page uses, so the options come from the key handling instead of pokes. `S` in front is Shift, and `F7` is the start itself. A snapshot's `$1383`/`$1384` set the handedness too, and a script's stick is turned the way the original turns the joystick. `Out=FILE` names the trace. The tests also pass `PauseOnFocusLoss=False FixBugsInOriginal=False InfiniteLives=False`.

### Building a case

1. `tools/vice_trace.py` records the original's trace. It needs VICE's `x64sc` on the PATH, and its first comment shows the usage. It starts `x64sc` with its binary monitor, loads the snapshot, and stops at `frame` (`$1BC2`) after each logic frame. Breakpoints at `$16BD` and `$16CD`, where the raster interrupt stores the stick into `$98` and the fire button into `$9B`, replace them with the script's values.
2. `tools/add_trace_case.py NAME SNAPSHOT TRACE SCRIPT [--frames N]` writes `tests/reference/NAME.txt` and adds the case to `tests/cases.json`, or replaces the case with that name. It reads the room from `$29` in the snapshot. Room 18 runs as `Oracle=room17`, because the trace mode has no room 18 entry and the snapshot replaces the room anyway.
3. `tests/run_traces.py` runs every case on the release build and reports the first frame where a body differs. It needs Python 3 and no other packages. Build the release, then run `python tests/run_traces.py` from the workspace root. Name cases to run only those, for example `python tests/run_traces.py hunt04 fight12`. The exit code is 0 when every case passes. `python tests/run_all.py` runs these and the real-time timing cases together.

### Alignment

A snapshot can stop anywhere in a frame. `add_trace_case.py` reads the program counter and checks whether `step_actors` has already read the stick this frame.

- **Already read (shift 0).** The rest of the frame needs no input, so the port runs the plain script, and its frame N is the reference's frame N. These are the frame wait (`$1C32`-`$1C36`), `between_lives`'s wait (`$0F47`-`$0F71`), `blit_sprites` and the routines it calls (`$2584`-`$277F`), and `check_bruce_down` (`$2D55`-`$2D78`).
- **Not yet read (shift 1).** The port's first frame finishes the snapshot's frame and reads the stick, so the script repeats its first line. That is `SCRIPT_lag.txt`, which the tool writes beside the script if it is missing. The port's frame N + 1 is then the reference's frame N.

`--shift 0` or `--shift 1` overrides the choice. `--poke ADDR=VAL` records a case for a changed snapshot: the case names the unchanged file and passes `Poke=` to the port. `--start` records a case from a trace that began on the options page (the logger's `menustart` flag, from `boot02_menu.vsf`): the case runs `Start=1` with shift 0. `--keys F3,SL` goes with a trace recorded with the logger's `menukeys=` flag, and passes the same list to the port as `Keys=`.

### Capped cases

The port does not count cycles. It estimates the raster (`collision.cpp`) and decides from that whether a frame sees the new stick (`slowOverlap` in `bruce.cpp`). In the two-fighter rooms most frames run past their third interrupt, so a small error builds up, and in time one interrupt lands on the other side of some read. Then the noise counter at `$16` moves one byte. That changes whether the ninja's wake is held off for 16 frames, or which side a fighter appears on. Or the frame reads the stick one frame early or late. Both versions play correctly from there, but the traces separate. `--frames` stops a case at the last frame that matches, and the case still checks everything before that. A trace whose VICE recording skips the game over and starts a new game, with Bruce at 26,196 and timer 4, stops at the frame before.

These differences are accepted on purpose. A cycle-exact frame clock would remove them, but a player cannot see a ninja waking 16 frames later or a stick read one frame early, so the port does not model cycles. That covers only differences that come from raster timing: the noise counter at `$16` (the ninja's wake hold-off, the spawn side), which frame first sees a new stick, and which frame `$D01E` first shows a sprite overlap. A noise byte the port never writes, or any other difference, is a bug, and a case is capped only once the divergence is shown to be timing (see the end of "Finding a divergence"). Long sessions are tested past these splits with sync cases instead.

### Sync cases

A long case can run past those timing splits in sync mode. Record it with the logger's `sync` flag: the trace in `tmp/oracle_vice_<stem>_sync.txt` then also holds every noise read (`nb Y value lo hi frame`), the `$D01E` value `read_sprite_hits` takes each frame (`hr value frame`), and the `$98` that Bruce's `on_ground` reads at `$1DD0` (`st value frame`). The port's `Sync=FILE` replays exactly those three things, the parts raster timing decides, and nothing else:

- At each noise read, the port takes VICE's pointer instead of its own, so the number of interrupts since the last read stops mattering. It still reads its own noise memory. When that byte differs from VICE's, it uses VICE's byte so the replay goes on. A byte the raster samples or counts is logged as `sync timing`: the xpos samples and contact bytes `$B9`–`$BE` and `$67`, the interrupt counters `$7F`, `$80`/`$81` and `$87`/`$88`, the color-split counters `$44` and `$F4`, the voice pointers `$F6`–`$FB`, since a voice frees itself one command per raster, `$18`–`$1A`, which the start delay leaves after a number of passes the raster decides, and `$0E`/`$0F`, blit_sprites' buffer pointer: `$277D` picks the buffer, and a death or a door blits twice close together, so whether an interrupt flips it in between is timing. While room 18's `paint_sparks` reads, the stack bytes below its live return addresses (`$0160`–`$01F9`) count as timing too: the deepest interrupt wrote them last. Any other byte is a `sync value`: a mirroring bug.
- A read with a different Y, or a frame with more or fewer reads than VICE made, is a `sync split`, a difference in the game logic. The replay stops syncing there.
- `Resolve()` in `src/fighter.cpp` takes the frame's `$D01E` from VICE and builds the three contact groups from its bits. Frames where the port's own value differs are logged as `sync hit`.
- Bruce's step in `src/bruce.cpp` takes the previous or the new stick to match VICE's `$98`, instead of the raster estimate. Frames where the estimate differed are logged as `sync stick`. A `$98` that is neither stick is a `sync value`.

The events and a summary line go to `tmp/port_sync.txt`. `add_trace_case.py --sync` copies the `nb` and `hr` lines to `tests/sync/NAME.txt` and adds `"sync"` to the case, and `run_traces.py` fails a sync case on a `sync split` or a `sync value` as well as on its bodies. Sync cases sit beside the capped strict ones (`long71` and `long71sync`): the strict case still checks the frames before the first timing split without help.

The `st` line carries the fire bit too (`st stick fire frame`), because a human's input changes in the middle of a frame and a script keeps only the last value of each frame. The port takes both from VICE.

### Recording a play session

A session played by hand in VICE becomes a sync case in three steps.

1. **Record.** Start `x64sc` with `-eventsnapshotdir DIR\ -eventstartmode 0 -eventstartsnapshot start.vsf -eventendsnapshot end.vsf`, where DIR is an empty folder. Load `boot02_menu.vsf`, then choose Snapshot, Start/Stop Recording History while on the options page: mode 0 saves the machine as it is then into `start.vsf`. Play, then stop the recording the same way. Milestones (Alt+E to set, Alt+U to return) are fine, as VICE trims the event list. The game reads player 1 from port 1. Mode 1 is for continuing an earlier recording and fails without one.
2. **Replay.** `bash tools/vice_debug.sh replay FRAMES DIR NAME` loads `DIR/start.vsf` and plays the joystick events from `DIR/end.vsf` itself. VICE's own playback cannot be used: started with `-playback` it resets after loading the snapshot, and the logger's breakpoints do not fire during a playback started from the menu. The logger keeps the CPU clock from the raster position at every stop, corrected once a logic frame and at each port read by CIA1 timer A, which runs throughout with the period 16422. (The interrupt runs once a video frame at the same line, so the raster alone loses whole frames.) It feeds each event's value to the game's port reads: the options page's button (`$08F8`), `wait_button_up` (`$0951`), the pause test (`$1A1E`), the interrupt's stick and fire (`$16AC`, `$16CD`), and the keyboard scan, where a joystick pulls its port's lines low too (`REPLAY_MASKS`). The run prints the frame where the recording ends, and the game there matches `end.vsf`. It writes `tmp/capture_NAME.txt`, the stick script, and `tmp/oracle_vice_NAME_sync.txt`.
3. **Add the case.** `python tools/add_trace_case.py NAME referencematerial/emulatorsnapshots/boot02_menu.vsf tmp/oracle_vice_NAME_sync.txt tests/scripts/NAME.txt --start --sync --frames END`, with the script copied to `tests/scripts/` and END the frame where the recording ended. The recordings are kept in `referencematerial/recordings/`: `play1` is `play1sync`.

### Save games

A save is a text file in the style of `config.ini`, written by `src/savegame.cpp`. `[Save]` holds `Format`, the save format number, and `Name`, the date, room, and finished-game count the slot menus show. Every other section is one source file's state. Each of `game.cpp`, `bruce.cpp`, `fighter.cpp`, `room.cpp`, `roomfx.cpp`, `collision.cpp`, `draw.cpp`, and `main.cpp` has a `Sync...State(SaveIO&)` function beside its own variables, and the same function writes, checks, and loads them, so a field cannot be written one way and read another. Byte arrays are hex, 32 bytes to a line. Pointers are saved as which picture file or which fighter they point at. A variable a save leaves out has a comment there saying why: trace and test state, picture files loaded at start, and window state.

A load reads the whole file into sections and keys first. A `Format` newer than `kSaveFormat` is refused. An older one runs the upgrade steps in `savegame.cpp`, one per format, which rename, split, or fill in keys until the file reads as the current format. Then a check pass reads every value without storing any, and a missing section or key, a short array, or a value out of range refuses the file. Only a file that passes is stored. A new key or a renamed one needs `kSaveFormat` raised and an upgrade step that turns the old file into the new keys.

`tests/run_saves.py` checks that a save holds the whole game. The port is compared with itself, so it needs no VICE recording. Every non-sync case runs once with `StateLog=FILE`, which writes a hash of the full save text after every frame, and again with `SaveAt=K,...` at several frames: early, middle, late, around each door and lost life, and on the first frame of each state Bruce and the fighters pass through. Each save is then loaded over a different game (room 0, room 13, a fresh start, room 5, or the attract demo) with `LoadGame=FILE ScriptSkip=K`, and that run must match the first, trace and state hash, from frame K on. On a state mismatch the script dumps both runs' save text at that frame with `StateDump=N` and names the first key that differs. Each case also runs with `SaveEvery=1`, a save and a load after every frame, sync cases included. Further checks load from the title, the options page, the PLAYER page, and game over (`LoadFrom=`), load a save made with the gameplay options one way into a run set the other way, upgrade a format 0 file, refuse damaged and newer files without changing the game (`LoadOptional=1`), and read the slot names (`SlotNames=1 SaveFolder=DIR`). The run ends with a list of the moments the saves landed in, and fails if a required one is never reached.

### Real-time speed

The trace cases do not run in real time, so they cannot see the pacing. `tests/run_timing.py` runs the release build with `TimingLog=FILE`: the game opens its window and runs as usual for `TimingTicks` frames (500 by default), writes each frame's period and paint time in ms, and closes without saving config.ini. `TimingPaintMs=N` adds N ms of busy work to each paint, standing in for a slower PC. `window`, `crtfull` (the CRT filter in full screen) and `slowpaint` (30 ms of extra paint) run on the title picture. `room00`, `room07`, `room13` and `room19` skip the title with `ShowTitleScreen=False` and play in that room with `StartRoom=N`. Bruce stands still while the room runs its fighters and effects, and `EnemiesCantHitBruce=True` keeps him there. `crtroom` plays room 0 with the CRT filter in full screen. Each case passes when the mean period is within 0.5% of 59.852 ms and at least 95% of frames are within 3 ms of it. A stall once a second puts about 11% of frames off. The test takes about three minutes and needs the machine otherwise idle. Run `python tests/run_timing.py` from the workspace root, or name cases to run only those.

`python tests/run_all.py` runs the trace cases, the save game checks, and then the timing cases, and exits non-zero if any fails. `--no-timing` leaves out the timing cases.

### Finding a divergence

New input finds new bugs, so the usual hunt runs a fresh stick script from every snapshot and looks at the traces that part. Three more tools help. They write their scratch files to `tmp/`, which git ignores and the tools create when it is missing.

- `tools/sweep_cmp.py SCRIPT FRAMES SNAPSHOT... --record` records the script in VICE from each snapshot and runs the port on it. For each snapshot it prints the first frame where the bodies, the health, the score and lives, or the human opponent's flag and the other player's falls differ, or `None`. `--poke 42CA=1` and the like run every snapshot in another mode. Without `--record` it reuses the VICE traces from an earlier run, which is the quick way to check a fix.
- `tools/vice_debug.sh` runs `tools/vice_debug.py`, a VICE logger that looks inside a frame. Its first comment lists the usage and the flags. `noise` logs every `noise_byte` read. `mark`, `markend`, and `mark7c` log the raster line at points in the frame, on the death path, and on the door path. `hit` logs the `$D01E` reads. `sync` records a trace for a sync case (see above). `storewatch=ADDR:FROM:TO` logs the program counter of every store to an address, which finds the original's code that writes a byte. `menustart`, from a snapshot on the options page, presses the button there once, so the trace is a new game from its first frame; `menukeys=F3,SL` presses options-page keys before that button, in order, by answering the keyboard scan's matrix reads until `title_key` takes each key, so F3, F5, F7, and the handedness keys go through the original's own handling. Poking the snapshot is the other way to set the options. The logger feeds the script's stick at `$16AC`, before the left-handed turn, so a poked `$1383` or `$1384` is tested too. VICE's `x64sc` must be on the PATH, or `X64SC` set to its full path.
- `tools/noise_cmp.py VICE_LOG PORT_LOG SHIFT` lines up the original's `noise_byte` reads with the port's. Record with the `noise` flag, then run the port without `Out=`, which writes `tmp/port_nb.txt`. Reads are paired by the noise counter at `$16`, and the first mismatch names the byte read. The address it prints adds 256 for each wrap of the counter, so take it modulo 256 once the counter has wrapped: `0x147` late in a trace is `$47`. If no death comes before it, it is usually a zero-page or page-1 byte the port never mirrors into its noise memory with `NoisePoke`. A read that is missing on one side means an interrupt landed elsewhere, which is timing. A read with a different value is usually such an unmirrored byte. In a sync replay, `tmp/port_sync.txt` lists the same mismatches directly.

More logger flags find what wrote a byte, and when:

- `storewatch=ADDR:FROM:TO` logs the program counter of each store to the address. `ADDR-END` watches a range and also logs its bytes after each store.
- `watchbyte=ADDR[-END]` logs those bytes at the end of every frame, to compare with the same values printed from the port.
- `execwatch=1165:FROM:TO`, with `sync` or `noise`, adds an `nbstack` line after each noise read with the stack: the return addresses name the routine that called `noise_byte`. A plain `execwatch` on `$1165` sees nothing, because the noise breakpoint takes that stop first.

When a byte differs only in the middle of a frame, check where the read sits in the frame. In the original, `flicker_lamps`, then `tick_wake_counts`, `try_yamo`, and `try_ninja` run before the `$7B` flip and the room hook (`$1BF1`-`$1C0A`). The port runs the hook first, so the hook's bytes reach the noise memory only after the tries (`MirrorRoomHookBytes`), and a read inside a hook on the frame `enter_room` runs it uses the Y `enter_room` left, not the caption index.

Pitfalls:

- `vice_debug.sh` takes the snapshot as a path, for example `referencematerial/emulatorsnapshots/boot02_menu.vsf`. A bare file name makes every attempt time out.
- Every logger run ends by closing all `x64sc` processes, including a VICE window opened by hand, so do not run it while recording.
- Recording again with the same script or name overwrites `tmp/oracle_vice_<stem>.txt`. `vice_debug.sh` retries a run that fails, and the retry overwrites the trace too, so copy a trace before stopping a run by hand.
- `sweep_cmp.py`'s result tuples are (port, VICE).
- PowerShell's `>` writes a file with a BOM, and a parser can then skip its first line.
- A Python heredoc turns `\n` and `\b` inside C++ or Python strings into control characters. Edit such lines another way.

Before capping a case, make sure the divergence is raster timing: an input change on that frame, a ninja wake or a spawn side, a sprite hit one frame early or late with two fighters, or a noise mismatch that follows a death. Anything else is a bug in the port.
