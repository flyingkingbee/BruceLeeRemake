; Bruce Lee, the shared code of the running game.
;
; ../Bruce Lee.d64 holds one program, "BRUCE LEE+2 /REM", packed so that the
; only machine code stored in the clear is the loader in disk-boot.asm.
; This file is that program after it has been unpacked, taken from a
; snapshot with room 0 on screen. Movement, collision, and room entry are
; the same in every room. These are the routines the Windows port follows,
; at the same addresses. The packed file is not a plain copy of this listing.
; Room tables are in rooms.asm. The per-room hooks are in this file.
;
; X selects the actor. X = 0 is Bruce. The same fields exist for the other
; two fighters.
;
;   xpos,X    $9E   horizontal position. One step here is two screen pixels.
;                    move_left and move_right never add a single screen pixel,
;                    so the overlap stays on the grid scan_row describes.
;   ypos,X    $A1   vertical position. One step is one screen pixel. Up decrements it.
;                    A script calls move_up or move_down one to four times, so an
;                    odd ypos is a position the game reaches. The first fall
;                    frame is the one-call case.
;   facing,X  $A4   0 left, 1 right.
;   hit,X     $B6   result of the overlap test. flags_from_nibbles rolls it in.
;                   bit 0: ground. Nibbles 1, 4, 5, 6, 7, 9, and 13, any pixel
;                          pair of color 01. On a ladder cell in the middle
;                          column, nibble 7 does not count. See flags_from_nibbles.
;                   bit 1: prize ink. Nibbles 2, 6, 8, 9, 10, 11, and 14, any
;                          pair of color 10. The lamp hanger is nibble 2.
;                   bit 2: ladder, which also holds him. Nibbles 3, 7, and 11-15
;                          when the cell property is not 0.
;                   bit 3: wall. Those same nibbles when the property is 0.
;                          push_out walks the step back out.
;                   scan_row marks the AND of the sprite and the glyph, not
;                   the glyph nibble itself. A partly covered $F can become
;                   1 or 4, and those are ground. An xpos step is two screen
;                   pixels, and that alignment is what keeps a solid wall on
;                   nibbles 3, 12, and 15.
;   state,X   $BF   which scripted move is running. 0 means none.
;   timer,X   $CE   counts down through that script.
;   active,X  $95   bit 0 set: this actor is in the room.
;   $0106,X          how many frames to hold the picture chosen for the state.
;   $98,X            the move he wants. $0E up, $0D down, $0B left, $07 right, $0F none.
;   $9B              fire. 0 means the button is held. irq_service stores it.
;   $AA,X            state $17's step mark. ride_surface stores 1, and his own
;                    step shifts it to 0. pose_carry keeps the old library while
;                    it is set. catch_surface clears it. The surface shove does not.
;   $AD,X            frames left before that step. A step stores 4. clear_carry
;                    does not touch it, so a dropped catch keeps the wait.
;   $C2,X            the state release_hold saw on the previous frame.
;   $CB,X            how many bursts are still shortened. State 0, or a
;                    state other than $C2, stores 6. Otherwise it counts
;                    down while it is not already 0. The sideways burst
;                    reads the value after that store. 6 is two xpos.
;                    0 is three. enemy_turn stores the chase before
;                    release_hold, so the first chase frame is a new
;                    state and reloads 6.
;   $4F57,X          up steps taken this frame. $4F5A,X is down, $4F5D,X
;                    is left, $4F60,X is right. The slots are three apart,
;                    one actor each. The generation before those is
;                    $4F63, $4F66, $4F69, and $4F6C. move_left and
;                    move_right do not test bit 3. push_out walks this
;                    count back on the next frame. The ninja's strike adds to
;                    the facing-direction slot and does not move xpos, so
;                    that count is walked back as a real step.
;
; States used by Bruce:
;   1 and 2      climb up, climb down
;   5            standing jump
;   6 and 7      sideways jump, left and right
;   $0C and $0D  flying kick, left and right
;   $0E          fall
;   $11          punch
;   $17          carried on the scrolling surface. catch_surface, from tile $62
;                with the ladder bit. ride_surface moves him. Not a climb.
;   $18          pushed back out of a wall. push_out stores it with timer
;                $40 after one generation has been undone. while_stuck
;                drops that timer on the frame bit 3 is clear, so the $40
;                is not a pause once he is out. pose_stuck keeps the
;                picture, and replaces library $44 with library 8.
;   $1A          duck
;
; Actor 1 is Yamo, the green fighter. spawn_yamo calls wake_actor with
; A = $80, so active is $81. His knockout is 450. Actor 2 is the ninja,
; drawn black. spawn_ninja passes A = $40, so active is $41. His knockout
; is 200.
; wake_actor stores $0F in $98,X, and enemy_turn does not read it. With $42CA
; set, the second port is stored in $99 and $9C and actor 1 is left out of
; enemy_turn. actor_tick then reads that stick the same way it reads Bruce's.
;   $0F   flinch. A non-Bruce leaves once the timer in Y is below 2.
;   $10   Yamo's first picture. Library $2A for $0A counts, then state $12.
;   $12   second picture. Library $2C facing left, $2E facing right.
;   $13   knockdown. Libraries $38-$3F. $D1 gone negative is forced here.
;   $14   chase. On ground, Bruce above by $10 or more is a stand. Bit 7
;         of $62 means this fighter is above Bruce, and he walks. A ladder
;         with the ground bit clear walks as well. Climb is never started.
;         Room 4's moving ladder is the same catch Bruce gets, state $17.
;         chase does not aim at it, and the computer stick is never $0E.
;         A property-0 wall is bit 3. The step that enters it is allowed,
;         and the next frame is push_out. Room 4's purple column is
;         property 4, so it is bit 2 and he walks through it. The black
;         column beside that ladder is the wall. See rooms.asm.
;   $15   sidestep. Ground is bit 0 only. Bit 0 clear is a fall.
;   $16   the ninja's strike. Libraries $30-$37. xpos stays put.
;   $1B   stomp. The knockdown libraries, split at timer 4.
; $D1,X is health. wake_actor stores $24. spawn_yamo caps a fresh value at
; $14. spawn_ninja caps it at 7. 0 is still standing. Negative is down.
; check_bruce_down leaves state $13 and state $19 while the timer remains.
;
; Score. $41 $42 $43 are one 24-bit binary total, $41 the high byte. add_score
; puts A into byte X and apply_score adds with carry. There is no SED on that
; add, and the sum wraps at 24 bits. stash_scores turns the total into BCD.
; draw_score prints $439C-$439E only, the low six digits, so 1000000 appears
; as 000000. The top score at $4388 is a real unsigned compare of all three
; bytes and is kept across games. draw_top prints the same six digits.
;
; An extra fall is the INC $28 in check_life_mark. The mark at $4392 is
; compared one byte at a time from the high byte, so a low byte that is still
; short waits even when the total has passed the mark. clear_work_ram copies
; the mark from $438B. room00.vsf holds 00 9C 40 there, which is 40000, and
; the step at $438E is 00 75 30, which is 30000. Each add_score tests once,
; so an award split into two adds is tested between them and the order
; matters. $4395 is the other player's mark.
;
; timed_caption flashes the player word on that same row. $43BD counts down
; once per logic frame. At $10 it prints string $03+1. At 0 it prints string
; 0 and reloads $20. String 1, at $448C, is 31 55 50: "1UP". String 2, at
; $4490, is 32 55 50: "2UP". String 0, at $4488, is three spaces. The row-0
; pointer is $8C00 and the column in Y is $2C, so the cells are $8C2C-$8C2E,
; row 1 columns 4-6, just left of the score. The word is up for the sixteen
; counts $10 down through $01, then blank for the sixteen counts $20 down
; through $11. init_hardware stores $11 and calls it once, so a life starts
; with the word showing. enter_room writes $20 across $8C00-$8C27 only, and
; these three cells are left as they are.
;
; $BC,X collects the blows. Bit 1 is the strike: 2 health and no points.
; Bit 2 is the punch: $64, which is 100, and 3 health. Bit 3 is the kick:
; $4B, which is 75, and 7 health. Bit 4 is the landing: $32, which is 50,
; and 5 health. Bit 7 is set when the attacker is actor 0. The points and
; the knockout are skipped when it is clear. Health below 0 pays the
; knockout on top of the blow. Actor 1, Yamo, is $01 in byte 1 and $C2 in
; byte 2, 450. Any other victim is $C8 in byte 2, 200. That is the ninja.
; A blow from either fighter leaves bit 7 of $BC clear, so it changes
; health and does not score. Yamo has no fall counter. $28 is Bruce's.
;
; A killing landing is an intentional bug in the original. force_knockdown
; jumps back to landing_blow while bit 4 is still set, so 50 and the knockout
; repeat until the health byte wraps into 0-127. The last pass stores state
; $1B with timer 8 over the knockdown, and the fighter stays up. A punch or
; a kick that kills takes the same jump, and the landing test continues only
; when bit 4 is set.
;
; $5E counts down to actor 1, Yamo. $5D counts down to actor 2, the ninja.
; tick_wake_counts subtracts one from each on every logic frame, including while that
; fighter is on screen. A 0 in the room table wakes him on the first
; check. enter_room uses $130B and $1347. A reload uses $135B for Yamo
; and $131F for the ninja, listed in rooms.asm. A long visit reloads 3.
; A middle visit halves the count. A short visit reloads 3 only when $40
; is set. A human opponent ($42CA) stores $30 over Yamo before that test.
;
; Where to start reading
;   boot              fill, charset expand, sprite pictures, then start
;   start             cold start
;   read_stick        joystick and keyboard
;   actor_tick        one actor for this frame
;   on_ground         the fall stops when hit bits 0 or 2 are set
;   hold_done         the pose hold has finished. Shift the step counts.
;   push_out          bit 3 walks the previous generation back out
;   undo_steps        one generation, each count walked back
;   mark_stuck        state $18, timer $40. The mover does not run.
;   while_stuck       state $18 and the timer is still running
;   stuck_reenter     every older count is 0. Respawn, no lost life.
;   start_sidestep    state $15. No walk on the frame it starts.
;   keep_chase        state $14. INC $52, so the $14 timer stays.
;   facing_bruce      punch, flying kick, or the ninja's strike
;   try_strike        state $16. Timer 1 is stand_down, with no ground test.
;   pose_stuck        state $18 keeps the picture. Library $44 becomes 8.
;   move_for_state    the jump, the kick, the sideways jump
;   move_up           one pixel up
;   move_down         one pixel down
;   move_left         one step left
;   move_right        one step right
;   pose_jump         which picture the standing jump shows
;   pose_kick_left    which picture the flying kick shows
;   scan_row          the overlap test for one row of his sprite
;   flags_from_nibbles  nibbles to the hit bits
;   scan_specials     tiles under him, a 3 by 2 window
;   catch_surface     tile $62 and the ladder bit. State $17, timer $10.
;   clear_carry       drop state $17 before those cells are read. $AD stays.
;   ride_surface      state $17. His own step, then the surface shove.
;   shove_with_surface  $60 is 1. Two pixels, up when $65 is clear.
;   pose_carry        state $17. $AA set keeps the picture already showing.
;   flip_climb        libraries $0A and $0C, the two climb pictures.
;   pose_stand        state 0. A ladder keeps $0A or $0C. Otherwise he stands.
;   carry_step        state $17's own step. Two pixels, pure directions only.
;   own_step_taken    that step finished. $AA becomes 0 and $AD is 4.
;   chase_walk        state $14 walks the way he is facing.
;   bruce_above       |dy| >= $10. Above Bruce he walks. Bruce above, he stands.
;   chase_ladder      ground bit clear and ladder bit set. Walk, no climb.
;   start_crumble     tile $60 with bit 1. $FD goes to color RAM, not the screen.
;   step_crumble      the three nozzle slots. Rooms 6, 7, 10-12, 14, 16, and 17.
;   shock             hot tiles, including the nozzle flames $71-$7C
;   paint_sparks      room 18. Four masked bytes in each spark shape.
;   blank_sparks      zero those bytes. A PLAYER page or game over calls it.
;   take_lamp         replace a lamp and add 125 to the low score byte
;   flicker_lamps     rewrite the lamp glyph rows
;   raster_irq        the in-game color bands
;   irq_service       count $48 down and read the stick
;
; More names
;   frame             one frame, then wait for the raster count
;   init_hardware     VIC bank, colors, row pointers
;   enter_room        load room $29. room_11_to_13 may open room 13 instead.
;   enter_room_at     spawn of room X, then finish_exit
;   finish_exit       A is xpos, Y is ypos, $4E is the room
;   exit_allowed      carry clear means the door can be taken. Room 11 always can.
;   exit_tile_2       door slot 0. exit_tile_3, exit_tile_4, exit_tile_5 follow.
;   title_loop        the options page. F3, F5, F7, and the handedness keys
;   step_actors       hold, then choose a picture, for each actor
;   treasure_stick    room 19 replaces Bruce's stick from $88
;   test_visit        $88 against $19 and $20. V and C come back.
;   hook_frame_13     room 13. Three height bonuses at $014B, 500 each.
;   hook_enter_19     treasure room. Blanks the black bar, arms $49/$4A.
;   hook_frame_19     congratulations, the flames, then room 0.
;   choose_pose       state and facing to a library number
;   blit_sprites      copy those pictures into the sprite slots
;   place_sprites     hardware X and Y. A left-facing body can sit 8 xpos left.
;   release_hold      the $0106,X pause between pose changes
;   show_screen       turn the VIC display back on
;   silence_sid       clear the SID and the three effect slots
;   play_sound        Y = $80-$8E. Volume $15, then one of three slots
;   voice_1           effect voice, $D400. voice_2 and voice_3 match it
;   service_tune      options and game-over tune, once per raster
;   score_blip        effect $80, the movement chirp. Not the score
;   hit_sound         effect $86. A connect, a landing, a new spark
;   slide_sound       effect $89, each frame a slide paints
;   play_sound_8a     effect $8A. Doors and the countdown hooks
;   crumble_sound     effect $8D, the nozzle count leaving 8
;   scroll_surface    glyphs $61-$63. Rooms 4, 5, 6, 8, 9, and 11.
;   spawn_yamo        actor 1, state $10, health capped at $14
;   spawn_ninja       actor 2, timer $10, health capped at 7, faces Bruce
;   try_yamo          $5E is 0 and actor 1 is inactive
;   try_ninja         $5D is 0, then the $96 gate
;   tick_wake_counts  $5D and $5E, every logic frame
;   load_wake_counts  X = 1 Yamo, X = 2 the ninja, X = 0 both
;   stand_down        state 0, timer 6. A kick then stores $18 over it.
;   load_library      one library. Actor 2's color byte is $F0.
;   expand_library    one source library into a 24-pixel sprite
;   range_to_bruce    $62 dy, $63 dx. Sign in bit 7, magnitude capped at $30.
;   reach_test        in front of the attacker, inside the reach in $61
;   resolve_blows     $BC for each actor: strike, punch, kick, landing
;   landing_blow      bit 4. 50 points, then subtract 5. The bug jumps here.
;   force_knockdown   $D1 went negative. Kill score, then back to landing_blow.
;   draw_score        low six digits of the binary total at $41
;   draw_top          low six digits of the top score at $4388
;   timed_caption     $43BD. "1UP" or "2UP" for 16 frames, then blank for 16.
;   check_life_mark   $4392, one byte at a time, high byte first
;   extra_fall        room 16, tiles $2D and $2E. INC $28, the DEC is not a gate.
;   retire_actor      clear active bit 0, then load that fighter's count
;
; $40 counts finished games. hook_frame_19 adds one when the treasure
; timer reaches 0, and the next visit is harder: enter_room forces the
; wake counts to 3, and test_visit's callers take their long-visit branch.
; $87/$88 are the visit clock, cleared by enter_room. irq_service adds one
; to $87 on every raster during play, and adds one to $88 when $87 wraps,
; until bit 7 of $88 is set. Room 19's treasure_stick reads $88. Below 2
; Bruce is forced up. From 2 on he is forced to stand.
;
; Room entry. $29 is the room, 0 through 19. $2A,X is the lamps still left
; in room X, copied from $4CCE. $36, $38, and $3A are rooms 12, 14, and 16.
; room_11_to_13 ORs those three and, when all are zero, opens room 13.
; $47 is the sprite mask enter_room saved from $D015 & $1F. $4E, while an
; exit is resolving, is the room finish_exit is about to open.
;
; Front end. The title picture is not drawn by this file. In boot01_title.vsf
; the loader at $C500 still has it: multicolor bitmap at $2000, video matrix
; $0400 filled with $1E, color RAM $0C, border light blue, background black.
; That loader is gone once this image is running. It is written out in title.asm.
;   open_room         options page. F3 is $42C9, F5 is $42CA, F7 or the button starts.
;   between_rooms     the PLAYER page. $03 selects the digit. Then the room.
;   lose_life         one fall. In the demo ($0104 clear) nothing is spent and
;                     the options page opens, its tune starting at once.
;   spend_fall        DEC $28. Zero stays in between_lives. Negative is game_over.
;   game_over         blue GAME OVER screen, then open_room. Room 0 comes from
;                     clear_work_ram, which zeros $29. $4388, the top score, stays.
;   draw_digit        one big score digit on that screen. 2x2 glyphs, charset $8000.
;   $28               falls left. clear_work_ram stores 4, or 9 when $42CA is set.
;                     FALLS 00 is still a life. The next DEC makes $FF and leaves.
;   $42C9             0 is one player, 1 is two players.
;   $42CA             0 is the computer, 1 is a human opponent.
;   $42CB, $42CC      copies of $42C9 and $42CA kept across clear_work_ram.
;   $03               0 or 1, the player named on the PLAYER page.
;   $1383, $1384      port 1 and port 2 handedness. 0 left, 1 right. Only the
;                     options page writes them (L, R, Shift-L, Shift-R), and
;                     clear_work_ram leaves them, so they last until reset.
;   $0104             1 in play, 0 in the attract demo (attract_demo halves it).
;   $49/$4A           the options page timeout, $0960 screens. Every option
;                     key stores it again. At 0, attract_demo.

; Sound. Two players, and only one is installed. During play, irq_service
; calls voice_1, voice_2, and voice_3 once per raster. On the options page
; and during game over, game_over_raster calls service_tune instead.
; The title picture is title.asm and plays nothing. The PLAYER page calls
; silence_sid and does not run the tune. play_sound only queues. frame
; stores 3 in $48, and wait_for_tick spins until the raster has counted
; it down, so the voice starts before the next logic frame.
; The bytes this listing used to skip at $E5EB and $E617 are the tune
; command jump table and its handlers. The branch offset is patched on
; each command, so a straight disassembly only followed the first jump.

; Runs before start and falls into it. The title snapshot enters here from the
; stub at $0400, which has already copied the character ROM. Plain glyphs land
; on $8800 and $8900, and the inverse of each lands $40 codes higher, which is
; why a menu highlight is EOR #$40. Eight bytes are then filled at $8900,
; $8A10, and $8AB0. expand_charset then doubles four packed charsets
; into $A000/$A400, $A800/$AC00, $B000/$B400, and $B800/$BC00. The
; fourth call leaves the stack pointer at $B8. The sprite pictures are
; built, $10F7 returns, and the sprite colors are written.
boot:
        LDX #$07                        ; $0466  eight rows
boot_patch_glyphs:
        LDA #$FF                        ; $0468  solid
        STA $8900,X                     ; $046A  glyph $20
        LDA #$03                        ; $046D  the right pixel pair
        STA $8A10,X                     ; $046F  glyph $42
        LDA #$C0                        ; $0472  the left pixel pair
        STA $8AB0,X                     ; $0474  glyph $56
        DEX                             ; $0477  the next row
        BPL boot_patch_glyphs           ; $0478  more
        LDA #$7F                        ; $047A  128 groups
        STA $F3                         ; $047C  the count
        LDA #$00                        ; $047E  from $9000
        STA $04                         ; $0480  source low
        LDA #$90                        ; $0482  $90
        STA $05                         ; $0484  source high
        LDA #$00                        ; $0486  to $A000 and $A400
        STA $06                         ; $0488  first copy, low
        STA $08                         ; $048A  second copy, low
        LDA #$A0                        ; $048C  $A0
        STA $07                         ; $048E  first copy, high
        LDA #$A4                        ; $0490  $A4
        STA $09                         ; $0492  second copy, high
        JSR expand_charset              ; $0494  charset 1
        LDA #$7F                        ; $0497  128 groups
        STA $F3                         ; $0499  the count
        LDA #$00                        ; $049B  from $9400
        STA $04                         ; $049D  source low
        LDA #$94                        ; $049F  $94
        STA $05                         ; $04A1  source high
        LDA #$00                        ; $04A3  to $A800 and $AC00
        STA $06                         ; $04A5  first copy, low
        STA $08                         ; $04A7  second copy, low
        LDA #$A8                        ; $04A9  $A8
        STA $07                         ; $04AB  first copy, high
        LDA #$AC                        ; $04AD  $AC
        STA $09                         ; $04AF  second copy, high
        JSR expand_charset              ; $04B1  charset 2
        LDA #$7F                        ; $04B4  128 groups
        STA $F3                         ; $04B6  the count
        LDA #$00                        ; $04B8  from $9800
        STA $04                         ; $04BA  source low
        LDA #$98                        ; $04BC  $98
        STA $05                         ; $04BE  source high
        LDA #$00                        ; $04C0  to $B000 and $B400
        STA $06                         ; $04C2  first copy, low
        STA $08                         ; $04C4  second copy, low
        LDA #$B0                        ; $04C6  $B0
        STA $07                         ; $04C8  first copy, high
        LDA #$B4                        ; $04CA  $B4
        STA $09                         ; $04CC  second copy, high
        JSR expand_charset              ; $04CE  charset 3
        LDA #$7F                        ; $04D1  128 groups
        STA $F3                         ; $04D3  the count
        LDA #$00                        ; $04D5  from $9C00
        STA $04                         ; $04D7  source low
        LDA #$9C                        ; $04D9  $9C
        STA $05                         ; $04DB  source high
        LDA #$00                        ; $04DD  to $B800 and $BC00
        STA $06                         ; $04DF  first copy, low
        STA $08                         ; $04E1  second copy, low
        LDA #$B8                        ; $04E3  $B8
        TAX                             ; $04E5  into X
        TXS                             ; $04E6  the stack pointer becomes $B8
        STA $07                         ; $04E7  first copy, high
        LDA #$BC                        ; $04E9  $BC
        STA $09                         ; $04EB  second copy, high
        JSR expand_charset              ; $04ED  charset 4
        JSR build_sprites               ; $04F0  the sprite pictures
        JSR empty_hook                  ; $04F3  returns at once
        LDA #$35                        ; $04F6  RAM, the I/O chips, no BASIC or KERNAL
        STA $01                         ; $04F8  the processor port
        LDA #$F0                        ; $04FA  black
        STA $D028                       ; $04FC  sprite 1 color
        STA $D02A                       ; $04FF  sprite 3 color
        STA $D02B                       ; $0502  sprite 4 color
        LDA #$F7                        ; $0505  yellow, Bruce
        STA $D027                       ; $0507  sprite 0 color
        LDA #$F5                        ; $050A  green, Yamo
        STA $D029                       ; $050C  sprite 2 color

; Cold start. The screen is turned off until the room is ready.
; boot falls into here. The per-room pointers enter_room walks are in
; rooms.asm.
start:
        SEI                             ; $050F  no interrupts
        CLD                             ; $0510  binary arithmetic
        LDX #$FD                        ; $0511  a fresh stack
        TXS                             ; $0513  at $01FD
        LDA $D011                       ; $0514  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0517  screen off
        STA $D011                       ; $0519  VIC control: yscroll, 25 rows, raster bit 8
        JSR reset_music                 ; $051C  silence the tune player
        LDA #$00                        ; $051F  the noise pointer
        STA $16                         ; $0521  low
        LDA #$02                        ; $0523  $0200
        STA $17                         ; $0525  high
        SEI                             ; $0527  still no interrupts
        JSR clear_work_ram              ; $0528  scores, lamps, lives
        JSR init_hardware               ; $052B  the VIC, the CIAs, the vectors
        JMP open_room                   ; $052E  the options page
; The attract demo. title_loop comes here when $49/$4A have counted the
; 2400 screens down. clear_work_ram resets the score, the lamps, and the
; falls (9 while OPPONENT is selected, since $42CA is still set then).
; $0104 is then halved from 1 to 0, which is the demo flag, and $42C9 and
; $42CA are kept in $42CB/$42CC and cleared, so the demo is one player
; against the computer. Room 0 opens, and ($1D) points at $F300.
; step_actors reads one byte from ($1D) each logic frame: the low nibble is
; Bruce's stick and the high nibble is $9B. $F300-$FFF9 are zeros in every
; snapshot, so he holds all four directions and the button. on_ground has
; no case for stick 0, and try_punch wants $0F, so he stands on the spawn
; until the fighters knock him out. That takes 428 frames, and the demo is
; the same every time: noise_byte returns 1, the visit clock stands still,
; and every wake is on the main spawn. lose_life then reopens the options
; page, and its tune starts at once. Joystick 1's button or F1 leaves
; earlier, through demo_exit_check and start.
attract_demo:
        SEI                             ; $0531  no interrupts
        LDA $D011                       ; $0532  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0535  screen off
        STA $D011                       ; $0537  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $053A  no sprites
        STA $D015                       ; $053C  sprite enable
        STA $D000                       ; $053F  sprite 0 x
        STA $D001                       ; $0542  sprite 0 y
; $E30A = 1 would make service_tune silence itself. reset_music
; clears that flag and the SID. The tune does not follow into play.
        LDA #$01                        ; $0545  stop the tune
        STA $E30A                       ; $0547  on its next service
        JSR reset_music                 ; $054A  and silence it now
        LDX #$FD                        ; $054D  a fresh stack
        TXS                             ; $054F  at $01FD
        JSR clear_work_ram              ; $0550  scores, lamps, lives
        JSR init_hardware               ; $0553  the VIC, the CIAs, the vectors
        LSR $0104                       ; $0556  1 becomes 0: the demo
        LDA $42C9                       ; $0559  the second player option
        STA $42CB                       ; $055C  kept
        LDA $42CA                       ; $055F  the opponent option
        STA $42CC                       ; $0562  kept
        LDA #$00                        ; $0565  off for the demo
        STA $42CA                       ; $0567  no opponent
        STA $42C9                       ; $056A  one player
        JSR enter_room                  ; $056D  room 0
        LDA #$00                        ; $0570  the demo script
        STA $1D                         ; $0572  low
        LDA #$F3                        ; $0574  $F300
        STA $1E                         ; $0576  high
        JSR show_screen                 ; $0578  screen on
        NOP                             ; $057B  five spare bytes
        NOP                             ; $057C  spare
        NOP                             ; $057D  spare
        NOP                             ; $057E  spare
        NOP                             ; $057F  spare
        CLI                             ; $0580  interrupts on
        JMP frame                       ; $0581  the frame loop
; Options page. Screen off, then the logo from the four rows at $49BD, the
; three prompt strings, and the highlight on F3, 1 PLAYER, F5, COMPUTER, and
; F7. Sprite 0 is the TM mark: twelve bytes from $0E40, X-expanded, at
; $83C0+$0C. The raster is game_over_raster, which keeps charset $8000 and
; multicolor on through row 9 and switches at raster $82. $49/$4A start at
; $0960, 2400 frames. title_loop returns on F7 or the button; the timeout
; jumps to attract_demo instead, which skips the PLAYER page.
open_room:
        SEI                             ; $0584  no interrupts
        LDA $D011                       ; $0585  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0588  screen off
        STA $D011                       ; $058A  VIC control: yscroll, 25 rows, raster bit 8
        JSR silence_sid                 ; $058D  the effect voices
        LDA #$00                        ; $0590  string number 0
        STA $0100                       ; $0592  the string number
        JSR clear_playfield             ; $0595  clear the screen
        JSR tm_dummy_read               ; $0598  a read whose value is dropped
        LDX #$3F                        ; $059B  64 bytes
        LDA #$00                        ; $059D  zero
open_room_clear_tm:
        STA $83C0,X                     ; $059F  sprite image $0F
        DEX                             ; $05A2  the next
        BPL open_room_clear_tm          ; $05A3  more
        LDA #$01                        ; $05A5  sprite 0 only
        STA $D015                       ; $05A7  sprite enable
        STA $D01D                       ; $05AA  sprite double width
        STA $D010                       ; $05AD  sprite x bit 8
        LDA #$00                        ; $05B0  none
        STA $D017                       ; $05B2  sprite double height
        STA $D01B                       ; $05B5  sprite behind the background
        STA $D01C                       ; $05B8  sprite multicolor
        LDA #$0A                        ; $05BB  x
        STA $D000                       ; $05BD  sprite 0 x
        LDA #$56                        ; $05C0  y
        STA $D001                       ; $05C2  sprite 0 y
        LDA #$FF                        ; $05C5  light grey
        STA $D027                       ; $05C7  sprite 0 color
        LDA #$0F                        ; $05CA  image $0F
        STA $8FF8                       ; $05CC  sprite 0's pointer
        LDX #$0B                        ; $05CF  twelve bytes
; Four rows of the TM sprite, placed on sprite image $0F.
copy_tm:
        LDA $0E40,X                     ; $05D1  the TM mark
        STA $83CC,X                     ; $05D4  from the fourth row of the image
        DEX                             ; $05D7  the next
        BPL copy_tm                     ; $05D8  more
        LDA #$2C                        ; $05DA  game_over_raster, low
        STA $0408                       ; $05DC  the interrupt vector at $0408
        LDA #$15                        ; $05DF  high
        STA $0409                       ; $05E1  the vector
        LDA #$01                        ; $05E4  the raster interrupt
        STA $D01A                       ; $05E6  VIC interrupt enable
        STA $D019                       ; $05E9  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $05EC  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $05EF  raster bit 8 clear
        STA $D011                       ; $05F1  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FD                        ; $05F4  line $FD
        STA $D012                       ; $05F6  raster line
        LDA #$F6                        ; $05F9  blue
        STA $D020                       ; $05FB  border color
        STA $D021                       ; $05FE  background color
        LDA #$FF                        ; $0601  light grey
        STA $D022                       ; $0603  background multicolor 1
        STA $D023                       ; $0606  background multicolor 2
        LDX #$08                        ; $0609  multicolor on, no scroll
        STX $D016                       ; $060B  VIC control: xscroll, multicolor
        JSR fill_color_ram              ; $060E  A is $FF: light grey, multicolor
        LDX #$00                        ; $0611  256 bytes each
open_room_blank_rows:
        LDA #$F1                        ; $0613  white, multicolor off
        STA $D9E0,X                     ; $0615  color RAM, row 12 column 0, plus X
        STA $DAE0,X                     ; $0618  color RAM, row 18 column 16, plus X
        LDA #$DC                        ; $061B  a blank code
        STA $8C00,X                     ; $061D  screen rows 0-6
        STA $8C68,X                     ; $0620  screen rows 2-8
        DEX                             ; $0623  the next
        BNE open_room_blank_rows        ; $0624  until X wraps
        LDX #$27                        ; $0626  40 columns
; Logo rows. Bit 7 selects the upper half of the $8000 charset, $8400-$87FF. $4A0D is
; character row 2, $49BD row 5, $49E5 row 6, $4A35 row 9.
copy_logo:
        LDA $4A0D,X                     ; $0628  the logo, row 2
        ORA #$80                        ; $062B  the upper half of the charset
        STA $8C50,X                     ; $062D  screen row 2
        LDA $49BD,X                     ; $0630  the logo, row 5
        ORA #$80                        ; $0633  the upper half
        STA $8CC8,X                     ; $0635  screen row 5
        LDA $49E5,X                     ; $0638  the logo, row 6
        ORA #$80                        ; $063B  the upper half
        STA $8CF0,X                     ; $063D  screen row 6
        LDA $4A35,X                     ; $0640  the logo, row 9
        ORA #$80                        ; $0643  the upper half
        STA $8D68,X                     ; $0645  screen row 9
        DEX                             ; $0648  the next column
        BPL copy_logo                   ; $0649  more
        LDA #$FF                        ; $064B  $FF
        STA $0100                       ; $064D  string number
        LDA #$4F                        ; $0650  the first prompt
        LDX #$06                        ; $0652  row 6
        LDY #$31                        ; $0654  column $31
        JSR print_string                ; $0656  print it
        LDA #$50                        ; $0659  the second prompt
        LDX #$07                        ; $065B  row 7
        LDY #$2B                        ; $065D  column $2B
        JSR print_string                ; $065F  print it
        LDA #$51                        ; $0662  the third prompt
        LDX #$08                        ; $0664  row 8
        LDY #$31                        ; $0666  column $31
        JSR print_string                ; $0668  print it
        LDX #$09                        ; $066B  ten cells
; Highlight the default choices. ADC #$40 sets bit 6, the inverse glyph.
; X = 0 and 1 also cover the F of F3, F5, and F7. The wider run is 1 PLAYER
; and COMPUTER. 2 PLAYERS, OPPONENT, and the dash stay plain.
highlight_menu:
        LDA $8DF0,X                     ; $066D  row 12, from column 16
        CLC                             ; $0670  carry clear
        ADC #$40                        ; $0671  plus $40: the inverse glyph
        STA $8DF0,X                     ; $0673  back
        LDA $8E40,X                     ; $0676  row 14, from column 16
        CLC                             ; $0679  carry clear
        ADC #$40                        ; $067A  plus $40
        STA $8E40,X                     ; $067C  back
        CPX #$02                        ; $067F  past the first two?
        BCS highlight_next              ; $0681  yes
        LDA $8DEB,X                     ; $0683  row 12, from column 11
        CLC                             ; $0686  carry clear
        ADC #$40                        ; $0687  plus $40
        STA $8DEB,X                     ; $0689  back
        LDA $8E3B,X                     ; $068C  row 14, from column 11
        CLC                             ; $068F  carry clear
        ADC #$40                        ; $0690  plus $40
        STA $8E3B,X                     ; $0692  back
        LDA $8E8B,X                     ; $0695  row 16, from column 11
        CLC                             ; $0698  carry clear
        ADC #$40                        ; $0699  plus $40
        STA $8E8B,X                     ; $069B  back
highlight_next:
        DEX                             ; $069E  the next cell
        BPL highlight_menu              ; $069F  more
        LDA $42CB                       ; $06A1  the second player option, kept
        STA $42C9                       ; $06A4  restored
        LDA $42CC                       ; $06A7  the opponent option, kept
        STA $42CA                       ; $06AA  restored
        LDA $42C9                       ; $06AD  2 PLAYERS?
        BEQ open_room_check_f5          ; $06B0  no
        JSR flip_menu_a                 ; $06B2  move the F3 highlight
open_room_check_f5:
        LDA $42CA                       ; $06B5  OPPONENT?
        BEQ open_room_tune              ; $06B8  no
        JSR flip_menu_b                 ; $06BA  move the F5 highlight
open_room_tune:
; $1385 nonzero skips the tune. The title picture is not this page.
; $09BB counts down. Below zero it is reloaded with 4, $E314 is set
; to 3 (walk the sequence and loop), $E870 is tune 0, $E871 is $FF
; (then restart), and start_tune runs.
        LDA $1385                       ; $06BD  the S key's setting
        BNE open_room_check_bytes       ; $06C0  set: no tune
        DEC $09BB                       ; $06C2  the tune countdown
        BPL open_room_check_bytes       ; $06C5  not below 0: no tune
        LDA #$04                        ; $06C7  4 again
        STA $09BB                       ; $06C9  the countdown
        LDA #$03                        ; $06CC  walk the sequence, and loop
        STA $E314                       ; $06CE  the mode
        LDX #$00                        ; $06D1  tune 0
        STX $E870                       ; $06D3  the sequence's first byte
        DEX                             ; $06D6  $FF
        STX $E871                       ; $06D7  restart
        JSR start_tune                  ; $06DA  load and start it
open_room_check_bytes:
        LDX #$00                        ; $06DD  Y is not set: the walk below uses whatever it holds
        LDA $CF8F,X                     ; $06DF  six check bytes, EORed
        EOR $CFB1,X                     ; $06E2  EOR its pair
        EOR $CF90,X                     ; $06E5  EOR
        EOR $CFAF,X                     ; $06E8  EOR
        EOR $CF91,X                     ; $06EB  EOR
        EOR $CFB0,X                     ; $06EE  EOR: 0 when the pairs agree
        BEQ open_room_show              ; $06F1  all agree: the page
; The check of the bytes around $CF8F failed. Stay here and walk ($1D) forward.
checksum_hang:
        STA ($1D),Y                     ; $06F3  overwrite a byte
        INC $1E                         ; $06F5  the next page
        JMP checksum_hang               ; $06F7  forever
open_room_show:
        LDA #$09                        ; $06FA  $0960 screens
        STA $4A                         ; $06FC  high
        LDA #$60                        ; $06FE  low
        STA $49                         ; $0700  the timeout
        JSR show_screen                 ; $0702  screen on
        NOP                             ; $0705  five spare bytes
        NOP                             ; $0706  spare
        NOP                             ; $0707  spare
        NOP                             ; $0708  spare
        NOP                             ; $0709  spare
        CLI                             ; $070A  interrupts on
        JSR title_loop                  ; $070B  wait for F7, the button, or the timeout
        SEI                             ; $070E  no interrupts
        LDA $D011                       ; $070F  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0712  screen off
        STA $D011                       ; $0714  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $0717  none
        STA $D015                       ; $0719  sprite enable
        STA $D000                       ; $071C  sprite 0 x
        STA $D001                       ; $071F  sprite 0 y
        STA $03                         ; $0722  the PLAYER page's player, 0
; Same stop as attract_demo. Leaving the options page silences the tune.
        LDA #$01                        ; $0724  stop the tune
        STA $E30A                       ; $0726  on its next service
        JSR reset_music                 ; $0729  and silence it now
        LDA $42C9                       ; $072C  the second player option
        STA $42CB                       ; $072F  kept
        LDA $42CA                       ; $0732  the opponent option
        STA $42CC                       ; $0735  kept
        JSR between_rooms               ; $0738  the PLAYER page
        LDA $D011                       ; $073B  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $073E  screen off
        STA $D011                       ; $0740  VIC control: yscroll, 25 rows, raster bit 8
        LDX #$FD                        ; $0743  a fresh stack
        TXS                             ; $0745  at $01FD
; A new game. clear_work_ram zeroes $03-$F5, so the noise pointer $16/$17
; starts over at $0000, and the six interrupts before the first frame leave
; $16 and $7F at 6 and the visit clock $87 at 4. Every new game therefore
; reads the same noise for the same input. $4E97/$4E98 and the rest of page
; 1 above $0107 keep what the options page left.
        JSR clear_work_ram              ; $0746  scores, lamps, lives
        JSR init_hardware               ; $0749  the VIC, the CIAs, the vectors
        JSR enter_room                  ; $074C  room 0
; ($1D) points at $F300 in play too, not only in the attract demo.
        LDA #$00                        ; $074F  the script pointer
        STA $1D                         ; $0751  low
        LDA #$F3                        ; $0753  $F300
        STA $1E                         ; $0755  high
        JSR show_screen                 ; $0757  screen on
        NOP                             ; $075A  five spare bytes
        NOP                             ; $075B  spare
        NOP                             ; $075C  spare
        NOP                             ; $075D  spare
        NOP                             ; $075E  spare
        CLI                             ; $075F  interrupts on
        JMP frame                       ; $0760  the frame loop
; VIC bank $8000, multicolor on, sprites expanded in X. Then the row pointers, the score
; row, and the room tables.
init_hardware:
        LDA #$00                        ; $0763  0
        STA $8B                         ; $0765  no saved position for Yamo
        STA $8C                         ; $0767  nor for the ninja
        JSR arm_raster                  ; $0769  the raster interrupt
        JSR init_cia                    ; $076C  the CIA ports
        LDA #$FF                        ; $076F  $FF
        STA $4B                         ; $0771  as the pause lockout sets it
        LDY #$8B                        ; $0773  high
        LDA #$D8                        ; $0775  $8BD8, one row above the screen
        JSR build_row_pointers          ; $0777  the row pointers
        LDA #$00                        ; $077A  first pointer, low
        STA $4338                       ; $077C  $8C00
        STA $4360                       ; $077F  second-row pointer, low
        STA $4361                       ; $0782  and the next one
        LDA #$8C                        ; $0785  high
        STA $434C                       ; $0787  $8C00
        LDA #$CE                        ; $078A  $CE
        STA $4374                       ; $078C  second-row pointer, high
        STA $4375                       ; $078F  and the next one
        JSR clear_playfield             ; $0792  13 rows
        LDA #$F8                        ; $0795  multicolor, ink 8
        JSR fill_color_ram              ; $0797  all of color RAM
; Three VIC rows sit above the picture and are not part of the packed room.
; Row 0 ($8C00) is screen code $20. In the score charset at $8800 that glyph
; is eight $FF bytes, and its color ($D800) is 0, so the hires cell is solid
; black. Row 1 ($8C28) is left as the 0 clear_playfield wrote. Color 0 with an
; empty glyph shows $D021, which raster_irq holds at $FC (grey) until raster
; $40, inside this row. The score digits are stored on this row: a column in
; Y of $3C or more is past the 40 cells of $8C00. Row 2 ($8C50) is screen code
; $06. The room charset, in use once raster_open has run, has eight $FF bytes
; there. Its color is the $F8 fill left at $D850, nibble $8, so the cell is
; multicolor ink black. enter_room repaints $8C00 with $20 and starts its
; color fill at $D878, the first picture row, so these three rows survive
; every room change. hook_enter_19 then stores 0 in row 0. Glyph 0 is
; empty, so the treasure room shows the grey of $D021 on that bar too.
        LDX #$27                        ; $079A  40 columns
init_top_rows:
        LDA #$00                        ; $079C  black, hires
        STA $D800,X                     ; $079E  color RAM, row 0 column 0, plus X
        STA $D828,X                     ; $07A1  color RAM, row 1 column 0, plus X
        LDA #$20                        ; $07A4  the solid glyph
        STA $8C00,X                     ; $07A6  screen row 0
        LDA #$06                        ; $07A9  the room's solid glyph
        STA $8C50,X                     ; $07AB  screen row 2
        CPX #$08                        ; $07AE  past the first eight?
        BCS init_top_next               ; $07B0  yes
        LDA #$0F                        ; $07B2  image $0F
        STA $8FF8,X                     ; $07B4  the eight sprite pointers
        LDA #$FF                        ; $07B7  solid
        STA $8900,X                     ; $07B9  glyph $20 of the score font
init_top_next:
        DEX                             ; $07BC  the next column
        BPL init_top_rows               ; $07BD  more
        LDA #$00                        ; $07BF  zero
        TAX                             ; $07C1  256 bytes each
init_clear_sprites:
        STA $8180,X                     ; $07C2  sprite images $06-$09
        STA $8280,X                     ; $07C5  sprite images $0A-$0D
        STA $8300,X                     ; $07C8  sprite images $0C-$0F
        INX                             ; $07CB  the next
        BNE init_clear_sprites          ; $07CC  until X wraps
        LDX #$03                        ; $07CE  four colors
init_border_colors:
        LDA $479B,X                     ; $07D0  the border, background, and multicolors
        STA $D020,X                     ; $07D3  border color, plus X
        DEX                             ; $07D6  the next
        BPL init_border_colors          ; $07D7  more
        LDA #$01                        ; $07D9  bank 2, $8000
        STA $DD00                       ; $07DB  CIA 2 port A: VIC bank
        LDA #$38                        ; $07DE  screen $8C00, charset $A000
        STA $D018                       ; $07E0  screen and charset address
        STA $F2                         ; $07E3  kept
        LDA #$18                        ; $07E5  multicolor on, no scroll
        STA $D016                       ; $07E7  VIC control: xscroll, multicolor
        LDA #$00                        ; $07EA  none
        STA $D015                       ; $07EC  sprite enable
        STA $D017                       ; $07EF  sprite double height
        STA $D01B                       ; $07F2  sprite behind the background
        STA $D01C                       ; $07F5  sprite multicolor
        LDA #$FF                        ; $07F8  every sprite
        STA $D01D                       ; $07FA  sprite double width
        LDA #$80                        ; $07FD  the first draw
        JSR draw_score                  ; $07FF  the score row
        JSR draw_top                    ; $0802  the top score
; $43BD starts at $11. timed_caption decrements it to $10 and prints the
; player word, so the score row comes up with "1UP" or "2UP" already there.
        LDA #$11                        ; $0805  one above $10
        STA $43BD                       ; $0807  the caption count
        JSR timed_caption               ; $080A  the player word
        JSR print_top_word              ; $080D  TOP
        JSR print_falls_word            ; $0810  FALLS
        JSR lives_to_bcd                ; $0813  the falls count
; Countdown and copy count for scroll_surface. The first call copies, and
; that copy does not move the delay slot. $64 is 0 in the opening snapshot,
; which is the picture expand_charset wrote.
        LDA #$01                        ; $0816  1
        STA $60                         ; $0818  the surface's delay
        STA $66                         ; $081A  the copy count
        LDX #$04                        ; $081C  five slots
        LDA #$FF                        ; $081E  no owner
init_clear_voice_owners:
        STA $4F40,X                     ; $0820  the voice slots for actors
        DEX                             ; $0823  the next
        BPL init_clear_voice_owners     ; $0824  more
        LDX #$00                        ; $0826  Bruce
        LDA #$00                        ; $0828  no flags
        JMP wake_actor                  ; $082A  wake him, and return from there
; Turn off CIA interrupts, enable the raster interrupt, and open the SID noise channel that
; the effects use. The vector is raster_irq and the compare starts at raster $FB.
arm_raster:
        LDA #$7F                        ; $082D  every CIA source off
        STA $DD0D                       ; $082F  CIA 2 interrupt control
        STA $DC0D                       ; $0832  CIA 1 interrupt control
        LDA $DD0D                       ; $0835  read to clear anything pending
        LDA $DC0D                       ; $0838  CIA 1 interrupt control
        CLD                             ; $083B  binary arithmetic
        LDA #$C1                        ; $083C  raster_irq, low
        STA $0408                       ; $083E  the vector at $0408
        LDA #$48                        ; $0841  high
        STA $0409                       ; $0843  the vector
        LDA #$01                        ; $0846  the raster interrupt
        STA $D01A                       ; $0848  VIC interrupt enable
        STA $D019                       ; $084B  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $084E  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $0851  raster bit 8 clear
        STA $D011                       ; $0853  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FB                        ; $0856  line $FB
        STA $D012                       ; $0858  raster line
        LDA #$FF                        ; $085B  the highest frequency
        STA $D40E                       ; $085D  SID voice 3 frequency low
        STA $D40F                       ; $0860  SID voice 3 frequency high
        LDA #$80                        ; $0863  noise, gate off
        STA $D412                       ; $0865  SID voice 3 waveform and gate
        RTS                             ; $0868  voice 3's output is the noise byte's source
; A is the low byte and Y the high byte of the first row. Builds 13 pointers, each $50
; bytes (two character rows) after the last.
build_row_pointers:
        LDX #$00                        ; $0869  the first entry
        STA $4338                       ; $086B  first row, low
        STY $434C                       ; $086E  first row, high
build_even_rows:
        LDA $4338,X                     ; $0871  this row
        CLC                             ; $0874  carry clear
        ADC #$50                        ; $0875  two rows on
        STA $4339,X                     ; $0877  the next even row, low
        LDA $434C,X                     ; $087A  high
        ADC #$00                        ; $087D  the carry
        STA $434D,X                     ; $087F  the next even row, high
        INX                             ; $0882  the next
        CPX #$0D                        ; $0883  13 rows?
        BCC build_even_rows             ; $0885  no
        LDA $4338                       ; $0887  the first row
        CLC                             ; $088A  carry clear
        ADC #$28                        ; $088B  one row on
        STA $4360                       ; $088D  the first odd row, low
        LDA $434C                       ; $0890  high
        ADC #$00                        ; $0893  the carry
        STA $4374                       ; $0895  the first odd row, high
        LDX #$00                        ; $0898  the first entry
build_odd_rows:
        LDA $4360,X                     ; $089A  this row
        CLC                             ; $089D  carry clear
        ADC #$50                        ; $089E  two rows on
        STA $4361,X                     ; $08A0  the next odd row, low
        LDA $4374,X                     ; $08A3  high
        ADC #$00                        ; $08A6  the carry
        STA $4375,X                     ; $08A8  the next odd row, high
        INX                             ; $08AB  the next
        CPX #$0D                        ; $08AC  13 rows?
        BCC build_odd_rows              ; $08AE  no
        RTS                             ; $08B0  back
; Wait on the options page. $49/$4A count down once a frame in game_over_raster.
; At 0 this jumps to attract_demo and never reaches the PLAYER page. A fresh
; key in $0109 is dispatched. The button is bit 4 of $DC01, active low.
; Key codes, after AND #$7F: F7 is 3, F3 is 5, F5 is 6. Bit 7 of $0109 is Shift.
title_loop:
        LDA $49                         ; $08B1  the timeout
        ORA $4A                         ; $08B3  either byte
        BNE title_read_key              ; $08B5  still counting
        JMP attract_demo                ; $08B7  the demo
title_read_key:
        LDA #$00                        ; $08BA  the full keyboard
        STA $010E                       ; $08BC  not the play keys
        JSR read_stick                  ; $08BF  the key reader
        LDA $010C                       ; $08C2  a key waiting?
        BEQ title_check_wipe            ; $08C5  no
        LDA #$00                        ; $08C7  zero
        STA $010C                       ; $08C9  taken
        LDA $0109                       ; $08CC  the key
        JMP title_key                   ; $08CF  L, R, or the menu keys
; F7, F5, F3. Anything else falls through to the button test.
menu_key:
        AND #$7F                        ; $08D2  without Shift
        CMP #$03                        ; $08D4  F7?
        BEQ menu_start                  ; $08D6  yes: start
        CMP #$06                        ; $08D8  F5?
        BEQ menu_f5                     ; $08DA  yes
        CMP #$05                        ; $08DC  F3?
        BEQ menu_f3                     ; $08DE  yes
title_check_wipe:
        LDA $4A                         ; $08E0  the timeout, high
        CMP #$08                        ; $08E2  $08?
        BNE title_check_button          ; $08E4  no
        LDA $49                         ; $08E6  the timeout, low
        CMP #$02                        ; $08E8  2 or more?
        BCS title_check_button          ; $08EA  yes
; String $0E is spaces. It wipes the handedness line once the count is at
; $0800 or $0801, which is 351 screens, about seven seconds, after the last
; option key. Only row 10 from column 2 is wiped, the same 36 cells.
        LDA #$0E                        ; $08EC  spaces
        LDX #$0A                        ; $08EE  row 10
        LDY #$02                        ; $08F0  column 2
        JSR print_string                ; $08F2  wipe the handedness line
title_check_button:
        LDA $DC01                       ; $08F5  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $08F8  the button, active low
        BNE title_loop                  ; $08FA  up: wait on
; F7 or the joystick button. $48 is 16 frames of debounce, counted by the raster.
menu_start:
        JSR wait_button_up              ; $08FC  let it go
        LDA #$10                        ; $08FF  16 frames
        STA $48                         ; $0901  the raster count
menu_start_wait:
        LDA $48                         ; $0903  counted down?
        BNE menu_start_wait             ; $0905  no
        RTS                             ; $0907  to the PLAYER page
; F5. $42CA is 0 for the computer and 1 for a human opponent. $42CC keeps a copy.
menu_f5:
        LDA $42CA                       ; $0908  the opponent
        EOR #$01                        ; $090B  the other choice
        STA $42CA                       ; $090D  stored
        STA $42CC                       ; $0910  and its copy
        JSR flip_menu_b                 ; $0913  move the highlight
; Let the key up, put the 2400-frame timeout back, and pause four frames.
menu_settle:
        JSR wait_button_up              ; $0916  let it go
        LDA #$09                        ; $0919  $0960 screens
        STA $4A                         ; $091B  high
        LDA #$60                        ; $091D  low
        STA $49                         ; $091F  the timeout
        LDA #$04                        ; $0921  four frames
        STA $48                         ; $0923  the raster count
menu_settle_wait:
        LDA $48                         ; $0925  counted down?
        BNE menu_settle_wait            ; $0927  no
        JMP title_loop                  ; $0929  wait again
; F3. $42C9 is 0 for one player and 1 for two. $42CB keeps a copy.
menu_f3:
        LDA $42C9                       ; $092C  the players
        EOR #$01                        ; $092F  the other choice
        STA $42C9                       ; $0931  stored
        STA $42CB                       ; $0934  and its copy
        JSR flip_menu_a                 ; $0937  move the highlight
        JSR wait_button_up              ; $093A  let it go
        LDA #$09                        ; $093D  $0960 screens
        STA $4A                         ; $093F  high
        LDA #$60                        ; $0941  low
        STA $49                         ; $0943  the timeout
        LDA #$04                        ; $0945  four frames
        STA $48                         ; $0947  the raster count
        BNE menu_settle_wait            ; $0949  always
; Stay here while either joystick button is still down.
wait_button_up:
        LDA $DC00                       ; $094B  CIA 1 port A: joystick 2, keyboard columns
        AND $DC01                       ; $094E  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $0951  both buttons, active low
        BEQ wait_button_up              ; $0953  one is down: wait
        RTS                             ; $0955  back
; Handedness. L is $2A and R is $11. Shift sets bit 7, so Shift-L is $AA and
; Shift-R is $91. $1383 is port 1 and $1384 is port 2. 0 is left-handed, which
; rotates the stick through the table at $4A85. 1 is right-handed, the stick as read.
; The four strings are $08, $0A, $09, and $0D.
title_key:
        CMP #$2A                        ; $0956  L?
        BEQ joy1_left                   ; $0958  yes
        CMP #$AA                        ; $095A  Shift-L?
        BEQ joy2_left                   ; $095C  yes
        CMP #$11                        ; $095E  R?
        BEQ joy1_right                  ; $0960  yes
        CMP #$91                        ; $0962  Shift-R?
        BEQ joy2_right                  ; $0964  yes
        JMP menu_key                    ; $0966  the F keys and the button
; L. Joystick 1, left-handed.
joy1_left:
        LDA #$08                        ; $0969  the string
        LDX #$0A                        ; $096B  row 10
        LDY #$02                        ; $096D  column 2
        JSR print_string                ; $096F  print it
        LDA #$00                        ; $0972  left-handed
        STA $1383                       ; $0974  joystick 1
        BEQ hand_done                   ; $0977  always
; Shift-L. Joystick 2, left-handed.
joy2_left:
        LDA #$0A                        ; $0979  the string
        TAX                             ; $097B  row 10 as well
        LDY #$02                        ; $097C  column 2
        JSR print_string                ; $097E  print it
        LDA #$00                        ; $0981  left-handed
        STA $1384                       ; $0983  joystick 2
        BEQ hand_done                   ; $0986  always
; R. Joystick 1, right-handed.
joy1_right:
        LDA #$09                        ; $0988  the string
        LDX #$0A                        ; $098A  row 10
        LDY #$02                        ; $098C  column 2
        JSR print_string                ; $098E  print it
        LDA #$01                        ; $0991  right-handed
        STA $1383                       ; $0993  joystick 1
        BNE hand_done                   ; $0996  always
; Shift-R. Joystick 2, right-handed.
joy2_right:
        LDA #$0D                        ; $0998  the string
        LDX #$0A                        ; $099A  row 10
        LDY #$02                        ; $099C  column 2
        JSR print_string                ; $099E  print it
        LDA #$01                        ; $09A1  right-handed
        STA $1384                       ; $09A3  joystick 2
hand_done:
        JMP menu_settle                 ; $09A6  settle and wait again
; Write A through all four pages of color RAM, $D800 to $DBFF.
fill_color_ram:
        LDX #$00                        ; $09A9  256 bytes a page
fill_color_loop:
        STA $D800,X                     ; $09AB  color RAM, row 0 column 0, plus X
        STA $D900,X                     ; $09AE  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $09B1  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $09B4  color RAM, row 19 column 8, plus X
        INX                             ; $09B7  the next
        BNE fill_color_loop             ; $09B8  until X wraps
        RTS                             ; $09BA  back
        .byte $04                       ; $09BB  the options tune countdown, 4

; Blank the screen and load room $29. $42CA set means a human opponent.
; Yamo's wake count $5E is forced to 8 here, ahead of the room table.
; try_yamo and load_yamo_count store $30 when he appears and when he is
; knocked out. $42CA clear, after the idle handover, uses the table again.
enter_room:
        LDA $D011                       ; $09BC  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $09BF  screen off
        STA $D011                       ; $09C1  VIC control: yscroll, 25 rows, raster bit 8
        LDA $D015                       ; $09C4  sprite enable
        AND #$1F                        ; $09C7  the five actor sprites
; $47 is the actors' sprites. $0B3B writes it back after the unpack.
; Sprites are blank until then. room_11_to_13 restores $47 before it
; calls enter_room_at, so the second entry saves this mask and not 0.
        STA $47                         ; $09C9  kept
        LDA #$00                        ; $09CB  none shown
        STA $D015                       ; $09CD  sprite enable
        LDX #$27                        ; $09D0  40 columns
        LDA #$20                        ; $09D2  the solid glyph
enter_room_black_bar:
        STA $8C00,X                     ; $09D4  screen row 0
        DEX                             ; $09D7  the next
        BPL enter_room_black_bar        ; $09D8  more
        LDX $29                         ; $09DA  the room
        LDA $47A0,X                     ; $09DC  its color
        LDX #$00                        ; $09DF  256 bytes a page
; $D878 is character row 3. Rows 0 and 1 keep the black written at $079C.
; Row 2 keeps the $F8 from fill_color_ram, which is multicolor black.
; hook_enter_19 runs later and stores 0 over the $20 just written on row 0.
enter_room_fill_color:
        STA $D878,X                     ; $09E1  color RAM, row 3 column 0, plus X
        STA $D900,X                     ; $09E4  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $09E7  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $09EA  color RAM, row 19 column 8, plus X
        INX                             ; $09ED  the next
        BNE enter_room_fill_color       ; $09EE  until X wraps
        JSR blank_sparks                ; $09F0  room 18's sparks off
        JSR silence_sid                 ; $09F3  the effect voices
; Room 11's tile 2 returns to room 10. Tiles 3, 4, and 5 are the three
; side doors, to rooms 12, 14, and 16. Each of those has a slot back to
; room 11, and room 10's way forward stores 11 as well, so every entry
; reaches here: a door, a respawn through enter_room_at, or the inlined
; copy of that sequence at $24DB.
;
; $36, $38, and $3A are $2A+room for rooms 12, 14, and 16. Any lamp still
; left in those three loads room 11. None left, and room 13 opens at its
; spawn. The packed picture and the enter hook of room 11 do not run.
room_11_to_13:
        LDA $29                         ; $09F6  the room
        CMP #$0B                        ; $09F8  room 11?
        BNE enter_room_body             ; $09FA  no
        LDA $36                         ; $09FC  room 12's lamps left
        ORA $38                         ; $09FE  room 14's
        ORA $3A                         ; $0A00  room 16's
        BNE enter_room_body             ; $0A02  any left: room 11
        LDA $47                         ; $0A04  the sprites saved above
        STA $D015                       ; $0A06  sprite enable
        LDX #$0D                        ; $0A09  room 13
        JMP enter_room_at               ; $0A0B  enter it at its spawn
; Every room except the room 13 shortcut. X becomes room*2 + player, the
; index of this player's entry flag at $0300.
enter_room_body:
        LDA $29                         ; $0A0E  the room
        ASL A                           ; $0A10  times 2
        ADC $03                         ; $0A11  plus the player. Carry is clear
        TAX                             ; $0A13  the flag's index
; $0300 + room*2 + player. A nonzero flag pays 2000, $07 into score byte 1
; and $D0 into byte 2, and the LSR spends it. The two adds are separate, so
; check_life_mark runs between them. rearm_room_bonus puts the flags back
; when the treasure room ends. Room 0's flag stays clear. room_11_to_13 has
; already switched a cleared room 11 over to room 13, so this pays room 13
; and leaves room 11's flag unspent.
        LDA $0300,X                     ; $0A14  the entry flag
        BEQ enter_room_clear_steps      ; $0A17  clear: no bonus
        LSR $0300,X                     ; $0A19  spent
        LDA #$07                        ; $0A1C  $07
        LDX #$01                        ; $0A1E  into score byte 1
        JSR add_score                   ; $0A20  1792
        LDA #$D0                        ; $0A23  $D0
        LDX #$02                        ; $0A25  into score byte 2
        JSR add_score                   ; $0A27  208 more: 2000
enter_room_clear_steps:
        LDA #$00                        ; $0A2A  zero
        LDY #$83                        ; $0A2C  132 bytes
enter_room_clear_loop:
        STA $4F57,Y                     ; $0A2E  the step history
        DEY                             ; $0A31  the next
        BPL enter_room_clear_loop       ; $0A32  more
; Visit clock. Both bytes start at 0, so treasure_stick begins on up and
; test_visit reports a fresh room. See count_visit.
        STA $87                         ; $0A34  the visit clock, low
        STA $88                         ; $0A36  high
; scroll_surface direction and delay slot. 0 moves the picture up. Slot 7
; is the last byte of $4CB2, an $08. $60, $64, and $66 keep running.
        STA $65                         ; $0A38  the picture moves up
        LDA #$07                        ; $0A3A  the last slot
        STA $4321                       ; $0A3C  the surface's delay slot
        LDX $29                         ; $0A3F  the room
        LDA $4C9E,X                     ; $0A41  a room without fighters?
        STA $7A                         ; $0A44  kept for frame
        BEQ enter_room_wake_counts      ; $0A46  no: fighters
        LDA #$00                        ; $0A48  no saved place
        STA $8B                         ; $0A4A  for Yamo
        STA $8C                         ; $0A4C  nor the ninja
enter_room_wake_counts:
        LDA $130B,X                     ; $0A4E  the room's ninja count
        STA $5D                         ; $0A51  the ninja's wake count
        LDA $1347,X                     ; $0A53  the room's Yamo count
        STA $5E                         ; $0A56  Yamo's wake count
        LDA $40                         ; $0A58  a set $40?
        BEQ enter_room_check_opponent   ; $0A5A  no
        LDA #$03                        ; $0A5C  3
        STA $5D                         ; $0A5E  for the ninja
        STA $5E                         ; $0A60  and Yamo
enter_room_check_opponent:
; Human opponent. Actor 1's wake count $5E is 8 instead of the room's value.
        LDA $42CA                       ; $0A62  a second player?
        BEQ enter_room_reset_bruce      ; $0A65  no
        LDA #$08                        ; $0A67  8
        STA $5E                         ; $0A69  Yamo's wake count
enter_room_reset_bruce:
        LDA #$01                        ; $0A6B  on the ground
        STA hit                         ; $0A6D  Bruce's hit
        LDA #$04                        ; $0A6F  4 counts
        STA timer                       ; $0A71  Bruce's timer
        LDA #$00                        ; $0A73  zero
        STA $4FDE                       ; $0A75  crumble slot 0
        STA $4FDF                       ; $0A78  slot 1
        STA $4FE0                       ; $0A7B  slot 2
        STA state                       ; $0A7E  Bruce's state
        STA $0106                       ; $0A80  no hold
        LDA $29                         ; $0A83  the room
        ASL A                           ; $0A85  times 2
        TAX                             ; $0A86  the index
        LDA $4AA8,X                     ; $0A87  its color list, low
        STA $06                         ; $0A8A  pointer
        LDA $4AA9,X                     ; $0A8C  high
        STA $07                         ; $0A8F  pointer
        LDY #$13                        ; $0A91  20 bytes
enter_room_copy_colors:
        LDA ($06),Y                     ; $0A93  a band color
        STA $0153,Y                     ; $0A95  into the live list
        DEY                             ; $0A98  the next
        BPL enter_room_copy_colors      ; $0A99  more
        ; $D018 follows the room. Below $0A the value is $38, charset $A000.
        ; Room $12 is $3C, charset $B000. Every other room is $3A, charset
        ; $A800. $B800 is expanded at startup and never selected here.
        ; boot expands each bank once. scroll_surface writes into the bank
        ; selected here, and this routine does not expand it again.
        LDA #$38                        ; $0A9B  charset $A000
        LDX $29                         ; $0A9D  the room
        CPX #$0A                        ; $0A9F  below 10?
        BCC enter_room_store_charset    ; $0AA1  yes
        CPX #$12                        ; $0AA3  room 18?
        BEQ enter_room_charset_18       ; $0AA5  yes
        LDA #$3A                        ; $0AA7  charset $A800
        BNE enter_room_store_charset    ; $0AA9  always
enter_room_charset_18:
        LDA #$3C                        ; $0AAB  charset $B000
enter_room_store_charset:
        STA $F2                         ; $0AAD  for raster_open
        LDA $4B34,X                     ; $0AAF  the packed picture, low
        STA $06                         ; $0AB2  source
        LDA $4B49,X                     ; $0AB4  high
        STA $07                         ; $0AB7  source
        LDA #$78                        ; $0AB9  $78
        STA $04                         ; $0ABB  upper screen cell, low
        STA $10                         ; $0ABD  upper color cell, low
        LDA #$A0                        ; $0ABF  $A0
        STA $08                         ; $0AC1  lower screen cell, low
        STA $12                         ; $0AC3  lower color cell, low
        LDA #$8C                        ; $0AC5  $8C: rows 3 and 4 of the screen
        STA $05                         ; $0AC7  upper screen cell, high
        STA $09                         ; $0AC9  lower screen cell, high
        LDA #$D8                        ; $0ACB  $D8: rows 3 and 4 of color RAM
        STA $11                         ; $0ACD  upper color cell, high
        STA $13                         ; $0ACF  lower color cell, high
        LDA #$27                        ; $0AD1  39
        STA $F3                         ; $0AD3  the column count
        LDY #$00                        ; $0AD5  Y stays 0
; One command byte, then its payload. A byte below $80 is a run: the next
; source byte is written that many times, and a count of 0 writes 256 because
; the loop is DEX/BNE. A byte at or above $80 is a literal: the low seven bits
; are the count, $80 ends the stream, and each following source byte is one
; tile. A payload byte with bit 7 set stores color $F8 on both color rows and
; the tile is the low seven bits. Otherwise the color stays the room fill
; from $47A0,X, which was written across $D878 before this loop. Rooms 4, 7,
; 10, 13, 17, and 18 emit 442 cells. The screen holds 1000, so the last two
; land past it and are not part of the picture.
unpack_command:
        LDA ($06),Y                     ; $0AD7  a command
        BPL unpack_run                  ; $0AD9  below $80: a run
        AND #$7F                        ; $0ADB  the count
        BEQ unpack_done                 ; $0ADD  0: the end
        TAX                             ; $0ADF  X counts
        JSR step_ptr_06                 ; $0AE0  past the command
unpack_literal:
        LDA ($06),Y                     ; $0AE3  a tile
        BPL unpack_literal_store        ; $0AE5  bit 7 clear: the room fill
        JSR bright_cell                 ; $0AE7  color $F8, and the tile without bit 7
unpack_literal_store:
        STA ($04),Y                     ; $0AEA  the upper cell
        ORA #$80                        ; $0AEC  the lower glyph
        STA ($08),Y                     ; $0AEE  the lower cell
        JSR step_ptr_04                 ; $0AF0  the next upper cell
        JSR step_ptr_06                 ; $0AF3  the next source byte
        JSR step_ptr_08                 ; $0AF6  the next lower cell
        JSR step_ptr_10                 ; $0AF9  the next upper color
        JSR step_ptr_12                 ; $0AFC  the next lower color
        JSR unpack_next_row             ; $0AFF  a row skip at the end of a row
        DEX                             ; $0B02  one fewer
        BNE unpack_literal              ; $0B03  more
        BEQ unpack_command              ; $0B05  always: the next command
unpack_run:
        TAX                             ; $0B07  the count
        JSR step_ptr_06                 ; $0B08  past the command
unpack_run_cell:
        LDA ($06),Y                     ; $0B0B  the tile
        BPL unpack_run_store            ; $0B0D  bit 7 clear: the room fill
        JSR bright_cell                 ; $0B0F  color $F8, and the tile without bit 7
unpack_run_store:
        STA ($04),Y                     ; $0B12  the upper cell
        ORA #$80                        ; $0B14  the lower glyph
        STA ($08),Y                     ; $0B16  the lower cell
        JSR step_ptr_04                 ; $0B18  the next upper cell
        JSR step_ptr_08                 ; $0B1B  the next lower cell
        JSR step_ptr_10                 ; $0B1E  the next upper color
        JSR step_ptr_12                 ; $0B21  the next lower color
        JSR unpack_next_row             ; $0B24  a row skip at the end of a row
        DEX                             ; $0B27  one fewer
        BNE unpack_run_cell             ; $0B28  the same tile again
        JSR step_ptr_06                 ; $0B2A  past the tile
        JMP unpack_command              ; $0B2D  the next command
unpack_done:
        JSR point_lamp_list             ; $0B30  the lamps
        JSR show_screen                 ; $0B33  screen on
        NOP                             ; $0B36  five spare bytes
        NOP                             ; $0B37  spare
        NOP                             ; $0B38  spare
        NOP                             ; $0B39  spare
        NOP                             ; $0B3A  spare
        LDA $47                         ; $0B3B  the sprites saved at the start
        STA $D015                       ; $0B3D  sprite enable
        JMP run_frame_hook              ; $0B40  the room's enter hook, and return from there
; Advance ($04) by one, the same as step_ptr_04. swap_room_lamps uses it
; to walk the waiting player's flags at $0340.
step_ptr_04b:
        INC $04                         ; $0B43  one on
        BNE step_ptr_04b_done           ; $0B45  no carry
        INC $05                         ; $0B47  the carry
step_ptr_04b_done:
        RTS                             ; $0B49  back

; $0B4A  7 bytes that no instruction reaches. They decode as a second copy
; of step_ptr_06: INC $06, BNE +2, INC $07, RTS.

; Advance ($10) by one. The unpack's upper color cell.
step_ptr_10:
        INC $10                         ; $0B51  one on
        BNE step_ptr_10_done            ; $0B53  no carry
        INC $11                         ; $0B55  the carry
step_ptr_10_done:
        RTS                             ; $0B57  back
; Advance ($12) by one. The unpack's lower color cell.
step_ptr_12:
        INC $12                         ; $0B58  one on
        BNE step_ptr_12_done            ; $0B5A  no carry
        INC $13                         ; $0B5C  the carry
step_ptr_12_done:
        RTS                             ; $0B5E  back
; A packed tile with bit 7 set. Color $F8 goes on both color rows, over
; the room fill, and A comes back as the tile without bit 7.
bright_cell:
        PHA                             ; $0B5F  keep the tile
        LDA #$F8                        ; $0B60  multicolor, ink 0
        STA ($10),Y                     ; $0B62  the upper color
        STA ($12),Y                     ; $0B64  the lower color
        PLA                             ; $0B66  the tile
        AND #$7F                        ; $0B67  without bit 7
        RTS                             ; $0B69  back

; $0B6A  36 bytes of code that nothing calls. It saves A, X, and Y in
; $54-$56 (the helper at $0B80), writes $86 four times through ($04) with
; step_ptr_04b between, stores $27 in $4C, and restores the registers (the
; helper at $0B87). It looks like an older way of starting a picture row,
; left behind when the unpack in enter_room_body replaced it.

; Mark this actor present and give him a standing picture. A carries the extra active
; flags. X is the actor. $98,X starts at $0F, which is no direction. The three
; rolls of the value just stored pick a column of $59A8. $01, $41, and $81
; land on 0, 1, and 2 whether carry came in set or clear. store_pose uses
; the same rolls on $59A5, whose room 0 bytes are 00 8C 46 04: Bruce, the
; ninja, Yamo, and a fourth copy.
; It does not store $C2,X, so the state release_hold saw before he left
; is still there after a wake.
wake_actor:
        ORA #$01                        ; $0B8E  in the room
        STA active,X                    ; $0B90  active
        ROL A                           ; $0B92  bit 7 into carry
        ROL A                           ; $0B93  bits 7 and 6 at the bottom
        ROL A                           ; $0B94  bit 6 into carry
        AND #$03                        ; $0B95  0, 1, or 2
        TAY                             ; $0B97  the column
        STY $52                         ; $0B98  kept
        LDA $59A8,Y                     ; $0B9A  his first slot
        STA $EC,X                       ; $0B9D  kept
        JSR claim_voice_slot            ; $0B9F  claimed for him
        LDY $52                         ; $0BA2  the column
        LDA $59AB,Y                     ; $0BA4  his second slot
        STA $EF,X                       ; $0BA7  kept
        BEQ wake_reset_fields           ; $0BA9  none
        JSR claim_voice_slot            ; $0BAB  claimed for him
wake_reset_fields:
        LDY $52                         ; $0BAE  the column
        LDA #$00                        ; $0BB0  zero
        STA state,X                     ; $0BB2  no state
        STA timer,X                     ; $0BB4  no timer
        STA $0106,X                     ; $0BB6  no hold
        LDA #$0F                        ; $0BB9  no direction
        STA $98,X                       ; $0BBB  his stick
        LDA #$01                        ; $0BBD  released
        STA $9B,X                       ; $0BBF  his fire
        LDA #$01                        ; $0BC1  on the ground
        STA hit,X                       ; $0BC3  his hit
        LDA #$01                        ; $0BC5  right
        STA facing,X                    ; $0BC7  his facing
        LDA #$02                        ; $0BC9  library 2
        STA $4F48,X                     ; $0BCB  relative library
        STA $4F4E,X                     ; $0BCE  absolute library
        LDA #$03                        ; $0BD1  library 3
        STA $4F4B,X                     ; $0BD3  relative second library
        STA $4F51,X                     ; $0BD6  absolute second library
        LDA #$24                        ; $0BD9  36
        STA $D1,X                       ; $0BDB  health
        STX $51                         ; $0BDD  the actor
        LDA $0104                       ; $0BDF  the demo?
        BEQ main_spawn                  ; $0BE2  yes: the main spawn
        TXA                             ; $0BE4  the actor
        BNE spawn_pick_side             ; $0BE5  a fighter picks a side
; The room's first spawn point, xpos from $4BAE+room and ypos from
; $4BC2+room. spawn_store_position stores them for the actor saved in $51.
main_spawn:
        LDX $29                         ; $0BE7  the room
        LDA $4BC2,X                     ; $0BE9  spawn ypos
        TAY                             ; $0BEC  kept
        LDA $4BAE,X                     ; $0BED  spawn xpos
spawn_store_position:
        LDX $51                         ; $0BF0  the actor
        STA xpos,X                      ; $0BF2  xpos
        TYA                             ; $0BF4  ypos
        STA ypos,X                      ; $0BF5  ypos
        JMP spawn_place_sprites         ; $0BF7  the sprites, and return from there
; $0104 clear, and Bruce himself, use main_spawn ($4BAE/$4BC2). A fighter
; with $8A,X clear picks a side. Yamo reads $136F for this room. 0, or
; a noise byte of $C0 or more, is toss_side: the low bit of a new noise
; byte, clear for main_spawn and set for alt_spawn ($4BD6/$4BEA). A smaller
; noise byte follows bit 7 of $136F, set for the alternate spot. The ninja reads
; $1333 the same way, and when that byte is keeping him he follows bit 7 of
; Yamo's $136F. A nonzero $8A,X resumes: that byte is the xpos, $8C,X
; the ypos, and $8E,X the health, and the xpos byte is then cleared. Actor 1's
; bytes are $8B, $8D, and $8F. Actor 2's are $8C, $8E, and $90. finish_exit
; writes Bruce's position and this fighter's $D1 there when he was active.
; The four position tables are listed in rooms.asm.
spawn_pick_side:
        LDA $8A,X                       ; $0BFA  a saved place?
        BNE spawn_resume                ; $0BFC  yes: resume there
        CPX #$01                        ; $0BFE  Yamo?
        BNE ninja_side                  ; $0C00  no: the ninja
        LDX $29                         ; $0C02  the room
        LDA $136F,X                     ; $0C04  Yamo's side byte
        BEQ toss_side                   ; $0C07  0: toss
        JSR noise_byte                  ; $0C09  a noise byte
        CMP #$C0                        ; $0C0C  $C0 or more?
        BCS toss_side                   ; $0C0E  yes: toss
        LDA $136F,X                     ; $0C10  the side byte again
        BPL main_spawn                  ; $0C13  bit 7 clear: the main spawn
        BMI alt_spawn                   ; $0C15  set: the second spawn
; A fresh noise byte picks the side: bit 0 clear is main_spawn, set is
; alt_spawn.
toss_side:
        JSR noise_byte                  ; $0C17  a noise byte
        AND #$01                        ; $0C1A  bit 0
        BEQ main_spawn                  ; $0C1C  clear: the main spawn
; The room's second spawn point, xpos from $4BD6+room and ypos from
; $4BEA+room.
alt_spawn:
        LDX $29                         ; $0C1E  the room
        LDA $4BEA,X                     ; $0C20  spawn ypos
        TAY                             ; $0C23  kept
        LDA $4BD6,X                     ; $0C24  spawn xpos
        JMP spawn_store_position        ; $0C27  store them
; The ninja's side choice. $1333+room of 0 tosses. Otherwise a noise byte
; of $C0 or more tosses, and a smaller one lets bit 7 of $136F+room decide:
; clear is main_spawn, set is alt_spawn. $136F is the table Yamo reads too.
ninja_side:
        LDX $29                         ; $0C2A  the room
        LDA $1333,X                     ; $0C2C  the ninja's side byte
        BEQ toss_side                   ; $0C2F  0: toss
        JSR noise_byte                  ; $0C31  a noise byte
        CMP #$C0                        ; $0C34  $C0 or more?
        BCS toss_side                   ; $0C36  yes: toss
        LDA $136F,X                     ; $0C38  Yamo's side byte
        BPL main_spawn                  ; $0C3B  bit 7 clear: the main spawn
        BMI alt_spawn                   ; $0C3D  set: the second spawn
spawn_resume:
        STA xpos,X                      ; $0C3F  the saved xpos
        LDA $8C,X                       ; $0C41  the saved ypos
        STA ypos,X                      ; $0C43  ypos
        LDA $8E,X                       ; $0C45  the saved health
        STA $D1,X                       ; $0C47  health
        LDA #$00                        ; $0C49  zero
        STA $8A,X                       ; $0C4B  the saved place is used up
spawn_place_sprites:
        LDA $276D,X                     ; $0C4D  his first sprite
        LDY $277D                       ; $0C50  the second picture set?
        BEQ spawn_set_pointers          ; $0C53  no
        CLC                             ; $0C55  carry clear
        ADC #$05                        ; $0C56  five on
spawn_set_pointers:
        TAY                             ; $0C58  the index
        LDA $2763,Y                     ; $0C59  the image for it
        LDY $276D,X                     ; $0C5C  his first sprite
        STA $8FF8,Y                     ; $0C5F  its pointer
        INY                             ; $0C62  the next sprite
        CLC                             ; $0C63  carry clear
        ADC #$01                        ; $0C64  the next image
        STA $8FF8,Y                     ; $0C66  its pointer
        LDA xpos,X                      ; $0C69  xpos
        ASL A                           ; $0C6B  screen x, bit 8 into carry
        PHA                             ; $0C6C  kept
        LDY $276D,X                     ; $0C6D  his first sprite
        LDA $D010                       ; $0C70  sprite x bit 8
        BCC spawn_clear_x_high          ; $0C73  bit 8 clear
        ORA $2773,Y                     ; $0C75  this sprite's bit
        BNE spawn_store_x_high          ; $0C78  always
spawn_clear_x_high:
        AND $2778,Y                     ; $0C7A  without this sprite's bit
spawn_store_x_high:
        STA $D010                       ; $0C7D  sprite x bit 8
        TYA                             ; $0C80  the sprite
        ASL A                           ; $0C81  times 2
        TAY                             ; $0C82  its register pair
        PLA                             ; $0C83  screen x
        STA $D000,Y                     ; $0C84  sprite 0 x, plus Y
        LDA ypos,X                      ; $0C87  ypos
        CLC                             ; $0C89  carry clear
        ADC #$1D                        ; $0C8A  plus $1D
        STA $D001,Y                     ; $0C8C  sprite 0 y, plus Y
        LDA $2770,X                     ; $0C8F  his second sprite
        BMI spawn_enable_sprites        ; $0C92  none
        LDA xpos,X                      ; $0C94  xpos
        ASL A                           ; $0C96  screen x, bit 8 into carry
        PHA                             ; $0C97  kept
        LDY $2770,X                     ; $0C98  his second sprite
        LDA $D010                       ; $0C9B  sprite x bit 8
        BCC spawn_clear_x_high2         ; $0C9E  bit 8 clear
        ORA $2773,Y                     ; $0CA0  this sprite's bit
        BNE spawn_store_x_high2         ; $0CA3  always
spawn_clear_x_high2:
        AND $2778,Y                     ; $0CA5  without this sprite's bit
spawn_store_x_high2:
        STA $D010                       ; $0CA8  sprite x bit 8
        TYA                             ; $0CAB  the sprite
        ASL A                           ; $0CAC  times 2
        TAY                             ; $0CAD  its register pair
        PLA                             ; $0CAE  screen x
        STA $D000,Y                     ; $0CAF  sprite 0 x, plus Y
        LDA ypos,X                      ; $0CB2  ypos
        CLC                             ; $0CB4  carry clear
        ADC #$1D                        ; $0CB5  plus $1D
        STA $D001,Y                     ; $0CB7  sprite 0 y, plus Y
spawn_enable_sprites:
        LDY $276D,X                     ; $0CBA  his first sprite
        LDA $D015                       ; $0CBD  sprite enable
        ORA $2773,Y                     ; $0CC0  on
        STA $D015                       ; $0CC3  sprite enable
        LDY $2770,X                     ; $0CC6  his second sprite
        BMI spawn_done                  ; $0CC9  none
        LDA $D015                       ; $0CCB  sprite enable
        ORA $2773,Y                     ; $0CCE  on
        STA $D015                       ; $0CD1  sprite enable
spawn_done:
        RTS                             ; $0CD4  back
; Actor 1. Active becomes $81. State $10, timer $0A. $D1 above $14 is
; brought down to $14. The four stores name libraries $2A/$2B and absolute
; $6C/$6D. choose_pose runs before blit_sprites and writes $4F4E from state
; $10, so the picture drawn is relative library $2A.
spawn_yamo:
        JSR blip_and_return             ; $0CD5  effect $82
        LDA $CF79                       ; $0CD8  a check byte
        EOR $CF99                       ; $0CDB  EOR its partner
        STA $1166                       ; $0CDE  the byte score_blip tests
        LDX #$01                        ; $0CE1  Yamo
        LDA #$80                        ; $0CE3  bit 7: the green fighter
        JSR wake_actor                  ; $0CE5  wake him
        LDA #$10                        ; $0CE8  his first picture
        STA state,X                     ; $0CEA  state
        LDA #$2A                        ; $0CEC  library $2A
        STA $4F48,X                     ; $0CEE  relative
        LDA #$2B                        ; $0CF1  library $2B
        STA $4F4B,X                     ; $0CF3  relative second
        LDA #$6C                        ; $0CF6  library $6C
        STA $4F4E,X                     ; $0CF8  absolute
        LDA #$6D                        ; $0CFB  library $6D
        STA $4F51,X                     ; $0CFD  absolute second
        LDA #$0A                        ; $0D00  ten counts
        STA timer,X                     ; $0D02  timer
        LDA $D1,X                       ; $0D04  health
        CMP #$14                        ; $0D06  $14 or more?
        BCC spawn_yamo_done             ; $0D08  no
        LDA #$14                        ; $0D0A  capped
        STA $D1,X                       ; $0D0C  at $14
spawn_yamo_done:
        RTS                             ; $0D0E  back
; Wake Yamo when $5E has reached 0 and actor 1's active bit 0 is
; clear. $135B for this room is then stored back into $5E. $42CA set
; replaces that with $30. test_visit: V set (long, $88 >= $20) or $40 set
; stores 3, carry set (middle, $88 >= $19) halves it, and a short visit
; leaves the table byte.
try_yamo:
        LDA $5E                         ; $0D0F  Yamo's wake count
        BNE try_yamo_done               ; $0D11  still counting
        LDX #$01                        ; $0D13  Yamo
        LDA active,X                    ; $0D15  active
        AND #$01                        ; $0D17  in the room?
        BNE try_yamo_done               ; $0D19  yes
        JSR spawn_yamo                  ; $0D1B  wake him
        LDX $29                         ; $0D1E  the room
        LDA $135B,X                     ; $0D20  the next count
        STA $5E                         ; $0D23  stored
; Human opponent reloads actor 1's count with $30.
        LDA $42CA                       ; $0D25  a second player?
        BEQ try_yamo_visit              ; $0D28  no
        LDA #$30                        ; $0D2A  $30
        STA $5E                         ; $0D2C  stored
try_yamo_visit:
        JSR test_visit                  ; $0D2E  how long Bruce has been in the room
        BVS yamo_soon                   ; $0D31  long: soon
        BCS try_yamo_halve              ; $0D33  middle: halve
        LDA $40                         ; $0D35  a set $40?
        BNE yamo_soon                   ; $0D37  yes: soon
        RTS                             ; $0D39  short: the table's count
try_yamo_halve:
        LSR $5E                         ; $0D3A  halved
try_yamo_done:
        RTS                             ; $0D3C  back
; A long visit, or a finished game in $40: Yamo's next wake is in 3 frames.
yamo_soon:
        LDA #$03                        ; $0D3D  three frames
        STA $5E                         ; $0D3F  Yamo's wake count
        RTS                             ; $0D41  back
; X = 1 reloads Yamo only. X = 2 branches to the ninja's count.
; Any other X, including the 0 finish_exit passes before a room starts,
; reloads both. retire_actor jumps here with the fighter who just left.
; The LDA $E000 is rewritten to $135B+room or $131F+room. The visit
; adjustments match try_yamo and try_ninja.
load_wake_counts:
        CPX #$01                        ; $0D42  Yamo?
        BNE load_wake_not_yamo          ; $0D44  no
; $5E = the byte at $135B+room, through the operand the stores above rewrite.
; A human opponent then stores $30 over it.
load_yamo_count:
        LDA #$5B                        ; $0D46  $5B
        CLC                             ; $0D48  carry clear
        ADC $29                         ; $0D49  plus the room
        STA $0D56                       ; $0D4B  the operand below, low
        LDA #$13                        ; $0D4E  $13
        ADC #$00                        ; $0D50  the carry
        STA $0D57                       ; $0D52  the operand, high
        LDA $E000                       ; $0D55  $135B+room
        STA $5E                         ; $0D58  Yamo's wake count
; Same override when actor 1 is the one being restarted.
        LDA $42CA                       ; $0D5A  a second player?
        BEQ load_yamo_visit             ; $0D5D  no
        LDA #$30                        ; $0D5F  $30
        STA $5E                         ; $0D61  stored
load_yamo_visit:
        JSR test_visit                  ; $0D63  how long Bruce has been in the room
        BVS yamo_soon                   ; $0D66  long: soon
        BCS load_yamo_halve             ; $0D68  middle: halve
        LDA $40                         ; $0D6A  a set $40?
        BNE yamo_soon                   ; $0D6C  yes: soon
        RTS                             ; $0D6E  short: the table's count
load_yamo_halve:
        LSR $5E                         ; $0D6F  halved
        RTS                             ; $0D71  back
load_wake_not_yamo:
        CPX #$02                        ; $0D72  the ninja?
        BNE load_both_counts            ; $0D74  no: both
; $5D = the byte at $131F+room, the same way.
load_ninja_count:
        LDA #$1F                        ; $0D76  $1F
        CLC                             ; $0D78  carry clear
        ADC $29                         ; $0D79  plus the room
        STA $0D86                       ; $0D7B  the operand below, low
        LDA #$13                        ; $0D7E  $13
        ADC #$00                        ; $0D80  the carry
        STA $0D87                       ; $0D82  the operand, high
        LDA $E000                       ; $0D85  $131F+room
        STA $5D                         ; $0D88  the ninja's wake count
        JSR test_visit                  ; $0D8A  how long Bruce has been in the room
        BVS ninja_soon                  ; $0D8D  long: soon
        BCS load_ninja_halve            ; $0D8F  middle: halve
        LDA $40                         ; $0D91  a set $40?
        BNE ninja_soon                  ; $0D93  yes: soon
        RTS                             ; $0D95  short: the table's count
load_ninja_halve:
        LSR $5D                         ; $0D96  halved
        RTS                             ; $0D98  back
; A long visit, or a finished game in $40: the ninja's next wake is in 3 frames.
ninja_soon:
        LDA #$03                        ; $0D99  three frames
        STA $5D                         ; $0D9B  the ninja's wake count
        RTS                             ; $0D9D  back
load_both_counts:
        JSR load_yamo_count             ; $0D9E  Yamo's
        JMP load_ninja_count            ; $0DA1  then the ninja's
; frame calls this once per logic frame, and skips it while $7A is set.
; A count of 0 is left at 0, which is why a table byte of 0 wakes on the
; first check. Both counts move while the fighters are already on screen.
tick_wake_counts:
        LDA $5D                         ; $0DA4  the ninja's count
        BEQ tick_yamo_count             ; $0DA6  0: stays 0
        DEC $5D                         ; $0DA8  one less
tick_yamo_count:
        LDA $5E                         ; $0DAA  Yamo's count
        BEQ tick_wake_done              ; $0DAC  0: stays 0
        DEC $5E                         ; $0DAE  one less
tick_wake_done:
        RTS                             ; $0DB0  back
; Wake the ninja when $5D has reached 0 and actor 2's active bit 0 is clear.
; Bit 0 of $96 can hold that off: $40 clear, $42CA clear, and test_visit
; returning a short visit, a noise byte of $19 or more stores $10 back
; into $5D and returns. Otherwise $131F for this room is stored into $5D
; and the same visit adjustment as Yamo's is applied.
try_ninja:
        LDA $5D                         ; $0DB1  the ninja's count
        BNE try_ninja_done              ; $0DB3  still counting
        LDA $96                         ; $0DB5  the ninja's active byte
        AND #$01                        ; $0DB7  bit 0
        BEQ try_ninja_wake              ; $0DB9  clear: wake him
        LDA $40                         ; $0DBB  a set $40?
        BNE try_ninja_wake              ; $0DBD  yes: wake
        LDA $42CA                       ; $0DBF  a second player?
        BNE try_ninja_wake              ; $0DC2  yes: wake
        JSR test_visit                  ; $0DC4  how long Bruce has been in the room
        BVS try_ninja_wake              ; $0DC7  long: wake
        BCS try_ninja_wake              ; $0DC9  middle: wake
        JSR noise_byte                  ; $0DCB  a noise byte
        CMP #$19                        ; $0DCE  below $19?
        BCC try_ninja_wake              ; $0DD0  yes: wake
        LDA #$10                        ; $0DD2  16 frames
        STA $5D                         ; $0DD4  more for the ninja
        RTS                             ; $0DD6  back
try_ninja_wake:
        LDX #$02                        ; $0DD7  the ninja
        LDA active,X                    ; $0DD9  active
        AND #$01                        ; $0DDB  in the room?
        BNE try_ninja_done              ; $0DDD  yes
        JSR spawn_ninja                 ; $0DDF  wake him
        LDX $29                         ; $0DE2  the room
        LDA $131F,X                     ; $0DE4  the next count
        STA $5D                         ; $0DE7  stored
        JSR test_visit                  ; $0DE9  how long Bruce has been in the room
        BVS ninja_soon                  ; $0DEC  long: soon
        BCS try_ninja_halve             ; $0DEE  middle: halve
        LDA $40                         ; $0DF0  a set $40?
        BNE ninja_soon                  ; $0DF2  yes: soon
        RTS                             ; $0DF4  short: the table's count
try_ninja_halve:
        LSR $5D                         ; $0DF5  halved
try_ninja_done:
        RTS                             ; $0DF7  back
; Actor 2. Active becomes $41. $D1 above 7 is brought down to 7. Timer
; $10 of state 0, so he stands until it expires. $4F4B and $4F51 are
; cleared: $2770 for actor 2 is $FF, and blit_sprites skips his second
; image on its own. $4F4E is set to $82. choose_pose on this same frame
; replaces it from state 0 before the blit. range_to_bruce and
; face_from_dx turn him toward Bruce. Bit 7 of $63 means Bruce is to his
; right.
spawn_ninja:
        JSR blip_and_return             ; $0DF8  effect $82
        LDA #$40                        ; $0DFB  bit 6: the ninja
        JSR wake_actor                  ; $0DFD  wake him
        LDA #$82                        ; $0E00  library $82
        STA $4F4E,X                     ; $0E02  absolute
        LDA #$00                        ; $0E05  none
        STA $4F4B,X                     ; $0E07  no relative second library
        STA $4F51,X                     ; $0E0A  no absolute second library
        LDA $D1,X                       ; $0E0D  health
        CMP #$07                        ; $0E0F  7 or more?
        BCC spawn_ninja_timer           ; $0E11  no
        LDA #$07                        ; $0E13  capped
        STA $D1,X                       ; $0E15  at 7
spawn_ninja_timer:
        LDA #$10                        ; $0E17  16 counts
        STA timer,X                     ; $0E19  he stands that long
        JSR range_to_bruce              ; $0E1B  dx and dy
        JMP face_from_dx                ; $0E1E  face Bruce, and return from there
; A is an effect number of 3 or more. $59AE,A-3 picks a byte of $4F40,
; and X, the actor, is stored there.
; The room snapshots hold 04 00 01 02 03 01 02 04 08 10 at $59AE.
claim_voice_slot:
        SEC                             ; $0E21  from effect 3
        SBC #$03                        ; $0E22  on
        TAY                             ; $0E24  the index
        LDA $59AE,Y                     ; $0E25  the slot
        TAY                             ; $0E28  its index
        TXA                             ; $0E29  the actor
        STA $4F40,Y                     ; $0E2A  owns it
        RTS                             ; $0E2D  back
; Reads the five bytes at $0E3B and throws them away, keeping X. open_room
; calls it before the TM sprite is copied. It has no effect; it may be
; left from a check that was taken out.
tm_dummy_read:
        TXA                             ; $0E2E  keep X
        PHA                             ; $0E2F  kept
        LDX #$04                        ; $0E30  five bytes
tm_dummy_loop:
        LDA $0E3B,X                     ; $0E32  read
        DEX                             ; $0E35  the next
        BPL tm_dummy_loop               ; $0E36  more
        PLA                             ; $0E38  X back
        TAX                             ; $0E39  into X
        RTS                             ; $0E3A  back

; $0E3B  5 bytes read and discarded by tm_dummy_read. $0E40 is 12 bytes, four rows of
; the TM sprite copied to $83CC.

; Flip bit 6 on the F5 row ($8E40, twenty bytes: row 14, columns 16-35), then
; draw the word selected by $42CA. $4D is the inverse dash and is left as it is.
flip_menu_b:
        LDX #$13                        ; $0E4C  20 cells
flip_menu_b_loop:
        LDA $8E40,X                     ; $0E4E  row 14, from column 16
        CMP #$4D                        ; $0E51  the dash?
        BEQ flip_menu_b_next            ; $0E53  yes: leave it
        EOR #$40                        ; $0E55  the other glyph set
        STA $8E40,X                     ; $0E57  back
flip_menu_b_next:
        DEX                             ; $0E5A  the next
        BPL flip_menu_b_loop            ; $0E5B  more
        LDX #$50                        ; $0E5D  the F5 row
        LDA $42CA                       ; $0E5F  the opponent option
        JMP draw_menu_word              ; $0E62  its word, and return from there
; Flip bit 6 on the F3 row ($8DF0, row 12, columns 16-35), then the word for $42C9.
flip_menu_a:
        LDX #$13                        ; $0E65  20 cells
flip_menu_a_loop:
        LDA $8DF0,X                     ; $0E67  row 12, from column 16
        CMP #$4D                        ; $0E6A  the dash?
        BEQ flip_menu_a_next            ; $0E6C  yes: leave it
        EOR #$40                        ; $0E6E  the other glyph set
        STA $8DF0,X                     ; $0E70  back
flip_menu_a_next:
        DEX                             ; $0E73  the next
        BPL flip_menu_a_loop            ; $0E74  more
        LDX #$00                        ; $0E76  the F3 row
        LDA $42C9                       ; $0E78  the players option
; X is 0 for the F3 row and $50 for the F5 row, one double-row lower. A = 0 keeps
; the first choice, 1 PLAYER or COMPUTER. A nonzero selects 2 PLAYERS or
; OPPONENT. The EOR above flips the letters. These four stores repair the
; key-cap glyphs and the extra S, which are not a plain inverse.
draw_menu_word:
        BNE menu_second_choice          ; $0E7B  the second choice?
        LDA #$42                        ; $0E7D  a key-cap glyph
        STA $8DEF,X                     ; $0E7F  row 12 column 15, or row 14
        LDA #$40                        ; $0E82  a key-cap glyph
        STA $8DF8,X                     ; $0E84  column 24
        LDA #$56                        ; $0E87  a key-cap glyph
        STA $8DFA,X                     ; $0E89  column 26
        LDA #$00                        ; $0E8C  blank
        STA $8E04,X                     ; $0E8E  column 36: no extra S
        RTS                             ; $0E91  back
; A nonzero: the glyphs for 2 PLAYERS or OPPONENT.
menu_second_choice:
        LDA #$00                        ; $0E92  blank
        STA $8DEF,X                     ; $0E94  column 15
        LDA #$42                        ; $0E97  a key-cap glyph
        STA $8DF8,X                     ; $0E99  column 24
        LDA #$40                        ; $0E9C  a key-cap glyph
        STA $8DFA,X                     ; $0E9E  column 26
        LDA #$56                        ; $0EA1  a key-cap glyph
        STA $8E04,X                     ; $0EA3  column 36
        RTS                             ; $0EA6  back
; PLAYER page. The whole screen is charset $8000, multicolor, background blue.
; $03 picks the player. His two digit glyphs are copied from $4A7D into the
; lines at $4A5D, and those lines are stored with bit 7 set at $8D24 and
; $8D4C, row 7 column 12 and row 8 column 12. The glyphs are multicolor pair
; 01, so the ink is $D022, which between_raster cycles. $48 starts at $40
; frames, or $80 when $42C9 is set. The raster decrements it. The countdown in
; $18/$19/$1A is longer than either of those, so the page ends on $48.
between_rooms:
        SEI                             ; $0EA7  no interrupts
        LDA $D011                       ; $0EA8  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0EAB  screen off
        STA $D011                       ; $0EAD  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $0EB0  none
        STA $D015                       ; $0EB2  sprite enable
        LDA #$06                        ; $0EB5  blue
        STA $D020                       ; $0EB7  border color
        STA $D021                       ; $0EBA  background color
        LDX #$00                        ; $0EBD  256 bytes a page
        LDA #$DC                        ; $0EBF  a blank code
between_rooms_blank:
        STA $8C00,X                     ; $0EC1  the screen, page 1
        STA $8D00,X                     ; $0EC4  page 2
        STA $8E00,X                     ; $0EC7  page 3
        STA $8F00,X                     ; $0ECA  page 4, with the sprite pointers
        INX                             ; $0ECD  the next
        BNE between_rooms_blank         ; $0ECE  until X wraps
        JSR silence_sid                 ; $0ED0  the effect voices
        LDA $03                         ; $0ED3  the player
        ASL A                           ; $0ED5  times 2
        TAX                             ; $0ED6  his digit pair
        LDY #$00                        ; $0ED7  two glyphs
; $4A7D is eight digit glyphs: player 1, then player 2, each line pair.
; X is $03 times 2. The first pair replaces columns 14-15 of line 1, the
; second pair the same columns of line 2.
patch_player_digits:
        LDA $4A7D,X                     ; $0ED9  a top-line digit glyph
        STA $4A6B,Y                     ; $0EDC  into line 1
        LDA $4A81,X                     ; $0EDF  a bottom-line digit glyph
        STA $4A7B,Y                     ; $0EE2  into line 2
        INX                             ; $0EE5  the next glyph
        INY                             ; $0EE6  the next column
        CPY #$02                        ; $0EE7  two?
        BCC patch_player_digits         ; $0EE9  no
        LDX #$0F                        ; $0EEB  16 cells
between_rooms_player_word:
        LDA $4A5D,X                     ; $0EED  line 1
        ORA #$80                        ; $0EF0  the upper half of the charset
        STA $8D24,X                     ; $0EF2  row 7, from column 12
        LDA $4A6D,X                     ; $0EF5  line 2
        ORA #$80                        ; $0EF8  the upper half
        STA $8D4C,X                     ; $0EFA  row 8, from column 12
        DEX                             ; $0EFD  the next
        BPL between_rooms_player_word   ; $0EFE  more
        LDA #$A4                        ; $0F00  low byte of between_raster
        STA $0408                       ; $0F02  the vector at $0408
        LDA #$14                        ; $0F05  high
        STA $0409                       ; $0F07  the vector
        LDA #$01                        ; $0F0A  the raster interrupt
        STA $D01A                       ; $0F0C  VIC interrupt enable
        STA $D019                       ; $0F0F  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $0F12  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $0F15  raster bit 8 clear
        STA $D011                       ; $0F17  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$63                        ; $0F1A  line $63
        STA $D012                       ; $0F1C  raster line
        LDA #$30                        ; $0F1F  screen $8C00, charset $8000
        STA $D018                       ; $0F21  screen and charset address
        LDA #$18                        ; $0F24  multicolor on, no scroll
        STA $D016                       ; $0F26  VIC control: xscroll, multicolor
        JSR show_screen                 ; $0F29  screen on
        NOP                             ; $0F2C  five spare bytes
        NOP                             ; $0F2D  spare
        NOP                             ; $0F2E  spare
        NOP                             ; $0F2F  spare
        NOP                             ; $0F30  spare
        CLI                             ; $0F31  interrupts on
        LDA #$80                        ; $0F32  $80
        STA $18                         ; $0F34  count, low
        STA $19                         ; $0F36  count, middle
        LDA #$03                        ; $0F38  3
        STA $1A                         ; $0F3A  count, high
        LDA #$40                        ; $0F3C  64 frames
        STA $48                         ; $0F3E  the raster count
        LDA $42C9                       ; $0F40  two players?
        BEQ player_page_wait            ; $0F43  no
        ASL $48                         ; $0F45  128 frames
player_page_wait:
        LDA $48                         ; $0F47  the raster count
        BEQ player_page_done            ; $0F49  out: done
        LDA $18                         ; $0F4B  the low byte
        BEQ player_page_count_mid       ; $0F4D  0: borrow
        DEC $18                         ; $0F4F  one less
        JMP player_page_test            ; $0F51  test
player_page_count_mid:
        LDA $19                         ; $0F54  the middle byte
        BEQ player_page_count_high      ; $0F56  0: borrow again
        DEC $18                         ; $0F58  $FF
        DEC $19                         ; $0F5A  one less
        JMP player_page_test            ; $0F5C  test
player_page_count_high:
        LDA $1A                         ; $0F5F  the high byte
        BEQ player_page_test            ; $0F61  0: the count is out
        DEC $18                         ; $0F63  $FF
        DEC $19                         ; $0F65  $FF
        DEC $1A                         ; $0F67  one less
player_page_test:
        LDA $18                         ; $0F69  the count
        ORA $19                         ; $0F6B  ORed with the middle byte
        ORA $1A                         ; $0F6D  all three bytes
        BNE player_page_wait            ; $0F6F  not out: wait on
player_page_done:
        RTS                             ; $0F71  back
; Zero $03 through $F5, the nibble tables at $4EED, and the per-room slots
; at $0300. $28, $29, $40, and the score at $41-$43 are in that range, so a
; game that reaches here through open_room starts in room 0 with no score
; and difficulty 0. The top score at $4388 is not in the range and remains.
; Falls are then stored as 4, or 9 when $42CA is set, and the 40000 mark
; is copied back. $4E95 and $4E96, the extra-fall counters, go back to 5.
clear_work_ram:
        LDA #$00                        ; $0F72  zero
        TAX                             ; $0F74  every page offset
clear_work_loop:
        CPX #$F3                        ; $0F75  past $F5?
        BCS clear_work_nibbles          ; $0F77  yes
        STA $03,X                       ; $0F79  $03-$F5
clear_work_nibbles:
        CPX #$FB                        ; $0F7B  past $4FE7?
        BCS clear_work_next             ; $0F7D  yes
        STA $4EED,X                     ; $0F7F  $4EED-$4FE7
clear_work_next:
        INX                             ; $0F82  the next
        BNE clear_work_loop             ; $0F83  until X wraps
        STA $89                         ; $0F85  no idle handover yet
        STA $8A                         ; $0F87  no saved place
        LDX #$07                        ; $0F89  eight bytes
        LDA #$01                        ; $0F8B  1
clear_work_page1:
        STA $014B,X                     ; $0F8D  $014B-$0152
        STA $0100,X                     ; $0F90  $0100-$0107
        DEX                             ; $0F93  the next
        BPL clear_work_page1            ; $0F94  more
        JSR silence_sid                 ; $0F96  the effect voices
        LDA #$05                        ; $0F99  5
        STA $4E95                       ; $0F9B  the extra-fall counter
        STA $4E96                       ; $0F9E  and the other player's
        JSR copy_room_defaults          ; $0FA1  the room bytes
        LDX #$27                        ; $0FA4  40 flags
        LDA #$01                        ; $0FA6  set
clear_work_room_flags:
        STA $0300,X                     ; $0FA8  the room bonus flags
        DEX                             ; $0FAB  the next
        BPL clear_work_room_flags       ; $0FAC  more
        LDA #$00                        ; $0FAE  clear
        STA $0300                       ; $0FB0  room 0, player 1
        STA $0301                       ; $0FB3  room 0, player 2
        JSR restore_lamps               ; $0FB6  the lamps
        JSR fill_0340                   ; $0FB9  the waiting player's lamps
; Falls. 4 against the computer. 9 when $42CA is the human opponent.
; FALLS 00 is still a life. The count is Bruce's. Yamo has none, and his
; hits do not add to the score. The Remember trainer can turn the later
; DEC and INC of $28 into LDA.
        LDA #$04                        ; $0FBC  4
        STA $28                         ; $0FBE  falls
        LDA $42CA                       ; $0FC0  a second player?
        BEQ clear_work_marks            ; $0FC3  no
        LDA #$09                        ; $0FC5  9
        STA $28                         ; $0FC7  falls
clear_work_marks:
; Extra-fall mark for both players. $438B in room00.vsf is 00 9C 40,
; 40000. $4392 is the live mark and $4395 is the other player's copy.
; The step added on a crossing sits at $438E: 00 75 30, 30000.
        LDX #$02                        ; $0FC9  three bytes
clear_work_mark_loop:
        LDA $438B,X                     ; $0FCB  the first mark
        STA $4392,X                     ; $0FCE  the live mark
        STA $4395,X                     ; $0FD1  the other player's
        DEX                             ; $0FD4  the next
        BPL clear_work_mark_loop        ; $0FD5  more
        LDX #$1B                        ; $0FD7  28 bytes
clear_work_save_player:
        LDA $28,X                       ; $0FD9  $28-$43
        STA $439F,X                     ; $0FDB  the other player's copy
        DEX                             ; $0FDE  the next
        BPL clear_work_save_player      ; $0FDF  more
        RTS                             ; $0FE1  back
; Fill $0340-$03A0 with the value in A. Called with 1.
fill_0340:
        LDA #$01                        ; $0FE2  1
        LDX #$60                        ; $0FE4  97 bytes
fill_0340_loop:
        STA $0340,X                     ; $0FE6  $0340-$03A0
        DEX                             ; $0FE9  the next
        BPL fill_0340_loop              ; $0FEA  more
        RTS                             ; $0FEC  back
; Two players. Trade the live lamp-taken flags with the waiting player's
; copy at $0340, one room list at a time, rooms 0 through 19.
swap_waiting_lamps:
        LDA #$40                        ; $0FED  $40
        STA $04                         ; $0FEF  pointer, low
        LDA #$03                        ; $0FF1  $03
        STA $05                         ; $0FF3  $0340
        LDA #$00                        ; $0FF5  room 0
        STA $4E                         ; $0FF7  the room
swap_waiting_room:
        ASL A                           ; $0FF9  times 2
        TAX                             ; $0FFA  the index
        JSR swap_room_lamps             ; $0FFB  trade this room's flags
        INC $4E                         ; $0FFE  the next room
        LDA $4E                         ; $1000  the room
        CMP #$14                        ; $1002  20 rooms?
        BCC swap_waiting_room           ; $1004  no
        RTS                             ; $1006  back
; One room's list at $4CE2,X. Each four-byte record starts with a flag,
; and a record whose first byte has bit 7 set ends the list. The flag
; and the byte at ($04) change places, then ($04) steps one and ($0A)
; steps one record.
swap_room_lamps:
        LDA $4CE2,X                     ; $1007  the room's lamp list, low
        STA $0A                         ; $100A  pointer
        LDA $4CE3,X                     ; $100C  high
        STA $0B                         ; $100F  pointer
        LDY #$00                        ; $1011  Y stays 0
swap_room_record:
        LDA ($0A),Y                     ; $1013  a record's flag
        BMI swap_room_done              ; $1015  bit 7: the end
        PHA                             ; $1017  kept
        LDA ($04),Y                     ; $1018  the waiting player's flag
        TAX                             ; $101A  kept
        PLA                             ; $101B  the live flag
        STA ($04),Y                     ; $101C  to the waiting copy
        TXA                             ; $101E  the waiting flag
        STA ($0A),Y                     ; $101F  to the live list
        JSR next_lamp_record            ; $1021  the next record
        JSR step_ptr_04b                ; $1024  the next waiting flag
        JMP swap_room_record            ; $1027  the next record
swap_room_done:
        RTS                             ; $102A  back

; The idle pause. The twenty band color bytes at $0153 go to $47B4, and $82
; becomes $FE, so irq_service starts cycling the bands from that copy.
save_band_colors:
        LDX #$13                        ; $102B  20 bytes
save_band_loop:
        LDA $0153,X                     ; $102D  a band color
        STA $47B4,X                     ; $1030  kept
        DEX                             ; $1033  the next
        BPL save_band_loop              ; $1034  more
        LDA #$FE                        ; $1036  negative: the bands cycle
        STA $82                         ; $1038  the idle count
        RTS                             ; $103A  back

; The end of the idle pause. The colors at $47B4 go back to $0153 and $82
; is cleared, so the idle count starts over.
restore_band_colors:
        LDX #$13                        ; $103B  20 bytes
restore_band_loop:
        LDA $47B4,X                     ; $103D  a saved band color
        STA $0153,X                     ; $1040  back
        DEX                             ; $1043  the next
        BPL restore_band_loop           ; $1044  more
        LDA #$00                        ; $1046  zero
        STA $82                         ; $1048  the idle count starts over
        RTS                             ; $104A  back

; The sliding blocks, up to nine of them in $010F-$0149. A slot whose
; $010F byte is 0 is empty. A positive byte moves the block left, a
; negative one right, and it wraps between the bounds at $0137 and
; $0141. $70 and $6F are stored before the step and $6E after it. The
; column it left goes to $012D,X and the new one to $0119,X.
step_sliders:
        LDX #$08                        ; $104B  nine slots
slider_loop:
        LDA $010F,X                     ; $104D  this slot's direction
        BEQ slider_next                 ; $1050  empty
        TXA                             ; $1052  the slot
        PHA                             ; $1053  kept
        LDA $0119,X                     ; $1054  its column
        STA $012D,X                     ; $1057  the column it leaves
        STA $70                         ; $105A  for the draw
        LDA $0123,X                     ; $105C  its row
        STA $6F                         ; $105F  for the draw
        LDA $010F,X                     ; $1061  the direction
        BMI slider_right                ; $1064  negative: right
        DEC $0119,X                     ; $1066  one column left
        LDA $0119,X                     ; $1069  the new column
        CMP $0137,X                     ; $106C  still inside?
        BCS slider_left_draw            ; $106F  yes
        LDA $0141,X                     ; $1071  wrap to the right bound
        STA $0119,X                     ; $1074  the new column
slider_left_draw:
        STA $6E                         ; $1077  for the draw
        LDA $6F                         ; $1079  the row
        CMP #$05                        ; $107B  row 5?
        BEQ slider_draw_tall            ; $107D  yes: the tall block
        CMP #$0A                        ; $107F  row 10?
        BEQ slider_draw_tall            ; $1081  yes: the tall block
        JSR draw_slider                 ; $1083  draw it
        JMP slider_restore_x            ; $1086  the slot back
slider_draw_tall:
        JSR draw_slider_tall            ; $1089  draw the tall block
        JMP slider_restore_x            ; $108C  the slot back
slider_right:
        INC $0119,X                     ; $108F  one column right
        LDA $0119,X                     ; $1092  the new column
        CMP $0141,X                     ; $1095  still inside?
        BCC slider_right_draw           ; $1098  yes
        LDA $0137,X                     ; $109A  wrap to the left bound
        STA $0119,X                     ; $109D  the new column
slider_right_draw:
        STA $6E                         ; $10A0  for the draw
        LDA $6F                         ; $10A2  the row
        CMP #$05                        ; $10A4  row 5?
        BEQ slider_draw_tall            ; $10A6  yes: the tall block
        CMP #$0A                        ; $10A8  row 10?
        BEQ slider_draw_tall            ; $10AA  yes: the tall block
        JSR draw_slider                 ; $10AC  draw it
slider_restore_x:
        PLA                             ; $10AF  the slot
        TAX                             ; $10B0  back in X
slider_next:
        DEX                             ; $10B1  the next slot
        BPL slider_loop                 ; $10B2  more
        RTS                             ; $10B4  back

; Effect $82, restoring A, X, and Y. spawn_yamo and spawn_ninja
; both return through here.
blip_and_return:
        PHA                             ; $10B5  keep A
        TXA                             ; $10B6  X
        PHA                             ; $10B7  keep X
        TYA                             ; $10B8  Y
        PHA                             ; $10B9  keep Y
        LDY #$82                        ; $10BA  effect $82
        JSR play_sound                  ; $10BC  queue it
        PLA                             ; $10BF  Y back
        TAY                             ; $10C0  into Y
        PLA                             ; $10C1  X back
        TAX                             ; $10C2  into X
        PLA                             ; $10C3  A back
        RTS                             ; $10C4  back
; Copy the 20 default bytes at $4CCE into $2A. $2A,X is the lamps still
; to take in room X. claim_lamp decrements that byte. Rooms 13 and 19
; start at 0. The room 11 gate reads three of them by address:
;   $36 room 12, $38 room 14, $3A room 16.
copy_room_defaults:
        LDX #$13                        ; $10C5  20 rooms
copy_room_defaults_loop:
        LDA $4CCE,X                     ; $10C7  the room's lamp count
        STA $2A,X                       ; $10CA  live
        DEX                             ; $10CC  the next
        BPL copy_room_defaults_loop     ; $10CD  more
        RTS                             ; $10CF  back
; $88 against two marks. Carry comes back set when $88 is at least $19.
; Overflow comes back set when $88 is at least $20. A fresh room has $88
; at 0, so both are clear. Callers that BVS take the long visit: the spawn
; wait becomes 3, and a hit recovery uses the short timer. Callers that
; BCS, with V clear, take the middle visit and halve the wait. The
; two-player idle path stores $20, which is a long visit on the next test.
; $10DF is the RTS below. BIT of that $60 sets V from bit 6.
test_visit:
        LDA $88                         ; $10D0  the visit clock, high
        CMP #$20                        ; $10D2  $20 or more?
        BCS visit_hard                  ; $10D4  yes: long
        CMP #$19                        ; $10D6  carry set from $19: middle
        CLV                             ; $10D8  not long
        RTS                             ; $10D9  back
; $88 is $20 or more. Carry is still set from the CMP, and BIT of the $60
; at $10DF sets V, so the caller sees both.
visit_hard:
        LDA #$FF                        ; $10DA  $FF
        BIT $10DF                       ; $10DC  V from bit 6 of the RTS byte, $60
        RTS                             ; $10DF  back, carry and V set

; The current player's room-entry flags, $0300 + room*2 + player. Every
; room is set back to 1, then room 0 is cleared, so the opening room does
; not pay again. enter_room spends a set flag. Only the treasure ending
; calls this.
rearm_room_bonus:
        LDA $03                         ; $10E0  the player
        CLC                             ; $10E2  plus $26
        ADC #$26                        ; $10E3  room 19's flag
        TAX                             ; $10E5  room 19's flag
        LDA #$01                        ; $10E6  set
; X starts at $26 + player, room 19's flag, and steps two bytes per room.
rearm_slot:
        STA $0300,X                     ; $10E8  the room's flag
        DEX                             ; $10EB  two bytes a room
        DEX                             ; $10EC  two bytes: the room below
        BPL rearm_slot                  ; $10ED  more
        LDX $03                         ; $10EF  the player
        LDA #$00                        ; $10F1  clear
        STA $0300,X                     ; $10F3  room 0's flag
        RTS                             ; $10F6  back
; A bare RTS that boot calls. Something here may have been removed.
empty_hook:
        RTS                             ; $10F7  back
; $10F8  11 bytes that no instruction reads. The first two are $10F7, the
; address of empty_hook. The rest do not decode as anything the game uses.
; Hardware IRQ. $FFFE points here. Both branches jump through the
; pointer at $0408, which is $491E in this snapshot. $FFFA and $FFFC
; point at the RTI below.
irq_vector:
        PHA                             ; $1103  keep A
        TXA                             ; $1104  X
        PHA                             ; $1105  keep X
        TYA                             ; $1106  Y
        PHA                             ; $1107  keep Y
        TSX                             ; $1108  the stack
        LDA $0104,X                     ; $1109  the stacked status byte, read for nothing
        AND #$00                        ; $110C  always 0
        BEQ irq_jump                    ; $110E  always taken
        JMP ($0408)                     ; $1110  not reached
irq_jump:
        JMP ($0408)                     ; $1113  the raster handler in $0408
; NMI and reset. The RESTORE key lands here and nothing happens.
nmi_vector:
        RTI                             ; $1116  back
; $1117  26 bytes of code that nothing calls. JMP ($FFFC) and JMP ($0000),
; then a routine that zeroes $8180-$81FF and $82C0-$833F, the sprite images
; next to the ones clear_sprite_ram clears. It is likely an earlier
; clear_sprite_ram from before the images moved.

; Zero $8200-$827F and $8340-$83BF.
clear_sprite_ram:
        PHA                             ; $1131  keep A
        TXA                             ; $1132  X
        PHA                             ; $1133  keep X
        LDA #$00                        ; $1134  zero
        LDX #$7F                        ; $1136  128 bytes
clear_sprite_loop:
        STA $8200,X                     ; $1138  sprite images $08-$09
        STA $8340,X                     ; $113B  sprite images $0D-$0E
        DEX                             ; $113E  the next
        BPL clear_sprite_loop           ; $113F  more
        PLA                             ; $1141  X back
        TAX                             ; $1142  into X
        PLA                             ; $1143  A back
        RTS                             ; $1144  back
; Zero $8280-$82BF and $83C0-$83FF.
clear_upper_sprites:
        PHA                             ; $1145  keep A
        TXA                             ; $1146  X
        PHA                             ; $1147  keep X
        LDA #$00                        ; $1148  zero
        LDX #$3F                        ; $114A  64 bytes
clear_upper_loop:
        STA $8280,X                     ; $114C  sprite image $0A
        STA $83C0,X                     ; $114F  sprite image $0F
        DEX                             ; $1152  the next
        BPL clear_upper_loop            ; $1153  more
        PLA                             ; $1155  X back
        TAX                             ; $1156  into X
        PLA                             ; $1157  A back
        RTS                             ; $1158  back
; One noise byte. While $0104 is 0 the result is 1, and flicker_lamps then
; rewrites a steady row every frame. In play, $16 advances and ($16),Y is
; returned. Y belongs to the caller.
noise_byte:
        LDA $0104                       ; $1159  the demo?
        BNE noise_next                  ; $115C  no
        LDA #$01                        ; $115E  always 1 in the demo
        RTS                             ; $1160  back
noise_next:
        INC $16                         ; $1161  the next byte
        LDA ($16),Y                     ; $1163  a byte of RAM, as noise
        RTS                             ; $1165  back

; $1166  544 bytes of data, to $1385.
;   $1166  the tamper byte. spawn_yamo stores $CF79 EOR $CF99 here, and
;          score_blip moves its first trap counter only while it is 0.
;   $1167  210 low bytes and $1239 210 high bytes: where build_sprites put
;          each library's scan picture, at $9000-$9FBF or $C000-$CADF. An
;          odd library's entry is $CAE0, the scratch it is merged from, and
;          a library with no picture has a high byte of 0. overlap_actors
;          patches mask_copy_loop from these.
;   $130B  the ninja's first wake count in each room, into $5D.
;   $131F  the ninja's reload after a wake or a knockout.
;   $1333  the ninja's side byte. Only zero or not zero matters.
;   $1347  Yamo's first wake count, into $5E.
;   $135B  Yamo's reload.
;   $136F  Yamo's side byte. Bit 7 picks the alternate spawn, for both.
;          rooms.asm lists the six tables.
;   $1383  joystick 1's handedness, 1 right-handed and 0 left-handed.
;   $1384  joystick 2's handedness.
;   $1385  the S key. Nonzero skips the options tune.


; Keyboard and joystick. $DC00 is port 2, $DC01 is port 1. Either port may be read; the
; keyboard scan uses both.
init_cia:
        LDX #$FF                        ; $1386  $FF
        STX $0109                       ; $1388  no key stored
        INX                             ; $138B  0
        STX $010C                       ; $138C  no key waiting
        STX $DC02                       ; $138F  CIA 1 port A directions
        STX $DC03                       ; $1392  CIA 1 port B directions
        LDA #$7F                        ; $1395  every source off
        STA $DC0D                       ; $1397  CIA 1 interrupt control
        STA $DD0D                       ; $139A  CIA 2 interrupt control
        RTS                             ; $139D  back
; The key reader. title_loop, demo_exit_check, and in_game_key call it
; once a frame. $010C set means a fresh key is waiting in $0109 and the
; caller has not taken it yet, so nothing is read. A joystick line held low
; on either port skips the scan, since the stick shares the matrix lines.
; With the stick idle: port B drives every line low and port A is read.
; Any low line is a key, and that row mask goes to $010D. Left Shift, row 1
; bit 7, or Right Shift, row 6 bit 4, sets $010B. $010E clear runs the full
; scan_keyboard, and $010E set runs scan_stick_only, the four play keys.
; Either one leaves the code in $010A, $FF for none. The stick is read again
; after the scan, and a line that went low throws the scan away. A code that
; matches $0109 without bit 7 is the same key still held and is not stored
; again, so a key never repeats. A new code is stored with Shift in bit 7,
; and $010C is set unless the code is $FF.
read_stick:
        LDA $010C                       ; $139E  a key still waiting?
        BNE read_stick_done             ; $13A1  yes: read nothing
        LDA $DC00                       ; $13A3  both ports
        AND $DC01                       ; $13A6  CIA 1 port B: joystick 1, keyboard rows
        EOR #$FF                        ; $13A9  any line low?
        BEQ read_stick_scan             ; $13AB  no: scan
read_stick_done:
        RTS                             ; $13AD  a stick is held: no scan
read_stick_scan:
        LDX #$FF                        ; $13AE  $FF
        STX $DC03                       ; $13B0  port B drives
        STX $010A                       ; $13B3  no key yet
        INX                             ; $13B6  0
        STX $010B                       ; $13B7  no Shift yet
        STX $DC01                       ; $13BA  every line low
        LDA $DC00                       ; $13BD  any key pulls a line
        CMP #$FF                        ; $13C0  none?
        BEQ read_stick_recheck          ; $13C2  none: recheck and store $FF
        STA $010D                       ; $13C4  the lines that are low
        STX $DC03                       ; $13C7  port B reads
        DEX                             ; $13CA  $FF
        STX $DC02                       ; $13CB  port A drives
        LDA #$FD                        ; $13CE  row 1
        STA $DC00                       ; $13D0  CIA 1 port A: joystick 2, keyboard columns
        LDA $DC01                       ; $13D3  bit 7: Left Shift
        BPL read_stick_shift            ; $13D6  down
        LDA #$BF                        ; $13D8  row 6
        STA $DC00                       ; $13DA  CIA 1 port A: joystick 2, keyboard columns
        LDA $DC01                       ; $13DD  the row
        AND #$10                        ; $13E0  bit 4: Right Shift
        BNE read_stick_pick_scan        ; $13E2  up
read_stick_shift:
        INC $010B                       ; $13E4  Shift
read_stick_pick_scan:
        LDA $010E                       ; $13E7  play?
        BNE read_stick_play_keys        ; $13EA  yes: the four play keys
        JSR scan_keyboard               ; $13EC  the full matrix
        JMP read_stick_recheck          ; $13EF  the stick test
read_stick_play_keys:
        JSR scan_stick_only             ; $13F2  F1, S, Space, V
read_stick_recheck:
        LDA #$00                        ; $13F5  inputs
        STA $DC02                       ; $13F7  both ports read
        STA $DC03                       ; $13FA  CIA 1 port B directions
        LDA $DC00                       ; $13FD  both ports
        AND $DC01                       ; $1400  CIA 1 port B: joystick 1, keyboard rows
        EOR #$FF                        ; $1403  any line low?
        BEQ read_stick_store            ; $1405  no: the scan stands
        RTS                             ; $1407  a stick moved during the scan: throw it away
read_stick_store:
        LDA $0109                       ; $1408  the key stored last
        AND #$7F                        ; $140B  without Shift
        CMP $010A                       ; $140D  the same key?
        BEQ read_stick_return           ; $1410  yes: still held, no repeat
        LDA $010B                       ; $1412  Shift?
        BEQ read_stick_store_code       ; $1415  no
        LDA #$80                        ; $1417  bit 7
read_stick_store_code:
        ORA $010A                       ; $1419  with the code
        STA $0109                       ; $141C  the new key
        LDA $010A                       ; $141F  the code
        CMP #$FF                        ; $1422  none?
        BEQ read_stick_return           ; $1424  yes: nothing waiting
        LDA #$01                        ; $1426  1
        STA $010C                       ; $1428  a key is waiting
read_stick_return:
        RTS                             ; $142B  back
; The full matrix. X walks the rows from 7 down, taking the bits of $010D
; from the top. A clear bit is a row with a key. Y walks the eight columns
; of that row from 7 down. The first key found is row*8 + column, the
; usual C64 key number: F7 is 3, F1 4, F3 5, F5 6, S $0D, V $1F, Space
; $3C. The two Shift keys, $0F and $34, are skipped. No other key leaves
; X at $FF, and that is the stored code.
scan_keyboard:
        LDX #$07                        ; $142C  row 7 first
scan_keyboard_row:
        ASL $010D                       ; $142E  the row's bit
        BCC scan_keyboard_columns       ; $1431  clear: a key in this row
scan_keyboard_next_row:
        DEX                             ; $1433  the next row
        BPL scan_keyboard_row           ; $1434  more rows
        STX $010A                       ; $1436  $FF: no key
        RTS                             ; $1439  back
scan_keyboard_columns:
        LDY #$07                        ; $143A  column 7 first
scan_keyboard_column:
        LDA $1494,X                     ; $143C  this row's select
        STA $DC00                       ; $143F  CIA 1 port A: joystick 2, keyboard columns
        LDA $DC01                       ; $1442  the columns
        ORA $1494,Y                     ; $1445  everything but this column
        EOR #$FF                        ; $1448  this column low?
        BNE scan_keyboard_found         ; $144A  yes
scan_keyboard_next_column:
        DEY                             ; $144C  the next column
        BPL scan_keyboard_column        ; $144D  more columns
        BMI scan_keyboard_next_row      ; $144F  always
scan_keyboard_found:
        TYA                             ; $1451  the column
        CLC                             ; $1452  carry clear
        ADC $149C,X                     ; $1453  plus row times 8
        CMP #$0F                        ; $1456  Left Shift?
        BEQ scan_keyboard_next_column   ; $1458  skip it
        CMP #$34                        ; $145A  Right Shift?
        BEQ scan_keyboard_next_column   ; $145C  skip it
        STA $010A                       ; $145E  the key
        RTS                             ; $1461  back
; The four play keys from the table at $1488. A key counts only when its
; row reads exactly the one-key value, so a second key on the same row
; hides it. None matched stores $6F, which no caller tests. That code still
; sets $010C, so any other key is taken and ignored.
scan_stick_only:
        LDY #$00                        ; $1462  the first pair
scan_play_key:
        LDA $1488,Y                     ; $1464  the row select
        STA $DC00                       ; $1467  CIA 1 port A: joystick 2, keyboard columns
        LDA $DC01                       ; $146A  the columns
        INY                             ; $146D  the expected value
        CMP $1488,Y                     ; $146E  this key alone?
        BEQ scan_play_key_found         ; $1471  yes
        INY                             ; $1473  the next pair
        CPY #$08                        ; $1474  four pairs?
        BNE scan_play_key               ; $1476  more pairs
        LDA #$6F                        ; $1478  none
        STA $010A                       ; $147A  $6F, which nothing tests
        RTS                             ; $147D  back
scan_play_key_found:
        TYA                             ; $147E  the index past the pair
        LSR A                           ; $147F  pair number
        TAY                             ; $1480  the pair number
        LDA $1490,Y                     ; $1481  its code
        STA $010A                       ; $1484  the key
        RTS                             ; $1487  back

; $1488  28 bytes of data between routines.
; scan_stick_only tests four pairs. A pair is a $DC00 row mask and the
; $DC01 value that one key alone produces. $1490 holds the code, in the
; same order. in_game_key sets $010E, so play reads this list.
;   $1488 FE EF   F1      code $04
;   $148A FD DF   S       code $0D
;   $148C 7F EF   Space   code $3C
;   $148E F7 7F   V       code $1F
; $1494 is FE FD FB F7 EF DF BF 7F. scan_keyboard uses those bytes as the
; row select and, again, as the column mask. $149C is 00 08 10 18 20 28
; 30 38, added to the column index. That full scan is what the options
; page uses, and F1, S, Space, and V come out as the same four codes.

; between_rooms points the raster here, at line $63. It waits until $6E, then
; walks $D022 through dark grey $B, grey $C, light grey $F, white $1, and
; back down. That is the band across the PLAYER glyphs. Each raster_wait is
; about one scanline. $48 counts down once per frame.
between_raster:
        LDX #$6D                        ; $14A4  line $6D
        LDA #$6E                        ; $14A6  line $6E
between_raster_wait:
        CMP $D012                       ; $14A8  raster line
        BEQ between_raster_band         ; $14AB  $6E reached
        CPX $D012                       ; $14AD  raster line
        BNE between_raster_wait         ; $14B0  neither yet: wait
        LDX #$0A                        ; $14B2  a short delay
between_raster_delay:
        DEX                             ; $14B4  count down
        BNE between_raster_delay        ; $14B5  more
between_raster_band:
        LDA #$FB                        ; $14B7  dark grey
        STA $D022                       ; $14B9  background multicolor 1
        JSR raster_wait                 ; $14BC  hold it
        JSR raster_wait                 ; $14BF  hold it
        LDA #$FC                        ; $14C2  grey
        STA $D022                       ; $14C4  background multicolor 1
        JSR raster_wait                 ; $14C7  hold it
        JSR raster_wait                 ; $14CA  hold it
        LDA #$FF                        ; $14CD  light grey
        STA $D022                       ; $14CF  background multicolor 1
        JSR raster_wait                 ; $14D2  hold it
        JSR raster_wait                 ; $14D5  hold it
        LDA #$F1                        ; $14D8  white
        STA $D022                       ; $14DA  background multicolor 1
        JSR raster_wait                 ; $14DD  hold it
        LDA #$FF                        ; $14E0  light grey again
        STA $D022                       ; $14E2  background multicolor 1
        JSR raster_wait                 ; $14E5  hold it
        JSR raster_wait                 ; $14E8  hold it
        LDA #$FC                        ; $14EB  grey again
        STA $D022                       ; $14ED  background multicolor 1
        JSR raster_wait                 ; $14F0  hold it
        JSR raster_wait                 ; $14F3  hold it
        LDA #$FB                        ; $14F6  dark grey again
        STA $D022                       ; $14F8  background multicolor 1
        LDA #$30                        ; $14FB  screen $8C00, charset $8000
        STA $D018                       ; $14FD  screen and charset address
        LDA #$18                        ; $1500  multicolor on, no scroll
        STA $D016                       ; $1502  VIC control: xscroll, multicolor
        LDA #$01                        ; $1505  the raster interrupt
        STA $D01A                       ; $1507  VIC interrupt enable
        STA $D019                       ; $150A  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $150D  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1510  raster bit 8 clear
        STA $D011                       ; $1512  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$63                        ; $1515  line $63 again
        STA $D012                       ; $1517  raster line
        LDA $48                         ; $151A  the frame count
        BEQ between_raster_done         ; $151C  already 0
        DEC $48                         ; $151E  one less
between_raster_done:
        PLA                             ; $1520  Y back
        TAY                             ; $1521  into Y
        PLA                             ; $1522  X back
        TAX                             ; $1523  into X
        PLA                             ; $1524  A back
        RTI                             ; $1525  back

; Burn about ten iterations. The between-lives flash pauses on each $D022 color.
raster_wait:
        LDX #$0A                        ; $1526  ten loops
raster_wait_loop:
        DEX                             ; $1528  count down
        BNE raster_wait_loop            ; $1529  more
        RTS                             ; $152B  back

; Options page and game over both point here. From raster $FD, charset $8000
; and multicolor stay on through the logo, rows 0-9. Raster $82 is the top of
; row 10, where options_late takes over. On the logo, color RAM is $0F:
; pair 00 is $D021 blue, 01 and 10 are $D022/$D023 light grey, 11 would be
; yellow. The logo glyphs use 00 and 01. $48, and $49/$4A, count down here.
options_raster:
game_over_raster:
        LDA $48                         ; $152C  the frame count
        BEQ options_raster_timeout      ; $152E  already 0
        DEC $48                         ; $1530  one less
options_raster_timeout:
        LDA $49                         ; $1532  the timeout, low
        BEQ options_raster_split        ; $1534  0: leave it
        DEC $49                         ; $1536  one less
        BNE options_raster_split        ; $1538  not 0 yet
        LDA $4A                         ; $153A  the timeout, high
        BEQ options_raster_split        ; $153C  0: leave it
        DEC $4A                         ; $153E  one less
        DEC $49                         ; $1540  the low byte wraps to $FF
options_raster_split:
        LDA #$30                        ; $1542  screen $8C00, charset $8000
        STA $D018                       ; $1544  screen and charset address
        LDA #$18                        ; $1547  multicolor on, no scroll
        STA $D016                       ; $1549  VIC control: xscroll, multicolor
; The tune advances here, once per raster. Play does not install this
; raster and the effect voices together.
        JSR service_tune                ; $154C  the tune
        LDA #$74                        ; $154F  options_late, low
        STA $0408                       ; $1551  the vector at $0408
        LDA #$15                        ; $1554  high
        STA $0409                       ; $1556  the vector
        LDA #$01                        ; $1559  the raster interrupt
        STA $D01A                       ; $155B  VIC interrupt enable
        STA $D019                       ; $155E  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $1561  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1564  raster bit 8 clear
        STA $D011                       ; $1566  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$82                        ; $1569  line $82
        STA $D012                       ; $156B  raster line
        PLA                             ; $156E  Y back
        TAY                             ; $156F  into Y
        PLA                             ; $1570  X back
        TAX                             ; $1571  into X
        PLA                             ; $1572  A back
        RTI                             ; $1573  back

; Raster $82. Charset $8800 is the score font, copied from the character ROM
; with the inverse $40 codes higher. $D016 drops to $16: multicolor off,
; xscroll 6. Rows 10-24 are hires, white ink on the blue background, and bit
; 6 of a code is the highlighted glyph. The vector returns to options_raster
; at raster $FD.
options_late:
game_over_late:
        LDX #$04                        ; $1574  a few cycles
options_late_delay:
        DEX                             ; $1576  count down
        BNE options_late_delay          ; $1577  more
        LDA #$32                        ; $1579  screen $8C00, charset $8800
        STA $D018                       ; $157B  screen and charset address
        LDA #$16                        ; $157E  multicolor off, xscroll 6
        STA $D016                       ; $1580  VIC control: xscroll, multicolor
        LDA #$2C                        ; $1583  options_raster, low
        STA $0408                       ; $1585  the vector at $0408
        LDA #$15                        ; $1588  high
        STA $0409                       ; $158A  the vector
        LDA #$01                        ; $158D  the raster interrupt
        STA $D01A                       ; $158F  VIC interrupt enable
        STA $D019                       ; $1592  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $1595  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1598  raster bit 8 clear
        STA $D011                       ; $159A  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FD                        ; $159D  line $FD
        STA $D012                       ; $159F  raster line
        PLA                             ; $15A2  Y back
        TAY                             ; $15A3  into Y
        PLA                             ; $15A4  X back
        TAX                             ; $15A5  into X
        PLA                             ; $15A6  A back
        RTI                             ; $15A7  back

; raster_irq calls this once per frame, from the interrupt at raster $FB.
; The color splits do not call it, so $48 loses one count per frame. frame
; waits until that count is 0.
; While $82 is negative, the twelve band colors copied to $0153 are replaced
; from the table at $47B4: (byte EOR $83) AND $84. $84 is $F7, which clears
; bit 3 of the color. $83 is the slow counter in $80. flicker_lamps is the
; routine that rewrites the lamp glyph bytes.
; In play, the stick nibble is stored at $98 and the fire button at $9B.
; $9B is 0 while fire is held.
; voice_1, voice_2, and voice_3 advance here, once per raster.
; service_tune is not called from play.
irq_service:
        CLD                             ; $15A8  binary arithmetic
        LDA #$00                        ; $15A9  zero
        STA $44                         ; $15AB  $44
        LDX $29                         ; $15AD  the room
        JSR voice_1                     ; $15AF  effect voice 1
        JSR voice_2                     ; $15B2  effect voice 2
        JSR voice_3                     ; $15B5  effect voice 3
        INC $16                         ; $15B8  the noise pointer moves on every interrupt
        JSR place_sprites               ; $15BA  the sprites
        LDA $4EEC                       ; $15BD  the landing reload count
        BNE irq_check_charset           ; $15C0  not 0 yet
        LDA #$02                        ; $15C2  two landings
        STA $4F45                       ; $15C4  for Bruce
        STA $4F46                       ; $15C7  for Yamo
        STA $4F47                       ; $15CA  for the ninja
irq_check_charset:
        DEC $4EEC                       ; $15CD  once every 256 interrupts
        LDA $F2                         ; $15D0  the room's charset
        CMP #$38                        ; $15D2  $A000?
        BNE irq_charset_a800            ; $15D4  no
        LDA #$A0                        ; $15D6  page $A0
        BNE irq_store_charset           ; $15D8  always
irq_charset_a800:
        CMP #$3A                        ; $15DA  $A800?
        BNE irq_charset_b000            ; $15DC  no
        LDA #$A8                        ; $15DE  page $A8
        BNE irq_store_charset           ; $15E0  always
irq_charset_b000:
        CMP #$3C                        ; $15E2  $B000?
        BNE irq_charset_b800            ; $15E4  no
        LDA #$B0                        ; $15E6  page $B0
        BNE irq_store_charset           ; $15E8  always
irq_charset_b800:
        LDA #$B8                        ; $15EA  page $B8
irq_store_charset:
        STA $7C                         ; $15EC  the charset page the scan reads
; $1383 = 0 prints L at row 1 column 2. Right-handed clears it. The second L,
; at $8C4D, is drawn only in two-player or opponent mode, from $1384.
        LDA $1383                       ; $15EE  joystick 1's handedness
        BEQ irq_hand1_mark              ; $15F1  left: the mark
        LDA #$00                        ; $15F3  blank
        BEQ irq_store_hand1             ; $15F5  always
irq_hand1_mark:
        LDA #$2C                        ; $15F7  L
irq_store_hand1:
        STA $8C2A                       ; $15F9  row 1 column 2
        LDA $42CA                       ; $15FC  a second player?
        BNE irq_hand2                   ; $15FF  yes
        LDA $42C9                       ; $1601  two players?
        BEQ irq_store_hand2             ; $1604  no: blank
irq_hand2:
        LDA $1384                       ; $1606  joystick 2's handedness
        BEQ irq_hand2_mark              ; $1609  left: the mark
        LDA #$00                        ; $160B  blank
        BEQ irq_store_hand2             ; $160D  always
irq_hand2_mark:
        LDA #$2C                        ; $160F  L
irq_store_hand2:
        STA $8C4D                       ; $1611  row 1 column 37
; One raster of the visit clock. $0104 clear is the demo, and a negative
; $0105 is the pause, so neither one advances it. Space toggles that flag
; from in_game_key. The idle count below sets it when $82 wraps negative.
; $88 stops when its own sign bit is set, at $80. That is 128 wraps,
; 32768 rasters.
count_visit:
        LDA $0104                       ; $1614  the demo?
        BEQ count_idle                  ; $1617  yes: no visit clock
        LDA $0105                       ; $1619  paused?
        BMI count_idle                  ; $161C  yes: no visit clock
        INC $87                         ; $161E  the visit clock, low
        BNE count_idle                  ; $1620  no wrap
        LDA $88                         ; $1622  the visit clock, high
        BMI count_idle                  ; $1624  stops at $80
        INC $88                         ; $1626  one more wrap
count_idle:
        INC $7F                         ; $1628  the idle count, low
        BNE count_band_mask             ; $162A  no wrap
        LDA $82                         ; $162C  the idle count, high
        BMI count_slow                  ; $162E  already paused for idle
        INC $82                         ; $1630  one more wrap
        BPL count_slow                  ; $1632  not yet 128 wraps
; Idle pause. $86 sets the sign bit and the three-frame lockout in bits 1-2.
; enter_pause forces the player word on and prints "** PAUSED **".
        LDA #$86                        ; $1634  paused, with the lockout
        STA $0105                       ; $1636  the pause flag
        JSR enter_pause                 ; $1639  show the pause
        JSR save_band_colors            ; $163C  and keep the band colors
count_slow:
        INC $80                         ; $163F  the slow counter, low
        BNE count_band_mask             ; $1641  no wrap
        INC $81                         ; $1643  high
count_band_mask:
        LDA #$FE                        ; $1645  the normal mask
        LDX #$00                        ; $1647  no EOR
        LDY $82                         ; $1649  idle pause?
        BPL count_store_mask            ; $164B  no
        STA $82                         ; $164D  held negative
        LDX $80                         ; $164F  EOR with the slow counter
        LDA #$F7                        ; $1651  bit 3 cleared
count_store_mask:
        STA $84                         ; $1653  the mask
        STX $83                         ; $1655  the EOR byte
        LDA $82                         ; $1657  idle pause?
        BPL count_timers                ; $1659  no
        LDX #$13                        ; $165B  20 bytes
count_cycle_bands:
        LDA $47B4,X                     ; $165D  a saved band color
        EOR $83                         ; $1660  EOR the counter
        AND $84                         ; $1662  AND the mask
        STA $0153,X                     ; $1664  the live band color
        DEX                             ; $1667  the next
        BPL count_cycle_bands           ; $1668  more
count_timers:
        NOP                             ; $166A  eight spare bytes
        NOP                             ; $166B  spare
        NOP                             ; $166C  spare
        NOP                             ; $166D  spare
        NOP                             ; $166E  spare
        NOP                             ; $166F  spare
        NOP                             ; $1670  spare
        NOP                             ; $1671  spare
        LDA $48                         ; $1672  the frame count
        BEQ count_timer_low             ; $1674  already 0
        DEC $48                         ; $1676  one less
count_timer_low:
        LDA $49                         ; $1678  the timeout, low
        BEQ count_timer_high            ; $167A  0: the high byte
        DEC $49                         ; $167C  one less
        JMP irq_read_sticks             ; $167E  the sticks
count_timer_high:
        LDA $4A                         ; $1681  the timeout, high
        BEQ irq_read_sticks             ; $1683  0: leave it
        DEC $4A                         ; $1685  one less
        DEC $49                         ; $1687  the low byte wraps to $FF
irq_read_sticks:
        LDA $DC02                       ; $1689  CIA 1 port A directions
        STA $2005                       ; $168C  kept
        LDA $DC03                       ; $168F  CIA 1 port B directions
        STA $2006                       ; $1692  kept
        LDA #$00                        ; $1695  every line an input
        STA $DC02                       ; $1697  CIA 1 port A directions
        STA $DC03                       ; $169A  CIA 1 port B directions
        LDA $0104                       ; $169D  the demo?
        BEQ irq_check_02                ; $16A0  yes: no sticks
; Port follows $03. Left-handed ($1383,X = 0) rotates the nibble through $4A85
; ($00, $08, $04, $0C): up becomes right, right becomes down, and so on.
; $42CA set also reads the other port into $99 and the button into $9C.
; Those are Yamo's, actor 1. actor_tick tests $98,X and the fire byte
; beside it, so his walk, climb, jump, duck, punch, and flying kick are
; the same branches Bruce takes on $98 and $9B. $9C is 0 while held.
        LDA $DC01                       ; $16A2  CIA 1 port B: joystick 1, keyboard rows
        LDX $03                         ; $16A5  the player
        BEQ irq_bruce_port              ; $16A7  player 1: port 1
        LDA $DC00                       ; $16A9  CIA 1 port A: joystick 2, keyboard columns
irq_bruce_port:
        AND #$0F                        ; $16AC  the stick nibble
        LDY $1383,X                     ; $16AE  right-handed?
        BNE irq_store_bruce_stick       ; $16B1  yes: as read
        PHA                             ; $16B3  kept
        AND #$03                        ; $16B4  up and down
        TAY                             ; $16B6  the index
        PLA                             ; $16B7  the nibble
        LSR A                           ; $16B8  shifted down
        LSR A                           ; $16B9  left and right into bits 0-1
        ORA $4A85,Y                     ; $16BA  up and down into bits 2-3
irq_store_bruce_stick:
        STA $98                         ; $16BD  Bruce's stick
        LDA $03                         ; $16BF  the player
        EOR #$01                        ; $16C1  the other port's index
        TAX                             ; $16C3  for $DC00,X
        LDA $DC00,X                     ; $16C4  CIA 1 port A: joystick 2, keyboard columns, plus X
        LSR A                           ; $16C7  the button, bit 4
        LSR A                           ; $16C8  shifted down
        LSR A                           ; $16C9  shifted down
        LSR A                           ; $16CA  shifted down
        AND #$01                        ; $16CB  0 while held
        STA $9B                         ; $16CD  Bruce's fire
        LDA $42CA                       ; $16CF  a second player?
        BEQ irq_check_02                ; $16D2  no
        LDA $03                         ; $16D4  the player
        EOR #$01                        ; $16D6  the other one
        TAX                             ; $16D8  his handedness index
        PHP                             ; $16D9  keep Z: the other player is player 1
        LDA $DC01                       ; $16DA  CIA 1 port B: joystick 1, keyboard rows
        PLP                             ; $16DD  the flags back
        BEQ irq_yamo_port               ; $16DE  player 1: port 1
        LDA $DC00                       ; $16E0  CIA 1 port A: joystick 2, keyboard columns
irq_yamo_port:
        AND #$0F                        ; $16E3  the stick nibble
        LDY $1383,X                     ; $16E5  right-handed?
        BNE irq_store_yamo_stick        ; $16E8  yes: as read
        PHA                             ; $16EA  kept
        AND #$03                        ; $16EB  up and down
        TAY                             ; $16ED  the index
        PLA                             ; $16EE  the nibble
        LSR A                           ; $16EF  shifted down
        LSR A                           ; $16F0  left and right into bits 0-1
        ORA $4A85,Y                     ; $16F1  up and down into bits 2-3
irq_store_yamo_stick:
        STA $99                         ; $16F4  Yamo's stick
        LDX $03                         ; $16F6  the player: Yamo's button is on the port at $DC00+player
        LDA $DC00,X                     ; $16F8  CIA 1 port A: joystick 2, keyboard columns, plus X
        LSR A                           ; $16FB  the button, bit 4
        LSR A                           ; $16FC  shifted down
        LSR A                           ; $16FD  shifted down
        LSR A                           ; $16FE  shifted down
        AND #$01                        ; $16FF  0 while held
        STA $9C                         ; $1701  Yamo's fire
; A tamper check. Unless $02 holds $32, every raster fills memory with
; the value in $02, a page at a time, downward from the page that value
; names. The page count is $0539, the high byte of the STA $D011 in
; attract_demo, so the loop also rewrites that instruction. The game is
; wrecked within one interrupt. $02 is $32 in every snapshot, so this never runs.
; hook_enter_5 also spins until $02 is $32.
irq_check_02:
        LDA $02                         ; $1703  the check byte
        CMP #$32                        ; $1705  $32?
        BEQ irq_restore_ddr             ; $1707  yes, always
        STA $05                         ; $1709  the page to start from
irq_wipe_memory:
        STA ($04),Y                     ; $170B  fill a page
        DEY                             ; $170D  the next byte
        BNE irq_wipe_memory             ; $170E  more
        DEC $05                         ; $1710  the page below
        DEC $0539                       ; $1712  one page fewer
        BNE irq_wipe_memory             ; $1715  more
irq_restore_ddr:
        LDA $2005                       ; $1717  the saved directions
        STA $DC02                       ; $171A  CIA 1 port A directions
        LDA $2006                       ; $171D  the saved directions
        STA $DC03                       ; $1720  CIA 1 port B directions
        LDA $0104                       ; $1723  the demo?
        BEQ idle_reset                  ; $1726  yes: no idle count
        LDA $0105                       ; $1728  paused?
        BMI opponent_idle               ; $172B  yes: the count runs on
; A direction is a clear bit, so the OR below shows one only when both
; sticks hold it. While $99 is $0F, as it is for a computer Yamo off the
; moving ladder, Bruce's stick never resets the count. Only a button does.
        LDA $98                         ; $172D  Bruce's stick
        ORA $99                         ; $172F  ORed with Yamo's
        CMP #$0F                        ; $1731  no direction?
        BNE idle_reset                  ; $1733  a direction: reset
        LDA $9B                         ; $1735  both buttons
        AND $9C                         ; $1737  0 if either is held
        BNE opponent_idle               ; $1739  both up: the count runs on
idle_reset:
        LDA #$00                        ; $173B  zero
        STA $82                         ; $173D  the idle count
opponent_idle:
        LDA $7A                         ; $173F  a room without fighters?
        BNE irq_service_done            ; $1741  yes
        LDA $0105                       ; $1743  paused?
        BMI irq_service_done            ; $1746  yes
        LDA $0104                       ; $1748  the demo?
        BEQ irq_service_done            ; $174B  yes
        LDA $42CA                       ; $174D  a second player?
        BEQ irq_service_done            ; $1750  no
        LDA $99                         ; $1752  his stick
        CMP #$0F                        ; $1754  none?
        BNE opponent_idle_reset         ; $1756  moved: reset
        LDA $9C                         ; $1758  his button
        BEQ opponent_idle_reset         ; $175A  held: reset
        INC $89                         ; $175C  one screen idle
        BNE irq_service_done            ; $175E  no wrap
        INC $8A                         ; $1760  one more wrap
        LDA $8A                         ; $1762  wraps
        CMP #$07                        ; $1764  seven?
        BCC irq_service_done            ; $1766  no
        LDA #$00                        ; $1768  the computer
        STA $42CA                       ; $176A  takes Yamo back
; $89 counts screens while $99 is $0F and $9C is up. $8A counts the
; wraps. Seven of them is about 36 seconds. A direction or a held button
; clears both at opponent_idle_reset. $42CA is cleared for the rest of this game, so
; enemy_turn takes Yamo back and later wake counts use the room table.
; $42CC is left set. The next options page still shows OPPONENT, and the
; next game from that page gives him back. Effect $8A plays. Five falls
; come off $28 and off $439F, the other player's stock, clamped at 0.
; $88 becomes $20, which test_visit treats as a long visit. Yamo has no
; fall counter of his own. The five falls are Bruce's.
        LDA #$20                        ; $176D  a long visit
        STA $88                         ; $176F  on the next test
        JSR play_sound_8a               ; $1771  effect $8A
        LDA $28                         ; $1774  falls
        CMP #$05                        ; $1776  below 5?
        BCC opponent_falls_zero         ; $1778  yes
        SBC #$05                        ; $177A  five fewer. Carry is set
        JMP opponent_store_falls        ; $177C  store
opponent_falls_zero:
        LDA #$00                        ; $177F  none
opponent_store_falls:
        STA $28                         ; $1781  falls
        LDA $439F                       ; $1783  the other player's falls
        CMP #$05                        ; $1786  below 5?
        BCC opponent_other_zero         ; $1788  yes
        SBC #$05                        ; $178A  five fewer. Carry is set
        JMP opponent_store_other        ; $178C  store
opponent_other_zero:
        LDA #$00                        ; $178F  none
opponent_store_other:
        STA $439F                       ; $1791  the other player's falls
        JSR lives_to_bcd                ; $1794  the falls count
opponent_idle_reset:
        LDA #$00                        ; $1797  zero
        STA $89                         ; $1799  the idle screens
        STA $8A                         ; $179B  and the wraps
irq_service_done:
        RTS                             ; $179D  back


; For each active actor, release the pose hold and then choose the picture. X = 0 is Bruce.
step_actors:
        JSR enemy_turn                  ; $179E  the computer's choices
; $0104 clear is the attract demo. Bruce's stick and button come from
; ($1D), one byte a frame from $F300, in place of what irq_service read.
        LDA $0104                       ; $17A1  the demo?
        BNE step_actors_loop_start      ; $17A4  no
        LDY #$00                        ; $17A6  Y stays 0
        LDA ($1D),Y                     ; $17A8  the demo byte
        AND #$0F                        ; $17AA  the stick nibble
        STA $98                         ; $17AC  Bruce's stick
        LDA ($1D),Y                     ; $17AE  the demo byte again
        LSR A                           ; $17B0  shifted down
        LSR A                           ; $17B1  shifted down
        LSR A                           ; $17B2  the high nibble
        LSR A                           ; $17B3  the high nibble
        STA $9B                         ; $17B4  Bruce's fire
        INC $1D                         ; $17B6  the next byte
        BNE step_actors_loop_start      ; $17B8  no carry
        INC $1E                         ; $17BA  carry into the high byte
step_actors_loop_start:
        LDX #$02                        ; $17BC  the ninja first
step_actors_loop:
        LDA active,X                    ; $17BE  active
        AND #$01                        ; $17C0  in the room?
        BEQ step_actors_next            ; $17C2  no
; Room 19, the treasure room. The stick irq_service just stored is thrown
; away. $88 below 2 writes $0E, up. With the ladder bit clear that is the
; standing jump, state 5, so he leaves the ledge and lands, then jumps
; again. $88 at 2 or more writes $0F, no direction, and he stands where he
; landed. $9B, the fire button, is not stored over. $88 reaches 2 after
; 512 rasters, two wraps of $87, and the congratulations timer at $49/$4A
; is 1112 rasters, so the jump ends while the line is still up. The store
; is $98, not $98,X, so only Bruce is replaced. The other fighters keep
; the stick enemy_turn gave them.
treasure_stick:
        LDA $29                         ; $17C4  the room
        CMP #$13                        ; $17C6  the treasure room?
        BNE release_actor               ; $17C8  no
        LDA $88                         ; $17CA  the treasure count
        CMP #$02                        ; $17CC  2 or more?
        BCS treasure_idle               ; $17CE  yes: stand
        LDA #$0E                        ; $17D0  up
        BNE treasure_store              ; $17D2  always
; $88 is 2 or more: no direction.
treasure_idle:
        LDA #$0F                        ; $17D4  no direction
; A is the stick for Bruce: $0E up during the first 512 rasters, then $0F.
treasure_store:
        STA $98                         ; $17D6  Bruce's stick only
; Every room. The hold, then the picture, for actor X.
release_actor:
        JSR release_hold                ; $17D8  the hold, then the move
        JSR choose_pose                 ; $17DB  his picture
step_actors_next:
        DEX                             ; $17DE  the next actor
        BPL step_actors_loop            ; $17DF  more
        RTS                             ; $17E1  back
; A selects a string from the table at $43BE. X is the row passed to
; point_at_row. Y is the column. Copies until the $A0 terminator. The plain
; byte goes to ($04), the same byte with bit 7 set goes to ($08).
; Subtracting $20 from the stored bytes is what makes them screen codes
; in the score font: glyph 0 is a space, $0A is a star, and $21 is A.
print_string:
        PHA                             ; $17E2  keep the string number
        JSR point_at_row                ; $17E3  ($04) and ($08) on row X
        PLA                             ; $17E6  the string number
        ASL A                           ; $17E7  times 2
        TAX                             ; $17E8  the index
        STY $06                         ; $17E9  the column
        LDA $43BE,X                     ; $17EB  the string, low
        SEC                             ; $17EE  the borrow
        SBC $06                         ; $17EF  less the column, so ($06),Y starts at the string
        STA $06                         ; $17F1  pointer
        LDA $43BF,X                     ; $17F3  high
        SBC #$00                        ; $17F6  the borrow
        STA $07                         ; $17F8  pointer
print_string_loop:
        LDA ($06),Y                     ; $17FA  a character
        SEC                             ; $17FC  the borrow
        SBC #$20                        ; $17FD  to a screen code
        CMP #$80                        ; $17FF  the terminator, $A0, gives $80
        BEQ print_string_done           ; $1801  the end
        AND #$7F                        ; $1803  the plain glyph
        STA ($04),Y                     ; $1805  on the row
        ORA #$80                        ; $1807  the inverse glyph
        STA ($08),Y                     ; $1809  on the second screen
        INY                             ; $180B  the next character
        BNE print_string_loop           ; $180C  no page crossing
        INC $05                         ; $180E  the next page
        INC $07                         ; $1810  for all three
        INC $09                         ; $1812  pointers
        JMP print_string_loop           ; $1814  the next character
print_string_done:
        RTS                             ; $1817  back
; Silence the SID. If $0104 is 0, the attract demo, spend nothing: $09BB = 0
; makes the options tune start at once, and open_room is the options page.
; Otherwise one fall is spent. A result with the sign bit clear, including 0,
; shows the PLAYER page and comes back to $29. A negative result is game over.
lose_life:
        JSR silence_sid                 ; $1818  the effect voices
        LDA $0104                       ; $181B  the demo?
        BNE spend_fall                  ; $181E  no: a fall
        STA $09BB                       ; $1820  0: the tune starts at once
        JMP open_room                   ; $1823  the options page
; One fall. The trainer's first question stores $A5 here, so this becomes LDA $28
; and the count never moves. The same byte is stored over the INC at $2FE5 and
; $3155. The frozen value is the one clear_work_ram wrote, 4 or 9, so the line
; stays on that full count. LDA of either is positive, so BMI never fires and
; the PLAYER page still runs. Game over does not.
spend_fall:
        DEC $28                         ; $1826  one fall
        BMI game_over                   ; $1828  none left: game over
; spend_fall already counted. Zero stays here. Two-player mode swaps the
; saved block at $439F before the next room. That block is $28 through $43,
; so it holds the falls and the score. The two extra-fall marks at $4392
; and $4395 are swapped after it. The room that opens is still $29.
between_lives:
        LDA #$24                        ; $182A  36
        STA $D1                         ; $182C  Bruce, Yamo, and the ninja. The caps apply again at the next wake.
        STA $D2                         ; $182E  Yamo's health
        STA $D3                         ; $1830  the ninja's health
        LDA #$00                        ; $1832  zero
        STA $8B                         ; $1834  no saved place for Yamo
        STA $8C                         ; $1836  nor the ninja
        JSR blank_sparks                ; $1838  room 18's sparks off
        LDA $42C9                       ; $183B  two players?
        BEQ between_lives_page          ; $183E  no
        LDA $439F                       ; $1840  the other player's falls
        BMI between_lives_page          ; $1843  out: he does not play
        LDA $03                         ; $1845  the player
        EOR #$01                        ; $1847  the other one
        STA $03                         ; $1849  plays next
between_lives_page:
        JSR between_rooms               ; $184B  the PLAYER page
        LDA $D011                       ; $184E  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $1851  screen off
        STA $D011                       ; $1853  VIC control: yscroll, 25 rows, raster bit 8
        LDA $42C9                       ; $1856  two players?
        BEQ between_lives_enter         ; $1859  no
        LDA $439F                       ; $185B  the other player's falls
        BMI between_lives_enter         ; $185E  out: no swap
        LDX #$1B                        ; $1860  28 bytes
between_lives_swap_block:
        LDA $28,X                       ; $1862  this player's byte
        LDY $439F,X                     ; $1864  the other's
        STA $439F,X                     ; $1867  saved
        TYA                             ; $186A  the other's
        STA $28,X                       ; $186B  live
        DEX                             ; $186D  the next
        BPL between_lives_swap_block    ; $186E  more
        JSR swap_waiting_lamps          ; $1870  the lamp flags too
        LDX #$02                        ; $1873  three bytes
between_lives_swap_marks:
        LDA $4392,X                     ; $1875  this player's mark
        PHA                             ; $1878  kept
        LDA $4395,X                     ; $1879  the other's
        STA $4392,X                     ; $187C  live
        PLA                             ; $187F  this player's
        STA $4395,X                     ; $1880  saved
        DEX                             ; $1883  the next
        BPL between_lives_swap_marks    ; $1884  more
between_lives_enter:
        JSR init_hardware               ; $1886  the VIC, the CIAs, the vectors
        LDX $29                         ; $1889  the room
        JMP enter_room_at               ; $188B  enter it at its spawn
; $28 went negative, which is the fall after FALLS 00. Blue border and
; background ($D020/$D021 = $06). $D022 and $D023 stay $0F, so the multicolor
; ink is flat light grey. game_over_raster keeps charset $8000 through row 9
; and the score font from row 10, the same split as the options page.
; Rows 1-2, column 11: the two GAME OVER rows at $42CD and $42DF, bit 7 set.
; Each letter is a 2x2 glyph. The $5C pair is the gap. Rows 5-6, column 12:
; the PLAYER lines, the same glyphs between_rooms puts on rows 7-8. Rows 8-9,
; column 14: the low six score digits, one 2x2 block each. Glyph $DC is empty,
; so the rest of the blue field shows $D021. The lower rows were cleared to
; code 0, and glyph 0 of the score font is empty too.
; $48 counts down once a frame. $FE is 254 frames, then $40 is 64 more, 318
; in all. Nothing reads the keyboard during either wait. One player, or a
; partner whose own $28 is already negative, then enters open_room. That is
; the options page, the PLAYER page, and clear_work_ram, which zeros $29, so
; the new game is room 0 with 4 or 9 falls and a zero score. The top score
; at $4388 is outside that clear and remains. Two players with a partner
; still in the game go to between_lives instead of the second wait.
game_over:
        JSR blank_sparks                ; $188E  room 18's sparks off
        JSR clear_playfield             ; $1891  13 rows
        SEI                             ; $1894  no interrupts
        LDA $D011                       ; $1895  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $1898  screen off
        STA $D011                       ; $189A  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $189D  none
        STA $D015                       ; $189F  sprite enable
        LDA #$2C                        ; $18A2  low byte of game_over_raster
        STA $0408                       ; $18A4  the vector at $0408
        LDA #$15                        ; $18A7  high
        STA $0409                       ; $18A9  the vector
        LDA #$01                        ; $18AC  the raster interrupt
        STA $D01A                       ; $18AE  VIC interrupt enable
        STA $D019                       ; $18B1  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $18B4  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $18B7  raster bit 8 clear
        STA $D011                       ; $18B9  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FB                        ; $18BC  line $FB
        STA $D012                       ; $18BE  raster line
        LDA #$06                        ; $18C1  blue
        STA $D020                       ; $18C3  border color
        STA $D021                       ; $18C6  background color
        LDA #$0F                        ; $18C9  light grey
        STA $D022                       ; $18CB  background multicolor 1
        STA $D023                       ; $18CE  background multicolor 2
        LDX #$08                        ; $18D1  multicolor on, no scroll
        STX $D016                       ; $18D3  VIC control: xscroll, multicolor
        JSR fill_color_ram              ; $18D6  all of color RAM
        LDX #$00                        ; $18D9  256 bytes each
; A is still $0F, so fill_color_ram left light grey. $F1 repaints from row 12
; down in white. The words are above that, on the $0F cells. $DC covers
; $8C00 and $8C90 for 256 bytes each, through row 9.
blank_over_screen:
        LDA #$F1                        ; $18DB  white, multicolor off
        STA $D9E0,X                     ; $18DD  color RAM, row 12 column 0, plus X
        STA $DAE0,X                     ; $18E0  color RAM, row 18 column 16, plus X
        LDA #$DC                        ; $18E3  a blank code
        STA $8C00,X                     ; $18E5  screen rows 0-6
        STA $8C90,X                     ; $18E8  screen rows 3-9
        INX                             ; $18EB  the next
        BNE blank_over_screen           ; $18EC  until X wraps
        LDX #$11                        ; $18EE  18 cells
; Eighteen screen codes. $8C33 is row 1 column 11, $8C5B row 2 column 11.
paint_over_word:
        LDA $42CD,X                     ; $18F0  GAME OVER, top half
        ORA #$80                        ; $18F3  the upper half of the charset
        STA $8C33,X                     ; $18F5  row 1, from column 11
        LDA $42DF,X                     ; $18F8  bottom half
        ORA #$80                        ; $18FB  the upper half
        STA $8C5B,X                     ; $18FD  row 2, from column 11
        DEX                             ; $1900  the next
        BPL paint_over_word             ; $1901  more
        LDA $03                         ; $1903  the player
        ASL A                           ; $1905  times 2
        TAX                             ; $1906  his digit
        LDY #$00                        ; $1907  one byte
; between_rooms copies both digit bytes and advances X. DEY here runs once:
; Y is 0, then $FF, and BPL stops. Column 14 of each PLAYER line ($4A6B and
; $4A7B) takes one byte from $4A7D,X and $4A81,X. Player 0's stored line
; already says PLAYER 1, so that byte matches the glyph that is there.
poke_over_digit:
        LDA $4A7D,X                     ; $1909  the top glyph
        STA $4A6B,Y                     ; $190C  line 1, column 14
        LDA $4A81,X                     ; $190F  the bottom glyph
        STA $4A7B,Y                     ; $1912  line 2, column 14
        DEY                             ; $1915  $FF
        BPL poke_over_digit             ; $1916  stops after one
        LDX #$0F                        ; $1918  16 cells
; $8CD4 is row 5 column 12. $8CFC is row 6. Sixteen glyphs, bit 7 set.
paint_over_player:
        LDA $4A5D,X                     ; $191A  line 1
        ORA #$80                        ; $191D  the upper half
        STA $8CD4,X                     ; $191F  row 5, from column 12
        LDA $4A6D,X                     ; $1922  line 2
        ORA #$80                        ; $1925  the upper half
        STA $8CFC,X                     ; $1927  row 6, from column 12
        DEX                             ; $192A  the next
        BPL paint_over_player           ; $192B  more
        JSR stash_scores                ; $192D  the score in BCD
        LDA #$4E                        ; $1930  $4E
        STA $04                         ; $1932  top row, low
        LDA #$76                        ; $1934  $76
        STA $06                         ; $1936  bottom row, low
        LDA #$8D                        ; $1938  $8D
        STA $05                         ; $193A  top row, high
        STA $07                         ; $193C  bottom row, high
        LDY #$00                        ; $193E  column 0
        LDX #$01                        ; $1940  skip the top BCD byte
; X starts at 1, so the high BCD byte $439B is skipped. $439C-$439E are the
; low six digits. $04/$06 point at $8D4E and $8D76, row 8 and row 9, column 14.
; draw_digit advances Y once, and the caller advances it again, two columns
; per digit.
paint_over_score:
        LDA $439B,X                     ; $1942  a BCD byte
        LSR A                           ; $1945  shifted down
        LSR A                           ; $1946  shifted down
        LSR A                           ; $1947  shifted down
        LSR A                           ; $1948  the high digit
        JSR draw_digit                  ; $1949  draw it
        INY                             ; $194C  the next column
        LDA $439B,X                     ; $194D  the same byte
        AND #$0F                        ; $1950  the low digit
        JSR draw_digit                  ; $1952  draw it
        INY                             ; $1955  the next column
        INX                             ; $1956  the next byte
        CPX #$04                        ; $1957  past $439E?
        BCC paint_over_score            ; $1959  no
        JSR show_screen                 ; $195B  screen on
        NOP                             ; $195E  five spare bytes
        NOP                             ; $195F  spare
        NOP                             ; $1960  spare
        NOP                             ; $1961  spare
        NOP                             ; $1962  spare
        CLI                             ; $1963  interrupts on
        LDA #$FE                        ; $1964  254 frames
        STA $48                         ; $1966  the raster count
; $48 = $FE. game_over_raster counts it down once a frame, about five
; seconds with GAME OVER on screen. A second player with falls left goes
; on to between_lives.
wait_over_long:
        LDA $48                         ; $1968  counted down?
        BNE wait_over_long              ; $196A  no
        LDA $42C9                       ; $196C  two players?
        BEQ over_fresh_game             ; $196F  no
        LDA $439F                       ; $1971  the other player's falls
        BMI over_fresh_game             ; $1974  out
        JMP between_lives               ; $1976  his turn
; The other player is absent, or his saved falls are already negative.
over_fresh_game:
        LDA #$40                        ; $1979  64 frames
        STA $48                         ; $197B  the raster count
; $40 more frames, about 1.3 seconds, then open_room shows the options page.
wait_over_short:
        LDA $48                         ; $197D  counted down?
        BNE wait_over_short             ; $197F  no
        JMP open_room                   ; $1981  the options page
; A is one hex digit. Four screen bytes: two on the row at ($04) and two on
; the row at ($06). Nibble N starts at glyph $34+N*4, with bit 7 set, so the
; block lives in the upper half of charset $8000. The status line does not
; use these. It uses the score font at $8800.
draw_digit:
        AND #$0F                        ; $1984  the digit
        ASL A                           ; $1986  times 4
        ASL A                           ; $1987  shifted up
        ADC #$34                        ; $1988  plus $34. Carry is clear
        ORA #$80                        ; $198A  the upper half
        STA ($04),Y                     ; $198C  top left
        CLC                             ; $198E  the next glyph
        ADC #$01                        ; $198F  the next glyph
        STA ($06),Y                     ; $1991  bottom left
        CLC                             ; $1993  carry clear
        ADC #$01                        ; $1994  the next glyph
        INY                             ; $1996  the next column
        STA ($04),Y                     ; $1997  top right
        CLC                             ; $1999  carry clear
        ADC #$01                        ; $199A  the next glyph
        STA ($06),Y                     ; $199C  bottom right
        RTS                             ; $199E  back
; Shift $43BC left three places into the pair $43BB/$43BC.
scale_by_eight:
        LDA #$00                        ; $199F  zero
        STA $43BB                       ; $19A1  the high byte
        CLC                             ; $19A4  nothing in
        ROL $43BC                       ; $19A5  shift one
        ROL $43BB                       ; $19A8  into the high byte
        ROL $43BC                       ; $19AB  shift two
        ROL $43BB                       ; $19AE  into the high byte
        ROL $43BC                       ; $19B1  shift three
        ROL $43BB                       ; $19B4  into the high byte
        RTS                             ; $19B7  back
; The demo only. Joystick 1's button ($DC01 bit 4), or key code 4, which is
; F1, waits for the button to come up and six more screens, then jumps to
; start, the cold start: clear_work_ram and the options page, with the two
; options copied back. In play this returns at once.
demo_exit_check:
        LDA $0104                       ; $19B8  the demo?
        BNE demo_exit_done              ; $19BB  no: back
        LDA $DC01                       ; $19BD  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $19C0  the button, active low
        BEQ demo_exit                   ; $19C2  held: leave
        LDA #$01                        ; $19C4  the play keys
        STA $010E                       ; $19C6  only
        JSR read_stick                  ; $19C9  the key reader
        LDA $010C                       ; $19CC  a key waiting?
        BEQ demo_exit_done              ; $19CF  no
        LDA #$00                        ; $19D1  taken
        STA $010C                       ; $19D3  clear
        LDA $0109                       ; $19D6  the key
        CMP #$04                        ; $19D9  F1?
        BNE demo_exit_done              ; $19DB  no
demo_exit:
        JSR wait_button_up              ; $19DD  let the button go
        LDA #$06                        ; $19E0  six frames
        STA $48                         ; $19E2  the raster count
demo_exit_wait:
        LDA $48                         ; $19E4  counted down?
        BNE demo_exit_wait              ; $19E6  no
        JMP start                       ; $19E8  the cold start
demo_exit_done:
        RTS                             ; $19EB  back
; Bits 1-2 of $0105 are the three-frame lockout after the pause flag
; flips. Each call takes one off and keeps bit 7. While it counts, $4B
; is set to $FF.
pause_lockout:
        LDA $0105                       ; $19EC  the pause byte
        PHA                             ; $19EF  kept
        AND #$80                        ; $19F0  the pause flag alone
        STA $0105                       ; $19F2  stored
        PLA                             ; $19F5  the byte again
        AND #$06                        ; $19F6  the lockout bits
        BEQ pause_lockout_done          ; $19F8  0: done
        SEC                             ; $19FA  one less
        SBC #$01                        ; $19FB  one less
        ORA $0105                       ; $19FD  with the pause flag
        STA $0105                       ; $1A00  one frame less of lockout
        LDA #$FF                        ; $1A03  $FF
        STA $4B                         ; $1A05  while the lockout counts
pause_lockout_done:
        RTS                             ; $1A07  back
; While paused and the lockout is spent, the current player's joystick
; button ($DC01 for player 1, $DC00 for player 2) leaves the pause.
; Space, through in_game_key, also toggles it.
fire_resumes:
        LDA $0105                       ; $1A08  the pause byte
        AND #$06                        ; $1A0B  the lockout
        BNE fire_resumes_done           ; $1A0D  still counting
        LDA $0105                       ; $1A0F  paused?
        BPL fire_resumes_done           ; $1A12  no
        LDA $03                         ; $1A14  the player
        EOR #$01                        ; $1A16  the other port's index
        AND #$01                        ; $1A18  0 or 1
        TAX                             ; $1A1A  for $DC00,X
        LDA $DC00,X                     ; $1A1B  CIA 1 port A: joystick 2, keyboard columns, plus X
        AND #$10                        ; $1A1E  the button, active low
        BNE fire_resumes_done           ; $1A20  up: stay paused
; Toggle bit 7 of $0105. The $06 is a three-frame lockout, counted down by
; pause_lockout, so the pass that set the flag cannot toggle it straight back.
; Clearing the bit wipes "** PAUSED **" with string $0C and reprints TOP.
toggle_pause:
        LDA $0105                       ; $1A22  the pause byte
        EOR #$80                        ; $1A25  flip the pause
        ORA #$06                        ; $1A27  and lock it for three frames
        STA $0105                       ; $1A29  stored
        BMI enter_pause                 ; $1A2C  now paused
        JSR wipe_paused                 ; $1A2E  wipe the PAUSED line
        LDA $82                         ; $1A31  the idle count
        BPL leave_pause                 ; $1A33  not the idle pause
        JSR restore_band_colors         ; $1A35  the band colors back
leave_pause:
        LDA #$00                        ; $1A38  zero
        STA $82                         ; $1A3A  the idle count starts over
        JSR print_top_word              ; $1A3C  TOP
        JMP draw_top                    ; $1A3F  the top score, and return from there
; Enter the pause. The same $11 and timed_caption pair as init_hardware,
; so the player word is forced on and $43BD sits at $10. frame then sees
; the sign bit and skips timed_caption, and the word stays up until the
; flag clears. The next live frame decrements $10, so the visible phase
; runs on.
enter_pause:
        LDA #$11                        ; $1A42  one above $10
        STA $43BD                       ; $1A44  the caption count
        JSR timed_caption               ; $1A47  the player word, shown
        LDA #$51                        ; $1A4A  positive
        STA $82                         ; $1A4C  the idle count, well short of a wrap
; String $0B is "** PAUSED **", twelve codes. X = 1 is row 1, whose pointer
; is $8C28, and Y = $0F, so the line covers columns 15-26: TOP and the top
; score. FALLS, at column 28, stays. wipe_paused clears it with twelve spaces.
        JMP print_paused                ; $1A4E  the PAUSED line, and return from there
fire_resumes_done:
        RTS                             ; $1A51  back
        .byte $A2, $02, $D0, $05        ; $1A52  LDX #$02 / BNE +5, not reached

; Clear 13 character rows, using the pointers built at startup.
clear_playfield:
        LDX #$00                        ; $1A56  row 0
        STX $0100                       ; $1A58  color RAM kept off
clear_playfield_loop:
        JSR point_at_row                ; $1A5B  the row's pointers
        JSR clear_row                   ; $1A5E  clear it
        INX                             ; $1A61  the next row
        CPX #$0D                        ; $1A62  13 rows?
        BCC clear_playfield_loop        ; $1A64  no
        RTS                             ; $1A66  back
; X is a row number. ($04) and ($08) become that row's two pointers. If $0100 is set, ($08)
; is forced to $CE00.
point_at_row:
        LDA $4338,X                     ; $1A67  the row, low
        STA $04                         ; $1A6A  screen pointer
        LDA $434C,X                     ; $1A6C  high
        STA $05                         ; $1A6F  screen pointer
        LDA $4360,X                     ; $1A71  the second row, low
        STA $08                         ; $1A74  second pointer
        LDA $4374,X                     ; $1A76  high
        STA $09                         ; $1A79  second pointer
        LDA $0100                       ; $1A7B  keep the colors?
        BNE point_at_scratch            ; $1A7E  yes: aim ($08) away
        RTS                             ; $1A80  back
point_at_scratch:
        LDA #$00                        ; $1A81  $00
        STA $08                         ; $1A83  low
        LDA #$CE                        ; $1A85  $CE00, a scratch page
        STA $09                         ; $1A87  high
        RTS                             ; $1A89  back
; Write 40 zero bytes through ($04) and ($08).
clear_row:
        LDY #$27                        ; $1A8A  40 cells
        LDA #$00                        ; $1A8C  zero
clear_row_loop:
        STA ($04),Y                     ; $1A8E  the first row
        STA ($08),Y                     ; $1A90  the second
        DEY                             ; $1A92  the next
        BPL clear_row_loop              ; $1A93  more
        RTS                             ; $1A95  back
; $43BD counts down once per logic frame. The two prints share column $2C
; and X = 0. point_at_row then uses the row-0 pointer init_hardware left at
; $8C00, so $8C00+$2C is $8C2C: character row 1, column 4.
; At $10 the string is $03 plus 1. $03 is the player, so player 0 prints
; string 1 ("1UP", $448C) and player 1 prints string 2 ("2UP", $4490).
; At 0, string 0 ($4488, three spaces) clears those cells and $43BD is
; reloaded with $20. The word therefore shows while the count sits in
; $01-$10 and is blank while it sits in $11-$20, sixteen logic frames each.
; Glyph 0 is empty, so the off phase is the grey of $D021. The score digits
; start at column 8 and are not touched.
timed_caption:
        DEC $43BD                       ; $1A96  the caption count
        BNE timed_caption_check         ; $1A99  not 0
        LDA #$20                        ; $1A9B  32
        STA $43BD                       ; $1A9D  starts over
        LDA #$00                        ; $1AA0  string 0, spaces
        TAX                             ; $1AA2  row 0
        LDY #$2C                        ; $1AA3  column $2C
        JMP print_string                ; $1AA5  clear the word, and return from there
timed_caption_check:
        LDA $43BD                       ; $1AA8  the count
        CMP #$10                        ; $1AAB  $10?
        BNE timed_caption_done          ; $1AAD  no
        LDX $03                         ; $1AAF  the player
        INX                             ; $1AB1  plus one
        TXA                             ; $1AB2  the string, 1UP or 2UP
        LDX #$00                        ; $1AB3  row 0
        LDY #$2C                        ; $1AB5  column $2C
        JMP print_string                ; $1AB7  print it, and return from there
timed_caption_done:
        RTS                             ; $1ABA  back
; String 3, "TOP", on row 1 at column 16, colors kept. Leaving the
; pause and init_hardware both call it.
print_top_word:
        LDA #$03                        ; $1ABB  TOP
        STA $0100                       ; $1ABD  keeps the colors
        LDX #$00                        ; $1AC0  row 0
        LDY #$38                        ; $1AC2  column $38
        JMP print_keep_color            ; $1AC4  print it, and return from there
; String 5, "FALLS", on row 1 at column 28. init_hardware only.
print_falls_word:
        LDA #$05                        ; $1AC7  FALLS
        LDX #$00                        ; $1AC9  row 0
        LDY #$44                        ; $1ACB  column $44
        JMP print_string                ; $1ACD  print it, and return from there

; $1AD0  29 bytes of code that nothing calls: an RTS, then a debug readout.
; It draws $E6 and $E9 (Bruce's column and row in the overlap scan), then
; $5A and $5B, as two hex digits each with draw_bcd_digits, at $8C43,
; $8C45, $8C47, and $8C4E on character row 1. Nothing in the game reaches
; it, so the numbers never show. It looks like a developer's aid for
; tuning collision.

; Divide the life counter $28 by ten. Four ASLs put the tens in the high
; nibble and the remainder stays in the low nibble, then draw_bcd_digits
; draws both. A tens nibble of 10 or more is a letter, so 100 draws as A0
; and 159 draws as F9. Sixteen tens shift out of the nibble, so 160 draws
; as 00 while $28 is still 160. The byte itself wraps on the next INC
; after 255.
lives_to_bcd:
        LDA #$00                        ; $1AED  zero
        STA $439B                       ; $1AEF  the tens
        LDA $28                         ; $1AF2  falls
        STA $4398                       ; $1AF4  the remainder so far
lives_tens_loop:
        SEC                             ; $1AF7  subtract
        SBC #$0A                        ; $1AF8  ten
        BCC lives_units                 ; $1AFA  below: the units
        INC $439B                       ; $1AFC  one more ten
        JMP lives_tens_loop             ; $1AFF  again
lives_units:
        CLC                             ; $1B02  add
        ADC #$0A                        ; $1B03  the ten back
        STA $4398                       ; $1B05  the units
        LDA $439B                       ; $1B08  the tens
        ASL A                           ; $1B0B  shifted up
        ASL A                           ; $1B0C  shifted up
        ASL A                           ; $1B0D  shifted up
        ASL A                           ; $1B0E  into the high nibble
        ORA $4398                       ; $1B0F  with the units
        LDY #$4A                        ; $1B12  column $4A
        JMP draw_bcd_digits             ; $1B14  draw them, and return from there
; Draw both nibbles of A at screen column Y. The callers pass $3C, $3E,
; $40, and $4A. Each of those is past the 40 cells of row 0, so the digits
; land on row 1 ($8C28), on the grey $D021 bar between the two black rows.
draw_split_digits:
        PHA                             ; $1B17  kept
        JSR high_nibble                 ; $1B18  the high digit
        ORA #$10                        ; $1B1B  the digit glyph
        STA $8C00,Y                     ; $1B1D  the first cell
        PLA                             ; $1B20  the byte again
        AND #$0F                        ; $1B21  the low digit
        ORA #$10                        ; $1B23  the digit glyph
        STA $8C01,Y                     ; $1B25  the next cell
        RTS                             ; $1B28  back
; Keys during play, the four codes from scan_stick_only. Bit 7 is Shift
; and is masked off, so a shifted key still matches.
; $04 is F1, and jumps back to the cold start.
; $0D is S. It toggles $1385. Nonzero skips the options tune. $09BB is
; cleared, so the next options page starts the tune at once.
; $3C is Space, and toggles the $0105 pause.
; $1F is V, and toggles the credit line on row 0.
in_game_key:
        LDA #$01                        ; $1B29  the play keys
        STA $010E                       ; $1B2B  only
        JSR read_stick                  ; $1B2E  the key reader
        LDA $010C                       ; $1B31  a key waiting?
        BNE in_game_key_take            ; $1B34  yes
        RTS                             ; $1B36  back
in_game_key_take:
        LDA #$00                        ; $1B37  zero
        STA $010C                       ; $1B39  taken
        LDA $0109                       ; $1B3C  the key
        AND #$7F                        ; $1B3F  without Shift
        STA $4B                         ; $1B41  kept
        CMP #$04                        ; $1B43  F1?
        BNE in_game_key_s               ; $1B45  no
        JMP start                       ; $1B47  the cold start
in_game_key_s:
        CMP #$0D                        ; $1B4A  S?
        BNE in_game_key_space_v         ; $1B4C  no
        LDA $1385                       ; $1B4E  the S setting
        EOR #$01                        ; $1B51  flipped
        STA $1385                       ; $1B53  stored
        LDA #$00                        ; $1B56  zero
        STA $09BB                       ; $1B58  the next options page plays the tune at once
        RTS                             ; $1B5B  back
in_game_key_space_v:
        CMP #$3C                        ; $1B5C  Space?
        BEQ in_game_key_pause           ; $1B5E  yes
        CMP #$1F                        ; $1B60  V?
        BEQ toggle_credit_line          ; $1B62  yes
        RTS                             ; $1B64  back
in_game_key_pause:
        JMP toggle_pause                ; $1B65  the pause, and return from there
; V. Row 0 normally holds screen code $20, the solid black bar. The forty
; codes at $4707 replace it: "BRUCE LEE (C) 1984 DATASOFT REV.2 BY RJF".
; They are score-font codes, the same numbers print_string stores. A first
; cell that is not $20 fills the row with $20 again.
toggle_credit_line:
        LDA #$20                        ; $1B68  the solid glyph
        CMP $8C00                       ; $1B6A  row 0 is the bar?
        BNE credit_line_clear           ; $1B6D  no: put the bar back
        LDX #$27                        ; $1B6F  40 cells
credit_line_copy:
        LDA $4707,X                     ; $1B71  the credit line
        STA $8C00,X                     ; $1B74  row 0
        DEX                             ; $1B77  the next
        BPL credit_line_copy            ; $1B78  more
        RTS                             ; $1B7A  back
credit_line_clear:
        LDX #$27                        ; $1B7B  40 cells
credit_line_clear_loop:
        STA $8C00,X                     ; $1B7D  the solid glyph
        DEX                             ; $1B80  the next
        BPL credit_line_clear_loop      ; $1B81  more
        RTS                             ; $1B83  back
; Draw both digits of A at column Y. A nibble past 9 is moved seven glyphs
; on, which is A through F. lives_to_bcd is the caller that reaches those
; glyphs. The score path uses draw_split_digits, whose nibbles are real BCD.
draw_bcd_digits:
        PHA                             ; $1B84  kept
        JSR high_nibble                 ; $1B85  the high digit
        ORA #$10                        ; $1B88  the digit glyph
        CMP #$1A                        ; $1B8A  past 9?
        BCC bcd_store_high              ; $1B8C  no
        CLC                             ; $1B8E  carry clear
        ADC #$07                        ; $1B8F  seven on: A-F
bcd_store_high:
        STA $8C00,Y                     ; $1B91  the first cell
        PLA                             ; $1B94  the byte again
        AND #$0F                        ; $1B95  the low digit
        ORA #$10                        ; $1B97  the digit glyph
        CMP #$1A                        ; $1B99  past 9?
        BCC bcd_store_low               ; $1B9B  no
        CLC                             ; $1B9D  carry clear
        ADC #$07                        ; $1B9E  seven on: A-F
bcd_store_low:
        STA $8C01,Y                     ; $1BA0  the next cell
        RTS                             ; $1BA3  back
; String $0B, "** PAUSED **", on row 1 at column 15, without touching
; color RAM.
print_paused:
        LDA #$0B                        ; $1BA4  ** PAUSED **
        STA $0100                       ; $1BA6  keeps the colors
        LDX #$01                        ; $1BA9  row 1
        LDY #$0F                        ; $1BAB  column 15
; print_string with $0100 set, so point_at_row aims the color pointer at
; the scratch page $CE00 and the cells keep their colors. $0100 is
; cleared after.
print_keep_color:
        JSR print_string                ; $1BAD  print it
        LDA #$00                        ; $1BB0  zero
        STA $0100                       ; $1BB2  colors written again from now on
        RTS                             ; $1BB5  back
; String $0C, twelve spaces, over the PAUSED line.
wipe_paused:
        LDA #$0C                        ; $1BB6  twelve spaces
        STA $0100                       ; $1BB8  keeps the colors
        LDX #$01                        ; $1BBB  row 1
        LDY #$0F                        ; $1BBD  column 15
        JMP print_keep_color            ; $1BBF  print them, and return from there
; One frame. flicker_lamps runs first, then the room hook. That hook is
; where scroll_surface decrements $60, so ride_surface sees the value
; after the decrement. overlap_actors, then scan_specials, then
; read_sprite_hits, then the three actors. A blow replaces a catch
; scan_specials just stored, and ride_surface has not run yet. push_out
; is inside release_hold, so a wall bit skips the ride that frame.
; Wait until the raster count in $48 reaches 0. irq_service decrements
; $48 once per frame, from the interrupt at raster $FB.
frame:
        LDA #$03                        ; $1BC2  three interrupts
        STA $48                         ; $1BC4  the frame waits for them
        JSR demo_exit_check             ; $1BC6  the demo's F1 and fire
        LDA $0104                       ; $1BC9  a game, not the demo?
        BEQ frame_live                  ; $1BCC  the demo
        JSR in_game_key                 ; $1BCE  Space, S, V
        JSR pause_lockout               ; $1BD1  the lockout
        JSR fire_resumes                ; $1BD4  fire leaves the pause
        LDA $0105                       ; $1BD7  paused?
        BPL frame_live                  ; $1BDA  no
        JMP wait_for_tick               ; $1BDC  paused: wait out the frame
frame_live:
        LDA $D2                         ; $1BDF  bit 6 cleared
        AND #$BF                        ; $1BE1  Yamo's health, without bit 6
        STA $D2                         ; $1BE3  stored
        LDA $D3                         ; $1BE5  bits 3-6 cleared
        AND #$87                        ; $1BE7  the ninja's health, bits 0-2 and 7
        STA $D3                         ; $1BE9  stored
; Player word. Runs when $0104 is clear as well. A negative $0105 has
; already jumped to wait_for_tick, which is what holds the word during pause.
        JSR timed_caption               ; $1BEB  the player word
        JSR flicker_lamps               ; $1BEE  the lamp glyphs
        LDA $7A                         ; $1BF1  a room where nobody wakes?
        BNE frame_flip_hook_phase       ; $1BF3  yes
        JSR tick_wake_counts            ; $1BF5  the wake counts
        JSR try_yamo                    ; $1BF8  maybe Yamo
        JSR try_ninja                   ; $1BFB  maybe the ninja
; $7B flips every logic frame. The room hook sees 1 on the skipped frame
; and 0 on the frame it runs, so it advances every other tick.
frame_flip_hook_phase:
        LDA $7B                         ; $1BFE  the hook phase
        BNE frame_hook_phase_clear      ; $1C00  1: back to 0
        LDA #$01                        ; $1C02  1
        STA $7B                         ; $1C04  0: now 1
        BNE frame_run                   ; $1C06  always
frame_hook_phase_clear:
        DEC $7B                         ; $1C08  now 0
frame_run:
        JSR run_frame_hook              ; $1C0A  the room's own frame code
        JSR overlap_actors              ; $1C0D  the overlap scan for each actor
        JSR scan_specials               ; $1C10  ladders, hot tiles, lamps
        LDA $CF7A                       ; $1C13  a check byte
        EOR $CF9A                       ; $1C16  EOR its partner
        STA $2007                       ; Folded into the byte score_blip tests.
        LDX $29                         ; $1C1C  the room
        LDA $4C9E,X                     ; $1C1E  a room without fighters?
        BNE frame_actors                ; $1C21  yes: no blows
        JSR read_sprite_hits            ; $1C23  blows between sprites
frame_actors:
        JSR refresh_top                 ; $1C26  the top score
        JSR step_actors                 ; $1C29  the three actors
        JSR blit_sprites                ; $1C2C  their pictures
        JSR check_bruce_down            ; $1C2F  a knockdown ends here
; The raster interrupt decrements $48. Spin until that count is 0, then start the next
; frame.
wait_for_tick:
        LDA $48                         ; $1C32  the frame count
        BNE wait_for_tick               ; $1C34  not 0 yet
        JMP frame                       ; $1C36  the next frame
; xpos and ypos of actor X, shifted down to a character cell in $E6,X and $E9,X.
; Room $0D adds 4 to ypos before the row shift only. The edge test at $30D4
; still sees the real ypos. scan_specials uses this same pair of cells.
cell_of_actor:
        LDA xpos,X                      ; $1C39  xpos
        SEC                             ; $1C3B  the borrow
        SBC #$0C                        ; $1C3C  the box's left edge
        LSR A                           ; $1C3E  four steps a cell
        LSR A                           ; $1C3F  four steps a cell
        STA $E6,X                       ; $1C40  the cell column
        LDA $29                         ; $1C42  the room
        CMP #$0D                        ; $1C44  room 13?
        BNE cell_plain_ypos             ; $1C46  no
        LDA ypos,X                      ; $1C48  ypos
        CLC                             ; $1C4A  carry clear
        ADC #$04                        ; $1C4B  four rows lower
        BNE cell_store_row              ; $1C4D  always
cell_plain_ypos:
        LDA ypos,X                      ; $1C4F  ypos
cell_store_row:
        SEC                             ; $1C51  the borrow
        SBC #$0C                        ; $1C52  the box's top
        LSR A                           ; $1C54  halved
        LSR A                           ; $1C55  quartered
        LSR A                           ; $1C56  an eighth
        LSR A                           ; $1C57  divided by 16
        STA $E9,X                       ; $1C58  the cell row
        RTS                             ; $1C5A  back
; The pose holds for $0106,X frames. While that count is running, the rest of the actor is
; skipped. $86 starts at 8. push_out decrements it once per generation, and
; the extra step is taken only when it is no longer 7, so the first
; generation does not take it. $4A8C is the hold for the state keep_state
; is about to store. States 1 and 2 are 3, state $1A is 1, and states
; $14, $15, $16, and $18 are 0, so the chase, the sidestep, the strike,
; and the bounce are not held.
release_hold:
        LDA #$08                        ; $1C5B  the extra step's count
        STA $86                         ; $1C5D  the extra step's count
        LDA $0106,X                     ; $1C5F  the hold
        BEQ hold_done                   ; $1C62  over: the rest of the actor
        DEC $0106,X                     ; $1C64  one frame less
        RTS                             ; $1C67  and nothing more this frame
; Hold finished, or undo_steps found a generation with no up step and no
; sideways step and came back here. Any of the four current counters
; shifts forty samples, stride 3, one generation older. The current four
; are then cleared. State 0, or a state other than $C2, stores 6 in $CB.
; The same state decrements $CB when it is not already 0. $C2 then becomes
; the state. State $19 jumps into actor_tick's timer test. State $18 with
; the timer still set is while_stuck. Anything else is push_out, which
; runs before actor_tick, so a wall bit never reaches the chase or the
; ladder ride on that frame.
hold_done:
        STA $4FDB,X                     ; $1C68  A is 0 here. choose_pose may run
        LDA $4F57,X                     ; $1C6B  any step this frame?
        ORA $4F5A,X                     ; $1C6E  down
        ORA $4F5D,X                     ; $1C71  left
        ORA $4F60,X                     ; $1C74  right
        BEQ hold_clear_current          ; $1C77  none: nothing to age
        LDA #$27                        ; $1C79  40 counters
        STA $4E                         ; $1C7B  kept
        TXA                             ; $1C7D  the actor
        CLC                             ; $1C7E  carry clear
        ADC #$75                        ; $1C7F  from the oldest kept generation
        TAY                             ; $1C81  down to the current one
hold_age_history:
        LDA $4F57,Y                     ; $1C82  one counter
        STA $4F63,Y                     ; $1C85  one generation older
        DEY                             ; $1C88  three bytes back
        DEY                             ; $1C89  the same actor
        DEY                             ; $1C8A  three bytes on: the same actor
        DEC $4E                         ; $1C8B  one fewer
        BPL hold_age_history            ; $1C8D  more
hold_clear_current:
        LDA #$00                        ; $1C8F  zero
        STA $4F57,X                     ; $1C91  up, cleared
        STA $4F5A,X                     ; $1C94  down, cleared
        STA $4F5D,X                     ; $1C97  left, cleared
        STA $4F60,X                     ; $1C9A  right, cleared
        LDA state,X                     ; $1C9D  the state
        BEQ hold_reload_burst           ; $1C9F  0: a new burst
        CMP $C2,X                       ; $1CA1  the same as last frame?
        BNE hold_reload_burst           ; $1CA3  no: a new burst
        LDA $CB,X                       ; $1CA5  the burst count
        BEQ hold_store_state            ; $1CA7  0: stays 0
        DEC $CB,X                       ; $1CA9  one less
        BPL hold_store_state            ; $1CAB  always
hold_reload_burst:
        LDA #$06                        ; $1CAD  six bursts
        STA $CB,X                       ; $1CAF  shortened
hold_store_state:
        LDA state,X                     ; $1CB1  the state
        STA $C2,X                       ; $1CB3  remembered for next frame
        CMP #$19                        ; $1CB5  state $19?
        BNE hold_check_stuck            ; $1CB7  no
        JMP actor_tick_timer            ; $1CB9  straight to the timer test
hold_check_stuck:
        CMP #$18                        ; $1CBC  state $18?
        BNE push_out                    ; $1CBE  no
        LDA timer,X                     ; $1CC0  its timer
        BEQ push_out                    ; $1CC2  0: done being stuck
        JMP while_stuck                 ; $1CC4  still stuck

; Bit 3 of hit,X. The step that entered the wall has already been taken.
; move_left and move_right do not look at this bit. The previous generation
; is walked back: an up count by move_down, a down count by move_up, a
; left count by move_right, a right count by move_left. move_right stores
; facing 1 and move_left stores facing 0, so a run into a wall on his left
; leaves him facing right. That facing is what the next chase reads.
; $85 starts at 1 and is shifted on the up undo and on both sideways
; undos. A down undo does not shift it. Still 1, and $C2 not the duck,
; goes back to hold_done for the next generation. The generation just
; undone, and the empty current slot, are dropped by the slide first.
; Hit bit 2 stops the loop after this one generation. The test is the
; overlap from the start of the frame, not a new scan, so a sprite that
; also covers the purple ladder still undoes the one generation and then
; stops. It does not take the extra step. $86 is decremented after the
; slide. It is 7 after the first generation, and the extra step is
; skipped. A later generation takes one step opposite the facing the
; undo just stored. mark_stuck then stores state $18 and timer $40 and
; returns. The chase does not run on this frame.
push_out:
        LDA hit,X                       ; $1CC7  the full hit
        AND #$08                        ; Bit 3, the solid flag.
        BNE push_out_start              ; $1CCB  a wall
        JMP actor_tick                  ; $1CCD  no wall: the move
push_out_start:
        LDA #$00                        ; $1CD0  zero
        STA $C8,X                       ; $1CD2  move_up may run
; Walk the four oldest step counters back to 0, each step reversed: up is
; undone with move_down, down with move_up, left with move_right, and right
; with move_left. $85 starts at 1, and any undo except a down one clears
; it. Then 36 bytes, stride 3, are copied from $4F6F,X over $4F57,X, the
; older history over the newer. while_stuck comes back here through
; undo_again.
undo_steps:
        LDA #$01                        ; $1CD4  an up or sideways undo will clear it
        STA $85                         ; $1CD6  1 until a step that moved him is undone
undo_up:
        DEC $4F63,X                     ; $1CD8  one up step of the last generation
        BMI undo_down                   ; $1CDB  none left
        LSR $85                         ; $1CDD  a step that moved him
        JSR move_down                   ; $1CDF  back down
        JMP undo_up                     ; $1CE2  the next
undo_down:
        DEC $4F66,X                     ; $1CE5  one down step
        BMI undo_left                   ; $1CE8  none left
        JSR move_up                     ; $1CEA  back up. $85 stays
        JMP undo_down                   ; $1CED  the next
undo_left:
        DEC $4F69,X                     ; $1CF0  one left step
        BMI undo_right                  ; $1CF3  none left
        LSR $85                         ; $1CF5  a step that moved him
        JSR move_right                  ; $1CF7  back right. Facing becomes 1
        JMP undo_left                   ; $1CFA  the next
undo_right:
        DEC $4F6C,X                     ; $1CFD  one right step
        BMI undo_slide_history          ; $1D00  none left
        LSR $85                         ; $1D02  a step that moved him
        JSR move_left                   ; $1D04  back left. Facing becomes 0
        JMP undo_right                  ; $1D07  the next
undo_slide_history:
        LDA #$23                        ; $1D0A  36 counters
        STA $4E                         ; $1D0C  kept
        TXA                             ; $1D0E  the actor
        TAY                             ; $1D0F  from the actor's own column
undo_slide_loop:
        LDA $4F6F,Y                     ; $1D10  two generations older
        STA $4F57,Y                     ; $1D13  over the current one
        INY                             ; $1D16  three bytes on
        INY                             ; $1D17  the same actor
        INY                             ; $1D18  three bytes on: the same actor
        DEC $4E                         ; $1D19  one fewer
        BPL undo_slide_loop             ; $1D1B  more
        LDA #$00                        ; $1D1D  zero
        STA $0106,X                     ; $1D1F  no hold
        STA $4FC3,X                     ; $1D22  the two oldest generations, left stale by the slide
        STA $4FC6,X                     ; $1D25  the two oldest generations
        STA $4FC9,X                     ; $1D28  cleared
        STA $4FCC,X                     ; $1D2B  cleared
        STA $4FCF,X                     ; $1D2E  cleared
        STA $4FD2,X                     ; $1D31  cleared
        STA $4FD5,X                     ; $1D34  cleared
        STA $4FD8,X                     ; $1D37  cleared
        DEC $86                         ; $1D3A  the extra step's count
        BMI mark_stuck                  ; $1D3C  spent: stuck
        LDA hit,X                       ; $1D3E  the frame's hit
        AND #$04                        ; $1D40  ladder?
        BNE mark_stuck                  ; $1D42  yes: stuck after one generation
        LDA $85                         ; $1D44  still 1?
        BEQ undo_extra_step             ; $1D46  no: an up or sideways step was undone
        LDA $C2,X                       ; $1D48  last frame's state
        CMP #$1A                        ; $1D4A  the duck?
        BEQ mark_stuck                  ; $1D4C  yes: stuck
        LDA #$00                        ; $1D4E  so choose_pose may run
        JMP hold_done                   ; $1D50  and walk the next generation back
undo_extra_step:
        LDA $86                         ; $1D53  the extra step's count
        CMP #$07                        ; $1D55  the first generation?
        BEQ mark_stuck                  ; $1D57  yes: no extra step
        LDA facing,X                    ; $1D59  the facing the undo left
        BNE undo_extra_left             ; $1D5B  left
        JSR move_right                  ; $1D5D  one more step right
        JMP mark_stuck                  ; $1D60  stuck
undo_extra_left:
        JSR move_left                   ; $1D63  one more step left
; State $18, timer $40. while_stuck runs from the next frame.
mark_stuck:
        LDA #$18                        ; $1D66  pushed out
        STA state,X                     ; $1D68  pushed out
        LDA #$40                        ; $1D6A  $40
        STA timer,X                     ; $1D6C  $40 frames
        RTS                             ; $1D6E  back

; One actor, for the X register passed in. The state timer gates the scripted mover.
actor_tick:
        STA $C8,X                       ; $1D6F  A from the caller. Bit 0 set refuses move_up
        LDA #$FF                        ; $1D71  $FF
        STA $C5,X                       ; $1D73  $FF. Nothing in this listing reads $C5,X
        LDA #$00                        ; $1D75  zero
actor_tick_timer:
        LDY timer,X                     ; A timer of 0 skips the mover. The last count has already run.
        BEQ actor_tick_idle             ; $1D79  timer 0
        JMP move_for_state              ; Timer still running: perform this state's step.
actor_tick_idle:
        LDA $C2,X                       ; $1D7E  the state on the previous frame
; The remembered state is $0E, the fall. The first airborne frame is begin_fall:
; $B0,X becomes 2 and he drops one pixel. Later frames drop two. While the
; shifted $B0,X is still set and the upper body ($A7) shows ground, one xpos
; step is added toward his facing. Bits 0 or 2 of the full hit land him on
; that pixel. The upper-body test is bit 0 only. A wall whose AND has
; collapsed to nibble 1 or 4 sets that bit on every row, so the fall never
; reaches the landing test while he overlaps that column.
        CMP #$0E                        ; $1D80  falling?
        BNE on_ground                   ; $1D82  no: read the stick
        TXA                             ; $1D84  the actor
        BEQ bruce_fall                  ; $1D85  Bruce
        LDA hit,X                       ; $1D87  the full hit
        AND #$05                        ; $1D89  ground or ladder
        BEQ fall_drop                   ; $1D8B  neither: keep falling
        LDA facing,X                    ; $1D8D  his facing
        CMP #$01                        ; $1D8F  facing right?
        BNE enemy_fall_left             ; $1D91  left
        JMP move_right                  ; $1D93  landed: one step on, to the right
enemy_fall_left:
        JMP move_left                   ; $1D96  or to the left
bruce_fall:
        LDA $A7,X                       ; $1D99  the upper body's hit
        AND #$01                        ; $1D9B  ground
        BEQ bruce_fall_land_test        ; $1D9D  no: the landing test
        LSR $B0,X                       ; $1D9F  the drift count
        BEQ fall_drop                   ; $1DA1  spent: drop only
        LDA facing,X                    ; $1DA3  his facing
        BEQ bruce_fall_drift_left       ; $1DA5  left
        JSR move_right                  ; $1DA7  drift one step
        JMP fall_drop                   ; $1DAA  then drop
bruce_fall_drift_left:
        JSR move_left                   ; $1DAD  drift one step
        JMP fall_drop                   ; $1DB0  then drop
bruce_fall_land_test:
        LDA hit,X                       ; $1DB3  the full hit
        AND #$05                        ; $1DB5  ground or ladder
        BNE up_refuse_if_set            ; $1DB7  landed: two BNEs on, clear_state
fall_drop:
        JSR move_down                   ; $1DB9  the second pixel
fall_drop_one:
        JSR move_down                   ; $1DBC  one pixel
        LDA #$0E                        ; $1DBF  still the fall
        JMP set_state                   ; $1DC1  the fall
begin_fall:
        LDA #$02                        ; $1DC4  two drift steps
        STA $B0,X                       ; $1DC6  the drift count for this fall
        BNE fall_drop_one               ; $1DC8  always: one pixel

; hit,X bits 0 and 2 mean the ground is holding him. Either one cancels the fall.
; Once he is on the ground, $98,X picks the move: $0E up, $0D down, $0B left, $07 right.
; X = 1 is $99. With $42CA set that is the second joystick, and the tests
; below are Yamo's as well as Bruce's. Fire for him is $9C.
on_ground:
        LDA hit,X                       ; $1DCA  the full hit
        AND #$05                        ; Bits 0 and 2. Set means do not fall.
        BEQ begin_fall                  ; $1DCE  neither: the fall starts
        LDA $98,X                       ; $1DD0  the stick
; $0E: up. Bit 2 climbs. Two calls and the fall through into move_up are three
; pixels, and $CB,X at 0 adds a fourth. A refused pixel clears the state.
; With bit 2 clear, bit 3 refuses the standing jump, and a ypos below $2E
; clears the state. Otherwise state 5 starts, with timer 15.
; Effect $80 plays before the ladder test, whenever ypos is at least
; $2E. The standing jump chirps. A wall that refuses the jump has
; already chirped.
        CMP #$0E                        ; $0E: climb up.
        BNE stick_down                  ; $1DD4  not up
        LDA ypos,X                      ; $1DD6  ypos
        CMP #$2E                        ; $1DD8  the top?
        BCC up_refuse_or_jump           ; $1DDA  above it: refused
        JSR score_blip                  ; $1DDC  effect $80
        LDA $CB,X                       ; $1DDF  the burst count
        BNE climb_up_steps              ; $1DE1  not 0: three steps
        JSR up_step                     ; $1DE3  the fourth
climb_up_steps:
        JSR up_step                     ; $1DE6  the third
        JSR up_step                     ; $1DE9  the second
; One up step, taken only while the ladder bit is set. The climb above
; comes through here three times, or four when $CB,X is 0.
up_step:
        LDA hit,X                       ; $1DEC  the full hit
        AND #$04                        ; $1DEE  ladder?
        BEQ up_not_ladder               ; $1DF0  no: maybe the jump

; One step up. ypos decreases. State becomes 1 (climb up) until the caller stores its own
; state on top.
move_up:
        LDA ypos,X                      ; $1DF2  ypos
        CMP #$2E                        ; $1DF4  the top?
        BCC up_refuse_if_set            ; $1DF6  above it: refused
        LDA $C8,X                       ; $1DF8  the caller's byte
        AND #$01                        ; $1DFA  bit 0 refuses
up_refuse_if_set:
        BNE up_refuse_or_jump           ; $1DFC  set: refused
        DEC ypos,X                      ; $1DFE  one pixel up
        INC $4F57,X                     ; $1E00  count the up step
        LDA #$01                        ; $1E03  climb up
        JMP set_state                   ; $1E05  and return from there
up_not_ladder:
        LDA hit,X                       ; $1E08  the full hit
        AND #$08                        ; $1E0A  wall?
up_refuse_or_jump:
        BNE stop_move                   ; $1E0C  yes: refused
        LDA #$05                        ; $1E0E  the standing jump
        JMP set_state_15                ; $1E10  timer 15
stick_down:
; $0D: down. Bit 2 climbs through move_down, three pixels, or four when $CB,X
; is 0. With bit 2 clear and bit 0 set, Bruce ducks.
; Effect $80 plays on that climb, and only when ypos is below $C7.
        CMP #$0D                        ; $0D: climb down.
        BNE stick_left                  ; $1E15  not down
        LDA hit,X                       ; $1E17  the full hit
        AND #$04                        ; $1E19  ladder?
        BNE climb_down                  ; $1E1B  yes: climb
        LDA hit,X                       ; $1E1D  the full hit
        AND #$01                        ; $1E1F  ground?
        BNE duck_from_down              ; $1E21  yes: duck
climb_down:
        LDA ypos,X                      ; $1E23  ypos
        CMP #$C7                        ; $1E25  the bottom?
        BCS stop_move                   ; $1E27  at it: refused
        JSR score_blip                  ; $1E29  effect $80
        LDA $CB,X                       ; $1E2C  the burst count
        BNE climb_down_steps            ; $1E2E  not 0: three steps
        JSR move_down                   ; $1E30  the fourth
climb_down_steps:
        JSR move_down                   ; $1E33  the third
        JSR move_down                   ; $1E36  the second

; One step down, one screen pixel. State becomes 2 (climb down) until the caller
; stores its own state on top. A ypos of $C7 or more refuses the step and clears
; the state. Callers issue this once (the first fall frame, and sideways-jump
; timer 6), twice (later falls, and the standing jump's descent), or three or
; four times (the climb). ypos is therefore not kept even.
move_down:
        LDA ypos,X                      ; $1E39  ypos
        CMP #$C7                        ; $1E3B  the bottom?
        BCS stop_move                   ; $1E3D  at it: refused
        INC ypos,X                      ; $1E3F  one pixel down
        INC $4F5A,X                     ; $1E41  count the down step
        LDA #$02                        ; $1E44  climb down
        JMP set_state                   ; $1E46  and return from there
duck_from_down:
        TXA                             ; $1E49  the actor
        BEQ bruce_duck_from_down        ; $1E4A  Bruce
        JMP yamo_down                   ; $1E4C  Yamo or the ninja
bruce_duck_from_down:
        LDA facing                      ; $1E4F  Bruce's facing
        BEQ bruce_duck_down_left        ; $1E51  left
        JMP duck_right                  ; $1E53  duck facing right
bruce_duck_down_left:
        JMP duck_left                   ; $1E56  duck facing left
stick_left:
; $0B: left. Two calls and the fall through into move_left are two xpos steps.
; $CB,X at 0 adds a third. When the previous state is already 3, $CB,X is
; below 4, and $9B,X is 0, the step is the flying kick instead.
; Effect $80 plays after the edge test, including a step that then
; becomes a kick.
        CMP #$0B                        ; $0B: step left. A low pose-repeat count starts the kick.
        BNE stick_right                 ; $1E5B  not left
        LDA xpos,X                      ; $1E5D  xpos
        CMP #$0D                        ; $1E5F  the left edge?
        BCC stop_move                   ; $1E61  past it: refused
        JSR score_blip                  ; $1E63  effect $80
        LDA $CB,X                       ; $1E66  the burst count
        BNE left_two_steps              ; $1E68  not 0: two steps
        JSR left_step                   ; $1E6A  the third
; The left burst's second and third steps, without the first. The chase
; enters here, so it moves two xpos.
left_two_steps:
        JSR left_step                   ; $1E6D  the second
; One left step. A walk that was already going left with fire held
; early in the burst ($CB,X under 4) turns into the flying kick instead.
left_step:
        LDA $C2,X                       ; $1E70  the state on the previous frame
        CMP #$03                        ; $1E72  already walking left?
        BNE move_left                   ; $1E74  no: a step
        LDA $CB,X                       ; $1E76  the burst count
        CMP #$04                        ; $1E78  4 or more?
        BCS move_left                   ; $1E7A  yes: a step
        LDA $9B,X                       ; $1E7C  fire
        BNE move_left                   ; $1E7E  not held: a step
        JMP begin_kick_left             ; $1E80  the flying kick, to the left
; A step the edge refused. The walk ends here, as a clear_state.
stop_move:
        JMP clear_state                 ; $1E83  and return from there

; One step left, if xpos is still above $0D. Facing becomes 0 and the state becomes 3 until
; the caller replaces it. Bit 3 is not tested. A wall is push_out's job on
; the next frame, from the count stored at $4F5D,X.
move_left:
        LDA xpos,X                      ; $1E86  xpos
        CMP #$0D                        ; $1E88  the left edge?
        BCC stop_move                   ; $1E8A  past it: refused
        DEC xpos,X                      ; $1E8C  one step left
        INC $4F5D,X                     ; $1E8E  count the left step
        LDA #$00                        ; $1E91  0
        STA facing,X                    ; $1E93  facing left
        LDA #$03                        ; $1E95  walk left
        JMP set_state                   ; $1E97  and return from there
stick_right:
; $07: right. The same two or three xpos steps. The kick replaces the step when
; the previous state is already 4, $CB,X is below 4, and fire is held.
; Effect $80 plays after the edge test, including a step that then
; becomes a kick.
        CMP #$07                        ; $07: step right. A low pose-repeat count starts the kick.
        BNE stick_down_left             ; $1E9C  not right
        LDA xpos,X                      ; $1E9E  xpos
        CMP #$A3                        ; $1EA0  the right edge?
        BCS stop_move                   ; $1EA2  past it: refused
        JSR score_blip                  ; $1EA4  effect $80
        LDA $CB,X                       ; $1EA7  the burst count
        BNE right_two_steps             ; $1EA9  not 0: two steps
        JSR right_step                  ; $1EAB  the third
; The right burst's second and third steps. The chase enters here.
right_two_steps:
        JSR right_step                  ; $1EAE  the second
; One right step, or the flying kick to the right, as in left_step.
right_step:
        LDA $C2,X                       ; $1EB1  the state on the previous frame
        CMP #$04                        ; $1EB3  already walking right?
        BNE move_right                  ; $1EB5  no: a step
        LDA $CB,X                       ; $1EB7  the burst count
        CMP #$04                        ; $1EB9  4 or more?
        BCS move_right                  ; $1EBB  yes: a step
        LDA $9B,X                       ; $1EBD  fire
        BNE move_right                  ; $1EBF  not held: a step
        JMP begin_kick_right            ; $1EC1  the flying kick, to the right

; One step right, if xpos is still below $A3. Facing becomes 1 and the state becomes 4
; until the caller replaces it. Bit 3 is not tested. The count lands in
; $4F60,X. push_out's undo of a leftward run comes through here, so the
; facing stored for the next chase is 1.
move_right:
        LDA xpos,X                      ; $1EC4  xpos
        CMP #$A3                        ; $1EC6  the right edge?
        BCS stop_move                   ; $1EC8  past it: refused
        INC xpos,X                      ; $1ECA  one step right
        INC $4F60,X                     ; $1ECC  count the right step
        LDA #$01                        ; $1ECF  1
        STA facing,X                    ; $1ED1  facing right
        LDA #$04                        ; $1ED3  walk right
        JMP set_state                   ; $1ED5  and return from there
stick_down_left:
; $09: down and left. A ladder clears the state. On the ground Bruce ducks,
; state $1A, facing left, unless xpos has reached $A2.
        CMP #$09                        ; $1ED8  down and left?
        BNE stick_down_right            ; $1EDA  not down and left
        TXA                             ; $1EDC  the actor
        BNE yamo_down                   ; $1EDD  not Bruce
        LDA hit,X                       ; $1EDF  the full hit
        AND #$04                        ; $1EE1  ladder?
ladder_refuse:
        BNE stop_move                   ; $1EE3  yes: refused
        LDA hit,X                       ; $1EE5  the full hit
        AND #$01                        ; $1EE7  ground?
        BEQ stick_clear                 ; $1EE9  no: clear the state
duck_left:
        LDA xpos,X                      ; $1EEB  xpos
        CMP #$A2                        ; $1EED  $A2 or more?
        BCS stick_clear                 ; $1EEF  yes: clear the state
        LDA #$00                        ; $1EF1  0
        STA facing,X                    ; $1EF3  facing left
        LDA #$1A                        ; $1EF5  duck
        JMP set_state                   ; $1EF7  and return from there
yamo_down:
        CMP #$01                        ; $1EFA  Yamo?
        BNE stick_clear                 ; $1EFC  no: clear the state
        LDA hit,X                       ; $1EFE  the full hit
        AND #$04                        ; $1F00  ladder?
        BNE stick_clear                 ; $1F02  yes: clear the state
        JMP yamo_appear                 ; $1F04  Yamo's first picture
stick_clear:
        JMP clear_state                 ; $1F07  and return from there
stick_down_right:
; $05: down and right. The duck faces right unless xpos is below $10.
        CMP #$05                        ; $1F0A  down and right?
        BNE stick_jump_or_punch         ; $1F0C  not down and right
        TXA                             ; $1F0E  the actor
        BNE yamo_down                   ; $1F0F  not Bruce
        LDA hit,X                       ; $1F11  the full hit
        AND #$04                        ; $1F13  ladder?
        BNE ladder_refuse               ; $1F15  yes: refused
        LDA hit,X                       ; $1F17  the full hit
        AND #$01                        ; $1F19  ground?
        BEQ stick_clear                 ; $1F1B  no: clear the state
duck_right:
        LDA xpos,X                      ; $1F1D  xpos
        CMP #$10                        ; $1F1F  below $10?
        BCC stick_clear                 ; $1F21  yes: clear the state
        LDA #$01                        ; $1F23  1
        STA facing,X                    ; $1F25  facing right
        LDA #$1A                        ; $1F27  duck
        JMP set_state                   ; $1F29  and return from there
; Wall bit 3 goes to try_punch and does not jump. Effect $80 plays
; when the sideways jump is taken: $0A left, $06 right, not a ladder.
stick_jump_or_punch:
        PHA                             ; $1F2C  keep the stick
        LDA hit,X                       ; $1F2D  the full hit
        AND #$08                        ; $1F2F  wall?
        BEQ stick_jump_left             ; $1F31  no: maybe a jump
        PLA                             ; $1F33  the stick again
        JMP try_punch                   ; $1F34  a wall turns the jump into a punch
stick_jump_left:
        PLA                             ; $1F37  the stick again
        CMP #$0A                        ; $1F38  up and left?
        BNE stick_jump_right            ; $1F3A  no
        LDA hit,X                       ; $1F3C  the full hit
        AND #$04                        ; $1F3E  ladder?
        BNE ladder_refuse               ; $1F40  yes: refused
        LDA #$00                        ; $1F42  0
        STA facing,X                    ; $1F44  facing left
        JSR score_blip                  ; $1F46  effect $80
        LDA #$06                        ; $1F49  the sideways jump left
        JMP set_state_15                ; $1F4B  timer 15
stick_jump_right:
        CMP #$06                        ; $1F4E  up and right?
        BNE try_punch                   ; $1F50  no
        LDA hit,X                       ; $1F52  the full hit
        AND #$04                        ; $1F54  ladder?
        BNE ladder_refuse               ; $1F56  yes: refused
        LDA #$01                        ; $1F58  1
        STA facing,X                    ; $1F5A  facing right
        JSR score_blip                  ; $1F5C  effect $80
        LDA #$07                        ; $1F5F  the sideways jump right
        JMP set_state_15                ; $1F61  timer 15

; Flying kick to the left. Facing 0, state $0C, timer 12.
begin_kick_left:
        LDA #$00                        ; $1F64  0
        STA facing,X                    ; $1F66  facing left
        LDA #$0C                        ; $1F68  the flying kick left
        JMP set_state_12                ; $1F6A  timer 12

; Flying kick to the right. Facing 1, state $0D, timer 12.
begin_kick_right:
        LDA #$01                        ; $1F6D  1
        STA facing,X                    ; $1F6F  facing right
        LDA #$0D                        ; $1F71  the flying kick right
        JMP set_state_12                ; $1F73  timer 12

; Fire with no direction. State $11, then begin_punch forces the timer to 4.
try_punch:
        CMP #$0F                        ; $1F76  no direction?
        BNE clear_state                 ; $1F78  no: clear the state
        LDA $9B,X                       ; $1F7A  fire
        BNE clear_state                 ; $1F7C  not held: clear the state
; try_punch after the stick and button tests. On a ladder the punch is
; refused and the state is cleared.
punch_unless_ladder:
        LDA hit,X                       ; $1F7E  the full hit
        AND #$04                        ; $1F80  ladder?
        BNE clear_state                 ; $1F82  yes: refused
        LDA #$11                        ; $1F84  the punch
        JMP begin_punch                 ; $1F86  and return from there

; State 0 and timer 0. If $C2,X is 0, $4FDB,X is incremented first.
; The picture hold from the state table is still stored.
clear_state:
        LDA $C2,X                       ; $1F89  the state on the previous frame
        BNE clear_state_store           ; $1F8B  not 0
        INC $4FDB,X                     ; $1F8D  already idle: choose_pose skips its turn
clear_state_store:
        LDA #$00                        ; $1F90  state 0
; A is the new state. The picture hold comes from $4A8C+state, and the
; timer is 0, so actor_tick does not run a script for it.
set_state:
        STA state,X                     ; $1F92  the new state
        TAY                             ; $1F94  the index
        LDA $4A8C,Y                     ; $1F95  its picture hold
        STA $0106,X                     ; $1F98  stored
        LDA #$00                        ; $1F9B  zero
        STA timer,X                     ; $1F9D  no script
        RTS                             ; $1F9F  back

; Store A as the state and start the timer at 15. The standing jump and both sideways jumps
; use this.
set_state_15:
        STA state,X                     ; $1FA0  the new state
        TAY                             ; $1FA2  the index
        LDA $4A8C,Y                     ; $1FA3  its picture hold
        STA $0106,X                     ; $1FA6  stored
        LDA #$0F                        ; $1FA9  15 counts
        STA timer,X                     ; $1FAB  the timer
        RTS                             ; $1FAD  back

; Store A as the state and start the timer at 12. Both flying kicks use this.
set_state_12:
        STA state,X                     ; $1FAE  the new state
        TAY                             ; $1FB0  the index
        LDA $4A8C,Y                     ; $1FB1  its picture hold
        STA $0106,X                     ; $1FB4  stored
        LDA #$0C                        ; $1FB7  12 counts
        STA timer,X                     ; $1FB9  the timer
        RTS                             ; $1FBB  back

; A is already $11. set_state_12 records that state, then the timer is replaced with 4.
; That is the punch.
begin_punch:
        JSR set_state_12                ; $1FBC  state $11 and its hold
        LDA #$04                        ; $1FBF  4 counts
        STA timer,X                     ; $1FC1  the timer
        RTS                             ; $1FC3  back
; Effect $80, the movement chirp. Walk, climb, the sideways jump, and
; a pure-direction carry step. add_score does not call it. A chase
; step starts past the walk's call, so it is silent.
; $0CD9 is a BCD counter for this effect, not the player score at $41.
; It increments unless $1166 is set, and the compare with $99 is what
; shows those digits are BCD. A second counter at $1C14 moves only
; when the check byte $2007 is zero.
score_blip:
        PHA                             ; $1FC4  keep A
        TXA                             ; $1FC5  X
        PHA                             ; $1FC6  keep X
        TYA                             ; $1FC7  Y
        PHA                             ; $1FC8  keep Y
        LDY #$80                        ; $1FC9  effect $80
        JSR play_sound                  ; $1FCB  queue it
        LDA $1166                       ; $1FCE  the check byte at $1166
        BNE blip_check_second           ; $1FD1  tampered: skip the first counter
        INC $0CD9                       ; $1FD3  the BCD counter
        INC $0CDC                       ; $1FD6  its partner
        LDA $0CD9                       ; $1FD9  the count
        CMP #$99                        ; $1FDC  99 or more?
        BCC blip_check_second           ; $1FDE  no
        LDA #$9A                        ; $1FE0  TXS
        STA $1159                       ; $1FE2  over the code at $1159. Only a tampered image gets here
blip_check_second:
        LDA $2007                       ; $1FE5  the check byte at $2007
        BNE blip_done                   ; $1FE8  tampered: skip
        INC $1C14                       ; $1FEA  the second counter
        INC $1C17                       ; $1FED  its partner
        LDA $1C14                       ; $1FF0  the count
        CMP #$9A                        ; $1FF3  $9A or more?
        BCC blip_done                   ; $1FF5  no
        LDX #$04                        ; $1FF7  not used
        LDA #$9A                        ; $1FF9  TXS
        STA $1FFE                       ; $1FFB  over the code at $1FFE
        CLC                             ; $1FFE  CLC, until the store above makes it TXS
blip_done:
        PLA                             ; $1FFF  Y back
        TAY                             ; $2000  Y back
        PLA                             ; $2001  X back
        TAX                             ; $2002  X back
        PLA                             ; $2003  A back
        RTS                             ; $2004  back
        .byte $00, $00, $04             ; $2005  the saved CIA directions, then the check byte


; Scripted motion. Y is timer,X from before this frame's decrement. It is copied to $52,
; which the state compares use. keep_state then decrements $52 and writes it back to
; timer,X.
move_for_state:
        STY $52                         ; $2008  the timer before the decrement
        LDA state,X                     ; $200A  the state
        CMP #$05                        ; $200C  the standing jump?
        BNE state_kick_left             ; $200E  no
        LDA hit,X                       ; $2010  the full hit
        AND #$04                        ; $2012  ladder?
        BNE script_land_if_set          ; $2014  yes: land
        CPY #$0D                        ; State 5, standing jump. The compares are on the timer in Y.
        BCS jump_keep                   ; $2018  timer 13-15: no motion yet
        CPY #$02                        ; $201A  timer 0 or 1?
        BCC jump_keep                   ; $201C  yes: no motion
        CPY #$08                        ; $201E  timer 8-12?
        BCS jump_rise                   ; $2020  yes: rise
        LDA hit,X                       ; $2022  the full hit
        AND #$01                        ; $2024  ground?
        BNE script_land_if_set          ; $2026  yes: land
        JSR move_down                   ; Timers 2 through 7: two steps down.
        JSR move_down                   ; $202B  the second pixel down
jump_keep:
        LDA #$05                        ; $202E  still the jump
        JMP keep_state                  ; $2030  timer one less
jump_rise:
        CPY #$0C                        ; $2033  timer 12?
        BNE jump_rise_two               ; $2035  no: two up
        JSR move_up                     ; Timer 12: four steps up.
        JSR move_up                     ; $203A  the second of four
jump_rise_two:
        JSR move_up                     ; $203D  two up
        JSR move_up                     ; $2040  the second
        LDA #$05                        ; $2043  still the jump
        JMP keep_state                  ; $2045  timer one less
state_kick_left:
        CMP #$0C                        ; State $0C, flying kick left. One step sideways on every count.
        BNE state_kick_right            ; $204A  no
        LDA hit,X                       ; $204C  the full hit
        AND #$0C                        ; $204E  ladder or wall?
        BNE script_land_if_set          ; $2050  either: land
; Timer still $0C, and the ladder and wall tests above have passed.
; Effect $84. Bruce and the fighters share this kick.
        CPY #$0C                        ; $2052  the first count?
        BNE kick_left_steps             ; $2054  not the first count
        STX $51                         ; $2056  keep the actor
        LDY #$84                        ; $2058  effect $84
        JSR play_sound                  ; $205A  queue it
        LDX $51                         ; $205D  the actor
        LDY $52                         ; $205F  the timer again
kick_left_steps:
        CPY #$0A                        ; $2061  timer 10 or more?
        BCC kick_left_glide             ; $2063  no
        JSR move_up                     ; $2065  up
        JSR move_left                   ; $2068  and left
        LDA #$0C                        ; $206B  still the kick
        JMP keep_state                  ; $206D  timer one less
kick_left_glide:
        CPY #$03                        ; $2070  timer 3 or more?
        BCC kick_left_land_test         ; $2072  no: the descent
        JSR move_left                   ; $2074  left, level
        LDA #$0C                        ; $2077  still the kick
        JMP keep_state                  ; $2079  timer one less
kick_left_land_test:
        LDA hit,X                       ; $207C  the full hit
        AND #$01                        ; $207E  ground?
script_land_if_set:
        BNE script_land                 ; $2080  yes: land
        JSR move_down                   ; $2082  down
        JSR move_left                   ; $2085  and left
        LDA #$0C                        ; $2088  still the kick
        JMP keep_state                  ; $208A  timer one less
state_kick_right:
        CMP #$0D                        ; State $0D, flying kick right.
        BNE state_jump_left             ; $208F  not the kick right
        LDA hit,X                       ; $2091  the full hit
        AND #$0C                        ; $2093  ladder or wall?
        BNE script_land                 ; $2095  either: land
; Timer still $0C, and the ladder and wall tests above have passed.
; Effect $84.
        CPY #$0C                        ; $2097  the first count?
        BNE kick_right_steps            ; $2099  not the first count
        STX $51                         ; $209B  keep the actor
        LDY #$84                        ; $209D  effect $84
        JSR play_sound                  ; $209F  queue it
        LDX $51                         ; $20A2  the actor
        LDY $52                         ; $20A4  the timer again
kick_right_steps:
        CPY #$0A                        ; $20A6  timer 10 or more?
        BCC kick_right_glide            ; $20A8  no
        JSR move_up                     ; $20AA  up
        JSR move_right                  ; $20AD  and right
        LDA #$0D                        ; $20B0  still the kick
        JMP keep_state                  ; $20B2  timer one less
kick_right_glide:
        CPY #$03                        ; $20B5  timer 3 or more?
        BCC kick_right_land_test        ; $20B7  no: the descent
        JSR move_right                  ; $20B9  right, level
        LDA #$0D                        ; $20BC  still the kick
        JMP keep_state                  ; $20BE  timer one less
kick_right_land_test:
        LDA hit,X                       ; $20C1  the full hit
        AND #$01                        ; $20C3  ground?
        BNE script_land                 ; $20C5  yes: land
        JSR move_down                   ; $20C7  down
        JSR move_right                  ; $20CA  and right
        LDA #$0D                        ; $20CD  still the kick
        JMP keep_state                  ; $20CF  timer one less
state_jump_left:
        CMP #$06                        ; State 6, sideways jump left. Two steps sideways on every count.
        BNE state_jump_right            ; $20D4  not the jump left
        LDA hit,X                       ; $20D6  the full hit
        AND #$04                        ; $20D8  ladder?
        BNE script_land                 ; $20DA  yes: land
        CPY #$0A                        ; $20DC  timer 10 or more?
        BCC jump_left_level             ; $20DE  below: level or falling
        BEQ jump_left_rise              ; $20E0  timer 10: one up
        JSR move_up                     ; $20E2  above 10: two up
jump_left_rise:
        JSR move_up                     ; $20E5  one up
        JSR move_left                   ; $20E8  two steps left
        JSR move_left                   ; $20EB  the second
        LDA #$06                        ; $20EE  still the jump
        JMP keep_state                  ; $20F0  timer one less
script_land:
        JMP land                        ; $20F3  the state ends
jump_left_level:
        CPY #$07                        ; $20F6  timer 7-9?
        BCC jump_left_descend           ; $20F8  below: the descent
        JSR move_left                   ; $20FA  two steps left, level
        JSR move_left                   ; $20FD  the second
        LDA #$06                        ; $2100  still the jump
        JMP keep_state                  ; $2102  timer one less
jump_left_descend:
        LDA hit,X                       ; $2105  the full hit
        AND #$01                        ; $2107  ground?
        BNE script_land                 ; $2109  yes: land
        JSR move_left                   ; $210B  two steps left
        JSR move_left                   ; $210E  the second
        CPY #$06                        ; $2111  timer 6?
        BEQ jump_left_drop              ; $2113  yes: one pixel down
        JSR move_down                   ; $2115  two pixels down
jump_left_drop:
        JSR move_down                   ; $2118  one pixel down
        LDA #$06                        ; $211B  still the jump
        JMP keep_state                  ; $211D  timer one less
state_jump_right:
        CMP #$07                        ; State 7, sideways jump right.
        BNE state_shocked               ; $2122  not the jump right
        LDA hit,X                       ; $2124  the full hit
        AND #$04                        ; $2126  ladder?
        BNE script_land                 ; $2128  yes: land
        CPY #$0A                        ; $212A  timer 10 or more?
        BCC jump_right_level            ; $212C  below: level or falling
        BEQ jump_right_rise             ; $212E  timer 10: one up
        JSR move_up                     ; $2130  above 10: two up
jump_right_rise:
        JSR move_up                     ; $2133  one up
        JSR move_right                  ; $2136  two steps right
        JSR move_right                  ; $2139  the second
        LDA #$07                        ; $213C  still the jump
        JMP keep_state                  ; $213E  timer one less
jump_right_level:
        CPY #$07                        ; $2141  timer 7-9?
        BCC jump_right_descend          ; $2143  below: the descent
        JSR move_right                  ; $2145  two steps right, level
        JSR move_right                  ; $2148  the second
        LDA #$07                        ; $214B  still the jump
        JMP keep_state                  ; $214D  timer one less
jump_right_descend:
        LDA hit,X                       ; $2150  the full hit
        AND #$01                        ; $2152  ground?
        BNE script_land                 ; $2154  yes: land
        JSR move_right                  ; $2156  two steps right
        JSR move_right                  ; $2159  the second
        CPY #$06                        ; $215C  timer 6?
        BEQ jump_right_drop             ; $215E  yes: one pixel down
        JSR move_down                   ; $2160  two pixels down
jump_right_drop:
        JSR move_down                   ; $2163  one pixel down
        LDA #$07                        ; $2166  still the jump
        JMP keep_state                  ; $2168  timer one less
state_shocked:
        CMP #$19                        ; $216B  shocked?
        BNE state_ride                  ; $216D  no
        CPX #$00                        ; $216F  Bruce?
        BNE shocked_keep                ; $2171  no: keep it
        CPY #$01                        ; $2173  the last count?
        BEQ shocked_lose_life           ; $2175  yes: a life lost
shocked_keep:
        JMP keep_state                  ; $2177  A is still $19
shocked_lose_life:
        JMP lose_life                   ; $217A  the shock ends a life
ride_land:
        JMP land                        ; $217D  the state ends
state_ride:
        CMP #$17                        ; $2180  carried on the surface?
        BEQ ride_surface                ; $2182  yes
        JMP state_yamo_rise             ; $2184  the other states
; State $17, the scrolling surface. scan_specials has caught him on tile
; $62, or clear_carry has already dropped the state when the tile was
; missed. Hit bit 2 clear leaves through land. $AA is set here and shifted
; to 0 only when his own step runs, which is what pose_carry keeps or flips.
; A computer fighter, X not 0 and $42CA clear, has his stick replaced from
; facing: 1 is $07, anything else is $0B. Bruce keeps the stick he brought.
; $42CA set skips that store for Yamo and for the ninja. Yamo's $99 is the
; second port, refreshed before this runs, so his up and down still climb
; and duck. The ninja's $9A is not a port. ride_finish stores $0F back into
; $98,X, and nothing else writes $9A, so during a human opponent he takes
; no step of his own. The surface shove still runs. $0E and $0D are not
; stored for the computer, so that fighter does not climb and does not
; jump. $AD counts the frames
; between his own steps. While it is set the step is skipped and $AA stays
; 1. A step is exactly two calls, and only a pure direction is taken. It
; stores 4 back into $AD. move_up refuses ypos below $2E and does not test
; a wall. push_out has already run, and a wall bit means this was not
; entered. $C8 is 0 on the path through actor_tick, so bit 0 of $C8 does
; not block the step either. A refused pixel returns through clear_state,
; and keep_state below stores $17 again, so the edge skips that pixel and
; the ride stays in force.
ride_surface:
        LDA hit,X                       ; $2187  the full hit
        AND #$04                        ; $2189  ladder?
        BEQ ride_land                   ; $218B  no: off the surface
        LDA #$01                        ; $218D  1
        STA $AA,X                       ; $218F  his own step has not run yet
        TXA                             ; $2191  Bruce?
        BEQ ride_wait                   ; $2192  yes: his own stick
        LDA $42CA                       ; $2194  a second player?
        BNE ride_wait                   ; $2197  yes: his own stick
        LDA facing,X                    ; $2199  the computer's facing
        CMP #$01                        ; $219B  right?
        BNE ride_stick_left             ; $219D  no
        LDA #$07                        ; $219F  right
        STA $98,X                       ; $21A1  his stick
        BNE ride_wait                   ; $21A3  always
ride_stick_left:
        LDA #$0B                        ; $21A5  left
        STA $98,X                       ; $21A7  his stick
ride_wait:
        LDA $AD,X                       ; $21A9  frames until his own step
        BEQ carry_step                  ; $21AB  0: step now
        DEC $AD,X                       ; $21AD  one frame less
        JMP shove_with_surface          ; $21AF  the surface only
; $AD has run out. Two pixels, and only a pure direction. A diagonal
; leaves $AA set and does not arm the next wait.
carry_step:
        LDA $98,X                       ; $21B2  the stick
        CMP #$0E                        ; $21B4  up?
        BNE carry_step_down             ; $21B6  no
        JSR move_up                     ; $21B8  two pixels up
        JSR move_up                     ; $21BB  the second
        JMP own_step_taken              ; $21BE  the step is taken
carry_step_down:
        CMP #$0D                        ; $21C1  down?
        BNE carry_step_left             ; $21C3  no
        JSR move_down                   ; $21C5  two pixels down
        JSR move_down                   ; $21C8  the second
        JMP own_step_taken              ; $21CB  the step is taken
carry_step_left:
        CMP #$0B                        ; $21CE  left?
        BNE carry_step_right            ; $21D0  no
        JSR move_left                   ; $21D2  two steps left
        JSR move_left                   ; $21D5  the second
        JMP own_step_taken              ; $21D8  the step is taken
carry_step_right:
        CMP #$07                        ; $21DB  right?
        BNE shove_with_surface          ; $21DD  no: a diagonal or none
        JSR move_right                  ; $21DF  two steps right
        JSR move_right                  ; $21E2  the second
; His own step was taken. $AA shifts to 0, so pose_carry will flip, and
; the next step waits four frames. Effect $80. Bruce and a carried
; fighter both reach this, on a pure-direction step.
own_step_taken:
        LSR $AA,X                       ; $21E5  his own step has run
        LDA #$04                        ; $21E7  four frames
        STA $AD,X                       ; $21E9  until the next
        JSR score_blip                  ; $21EB  effect $80
; State $17. The stick has already stepped him two pixels. $60 is read
; after scroll_surface, so a 1 here is the frame before that copy. The
; compare is exact: the $84 pause has bit 7 set and does not shove. $65
; clear moves him up two pixels, the same two rows one pattern byte covers.
; $65 set moves him down.
shove_with_surface:
        LDA $60                         ; $21EE  the surface's delay
        CMP #$01                        ; $21F0  the frame before the copy?
        BNE ride_finish                 ; $21F2  no: no shove
        LDA $65                         ; $21F4  which way it scrolls
        BEQ shove_up                    ; $21F6  up
        JSR move_down                   ; $21F8  two pixels down
        JSR move_down                   ; $21FB  the second
        JMP ride_finish                 ; $21FE  done
shove_up:
        JSR move_up                     ; $2201  two pixels up
        JSR move_up                     ; $2204  the second
; Stick back to none, and fire released. $52 still holds the timer from
; the start of move_for_state. The increment cancels the decrement in
; keep_state, so the $10 catch_surface stored is not consumed. The steps
; above zeroed that timer on their way through set_state, and this write
; puts it back. The two counters are then reduced to the difference.
; $4F57 keeps the extra upward pixels, $4F5A the extra downward ones, and
; the other is cleared. A frame that stepped both ways records only the
; net. exit_allowed reads $4F57 and does not read $4F5A.
ride_finish:
        LDA #$0F                        ; $2207  none
        STA $98,X                       ; $2209  stick none
        LDA #$01                        ; $220B  up
        STA $9B,X                       ; $220D  fire released
        INC $52                         ; $220F  cancels keep_state's decrement
        LDA $4F57,X                     ; $2211  up pixels this frame
        SEC                             ; $2214  the borrow
        SBC $4F5A,X                     ; $2215  less down pixels
        BPL ride_net_up                 ; $2218  more up, or level
        EOR #$FF                        ; $221A  negative
        ADC #$01                        ; $221C  negated: more down
        STA $4F5A,X                     ; $221E  the net down
        LDA #$00                        ; $2221  zero
        STA $4F57,X                     ; $2223  no up
        BEQ ride_keep                   ; $2226  always
ride_net_up:
        STA $4F57,X                     ; $2228  the net up
        LDA #$00                        ; $222B  zero
        STA $4F5A,X                     ; $222D  no down
ride_keep:
        LDA #$17                        ; $2230  still on the surface
        JMP keep_state                  ; $2232  the timer put back
state_yamo_rise:
        CMP #$10                        ; $2235  Yamo's first picture?
        BNE state_punch                 ; $2237  no
        LDA timer,X                     ; $2239  the timer
        CMP #$01                        ; $223B  the last count?
        BEQ yamo_appear                 ; $223D  yes: he appears
        LDA #$10                        ; $223F  still waiting
        JMP keep_state                  ; $2241  timer one less
yamo_appear:
        LDA xpos,X                      ; $2244  Yamo's xpos
        CMP xpos                        ; $2246  left of Bruce?
        BCC yamo_appear_right           ; $2248  yes: face right
        LDA #$00                        ; $224A  face left
yamo_appear_store:
        STA facing,X                    ; $224C  his facing
        LDA #$12                        ; $224E  the second picture
        STA state,X                     ; $2250  the second picture
        LDA #$10                        ; $2252  16
        STA timer,X                     ; $2254  16 counts
        LDA #$00                        ; $2256  zero
        STA $0106,X                     ; $2258  no hold
        TXA                             ; $225B  keep the actor
        PHA                             ; $225C  kept
; Effect $81. State $10's timer was exactly 1, so Yamo is appearing.
        LDY #$81                        ; $225D  effect $81
        JSR play_sound                  ; $225F  effect $81
        PLA                             ; $2262  the actor
        TAX                             ; $2263  the actor back
        RTS                             ; $2264  back
yamo_appear_right:
        LDA #$01                        ; $2265  face right
        JMP yamo_appear_store           ; $2267  always
state_punch:
        CMP #$11                        ; $226A  the punch?
        BNE try_strike                  ; $226C  no
        LDA hit,X                       ; $226E  the full hit
        AND #$0C                        ; $2270  ladder or wall?
        BNE land_if_wall                ; $2272  either: land
; Compared with 8. begin_punch stores 4, so this never plays.
; Effect $85 is the strike below, not the punch.
        CPY #$08                        ; $2274  timer 8, which a punch never has
        BNE punch_keep                  ; $2276  always
        STX $51                         ; $2278  keep the actor
        LDY #$85                        ; $227A  effect $85
        JSR play_sound                  ; $227C  queue it
        LDX $51                         ; $227F  the actor
        LDY $52                         ; $2281  the timer again
punch_keep:
        CPY #$01                        ; $2283  the last count?
        BEQ stand_down                  ; $2285  yes: stand
        LDA #$11                        ; $2287  still the punch
        JMP keep_state                  ; $2289  timer one less
; State 0 and timer 6, and the pose hold is cleared. A timer still running
; keeps actor_tick inside move_for_state, so these frames do not fall.
; Bruce: a long or middle visit doubles the 6, a short visit halves it.
; Another fighter: a long visit or a set $40 stores 1, a middle visit
; halves the 6, and a short visit with $40 clear keeps 6. The kick path in
; enemy_turn calls this and then stores $18 over the timer.
stand_down:
        LDA #$00                        ; $228C  zero
        STA state,X                     ; $228E  state 0
        LDA #$06                        ; $2290  6
        STA timer,X                     ; $2292  6 counts
        LDA #$00                        ; $2294  zero
        STA $0106,X                     ; $2296  no hold
        TXA                             ; $2299  the actor
        BNE stand_down_enemy            ; $229A  not Bruce
        JSR test_visit                  ; $229C  how long he has been in the room
        BVS stand_down_double           ; $229F  long: double
        BCS stand_down_double           ; $22A1  middle: double
        LSR timer,X                     ; $22A3  short: halve
        RTS                             ; $22A5  back
stand_down_enemy:
        JSR test_visit                  ; $22A6  how long he has been in the room
        BVS stand_down_short            ; $22A9  long: 1
        BCS stand_down_halve            ; $22AB  middle: halve
        LDA $40                         ; $22AD  a set $40
        BNE stand_down_short            ; $22AF  1
        RTS                             ; $22B1  short: 6
stand_down_halve:
        LSR timer,X                     ; $22B2  3
        RTS                             ; $22B4  back
stand_down_double:
        ASL timer,X                     ; $22B5  12
        RTS                             ; $22B7  back
stand_down_short:
        LDA #$01                        ; $22B8  one count
        STA timer,X                     ; $22BA  the timer
        RTS                             ; $22BC  back
; Not the punch. The test below is for state $16.
try_strike:
; State $16, the ninja's strike. Wall bit 3 goes to land: state 0, timer 0.
; Ladder bit 2 does not. The punch falls into the land test at land_if_wall
; with bits 2 and 3 both counted, so a ladder ends a punch and only a
; wall ends this strike. The INCs add to the push counters, $4F60 when
; he faces right and $4F5D when he faces left. xpos stays where it is,
; and a later push_out walks that count as a real step. Timer 1 is
; stand_down. There is no ground test on that path. stand_down stores 6,
; and test_visit may shorten it. The strike picture often misses the
; floor. Testing the ground here would store 0, and enemy_turn would
; start another strike on the next frame.
        CMP #$16                        ; $22BD  the ninja's strike?
        BNE state_chase                 ; $22BF  no
        LDA hit,X                       ; $22C1  the full hit
        AND #$08                        ; $22C3  wall?
land_if_wall:
        BEQ strike_sound                ; $22C5  no
        JMP land                        ; $22C7  the strike ends
strike_sound:
; Timer still $0C, and wall bit 3 did not end the strike. Effect $85.
        CPY #$0C                        ; $22CA  the first count?
        BNE strike_push                 ; $22CC  no
        STX $51                         ; $22CE  keep the actor
        LDY #$85                        ; $22D0  effect $85
        JSR play_sound                  ; $22D2  queue it
        LDX $51                         ; $22D5  the actor
        LDY $52                         ; $22D7  the timer again
strike_push:
        CPY #$01                        ; $22D9  the last count?
        BEQ strike_done                 ; $22DB  yes: stand
        LDA facing,X                    ; $22DD  his facing
        CMP #$01                        ; $22DF  right?
        BNE strike_push_left            ; $22E1  no
        INC $4F60,X                     ; $22E3  a right step that never moved him
        BNE strike_keep                 ; $22E6  always
strike_push_left:
        INC $4F5D,X                     ; $22E8  a left step that never moved him
strike_keep:
        LDA #$16                        ; $22EB  still the strike
        JMP keep_state                  ; $22ED  timer one less
strike_done:
        JMP stand_down                  ; $22F0  stand, timer 6
state_chase:
        CMP #$14                        ; $22F3  the chase?
        BEQ chase_test                  ; $22F5  yes
        JMP state_sidestep              ; $22F7  no: the sidestep and later states
chase_test:
        LDA hit,X                       ; $22FA  the full hit
        AND #$01                        ; $22FC  ground?
        BEQ chase_ladder                ; $22FE  no: the ladder case
        JSR range_to_bruce              ; $2300  dx and dy
        LDA $62                         ; $2303  dy
        AND #$7F                        ; $2305  the size alone
        CMP #$10                        ; $2307  $10 or more?
        BCS bruce_above                 ; $2309  yes: Bruce is far above or below
        LDA facing,X                    ; $230B  his facing
        LDY $63                         ; $230D  Bruce to his right?
        BMI chase_facing_test           ; $230F  yes: facing 1 is toward him
        EOR #$01                        ; $2311  no: facing 0 is toward him
chase_facing_test:
        CMP #$01                        ; $2313  facing Bruce?
        BEQ facing_bruce                ; $2315  yes
        TYA                             ; $2317  dx
        AND #$7F                        ; $2318  the size alone
        CMP #$21                        ; $231A  below $21?
        BCC start_sidestep              ; $231C  yes: sidestep
        LDA facing,X                    ; $231E  his facing
        EOR #$01                        ; $2320  turned
        STA facing,X                    ; $2322  toward Bruce
        JMP chase_walk                  ; $2324  and walk
; Not facing Bruce, and |dx| is below $21. State $15, and no walk on
; this frame. The timer is the distance to Bruce's xpos plus or minus
; $0F, and at least 5. push_out has usually just left him facing away
; from the wall. This sidestep then walks that way, so a close Bruce
; on the far side of the wall does not turn him back into it. |dx| of
; $21 or more is the branch above: facing flips and chase_walk runs
; on this same frame, back toward Bruce.
start_sidestep:
        LDA xpos                        ; $2327  Bruce's xpos
        LDY $63                         ; $2329  Bruce to his right?
        BPL sidestep_right_target       ; $232B  yes
        SEC                             ; $232D  the borrow
        SBC #$0F                        ; $232E  less $0F
        BNE sidestep_distance           ; $2330  always
sidestep_right_target:
        CLC                             ; $2332  carry clear
        ADC #$0F                        ; $2333  plus $0F
sidestep_distance:
        SEC                             ; $2335  the borrow
        SBC xpos,X                      ; $2336  less his xpos
        BCS sidestep_min                ; $2338  not negative
        EOR #$FF                        ; $233A  negative
        ADC #$01                        ; $233C  the distance
sidestep_min:
        CMP #$05                        ; $233E  5 or more?
        BCS sidestep_store              ; $2340  yes
        LDA #$05                        ; $2342  at least 5
sidestep_store:
        STA timer,X                     ; $2344  the sidestep's length
        LDA #$15                        ; $2346  the sidestep
        STA state,X                     ; $2348  the sidestep
        LDA #$00                        ; $234A  zero
        STA $0106,X                     ; $234C  no hold
        STA $C8,X                       ; $234F  move_up may run
        RTS                             ; $2351  back
; Facing 1 walks right and facing 0 walks left. State $14 is kept.
; bruce_above and chase_ladder both arrive here when he should keep
; walking. The walk is the two-or-three xpos burst, not a climb.
; keep_chase increments $52 before keep_state, so the $14 is not
; consumed while he is walking. The sidestep's own keep_state does
; consume its timer. The burst length is $CB, already updated by
; hold_done: 6 on the first frame of the chase, two xpos, and 0
; once that count has run out, three xpos.
; The burst starts at left_two_steps or right_two_steps, past score_blip, so a chase
; step does not play effect $80.
chase_walk:
        LDA facing,X                    ; $2352  his facing
        CMP #$01                        ; $2354  right?
        BNE chase_walk_left             ; $2356  no
        JSR right_two_steps             ; $2358  the burst, right
; Both walk directions finish here.
keep_chase:
        INC $52                         ; $235B  cancels keep_state's decrement
        LDA #$14                        ; $235D  still the chase
        JMP keep_state                  ; $235F  the timer kept
; |dy| is at least $10, and hit bit 0 was set. Bit 7 of $62 means this
; fighter is above Bruce, so he keeps walking at chase_walk. Bruce above:
; face_from_dx, then stand_down. chase_ladder is the bit-0-clear path,
; and that one walks without this compare. Neither path climbs.
bruce_above:
        LDA $62                         ; $2362  dy
        BMI chase_walk                  ; $2364  he is above Bruce: walk
        JSR face_from_dx                ; $2366  Bruce is above: face him
        JMP stand_down                  ; $2369  and stand
chase_walk_left:
        JSR left_two_steps              ; $236C  the burst, left
        JMP keep_chase                  ; $236F  still the chase
; Ground bit clear. The ladder bit walks, at chase_walk. Neither bit
; set falls. This is a ladder with no floor under him, and he does not
; climb it.
chase_ladder:
        LDA hit,X                       ; $2372  the full hit
        AND #$04                        ; $2374  ladder?
        BNE chase_walk                  ; $2376  yes: walk
chase_fall:
        JMP begin_fall                  ; $2378  nothing under him
; Facing Bruce. Active $81 is Yamo. |dx| below 5 sidesteps, below
; $0C punches, below $13 starts the flying kick, and anything farther
; walks. The ninja walks at $0B or more, sidesteps below 5, and the distances
; in between are state $16 with timer $13.
facing_bruce:
        LDA active,X                    ; $237B  active
        AND #$81                        ; $237D  both bits
        CMP #$81                        ; $237F  Yamo?
        BNE facing_ninja                ; $2381  no: the ninja
        LDA $63                         ; $2383  dx
        AND #$7F                        ; $2385  the size alone
        CMP #$05                        ; $2387  below 5?
facing_close:
        BCC start_sidestep              ; $2389  yes: sidestep
        CMP #$0C                        ; $238B  $0C or more?
        BCS facing_kick                 ; $238D  yes: kick or walk
        JSR punch_unless_ladder         ; $238F  the punch, unless on a ladder
        LDA state,X                     ; $2392  the state now
        CMP #$11                        ; $2394  the punch?
        BNE facing_punch_refused        ; $2396  no: refused
        RTS                             ; $2398  punching
facing_punch_refused:
        JMP stand_down                  ; $2399  stand instead
facing_kick:
        CMP #$13                        ; $239C  $13 or more?
        BCS chase_walk                  ; $239E  yes: walk
        LDA facing,X                    ; $23A0  his facing
        CMP #$01                        ; $23A2  right?
        BEQ facing_kick_right           ; $23A4  yes
        LDA #$0C                        ; $23A6  the flying kick left
facing_kick_store:
        STA state,X                     ; $23A8  the kick
        LDA #$0C                        ; $23AA  12 counts
        STA timer,X                     ; $23AC  the timer
        LDA #$00                        ; $23AE  zero
        STA $0106,X                     ; $23B0  no hold
        RTS                             ; $23B3  back
facing_kick_right:
        LDA #$0D                        ; $23B4  the flying kick right
        BNE facing_kick_store           ; $23B6  always
facing_ninja:
        LDA $63                         ; $23B8  dx
        AND #$7F                        ; $23BA  the size alone
        CMP #$0B                        ; $23BC  $0B or more?
        BCS chase_walk                  ; $23BE  yes: walk
        CMP #$05                        ; $23C0  below 5?
        BCC facing_close                ; $23C2  yes: sidestep, carry still clear
        LDA #$16                        ; $23C4  the strike
        STA state,X                     ; $23C6  the state
        LDA #$13                        ; $23C8  19 counts
        STA timer,X                     ; $23CA  the timer
        RTS                             ; $23CC  back
; State $15, the sidestep. Bit 0 clear is a fall, ladder or otherwise.
; Timer 1 turns him around and stores state $14 with timer $80.
state_sidestep:
        CMP #$15                        ; $23CD  the sidestep?
        BNE state_rising                ; $23CF  no
        LDA hit,X                       ; $23D1  the full hit
        AND #$01                        ; $23D3  ground?
        BEQ chase_fall                  ; $23D5  no: fall
        LDA timer,X                     ; $23D7  the timer
        CMP #$01                        ; $23D9  the last count?
        BNE sidestep_walk               ; $23DB  no: walk on
        LDA facing,X                    ; $23DD  his facing
        EOR #$01                        ; $23DF  turned
        STA facing,X                    ; $23E1  back
        LDA #$14                        ; $23E3  the chase
        STA state,X                     ; $23E5  the state
        LDA #$00                        ; $23E7  zero
        STA $0106,X                     ; $23E9  no hold
        LDA #$80                        ; $23EC  128 counts, kept by keep_chase
        STA timer,X                     ; $23EE  the timer
        RTS                             ; $23F0  back
sidestep_walk:
        LDA facing,X                    ; $23F1  his facing
        CMP #$01                        ; $23F3  right?
        BNE sidestep_walk_left          ; $23F5  no
        JSR right_two_steps             ; $23F7  the burst, right
        LDA #$15                        ; $23FA  still the sidestep
        JMP keep_state                  ; $23FC  timer one less
sidestep_walk_left:
        JSR left_two_steps              ; $23FF  the burst, left
        LDA #$15                        ; $2402  still the sidestep
        JMP keep_state                  ; $2404  timer one less
state_rising:
        CMP #$12                        ; $2407  Yamo's second picture?
        BNE state_flinch                ; $2409  no
        JMP keep_state                  ; $240B  A is $12: timer one less
state_flinch:
; State $0F, the flinch. A non-Bruce whose timer in Y is below 2 goes to
; stand_down. Facing right slides two steps left, facing left two steps
; right, and the facing is written back. The picture is the stand.
        CMP #$0F                        ; $240E  the flinch?
        BNE state_knockdown             ; $2410  no
        TXA                             ; $2412  Bruce?
        BEQ flinch_slide                ; $2413  yes: always slides
        CPY #$02                        ; $2415  timer 0 or 1?
        BCC flinch_done                 ; $2417  yes: stand
flinch_slide:
        LDA facing,X                    ; $2419  his facing
        CMP #$01                        ; $241B  right?
        BNE flinch_slide_right          ; $241D  no
        JSR move_left                   ; $241F  two steps back, left
        JSR move_left                   ; $2422  the second
        LDA #$01                        ; $2425  1
        STA facing,X                    ; $2427  facing right again
        LDA #$0F                        ; $2429  still the flinch
        JMP keep_state                  ; $242B  timer one less
flinch_slide_right:
        JSR move_right                  ; $242E  two steps back, right
        JSR move_right                  ; $2431  the second
        LDA #$00                        ; $2434  0
        STA facing,X                    ; $2436  facing left again
        LDA #$0F                        ; $2438  still the flinch
        JMP keep_state                  ; $243A  timer one less
flinch_done:
        JMP stand_down                  ; $243D  stand
; State $13, the knockdown. A non-Bruce whose $D1 is still positive leaves
; through stand_down once Y is below 2. Negative $D1 stays here until the
; timer reaches 0 and check_bruce_down removes him. Bits 0 and 2 both clear
; drops one pixel. Facing right slides left, facing left slides right, two
; steps, and the facing is written back. The ninja on the frame Y is $0A adds
; eight steps to that left slide, or four steps to that right slide.
state_knockdown:
        CMP #$13                        ; $2440  the knockdown?
        BNE state_stuck                 ; $2442  no
        TXA                             ; $2444  Bruce?
        BEQ knockdown_slide             ; $2445  yes: always slides
        LDA $D1,X                       ; $2447  health
        BMI knockdown_slide             ; $2449  down for good: slides
        CPY #$02                        ; $244B  timer 0 or 1?
        BCC knockdown_done              ; $244D  yes: stand
knockdown_slide:
        LDA hit,X                       ; $244F  the full hit
        AND #$05                        ; $2451  ground or ladder
        BNE knockdown_dir               ; $2453  either: no drop
        JSR move_down                   ; $2455  one pixel down
knockdown_dir:
        LDA facing,X                    ; $2458  his facing
        CMP #$01                        ; $245A  right?
        BNE knockdown_right             ; $245C  no
        CPY #$0A                        ; $245E  timer 10?
        BNE knockdown_left              ; $2460  no
        CPX #$02                        ; $2462  the ninja?
        BNE knockdown_left              ; $2464  no
        JSR move_left                   ; $2466  eight more steps left
        JSR move_left                   ; $2469  two
        JSR move_left                   ; $246C  three
        JSR move_left                   ; $246F  four
        JSR move_left                   ; $2472  five
        JSR move_left                   ; $2475  six
        JSR move_left                   ; $2478  seven
        JSR move_left                   ; $247B  eight
knockdown_left:
        JSR move_left                   ; $247E  two steps left
        JSR move_left                   ; $2481  the second
        LDA #$01                        ; $2484  1
        STA facing,X                    ; $2486  facing right again
        LDA #$13                        ; $2488  still the knockdown
        JMP keep_state                  ; $248A  timer one less
knockdown_right:
        CPY #$0A                        ; $248D  timer 10?
        BNE knockdown_right_steps       ; $248F  no
        CPX #$02                        ; $2491  the ninja?
        BNE knockdown_right_steps       ; $2493  no
        JSR move_right                  ; $2495  four more steps right
        JSR move_right                  ; $2498  two
        JSR move_right                  ; $249B  three
        JSR move_right                  ; $249E  four
knockdown_right_steps:
        JSR move_right                  ; $24A1  two steps right
        JSR move_right                  ; $24A4  the second
        LDA #$00                        ; $24A7  0
        STA facing,X                    ; $24A9  facing left again
        LDA #$13                        ; $24AB  still the knockdown
        JMP keep_state                  ; $24AD  timer one less
knockdown_done:
        JMP stand_down                  ; $24B0  stand
state_stuck:
        CMP #$18                        ; $24B3  pushed out?
        BNE keep_state                  ; $24B5  no: keep A's state
; State $18 with the timer still running. release_hold jumps here and
; does not call actor_tick. Bit 3 clear stores 1 in $52 and keep_state
; decrements it, so the timer becomes 0 and the state stays $18. The
; next frame the timer is 0, push_out does not take this branch, and
; actor_tick clears the state. enemy_turn starts the chase on the
; frame after that. Bit 3 still set ORs the older counters from $4F63,
; stride 3, forty times. Any of them set is another undo. None set
; forces $51 to 0 and re-enters the current room on Bruce's spawn.
; That is finish_exit, not lose_life.
while_stuck:
        LDA hit,X                       ; $24B7  the full hit
        AND #$08                        ; $24B9  wall?
        BNE stuck_check_history         ; $24BB  yes: look back further
        LDA #$01                        ; $24BD  1
        STA $52                         ; $24BF  so keep_state stores timer 0
        LDA #$18                        ; $24C1  still pushed out
        JMP keep_state                  ; $24C3  timer 0
stuck_check_history:
        TXA                             ; $24C6  keep the actor
        PHA                             ; $24C7  kept
        LDA #$00                        ; $24C8  no step yet
        LDY #$27                        ; $24CA  40 counters
stuck_or_history:
        ORA $4F63,X                     ; $24CC  one, from the generation before
        INX                             ; $24CF  three bytes on
        INX                             ; $24D0  the same actor
        INX                             ; $24D1  three bytes on: the same actor
        DEY                             ; $24D2  one fewer
        BPL stuck_or_history            ; $24D3  more
        TAY                             ; $24D5  the OR
        PLA                             ; $24D6  the actor
        TAX                             ; $24D7  the actor back
        TYA                             ; $24D8  the OR again
        BNE undo_again                  ; $24D9  an older step: undo it
; Same registers as enter_room_at, for the room already in $29. finish_exit
; places him on that room's spawn. enter_room then runs, so room 11 can
; still open room 13 when rooms 12, 14, and 16 are clear. $51 is 0, so
; the life counter is not touched.
stuck_reenter:
        LDA #$00                        ; $24DB  zero
        STA $51                         ; $24DD  no life lost
        LDX $29                         ; $24DF  this room
        STX $4E                         ; $24E1  the room for finish_exit
        LDA $4BC2,X                     ; $24E3  its spawn ypos
        TAY                             ; $24E6  kept
        LDA $4BAE,X                     ; $24E7  its spawn xpos
        JMP finish_exit                 ; $24EA  put Bruce there and enter the room again
; An older counter was still set. $4C keeps the facing, and the undo
; runs again on this frame.
undo_again:
        LDA facing,X                    ; $24ED  his facing
        STA $4C                         ; $24EF  kept
        JMP undo_steps                  ; $24F1  walk the next generation back

; A is the state to keep. $52 still holds the timer from the start of move_for_state. It is
; decremented here and stored back to timer,X.
keep_state:
        STA state,X                     ; $24F4  the state
        TAY                             ; $24F6  the index
        LDA $4A8C,Y                     ; $24F7  its picture hold
        STA $0106,X                     ; $24FA  stored
        DEC $52                         ; Decrement after the state has used the old value.
        LDA $52                         ; $24FF  the timer, one less
        STA timer,X                     ; $2501  stored
        RTS                             ; $2503  back

; Leave the script. State 0, timer 0. A sideways jump that has started to fall uses this
; when it meets the ground.
land:
        LDA #$00                        ; $2504  state 0
        JMP set_state                   ; $2506  and return from there
; Y is $80-$8E. $D418 is set to $15 first: volume 5, with the lowpass
; bit. Effects leave $D417 at 0, so that bit routes nothing.
; The first free slot wins: $EB00, then $EF70, then $F070. The id's
; low nibble indexes the priority at $2572, stored at $2581, $2582,
; or $2583. When every slot is busy, the new priority replaces the
; first slot whose stored priority is lower or equal. The compare is
; BCS, so an equal priority replaces. A zero id means the slot is free.
; Bit 7 of the id means start. The voice clears it on the next call
; and runs the first command on that same call.
play_sound:
        LDA #$15                        ; $2509  volume 5, the lowpass bit
        STA $D418                       ; $250B  SID volume and filter mode
        LDA $EB00                       ; $250E  slot 1 busy?
        BNE play_sound_try_2            ; $2511  yes: try slot 2
; Y goes into slot 1, $EB00, and the priority for its low nibble goes to $2581.
claim_voice_1:
        STY $EB00                       ; $2513  claim slot 1. Bit 7 of the id starts it
        TYA                             ; $2516  the id
        AND #$0F                        ; $2517  the id's low nibble
        TAX                             ; $2519  the index
        LDA $2572,X                     ; $251A  its priority
        STA $2581                       ; $251D  kept for slot 1
        RTS                             ; $2520  back
play_sound_try_2:
        LDA $EF70                       ; $2521  slot 2 busy?
        BNE play_sound_try_3            ; $2524  yes: try slot 3
; The same for slot 2, $EF70, with the priority at $2582.
claim_voice_2:
        STY $EF70                       ; $2526  claim slot 2
        TYA                             ; $2529  the id
        AND #$0F                        ; $252A  the id's low nibble
        TAX                             ; $252C  the index
        LDA $2572,X                     ; $252D  its priority
        STA $2582                       ; $2530  kept for slot 2
        RTS                             ; $2533  back
play_sound_try_3:
        LDA $F070                       ; $2534  slot 3 busy?
        BNE play_sound_replace          ; $2537  yes: all three are busy
; The same for slot 3, $F070, with the priority at $2583.
claim_voice_3:
        STY $F070                       ; $2539  claim slot 3
        TYA                             ; $253C  the id
        AND #$0F                        ; $253D  the id's low nibble
        TAX                             ; $253F  the index
        LDA $2572,X                     ; $2540  its priority
        STA $2583                       ; $2543  kept for slot 3
        RTS                             ; $2546  back
play_sound_replace:
        TYA                             ; $2547  the id
        AND #$0F                        ; $2548  the id's low nibble
        TAX                             ; $254A  the index
        LDA $2572,X                     ; $254B  the new priority
        CMP $2581                       ; $254E  at least slot 1's?
        BCS claim_voice_1               ; $2551  then it replaces slot 1
        CMP $2582                       ; $2553  at least slot 2's?
        BCS claim_voice_2               ; $2556  then it replaces slot 2
        CMP $2583                       ; $2558  at least slot 3's?
        BCS claim_voice_3               ; $255B  then it replaces slot 3
        RTS                             ; $255D  lower than all three: dropped
; Zero the three effect slots, then $D400 through $D420. X starts at
; $20 and the write happens before DEX, so the last store is past the
; SID. Called from enter_room, between_rooms, clear_work_ram, and
; lose_life. It does not run the tune player.
silence_sid:
        LDA #$00                        ; $255E  zero
        STA $EB00                       ; $2560  free slot 1
        STA $EF70                       ; $2563  free slot 2
        STA $F070                       ; $2566  free slot 3
        LDX #$20                        ; $2569  $D420 down to $D400
silence_sid_loop:
        STA $D400,X                     ; $256B  SID voice 1 frequency low, plus X
        DEX                             ; $256E  the next register
        BPL silence_sid_loop            ; $256F  more
        RTS                             ; $2571  back

; $2572  15 priority bytes, low nibbles 0 through $0E:
; 0B 0C 0A 00 08 07 09 06 00 00 01 02 03 04 05.
; $2581, $2582, $2583 are the live priorities of the three slots.
; Nibble $0F is not an effect id. That lookup would read $2581.

; For each active actor, copy his two sprite images into the hardware image slots.
blit_sprites:
        LDX #$02                        ; $2584  the ninja first
blit_loop:
        STX $51                         ; $2586  the actor
        LDA active,X                    ; $2588  active
        AND #$01                        ; $258A  in the room?
        BEQ blit_next                   ; $258C  no
        LDA $276D,X                     ; $258E  his first sprite
        JSR blit_target                 ; $2591  its image buffer
        LDA $4F4E,X                     ; $2594  his library
        TAX                             ; $2597  the index
        JSR load_library                ; $2598  pointer, height, color
        PHA                             ; $259B  the color
        TXA                             ; $259C  the shift byte
        LDX $51                         ; $259D  the actor
        STA $D4,X                       ; $259F  kept: the first sprite's shift byte
        PLA                             ; $25A1  the color
        STA $DA,X                       ; $25A2  the first sprite's color
        TYA                             ; $25A4  the height
        ASL A                           ; $25A5  times 2
        ADC $E0,X                       ; $25A6  plus the height: three bytes a row
        TAY                             ; $25A8  the last byte of the picture
        LDA $D4,X                       ; $25A9  the shift byte: 0 copies one byte a row
        JSR copy_sprite_image           ; $25AB  copy the picture
        LDX $51                         ; $25AE  the actor
; Actor 2 stops here. In the room 0 snapshot $276D is 00 02 04 and $2770
; is 01 03 FF: Bruce is sprites 0 and 1, Yamo is 2 and 3, the ninja is
; sprite 4. The $FF also makes the BMI below skip a second image.
        CPX #$02                        ; $25B0  the ninja?
        BEQ blit_next                   ; $25B2  yes: one sprite
        LDA $2770,X                     ; $25B4  his second sprite
        BMI blit_next                   ; $25B7  none
        JSR blit_target                 ; $25B9  its image buffer
        LDA $4F4E,X                     ; $25BC  his library
        TAX                             ; $25BF  the index
        INX                             ; $25C0  the next library: the second picture
        JSR load_library                ; $25C1  pointer, height, color
        PHA                             ; $25C4  the color
        TXA                             ; $25C5  the shift byte
        LDX $51                         ; $25C6  the actor
        STA $D7,X                       ; $25C8  kept: the second sprite's shift byte
        PLA                             ; $25CA  the color
        STA $DD,X                       ; $25CB  the second sprite's color
        TYA                             ; $25CD  the height
        ASL A                           ; $25CE  times 2
        ADC $E0,X                       ; $25CF  plus the height
        TAY                             ; $25D1  the last byte
        LDA $D7,X                       ; $25D2  the shift byte
        JSR copy_sprite_image           ; $25D4  copy the picture
blit_next:
        LDX $51                         ; $25D7  the actor
        DEX                             ; $25D9  the next one
        BPL blit_loop                   ; $25DA  more
        LDA #$00                        ; $25DC  zero
        STA $277E                       ; $25DE  place_sprites may write again
        RTS                             ; $25E1  back

; Hardware sprite positions. irq_service calls this every frame. blit_sprites
; clears $277E after copying images, and a nonzero $277E skips the write.
; Collision keeps testing the unshifted xpos.
;
; The body's hardware X is xpos times two, the expanded sprite coordinate.
; $D4,X is the $5CBF byte load_library returned. When it is nonzero and facing is
; left, 8 is subtracted first, so the picture is drawn 16 screen pixels to
; the left of the collision box. Yamo's relative libraries $18 and $3E
; are nonzero there, and Bruce's copies of those two are zero, so the
; extended left kick and the late left knockdown slide for Yamo only.
; The ninja's relative $32, $36, $38, $3A, $3C, and $3E hold $55. Any nonzero
; byte takes this shift. The second sprite does that subtract when its
; library, $4F4B,X, is $05, $3F, $43, or $19: punch left, the late left
; knockdown, duck right, and the extended left kick. Actor 2 has no second
; sprite here. The hardware Y of both sprites is ypos+$1D. The carry out of
; the ASL is that sprite's bit in $D010.
;
; The five pointers at $8FF8-$8FFC come from $2763, or from $2768 when $277D
; is set. $277D flips on every call that gets this far.
place_sprites:
        LDA $277E                       ; $25E2  written since the last blit?
        BEQ place_sprites_go            ; $25E5  no
        RTS                             ; $25E7  yes: back
place_sprites_go:
        INC $277E                       ; $25E8  written
        LDX #$02                        ; $25EB  the ninja first
        STX $51                         ; $25ED  the actor
place_loop:
        LDA active,X                    ; $25EF  active
        AND #$01                        ; $25F1  in the room?
        BEQ place_second                ; $25F3  no
        LDA xpos,X                      ; $25F5  xpos
        STA $B9,X                       ; $25F7  the xpos the sprites show
        LDY $D4,X                       ; $25F9  the shift byte
        BEQ place_first_x               ; $25FB  0: no shift
        LDY facing,X                    ; $25FD  his facing
        CPY #$01                        ; $25FF  right?
        BEQ place_first_x               ; $2601  yes: no shift
        SEC                             ; $2603  the borrow
        SBC #$08                        ; $2604  eight steps left, 16 pixels
place_first_x:
        ASL A                           ; $2606  screen x, bit 8 into carry
        PHA                             ; $2607  kept
        LDY $276D,X                     ; $2608  his first sprite
        LDA $D010                       ; $260B  sprite x bit 8
        BCC place_first_clear_high      ; $260E  bit 8 clear
        ORA $2773,Y                     ; $2610  this sprite's bit
        BNE place_first_store_high      ; $2613  always
place_first_clear_high:
        AND $2778,Y                     ; $2615  without this sprite's bit
place_first_store_high:
        STA $D010                       ; $2618  sprite x bit 8
        TYA                             ; $261B  the sprite
        ASL A                           ; $261C  times 2
        TAY                             ; $261D  its register pair
        PLA                             ; $261E  screen x
        STA $D000,Y                     ; $261F  sprite 0 x, plus Y
        LDA ypos,X                      ; $2622  ypos
        CLC                             ; $2624  carry clear
        ADC #$1D                        ; $2625  plus $1D
        STA $D001,Y                     ; $2627  sprite 0 y, plus Y
        LDY $276D,X                     ; $262A  his first sprite
        LDA $DA,X                       ; $262D  its color
        STA $D027,Y                     ; $262F  sprite 0 color, plus Y
place_first_done:
        CPX #$02                        ; $2632  the ninja?
place_second:
        BEQ place_next                  ; $2634  yes: no second sprite
        LDY $4F4B,X                     ; $2636  his second library
        LDA xpos,X                      ; $2639  xpos
        CPY #$05                        ; $263B  punch left?
        BEQ place_second_shift          ; $263D  yes: shift
        CPY #$3F                        ; $263F  the late left knockdown?
        BEQ place_second_shift          ; $2641  yes: shift
        CPY #$43                        ; $2643  duck right?
        BEQ place_second_shift          ; $2645  yes: shift
        CPY #$19                        ; $2647  the extended left kick?
        BNE place_second_x              ; $2649  no
place_second_shift:
        SEC                             ; $264B  the borrow
        SBC #$08                        ; $264C  eight steps left, 16 pixels
place_second_x:
        ASL A                           ; $264E  screen x, bit 8 into carry
        PHA                             ; $264F  kept
        LDY $2770,X                     ; $2650  his second sprite
        LDA $D010                       ; $2653  sprite x bit 8
        BCC place_second_clear_high     ; $2656  bit 8 clear
        ORA $2773,Y                     ; $2658  this sprite's bit
        BNE place_second_store_high     ; $265B  always
place_second_clear_high:
        AND $2778,Y                     ; $265D  without this sprite's bit
place_second_store_high:
        STA $D010                       ; $2660  sprite x bit 8
        TYA                             ; $2663  the sprite
        ASL A                           ; $2664  times 2
        TAY                             ; $2665  its register pair
        PLA                             ; $2666  screen x
        STA $D000,Y                     ; $2667  sprite 0 x, plus Y
        LDA ypos,X                      ; $266A  ypos
        CLC                             ; $266C  carry clear
        ADC #$1D                        ; $266D  plus $1D
        STA $D001,Y                     ; $266F  sprite 0 y, plus Y
        LDY $2770,X                     ; $2672  his second sprite
        LDA $DD,X                       ; $2675  its color
        STA $D027,Y                     ; $2677  sprite 0 color, plus Y
place_next:
        LDX $51                         ; $267A  the actor
        DEX                             ; $267C  the next one
        BMI place_pointers              ; $267D  all three done
        JMP place_loop                  ; $267F  more
place_pointers:
        LDX #$04                        ; $2682  five pointers
        LDY #$04                        ; $2684  the first half's images
        LDA $277D                       ; $2686  which half?
        BEQ place_pointer_loop          ; $2689  the first
        LDY #$09                        ; $268B  the second half's images
place_pointer_loop:
        LDA $2763,Y                     ; $268D  an image number
        STA $8FF8,X                     ; $2690  a sprite pointer
        DEY                             ; $2693  the next image
        DEX                             ; $2694  the next sprite
        BPL place_pointer_loop          ; $2695  more
        LDA $277D                       ; $2697  the half
        EOR #$01                        ; $269A  the other one
        STA $277D                       ; $269C  next time
        RTS                             ; $269F  back


; Copy one image from the library at $6667 into the sprite buffer at ($0E). A zero in A
; means the buffer is cleared instead.
copy_sprite_image:
        BNE copy_wide                   ; $26A0  a wide picture
        LDA #$3F                        ; $26A2  64 bytes
        STA $277F                       ; $26A4  to write
        LDA $E0,X                       ; $26A7  the height
        TAX                             ; $26A9  the last source byte
copy_narrow_row:
        LDA $6667,X                     ; $26AA  one byte of the row. The operand is patched
        STA ($0E),Y                     ; $26AD  the left byte
        DEC $277F                       ; $26AF  one written
        DEX                             ; $26B2  the next source byte
        BMI copy_clear_rest             ; $26B3  none left: clear the rest
        DEY                             ; $26B5  the middle byte
        LDA #$00                        ; $26B6  blank
        STA ($0E),Y                     ; $26B8  written
        DEC $277F                       ; $26BA  one written
        DEY                             ; $26BD  the right byte
        STA ($0E),Y                     ; $26BE  blank
        DEC $277F                       ; $26C0  one written
        DEY                             ; $26C3  the row above
        BPL copy_narrow_row             ; $26C4  more
copy_clear_rest:
        LDA $277F                       ; $26C6  bytes left
        EOR #$3F                        ; $26C9  the first one not written
        TAY                             ; $26CB  the index
        LDA #$00                        ; $26CC  blank
copy_clear_loop:
        STA ($0E),Y                     ; $26CE  clear it
        INY                             ; $26D0  the next
        DEC $277F                       ; $26D1  one fewer
        BPL copy_clear_loop             ; $26D4  more
        RTS                             ; $26D6  back
copy_wide:
        LDA #$3F                        ; $26D7  64 bytes
        STA $277F                       ; $26D9  to write
        LDA $E0,X                       ; $26DC  the height
        ASL A                           ; $26DE  times 2
        TAX                             ; $26DF  the index
        DEX                             ; $26E0  the last source byte
        DEY                             ; $26E1  skip the right byte
        DEY                             ; $26E2  to the middle
copy_wide_row:
        LDA $6667,X                     ; $26E3  the right half of the row. The operand is patched
        STA ($0E),Y                     ; $26E6  the middle byte
        DEC $277F                       ; $26E8  one written
        DEX                             ; $26EB  the next source byte
        DEY                             ; $26EC  the left byte
        LDA $6667,X                     ; $26ED  the left half. The operand is patched
        STA ($0E),Y                     ; $26F0  the left byte
        DEC $277F                       ; $26F2  one written
        DEX                             ; $26F5  the next source byte
        BMI copy_clear_rest             ; $26F6  none left: clear the rest
        DEY                             ; $26F8  the right byte of the row above
        LDA #$00                        ; $26F9  blank
        STA ($0E),Y                     ; $26FB  written
        DEC $277F                       ; $26FD  one written
        DEY                             ; $2700  the middle byte
        BPL copy_wide_row               ; $2701  more
        BRK                             ; $2703  reached only if the buffer runs out before the picture
; A is a sprite slot. ($0E) becomes that slot's image address from
; $274F. $277D picks the half of the double buffer: when it is set the
; slot moves on ten entries, to the other set of images.
blit_target:
        ASL A                           ; $2704  times 2
        LDY $277D                       ; $2705  which half?
        BEQ blit_target_store           ; $2708  the first
        CLC                             ; $270A  carry clear
        ADC #$0A                        ; $270B  the other half
blit_target_store:
        TAY                             ; $270D  the index
        LDA $274F,Y                     ; $270E  the image address, low
        STA $0E                         ; $2711  ($0E)
        LDA $2750,Y                     ; $2713  high
        STA $0F                         ; $2716  ($0E)
        RTS                             ; $2718  back
; Library X: pointer from $59BD/$5A8F, height from $5B61, color from
; $5C33. A returns the color, Y the height, X the $5CBF byte. $51 = 2
; stores $F0 in place of the table color. The VIC takes the low nibble, so
; The ninja is black. Yamo's table bytes are $F5 then $F0, green under
; black, except relative $04, $06, $18, $1C, and $3E, where the first byte
; is $F0 and the second is $F5. Those are the two punches, the extended
; kicks, and the late left knockdown.
load_library:
        LDA $59BD,X                     ; $2719  the picture, low
        STA $26AB                       ; $271C  into the narrow copy
        STA $26E4                       ; $271F  into the wide copy, right half
        STA $26EE                       ; $2722  and left half
        LDA $5A8F,X                     ; $2725  the picture, high
        STA $26AC                       ; $2728  the narrow copy
        STA $26E5                       ; $272B  the wide copy, right half
        STA $26EF                       ; $272E  and left half
        LDY $5B61,X                     ; $2731  the height
        LDA #$02                        ; $2734  the ninja?
        CMP $51                         ; $2736  is the actor 2?
        BNE load_library_color          ; $2738  no
        LDA #$F0                        ; $273A  black
        BNE load_library_mode           ; $273C  always
load_library_color:
        LDA $5C33,X                     ; $273E  the table's color
load_library_mode:
        PHA                             ; $2741  kept
; X returns the $5CBF byte for this library. place_sprites shifts a
; left-facing body eight xpos when the byte is nonzero.
        LDA $5CBF,X                     ; $2742  the shift byte
        PHA                             ; $2745  kept
        LDX $51                         ; $2746  the actor
        TYA                             ; $2748  the height
        STA $E0,X                       ; $2749  kept
        PLA                             ; $274B  the shift byte
        TAX                             ; $274C  in X
        PLA                             ; $274D  the color in A
choose_pose_done:
        RTS                             ; $274E  back

; $274F  49 bytes, the sprite tables blit_sprites and place_sprites use.
;   $274F  ten words, the image addresses $8180-$83C0, 64 bytes apart.
;          blit_target picks one. The second half of the double buffer
;          is five words on.
;   $2763  ten image numbers, 06-0F, for the sprite pointers.
;   $276D  00 02 04, each actor's first sprite: Bruce 0, Yamo 2, ninja 4.
;   $2770  01 03 FF, each actor's second sprite. The ninja has none.
;   $2773  01 02 04 08 10, the $D015 bit of sprites 0-4.
;   $2778  FE FD FB F7 EF, the same bits inverted, to clear them.
;   $277D  which half of the double buffer is drawn, 0 or 1.
;   $277E  place_sprites' count.
;   $277F  copy_sprite_image's row count.

; Pick the library number from the state and the facing, then store_pose records it. Runs
; once per actor per step.
choose_pose:
        LDA $4FDB,X                     ; $2780  a picture already this step?
        BNE choose_pose_done            ; $2783  yes
        INC $4FDB,X                     ; $2785  one now
        LDA $4F48,X                     ; $2788  the library showing
        STA $4F54,X                     ; $278B  kept
        LDY facing,X                    ; $278E  the facing
        LDA state,X                     ; $2790  the state
; Fall. Bit 3 selects library 8, the legs together. Otherwise library $44,
; the arms. The two pictures do not cover the same cells. One pixel is
; enough for $44 to touch a wall that library 8 misses. Room 4's right lip
; is that case: see rooms.asm. $1CC7 then puts the pixel back.
        CMP #$0E                        ; $2792  the fall?
        BNE pose_duck                   ; $2794  no
        LDA hit,X                       ; $2796  the full hit
        AND #$08                        ; $2798  wall?
        BEQ pose_fall_arms              ; $279A  no: the arms
        LDY #$08                        ; $279C  legs together
        JMP store_pose                  ; $279E  store it
pose_fall_arms:
        LDY #$44                        ; $27A1  arms up
        JMP store_pose                  ; $27A3  store it
pose_duck:
        CMP #$1A                        ; $27A6  duck. Facing right is library $42, facing left is library $40.
        BNE pose_shocked                ; $27A8  no
        CPY #$01                        ; $27AA  right?
        BNE pose_duck_left              ; $27AC  no
        LDY #$42                        ; $27AE  facing right
        JMP store_pose                  ; $27B0  store it
pose_duck_left:
        LDY #$40                        ; $27B3  facing left
        JMP store_pose                  ; $27B5  store it
pose_shocked:
        CMP #$19                        ; $27B8  the shock?
        BNE pose_stuck                  ; $27BA  no
        LDY #$08                        ; $27BC  legs together
        JMP store_pose                  ; $27BE  store it
; State $18. The library already showing is kept, unless it is $44 or
; either mode byte is set, in which case library 8 replaces it. The
; walk pictures are chosen for states $14 and $15, so the run keeps
; cycling only while those states last. This state freezes the picture.
pose_stuck:
        CMP #$18                        ; $27C1  pushed out?
        BNE pose_landed_on              ; $27C3  no
        LDY $4F54,X                     ; $27C5  the library showing
        CPY #$44                        ; $27C8  the arms?
        BEQ pose_stuck_legs             ; $27CA  yes: the legs instead
        LDA $D4,X                       ; $27CC  either shift byte
        ORA $D7,X                       ; $27CE  ORed with the second sprite's
        BNE pose_stuck_legs             ; $27D0  set: the legs
        JMP store_pose                  ; $27D2  keep the picture
pose_stuck_legs:
        LDY #$08                        ; $27D5  legs together
        JMP store_pose                  ; $27D7  store it
pose_landed_on:
        CMP #$1B                        ; $27DA  stomped on?
        BNE pose_knockdown              ; $27DC  no
        LDA timer,X                     ; $27DE  the timer
        CPY #$00                        ; $27E0  facing left?
        BEQ pose_landed_left            ; $27E2  yes
        CMP #$04                        ; $27E4  below 4?
        BCC pose_landed_late_right      ; $27E6  yes: the late picture
        LDY #$38                        ; $27E8  early, right
        JMP store_pose                  ; $27EA  store it
pose_landed_late_right:
        LDY #$3A                        ; $27ED  late, right
        JMP store_pose                  ; $27EF  store it
pose_landed_left:
        CMP #$04                        ; $27F2  below 4?
        BCC pose_landed_late_left       ; $27F4  yes: the late picture
        LDY #$3C                        ; $27F6  early, left
        JMP store_pose                  ; $27F8  store it
pose_landed_late_left:
        LDY #$3E                        ; $27FB  late, left
        JMP store_pose                  ; $27FD  store it
pose_knockdown:
        CMP #$13                        ; $2800  the knockdown?
        BNE pose_yamo_rise              ; $2802  no
        LDA timer,X                     ; $2804  the timer
        CMP #$0A                        ; $2806  below 10?
        BCC pose_knockdown_late         ; $2808  yes: the late picture
        CPY #$00                        ; $280A  facing left?
        BNE pose_knockdown_right        ; $280C  no
        LDY #$3C                        ; $280E  early, left
        JMP store_pose                  ; $2810  store it
pose_knockdown_right:
        LDY #$38                        ; $2813  early, right
        JMP store_pose                  ; $2815  store it
pose_knockdown_late:
        CPY #$00                        ; $2818  facing left?
        BNE pose_knockdown_late_right   ; $281A  no
        LDY #$3E                        ; $281C  late, left
        JMP store_pose                  ; $281E  store it
pose_knockdown_late_right:
        LDY #$3A                        ; $2821  late, right
        JMP store_pose                  ; $2823  store it
pose_yamo_rise:
; State $10. Yamo's first picture, library $2A, both facings.
        CMP #$10                        ; $2826  Yamo's first picture?
        BNE pose_punch                  ; $2828  no
        LDY #$2A                        ; $282A  library $2A
        JMP store_pose                  ; $282C  store it
pose_punch:
        CMP #$11                        ; $282F  the punch?
        BNE pose_rising                 ; $2831  no
        CPY #$01                        ; $2833  right?
        BNE pose_punch_left             ; $2835  no
        LDY #$06                        ; $2837  punch right
        JMP store_pose                  ; $2839  store it
pose_punch_left:
        LDY #$04                        ; $283C  punch left
        JMP store_pose                  ; $283E  store it
pose_rising:
; State $12. Facing right is library $2E, facing left is $2C.
        CMP #$12                        ; $2841  Yamo's second picture?
        BNE pose_strike                 ; $2843  no
        CPY #$01                        ; $2845  right?
        BNE pose_rising_left            ; $2847  no
        LDY #$2E                        ; $2849  facing right
        JMP store_pose                  ; $284B  store it
pose_rising_left:
        LDY #$2C                        ; $284E  facing left
        JMP store_pose                  ; $2850  store it
pose_strike:
; State $16, the ninja's strike. Timer >= $0B is library $34 facing right and
; $30 facing left. Below $0B that is $36 and $32.
        CMP #$16                        ; $2853  the strike?
        BNE pose_flinch                 ; $2855  no
        LDA timer,X                     ; $2857  the timer
        CMP #$0B                        ; $2859  below $0B?
        BCC pose_strike_late            ; $285B  yes: the late picture
        CPY #$01                        ; $285D  right?
        BNE pose_strike_left            ; $285F  no
        LDY #$34                        ; $2861  early, right
        JMP store_pose                  ; $2863  store it
pose_strike_left:
        LDY #$30                        ; $2866  early, left
        JMP store_pose                  ; $2868  store it
pose_strike_late:
        CPY #$01                        ; $286B  right?
        BNE pose_strike_late_left       ; $286D  no
        LDY #$36                        ; $286F  late, right
        JMP store_pose                  ; $2871  store it
pose_strike_late_left:
        LDY #$32                        ; $2874  late, left
        JMP store_pose                  ; $2876  store it
pose_flinch:
        CMP #$0F                        ; $2879  the flinch?
        BNE pose_kick_left              ; $287B  no
        CPY #$01                        ; $287D  right?
        BNE pose_flinch_left            ; $287F  no
        LDY #$02                        ; $2881  standing, right
        JMP store_pose                  ; $2883  store it
pose_flinch_left:
        LDY #$00                        ; $2886  standing, left
        JMP store_pose                  ; $2888  store it

; Picture for flying kick left. Timer 10 or more is library $16 (tucked). The rest is
; library $18 (leg out).
pose_kick_left:
        CMP #$0C                        ; $288B  the kick left?
        BNE pose_kick_right             ; $288D  no
        LDA timer,X                     ; $288F  the timer
        CMP #$0A                        ; $2891  below 10?
        BCC pose_kick_left_out          ; $2893  yes: leg out
        LDY #$16                        ; $2895  tucked
        JMP store_pose                  ; $2897  store it
pose_kick_left_out:
        LDY #$18                        ; $289A  leg out
        JMP store_pose                  ; $289C  store it

; Picture for flying kick right. Libraries $1A and $1C.
pose_kick_right:
        CMP #$0D                        ; $289F  the kick right?
        BNE pose_chase                  ; $28A1  no
        LDA timer,X                     ; $28A3  the timer
        CMP #$0A                        ; $28A5  below 10?
        BCC pose_kick_right_out         ; $28A7  yes: leg out
        LDY #$1A                        ; $28A9  tucked
        JMP store_pose                  ; $28AB  store it
pose_kick_right_out:
        LDY #$1C                        ; $28AE  leg out
        JMP store_pose                  ; $28B0  store it
pose_chase:
        CMP #$14                        ; $28B3  the chase?
        BNE pose_sidestep               ; $28B5  no
        CPY #$01                        ; $28B7  right?
        BEQ pose_walk_right_test        ; $28B9  yes: walk right
        BNE pose_walk_left_test         ; $28BB  no: walk left
pose_sidestep:
        CMP #$15                        ; $28BD  the sidestep?
        BNE pose_walk_left              ; $28BF  no
        CPY #$01                        ; $28C1  right?
        BEQ pose_walk_right_test        ; $28C3  yes: walk right
        BNE pose_walk_left_test         ; $28C5  no: walk left
pose_walk_left:
        CMP #$03                        ; $28C7  walk left?
        BNE pose_walk_right             ; $28C9  no
pose_walk_left_test:
        LDA hit,X                       ; $28CB  the full hit
        AND #$04                        ; $28CD  ladder?
        BEQ pose_walk_left_cycle        ; $28CF  no
        JMP flip_climb                  ; $28D1  a climb picture
pose_walk_left_cycle:
        LDY $4F48,X                     ; $28D4  the last picture
        CPY #$0E                        ; $28D7  the first walk frame?
        BEQ pose_walk_left_second       ; $28D9  yes: the second
        LDY #$0E                        ; $28DB  the first, left
        JMP store_pose                  ; $28DD  store it
pose_walk_left_second:
        LDY #$10                        ; $28E0  the second, left
        JMP store_pose                  ; $28E2  store it
pose_walk_right:
        CMP #$04                        ; $28E5  walk right?
        BNE pose_jump                   ; $28E7  no
pose_walk_right_test:
        LDA hit,X                       ; $28E9  the full hit
        AND #$04                        ; $28EB  ladder?
        BEQ pose_walk_right_cycle       ; $28ED  no
        JMP flip_climb                  ; $28EF  a climb picture
pose_walk_right_cycle:
        LDY $4F48,X                     ; $28F2  the last picture
        CPY #$12                        ; $28F5  the first walk frame?
        BEQ pose_walk_right_second      ; $28F7  yes: the second
        LDY #$12                        ; $28F9  the first, right
        JMP store_pose                  ; $28FB  store it
pose_walk_right_second:
        LDY #$14                        ; $28FE  the second, right
        JMP store_pose                  ; $2900  store it

; Picture for the standing jump, state 5. Timer 15 is library 8 (legs together). 12 through
; 14 are library $1E. 2 through 11 are library $20. Timer 1 is library $1E again, and 0 is
; library 8.
pose_jump:
        CMP #$05                        ; $2903  the standing jump?
        BNE pose_side_left              ; $2905  no
        LDY timer,X                     ; $2907  the timer
        CPY #$0F                        ; $2909  below 15?
        BCC pose_jump_tuck              ; $290B  yes
        LDY #$08                        ; $290D  legs together
        JMP store_pose                  ; $290F  store it
pose_jump_tuck:
        CPY #$0C                        ; $2912  below 12?
        BCC pose_jump_mid               ; $2914  yes
        LDY #$1E                        ; $2916  tucked
        JMP store_pose                  ; $2918  store it
pose_jump_mid:
        CPY #$02                        ; $291B  below 2?
        BCC pose_jump_end               ; $291D  yes
        LDY #$20                        ; $291F  high
        JMP store_pose                  ; $2921  store it
pose_jump_end:
        CPY #$01                        ; $2924  0?
        BCC pose_jump_legs              ; $2926  yes
        LDY #$1E                        ; $2928  tucked
        JMP store_pose                  ; $292A  store it
pose_jump_legs:
        LDY #$08                        ; $292D  legs together
        JMP store_pose                  ; $292F  store it

; Picture for sideways jump left, state 6. Timer 12 or more, and timers 0, 1 and 2, are
; library $22. The counts between are library $24.
pose_side_left:
        CMP #$06                        ; $2932  the jump left?
        BNE pose_side_right             ; $2934  no
        LDY timer,X                     ; $2936  the timer
        CPY #$0C                        ; $2938  below 12?
        BCC pose_side_left_mid          ; $293A  yes
pose_side_left_tuck:
        LDY #$22                        ; $293C  tucked
        JMP store_pose                  ; $293E  store it
pose_side_left_mid:
        CPY #$03                        ; $2941  below 3?
        BCC pose_side_left_tuck         ; $2943  yes: tucked
        LDY #$24                        ; $2945  stretched
        JMP store_pose                  ; $2947  store it

; Picture for sideways jump right, state 7. Libraries $26 and $28.
pose_side_right:
        CMP #$07                        ; $294A  the jump right?
        BNE pose_carry                  ; $294C  no
        LDY timer,X                     ; $294E  the timer
        CPY #$0C                        ; $2950  below 12?
        BCC pose_side_right_mid         ; $2952  yes
pose_side_right_tuck:
        LDY #$26                        ; $2954  tucked
        JMP store_pose                  ; $2956  store it
pose_side_right_mid:
        CPY #$03                        ; $2959  below 3?
        BCC pose_side_right_tuck        ; $295B  yes: tucked
        LDY #$28                        ; $295D  stretched
        JMP store_pose                  ; $295F  store it
; State $17. $4F54 is the library stored last time. $AA still set means
; this frame did not take its own step, and that library is kept. $AA
; clear falls into flip_climb. The surface shove does not change $AA.
pose_carry:
        CMP #$17                        ; $2962  on the surface?
        BNE pose_stand                  ; $2964  no
        LDY $4F54,X                     ; $2966  the last picture
        LDA $AA,X                       ; $2969  his own step taken?
        BEQ flip_climb                  ; $296B  yes: flip the climb
        JMP store_pose                  ; $296D  no: keep it
; State 0. On a ladder, $0A or $0C stays up. Any other picture on a
; ladder, and every state not named above, falls into flip_climb. Off
; the ladder, facing left is library 0 and facing right is library 2.
pose_stand:
        CMP #$00                        ; $2970  standing?
        BNE flip_climb                  ; $2972  no: a climb picture
        LDA hit,X                       ; $2974  the full hit
        AND #$04                        ; $2976  ladder?
        BEQ pose_stand_floor            ; $2978  no
        LDY $4F54,X                     ; $297A  the last picture
        CPY #$0A                        ; $297D  climb 1?
        BEQ pose_keep_climb             ; $297F  yes: keep it
        CPY #$0C                        ; $2981  climb 2?
        BEQ pose_keep_climb             ; $2983  yes: keep it
; Libraries $0A and $0C, the two climb pictures. $0A is showing, so the
; next one is $0C. Anything else becomes $0A. State $17 reaches this only
; on the frame his own step shifted $AA to 0. A walk that overlaps a
; ladder jumps here too. State 0 on a ladder keeps $0A or $0C, and only
; arrives here when the picture is neither. A state choose_pose does not
; name falls through to here as well, and the climbs are that case.
flip_climb:
        LDY $4F54,X                     ; $2985  the last picture
        CPY #$0A                        ; $2988  climb 1?
        BEQ flip_climb_second           ; $298A  yes: climb 2
        LDY #$0A                        ; $298C  climb 1
pose_keep_climb:
        JMP store_pose                  ; $298E  store it
flip_climb_second:
        LDY #$0C                        ; $2991  climb 2
        JMP store_pose                  ; $2993  store it
pose_stand_floor:
        CPY #$01                        ; $2996  right?
        BEQ pose_stand_right            ; $2998  yes
        LDY #$00                        ; $299A  standing, left
        JMP store_pose                  ; $299C  store it
pose_stand_right:
        LDY #$02                        ; $299F  standing, right

; Y is the relative library. It is kept at $4F48, and the next one at $4F4B.
; Three rolls of active,X pick the base in $59A5. Room 0 holds 00 8C 46 04,
; and $01, $41, and $81 select the first three. The sum is the absolute
; library blit_sprites reads from $4F4E. The following absolute library is
; $4F51. Carry into the rolls does not change those three results.
store_pose:
        TYA                             ; $29A1  the relative library
        STA $4F48,X                     ; $29A2  kept
        CLC                             ; $29A5  carry clear
        ADC #$01                        ; $29A6  the next one
        STA $4F4B,X                     ; $29A8  the second picture
        LDA active,X                    ; $29AB  active
        ROL A                           ; $29AD  rolled
        ROL A                           ; $29AE  rolled
        ROL A                           ; $29AF  bits 7 and 6 at the bottom
        AND #$03                        ; $29B0  0, 1, or 2
        TAY                             ; $29B2  the actor's column
        LDA $59A5,Y                     ; $29B3  his base
        CLC                             ; $29B6  carry clear
        ADC $4F48,X                     ; $29B7  plus the relative library
        STA $4F4E,X                     ; $29BA  the absolute library
        ADC #$01                        ; $29BD  the next one. Carry is clear
        STA $4F51,X                     ; $29BF  the second picture
        RTS                             ; $29C2  back
; Clear $B3 and $BC, then read the VIC sprite-sprite register $D01E. A hit is kept in $67.
read_sprite_hits:
        LDA #$00                        ; $29C3  zero
        LDX #$02                        ; $29C5  three actors
sprite_hits_clear:
        STA $B3,X                       ; $29C7  sprite-hit bits
        STA $BC,X                       ; $29C9  blow bits
        DEX                             ; $29CB  the next
        BPL sprite_hits_clear           ; $29CC  more
        LDA $D01E                       ; $29CE  sprite-sprite contacts. Reading clears it
        BNE sprite_hits_bruce           ; $29D1  a contact
        RTS                             ; $29D3  none: back
sprite_hits_bruce:
        STA $67                         ; $29D4  kept
        AND #$03                        ; $29D6  Bruce's two sprites?
        BNE sprite_hits_bruce_yamo      ; $29D8  yes
        JMP sprite_hits_yamo_ninja      ; $29DA  no: Yamo and the ninja
sprite_hits_bruce_yamo:
        LDA $67                         ; $29DD  the contacts
        AND #$0C                        ; $29DF  Yamo's two sprites?
; The trainer's second question writes $09 over this branch offset. The
; branch then lands on LDA $B4, so the ORA #$08 into $B3 is skipped and the
; Yamo's own hit bit is still stored. $B3 is Bruce's sprite-hit bits.
; $29F7 is the ninja's pair, and $09 there lands on LDA $B5. The swing itself
; was chosen earlier. This only drops Bruce's recorded contact, so he never
; flinches, and a blow he lands on either fighter is still recorded.
        BNE sprite_hits_mark_yamo       ; $29E1  yes
        JMP sprite_hits_bruce_ninja     ; $29E3  no: Bruce and the ninja
sprite_hits_mark_yamo:
        LDA $B3                         ; $29E6  Bruce's bits
        ORA #$08                        ; $29E8  Yamo touches him
        STA $B3                         ; $29EA  stored
        LDA $B4                         ; $29EC  Yamo's bits
        ORA #$02                        ; $29EE  Bruce touches him
        STA $B4                         ; $29F0  stored
sprite_hits_bruce_ninja:
        LDA $67                         ; $29F2  the contacts
        AND #$30                        ; $29F4  the ninja's sprite?
; Same patch. Offset $09 lands on LDA $B5, so the ninja's hit bit is still stored.
        BNE sprite_hits_mark_ninja      ; $29F6  yes
        JMP sprite_hits_yamo_ninja      ; $29F8  no: Yamo and the ninja
sprite_hits_mark_ninja:
        LDA $B3                         ; $29FB  Bruce's bits
        ORA #$10                        ; $29FD  the ninja touches him
        STA $B3                         ; $29FF  stored
        LDA $B5                         ; $2A01  the ninja's bits
        ORA #$02                        ; $2A03  Bruce touches him
        STA $B5                         ; $2A05  stored
sprite_hits_yamo_ninja:
        LDA $67                         ; $2A07  the contacts
        AND #$0C                        ; $2A09  Yamo's sprites?
        BEQ sprite_hits_victims         ; $2A0B  no
        LDA $67                         ; $2A0D  the contacts
        AND #$30                        ; $2A0F  the ninja's sprite?
        BEQ sprite_hits_victims         ; $2A11  no
        LDA $B4                         ; $2A13  Yamo's bits
        ORA #$10                        ; $2A15  the ninja touches him
        STA $B4                         ; $2A17  stored
        LDA $B5                         ; $2A19  the ninja's bits
        ORA #$08                        ; $2A1B  Yamo touches him
        STA $B5                         ; $2A1D  stored
sprite_hits_victims:
        LDX #$02                        ; $2A1F  the ninja first
sprite_hits_victim_loop:
        LDA $B3,X                       ; $2A21  his sprite-hit bits
        STA $4C                         ; $2A23  shifted out one at a time
        LDY #$00                        ; $2A25  bit 0 first
sprite_hits_bit_loop:
        LSR $4C                         ; $2A27  the next bit
        BCS sprite_hits_contact         ; $2A29  set: a contact
sprite_hits_next_bit:
        INY                             ; $2A2B  the next bit number
        CPY #$05                        ; $2A2C  five bits?
        BCC sprite_hits_bit_loop        ; $2A2E  no
        DEX                             ; $2A30  the next victim
        BPL sprite_hits_victim_loop     ; $2A31  more
        JMP resolve_blows               ; $2A33  the blows
sprite_hits_contact:
        STY $52                         ; $2A36  the other actor's bit number
        LDA state,X                     ; $2A38  the victim's state
        CMP #$18                        ; $2A3A  pushed out?
        BEQ sprite_hits_next_bit        ; $2A3C  yes: no blow
        CMP #$1A                        ; $2A3E  ducking?
        BEQ sprite_hits_next_bit        ; $2A40  yes: no blow
        CMP #$0F                        ; $2A42  flinching?
        BEQ sprite_hits_next_bit        ; $2A44  yes: no blow
        CMP #$13                        ; $2A46  knocked down?
        BEQ sprite_hits_next_bit        ; $2A48  yes: no blow
        CMP #$19                        ; $2A4A  shocked?
        BEQ sprite_hits_next_bit        ; $2A4C  yes: no blow
        CMP #$1B                        ; $2A4E  stomped on?
        BEQ sprite_hits_next_bit        ; $2A50  yes: no blow
        LDA $4F40,Y                     ; $2A52  who owns the touching sprite
        BMI sprite_hits_no_blow         ; $2A55  nobody
        TAY                             ; $2A57  the attacker
        LDA $00BF,Y                     ; $2A58  his state
        CMP #$1B                        ; $2A5B  stomped on himself?
        BEQ sprite_hits_no_blow         ; $2A5D  yes: no blow
        CMP #$16                        ; $2A5F  the strike?
        BEQ blow_strike                 ; $2A61  yes
        CMP #$11                        ; $2A63  the punch?
        BEQ blow_punch                  ; $2A65  yes
        CMP #$0D                        ; $2A67  the kick right?
        BEQ blow_kick                   ; $2A69  yes
        CMP #$0C                        ; $2A6B  the kick left?
        BEQ blow_kick                   ; $2A6D  yes
        CMP #$0E                        ; $2A6F  falling?
        BNE sprite_hits_no_blow         ; $2A71  no: no blow
        JMP blow_landing                ; $2A73  a landing
sprite_hits_no_blow:
        LDY $52                         ; $2A76  the bit number back
        JMP sprite_hits_next_bit        ; $2A78  the next bit
blow_strike:
        LDA $00CE,Y                     ; $2A7B  the attacker's timer
        CMP #$08                        ; $2A7E  8 or more?
        BCS sprite_hits_no_blow         ; $2A80  yes: too early
        LDA #$04                        ; $2A82  reach 4
        STA $61                         ; $2A84  for reach_test
        JSR reach_test                  ; $2A86  in front of him and close?
        BCC sprite_hits_no_blow         ; $2A89  too close
        BMI sprite_hits_no_blow         ; $2A8B  behind him
        TXA                             ; $2A8D  keep X
        PHA                             ; $2A8E  kept
        TYA                             ; $2A8F  keep Y
        PHA                             ; $2A90  kept
; Effect $87, the strike connect. Blow 2. A punch, a kick, and a
; landing go to hit_sound instead.
        LDY #$87                        ; $2A91  effect $87
        JSR play_sound                  ; $2A93  queue it
        PLA                             ; $2A96  Y back
        TAY                             ; $2A97  into Y
        PLA                             ; $2A98  X back
        TAX                             ; $2A99  into X
        JSR mark_swing                  ; $2A9A  mark the swing, turn the victim
        LDA $BC,X                       ; $2A9D  the victim's blow bits
        ORA #$02                        ; $2A9F  the strike
        STA $BC,X                       ; $2AA1  stored
        BNE sprite_hits_no_blow         ; $2AA3  always
blow_punch:
        LDA #$06                        ; $2AA5  reach 6
        STA $61                         ; $2AA7  for reach_test
        JSR reach_test                  ; $2AA9  in front of him and close?
        BCC sprite_hits_no_blow         ; $2AAC  too close
        BMI sprite_hits_no_blow         ; $2AAE  behind him
        LDA $00A1,Y                     ; $2AB0  the attacker's ypos
        SEC                             ; $2AB3  the borrow
        SBC ypos,X                      ; $2AB4  less the victim's
        BPL blow_punch_height           ; $2AB6  not negative
        EOR #$FF                        ; $2AB8  negated
        ADC #$01                        ; $2ABA  the size
blow_punch_height:
        CMP #$16                        ; $2ABC  $16 or more apart?
        BCS sprite_hits_no_blow         ; $2ABE  yes: no blow
        JSR hit_sound                   ; $2AC0  effect $86
        JSR mark_swing                  ; $2AC3  mark the swing, turn the victim
        LDA $BC,X                       ; $2AC6  the victim's blow bits
        ORA #$04                        ; $2AC8  the punch
        CPY #$00                        ; $2ACA  Bruce's?
        BNE blow_punch_store            ; $2ACC  no
        ORA #$80                        ; $2ACE  yes: points
blow_punch_store:
        STA $BC,X                       ; $2AD0  stored
        BNE sprite_hits_no_blow         ; $2AD2  always
blow_kick:
        LDA $00CE,Y                     ; $2AD4  the attacker's timer
        CMP #$0A                        ; $2AD7  10 or more?
        BCS blow_done                   ; $2AD9  yes: still tucked
        LDA #$06                        ; $2ADB  reach 6
        STA $61                         ; $2ADD  for reach_test
        JSR reach_test                  ; $2ADF  in front of him and close?
        BCC blow_done                   ; $2AE2  too close
        BMI blow_done                   ; $2AE4  behind him
        JSR hit_sound                   ; $2AE6  effect $86
        JSR mark_swing                  ; $2AE9  mark the swing, turn the victim
        LDA $BC,X                       ; $2AEC  the victim's blow bits
        ORA #$08                        ; $2AEE  the kick
        CPY #$00                        ; $2AF0  Bruce's?
        BNE blow_kick_store             ; $2AF2  no
        ORA #$80                        ; $2AF4  yes: points
blow_kick_store:
        STA $BC,X                       ; $2AF6  stored
        BNE blow_done                   ; $2AF8  always
blow_landing:
        LDA ypos,X                      ; $2AFA  the victim's ypos
        SEC                             ; $2AFC  the borrow
        SBC $00A1,Y                     ; $2AFD  less the attacker's
        CMP #$0A                        ; $2B00  10 or more?
        BMI blow_done                   ; $2B02  the attacker is lower
        BCC blow_done                   ; $2B04  too close in height
        LDA $4F45,Y                     ; $2B06  the attacker's landings left
        BEQ blow_done                   ; $2B09  none
        SEC                             ; $2B0B  the borrow
        SBC #$01                        ; $2B0C  one fewer
        STA $4F45,Y                     ; $2B0E  stored
        LDA $BC,X                       ; $2B11  the victim's blow bits
        AND #$10                        ; $2B13  a landing already?
        BNE blow_done                   ; $2B15  yes
        LDA $00BC,Y                     ; $2B17  the attacker's blow bits
        AND #$10                        ; $2B1A  landed on himself?
        BNE blow_done                   ; $2B1C  yes
        LDA state,X                     ; $2B1E  the victim's state
        CMP #$0C                        ; $2B20  kicking left?
        BEQ blow_done                   ; $2B22  yes: no landing
        CMP #$0D                        ; $2B24  kicking right?
        BEQ blow_done                   ; $2B26  yes
        CMP #$11                        ; $2B28  punching?
        BEQ blow_done                   ; $2B2A  yes
        JSR hit_sound                   ; $2B2C  effect $86
        LDA $BC,X                       ; $2B2F  the victim's blow bits
        ORA #$10                        ; $2B31  the landing
        CPY #$00                        ; $2B33  Bruce's?
        BNE blow_landing_store          ; $2B35  no
        ORA #$80                        ; $2B37  yes: points
blow_landing_store:
        STA $BC,X                       ; $2B39  stored
blow_done:
        JMP sprite_hits_no_blow         ; $2B3B  the next bit
; Y is the attacker that connected, X the victim. Bit 0 of the attacker's
; $BC marks the blow for resolve_blows, and the victim turns to face him
; (the attacker's facing, flipped). A landing does not come here, so a
; stomp does not turn the victim round.
mark_swing:
        LDA $00BC,Y                     ; $2B3E  the attacker's blow bits
        ORA #$01                        ; $2B41  he swung
        STA $00BC,Y                     ; $2B43  stored
        LDA $00A4,Y                     ; $2B46  the attacker's facing
        EOR #$01                        ; $2B49  turned round
        STA facing,X                    ; $2B4B  the victim faces him
        RTS                             ; $2B4D  back
; One pass over the three actors, high X first. Bit 0 of $BC was set on
; the attacker by $2B3E. He leaves the attack for state 0. Bruce keeps
; timer $18. Another fighter keeps $18 on a short visit with $40 clear,
; stores $0A on a middle visit, and stores 2 on a long visit or when $40
; is set. The four blow tests then run in order, and a set bit is not
; cleared, so a later test still sees it.
resolve_blows:
        LDX #$02                        ; $2B4E  the ninja first
; X is the victim, saved in $51. The loop counts it down to 0.
resolve_actor:
        STX $51                         ; $2B50  the actor
        LDA $BC,X                       ; $2B52  his blow bits
        AND #$01                        ; $2B54  did he swing?
        BEQ strike_blow                 ; $2B56  no
        LDA #$00                        ; $2B58  zero
        STA state,X                     ; $2B5A  the attack ends
        LDA #$04                        ; $2B5C  hold the picture four frames
        STA $0106,X                     ; $2B5E  the picture hold
        LDA #$18                        ; $2B61  $18
        STA timer,X                     ; $2B63  timer
        INC $4FDB,X                     ; $2B65  choose_pose skips its turn
        TXA                             ; $2B68  Bruce?
        BEQ resolve_bruce_timer         ; $2B69  yes
        JSR test_visit                  ; $2B6B  how long Bruce has been in the room
        BVS resolve_enemy_long          ; $2B6E  long
        BCS resolve_enemy_middle        ; $2B70  middle
        LDA $40                         ; $2B72  a set $40?
        BNE resolve_enemy_long          ; $2B74  yes
        JMP strike_blow                 ; $2B76  short: $18
resolve_enemy_middle:
        LDA #$0A                        ; $2B79  10
        STA timer,X                     ; $2B7B  timer
        BNE strike_blow                 ; $2B7D  always
resolve_enemy_long:
        LDA #$02                        ; $2B7F  2
        STA timer,X                     ; $2B81  timer
resolve_bruce_timer:
        JSR test_visit                  ; $2B83  how long he has been in the room
        BVS resolve_bruce_long          ; $2B86  long
        BCS resolve_bruce_middle        ; $2B88  middle
        LDA #$03                        ; $2B8A  3
        STA timer,X                     ; $2B8C  timer
        BNE strike_blow                 ; $2B8E  always
resolve_bruce_middle:
        LDA #$08                        ; $2B90  8
        STA timer,X                     ; $2B92  timer
        BNE strike_blow                 ; $2B94  always
resolve_bruce_long:
        LDA #$0A                        ; $2B96  10
        STA timer,X                     ; $2B98  timer
; Bit 1. Two health, state $0F, timer 3. No points. A negative byte
; shares kick_result, whose first test is the knockdown.
strike_blow:
        LDA $BC,X                       ; $2B9A  his blow bits
        AND #$02                        ; $2B9C  the strike?
        BEQ punch_blow                  ; $2B9E  no
        LDA $D1,X                       ; $2BA0  health
        SEC                             ; $2BA2  the borrow
        SBC #$02                        ; $2BA3  less 2
        STA $D1,X                       ; $2BA5  stored
        BMI kick_result                 ; $2BA7  negative: the knockdown test
        LDA #$0F                        ; $2BA9  the flinch
        STA state,X                     ; $2BAB  state
        LDA #$03                        ; $2BAD  3
        STA timer,X                     ; $2BAF  timer
; Bit 2. $64 into the low score byte, 100, then 3 health. Bit 7 clear
; skips the points and still subtracts. Below zero is force_knockdown.
; A blow that stays positive is state $0F, timer 4.
punch_blow:
        LDA $BC,X                       ; $2BB1  his blow bits
        AND #$04                        ; $2BB3  the punch?
        BEQ kick_blow                   ; $2BB5  no
        LDA $BC,X                       ; $2BB7  his blow bits
        BPL punch_damage                ; $2BB9  not Bruce's: no points
        LDA #$64                        ; $2BBB  100
        LDX #$02                        ; $2BBD  into the low byte
        JSR add_score                   ; $2BBF  points
        LDX $51                         ; $2BC2  the victim
punch_damage:
        LDA $D1,X                       ; $2BC4  health
        SEC                             ; $2BC6  the borrow
        SBC #$03                        ; $2BC7  less 3
        STA $D1,X                       ; $2BC9  stored
        BMI force_knockdown             ; $2BCB  negative: knocked out
        LDA #$0F                        ; $2BCD  the flinch
        STA state,X                     ; $2BCF  state
        LDA #$04                        ; $2BD1  4
        STA timer,X                     ; $2BD3  timer
; Bit 3. $4B into the low score byte, 75, then 7 health. The same bit 7
; gate as the punch. Below zero is force_knockdown. A kick that stays
; positive still stores the knockdown pose, state $13, timer $0C.
kick_blow:
        LDA $BC,X                       ; $2BD5  his blow bits
        AND #$08                        ; $2BD7  the kick?
        BEQ landing_blow                ; $2BD9  no
        LDA $BC,X                       ; $2BDB  his blow bits
        BPL kick_damage                 ; $2BDD  not Bruce's: no points
        LDA #$4B                        ; $2BDF  75
        LDX #$02                        ; $2BE1  into the low byte
        JSR add_score                   ; $2BE3  points
        LDX $51                         ; $2BE6  the victim
kick_damage:
        LDA $D1,X                       ; $2BE8  health
        SEC                             ; $2BEA  the borrow
        SBC #$07                        ; $2BEB  less 7
        STA $D1,X                       ; $2BED  stored
; The kick's health, or the strike's when it went negative. Minus is the
; knockdown. Otherwise the kick pose, state $13, timer $0C. A strike that
; reaches here only through BMI never takes that store.
kick_result:
        BMI force_knockdown             ; $2BEF  negative: knocked out
        LDA #$13                        ; $2BF1  the knockdown
        STA state,X                     ; $2BF3  state
        LDA #$0C                        ; $2BF5  12
        STA timer,X                     ; $2BF7  timer
; Bit 4. $32 into the low score byte, 50, then 5 health. Bit 7 clear
; skips the points. Below zero is force_knockdown, and that routine
; jumps back here with the bit still set. A landing that stays positive
; is state $1B, timer 8, and that store is also how the bug loop ends.
landing_blow:
        LDA $BC,X                       ; $2BF9  his blow bits
        AND #$10                        ; $2BFB  a landing?
        BEQ resolve_next                ; $2BFD  no
        LDA $BC,X                       ; $2BFF  his blow bits
        BPL landing_damage              ; $2C01  not Bruce's: no points
        LDA #$32                        ; $2C03  50
        LDX #$02                        ; $2C05  into the low byte
        JSR add_score                   ; $2C07  points
        LDX $51                         ; $2C0A  the victim
; Bit 7 clear arrives here without the 50 points.
landing_damage:
        LDA $D1,X                       ; $2C0C  health
        SEC                             ; $2C0E  the borrow
        SBC #$05                        ; $2C0F  less 5
        STA $D1,X                       ; $2C11  stored
        BMI force_knockdown             ; $2C13  negative: knocked out
        LDA #$1B                        ; $2C15  stomped on
        STA state,X                     ; $2C17  state
        LDA #$08                        ; $2C19  8
        STA timer,X                     ; $2C1B  timer
resolve_next:
        DEX                             ; $2C1D  the next actor
        BMI resolve_done                ; $2C1E  all done
        JMP resolve_actor               ; $2C20  more
resolve_done:
        RTS                             ; $2C23  back
; $D1 just went negative. Punch, kick, and landing all arrive here.
; State $13, timer $0C, so the knockdown plays before check_bruce_down
; removes him. Bit 7 of $BC is set when the attacker was actor 0, and
; the kill score is skipped without it. Actor 1, the green fighter, adds
; $01 through the middle score byte and $C2 through the low byte, 450.
; Those are two adds, so the extra-fall test runs between them. Any other
; victim adds $C8 through the low byte, 200. Yamo is 450 and the ninja is 200.
;
; Intentional bug in the original. The jump below returns to landing_blow
; while bit 4 is still set. A landing that drove the health negative pays
; 50, subtracts 5, and comes back here for another knockout, then does
; that again. The health is one byte, so it wraps, and the loop stops on
; the first result in 0-127. That last pass stores state $1B with timer 8
; over this knockdown, and the fighter stays up. The ninja on 4 health ends at
; 125 after 27 landings and 26 knockouts, 6550 points. Yamo on 4 ends at
; 125 after the same count, 13050 points. Health 5 pays 50 once
; and stops at 0, because 0 is not negative. A killing punch or kick also
; jumps back, and the landing test continues only when bit 4 is set.
force_knockdown:
        LDA $BC,X                       ; $2C24  his blow bits
        AND #$80                        ; $2C26  Bruce's blow?
        BEQ store_knockdown             ; $2C28  no: no points
        STX $51                         ; $2C2A  the victim
        CPX #$01                        ; $2C2C  Yamo?
        BNE knockout_ninja              ; $2C2E  no
; Actor 1. $01 into byte 1, then $C2 into byte 2: 256 + 194 = 450.
knockout_yamo:
        LDA #$01                        ; $2C30  1
        TAX                             ; $2C32  into byte 1
        JSR add_score                   ; $2C33  256 points
        LDA #$C2                        ; $2C36  194
        LDX #$02                        ; $2C38  into the low byte
        JSR add_score                   ; $2C3A  450 in all
        JMP store_knockdown             ; $2C3D  the knockdown
; Not actor 1. The ninja takes this path. $C8 in the low byte is 200.
knockout_ninja:
        LDA #$C8                        ; $2C40  200
        LDX #$02                        ; $2C42  into the low byte
        JSR add_score                   ; $2C44  points
; Every knockdown, paid or not. State $13, timer $0C.
store_knockdown:
        LDX $51                         ; $2C47  the victim
        LDA #$13                        ; $2C49  the knockdown
        STA state,X                     ; $2C4B  state
        LDA #$0C                        ; $2C4D  12
        STA timer,X                     ; $2C4F  timer
; Bit 4 is still set, so a killing landing runs landing_blow again.
        JMP landing_blow                ; $2C51  the landing test again
; Y is the attacker, X the victim. A is the attacker's xpos minus the
; victim's, negated when the attacker faces right, so a positive A is in
; front of him. Carry set means A >= the reach in $61. Bit 7 means he is
; behind, or the gap is $80 or more. Callers treat carry clear or minus
; as a miss. The strike passes 4, the punch and the kick pass 6.
reach_test:
        LDA $009E,Y                     ; $2C54  the attacker's xpos
        SEC                             ; $2C57  the borrow
        SBC xpos,X                      ; $2C58  less the victim's
        PHA                             ; $2C5A  kept
        PHP                             ; $2C5B  and its flags
        LDA $00A4,Y                     ; $2C5C  the attacker's facing
        CMP #$01                        ; $2C5F  right?
        BNE reach_compare               ; $2C61  no
        PLP                             ; $2C63  drop the flags
        PLA                             ; $2C64  the difference
        EOR #$FF                        ; $2C65  negated
        ADC #$01                        ; $2C67  negated. Carry is set from the CMP
        PHA                             ; $2C69  kept
        PHP                             ; $2C6A  and its flags
reach_compare:
        PLP                             ; $2C6B  the flags
        PLA                             ; $2C6C  the difference
        CMP $61                         ; $2C6D  against the reach
        RTS                             ; $2C6F  back

; Scrolling surface. The per-frame hooks of rooms 4, 5, 6, 8, 9, and 11
; jump here. It rewrites glyphs $61, $62, and $63 and the shadow copies
; $E1, $E2, and $E3 in the charset on screen. Rooms below 10 read the 24
; bytes at $42F1 and write charset $A000. Room 11 reads the 24 bytes at
; $4309 and writes charset $A800. Eight bytes belong to each glyph.
; enter_room selects the bank with $D018 and does not expand it again, so
; a step written into a bank is still there when that bank is shown again.
; $64 is shared by both banks.
;
;   $60    countdown. $0818 stores 1, so the first call copies. Bit 7 is
;          the long pause: the low seven bits count down and the glyphs
;          stay put unless $66 has run out.
;   $64    which pattern byte is at the top of the glyph, kept across a
;          room change. The opening snapshot holds 0, the expanded picture.
;   $65    0 increments $64 and the picture moves up. Any other value
;          decrements $64 and the picture moves down. enter_room stores 0.
;          Wrapping the slot complements this byte, which is the reversal.
;          Room 4 stores 0 again when lamp $4D74 is taken. Room 8 stores 1
;          when lamp $4E04 is still present. Room 9 stores 1 on every frame
;          while lamp $4E09 is gone and $4E99 has not run out, and stores 0
;          when lamp $4E0D is taken and when the room's lamps are clear.
;          Room 11 stores 0 when lamp $4E33 is gone.
;   $66    copies left at this delay. A slot change stores $10. The copy
;          that starts from the 1 at $0818 does not move the slot.
;   $4321  index into $4CB2: 84 08 06 04 02 04 06 08. enter_room stores 7.
;          $84 is the bit-7 pause. Wrapping from 0 back to 7 complements $65.
;
; A plain countdown copies when $60 reaches 0. X walks eight pattern bytes
; from $64 and wraps to 0. Y 0-3 doubles the first four into the picture
; glyph. Y 4-7 doubles the next four into the shadow; that pointer starts
; four bytes early because Y is already 4. Glyph byte 0 is the top row, so
; one step up or down is two pixel rows. State $17 shoves the actor those
; two pixels on the frame before a plain copy. The $84 pause never leaves
; $60 equal to 1, so it does not shove. The STA at $2CFC and $2D03
; rewrite the address of the LDA at $2D2B. The BCS at $2CE4 lands on the
; $00 inside the BIT at $2CEC, an LDA #$00, and $64 becomes 0. The
; underflow path stores 7.
scroll_surface:
        LDA $60                         ; $2C70  the countdown
        BMI scroll_pause                ; $2C72  the long pause
        DEC $60                         ; $2C74  one less
        BEQ scroll_copy                 ; $2C76  0: copy
        RTS                             ; $2C78  back
scroll_pause:
        AND #$7F                        ; $2C79  the pause count
        SEC                             ; $2C7B  the borrow
        SBC #$01                        ; $2C7C  one less
        BEQ scroll_pause_done           ; $2C7E  0: done
        ORA #$80                        ; $2C80  still the pause
        STA $60                         ; $2C82  the countdown
        RTS                             ; $2C84  back
scroll_pause_done:
        LDX $4321                       ; $2C85  the delay slot
        LDA $4CB2,X                     ; $2C88  its delay
        STA $60                         ; $2C8B  the countdown
        DEC $66                         ; $2C8D  one copy fewer
        BMI scroll_next_slot            ; $2C8F  out: the next slot
        RTS                             ; $2C91  back
scroll_copy:
        LDA #$A0                        ; $2C92  charset $A000
        STA $7C                         ; $2C94  the glyph page
        LDA #$F1                        ; $2C96  $42F1, the pattern
        STA $7D                         ; $2C98  low
        LDA #$42                        ; $2C9A  high
        STA $7E                         ; $2C9C  the pattern
        LDA $29                         ; $2C9E  the room
        CMP #$0A                        ; $2CA0  below 10?
        BCC scroll_next_delay           ; $2CA2  yes
        LDA #$A8                        ; $2CA4  charset $A800
        STA $7C                         ; $2CA6  the glyph page
        LDA #$09                        ; $2CA8  $4309, the pattern
        STA $7D                         ; $2CAA  low
        LDA #$43                        ; $2CAC  high
        STA $7E                         ; $2CAE  the pattern
scroll_next_delay:
        LDX $4321                       ; $2CB0  the delay slot
        LDA $4CB2,X                     ; $2CB3  its delay
        STA $60                         ; $2CB6  the countdown
        DEC $66                         ; $2CB8  one copy fewer
        BPL scroll_move                 ; $2CBA  copies left: move
scroll_next_slot:
        DEC $4321                       ; $2CBC  the next slot
        BPL scroll_load_delay           ; $2CBF  not past 0
        LDX #$07                        ; $2CC1  the last slot again
        STX $4321                       ; $2CC3  the slot
        LDA $65                         ; $2CC6  the direction
        EOR #$01                        ; $2CC8  reversed
        STA $65                         ; $2CCA  stored
scroll_load_delay:
        LDX $4321                       ; $2CCC  the slot
        LDA $4CB2,X                     ; $2CCF  its delay
        STA $60                         ; $2CD2  the countdown
        LDA #$10                        ; $2CD4  16 copies
        STA $66                         ; $2CD6  at this delay
scroll_move:
        LDA $65                         ; $2CD8  the direction
        BNE scroll_move_down            ; $2CDA  down
        INC $64                         ; $2CDC  the next pattern byte
        LDA $64                         ; $2CDE  the top byte
        CMP #$08                        ; $2CE0  past 7?
        BCC scroll_glyphs               ; $2CE2  no
        BCS $2CED                       ; $2CE4  lands on LDA #$00 inside $2CEC
scroll_move_down:
        DEC $64                         ; $2CE6  the byte before
        BPL scroll_glyphs               ; $2CE8  not past 0
        LDA #$07                        ; $2CEA  wrap to 7
        BIT $00A9                       ; $2CEC  the $00 of its operand is the LDA #$00 the BCS lands on
        STA $64                         ; $2CEF  the top byte
scroll_glyphs:
        LDX #$02                        ; $2CF1  three glyphs
scroll_glyph_loop:
        STX $51                         ; $2CF3  the glyph
        TXA                             ; $2CF5  the glyph
        ASL A                           ; $2CF6  shifted up
        ASL A                           ; $2CF7  shifted up
        ASL A                           ; $2CF8  times 8
        CLC                             ; $2CF9  carry clear
        ADC $7D                         ; $2CFA  plus the pattern's address
        STA $2D2C                       ; $2CFC  rewrites a byte of the instruction at $2D2B
        LDA $7E                         ; $2CFF  high
        ADC #$00                        ; $2D01  the carry
        STA $2D2D                       ; $2D03  rewrites a byte of the instruction at $2D2B
        TXA                             ; $2D06  the glyph
        CLC                             ; $2D07  carry clear
        ADC #$61                        ; $2D08  plus $61: glyphs $61-$63
        STA $43BC                       ; $2D0A  for the scale
        JSR scale_by_eight              ; $2D0D  times 8
        LDA $43BC                       ; $2D10  the offset, low
        STA $06                         ; $2D13  the glyph's first byte
        SEC                             ; $2D15  the borrow
        SBC #$04                        ; $2D16  four bytes early
        STA $08                         ; $2D18  the shadow's first byte
        LDA $43BB                       ; $2D1A  the offset, high
        CLC                             ; $2D1D  carry clear
        ADC $7C                         ; $2D1E  plus the charset page
        STA $07                         ; $2D20  the glyph, high
        CLC                             ; $2D22  carry clear
        ADC #$04                        ; $2D23  four pages on: the shadow glyph, $80 codes higher
        STA $09                         ; $2D25  the shadow, high
        LDY #$00                        ; $2D27  the glyph's first row
        LDX $64                         ; $2D29  the pattern's top byte
scroll_byte_loop:
        LDA $E000,X                     ; $2D2B  a pattern byte. The operand is patched
        CPY #$04                        ; $2D2E  the shadow's half?
        BCS scroll_shadow_byte          ; $2D30  yes
        STA ($06),Y                     ; $2D32  one glyph row
        JSR step_ptr_06                 ; $2D34  the next byte
        STA ($06),Y                     ; $2D37  twice: a multicolor row
        JMP scroll_next_byte            ; $2D39  the next
scroll_shadow_byte:
        STA ($08),Y                     ; $2D3C  one shadow row
        JSR step_ptr_08                 ; $2D3E  the next byte
        STA ($08),Y                     ; $2D41  twice
scroll_next_byte:
        INY                             ; $2D43  the next row
        INX                             ; $2D44  the next pattern byte
        CPX #$08                        ; $2D45  past 7?
        BNE scroll_byte_test            ; $2D47  no
        LDX #$00                        ; $2D49  wrap to 0
scroll_byte_test:
        CPY #$08                        ; $2D4B  eight rows?
        BNE scroll_byte_loop            ; $2D4D  no
        LDX $51                         ; $2D4F  the glyph
        DEX                             ; $2D51  the next one
        BPL scroll_glyph_loop           ; $2D52  more
        RTS                             ; $2D54  back

; If Bruce (X = 0) has $D1 negative, he has lost a life. The other actors
; call retire_actor. State $13 and state $19 are skipped while the timer
; is still running, so the knockdown from force_knockdown is drawn through.
check_bruce_down:
        LDX #$02                        ; $2D55  the ninja first
check_down_loop:
        LDA active,X                    ; $2D57  active
        AND #$01                        ; $2D59  in the room?
        BEQ check_down_next             ; $2D5B  no
        LDA state,X                     ; $2D5D  the state
        CMP #$13                        ; $2D5F  the knockdown?
        BEQ check_down_timer            ; $2D61  yes: wait for its timer
        CMP #$19                        ; $2D63  the shock?
        BNE check_down_health           ; $2D65  no
check_down_timer:
        LDA timer,X                     ; $2D67  the timer
        BNE check_down_next             ; $2D69  still running: not yet
check_down_health:
        LDA $D1,X                       ; $2D6B  health
        BPL check_down_next             ; $2D6D  not negative: still in it
        TXA                             ; $2D6F  the actor
        BEQ check_down_bruce            ; $2D70  Bruce
        JSR retire_actor                ; $2D72  a fighter leaves
check_down_next:
        DEX                             ; $2D75  the next actor
        BPL check_down_loop             ; $2D76  more
        RTS                             ; $2D78  back
check_down_bruce:
        JMP lose_life                   ; $2D79  a life lost
; The other fighters. State 0, timer already 0, and hit bit 0 or bit 2 set:
; $C2 still $0C or $0D is a kick that just ended, and stand_down's 6 is
; replaced with $18. A long visit or a set $40 then stores 1. A middle
; visit stores 3. Any other remembered state starts state $14 with timer
; $14. A timer still counting, or a fighter in the air, is left for
; actor_tick. $42CA set skips the $81 test, so Yamo is not started here.
; He stays on the stick in $99, and actor_tick runs him on it. Actor 2,
; the ninja, is still accepted when active is $41.
enemy_turn:
        LDX #$02                        ; $2D7C  the ninja first. Bruce fails both tests below
enemy_turn_loop:
        LDA $D1,X                       ; $2D7E  health
        BMI enemy_turn_next             ; $2D80  down: no turn
        LDA $42CA                       ; $2D82  a second player?
        BNE enemy_turn_ninja            ; $2D85  yes: Yamo is his
        LDA active,X                    ; $2D87  active
        AND #$81                        ; $2D89  both bits
        CMP #$81                        ; $2D8B  Yamo?
        BEQ enemy_turn_idle             ; $2D8D  yes
enemy_turn_ninja:
        LDA active,X                    ; $2D8F  active
        AND #$41                        ; $2D91  both bits
        CMP #$41                        ; $2D93  the ninja?
        BNE enemy_turn_next             ; $2D95  no
enemy_turn_idle:
        LDA state,X                     ; $2D97  the state
        CMP #$00                        ; $2D99  idle?
        BNE enemy_turn_next             ; $2D9B  no: the script runs
        LDA timer,X                     ; $2D9D  the timer
        BNE enemy_turn_next             ; $2D9F  still running
        LDA hit,X                       ; $2DA1  the full hit
        AND #$05                        ; $2DA3  ground or ladder
        BEQ enemy_turn_next             ; $2DA5  neither: in the air
        LDA $C2,X                       ; $2DA7  the state on the previous frame
        CMP #$0D                        ; $2DA9  the kick right?
        BEQ enemy_turn_after_kick       ; $2DAB  yes
        CMP #$0C                        ; $2DAD  the kick left?
        BEQ enemy_turn_after_kick       ; $2DAF  yes
        LDA #$14                        ; $2DB1  the chase
        STA state,X                     ; $2DB3  the state
        STA timer,X                     ; $2DB5  $14 counts
        LDA #$00                        ; $2DB7  zero
        STA $0106,X                     ; $2DB9  no hold
enemy_turn_next:
        DEX                             ; $2DBC  the next actor
        BPL enemy_turn_loop             ; $2DBD  more
        RTS                             ; $2DBF  back
enemy_turn_after_kick:
        JSR stand_down                  ; $2DC0  state 0, timer 6
        LDA #$18                        ; $2DC3  $18 counts
        STA timer,X                     ; $2DC5  a long rest after a kick
        JSR test_visit                  ; $2DC7  how long he has been in the room
        BVS enemy_turn_long             ; $2DCA  long: 1
        BCS enemy_turn_middle           ; $2DCC  middle: 3
        LDA $40                         ; $2DCE  a set $40
        BNE enemy_turn_long             ; $2DD0  1
        RTS                             ; $2DD2  short: $18
enemy_turn_middle:
        LDA #$03                        ; $2DD3  3
        STA timer,X                     ; $2DD5  3 counts
        RTS                             ; $2DD7  back
enemy_turn_long:
        LDA #$01                        ; $2DD8  1
        STA timer,X                     ; $2DDA  1 count
        RTS                             ; $2DDC  back
; $62 is this fighter's ypos minus Bruce's, $63 the same for xpos. The
; magnitude is capped at $30. Bit 7 is set when this fighter's coordinate
; is the smaller one: he is above Bruce, or Bruce is to his right.
; face_from_dx writes facing 1 when bit 7 of $63 is set.
range_to_bruce:
        LDA ypos,X                      ; $2DDD  his ypos
        SEC                             ; $2DDF  the borrow
        SBC ypos                        ; $2DE0  less Bruce's
        PHP                             ; $2DE2  keep the borrow
        BCS range_dy_cap                ; $2DE3  not negative
        EOR #$FF                        ; $2DE5  negative
        ADC #$01                        ; $2DE7  the size
range_dy_cap:
        CMP #$31                        ; $2DE9  above $30?
        BCC range_dy_sign               ; $2DEB  no
        LDA #$30                        ; $2DED  capped
range_dy_sign:
        PLP                             ; $2DEF  the borrow
        BCS range_store_dy              ; $2DF0  he is lower: bit 7 clear
        ORA #$80                        ; $2DF2  he is higher
range_store_dy:
        STA $62                         ; $2DF4  dy
        LDA xpos,X                      ; $2DF6  his xpos
        SEC                             ; $2DF8  the borrow
        SBC xpos                        ; $2DF9  less Bruce's
        PHP                             ; $2DFB  keep the borrow
        BCS range_dx_cap                ; $2DFC  not negative
        EOR #$FF                        ; $2DFE  negative
        ADC #$01                        ; $2E00  the size
range_dx_cap:
        CMP #$31                        ; $2E02  above $30?
        BCC range_dx_sign               ; $2E04  no
        LDA #$30                        ; $2E06  capped
range_dx_sign:
        PLP                             ; $2E08  the borrow
        BCS range_store_dx              ; $2E09  Bruce is to his left: bit 7 clear
        ORA #$80                        ; $2E0B  Bruce is to his right
range_store_dx:
        STA $63                         ; $2E0D  dx
        RTS                             ; $2E0F  back
; Drop state $17 before the tile window is read. The timer and the pose
; hold go with it. $AA and $AD are left as they were, so a step that was
; still waiting keeps waiting if the next cell catches him again.
clear_carry:
        LDA #$00                        ; $2E10  zero
        STA state,X                     ; $2E12  no state
        LDA #$00                        ; $2E14  zero
        STA timer,X                     ; $2E16  no timer
        STA $0106,X                     ; $2E18  no hold
        RTS                             ; $2E1B  back
; Face Bruce. Bit 7 of $63 means Bruce is to the right: facing 1. Otherwise
; facing 0. spawn_ninja and bruce_above call this.
face_from_dx:
        LDA $63                         ; $2E1C  dx
        BPL face_left                   ; $2E1E  Bruce to the left
        LDA #$01                        ; $2E20  right
        BNE face_store                  ; $2E22  always
face_left:
        LDA #$00                        ; $2E24  left
face_store:
        STA facing,X                    ; $2E26  his facing
        RTS                             ; $2E28  back
; Effect $86. Punch connect, kick connect, and a landing. Room 18
; also jumps here when a spark is armed. Blow 2 does not.
hit_sound:
        PHA                             ; $2E29  keep A
        TXA                             ; $2E2A  X
        PHA                             ; $2E2B  keep X
        TYA                             ; $2E2C  Y
        PHA                             ; $2E2D  keep Y
        LDY #$86                        ; $2E2E  effect $86
        JSR play_sound                  ; $2E30  queue it
        PLA                             ; $2E33  Y back
        TAY                             ; $2E34  Y
        PLA                             ; $2E35  X back
        TAX                             ; $2E36  X
        PLA                             ; $2E37  A back
        RTS                             ; $2E38  back
; For each active actor except state $19, look at his tile row and the row
; below. cell_of_actor has his column in $E6,X and his tile row in $E9,X.
; Each of those rows checks that column and the two to the right. Hit bit 1
; is kept in $53 and gates the prize tiles, the lamps among them. State $17
; is cleared first, through clear_carry, and catch_surface puts it back
; only when tile $62 is in this window and hit bit 2 is set. $AD is left
; alone. The same window still tests the doors and the other tiles after
; the catch, so a hot tile can shock him on the frame he was caught.
scan_specials:
        LDA #$00                        ; $2E39  zero
        STA $0100                       ; $2E3B  colors written
        LDX #$02                        ; $2E3E  the ninja first
scan_specials_loop:
        STX $51                         ; $2E40  the actor
        LDA active,X                    ; $2E42  active
        AND #$01                        ; $2E44  in the room?
        BEQ scan_specials_next          ; $2E46  no
        LDA state,X                     ; $2E48  the state
        CMP #$19                        ; $2E4A  shocked?
        BEQ scan_specials_next          ; $2E4C  yes: skip
        CMP #$17                        ; $2E4E  on the surface?
        BNE scan_specials_rows          ; $2E50  no
        JSR clear_carry                 ; $2E52  off it until caught again
scan_specials_rows:
        LDA hit,X                       ; $2E55  the full hit
        AND #$02                        ; $2E57  prize ink
        STA $53                         ; $2E59  kept
        JSR cell_of_actor               ; $2E5B  his cell
        JSR scan_special_row            ; $2E5E  the row he is on
        LDX $51                         ; $2E61  the actor
        INC $E9,X                       ; $2E63  the row below
        JSR scan_special_row            ; $2E65  that row too
scan_specials_next:
        LDX $51                         ; $2E68  the actor
        DEX                             ; $2E6A  the next one
        BPL scan_specials_loop          ; $2E6B  more
        RTS                             ; $2E6D  back
; $4C counts 2, 1, 0, so three columns from $E6,X. Bit 7 of the tile is
; ignored. A shadow row therefore matches the same number as the row above.
scan_special_row:
        LDA $E9,X                       ; $2E6E  the row
        TAX                             ; $2E70  for point_at_row
        JSR point_at_row                ; $2E71  ($04) is the row
        LDX $51                         ; $2E74  the actor
        LDY $E6,X                       ; $2E76  his column
        LDA #$02                        ; $2E78  three cells
        STA $4C                         ; $2E7A  the count
scan_special_cell:
        LDA ($04),Y                     ; $2E7C  a tile
        AND #$7F                        ; $2E7E  without the shadow bit
        JSR match_special               ; $2E80  test it
        INY                             ; $2E83  the next column
        DEC $4C                         ; $2E84  one fewer
        BPL scan_special_cell           ; $2E86  more
        RTS                             ; $2E88  back
; Tiles 2, 3, 4, and 5 are the four exit slots. The destination room, xpos,
; and ypos are the parallel tables at $4B5E/$4BFE/$4C12, then $4B72/$4C26/
; $4C3A, $4B86/$4C4E/$4C62, and $4B9A/$4C76/$4C8A. Tiles 2, 3, and 4 fall
; through to the next slot when that slot's xpos byte is 0. Tile 5 does not
; test xpos. The whole table is in rooms.asm. A slot whose xpos is 0 is the
; unused marker, including the tile 4 and tile 5 records in room 18, which
; are drawn as part of the boss and are not doors.
;
; Room 11's tile 2 goes to room 10. Tiles 3, 4, and 5 go to rooms 12, 14,
; and 16. The way back from those three stores room 11, and room_11_to_13
; may turn that arrival into room 13.
match_special:
        CMP #$05                        ; $2E89  tile 5?
        BNE match_tile_2                ; $2E8B  no
        JMP exit_tile_5                 ; $2E8D  the fourth exit
match_tile_2:
        CMP #$02                        ; $2E90  tile 2?
        BNE match_tile_3                ; $2E92  no
        JMP exit_tile_2                 ; $2E94  the first exit
match_tile_3:
        CMP #$03                        ; $2E97  tile 3?
        BNE match_tile_4                ; $2E99  no
        JMP exit_tile_3                 ; $2E9B  the second exit
match_tile_4:
        CMP #$04                        ; $2E9E  tile 4?
        BNE match_ladder                ; $2EA0  no
        JMP exit_tile_4                 ; $2EA2  the third exit
; Tile $62 is the scrolling ladder. $61 and $63 move with it and do not
; catch. Bit 7 was masked, so the shadow's $E2 matches this compare too.
match_ladder:
        CMP #$62                        ; $2EA5  the moving ladder?
        BEQ match_catch                 ; $2EA7  yes: catch him
match_extra_fall:
        CMP #$2D                        ; $2EA9  tile $2D?
        BEQ match_room_16               ; $2EAB  yes
        CMP #$2E                        ; $2EAD  tile $2E?
        BEQ match_room_16               ; $2EAF  yes
; $53 held hit bit 1. The shift leaves zero when that bit was clear, and
; every prize tile below is then skipped. The tiles compared above, the
; doors among them, are tested either way.
        ASL $53                         ; $2EB1  prize ink?
        BEQ match_none                  ; $2EB3  no: nothing below
        CMP #$13                        ; $2EB5  a lamp, $13?
        BEQ take_lamp                   ; $2EB7  yes
        CMP #$14                        ; $2EB9  a lamp, $14?
        BEQ take_lamp                   ; $2EBB  yes
        CMP #$31                        ; $2EBD  a lamp, $31?
        BEQ take_lamp                   ; $2EBF  yes
        CMP #$64                        ; $2EC1  tile $64?
        BEQ match_shock                 ; $2EC3  yes: shock
        CMP #$66                        ; $2EC5  tile $66?
        BEQ match_tile_66               ; $2EC7  yes
        CMP #$0F                        ; $2EC9  tile $0F?
        BEQ match_shock                 ; $2ECB  yes: shock
        CMP #$40                        ; $2ECD  tile $40?
        BEQ match_shock                 ; $2ECF  yes: shock
        CMP #$57                        ; $2ED1  tile $57?
        BEQ match_hot                   ; $2ED3  yes: past the range below, so it does nothing
        CMP #$54                        ; $2ED5  below $54?
        BCC match_none                  ; $2ED7  yes: nothing
        CMP #$5B                        ; $2ED9  $54-$5A?
        BCC match_shock                 ; $2EDB  yes: shock
; $71-$7C are hot, and shock is where they go. The flames that step_crumble
; prints over a nozzle are this range. $60 is the nozzle itself. Bit 1 arms
; start_crumble. The nozzle is not hot, and its screen code is not a wall.
match_hot:
        CMP #$71                        ; $2EDD  below $71?
        BCC match_nozzle                ; $2EDF  yes
        CMP #$7D                        ; $2EE1  $71-$7C?
        BCC match_shock                 ; $2EE3  yes: shock
match_nozzle:
        CMP #$60                        ; $2EE5  the nozzle?
        BEQ match_crumble               ; $2EE7  yes
match_none:
        RTS                             ; $2EE9  back
match_room_16:
        LDA $29                         ; $2EEA  the room
        CMP #$10                        ; $2EEC  room 16?
        BEQ match_extra_fall_go         ; $2EEE  yes
        RTS                             ; $2EF0  back
match_extra_fall_go:
        JMP extra_fall                  ; $2EF1  an extra fall
match_catch:
        JMP catch_surface               ; $2EF4  the surface
match_crumble:
        JMP start_crumble               ; $2EF7  the crumble
match_tile_66:
        LDA $29                         ; $2EFA  the room
        CMP #$0A                        ; $2EFC  room 10 or later?
        BCS match_shock                 ; $2EFE  yes: shock
        RTS                             ; $2F00  back
match_shock:
        JMP shock                       ; $2F01  the shock
; Tiles $13, $14, and $31. Bruce only: any other actor returns. claim_lamp
; returns the bare mount, or sets carry when this cell is not in the room's
; list. The mount is written on this row. The same byte with bit 7 set is
; written $28 bytes later, the shadow row. $7D is added to the low score
; byte. That add is binary, and 125 is what the six digits then show.
; Sound $8E plays.
take_lamp:
        TXA                             ; $2F04  the actor
        BNE match_none                  ; $2F05  not Bruce: nothing
        JSR stash_axy                   ; $2F07  keep A, X, Y
        JSR claim_lamp                  ; $2F0A  find the lamp
        BCS take_lamp_done              ; $2F0D  not in the list
        PHA                             ; $2F0F  the bare mount
        JSR restore_axy                 ; $2F10  A, X, Y back
        PLA                             ; $2F13  the mount
        STA ($04),Y                     ; $2F14  on this row
        ORA #$80                        ; $2F16  the shadow glyph
        PHA                             ; $2F18  kept
        TYA                             ; $2F19  the column
        CLC                             ; $2F1A  carry clear
        ADC #$28                        ; $2F1B  one row down
        TAY                             ; $2F1D  the index
        PLA                             ; $2F1E  the shadow glyph
        STA ($04),Y                     ; $2F1F  on the shadow row
        AND #$7F                        ; $2F21  the bare mount again
        PHA                             ; $2F23  kept
        TYA                             ; $2F24  the index
        SEC                             ; $2F25  the borrow
        SBC #$28                        ; $2F26  one row up
        TAY                             ; $2F28  the column again
        PLA                             ; $2F29  the mount
        JSR stash_axy                   ; $2F2A  keep A, X, Y
        LDA #$7D                        ; $2F2D  125
        LDX #$02                        ; $2F2F  into the low byte
        JSR add_score                   ; $2F31  points
        LDY #$8E                        ; $2F34  effect $8E
        JSR play_sound                  ; $2F36  queue it
take_lamp_done:
        JMP restore_axy                 ; $2F39  A, X, Y back, and return from there
; One slot. exit_allowed returns carry clear to take it. $4E becomes
; the destination room, Y the ypos, A the xpos. A zero xpos falls
; through to the next slot. Tile 5 does not test A. $51 is the actor
; the scan is on. Bruce, $51 = 0, is the one who changes rooms.
exit_tile_2:
        JSR exit_allowed                ; $2F3C  through the edge he is on?
exit_slot_0_test:
        BCS match_none                  ; $2F3F  no
        LDX $29                         ; $2F41  the room
        LDA $4B5E,X                     ; $2F43  slot 0's room
        STA $4E                         ; $2F46  the destination
        LDA $4C12,X                     ; $2F48  its ypos
        TAY                             ; $2F4B  kept
        LDA $4BFE,X                     ; $2F4C  its xpos
        BNE finish_exit                 ; $2F4F  used: go
; Door slot 1: $4B72 room, $4C26 xpos, $4C3A ypos.
exit_tile_3:
        JSR exit_allowed                ; $2F51  through the edge he is on?
        BCS exit_slot_0_test            ; $2F54  no: slot 0's test
        LDX $29                         ; $2F56  the room
        LDA $4B72,X                     ; $2F58  slot 1's room
        STA $4E                         ; $2F5B  the destination
        LDA $4C3A,X                     ; $2F5D  its ypos
        TAY                             ; $2F60  kept
        LDA $4C26,X                     ; $2F61  its xpos
        BNE finish_exit                 ; $2F64  used: go
; Door slot 2: $4B86 room, $4C4E xpos, $4C62 ypos.
exit_tile_4:
        JSR exit_allowed                ; $2F66  through the edge he is on?
exit_slot_2_test:
        BCS exit_slot_0_test            ; $2F69  no
        LDX $29                         ; $2F6B  the room
        LDA $4B86,X                     ; $2F6D  slot 2's room
        STA $4E                         ; $2F70  the destination
        LDA $4C62,X                     ; $2F72  its ypos
        TAY                             ; $2F75  kept
        LDA $4C4E,X                     ; $2F76  its xpos
        BNE finish_exit                 ; $2F79  used: go
; Door slot 3: $4B9A room, $4C76 xpos, $4C8A ypos. The xpos is not tested.
exit_tile_5:
        JSR exit_allowed                ; $2F7B  through the edge he is on?
        BCS exit_slot_2_test            ; $2F7E  no
        LDX $29                         ; $2F80  the room
        LDA $4B9A,X                     ; $2F82  slot 3's room
        STA $4E                         ; $2F85  the destination
        LDA $4C8A,X                     ; $2F87  its ypos
        TAY                             ; $2F8A  kept
        LDA $4C76,X                     ; $2F8B  its xpos
; A is xpos, Y is ypos, $4E is the room. Facing is left as it was.
; Anyone other than Bruce is removed and the scan goes on to the next actor.
; The two PLAs drop only match_special's return. match_special reached the
; exit with a JMP, so the JSR from scan_specials into scan_special_row is
; still on the stack. A fighter who exits on his first row leaves the
; return to $2E61 there. When the actor loop ends, its RTS lands at $2E61
; with $51 at 0: Bruce's $E9 goes up once more and that row is scanned too,
; once for each such fighter. A second-row exit leaves $2E68, which only
; ends the loop again. Tile row 13 is $8FE8, past the screen: from column 24
; on it is $9000-$900F, 00 00 03 03 03 03 00 00 03 CF FF 03 03 03 0F 0C in
; every snapshot. Bruce at room 0's bottom right reads its tile 3 there, and
; slot 5 takes him to room 1 at 15,98 in the frame Yamo leaves overhead.
finish_exit:
        LDX $51                         ; $2F8E  the actor
        BEQ finish_exit_bruce           ; $2F90  Bruce
        JSR retire_actor                ; $2F92  a fighter leaves
        PLA                             ; $2F95  drop match_special's return
        PLA                             ; $2F96  high byte
        JMP scan_specials_next          ; $2F97  the next actor
; Bruce. Store the new position and the room, then go through the
; fighters from X = 2.
finish_exit_bruce:
        STA xpos,X                      ; $2F9A  the new xpos
        TYA                             ; $2F9C  the ypos
        STA ypos,X                      ; $2F9D  stored
        LDA $4E                         ; $2F9F  the new room
        STA $29                         ; $2FA1  stored
        LDX #$02                        ; $2FA3  the ninja first
; Active: keep Bruce's xpos and ypos, and this fighter's $D1, for the next
; wake. Inactive: the xpos and ypos bytes are cleared, so that wake uses
; the room's spawn tables.
save_fighter_loop:
        LDA active,X                    ; $2FA5  active
        AND #$01                        ; $2FA7  in the room?
        BEQ save_fighter_clear          ; $2FA9  no
        LDA $D1,X                       ; $2FAB  his health
        STA $8E,X                       ; $2FAD  saved
        LDA xpos                        ; $2FAF  Bruce's xpos
        STA $8A,X                       ; $2FB1  where he wakes next
        LDA ypos                        ; $2FB3  Bruce's ypos
        STA $8C,X                       ; $2FB5  saved
        BNE save_fighter_retire         ; $2FB7  always: ypos is never 0
save_fighter_clear:
        LDA #$00                        ; $2FB9  zero
        STA $8A,X                       ; $2FBB  no saved place
        STA $8C,X                       ; $2FBD  no saved place
save_fighter_retire:
        JSR retire_actor                ; $2FBF  he leaves
        DEX                             ; $2FC2  the next fighter
        BNE save_fighter_loop           ; $2FC3  down to Yamo
        SEI                             ; $2FC5  no interrupts
        JSR load_wake_counts            ; $2FC6  both wake counts. X is 0
        LDX #$FF                        ; $2FC9  a fresh stack
        TXS                             ; $2FCB  at $01FF
        JSR enter_room                  ; $2FCC  the new room
        JSR blit_sprites                ; $2FCF  the pictures
        CLI                             ; $2FD2  interrupts on
        JMP frame                       ; $2FD3  the frame loop
; Tiles $2D and $2E, and the caller has already required room 16. Bruce
; only, and only when ypos is at least $A0. The DEC of $4E95,X is not
; tested, so the fall is given every time the scan matches, including after
; the counter has gone through zero. hook_enter_16 reads that counter only to
; decide whether to print the caption. The trainer overwrites the INC with
; LDA, the same byte as at $1826.
; Effect $8E, the same phrase as take_lamp. The extra fall that
; check_life_mark gives for a score mark is silent.
extra_fall:
        TXA                             ; $2FD6  the actor
        BEQ extra_fall_bruce            ; $2FD7  Bruce
extra_fall_done:
        RTS                             ; $2FD9  back
extra_fall_bruce:
        LDA ypos                        ; $2FDA  Bruce's ypos
        CMP #$A0                        ; $2FDC  $A0 or more?
        BCC extra_fall_done             ; $2FDE  no
        LDX $03                         ; $2FE0  the player
        DEC $4E95,X                     ; $2FE2  one fewer left in the room
        INC $28                         ; $2FE5  one more fall
        JSR lives_to_bcd                ; $2FE7  the falls count
        LDY #$8E                        ; $2FEA  effect $8E
        JSR play_sound                  ; $2FEC  queue it
; String $56 at column $24 of tile rows $0A and $0B. hook_enter_16 also
; prints it, once the room's extra falls are spent.
extra_fall_caption:
        LDA #$56                        ; $2FEF  the caption
        LDX #$0A                        ; $2FF1  tile row $0A
        LDY #$24                        ; $2FF3  column $24
        JSR print_string                ; $2FF5  print it
        LDA #$56                        ; $2FF8  the caption
        LDX #$0B                        ; $2FFA  tile row $0B
        LDY #$24                        ; $2FFC  column $24
        JMP print_string                ; $2FFE  print it, and return from there
; Clear active bit 0, turn off his hardware sprites, and drop the two
; object slots at $EC,X and $EF,X, then jumps to load_wake_counts to arm
; the next wake for this X.
retire_actor:
        LDA #$01                        ; $3001  bit 0
        EOR #$FF                        ; $3003  inverted
        AND active,X                    ; $3005  cleared
        STA active,X                    ; $3007  not in the room
        LDY $276D,X                     ; $3009  his first sprite
        LDA $D015                       ; $300C  sprite enable
        AND $2778,Y                     ; $300F  off
        STA $D015                       ; $3012  sprite enable
        LDY $2770,X                     ; $3015  his second sprite
        BMI retire_voice_1              ; $3018  none
        LDA $D015                       ; $301A  sprite enable
        AND $2778,Y                     ; $301D  off
        STA $D015                       ; $3020  sprite enable
retire_voice_1:
        LDA $EC,X                       ; $3023  his first slot's effect number
        BEQ retire_voice_2              ; $3025  none
        JSR claim_voice_slot            ; $3027  the slot, in Y
        LDA #$FF                        ; $302A  no owner
        STA $4F40,Y                     ; $302C  freed
retire_voice_2:
        LDA $EF,X                       ; $302F  his second slot's effect number
        BEQ retire_clear_images         ; $3031  none
        JSR claim_voice_slot            ; $3033  the slot, in Y
        LDA #$FF                        ; $3036  no owner
        STA $4F40,Y                     ; $3038  freed
retire_clear_images:
        CPX #$01                        ; $303B  Yamo?
        BNE retire_ninja_images         ; $303D  no
        JSR clear_sprite_ram            ; $303F  his images
        JMP retire_reload_count         ; $3042  the wake count
retire_ninja_images:
        JSR clear_upper_sprites         ; $3045  the ninja's images
retire_reload_count:
        JMP load_wake_counts            ; $3048  the next wake, and return from there
; Hot tiles from match_special: $0F, $40, $64, $66 from room 10 on, $54-$5A
; except $57, and $71-$7C. Sound $8C. Room 18 returns without a shock.
; Bruce, $51 = 0, goes to state $19 for $10 frames. Any other actor loses
; active bit 0.
shock:
        LDA $29                         ; $304B  the room
        CMP #$12                        ; $304D  room 18?
        BNE shock_play                  ; $304F  no
        RTS                             ; $3051  back
shock_play:
        PHA                             ; $3052  keep A
        TXA                             ; $3053  X
        PHA                             ; $3054  keep X
        TYA                             ; $3055  Y
        PHA                             ; $3056  keep Y
        LDY #$8C                        ; $3057  effect $8C
        JSR play_sound                  ; $3059  queue it
        PLA                             ; $305C  Y back
        TAY                             ; $305D  into Y
        PLA                             ; $305E  X back
        TAX                             ; $305F  into X
        PLA                             ; $3060  A back
        LDX $51                         ; $3061  the actor
        BEQ shock_bruce_go              ; $3063  Bruce
        JMP retire_actor                ; $3065  a fighter leaves
shock_bruce_go:
        JMP shock_bruce                 ; $3068  Bruce is shocked
; Tile $60 with hit bit 1 set. Room 7's nozzles are this tile, on tile row 4
; at columns 7 and 29 and on tile row 7 at columns 3, 17, and 21. Column 7
; of row 4 is the one just to the right of the spawn.
;
; ($04) is the picture row from point_at_row. Adding $4C to its high byte
; aims it at color RAM, the same offset that turns $8C00 into $D800. An ink
; of 5, the low three bits, means this cell is already armed, and the store
; is skipped. Otherwise the first free slot of $4FDE, $4FDF, and $4FE0 is
; set to 1. Y minus 1 is stored at $4FE1,X and the row minus 1 at $4FE4,X.
; The flame strings are three tiles wide and are printed from that corner.
;
; The $FD store uses the color pointer, before $4C is subtracted again. It
; is not written to the screen. Color RAM keeps four bits, so the cell
; becomes $0D: multicolor, with ink 5 so the next pass skips it. The screen
; code stays $60, and the shadow under it stays $E0. Walking right from the
; room 7 spawn crosses that cell with hit $01 or $03. Bit 3 stays clear, so
; push_out does not run. A screen code of $FD is a different glyph, and that
; one is solid where his legs are.
start_crumble:
        LDA $05                         ; $306B  the screen row, high
        CLC                             ; $306D  carry clear
        ADC #$4C                        ; $306E  plus $4C
        STA $05                         ; $3070  the color row
        LDA ($04),Y                     ; $3072  the cell's color
        AND #$07                        ; $3074  the ink
        CMP #$05                        ; $3076  5?
        BEQ crumble_return              ; $3078  yes: already armed
        LDA $4FDE                       ; $307A  slot 0
        BNE crumble_slot_2              ; $307D  busy
        LDA #$01                        ; $307F  armed
        STA $4FDE                       ; $3081  stored
        LDA $E9,X                       ; $3084  the row
        STA $4FE4                       ; $3086  kept
        STY $4FE1                       ; $3089  the column
        DEC $4FE1                       ; $308C  one column left
        DEC $4FE4                       ; $308F  one row up
        JMP mark_crumble_spent          ; $3092  mark it
crumble_slot_2:
        LDA $4FDF                       ; $3095  slot 1
        BNE crumble_slot_3              ; $3098  busy
        LDA #$01                        ; $309A  armed
        STA $4FDF                       ; $309C  stored
        LDA $E9,X                       ; $309F  the row
        STA $4FE5                       ; $30A1  kept
        STY $4FE2                       ; $30A4  the column
        DEC $4FE2                       ; $30A7  one column left
        DEC $4FE5                       ; $30AA  one row up
        JMP mark_crumble_spent          ; $30AD  mark it
crumble_slot_3:
        LDA $4FE0                       ; $30B0  slot 2
        BNE crumble_return              ; $30B3  busy: no crumble
        LDA #$01                        ; $30B5  armed
        STA $4FE0                       ; $30B7  stored
        LDA $E9,X                       ; $30BA  the row
        STA $4FE6                       ; $30BC  kept
        STY $4FE3                       ; $30BF  the column
        DEC $4FE3                       ; $30C2  one column left
        DEC $4FE6                       ; $30C5  one row up
; Write $FD to the cell's color byte, so its ink becomes 5 and the
; scan skips it from now on.
mark_crumble_spent:
        LDA #$FD                        ; $30C8  ink 5, multicolor
        STA ($04),Y                     ; $30CA  the cell's color
; Put $05 back on the screen row.
crumble_return:
        LDA $05                         ; $30CC  the color row
        SEC                             ; $30CE  the borrow
        SBC #$4C                        ; $30CF  less $4C
        STA $05                         ; $30D1  the screen row again
        RTS                             ; $30D3  back
; Carry clear means the exit is allowed. Room 11 always is: its three
; side doors, and the door back to room 10, sit in the middle of the
; screen, so the edge tests would reject them. Otherwise the actor has
; to be leaving through the edge he is standing on: xpos below $10
; with $4F5D set, xpos above $A1 with $4F60 set, ypos above $C5 while the
; state is $0E, or ypos below $31 with $4F57 set. $4F5A, the down counter,
; is not read here.
; $4F5D, $4F60, and $4F57 are this frame's steps left, right, and up, the
; first generation of the step history. clear_work_ram zeroes them.
exit_allowed:
        LDA $29                         ; $30D4  the room
        CMP #$0B                        ; $30D6  room 11?
        BEQ exit_yes                    ; $30D8  yes: always
        SEC                             ; $30DA  set: refused unless a test passes
        LDA xpos,X                      ; $30DB  xpos
        CMP #$10                        ; $30DD  $10 or more?
        BCS exit_test_right             ; $30DF  yes
        LDA $4F5D,X                     ; $30E1  stepped left this frame?
        BNE exit_yes                    ; $30E4  yes: through the left edge
exit_test_right:
        LDA #$A1                        ; $30E6  $A1
        CMP xpos,X                      ; $30E8  xpos above it?
        BCS exit_test_bottom            ; $30EA  no
        LDA $4F60,X                     ; $30EC  stepped right this frame?
        BNE exit_yes                    ; $30EF  yes: through the right edge
exit_test_bottom:
        LDA #$C5                        ; $30F1  $C5
        CMP ypos,X                      ; $30F3  ypos above it?
        BCS exit_test_top               ; $30F5  no
        LDA state,X                     ; $30F7  the state
        CMP #$0E                        ; $30F9  falling?
        BEQ exit_yes                    ; $30FB  yes: through the bottom
exit_test_top:
        LDA ypos,X                      ; $30FD  ypos
        CMP #$31                        ; $30FF  $31 or more?
        BCS exit_no                     ; $3101  yes: refused
        LDA $4F57,X                     ; $3103  stepped up this frame?
        BNE exit_yes                    ; $3106  yes: through the top
; Carry set: the door stays shut for this step.
exit_no:
        SEC                             ; $3108  refused
        RTS                             ; $3109  back
; Carry clear: the door is taken.
exit_yes:
        CLC                             ; $310A  taken
        RTS                             ; $310B  back
; Tile $62. State $19 does not catch. Hit bit 2 clear does not catch.
; Otherwise state $17, timer $10, the pose hold cleared, and $AA cleared.
; $AD is not written. Control then continues at match_extra_fall, so a later test
; on the same cell can still shock him. Every actor is tested. This is
; how Yamo and the ninja get onto the moving ladder. They do not jump,
; and chase never climbs.
catch_surface:
        LDA state,X                     ; $310C  the state
        CMP #$19                        ; $310E  shocked?
        BEQ catch_continue              ; $3110  yes: no catch
        LDA hit,X                       ; $3112  the full hit
        AND #$04                        ; $3114  ladder?
        BEQ catch_continue              ; $3116  no: no catch
        LDA #$17                        ; $3118  carried
        STA state,X                     ; $311A  state
        LDA #$10                        ; $311C  16 counts
        STA timer,X                     ; $311E  timer
        LDA #$00                        ; $3120  zero
        STA $0106,X                     ; $3122  no hold
        STA $AA,X                       ; $3125  his own step not yet taken
catch_continue:
        LDA ($04),Y                     ; $3127  the tile again
        JMP match_extra_fall            ; $3129  the other tests
; Add the three bytes at $25 into the score at $41. $41 is the high byte and
; $43 is the low byte. The add is binary, with the carry kept between bytes,
; and a carry out of $41 is dropped, so the total wraps at 24 bits.
; check_life_mark then compares from the high byte. The first byte that is
; below its pair in $4392 skips the fall. When none is below, $28 is
; incremented and the step at $438E is added into the mark. draw_score runs
; either way and prints only the low six BCD digits.
apply_score:
        LDX #$02                        ; $312C  three bytes
        CLC                             ; $312E  nothing in
apply_score_add:
        LDA $41,X                       ; $312F  a score byte
        ADC $25,X                       ; $3131  plus the addend
        STA $41,X                       ; $3133  stored
        DEX                             ; $3135  the next byte up
        BPL apply_score_add             ; $3136  more
; High byte first. BCC on a short byte waits, even when a lower byte has
; already carried the total past the mark.
        LDX #$00                        ; $3138  the high byte
; X = 0, 1, 2: compare one score byte with the mark at $4392,X.
check_life_mark:
        LDA $41,X                       ; $313A  a score byte
        CMP $4392,X                     ; $313C  below the mark's?
        BCC draw_score                  ; $313F  yes: no fall
        INX                             ; $3141  the next byte
        CPX #$03                        ; $3142  all three?
        BCC check_life_mark             ; $3144  no
        LDX #$02                        ; $3146  three bytes
        CLC                             ; $3148  nothing in
life_mark_step:
        LDA $4392,X                     ; $3149  the mark
        ADC $438E,X                     ; $314C  plus the step
        STA $4392,X                     ; $314F  the next mark
        DEX                             ; $3152  the next byte up
        BPL life_mark_step              ; $3153  more
; Extra fall when the score crosses the next mark. The trainer's LDA patch covers this too.
        INC $28                         ; $3155  one more fall
        JSR lives_to_bcd                ; $3157  the falls count
; Low six digits of the current total. Columns $30, $32, and $34.
draw_score:
        JSR stash_scores                ; $315A  the score in BCD
        LDY #$30                        ; $315D  column $30
        LDA $439C                       ; $315F  digits 5 and 6 from the right
        JSR draw_split_digits           ; $3162  drawn
        LDY #$32                        ; $3165  column $32
        LDA $439D                       ; $3167  digits 3 and 4
        JSR draw_split_digits           ; $316A  drawn
        LDY #$34                        ; $316D  column $34
        LDA $439E                       ; $316F  digits 1 and 2
        JMP draw_split_digits           ; $3172  drawn, and return from there
; Add A to score byte X. The other two bytes of the addend are cleared, so
; one call moves one byte of the total. X = 0 is $41, X = 1 is $42, and
; X = 2 is $43. A lamp passes $7D with X = 2, which is 125.
add_score:
        PHA                             ; $3175  kept
        LDA #$00                        ; $3176  zero
        STA $25                         ; $3178  addend, high
        STA $26                         ; $317A  middle
        STA $27                         ; $317C  low
        PLA                             ; $317E  the value
        STA $25,X                       ; $317F  into byte X
        JMP apply_score                 ; $3181  into the total, and return from there
; Every frame. With $0104 clear, draw_score redraws the current total. In
; play, compare $4388 with $41 from the high byte as an unsigned 24-bit
; value. A smaller top is replaced from the score and draw_top reprints it.
; The top score is not cleared with the working RAM, so it survives a game.
refresh_top:
        LDA $0104                       ; $3184  the demo?
        BEQ draw_score                  ; $3187  yes: the score only
        LDA $CF7B                       ; $3189  a check byte
        EOR $CF9B                       ; $318C  EOR its partner
        BNE top_compare                 ; $318F  the compare either way
        LDA $CF7E                       ; $3191  a check byte
        EOR $CF9E                       ; $3194  EOR its partner
        BNE top_compare                 ; $3197  the compare either way
        LDA $CF81                       ; $3199  a check byte
        EOR $CFA1                       ; $319C  EOR its partner
        BNE top_compare                 ; $319F  the compare either way
        NOP                             ; $31A1  three spare bytes
        NOP                             ; $31A2  spare
        NOP                             ; $31A3  spare
top_compare:
        LDX #$00                        ; $31A4  the high byte first
top_compare_loop:
        LDA $4388,X                     ; $31A6  the top score
        CMP $41,X                       ; $31A9  against the total
        BCC top_replace                 ; $31AB  below: replace it
        BEQ top_compare_next            ; $31AD  equal: the next byte
        BCS draw_score                  ; $31AF  above: the score only
top_compare_next:
        INX                             ; $31B1  the next byte
        CPX #$03                        ; $31B2  all three?
        BCC top_compare_loop            ; $31B4  no
        BCS draw_score                  ; $31B6  equal: the score only
top_replace:
        LDX #$03                        ; $31B8  four bytes, one too many
top_replace_loop:
        LDA $41,X                       ; $31BA  $41-$44. $44, the raster split index, lands on $438B
        STA $4388,X                     ; $31BC  the top score, and the first mark's high byte
        DEX                             ; $31BF  the next
        BPL top_replace_loop            ; $31C0  more
; Low six digits of the top score. Columns $3C, $3E, and $40.
draw_top:
        LDX #$03                        ; $31C2  four bytes
top_copy:
        LDA $4388,X                     ; $31C4  the top score
        STA $4398,X                     ; $31C7  for the conversion
        LDA #$00                        ; $31CA  zero
        STA $439B,X                     ; $31CC  the BCD digits
        DEX                             ; $31CF  the next
        BPL top_copy                    ; $31D0  more
        STA $439E                       ; $31D2  the last digit pair
        PHP                             ; $31D5  keep the decimal flag
        SED                             ; $31D6  decimal
        LDX #$17                        ; $31D7  24 bits
top_bcd_bit:
        ASL $439A                       ; $31D9  the next bit out
        ROL $4399                       ; $31DC  of the three
        ROL $4398                       ; $31DF  bytes
        LDY #$03                        ; $31E2  four BCD bytes
top_bcd_double:
        LDA $439B,Y                     ; $31E4  a BCD byte
        ADC $439B,Y                     ; $31E7  doubled, plus the bit
        STA $439B,Y                     ; $31EA  stored
        DEY                             ; $31ED  the next one up
        BPL top_bcd_double              ; $31EE  more
        DEX                             ; $31F0  the next bit
        BPL top_bcd_bit                 ; $31F1  more
        PLP                             ; $31F3  binary again
        LDY #$3C                        ; $31F4  column $3C
        LDA $439C                       ; $31F6  digits 5 and 6
        JSR draw_split_digits           ; $31F9  drawn
        LDY #$3E                        ; $31FC  column $3E
        LDA $439D                       ; $31FE  digits 3 and 4
        JSR draw_split_digits           ; $3201  drawn
        LDY #$40                        ; $3204  column $40
        LDA $439E                       ; $3206  digits 1 and 2
        JMP draw_split_digits           ; $3209  drawn, and return from there
        .byte $B0, $04                  ; $320C  BCS +4, not reached

; A is shifted down by four. Used before a digit is drawn.
high_nibble:
        LSR A                           ; $320E  four shifts
        LSR A                           ; $320F  shifted down
        LSR A                           ; $3210  shifted down
        LSR A                           ; $3211  the high nibble
        AND #$0F                        ; $3212  nothing above it
        RTS                             ; $3214  back
        .byte $A6, $29                  ; $3215  LDX $29, not reached

; X is the room. $51 is forced to 0, so finish_exit treats the caller as
; Bruce. A and Y are that room's spawn at $4BAE,X and $4BC2,X, not an
; exit slot. room_11_to_13 calls this with X = $0D once rooms 12, 14, and
; 16 are clear. between_lives calls it with X = $29. $24DB is this same
; sequence inlined for the current room.
enter_room_at:
        LDA #$00                        ; $3217  zero
        STA $51                         ; $3219  the actor is Bruce
        TXA                             ; $321B  the room
        STA $4E                         ; $321C  the destination
        LDA $4BC2,X                     ; $321E  its spawn ypos
        TAY                             ; $3221  kept
        LDA $4BAE,X                     ; $3222  its spawn xpos
        JMP finish_exit                 ; $3225  go there

; Slots armed by start_crumble. The per-frame hooks of rooms 6, 7, 10, 11,
; 12, 14, 16, and 17 call this, and the hook runs before the overlap. The
; compare below is the count before the increment.
;
; 8 and $10 print the first flame, from the stored column and row, which is
; one tile left and one tile above the nozzle. $2F at $4612 is 11 12 13.
; print_string subtracts $20, so those are tiles $71 $72 $73 on the upper
; row. $30 at $4616 is 14 15 16, tiles $74 $75 $76, on the nozzle's row.
; Sound $8D plays only when the count leaves 8.
; $0C prints the second flame. $31 at $461A is tiles $77 $78 $79. $32 at
; $461E is tiles $7A $7B $7C.
; $14 clears the upper row with string 0, three $00 at $4488. Y then sits
; two past the nozzle's column, and the two DEY leave the nozzle's own
; column. Adding $50 drops two character rows, which is one tile row, and
; adding $4C00 selects color RAM, so $F8 is stored on the nozzle. Its ink
; is no longer 5 and start_crumble can arm it again. $33 at
; $4622 is 1D 00 1D, tiles $7D $60 $7D, which puts the nozzle back.
; $18 frees the slot. Until the count leaves 8 the screen code is still
; $60, so the walk that armed the nozzle is not pushed out. Tiles $71-$7C
; are the hot range in match_special, and an overlap with bit 1 set still
; reaches shock.
step_crumble:
        LDX #$02                        ; $3228  three slots
        STX $4F                         ; $322A  the slot
crumble_loop:
        LDX $4F                         ; $322C  the slot
        LDA $4FDE,X                     ; $322E  its count
        BNE crumble_count               ; $3231  armed
        JMP crumble_next                ; $3233  free
crumble_count:
        INC $4FDE,X                     ; $3236  one more
        CMP #$08                        ; $3239  it was 8?
        BNE crumble_second_test         ; $323B  no
        JSR crumble_sound               ; $323D  effect $8D
crumble_first_flame:
        LDX $4F                         ; $3240  the slot
        LDY $4FE1,X                     ; $3242  its column
        LDA $4FE4,X                     ; $3245  its row
        TAX                             ; $3248  for print_string
        LDA #$2F                        ; $3249  the upper flame
        JSR print_string                ; $324B  printed
        LDX $4F                         ; $324E  the slot
        LDY $4FE1,X                     ; $3250  its column
        LDA $4FE4,X                     ; $3253  its row
        TAX                             ; $3256  for print_string
        INX                             ; $3257  one row down
        LDA #$30                        ; $3258  the lower flame
        JSR print_string                ; $325A  printed
        JMP crumble_next                ; $325D  the next slot
crumble_second_test:
        CMP #$0C                        ; $3260  it was 12?
        BNE crumble_clear_test          ; $3262  no
        LDY $4FE1,X                     ; $3264  its column
        LDA $4FE4,X                     ; $3267  its row
        TAX                             ; $326A  for print_string
        LDA #$31                        ; $326B  the second upper flame
        JSR print_string                ; $326D  printed
        LDX $4F                         ; $3270  the slot
        LDY $4FE1,X                     ; $3272  its column
        LDA $4FE4,X                     ; $3275  its row
        TAX                             ; $3278  for print_string
        INX                             ; $3279  one row down
        LDA #$32                        ; $327A  the second lower flame
        JSR print_string                ; $327C  printed
        JMP crumble_next                ; $327F  the next slot
crumble_clear_test:
        CMP #$10                        ; $3282  it was 16?
        BEQ crumble_first_flame         ; $3284  yes: the first flame again
        CMP #$14                        ; $3286  it was 20?
        BNE crumble_free_test           ; $3288  no
        LDY $4FE1,X                     ; $328A  its column
        LDA $4FE4,X                     ; $328D  its row
        TAX                             ; $3290  for print_string
        LDA #$00                        ; $3291  three blanks
        JSR print_string                ; $3293  the upper row cleared
        DEY                             ; $3296  back two columns
        DEY                             ; $3297  to the nozzle
        LDA $04                         ; $3298  the row
        CLC                             ; $329A  carry clear
        ADC #$50                        ; $329B  two character rows on
        STA $04                         ; $329D  low
        LDA $05                         ; $329F  high
        ADC #$4C                        ; $32A1  plus $4C: color RAM
        STA $05                         ; $32A3  high
        LDA #$F8                        ; $32A5  the room fill
        STA ($04),Y                     ; $32A7  the nozzle can be armed again
        LDX $4F                         ; $32A9  the slot
        LDY $4FE1,X                     ; $32AB  its column
        LDA $4FE4,X                     ; $32AE  its row
        TAX                             ; $32B1  for print_string
        INX                             ; $32B2  one row down
        LDA #$33                        ; $32B3  the nozzle row
        JSR print_string                ; $32B5  printed
        JMP crumble_next                ; $32B8  the next slot
crumble_free_test:
        CMP #$18                        ; $32BB  it was 24?
        BNE crumble_next                ; $32BD  no
        LDA #$00                        ; $32BF  zero
        STA $4FDE,X                     ; $32C1  the slot is free
crumble_next:
        DEC $4F                         ; $32C4  the next slot
        BMI crumble_done                ; $32C6  all three done
        JMP crumble_loop                ; $32C8  more
crumble_done:
        RTS                             ; $32CB  back
; Sound $8D. Played when a nozzle's count leaves 8, the first flame frame.
crumble_sound:
        PHA                             ; $32CC  keep A
        TXA                             ; $32CD  X
        PHA                             ; $32CE  keep X
        TYA                             ; $32CF  Y
        PHA                             ; $32D0  keep Y
        LDY #$8D                        ; $32D1  effect $8D
        JSR play_sound                  ; $32D3  queue it
        PLA                             ; $32D6  Y back
        TAY                             ; $32D7  into Y
        PLA                             ; $32D8  X back
        TAX                             ; $32D9  into X
        PLA                             ; $32DA  A back
        RTS                             ; $32DB  back

; Copy the three score bytes at $41 into $4398 and convert that binary
; value to BCD with SED. The eight digits land in $439B-$439E. draw_score
; prints the low six, $439C-$439E. draw_top converts $4388 the same way.
stash_scores:
        LDX #$02                        ; $32DC  three bytes
stash_copy:
        LDA $41,X                       ; $32DE  the total
        STA $4398,X                     ; $32E0  for the conversion
        LDA #$00                        ; $32E3  zero
        STA $439B,X                     ; $32E5  the BCD digits
        DEX                             ; $32E8  the next
        BPL stash_copy                  ; $32E9  more
        STA $439E                       ; $32EB  the last digit pair
        PHP                             ; $32EE  keep the decimal flag
        SED                             ; $32EF  decimal
        LDX #$17                        ; $32F0  24 bits
stash_bcd_bit:
        ASL $439A                       ; $32F2  the next bit out
        ROL $4399                       ; $32F5  of the three
        ROL $4398                       ; $32F8  bytes
        LDY #$03                        ; $32FB  four BCD bytes
stash_bcd_double:
        LDA $439B,Y                     ; $32FD  a BCD byte
        ADC $439B,Y                     ; $3300  doubled, plus the bit
        STA $439B,Y                     ; $3303  stored
        DEY                             ; $3306  the next one up
        BPL stash_bcd_double            ; $3307  more
        DEX                             ; $3309  the next bit
        BPL stash_bcd_bit               ; $330A  more
        PLP                             ; $330C  binary again
        RTS                             ; $330D  back
; Keep A, X, and Y in $57-$59. take_lamp brackets claim_lamp with these.
stash_axy:
        STA $57                         ; $330E  A
        STX $58                         ; $3310  X
        STY $59                         ; $3312  Y
        RTS                             ; $3314  back
; The other half. A, X, and Y come back from $57-$59.
restore_axy:
        LDA $57                         ; $3315  A
        LDX $58                         ; $3317  X
        LDY $59                         ; $3319  Y
        RTS                             ; $331B  back
; The room in $29 selects a list through $4CE2. A record is four bytes: a
; flag (0 means taken, and the high bit means the end), the replacement tile
; with its high bit set, the column, and the tile row. $5A is the column
; under the scan and $5B is the tile row. A match stores 0 in the flag,
; decrements the room's remaining count at $2A,X, and returns the replacement
; with the high bit clear. Carry set means there was no match. $2A,X is
; $2A plus the room. room_11_to_13 reads $36, $38, and $3A, which are
; rooms 12, 14, and 16. The counts copied to $2A are the twenty bytes at
; $4CCE. Rooms 13 and 19 have a dummy record whose column and row are 0.
; Room 0's list is at $4D0C: columns 31 and 38 of tile row 7, and columns
; 2, 25, 29, and 38 of tile row 10. The mounts are $1F and $12. The other
; lists are in rooms.asm.
claim_lamp:
        LDX $51                         ; $331C  the actor
        LDA $E9,X                       ; $331E  his row
        STA $5B                         ; $3320  the row to match
        STY $5A                         ; $3322  the column to match
        LDA $29                         ; $3324  the room
        ASL A                           ; $3326  times 2
        TAX                             ; $3327  the index
        LDA $4CE2,X                     ; $3328  its lamp list, low
        STA $14                         ; $332B  pointer
        LDA $4CE3,X                     ; $332D  high
        STA $15                         ; $3330  pointer
        LDY #$00                        ; $3332  the first record
claim_lamp_record:
        LDA #$01                        ; $3334  all three tests pass so far
        STA $5C                         ; $3336  the match bit
        LDA ($14),Y                     ; $3338  the flag
        BMI claim_lamp_none             ; $333A  the end
        BNE claim_lamp_column           ; $333C  not taken
        LSR $5C                         ; $333E  taken: no match
claim_lamp_column:
        INY                             ; $3340  past the tile
        INY                             ; $3341  to the column
        LDA ($14),Y                     ; $3342  the column
        CMP $5A                         ; $3344  this one?
        BEQ claim_lamp_row              ; $3346  yes
        LSR $5C                         ; $3348  no match
claim_lamp_row:
        INY                             ; $334A  the row
        LDA ($14),Y                     ; $334B  the row
        CMP $5B                         ; $334D  this one?
        BEQ claim_lamp_test             ; $334F  yes
        LSR $5C                         ; $3351  no match
claim_lamp_test:
        LDA $5C                         ; $3353  still set?
        BNE claim_lamp_found            ; $3355  yes: found
        INY                             ; $3357  the next record
        BNE claim_lamp_record           ; $3358  always
claim_lamp_none:
        SEC                             ; $335A  no match
        RTS                             ; $335B  back
claim_lamp_found:
        DEY                             ; $335C  back
        DEY                             ; $335D  to the
        DEY                             ; $335E  flag
        LDA #$00                        ; $335F  zero
        STA ($14),Y                     ; $3361  taken
        LDX $29                         ; $3363  the room
        DEC $2A,X                       ; $3365  one lamp fewer
        INY                             ; $3367  the tile
        LDA ($14),Y                     ; $3368  the mount
        AND #$7F                        ; $336A  without bit 7
        CLC                             ; $336C  found
        RTS                             ; $336D  back
; ($14) becomes the room's lamp list from $4CE2, room*2, for claim_lamp
; and the enter path. Y is left at four times the records in the list.
point_lamp_list:
        LDA $29                         ; $336E  the room
        ASL A                           ; $3370  times 2
        TAX                             ; $3371  the index
        LDA $4CE2,X                     ; $3372  its lamp list, low
        STA $14                         ; $3375  pointer
        LDA $4CE3,X                     ; $3377  high
        STA $15                         ; $337A  pointer
        LDY #$00                        ; $337C  the first record
paint_lamp_record:
        LDA ($14),Y                     ; $337E  the flag
        BMI run_enter_hook              ; $3380  the end: the enter hook
        BNE paint_lamp_skip             ; $3382  not taken: skip
        INY                             ; $3384  the tile
        LDA ($14),Y                     ; $3385  the mount
        PHA                             ; $3387  kept
        INY                             ; $3388  the column
        LDA ($14),Y                     ; $3389  the column
        PHA                             ; $338B  kept
        INY                             ; $338C  the row
        STY $52                         ; $338D  the record's last byte
        LDA ($14),Y                     ; $338F  the row
        TAX                             ; $3391  for point_at_row
        JSR point_at_row                ; $3392  ($04) is the row
        PLA                             ; $3395  the column
        TAY                             ; $3396  in Y
        PLA                             ; $3397  the mount
        AND #$7F                        ; $3398  without bit 7
        STA ($04),Y                     ; $339A  painted
        ORA #$80                        ; $339C  the shadow glyph
        PHA                             ; $339E  kept
        TYA                             ; $339F  the column
        CLC                             ; $33A0  carry clear
        ADC #$28                        ; $33A1  one row down
        TAY                             ; $33A3  the index
        PLA                             ; $33A4  the shadow glyph
        STA ($04),Y                     ; $33A5  painted
        LDY $52                         ; $33A7  the record's last byte
        JMP paint_lamp_next             ; $33A9  the next record
paint_lamp_skip:
        INY                             ; $33AC  skip
        INY                             ; $33AD  the record's
        INY                             ; $33AE  three bytes
paint_lamp_next:
        INY                             ; $33AF  the next record
        JMP paint_lamp_record           ; $33B0  more
run_enter_hook:
        LDX #$04                        ; $33B3  five bytes
        LDA #$00                        ; $33B5  zero
enter_hook_clear:
        STA $4E97,X                     ; $33B7  the room counters at $4E97
        DEX                             ; $33BA  the next
        BPL enter_hook_clear            ; $33BB  more
        LDA $29                         ; $33BD  the room
        ASL A                           ; $33BF  times 2
        TAX                             ; $33C0  the index
        LDA $4E9D,X                     ; $33C1  the hook's address less one, high
        PHA                             ; $33C4  on the stack
        LDA $4E9C,X                     ; $33C5  low
        PHA                             ; $33C8  on the stack
        RTS                             ; $33C9  into the hook
; Put every lamp flag back to 1. A flag with bit 7 set is the end of that
; room's list and is left alone. step_lamp advances four bytes, one record.
; Cold start calls this, and so does the treasure ending, so a finished
; game collects the lamps again. The counts at $2A are a separate copy.
; copy_room_defaults reloads those.
restore_lamps:
        LDA #$13                        ; $33CA  room 19
        STA $4E                         ; $33CC  the room
; Rooms 19 down to 0. X is room*2, an index into $4CE2.
restore_next:
        LDA $4E                         ; $33CE  the room
        ASL A                           ; $33D0  times 2
        TAX                             ; $33D1  the index
        JSR restore_room                ; $33D2  its flags
        DEC $4E                         ; $33D5  the next room
        BPL restore_next                ; $33D7  more
        RTS                             ; $33D9  back
; $14/$15 = this room's lamp list from $4CE2,X.
restore_room:
        LDA $4CE2,X                     ; $33DA  its lamp list, low
        STA $14                         ; $33DD  pointer
        LDA $4CE3,X                     ; $33DF  high
        STA $15                         ; $33E2  pointer
        LDY #$00                        ; $33E4  the first record
; Store 1 in each record's flag until the bit-7 end marker.
next_flag:
        LDA ($14),Y                     ; $33E6  the flag
        BMI list_end                    ; $33E8  the end
        LDA #$01                        ; $33EA  present
        STA ($14),Y                     ; $33EC  stored
        JSR step_lamp                   ; $33EE  the next record
        JMP next_flag                   ; $33F1  more
; The end marker of this room's list.
list_end:
        RTS                             ; $33F4  back

; Per-room hooks. The word at $4E9C, room*2 is the enter hook, and the
; word at $4EC4, room*2 is the per-frame hook. Both store the address
; minus one. point_lamp_list calls the enter hook after the taken lamps are
; painted. run_frame_hook calls the per-frame hook once a logic frame.
;
; Enter hook for rooms 0, 2, 6, 10, and 11.
hook_enter_0:
        RTS                             ; $33F5  back
; Enter hook for room 1. Arms the trap-door count at $4E97 with 3.
hook_enter_1:
        LDA #$03                        ; $33F6  3
        STA $4E97                       ; $33F8  the trap-door count
        RTS                             ; $33FB  back
; Enter hook for room 3.
hook_enter_3:
        LDA #$03                        ; $33FC  3
        STA $4E97                       ; $33FE  the trap-door count
        RTS                             ; $3401  back
; Enter hook for room 4. Arms the three beams. It does not change $64 or
; $65. enter_room has already set the upward direction.
hook_enter_4:
        LDA #$1F                        ; $3402  31
        STA $4E9A                       ; $3404  a room counter
        LDA #$01                        ; $3407  column 1
        STA $71                         ; $3409  beam 1's column
        LDA #$0B                        ; $340B  row 11
        STA $74                         ; $340D  beam 1's row
        LDA #$0B                        ; $340F  column 11
        STA $72                         ; $3411  beam 2's column
        LDA #$07                        ; $3413  row 7
        STA $75                         ; $3415  beam 2's row
        STA $76                         ; $3417  beam 3's row
        LDA #$1A                        ; $3419  column 26
        STA $73                         ; $341B  beam 3's column
        LDA #$FF                        ; $341D  a long wait
        STA $77                         ; $341F  beam 1's timer
        STA $78                         ; $3421  beam 2's timer
        LDA #$F4                        ; $3423  a shorter one
        STA $79                         ; $3425  beam 3's timer
        RTS                             ; $3427  back
; Enter hook for room 5. Repeats until the byte at $02 is $32, writes
; color $FC across $D89A-$D89C and $D8C2-$D8C4, and reloads the three
; beam columns, rows, and timers. $74, $75, and $76 are tile rows 9,
; $0A, and 5. A timer is a byte, so $FF, $FC, and $F8 are the pauses.
hook_enter_5:
        LDX #$00                        ; $3428  from $02
        LDA $02,X                       ; $342A  the check byte
        TAY                             ; $342C  into Y
        CPY #$32                        ; $342D  $32?
        BNE hook_enter_5                ; $342F  no: again, forever
        LDA #$FC                        ; $3431  light grey, multicolor
        LDX #$02                        ; $3433  three cells
hook5_colors:
        STA $D89A,X                     ; $3435  color RAM, row 3 column 34, plus X
        STA $D8C2,X                     ; $3438  color RAM, row 4 column 34, plus X
        DEX                             ; $343B  the next
        BPL hook5_colors                ; $343C  more
        LDA #$1B                        ; $343E  column 27
        STA $71                         ; $3440  beam 1's column
        STA $72                         ; $3442  beam 2's column
        LDA #$01                        ; $3444  column 1
        STA $73                         ; $3446  beam 3's column
        LDA #$09                        ; $3448  row 9
        STA $74                         ; $344A  beam 1's row
        LDA #$0A                        ; $344C  row 10
        STA $75                         ; $344E  beam 2's row
        LDA #$05                        ; $3450  row 5
        STA $76                         ; $3452  beam 3's row
        LDA #$FF                        ; $3454  the longest pause
        STA $77                         ; $3456  beam 1's timer
        LDA #$FC                        ; $3458  shorter
        STA $78                         ; $345A  beam 2's timer
        LDA #$F8                        ; $345C  shorter still
        STA $79                         ; $345E  beam 3's timer
        RTS                             ; $3460  back
; Enter hook for room 7.
hook_enter_7:
        LDA #$05                        ; $3461  column 5
        STA $6E                         ; $3463  the block's column
        STA $70                         ; $3465  the column it left
        LDA #$0B                        ; $3467  row 11
        STA $6F                         ; $3469  the block's row
        LDA #$22                        ; $346B  column 34
        STA $71                         ; $346D  beam 1's column
        LDA #$04                        ; $346F  row 4
        STA $74                         ; $3471  beam 1's row
        LDA #$FF                        ; $3473  a long wait
        STA $77                         ; $3475  beam 1's timer
        RTS                             ; $3477  back
; Enter hook for room 8.
hook_enter_8:
        LDA #$06                        ; $3478  column 6
        STA $71                         ; $347A  beam 1's column
        LDA #$1B                        ; $347C  column 27
        STA $72                         ; $347E  beam 2's column
        LDA #$05                        ; $3480  row 5
        STA $74                         ; $3482  beam 1's row
        STA $75                         ; $3484  beam 2's row
        LDA #$FF                        ; $3486  a long wait
        STA $77                         ; $3488  beam 1's timer
        LDA #$F2                        ; $348A  a shorter one
        STA $78                         ; $348C  beam 2's timer
        RTS                             ; $348E  back
; Enter hook for room 9.
hook_enter_9:
        LDA #$FA                        ; $348F  grey, multicolor
        LDX #$03                        ; $3491  four cells
hook9_colors:
        STA $D89B,X                     ; $3493  color RAM, row 3 column 35, plus X
        STA $D8C3,X                     ; $3496  color RAM, row 4 column 35, plus X
        DEX                             ; $3499  the next
        BPL hook9_colors                ; $349A  more
        LDA #$04                        ; $349C  column 4
        STA $6E                         ; $349E  the block's column
        STA $70                         ; $34A0  the column it left
        LDA #$0C                        ; $34A2  row 12
        STA $6F                         ; $34A4  the block's row
        LDA #$10                        ; $34A6  column 16
        STA $71                         ; $34A8  beam 1's column
        STA $72                         ; $34AA  beam 2's column
        LDA #$05                        ; $34AC  row 5
        STA $74                         ; $34AE  beam 1's row
        LDA #$06                        ; $34B0  row 6
        STA $75                         ; $34B2  beam 2's row
        LDA #$FC                        ; $34B4  a shorter wait
        STA $77                         ; $34B6  beam 1's timer
        LDA #$FF                        ; $34B8  a long wait
        STA $78                         ; $34BA  beam 2's timer
        RTS                             ; $34BC  back
; Enter hook for room 12.
hook_enter_12:
        LDA #$01                        ; $34BD  1
        STA $4E97                       ; $34BF  a room counter
        RTS                             ; $34C2  back
; Enter hook for room 13.
hook_enter_13:
        LDX #$04                        ; $34C3  five slots each
hook13_sliders:
        LDA #$02                        ; $34C5  left
        STA $010F,X                     ; $34C7  sliders 0-4 move left
        LDA #$82                        ; $34CA  right
        STA $0114,X                     ; $34CC  sliders 5-9 move right
        DEX                             ; $34CF  the next
        BPL hook13_sliders              ; $34D0  more
        LDA #$00                        ; $34D2  zero
        STA $0118                       ; $34D4  slider 9 still. step_sliders walks 0-8 only
        STA $0112                       ; $34D7  slider 3 empty
        LDA #$06                        ; $34DA  6
        STA $0138                       ; $34DC  slider 1's left bound
        STA $011E                       ; $34DF  slider 5's column
        STA $0132                       ; $34E2  slider 5's old column
        STA $013C                       ; $34E5  slider 5's left bound
        STA $013D                       ; $34E8  slider 6's left bound
        LDA #$02                        ; $34EB  2
        STA $011B                       ; $34ED  slider 2's column
        STA $012F                       ; $34F0  slider 2's old column
        STA $0139                       ; $34F3  slider 2's left bound
        STA $013B                       ; $34F6  slider 4's left bound
        LDX $40                         ; $34F9  a set $40?
        BNE hook13_store_a              ; $34FB  yes: 2
        LDA #$06                        ; $34FD  6
hook13_store_a:
        STA $0120                       ; $34FF  slider 7's column
        STA $0134                       ; $3502  slider 7's old column
        STA $013E                       ; $3505  slider 7's left bound
        LDA #$12                        ; $3508  $12
        LDX $40                         ; $350A  a set $40?
        BNE hook13_store_b              ; $350C  yes: $12
        LDA #$14                        ; $350E  $14
hook13_store_b:
        STA $0137                       ; $3510  slider 0's left bound
        STA $0148                       ; $3513  slider 7's right bound
        LDA #$15                        ; $3516  $15
        LDX $40                         ; $3518  a set $40?
        BNE hook13_store_c              ; $351A  yes: $15
        LDA #$13                        ; $351C  $13
hook13_store_c:
        STA $011A                       ; $351E  slider 1's column
        STA $012E                       ; $3521  slider 1's old column
        STA $0142                       ; $3524  slider 1's right bound
        LDA #$16                        ; $3527  $16
        STA $011F                       ; $3529  slider 6's column
        STA $0133                       ; $352C  slider 6's old column
        STA $011D                       ; $352F  slider 4's column
        STA $0131                       ; $3532  slider 4's old column
        LDX $40                         ; $3535  a set $40?
        BNE hook13_store_d              ; $3537  yes: $16
        LDA #$14                        ; $3539  $14
hook13_store_d:
        STA $0121                       ; $353B  slider 8's column
        STA $0135                       ; $353E  slider 8's old column
        STA $013F                       ; $3541  slider 8's left bound
        LDA #$21                        ; $3544  $21
        STA $0119                       ; $3546  slider 0's column
        STA $012D                       ; $3549  slider 0's old column
        STA $0141                       ; $354C  slider 0's right bound
        LDX $40                         ; $354F  a set $40?
        BEQ hook13_store_e              ; $3551  no: $21
        LDA #$25                        ; $3553  $25
hook13_store_e:
        STA $0143                       ; $3555  slider 2's right bound
        STA $0145                       ; $3558  slider 4's right bound
        LDA #$26                        ; $355B  $26
        LDX $40                         ; $355D  a set $40?
        BNE hook13_store_f              ; $355F  yes: $26
        LDA #$22                        ; $3561  $22
hook13_store_f:
        STA $0146                       ; $3563  slider 5's right bound
        STA $0147                       ; $3566  slider 6's right bound
        STA $0149                       ; $3569  slider 8's right bound
        LDA #$05                        ; $356C  row 5
        STA $0128                       ; $356E  slider 5's row
        STA $0129                       ; $3571  slider 6's row
        LDA #$07                        ; $3574  row 7
        STA $0123                       ; $3576  slider 0's row
        STA $012A                       ; $3579  slider 7's row
        LDA #$0A                        ; $357C  row 10
        STA $0124                       ; $357E  slider 1's row
        STA $012B                       ; $3581  slider 8's row
        LDA #$0C                        ; $3584  row 12
        STA $0125                       ; $3586  slider 2's row
        STA $0127                       ; $3589  slider 4's row
        RTS                             ; $358C  back
; Enter hook for room 14.
hook_enter_14:
        LDA #$01                        ; $358D  1
        STA $4E97                       ; $358F  a room counter
        RTS                             ; $3592  back
; Enter hook for room 15.
hook_enter_15:
        LDA #$01                        ; $3593  1
        STA $4E97                       ; $3595  room counter 1
        STA $4E98                       ; $3598  room counter 2
        STA $4E99                       ; $359B  room counter 3
        RTS                             ; $359E  back
; Enter hook for room 16.
hook_enter_16:
        LDA #$FF                        ; $359F  light grey, multicolor
        STA $DB1C                       ; $35A1  color RAM, row 19 column 36
        STA $DB1D                       ; $35A4  color RAM, row 19 column 37
        STA $DB44                       ; $35A7  color RAM, row 20 column 36
        STA $DB45                       ; $35AA  color RAM, row 20 column 37
        STA $DB6C                       ; $35AD  color RAM, row 21 column 36
        STA $DB6D                       ; $35B0  color RAM, row 21 column 37
        STA $DB94                       ; $35B3  color RAM, row 22 column 36
        STA $DB95                       ; $35B6  color RAM, row 22 column 37
; $4E95,X counts down in extra_fall and is not a gate there. Once it has
; reached 0, entering the room prints the caption without giving another fall.
        LDX $03                         ; $35B9  the player
        LDA $4E95,X                     ; $35BB  his extra falls left here
        BNE hook16_done                 ; $35BE  some left
        JSR extra_fall_caption          ; $35C0  the caption
hook16_done:
        RTS                             ; $35C3  back
; Enter hook for room 17.
hook_enter_17:
        LDA #$FF                        ; $35C4  light grey, multicolor
        STA $DB1E                       ; $35C6  color RAM, row 19 column 38
        LDA #$01                        ; $35C9  1
        STA $4E97                       ; $35CB  room counter 1
        STA $4E98                       ; $35CE  room counter 2
        LDA #$08                        ; $35D1  column 8
        STA $71                         ; $35D3  beam 1's column
        STA $72                         ; $35D5  beam 2's column
        STA $73                         ; $35D7  beam 3's column
        LDA #$03                        ; $35D9  row 3
        STA $74                         ; $35DB  beam 1's row
        LDA #$05                        ; $35DD  row 5
        STA $6F                         ; $35DF  the block's row
        LDA #$07                        ; $35E1  row 7
        STA $75                         ; $35E3  beam 2's row
        LDA #$09                        ; $35E5  row 9
        STA $76                         ; $35E7  beam 3's row
        LDA #$0B                        ; $35E9  column 11
        STA $6E                         ; $35EB  the block's column
        LDA #$F8                        ; $35ED  a wait
        STA $77                         ; $35EF  beam 1's timer
        LDA #$F1                        ; $35F1  a longer one
        STA $78                         ; $35F3  beam 2's timer
        LDA #$EA                        ; $35F5  longer still
        STA $79                         ; $35F7  beam 3's timer
        RTS                             ; $35F9  back
; Enter hook for room 18.
hook_enter_18:
        LDX #$00                        ; $35FA  256 bytes a page
        LDA #$FE                        ; $35FC  light blue, multicolor
hook18_colors:
        STA $D878,X                     ; $35FE  color RAM, row 3 column 0, plus X
        STA $D900,X                     ; $3601  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $3604  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $3607  color RAM, row 19 column 8, plus X
        INX                             ; $360A  the next
        BNE hook18_colors               ; $360B  until X wraps
        LDX #$7F                        ; $360D  128 bytes
        LDA #$00                        ; $360F  zero
hook18_clear_sprite:
        STA $8340,X                     ; $3611  sprite images $0D-$0E
        DEX                             ; $3614  the next
        BPL hook18_clear_sprite         ; $3615  more
        STA $D017                       ; $3617  sprite double height
        LDA #$FF                        ; $361A  every sprite
        STA $D01D                       ; $361C  sprite double width
        LDA #$01                        ; $361F  1
        STA $4E97                       ; $3621  room counter 0
        STA $4E98                       ; $3624  room counter 1
        LDA #$00                        ; $3627  zero
        STA $432E                       ; $3629  the flash state
        STA $432F                       ; $362C  cleared
        STA $4330                       ; $362F  cleared
        LDA #$10                        ; $3632  16
        STA $4331                       ; $3634  the flash count
        LDA #$06                        ; $3637  6
        STA $4336                       ; $3639  a flash setting
        LDA #$07                        ; $363C  7
        STA $4337                       ; $363E  a flash setting
        RTS                             ; $3641  back
; Per-frame hook for room 0.
hook_frame_0:
        LDA $30                         ; $3642  room 6's lamps left
        BNE hook0_done                  ; $3644  lamps left in room 6: no blink
        LDA $7B                         ; $3646  the hook phase
        BNE hook0_done                  ; $3648  the off frame: skip
        DEC $4E97                       ; $364A  room counter 0, one less
        BPL hook0_done                  ; $364D  not yet
        LDA $4E98                       ; $364F  room counter 1
        BNE hook0_blink_off             ; $3652  the lit phase is showing
; Effect $81 with string $1D. The other phase of this blink is silent.
        LDY #$81                        ; $3654  effect $81
        JSR play_sound                  ; $3656  queue it
        LDA #$1D                        ; $3659  string $1D
        LDX #$09                        ; $365B  tile row $09
        LDY #$07                        ; $365D  column $07
        JSR print_string                ; $365F  print it
        INC $4E98                       ; $3662  room counter 1, one more
        BNE hook0_done                  ; $3665  always
hook0_blink_off:
        LDA #$1E                        ; $3667  string $1E
        LDX #$09                        ; $3669  tile row $09
        LDY #$07                        ; $366B  column $07
        JSR print_string                ; $366D  print it
        DEC $4E98                       ; $3670  room counter 1, one less
        LDA #$05                        ; $3673  five steps
        STA $4E97                       ; $3675  room counter 0
hook0_done:
        RTS                             ; $3678  back
; Per-frame hook for room 1. Opens the trap door in the floor. $2A,
; $2B, and $2C have to be zero, which is every lamp in rooms 0, 1, and
; 2 taken. $30 is room 6's count and has to be nonzero, so the door
; stays shut once room 6 is clear. $4E97 then counts 3, 2, 1, 0, $FF.
; Each step prints five tiles at column $11 of tile row $0C. The first
; step, when the count becomes 2, calls play_sound_8a.
;
; print_string subtracts $20 from each byte and stops on $A0. The four
; strings, and the tiles they become, are:
;
;   $12 at $45AA: 31 7C 7D 7E 7F A0    tiles 11 5C 5D 5E 5F
;   $11 at $45B0: 31 42 42 A3 A3 A0    tiles 11 22 22 03 03
;   $10 at $45B6: 7C 7D 7E A3 A3 A0    tiles 5C 5D 5E 03 03
;   $0F at $45BC: 42 42 A3 A3 A3 A0    tiles 22 22 03 03 03
;
; Tile $03 is the exit in slot 1, so the open hole leads to room 5.
; The packed stream is still the closed floor: columns $11-$15 of that
; row are tiles 11 11 22 22 11 until this hook paints over them. Coming
; back into the room decompresses that floor and arms $4E97 with 3.
hook_frame_1:
        LDA $7B                         ; $3679  the hook phase
        BNE hook1_done                  ; $367B  the off frame: skip
        LDA $4E97                       ; $367D  room counter 0
        BMI hook1_done                  ; $3680  spent: the door is open
        LDA $30                         ; $3682  room 6's lamps left
        BEQ hook1_done                  ; $3684  room 6 clear: shut for good
        LDA $2A                         ; $3686  room 0's lamps left
        ORA $2B                         ; $3688  room 1's lamps left
        ORA $2C                         ; $368A  room 2's lamps left
        BNE hook1_done                  ; $368C  lamps left: shut
        DEC $4E97                       ; $368E  room counter 0, one less
        LDA $4E97                       ; $3691  room counter 0
        CMP #$02                        ; $3694  2?
        BNE hook1_paint_door            ; $3696  no
        JSR play_sound_8a               ; $3698  effect $8A
hook1_paint_door:
        CLC                             ; $369B  carry clear
        ADC #$10                        ; $369C  the door string for this step
        LDX #$0C                        ; $369E  tile row $0C
        LDY #$11                        ; $36A0  column $11
        JMP print_string                ; $36A2  print it, and return from there
hook1_done:
        RTS                             ; $36A5  back
; Per-frame hook for room 2.
hook_frame_2:
        NOP                             ; $36A6  eight spare bytes
        NOP                             ; $36A7  spare
        NOP                             ; $36A8  spare
        NOP                             ; $36A9  spare
        NOP                             ; $36AA  spare
        NOP                             ; $36AB  spare
        NOP                             ; $36AC  spare
        NOP                             ; $36AD  spare
        LDA $30                         ; $36AE  room 6's lamps left
        BNE hook2_done                  ; $36B0  lamps left in room 6: nothing
        LDA $4E98                       ; $36B2  room counter 1
        BMI hook2_blink                 ; $36B5  the passage is open already
        DEC $4E98                       ; $36B7  room counter 1, one less
        JSR play_sound_8a               ; $36BA  effect $8A
        LDA #$1A                        ; $36BD  string $1A
        LDX #$0B                        ; $36BF  tile row $0B
        LDY #$25                        ; $36C1  column $25
        JSR print_string                ; $36C3  print it
        LDA #$07                        ; $36C6  string $07
        LDX #$0C                        ; $36C8  tile row $0C
        LDY #$25                        ; $36CA  column $25
        JSR print_string                ; $36CC  print it
hook2_blink:
        LDA $7B                         ; $36CF  the hook phase
        BNE hook2_done                  ; $36D1  the off frame: skip
        DEC $4E99                       ; $36D3  room counter 2, one less
        BPL hook2_done                  ; $36D6  not yet
        LDA $4E97                       ; $36D8  room counter 0
        BNE hook2_blink_off             ; $36DB  the lit phase is showing
; Effect $81 with string $1D. The other phase of this blink is silent.
        LDY #$81                        ; $36DD  effect $81
        JSR play_sound                  ; $36DF  queue it
        LDA #$1D                        ; $36E2  string $1D
        LDX #$09                        ; $36E4  tile row $09
        LDY #$21                        ; $36E6  column $21
        JSR print_string                ; $36E8  print it
        INC $4E97                       ; $36EB  room counter 0, one more
        BNE hook2_done                  ; $36EE  always
hook2_blink_off:
        LDA #$1E                        ; $36F0  string $1E
        LDX #$09                        ; $36F2  tile row $09
        LDY #$21                        ; $36F4  column $21
        JSR print_string                ; $36F6  print it
        DEC $4E97                       ; $36F9  room counter 0, one less
        LDA #$05                        ; $36FC  five steps
        STA $4E99                       ; $36FE  room counter 2
hook2_done:
        RTS                             ; $3701  back
; Per-frame hook for room 3.
hook_frame_3:
        LDA $7B                         ; $3702  the hook phase
        BNE hook3_swap_timer            ; $3704  the off frame
        LDA $4E97                       ; $3706  room counter 0
        BMI hook3_swap_timer            ; $3709  spent
        LDA $2D                         ; $370B  room 3's lamps left
        BNE hook3_swap_timer            ; $370D  lamps left: shut
        DEC $4E97                       ; $370F  room counter 0, one less
        LDA $4E97                       ; $3712  room counter 0
        CMP #$02                        ; $3715  2?
        BNE hook3_paint_door            ; $3717  no
        JSR play_sound_8a               ; $3719  effect $8A
hook3_paint_door:
        CLC                             ; $371C  carry clear
        ADC #$10                        ; $371D  the door string for this step
        LDX #$0C                        ; $371F  tile row $0C
        LDY #$1D                        ; $3721  column $1D
        JSR print_string                ; $3723  print it
hook3_swap_timer:
        DEC $4E99                       ; $3726  room counter 2, one less
        BMI hook3_swap                  ; $3729  time for the swap
        RTS                             ; $372B  back
hook3_swap:
        LDA #$20                        ; $372C  32 steps
        STA $4E99                       ; $372E  room counter 2
        LDA $4E98                       ; $3731  room counter 1
        BEQ hook3_swap_back             ; $3734  the first state
        DEC $4E98                       ; $3736  room counter 1, one less
        LDA #$06                        ; $3739  string $06
        LDX #$06                        ; $373B  tile row $06
        LDY #$09                        ; $373D  column $09
        JSR print_string                ; $373F  print it
        LDA #$60                        ; $3742  string $60
        LDX #$06                        ; $3744  tile row $06
        LDY #$15                        ; $3746  column $15
        JMP print_string                ; $3748  print it, and return from there
hook3_swap_back:
        INC $4E98                       ; $374B  room counter 1, one more
        LDA #$60                        ; $374E  string $60
        LDX #$06                        ; $3750  tile row $06
        LDY #$09                        ; $3752  column $09
        JSR print_string                ; $3754  print it
        LDA #$06                        ; $3757  string $06
        LDX #$06                        ; $3759  tile row $06
        LDY #$15                        ; $375B  column $15
        JMP print_string                ; $375D  print it, and return from there
; Per-frame hook for room 4. It ends in scroll_surface. The ladder is the
; vertical run of tiles $61, $62, $62, $63.
hook_frame_4:
        LDA $4D70                       ; $3760  the flag of lamp $4D70
        BEQ hook4_open_door             ; $3763  taken: the door
        INC $4E99                       ; $3765  room counter 2, one more
        LDA $4E99                       ; $3768  room counter 2
        CMP #$20                        ; $376B  32?
        BNE hook4_lamp_blink_off        ; $376D  no
        LDA #$34                        ; $376F  string $34
        LDX #$04                        ; $3771  tile row $04
        LDY #$0B                        ; $3773  column $0B
        JSR print_string                ; $3775  print it
        JMP hook4_open_door             ; $3778  the door test
hook4_lamp_blink_off:
        CMP #$40                        ; $377B  64?
        BNE hook4_open_door             ; $377D  no
        LDA #$00                        ; $377F  zero
        STA $4E99                       ; $3781  room counter 2
        LDA #$36                        ; $3784  string $36
        LDX #$04                        ; $3786  tile row $04
        LDY #$0B                        ; $3788  column $0B
        JSR print_string                ; $378A  print it
hook4_open_door:
        LDA $4D70                       ; $378D  the flag of lamp $4D70
        BNE hook4_second_lamp           ; $3790  still there: shut
        LDA $4E97                       ; $3792  room counter 0
        BMI hook4_second_lamp           ; $3795  spent: open already
        DEC $4E97                       ; $3797  room counter 0, one less
        JSR play_sound_8a               ; $379A  effect $8A
        LDA #$16                        ; $379D  string $16
        LDX #$08                        ; $379F  tile row $08
        LDY #$0B                        ; $37A1  column $0B
        JSR print_string                ; $37A3  print it
        LDA #$16                        ; $37A6  string $16
        LDX #$09                        ; $37A8  tile row $09
        LDY #$0B                        ; $37AA  column $0B
        JSR print_string                ; $37AC  print it
        LDA #$06                        ; $37AF  the blank frame
        JSR print_row75                 ; $37B1  erase beam 2
hook4_second_lamp:
        LDA $4D74                       ; $37B4  the flag of lamp $4D74
        BEQ hook4_open_second_door      ; $37B7  taken: the door
        INC $4E9A                       ; $37B9  room counter 3, one more
        LDA $4E9A                       ; $37BC  room counter 3
        CMP #$20                        ; $37BF  32?
        BNE hook4_lamp2_blink_off       ; $37C1  no
        LDA #$35                        ; $37C3  string $35
        LDX #$04                        ; $37C5  tile row $04
        LDY #$1C                        ; $37C7  column $1C
        JSR print_string                ; $37C9  print it
        JMP hook4_open_second_door      ; $37CC  the door test
hook4_lamp2_blink_off:
        CMP #$40                        ; $37CF  64?
        BNE hook4_open_second_door      ; $37D1  no
        LDA #$00                        ; $37D3  zero
        STA $4E9A                       ; $37D5  room counter 3
        LDA #$37                        ; $37D8  string $37
        LDX #$04                        ; $37DA  tile row $04
        LDY #$1C                        ; $37DC  column $1C
        JSR print_string                ; $37DE  print it
hook4_open_second_door:
        LDA $4D74                       ; $37E1  the flag of lamp $4D74
        BNE hook4_beam1                 ; $37E4  still there: shut
        LDA $4E98                       ; $37E6  room counter 1
        BMI hook4_beam1                 ; $37E9  spent: open already
        DEC $4E98                       ; $37EB  room counter 1, one less
; Lamp $4D74 has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $37EE  zero
        STA $65                         ; $37F0  the surface moves up
        LDA #$07                        ; $37F2  the last slot
        STA $4321                       ; $37F4  the surface's delay slot
        JSR play_sound_8a               ; $37F7  effect $8A
        LDA #$16                        ; $37FA  string $16
        LDX #$08                        ; $37FC  tile row $08
        LDY #$19                        ; $37FE  column $19
        JSR print_string                ; $3800  print it
        LDA #$16                        ; $3803  string $16
        LDX #$09                        ; $3805  tile row $09
        LDY #$19                        ; $3807  column $19
        JSR print_string                ; $3809  print it
        LDA #$06                        ; $380C  the blank frame
        JSR print_row76                 ; $380E  erase beam 3
hook4_beam1:
        INC $77                         ; $3811  beam 1's timer, one on
        BMI hook4_beam2                 ; $3813  still pausing
        LDA $77                         ; $3815  beam 1's timer
        CMP #$03                        ; $3817  3?
        BEQ hook4_beam1_advance         ; $3819  yes: step on
        CMP #$07                        ; $381B  7?
        BEQ hook4_beam1_reload          ; $381D  yes: reload
hook4_beam1_draw:
        JSR print_row74_later           ; $381F  draw this frame
        JMP hook4_beam2                 ; $3822  the next beam
hook4_beam1_advance:
        LDX $71                         ; $3825  beam 1's column
        CPX #$03                        ; $3827  at the limit?
        BCS hook4_beam1_draw            ; $3829  yes: just draw
        LDA #$06                        ; $382B  the blank frame
        JSR print_row74_later           ; $382D  erase it
        INC $71                         ; $3830  beam 1's column, one on
        LDA #$02                        ; $3832  frame 2
        STA $77                         ; $3834  beam 1's timer
        BNE hook4_beam1_draw            ; $3836  always
hook4_beam1_reload:
        LDA #$A0                        ; $3838  a long pause
        STA $77                         ; $383A  beam 1's timer
        LDA #$01                        ; $383C  column 1
        STA $71                         ; $383E  beam 1's column
hook4_beam2:
        LDA $4D70                       ; $3840  the flag of lamp $4D70
        BEQ hook4_beam3                 ; $3843  taken: no beam 2
        INC $78                         ; $3845  beam 2's timer, one on
        BMI hook4_beam3                 ; $3847  still pausing
        LDA $78                         ; $3849  beam 2's timer
        CMP #$03                        ; $384B  3?
        BEQ hook4_beam2_advance         ; $384D  yes: step on
        CMP #$07                        ; $384F  7?
        BEQ hook4_beam2_reload          ; $3851  yes: reload
hook4_beam2_draw:
        JSR print_row75                 ; $3853  draw this frame
        JMP hook4_beam3                 ; $3856  the next beam
hook4_beam2_advance:
        LDX $72                         ; $3859  beam 2's column
        CPX #$0C                        ; $385B  at the limit?
        BCS hook4_beam2_draw            ; $385D  yes: just draw
        LDA #$06                        ; $385F  the blank frame
        JSR print_row75                 ; $3861  erase it
        INC $72                         ; $3864  beam 2's column, one on
        LDA #$02                        ; $3866  frame 2
        STA $78                         ; $3868  beam 2's timer
        BNE hook4_beam2_draw            ; $386A  always
hook4_beam2_reload:
        LDA #$E4                        ; $386C  a pause
        STA $78                         ; $386E  beam 2's timer
        LDA #$0B                        ; $3870  column 11
        STA $72                         ; $3872  beam 2's column
hook4_beam3:
        LDA $4D74                       ; $3874  the flag of lamp $4D74
        BEQ hook4_scroll                ; $3877  taken: no beam 3
        INC $79                         ; $3879  beam 3's timer, one on
        BMI hook4_scroll                ; $387B  still pausing
        LDA $79                         ; $387D  beam 3's timer
        CMP #$03                        ; $387F  3?
        BEQ hook4_beam3_advance         ; $3881  yes: step on
        CMP #$07                        ; $3883  7?
        BEQ hook4_beam3_reload          ; $3885  yes: reload
hook4_beam3_draw:
        JSR print_row76                 ; $3887  draw this frame
        JMP hook4_scroll                ; $388A  the surface
hook4_beam3_advance:
        LDX $73                         ; $388D  beam 3's column
        CPX #$1B                        ; $388F  at the limit?
        BCS hook4_beam3_draw            ; $3891  yes: just draw
        LDA #$06                        ; $3893  the blank frame
        JSR print_row76                 ; $3895  erase it
        INC $73                         ; $3898  beam 3's column, one on
        LDA #$02                        ; $389A  frame 2
        STA $79                         ; $389C  beam 3's timer
        BNE hook4_beam3_draw            ; $389E  always
hook4_beam3_reload:
        LDA #$E4                        ; $38A0  a pause
        STA $79                         ; $38A2  beam 3's timer
        LDA #$1A                        ; $38A4  column 26
        STA $73                         ; $38A6  beam 3's column
hook4_scroll:
        JMP scroll_surface              ; $38A8  the surface, and return from there
; Per-frame hook for room 5. It does not read $7B, so the beams move on
; every logic frame. These are energy beams.
;
; $71/$77 slides the beam under the middle gap on tile row $74.
; $72/$78 slides the beam on tile row $75, the next row down. Both run
; from column $1B to column $1C. $73/$79 slides the beam at the left of
; the upper level, tile row $76, from column $01 to column $02. Count 3
; erases with accumulator 6 and, while the column is still left of the
; limit, steps one column right and draws accumulator 2. Count 7
; reloads the column and the pause. $E0 is -32 and $E2 is -30.
;
; print_row74 and print_row75 add $1F to the frame. The two gap beams
; use strings $1F-$25:
;   56 / 55 / 55 56 / 54 55 / 00 55 / 00 54 / 00 00
; print_row76_later adds 7 before that, so the upper beam uses strings
; $26-$2C:
;   5A / 59 / 59 5A / 58 59 / 00 59 / 00 58 / 00 00
;
; The second beam runs only when $4D99 is nonzero. The opening snapshot
; holds 1 there, and nothing from $0500 to $4FFF stores $4D99.
;
; The blocks above the beam counters are one-shots on $4E99, $4E9A,
; and $4E9B. Each waits while its $4Dxx flag is still clear. The hook
; ends in scroll_surface.
hook_frame_5:
        LDA $4D99                       ; $38AB  the flag of lamp $4D99
        BNE hook5_second_passage        ; $38AE  still there: shut
        LDA $4E99                       ; $38B0  room counter 2
        BMI hook5_second_passage        ; $38B3  spent: open already
        DEC $4E99                       ; $38B5  room counter 2, one less
        LDA #$0A                        ; $38B8  row 10
        LDY #$19                        ; $38BA  column 25
        JSR draw_passage                ; $38BC  open it
        LDA #$0A                        ; $38BF  row 10
        LDY #$1A                        ; $38C1  column 26
        JSR draw_passage                ; $38C3  open it
        LDA #$06                        ; $38C6  the blank frame
        JSR print_row75                 ; $38C8  erase beam 2
hook5_second_passage:
        LDA $4D91                       ; $38CB  the flag of lamp $4D91
        BNE hook5_third_passage         ; $38CE  still there: shut
        LDA $4E9A                       ; $38D0  room counter 3
        BMI hook5_third_passage         ; $38D3  spent
        DEC $4E9A                       ; $38D5  room counter 3, one less
        LDA #$0A                        ; $38D8  row 10
        LDY #$00                        ; $38DA  column 0
        JSR draw_passage                ; $38DC  open it
        LDA #$15                        ; $38DF  string $15
        LDX #$0B                        ; $38E1  tile row $0B
        LDY #$00                        ; $38E3  column $00
        JSR print_string                ; $38E5  print it
hook5_third_passage:
        LDA $30                         ; $38E8  room 6's lamps left
        ORA $4D81                       ; $38EA  the flag of lamp $4D81
        BEQ hook5_open_third            ; $38ED  either clear: open
        LDA $30                         ; $38EF  room 6's lamps left
        ORA $4D89                       ; $38F1  the flag of lamp $4D89
        BNE hook5_beam1                 ; $38F4  neither: shut
hook5_open_third:
        LDA $4E9B                       ; $38F6  room counter 4
        BMI hook5_beam1                 ; $38F9  spent
        DEC $4E9B                       ; $38FB  room counter 4, one less
        LDA #$19                        ; $38FE  string $19
        LDX #$02                        ; $3900  tile row $02
        LDY #$22                        ; $3902  column $22
        JSR print_string                ; $3904  print it
        LDA #$03                        ; $3907  row 3
        LDY #$1E                        ; $3909  column 30
        JSR draw_passage                ; $390B  open it
        LDA #$06                        ; $390E  row 6
        LDY #$20                        ; $3910  column 32
        JSR draw_passage                ; $3912  open it
hook5_beam1:
        INC $77                         ; $3915  beam 1's timer, one on
        BMI hook5_beam2                 ; $3917  still pausing
        LDA $77                         ; $3919  beam 1's timer
        CMP #$03                        ; $391B  3?
        BEQ hook5_beam1_advance         ; $391D  yes: step on
        CMP #$07                        ; $391F  7?
        BEQ hook5_beam1_reload          ; $3921  yes: reload
hook5_beam1_draw:
        JSR print_row74                 ; $3923  draw this frame
        JMP hook5_beam2                 ; $3926  to the next part
hook5_beam1_advance:
        LDX $71                         ; $3929  beam 1's column
        CPX #$1C                        ; $392B  at the limit?
        BCS hook5_beam1_draw            ; $392D  yes: just draw
        LDA #$06                        ; $392F  the blank frame
        JSR print_row74                 ; $3931  erase it
        INC $71                         ; $3934  beam 1's column, one on
        LDA #$02                        ; $3936  frame 2
        STA $77                         ; $3938  beam 1's timer
        BNE hook5_beam1_draw            ; $393A  always
hook5_beam1_reload:
        LDA #$E0                        ; $393C  a pause
        STA $77                         ; $393E  beam 1's timer
        LDA #$1B                        ; $3940  column 27
        STA $71                         ; $3942  beam 1's column
hook5_beam2:
        LDA $4D99                       ; $3944  the flag of lamp $4D99
        BEQ hook5_beam3                 ; $3947  taken
        INC $78                         ; $3949  beam 2's timer, one on
        BMI hook5_beam3                 ; $394B  still pausing
        LDA $78                         ; $394D  beam 2's timer
        CMP #$03                        ; $394F  3?
        BEQ hook5_beam2_advance         ; $3951  yes: step on
        CMP #$07                        ; $3953  7?
        BEQ hook5_beam2_reload          ; $3955  yes: reload
hook5_beam2_draw:
        JSR print_row75                 ; $3957  draw this frame
        JMP hook5_beam3                 ; $395A  to the next part
hook5_beam2_advance:
        LDX $72                         ; $395D  beam 2's column
        CPX #$1C                        ; $395F  at the limit?
        BCS hook5_beam2_draw            ; $3961  yes: just draw
        LDA #$06                        ; $3963  the blank frame
        JSR print_row75                 ; $3965  erase it
        INC $72                         ; $3968  beam 2's column, one on
        LDA #$02                        ; $396A  frame 2
        STA $78                         ; $396C  beam 2's timer
        BNE hook5_beam2_draw            ; $396E  always
hook5_beam2_reload:
        LDA #$E0                        ; $3970  a pause
        STA $78                         ; $3972  beam 2's timer
        LDA #$1B                        ; $3974  column 27
        STA $72                         ; $3976  beam 2's column
hook5_beam3:
        INC $79                         ; $3978  beam 3's timer, one on
        BMI hook5_scroll                ; $397A  still pausing
        LDA $79                         ; $397C  beam 3's timer
        CMP #$03                        ; $397E  3?
        BEQ hook5_beam3_advance         ; $3980  yes: step on
        CMP #$07                        ; $3982  7?
        BEQ hook5_beam3_reload          ; $3984  yes: reload
hook5_beam3_draw:
        JSR print_row76_later           ; $3986  draw this frame
        JMP hook5_scroll                ; $3989  to the next part
hook5_beam3_advance:
        LDX $73                         ; $398C  beam 3's column
        CPX #$02                        ; $398E  at the limit?
        BCS hook5_beam3_draw            ; $3990  yes: just draw
        LDA #$06                        ; $3992  the blank frame
        JSR print_row76_later           ; $3994  erase it
        INC $73                         ; $3997  beam 3's column, one on
        LDA #$02                        ; $3999  frame 2
        STA $79                         ; $399B  beam 3's timer
        BNE hook5_beam3_draw            ; $399D  always
hook5_beam3_reload:
        LDA #$E2                        ; $399F  a pause
        STA $79                         ; $39A1  beam 3's timer
        LDA #$01                        ; $39A3  column 1
        STA $73                         ; $39A5  beam 3's column
hook5_scroll:
        JMP scroll_surface              ; $39A7  the surface, and return from there
; Per-frame hook for room 6. It ends in scroll_surface.
hook_frame_6:
        LDA $30                         ; $39AA  room 6's lamps left
        BNE hook6_crumble               ; $39AC  lamps left
        LDA $4E97                       ; $39AE  room counter 0
        BMI hook6_crumble               ; $39B1  spent
        DEC $4E97                       ; $39B3  room counter 0, one less
        LDA #$05                        ; $39B6  row 5
        LDY #$01                        ; $39B8  column 1
        JSR draw_passage_17             ; $39BA  open it
hook6_crumble:
        JSR step_crumble                ; $39BD  the nozzle flames
        JMP scroll_surface              ; $39C0  the surface, and return from there
; Per-frame hook for room 7. step_crumble runs first. The hook itself runs
; before the overlap, so a nozzle armed on the previous frame is still
; screen code $60 when that walk is tested again.
hook_frame_7:
        JSR step_crumble                ; $39C3  the nozzle flames
        LDA $4DC3                       ; $39C6  the flag of lamp $4DC3
        ORA $4DC7                       ; $39C9  the flag of lamp $4DC7
        ORA $4DCB                       ; $39CC  the flag of lamp $4DCB
        ORA $4DCF                       ; $39CF  the flag of lamp $4DCF
        ORA $4DD3                       ; $39D2  the flag of lamp $4DD3
        BNE hook7_second_passage        ; $39D5  still there
        LDA $4E97                       ; $39D7  room counter 0
        BMI hook7_second_passage        ; $39DA  spent
        DEC $4E97                       ; $39DC  room counter 0, one less
        LDA #$02                        ; $39DF  row 2
        LDY #$21                        ; $39E1  column 33
        JMP draw_passage_17             ; $39E3  open it, and return from there
hook7_second_passage:
        LDA $4DD7                       ; $39E6  the flag of lamp $4DD7
        ORA $4DDB                       ; $39E9  the flag of lamp $4DDB
        ORA $4DDF                       ; $39EC  the flag of lamp $4DDF
        ORA $4DE3                       ; $39EF  the flag of lamp $4DE3
        ORA $4DE7                       ; $39F2  the flag of lamp $4DE7
        ORA $4DEB                       ; $39F5  the flag of lamp $4DEB
        BNE hook7_beam                  ; $39F8  still there
        LDA $4E98                       ; $39FA  room counter 1
        BMI hook7_beam                  ; $39FD  spent
        DEC $4E98                       ; $39FF  room counter 1, one less
        LDA #$05                        ; $3A02  row 5
        LDY #$26                        ; $3A04  column 38
        JMP draw_passage_17             ; $3A06  open it, and return from there
hook7_beam:
        INC $77                         ; $3A09  beam 1's timer, one on
        BMI hook7_slider                ; $3A0B  still pausing
        LDA $77                         ; $3A0D  beam 1's timer
        CMP #$03                        ; $3A0F  3?
        BEQ hook7_beam_advance          ; $3A11  yes: step on
        CMP #$07                        ; $3A13  7?
        BEQ hook7_beam_reload           ; $3A15  yes: reload
hook7_beam_draw:
        JSR print_row74_later           ; $3A17  draw this frame
        JMP hook7_slider                ; $3A1A  to the next part
hook7_beam_advance:
        LDX $71                         ; $3A1D  beam 1's column
        CPX #$24                        ; $3A1F  at the limit?
        BCS hook7_beam_draw             ; $3A21  yes: just draw
        LDA #$06                        ; $3A23  the blank frame
        JSR print_row74_later           ; $3A25  erase it
        INC $71                         ; $3A28  beam 1's column, one on
        LDA #$02                        ; $3A2A  frame 2
        STA $77                         ; $3A2C  beam 1's timer
        BNE hook7_beam_draw             ; $3A2E  always
hook7_beam_reload:
        LDA #$22                        ; $3A30  column 34
        STA $71                         ; $3A32  beam 1's column
        LDA #$E0                        ; $3A34  a pause
        STA $77                         ; $3A36  beam 1's timer
hook7_slider:
        LDA $4DEF                       ; $3A38  the flag of lamp $4DEF
        ORA $4DF3                       ; $3A3B  the flag of lamp $4DF3
        BEQ hook7_slider_left           ; $3A3E  taken
        LDA $6E                         ; $3A40  the block's column
        STA $70                         ; $3A42  the column it leaves
        INC $6E                         ; $3A44  one column right
        CMP #$23                        ; $3A46  past 34?
        BCC hook7_slider_draw_right     ; $3A48  no
        LDA #$05                        ; $3A4A  column 5
        STA $6E                         ; $3A4C  wrap
hook7_slider_draw_right:
        JMP draw_slider                 ; $3A4E  draw it, and return from there
hook7_slider_left:
        LDA $6E                         ; $3A51  the block's column
        STA $70                         ; $3A53  the column it leaves
        DEC $6E                         ; $3A55  one column left
        CMP #$06                        ; $3A57  6 or more?
        BCS hook7_slider_draw_left      ; $3A59  yes
        LDA #$24                        ; $3A5B  column 36
        STA $6E                         ; $3A5D  wrap
hook7_slider_draw_left:
        JMP draw_slider                 ; $3A5F  draw it, and return from there
; $3A62  one RTS that nothing reaches.

; Add 4 to the lamp-list pointer in $14/$15. restore_lamps uses this
; to walk from one record to the next.
step_lamp:
        LDA $14                         ; $3A63  the pointer, low
        CLC                             ; $3A65  carry clear
        ADC #$04                        ; $3A66  four bytes on
        STA $14                         ; $3A68  stored
        BCC step_lamp_done              ; $3A6A  no carry
        INC $15                         ; $3A6C  the carry
step_lamp_done:
        RTS                             ; $3A6E  back
; Once per logic frame, from frame, and once more at the end of
; enter_room. The word at $4EC4, room*2 is the hook address minus one,
; because RTS adds one. Room 1's hook opens the trap door. Room 5's hook
; slides three energy beams and does not read $7B, so those move on every
; logic frame. hook_frame_5 is the beam code. The lamp counts are in
; rooms.asm.
run_frame_hook:
        LDA $29                         ; $3A6F  the room
        ASL A                           ; $3A71  times 2
        TAX                             ; $3A72  the index
        LDA $4EC5,X                     ; $3A73  the hook's address less one, high
        PHA                             ; $3A76  on the stack
        LDA $4EC4,X                     ; $3A77  low
        PHA                             ; $3A7A  on the stack
        RTS                             ; $3A7B  back
; Move ($0A) on four bytes, one lamp record.
next_lamp_record:
        LDA $0A                         ; $3A7C  the pointer, low
        CLC                             ; $3A7E  carry clear
        ADC #$04                        ; $3A7F  four bytes on
        STA $0A                         ; $3A81  stored
        LDA $0B                         ; $3A83  high
        ADC #$00                        ; $3A85  the carry
        STA $0B                         ; $3A87  stored
        RTS                             ; $3A89  back

; Calls play_sound_8a, which keeps A, then prints strings $13, $13, and $14.
; Open a passage once a room's lamps are taken. A is the row and Y the
; column. play_sound_8a sounds it, then strings $13, $13, and $14 draw
; three rows of the opening, one row lower each.
draw_passage:
        JSR play_sound_8a               ; $3A8A  effect $8A
        STA $6C                         ; $3A8D  the row
        STY $6D                         ; $3A8F  the column
        LDA #$13                        ; $3A91  the opening's top
        JSR print_and_step_row          ; $3A93  printed, one row down
        LDA #$13                        ; $3A96  the middle
        JSR print_and_step_row          ; $3A98  printed, one row down
        LDA #$14                        ; $3A9B  the bottom
        JMP print_and_step_row          ; $3A9D  printed, and return from there
; draw_passage, then string $17 one row back up, over the third row.
; Room 6's opening.
draw_passage_17:
        JSR draw_passage                ; $3AA0  open it
        DEC $6C                         ; $3AA3  back up one row
        LDA #$17                        ; $3AA5  the cap
        JMP print_and_step_row          ; $3AA7  printed, and return from there
; draw_passage, then string $2D one row back up. Room 8's opening.
draw_passage_2d:
        JSR draw_passage                ; $3AAA  open it
        DEC $6C                         ; $3AAD  back up one row
        LDA #$2D                        ; $3AAF  the cap
        JMP print_and_step_row          ; $3AB1  printed, and return from there
; The other opening: strings $63, $63, and $64, one row lower each, with
; the same sound.
draw_passage_63:
        JSR play_sound_8a               ; $3AB4  effect $8A
        STA $6C                         ; $3AB7  the row
        STY $6D                         ; $3AB9  the column
        LDA #$63                        ; $3ABB  the opening's top
        JSR print_and_step_row          ; $3ABD  printed, one row down
        LDA #$63                        ; $3AC0  the middle
        JSR print_and_step_row          ; $3AC2  printed, one row down
        LDA #$64                        ; $3AC5  the bottom
        JMP print_and_step_row          ; $3AC7  printed, and return from there
; Print string A at row $6C, column $6D, then move $6C down one row.
print_and_step_row:
        LDX $6C                         ; $3ACA  the row
        LDY $6D                         ; $3ACC  the column
        JSR print_string                ; $3ACE  print it
        INC $6C                         ; $3AD1  the next row
        RTS                             ; $3AD3  back
; Per-frame hook for room 8. It ends in scroll_surface.
hook_frame_8:
        LDA $31                         ; $3AD4  room 7's lamps left
        ORA $4E00                       ; $3AD6  the flag of lamp $4E00
        BNE hook8_second_passage        ; $3AD9  still there
        LDA $4E99                       ; $3ADB  room counter 2
        BMI hook8_second_passage        ; $3ADE  spent
        DEC $4E99                       ; $3AE0  room counter 2, one less
        LDA #$07                        ; $3AE3  row 7
        LDY #$0E                        ; $3AE5  column 14
        JSR draw_passage                ; $3AE7  open it
hook8_second_passage:
        LDA $4DF8                       ; $3AEA  the flag of lamp $4DF8
        ORA $4DFC                       ; $3AED  the flag of lamp $4DFC
        BNE hook8_third_passage         ; $3AF0  still there
        LDA $4E9A                       ; $3AF2  room counter 3
        BMI hook8_third_passage         ; $3AF5  spent
        DEC $4E9A                       ; $3AF7  room counter 3, one less
        LDA $4E04                       ; $3AFA  the flag of lamp $4E04
        BEQ hook8_open_second           ; $3AFD  taken
; Lamp $4E04 is still present. Force the surface down and restart its slot.
        LDA #$01                        ; $3AFF  down
        STA $65                         ; $3B01  the surface's direction
        LDA #$07                        ; $3B03  the last slot
        STA $4321                       ; $3B05  the surface's delay slot
hook8_open_second:
        LDA #$07                        ; $3B08  row 7
        LDY #$19                        ; $3B0A  column 25
        JSR draw_passage                ; $3B0C  open it
hook8_third_passage:
        LDA $32                         ; $3B0F  room 8's lamps left
        ORA $4E11                       ; $3B11  the flag of lamp $4E11
        ORA $4E15                       ; $3B14  the flag of lamp $4E15
        BNE hook8_fourth_passage        ; $3B17  still there
        LDA $4E9B                       ; $3B19  room counter 4
        BMI hook8_fourth_passage        ; $3B1C  spent
        DEC $4E9B                       ; $3B1E  room counter 4, one less
        LDA #$02                        ; $3B21  row 2
        LDY #$26                        ; $3B23  column 38
        JSR draw_passage_2d             ; $3B25  open it
hook8_fourth_passage:
        LDA $4E00                       ; $3B28  the flag of lamp $4E00
        BNE hook8_fifth_passage         ; $3B2B  still there
        LDA $4E97                       ; $3B2D  room counter 0
        BMI hook8_fifth_passage         ; $3B30  spent
        DEC $4E97                       ; $3B32  room counter 0, one less
        LDA #$0A                        ; $3B35  row 10
        LDY #$01                        ; $3B37  column 1
        JSR draw_passage                ; $3B39  open it
hook8_fifth_passage:
        LDA $31                         ; $3B3C  room 7's lamps left
        ORA $32                         ; $3B3E  room 8's lamps left
        BNE hook8_beam1                 ; $3B40  lamps left
        LDA $4E98                       ; $3B42  room counter 1
        BMI hook8_beam1                 ; $3B45  spent
        DEC $4E98                       ; $3B47  room counter 1, one less
        LDA #$0A                        ; $3B4A  row 10
        LDY #$26                        ; $3B4C  column 38
        JSR draw_passage                ; $3B4E  open it
hook8_beam1:
        INC $77                         ; $3B51  beam 1's timer, one on
        BMI hook8_beam2                 ; $3B53  still pausing
        LDA $77                         ; $3B55  beam 1's timer
        CMP #$03                        ; $3B57  3?
        BEQ hook8_beam1_advance         ; $3B59  yes: step on
        CMP #$07                        ; $3B5B  7?
        BEQ hook8_beam1_reload          ; $3B5D  yes: reload
hook8_beam1_draw:
        JSR print_row74                 ; $3B5F  draw this frame
        JMP hook8_beam2                 ; $3B62  to the next part
hook8_beam1_advance:
        LDX $71                         ; $3B65  beam 1's column
        CPX #$0B                        ; $3B67  at the limit?
        BCS hook8_beam1_draw            ; $3B69  yes: just draw
        LDA #$06                        ; $3B6B  the blank frame
        JSR print_row74                 ; $3B6D  erase it
        INC $71                         ; $3B70  beam 1's column, one on
        LDA #$02                        ; $3B72  frame 2
        STA $77                         ; $3B74  beam 1's timer
        BNE hook8_beam1_draw            ; $3B76  always
hook8_beam1_reload:
        LDA #$06                        ; $3B78  column 6
        STA $71                         ; $3B7A  beam 1's column
        LDA #$DA                        ; $3B7C  a pause
        STA $77                         ; $3B7E  beam 1's timer
hook8_beam2:
        INC $78                         ; $3B80  beam 2's timer, one on
        BMI hook8_scroll                ; $3B82  still pausing
        LDA $78                         ; $3B84  beam 2's timer
        CMP #$03                        ; $3B86  3?
        BEQ hook8_beam2_advance         ; $3B88  yes: step on
        CMP #$07                        ; $3B8A  7?
        BEQ hook8_beam2_reload          ; $3B8C  yes: reload
hook8_beam2_draw:
        JSR print_row75                 ; $3B8E  draw this frame
        JMP hook8_scroll                ; $3B91  to the next part
hook8_beam2_advance:
        LDX $72                         ; $3B94  beam 2's column
        CPX #$20                        ; $3B96  at the limit?
        BCS hook8_beam2_draw            ; $3B98  yes: just draw
        LDA #$06                        ; $3B9A  the blank frame
        JSR print_row75                 ; $3B9C  erase it
        INC $72                         ; $3B9F  beam 2's column, one on
        LDA #$02                        ; $3BA1  frame 2
        STA $78                         ; $3BA3  beam 2's timer
        BNE hook8_beam2_draw            ; $3BA5  always
hook8_beam2_reload:
        LDA #$1B                        ; $3BA7  column 27
        STA $72                         ; $3BA9  beam 2's column
        LDA #$DA                        ; $3BAB  a pause
        STA $78                         ; $3BAD  beam 2's timer
hook8_scroll:
        JMP scroll_surface              ; $3BAF  the surface, and return from there
; Per-frame hook for room 9. It ends in scroll_surface.
hook_frame_9:
        LDA $4E99                       ; $3BB2  room counter 2
        BMI hook9_first_passage         ; $3BB5  spent
        LDA $4E09                       ; $3BB7  the flag of lamp $4E09
        BNE hook9_first_passage         ; $3BBA  still there
        DEC $4E99                       ; $3BBC  room counter 2, one less
; Lamp $4E09 is gone. Pin the surface down, and the slot at 7, until this
; counter runs out. The slot never wraps while this runs, so it cannot
; reverse on its own.
        LDA #$01                        ; $3BBF  down
        STA $65                         ; $3BC1  the surface's direction
        LDA #$07                        ; $3BC3  the last slot
        STA $4321                       ; $3BC5  the surface's delay slot
hook9_first_passage:
        LDA $4E0D                       ; $3BC8  the flag of lamp $4E0D
        BNE hook9_lamps_clear           ; $3BCB  still there
        LDA $4E97                       ; $3BCD  room counter 0
        BMI hook9_lamps_clear           ; $3BD0  spent
        DEC $4E97                       ; $3BD2  room counter 0, one less
        LDA #$07                        ; $3BD5  row 7
        LDY #$17                        ; $3BD7  column 23
        JSR draw_passage                ; $3BD9  open it
; Lamp $4E0D has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $3BDC  up
        STA $65                         ; $3BDE  the surface's direction
        LDA #$07                        ; $3BE0  the last slot
        STA $4321                       ; $3BE2  the surface's delay slot
hook9_lamps_clear:
        LDA $33                         ; $3BE5  room 9's lamps left
        BNE hook9_slider                ; $3BE7  lamps left
        LDA $4E98                       ; $3BE9  room counter 1
        BMI hook9_slider                ; $3BEC  spent
        DEC $4E98                       ; $3BEE  room counter 1, one less
; Room 9's lamps are clear. Force the surface up and restart its slot.
        LDA #$00                        ; $3BF1  up
        STA $65                         ; $3BF3  the surface's direction
        LDA #$07                        ; $3BF5  the last slot
        STA $4321                       ; $3BF7  the surface's delay slot
        JSR play_sound_8a               ; $3BFA  effect $8A
        LDA #$18                        ; $3BFD  string $18
        LDX #$02                        ; $3BFF  tile row $02
        LDY #$23                        ; $3C01  column $23
        JSR print_string                ; $3C03  print it
hook9_slider:
        LDA $4E11                       ; $3C06  the flag of lamp $4E11
        ORA $4E15                       ; $3C09  the flag of lamp $4E15
        BNE hook9_slider_right          ; $3C0C  still there
        LDA $6E                         ; $3C0E  the block's column
        STA $70                         ; $3C10  the column it leaves
        DEC $6E                         ; $3C12  one column left
        CMP #$05                        ; $3C14  5 or more?
        BCS hook9_slider_draw           ; $3C16  yes
        LDA #$18                        ; $3C18  column 24
        STA $6E                         ; $3C1A  wrap
        BNE hook9_slider_draw           ; $3C1C  always
hook9_slider_right:
        LDA $6E                         ; $3C1E  the block's column
        STA $70                         ; $3C20  the column it leaves
        INC $6E                         ; $3C22  one column right
        CMP #$18                        ; $3C24  below 24?
        BCC hook9_slider_draw           ; $3C26  yes
        LDA #$04                        ; $3C28  column 4
        STA $6E                         ; $3C2A  wrap
hook9_slider_draw:
        JSR draw_slider                 ; $3C2C  draw it
        INC $77                         ; $3C2F  beam 1's timer, one on
        BMI hook9_beam2                 ; $3C31  still pausing
        LDA $77                         ; $3C33  beam 1's timer
        CMP #$03                        ; $3C35  3?
        BEQ hook9_beam1_advance         ; $3C37  yes: step on
        CMP #$07                        ; $3C39  7?
        BEQ hook9_beam1_reload          ; $3C3B  yes: reload
hook9_beam1_draw:
        JSR print_row74_later           ; $3C3D  draw this frame
        JMP hook9_beam2                 ; $3C40  to the next part
hook9_beam1_advance:
        LDX $71                         ; $3C43  beam 1's column
        CPX #$14                        ; $3C45  at the limit?
        BCS hook9_beam1_draw            ; $3C47  yes: just draw
        LDA #$06                        ; $3C49  the blank frame
        JSR print_row74_later           ; $3C4B  erase it
        INC $71                         ; $3C4E  beam 1's column, one on
        LDA #$02                        ; $3C50  frame 2
        STA $77                         ; $3C52  beam 1's timer
        BNE hook9_beam1_draw            ; $3C54  always
hook9_beam1_reload:
        LDA #$10                        ; $3C56  column 16
        STA $71                         ; $3C58  beam 1's column
        LDA #$C0                        ; $3C5A  a pause
        STA $77                         ; $3C5C  beam 1's timer
hook9_beam2:
        INC $78                         ; $3C5E  beam 2's timer, one on
        BMI hook9_scroll                ; $3C60  still pausing
        LDA $78                         ; $3C62  beam 2's timer
        CMP #$03                        ; $3C64  3?
        BEQ hook9_beam2_advance         ; $3C66  yes: step on
        CMP #$07                        ; $3C68  7?
        BEQ hook9_beam2_reload          ; $3C6A  yes: reload
hook9_beam2_draw:
        JSR print_row75_later           ; $3C6C  draw this frame
        JMP hook9_scroll                ; $3C6F  to the next part
hook9_beam2_advance:
        LDX $72                         ; $3C72  beam 2's column
        CPX #$14                        ; $3C74  at the limit?
        BCS hook9_beam2_draw            ; $3C76  yes: just draw
        LDA #$06                        ; $3C78  the blank frame
        JSR print_row75_later           ; $3C7A  erase it
        INC $72                         ; $3C7D  beam 2's column, one on
        LDA #$02                        ; $3C7F  frame 2
        STA $78                         ; $3C81  beam 2's timer
        BNE hook9_beam2_draw            ; $3C83  always
hook9_beam2_reload:
        LDA #$10                        ; $3C85  column 16
        STA $72                         ; $3C87  beam 2's column
        LDA #$C0                        ; $3C89  a pause
        STA $78                         ; $3C8B  beam 2's timer
hook9_scroll:
        JMP scroll_surface              ; $3C8D  the surface, and return from there
; Per-frame hook for room 10.
hook_frame_10:
        LDA $4E97                       ; $3C90  room counter 0
        BMI hook10_crumble              ; $3C93  spent
        LDA $4E1E                       ; $3C95  the flag of lamp $4E1E
        ORA $4E22                       ; $3C98  the flag of lamp $4E22
        BNE hook10_crumble              ; $3C9B  still there
        DEC $4E97                       ; $3C9D  room counter 0, one less
        LDA #$04                        ; $3CA0  row 4
        LDY #$26                        ; $3CA2  column 38
        JSR draw_passage_63             ; $3CA4  open it
hook10_crumble:
        NOP                             ; $3CA7  22 spare bytes
        NOP                             ; $3CA8  spare
        NOP                             ; $3CA9  spare
        NOP                             ; $3CAA  spare
        NOP                             ; $3CAB  spare
        NOP                             ; $3CAC  spare
        NOP                             ; $3CAD  spare
        NOP                             ; $3CAE  spare
        NOP                             ; $3CAF  spare
        NOP                             ; $3CB0  spare
        NOP                             ; $3CB1  spare
        NOP                             ; $3CB2  spare
        NOP                             ; $3CB3  spare
        NOP                             ; $3CB4  spare
        NOP                             ; $3CB5  spare
        NOP                             ; $3CB6  spare
        NOP                             ; $3CB7  spare
        NOP                             ; $3CB8  spare
        NOP                             ; $3CB9  spare
        NOP                             ; $3CBA  spare
        NOP                             ; $3CBB  spare
        NOP                             ; $3CBC  spare
        JMP step_crumble                ; $3CBD  the nozzle flames, and return from there
; Per-frame hook for room 11. It ends in scroll_surface. The pattern is
; the block at $4309, written into charset $A800.
hook_frame_11:
        LDA $4E97                       ; $3CC0  room counter 0
        BMI hook11_crumble              ; $3CC3  spent
        LDA $4E33                       ; $3CC5  the flag of lamp $4E33
        BNE hook11_crumble              ; $3CC8  still there
        DEC $4E97                       ; $3CCA  room counter 0, one less
; Lamp $4E33 has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $3CCD  up
        STA $65                         ; $3CCF  the surface's direction
        LDA #$07                        ; $3CD1  the last slot
        STA $4321                       ; $3CD3  the surface's delay slot
hook11_crumble:
        JSR step_crumble                ; $3CD6  the nozzle flames
        JMP scroll_surface              ; $3CD9  the surface, and return from there
; Per-frame hook for room 18.
hook_frame_18:
        LDA $4E97                       ; $3CDC  room counter 0
        BNE hook18_boss                 ; $3CDF  the boss is still up
        JMP hook18_after_boss           ; $3CE1  after the boss
hook18_boss:
        LDA $4E86                       ; $3CE4  the flag of lamp $4E86
        BNE hook18_sparks               ; $3CE7  still there
        STA $4E97                       ; $3CE9  room counter 0
        JSR blank_sparks                ; $3CEC  the sparks off
        LDA $D015                       ; $3CEF  sprite enable
        AND #$1F                        ; $3CF2  the five actor sprites only
        STA $D015                       ; $3CF4  sprite enable
        LDA #$61                        ; $3CF7  string $61
        LDX #$0B                        ; $3CF9  tile row $0B
        LDY #$00                        ; $3CFB  column $00
        JSR print_string                ; $3CFD  print it
; 3000 for the wizard. The low byte $B8 is added first, then $0B in the
; middle byte, and check_life_mark runs on each add.
        LDA #$B8                        ; $3D00  184
        LDX #$02                        ; $3D02  into the low byte
        JSR add_score                   ; $3D04  points
        LDA #$0B                        ; $3D07  11
        LDX #$01                        ; $3D09  into the middle byte
        JSR add_score                   ; $3D0B  2816 more: 3000
        LDX #$01                        ; $3D0E  band 1
        LDA #$00                        ; $3D10  zero
        STA $4E9A                       ; $3D12  room counter 3
        LDA #$50                        ; $3D15  80 frames
        STA $4E98                       ; $3D17  room counter 1
        JMP hook18_show_band            ; $3D1A  show the band
hook18_sparks:
        JSR paint_sparks                ; $3D1D  the sparks
        LDA $D01E                       ; $3D20  sprite-sprite contacts. Reading clears it
        TAX                             ; $3D23  kept
        AND #$03                        ; $3D24  Bruce's sprites?
        BEQ hook18_band_timer           ; $3D26  no
        TXA                             ; $3D28  the contacts
        AND #$C0                        ; $3D29  the spark sprites?
        BEQ hook18_band_timer           ; $3D2B  no
        LDX #$00                        ; $3D2D  Bruce
        LDA $BF                         ; $3D2F  his state
        CMP #$19                        ; $3D31  shocked already?
        BEQ hook18_band_timer           ; $3D33  yes
        JSR shock_bruce                 ; $3D35  shock him
hook18_band_timer:
        DEC $4E98                       ; $3D38  room counter 1, one less
        BNE hook18_done                 ; $3D3B  not yet
        LDA #$08                        ; $3D3D  eight frames
        STA $4E98                       ; $3D3F  room counter 1
        LDA $9E                         ; $3D42  Bruce's xpos
        LDX #$02                        ; $3D44  three bands
hook18_band_loop:
        CMP $4A89,X                     ; $3D46  past this band's mark?
        BCS hook18_show_band            ; $3D49  yes
        DEX                             ; $3D4B  the band to the left
        BNE hook18_band_loop            ; $3D4C  more
hook18_show_band:
        STX $4E99                       ; $3D4E  the band
        LDA #$38                        ; $3D51  the band's string
        CLC                             ; $3D53  carry clear
        ADC $4E99                       ; $3D54  plus the band
        LDX #$02                        ; $3D57  tile row $02
        LDY #$10                        ; $3D59  column $10
        JSR print_string                ; $3D5B  print it
        LDA $4E9A                       ; $3D5E  room counter 3
        BNE hook18_flash_off            ; $3D61  the lit phase is showing
        INC $4E9A                       ; $3D63  room counter 3, one more
        LDA #$06                        ; $3D66  lit
        JSR flash_row_3                 ; $3D68  row 3
        LDA #$06                        ; $3D6B  lit
        JSR flash_row_4                 ; $3D6D  row 4
        JMP hook18_done                 ; $3D70  done
hook18_flash_off:
        DEC $4E9A                       ; $3D73  room counter 3, one less
        LDA #$00                        ; $3D76  dark
        JSR flash_row_3                 ; $3D78  row 3
        LDA #$00                        ; $3D7B  dark
        JSR flash_row_4                 ; $3D7D  row 4
hook18_done:
        RTS                             ; $3D80  back
; Room 18. String $3B plus A plus $4E99 on row 3 at column $12. $4E99 is
; the band of the room Bruce's xpos is in, from the marks at $4A89, and A
; is 0 or 6, so the strings alternate every eight frames.
flash_row_3:
        CLC                             ; $3D81  carry clear
        ADC #$3B                        ; $3D82  the row's first string
        ADC $4E99                       ; $3D84  plus the band
        LDX #$03                        ; $3D87  tile row $03
        LDY #$12                        ; $3D89  column $12
        JMP print_string                ; $3D8B  print it, and return from there
; The same for row 4, from string $3E.
flash_row_4:
        CLC                             ; $3D8E  carry clear
        ADC #$3E                        ; $3D8F  the row's first string
        ADC $4E99                       ; $3D91  plus the band
        LDX #$04                        ; $3D94  tile row $04
        LDY #$12                        ; $3D96  column $12
        JMP print_string                ; $3D98  print it, and return from there
hook18_defeated:
        LDA #$00                        ; $3D9B  a load the next one replaces
        LDA #$5E                        ; $3D9D  string $5E
        LDX #$0B                        ; $3D9F  tile row $0B
        LDY #$25                        ; $3DA1  column $25
        JSR print_string                ; $3DA3  print it
        LDA #$5F                        ; $3DA6  string $5F
        LDX #$0C                        ; $3DA8  tile row $0C
        LDY #$26                        ; $3DAA  column $26
        JMP print_string                ; $3DAC  print it, and return from there
hook18_after_boss:
        LDA $4E98                       ; $3DAF  room counter 1
        BEQ hook18_defeated             ; $3DB2  the count is out: defeated
        TAX                             ; $3DB4  the count
        JSR noise_byte                  ; $3DB5  a noise byte
        AND #$0F                        ; $3DB8  the low nibble
        ORA #$80                        ; $3DBA  with bit 7
        CPX #$01                        ; $3DBC  the last frame?
        BNE hook18_flash_ink            ; $3DBE  no
        LDA #$00                        ; $3DC0  the last frame: black
        BEQ hook18_store_ink            ; $3DC2  always
hook18_flash_ink:
        JSR noise_byte                  ; $3DC4  a noise byte
        AND #$07                        ; $3DC7  ink 0-7
hook18_store_ink:
        ORA #$F8                        ; $3DC9  multicolor
        LDX #$11                        ; $3DCB  18 cells
hook18_ink_loop:
        STA $D8D3,X                     ; $3DCD  color RAM, row 5 column 11, plus X
        STA $D8FB,X                     ; $3DD0  color RAM, row 6 column 11, plus X
        STA $D923,X                     ; $3DD3  color RAM, row 7 column 11, plus X
        STA $D94B,X                     ; $3DD6  color RAM, row 8 column 11, plus X
        CPX #$0C                        ; $3DD9  past the first twelve?
        BCS hook18_ink_next             ; $3DDB  yes
        STA $D886,X                     ; $3DDD  color RAM, row 3 column 14, plus X
        STA $D8AE,X                     ; $3DE0  color RAM, row 4 column 14, plus X
        STA $D976,X                     ; $3DE3  color RAM, row 9 column 14, plus X
        STA $D99E,X                     ; $3DE6  color RAM, row 10 column 14, plus X
        STA $D9C6,X                     ; $3DE9  color RAM, row 11 column 14, plus X
        STA $D9EE,X                     ; $3DEC  color RAM, row 12 column 14, plus X
hook18_ink_next:
        DEX                             ; $3DEF  the next
        BPL hook18_ink_loop             ; $3DF0  more
        LDX $4E98                       ; $3DF2  the count
        DEC $4E98                       ; $3DF5  room counter 1, one less
        LDA #$3E                        ; $3DF8  charset $B800
        STA $F2                         ; $3DFA  for raster_open
        CPX #$11                        ; $3DFC  17 or more left?
        BCC hook18_flash_sound          ; $3DFE  no
        JSR noise_byte                  ; $3E00  a noise byte
        CMP #$10                        ; $3E03  $10 or more?
        BCS hook18_flash_sound          ; $3E05  yes
        LDA #$3C                        ; $3E07  charset $B000, the room's own
        STA $F2                         ; $3E09  for raster_open
hook18_flash_sound:
; Effect $8B. $4E98 is still nonzero, so this is a flash frame.
; The zero count prints at hook18_defeated and does not play it.
        LDY #$8B                        ; $3E0B  effect $8B
        JSR play_sound                  ; $3E0D  queue it
        LDA $4E9A                       ; $3E10  room counter 3
        EOR #$01                        ; $3E13  flip the phase
        STA $4E9A                       ; $3E15  room counter 3
        LDA #$47                        ; $3E18  the first string
        CLC                             ; $3E1A  carry clear
        ADC $4E9A                       ; $3E1B  plus the phase
        LDX #$03                        ; $3E1E  tile row $03
        LDY #$0C                        ; $3E20  column $0C
        JSR print_string                ; $3E22  print it
        LDA #$49                        ; $3E25  the second string
        CLC                             ; $3E27  carry clear
        ADC $4E9A                       ; $3E28  plus the phase
        LDX #$03                        ; $3E2B  tile row $03
        LDY #$19                        ; $3E2D  column $19
        JSR print_string                ; $3E2F  print it
        LDA #$4B                        ; $3E32  the third string
        CLC                             ; $3E34  carry clear
        ADC $4E9A                       ; $3E35  plus the phase
        LDX #$06                        ; $3E38  tile row $06
        LDY #$0E                        ; $3E3A  column $0E
        JSR print_string                ; $3E3C  print it
        LDA #$4D                        ; $3E3F  the fourth string
        CLC                             ; $3E41  carry clear
        ADC $4E9A                       ; $3E42  plus the phase
        LDX #$06                        ; $3E45  tile row $06
        LDY #$17                        ; $3E47  column $17
        JMP print_string                ; $3E49  print it, and return from there
; Per-frame hook for room 12.
hook_frame_12:
        LDA $4E97                       ; $3E4C  room counter 0
        BMI hook12_second_passage       ; $3E4F  spent
        LDA $4E40                       ; $3E51  the flag of lamp $4E40
        BNE hook12_second_passage       ; $3E54  still there
        DEC $4E97                       ; $3E56  room counter 0, one less
        LDA #$0A                        ; $3E59  row 10
        LDY #$26                        ; $3E5B  column 38
        JSR draw_passage_63             ; $3E5D  open it
hook12_second_passage:
        LDA $4E98                       ; $3E60  room counter 1
        BMI hook12_crumble              ; $3E63  spent
        LDA $36                         ; $3E65  room 12's lamps left
        ORA $4E52                       ; $3E67  the flag of lamp $4E52
        ORA $4E56                       ; $3E6A  the flag of lamp $4E56
        BNE hook12_crumble              ; $3E6D  still there
        DEC $4E98                       ; $3E6F  room counter 1, one less
        LDA #$07                        ; $3E72  row 7
        LDY #$26                        ; $3E74  column 38
        JSR draw_passage_63             ; $3E76  open it
hook12_crumble:
        JMP step_crumble                ; $3E79  the nozzle flames, and return from there
; Per-frame hook for room 13. $014B + player*4 holds three one-shot
; flags. ypos below $64 pays nothing. From $64 to $89 the first flag
; pays, from $8A to $B5 the second, and from $B6 down the third. Each
; pays 500: $01 into score byte 1 and $F4 into byte 2, as two adds, so the
; extra-fall test runs between them. The fourth byte
; of the group is not read. hook_frame_19 writes 1 back into all four
; when the treasure room ends.
hook_frame_13:
        LDA $03                         ; $3E7C  the player
        ASL A                           ; $3E7E  shifted up
        ASL A                           ; $3E7F  times 4
        TAX                             ; $3E80  his flags
        LDA $A1                         ; $3E81  Bruce's ypos
        CMP #$64                        ; $3E83  below $64?
        BCC hook13_sliders_step         ; $3E85  yes: nothing
        CMP #$8A                        ; $3E87  $8A or more?
        BCS height_lower                ; $3E89  yes
        LDA $014B,X                     ; $3E8B  the first flag
        BEQ hook13_sliders_step         ; $3E8E  spent
        DEC $014B,X                     ; $3E90  spent now
        JMP pay_height                  ; $3E93  500 points
; ypos $8A or more. The second flag, unless ypos is $B6 or more.
height_lower:
        INX                             ; $3E96  the second flag
        CMP #$B6                        ; $3E97  $B6 or more?
        BCS height_low                  ; $3E99  yes
        LDA $014B,X                     ; $3E9B  the second flag
        BEQ hook13_sliders_step         ; $3E9E  spent
        DEC $014B,X                     ; $3EA0  spent now
        JMP pay_height                  ; $3EA3  500 points
; ypos $B6 or more. The third flag.
height_low:
        INX                             ; $3EA6  the third flag
        LDA $014B,X                     ; $3EA7  the third flag
        BEQ hook13_sliders_step         ; $3EAA  spent
        DEC $014B,X                     ; $3EAC  spent now
; 500 points: $01 into byte 1, then $F4 into byte 2.
pay_height:
        LDA #$01                        ; $3EAF  1
        TAX                             ; $3EB1  into byte 1
        JSR add_score                   ; $3EB2  256 points
        LDA #$F4                        ; $3EB5  244
        LDX #$02                        ; $3EB7  into the low byte
        JMP add_score                   ; $3EB9  500 in all, and return from there
hook13_sliders_step:
        LDA $7B                         ; $3EBC  the hook phase
        BNE hook13_sprites              ; $3EBE  the off frame: skip
        JSR step_sliders                ; $3EC0  the sliding blocks
hook13_sprites:
        LDA $D015                       ; $3EC3  sprite enable
        AND #$03                        ; $3EC6  Bruce's two sprites only
        STA $D015                       ; $3EC8  sprite enable
        RTS                             ; $3ECB  back
; Per-frame hook for room 14.
hook_frame_14:
        LDA $4E97                       ; $3ECC  room counter 0
        BMI hook14_crumble              ; $3ECF  spent
        LDA $4E4A                       ; $3ED1  the flag of lamp $4E4A
        ORA $4E4E                       ; $3ED4  the flag of lamp $4E4E
        BNE hook14_crumble              ; $3ED7  still there
        DEC $4E97                       ; $3ED9  room counter 0, one less
        LDA #$04                        ; $3EDC  row 4
        LDY #$26                        ; $3EDE  column 38
        JSR draw_passage_63             ; $3EE0  open it
hook14_crumble:
        JMP step_crumble                ; $3EE3  the nozzle flames, and return from there
; Per-frame hook for room 15.
hook_frame_15:
        LDA $4E97                       ; $3EE6  room counter 0
        BMI hook15_second_door          ; $3EE9  spent
        LDA $4E5B                       ; $3EEB  the flag of lamp $4E5B
        BNE hook15_second_door          ; $3EEE  still there
        LDA #$57                        ; $3EF0  string $57
        LDX #$03                        ; $3EF2  tile row $03
        LDY #$11                        ; $3EF4  column $11
        JSR print_string                ; $3EF6  print it
        LDA #$58                        ; $3EF9  string $58
        LDX #$04                        ; $3EFB  tile row $04
        LDY #$11                        ; $3EFD  column $11
        JSR print_string                ; $3EFF  print it
        DEC $4E97                       ; $3F02  room counter 0, one less
        JSR play_sound_8a               ; $3F05  effect $8A
hook15_second_door:
        LDA $4E98                       ; $3F08  room counter 1
        BMI hook15_third_door           ; $3F0B  spent
        LDA $4E5F                       ; $3F0D  the flag of lamp $4E5F
        ORA $4E63                       ; $3F10  the flag of lamp $4E63
        ORA $4E6B                       ; $3F13  the flag of lamp $4E6B
        BNE hook15_third_door           ; $3F16  still there
        LDA #$57                        ; $3F18  string $57
        LDX #$03                        ; $3F1A  tile row $03
        LDY #$17                        ; $3F1C  column $17
        JSR print_string                ; $3F1E  print it
        LDA #$58                        ; $3F21  string $58
        LDX #$04                        ; $3F23  tile row $04
        LDY #$17                        ; $3F25  column $17
        JSR print_string                ; $3F27  print it
        DEC $4E98                       ; $3F2A  room counter 1, one less
        JSR play_sound_8a               ; $3F2D  effect $8A
hook15_third_door:
        LDA $4E99                       ; $3F30  room counter 2
        BMI hook15_done                 ; $3F33  spent
        LDA $39                         ; $3F35  room 15's lamps left
        BNE hook15_done                 ; $3F37  lamps left
        LDA #$59                        ; $3F39  string $59
        LDX #$09                        ; $3F3B  tile row $09
        LDY #$25                        ; $3F3D  column $25
        JSR print_string                ; $3F3F  print it
        LDA #$5A                        ; $3F42  string $5A
        LDX #$08                        ; $3F44  tile row $08
        LDY #$25                        ; $3F46  column $25
        JSR print_string                ; $3F48  print it
        LDA #$5B                        ; $3F4B  string $5B
        LDX #$07                        ; $3F4D  tile row $07
        LDY #$25                        ; $3F4F  column $25
        JSR print_string                ; $3F51  print it
        JSR play_sound_8a               ; $3F54  effect $8A
        DEC $4E99                       ; $3F57  room counter 2, one less
hook15_done:
        RTS                             ; $3F5A  back
; Per-frame hook for room 16.
hook_frame_16:
        LDA $4E97                       ; $3F5B  room counter 0
        BMI hook16_crumble              ; $3F5E  spent
        LDA $3A                         ; $3F60  room 16's lamps left
        BNE hook16_crumble              ; $3F62  lamps left
        DEC $4E97                       ; $3F64  room counter 0, one less
        LDA #$07                        ; $3F67  row 7
        LDY #$01                        ; $3F69  column 1
        JSR draw_passage_63             ; $3F6B  open it
hook16_crumble:
        JMP step_crumble                ; $3F6E  the nozzle flames, and return from there
; Per-frame hook for room 17.
hook_frame_17:
        DEC $4E99                       ; $3F71  room counter 2, one less
        BPL hook17_slider_timer         ; $3F74  not yet
        LDA #$0A                        ; $3F76  ten frames
        STA $4E99                       ; $3F78  room counter 2
        LDA $D880                       ; $3F7B  color RAM, row 3 column 8
        AND #$07                        ; $3F7E  the floor's ink
        EOR #$02                        ; $3F80  swapped with its partner
        ORA #$F8                        ; $3F82  multicolor
        LDX #$1B                        ; $3F84  28 cells
hook17_floor_ink:
        STA $D880,X                     ; $3F86  color RAM, row 3 column 8, plus X
        DEX                             ; $3F89  the next
        BPL hook17_floor_ink            ; $3F8A  more
hook17_slider_timer:
        DEC $4E9A                       ; $3F8C  room counter 3, one less
        BEQ hook17_first_door           ; $3F8F  reached 0: no slide
        BPL hook17_slider               ; $3F91  not yet: slide
        LDA #$01                        ; $3F93  1
        STA $4E9A                       ; $3F95  room counter 3
hook17_slider:
        LDA $6E                         ; $3F98  the block's column
        STA $70                         ; $3F9A  the column it leaves
        INC $6E                         ; $3F9C  one column right
        CMP #$1B                        ; $3F9E  below 27?
        BCC hook17_slider_draw          ; $3FA0  yes
        LDA #$0B                        ; $3FA2  column 11
        STA $6E                         ; $3FA4  wrap
hook17_slider_draw:
        JSR draw_slider                 ; $3FA6  draw it
hook17_first_door:
        LDA $4E97                       ; $3FA9  room counter 0
        BEQ hook17_second_door          ; $3FAC  spent
        LDA $4E7D                       ; $3FAE  the flag of lamp $4E7D
        BNE hook17_second_door          ; $3FB1  still there
        DEC $4E97                       ; $3FB3  room counter 0, one less
        LDA #$5D                        ; $3FB6  string $5D
        LDX #$0A                        ; $3FB8  tile row $0A
        LDY #$25                        ; $3FBA  column $25
        JSR print_string                ; $3FBC  print it
hook17_second_door:
        LDA $4E98                       ; $3FBF  room counter 1
        BEQ hook17_beams                ; $3FC2  spent
        LDA $4E81                       ; $3FC4  the flag of lamp $4E81
        BNE hook17_beams                ; $3FC7  still there
        DEC $4E98                       ; $3FC9  room counter 1, one less
        LDA #$5C                        ; $3FCC  string $5C
        LDX #$0A                        ; $3FCE  tile row $0A
        LDY #$18                        ; $3FD0  column $18
        JSR print_string                ; $3FD2  print it
hook17_beams:
        JSR step_crumble                ; $3FD5  the nozzle flames
        LDA #$02                        ; $3FD8  three beams
        STA $4C                         ; $3FDA  the beam
hook17_beam_loop:
        LDX $4C                         ; $3FDC  the beam
        INC $77,X                       ; $3FDE  its timer
        BMI hook17_beam_next            ; $3FE0  still pausing
        LDA $77,X                       ; $3FE2  its timer
        CMP #$03                        ; $3FE4  3?
        BEQ hook17_beam_advance         ; $3FE6  yes: step on
        CMP #$07                        ; $3FE8  7?
        BEQ hook17_beam_reload          ; $3FEA  yes: reload
hook17_beam_draw:
        CPX #$00                        ; $3FEC  beam 1?
        BNE hook17_beam_draw_75         ; $3FEE  no
        JSR print_row74                 ; $3FF0  draw this frame
        JMP hook17_beam_next            ; $3FF3  to the next part
hook17_beam_draw_75:
        CPX #$01                        ; $3FF6  beam 2?
        BNE hook17_beam_draw_76         ; $3FF8  no
        JSR print_row75                 ; $3FFA  draw this frame
        JMP hook17_beam_next            ; $3FFD  to the next part
hook17_beam_draw_76:
        JSR print_row76                 ; $4000  draw this frame
        JMP hook17_beam_next            ; $4003  to the next part
hook17_beam_advance:
        LDY $71,X                       ; $4006  its column
        CPX #$00                        ; $4008  beam 1?
        BNE hook17_beam_limit           ; $400A  no
        CPY #$23                        ; $400C  35 or more?
        BCS hook17_beam_draw            ; $400E  yes: just draw
        BCC hook17_beam_erase           ; $4010  no: step on
hook17_beam_limit:
        CPY #$25                        ; $4012  37 or more?
        BCS hook17_beam_draw            ; $4014  yes: just draw
hook17_beam_erase:
        LDA #$06                        ; $4016  the blank frame
        CPX #$00                        ; $4018  beam 1?
        BNE hook17_beam_erase_75        ; $401A  no
        JSR print_row74                 ; $401C  erase it
        JMP hook17_beam_step            ; $401F  to the next part
hook17_beam_erase_75:
        CPX #$01                        ; $4022  beam 2?
        BNE hook17_beam_erase_76        ; $4024  no
        JSR print_row75                 ; $4026  erase it
        JMP hook17_beam_step            ; $4029  to the next part
hook17_beam_erase_76:
        JSR print_row76                 ; $402C  erase it
hook17_beam_step:
        LDX $4C                         ; $402F  the beam
        INC $71,X                       ; $4031  one column right
        LDA #$02                        ; $4033  frame 2
        STA $77,X                       ; $4035  its timer
        BNE hook17_beam_draw            ; $4037  always
hook17_beam_reload:
        LDA #$CA                        ; $4039  a pause
        STA $77,X                       ; $403B  its timer
        LDA #$08                        ; $403D  column 8
        STA $71,X                       ; $403F  its column
        CPX #$00                        ; $4041  beam 1?
        BNE hook17_beam_next            ; $4043  no
        LDA #$C8                        ; $4045  a shorter pause
        STA $77,X                       ; $4047  beam 1's timer
hook17_beam_next:
        DEC $4C                         ; $4049  the next beam
        BPL hook17_beam_loop            ; $404B  more
        RTS                             ; $404D  back
; One slider block moved. $6F is its row, $70 the column it left and $6E
; the new column. String $1C clears the old cell and $1B draws the new
; one, with slide_sound.
draw_slider:
        JSR slide_sound                 ; $404E  effect $89
        LDA #$1C                        ; $4051  string $1C
        LDX $6F                         ; $4053  the row
        LDY $70                         ; $4055  the old column
        JSR print_string                ; $4057  print it
        LDA #$1B                        ; $405A  string $1B
        LDX $6F                         ; $405C  the row
        LDY $6E                         ; $405E  the new column
        JMP print_string                ; $4060  print it, and return from there
; The same as draw_slider for a slider on row 5 or 10, which uses
; strings $55 and $54.
draw_slider_tall:
        JSR slide_sound                 ; $4063  effect $89
        LDA #$55                        ; $4066  string $55
        LDX $6F                         ; $4068  the row
        LDY $70                         ; $406A  the old column
        JSR print_string                ; $406C  print it
        LDA #$54                        ; $406F  string $54
        LDX $6F                         ; $4071  the row
        LDY $6E                         ; $4073  the new column
        JMP print_string                ; $4075  print it, and return from there
; Effect $89. Both slide painters call this. One pulse click,
; retriggered every logic frame the slide paints. The beams do not.
slide_sound:
        LDY #$89                        ; $4078  effect $89
        JMP play_sound                  ; $407A  queue it, and return from there

; State $19 for $10 frames. shock uses it for Bruce. The room 18 spark
; uses it when the sprite hit lands and he is not already in that state.
shock_bruce:
        LDA #$19                        ; $407D  shocked
        STA state,X                     ; $407F  state
        LDA #$10                        ; $4081  16 counts
        STA timer,X                     ; $4083  timer
        RTS                             ; $4085  back

; Beam frames for room 5. A is the frame number. $1F selects the string,
; which print_string stores as the screen code minus $20. X is the tile row
; and Y is the column. print_row74 uses row $74 and column $71, print_row75
; uses $75 and $72, and print_row76 uses $76 and $73. The three entries that
; add 7 first are how the upper beam reaches its own strings. The BNE after
; each JMP is not reached from these entries.
print_row74:
        CLC                             ; $4086  carry clear
        ADC #$1F                        ; $4087  plus $1F: the string
        LDX $74                         ; $4089  beam 1's row
        LDY $71                         ; $408B  beam 1's column
        JMP print_string                ; $408D  print it, and return from there
; The middle beam row, $75 and $72.
print_row75:
        CLC                             ; $4090  carry clear
        ADC #$1F                        ; $4091  plus $1F: the string
        LDX $75                         ; $4093  beam 2's row
        LDY $72                         ; $4095  beam 2's column
        JMP print_string                ; $4097  print it, and return from there
; The bottom beam row, $76 and $73.
print_row76:
        CLC                             ; $409A  carry clear
        ADC #$1F                        ; $409B  plus $1F: the string
        LDX $76                         ; $409D  beam 3's row
        LDY $73                         ; $409F  beam 3's column
        JMP print_string                ; $40A1  print it, and return from there
; Strings 7 higher, the upper beam's own frames. The three _later entries
; match the three rows above.
print_row74_later:
        CLC                             ; $40A4  carry clear
        ADC #$07                        ; $40A5  seven strings on
        JMP print_row74                 ; $40A7  draw this frame
        BNE print_row74                 ; $40AA  not reached
; Strings 7 higher, on the middle row.
print_row75_later:
        CLC                             ; $40AC  carry clear
        ADC #$07                        ; $40AD  seven strings on
        JMP print_row75                 ; $40AF  draw this frame
        BNE print_row75                 ; $40B2  not reached
; Strings 7 higher, on the bottom row.
print_row76_later:
        CLC                             ; $40B4  carry clear
        ADC #$07                        ; $40B5  seven strings on
        JMP print_row76                 ; $40B7  draw this frame
        BNE print_row76                 ; $40BA  not reached


; Once per logic frame, from frame, before the overlap. $0101, $0102, and
; $0103 each reload to a count from 1 to 15. The new row comes from
; noise_byte. The display charset is at $A000.
; $0101 writes glyph $93, bytes 2 and 3 ($A49A). That is the shadow of tile
; $13. Noise masked with $30 is combined with $CC, so one dot cycles through
; the four multicolor pairs. The same byte masked with $B8 goes to glyph $86.
; $0102 does the $30/$CC write to glyph $B1 ($A58A), the shadow of tile $31.
; $0103 masks with $0C, combines with $33, and stores glyph $94 ($A4A2), the
; shadow of tile $14. Masked with $2E, that byte also goes to glyph $E7.
; The $A800 copies ($AC9A, $AD8A, $ACA2) receive the mask by itself, and
; glyphs $86 and $E7 are not written there. Charset $B000, selected for room
; $12, is not written, so those lamps stay still. This snapshot's room shows
; charset $A000, and its lamps are tiles $14 and $31, so those two shapes
; flicker. Lamps of one shape share the glyph and change together.
flicker_lamps:
        DEC $0101                       ; $40BC  the first count
        BNE flicker_second_count        ; $40BF  still counting
flicker_first:
        JSR noise_byte                  ; $40C1  a noise byte
        AND #$0F                        ; $40C4  1-15
        BEQ flicker_first               ; $40C6  0: again
        STA $0101                       ; $40C8  the next count
        JSR noise_byte                  ; $40CB  a noise byte
        AND #$30                        ; $40CE  one dot's pair
        STA $AC9A                       ; $40D0  glyph $93 in charset $A800, row 1
        STA $AC9B                       ; $40D3  doubled
        ORA #$CC                        ; $40D6  with the rest of the shape
        STA $A49A                       ; $40D8  glyph $93 in charset $A000, row 1
        STA $A49B                       ; $40DB  doubled
        AND #$B8                        ; $40DE  another mask
        STA $A432                       ; $40E0  glyph $86, row 1
        STA $A433                       ; $40E3  doubled
flicker_second_count:
        DEC $0102                       ; $40E6  the second count
        BNE flicker_third_count         ; $40E9  still counting
flicker_second:
        JSR noise_byte                  ; $40EB  a noise byte
        AND #$0F                        ; $40EE  1-15
        BEQ flicker_second              ; $40F0  0: again
        STA $0102                       ; $40F2  the next count
        JSR noise_byte                  ; $40F5  a noise byte
        AND #$30                        ; $40F8  one dot's pair
        STA $AD8A                       ; $40FA  glyph $B1 in charset $A800, row 1
        STA $AD8B                       ; $40FD  doubled
        ORA #$CC                        ; $4100  with the rest of the shape
        STA $A58A                       ; $4102  glyph $B1 in charset $A000, row 1
        STA $A58B                       ; $4105  doubled
flicker_third_count:
        DEC $0103                       ; $4108  the third count
        BNE flicker_done                ; $410B  still counting
flicker_third:
        JSR noise_byte                  ; $410D  a noise byte
        AND #$0F                        ; $4110  1-15
        BEQ flicker_third               ; $4112  0: again
        STA $0103                       ; $4114  the next count
        JSR noise_byte                  ; $4117  a noise byte
        AND #$0C                        ; $411A  one dot's pair
        STA $ACA2                       ; $411C  glyph $94 in charset $A800, row 2
        STA $ACA3                       ; $411F  doubled
        ORA #$33                        ; $4122  with the rest of the shape
        STA $A4A2                       ; $4124  glyph $94 in charset $A000, row 2
        STA $A4A3                       ; $4127  doubled
        AND #$2E                        ; $412A  another mask
        STA $A73A                       ; $412C  glyph $E7, row 1
        STA $A73B                       ; $412F  doubled
flicker_done:
        RTS                             ; $4132  back

; Room 18's two sparks, sprites at $8340 and $8380. X runs 3 down to 0
; and Y steps 0, 3, 6, 9, so each shape gets four bytes. The byte is
; noise AND $4322,X. Those four mask bytes are 18 3C 3C 18, read from
; the end, so the rows come out 18, 3C, 3C, 18. blank_sparks zeros
; the same four offsets.
paint_sparks:
        LDX #$03                        ; $4133  four rows
        LDY #$00                        ; $4135  offset 0
sparks_shape_loop:
        JSR noise_byte                  ; $4137  a noise byte
        AND $4322,X                     ; $413A  masked
        STA $8340,Y                     ; $413D  spark 6's shape
        JSR noise_byte                  ; $4140  a noise byte
        AND $4322,X                     ; $4143  masked
        STA $8380,Y                     ; $4146  spark 7's shape
        INY                             ; $4149  three bytes on
        INY                             ; $414A  the next
        INY                             ; $414B  row
        DEX                             ; $414C  the next mask
        BPL sparks_shape_loop           ; $414D  more
        LDA $432E                       ; $414F  spark 6 falling?
        BNE sparks_check_7              ; $4152  yes
        LDA $4330                       ; $4154  its wait
        BNE sparks_wait_6               ; $4157  still waiting
        JSR launch_spark_6              ; $4159  launch it
        JMP sparks_fall                 ; $415C  move them
sparks_wait_6:
        DEC $4330                       ; $415F  one frame less
sparks_check_7:
        LDA $432F                       ; $4162  spark 7 falling?
        BNE sparks_fall                 ; $4165  yes
        LDA $4331                       ; $4167  its wait
        BNE sparks_wait_7               ; $416A  still waiting
        JSR launch_spark_7              ; $416C  launch it
        JMP sparks_fall                 ; $416F  move them
sparks_wait_7:
        DEC $4331                       ; $4172  one frame less
sparks_fall:
        LDX #$01                        ; $4175  two sparks
sparks_fall_loop:
        LDA $432E,X                     ; $4177  falling?
        BEQ sparks_fall_next            ; $417A  no
        LDA $4334,X                     ; $417C  its ypos
        CLC                             ; $417F  carry clear
        ADC #$05                        ; $4180  five pixels down
        STA $4334,X                     ; $4182  stored
        CMP #$E0                        ; $4185  past $E0?
        BCC sparks_fall_next            ; $4187  no
        LDA #$00                        ; $4189  zero
        STA $432E,X                     ; $418B  it stops
        LDA #$02                        ; $418E  two frames
        STA $4330,X                     ; $4190  before the next launch
sparks_fall_next:
        DEX                             ; $4193  the next spark
        BPL sparks_fall_loop            ; $4194  more
        LDA $432E                       ; $4196  spark 6 falling?
        BEQ sparks_check_second         ; $4199  either way, the next line
; This BEQ and the one before it both have offset 0, so neither one
; changes where the code goes.
sparks_check_second:
        LDA $432F                       ; $419B  spark 7 falling?
        BEQ sparks_place                ; $419E  either way, the next line
sparks_place:
        LDX #$01                        ; $41A0  two sparks
sparks_place_loop:
        LDA $432E,X                     ; $41A2  falling?
        BEQ sparks_place_next           ; $41A5  no
        LDY #$01                        ; $41A7  one step
        LDA $4334,X                     ; $41A9  its ypos
        CMP #$A8                        ; $41AC  $A8 or more?
        BCS sparks_chase_step           ; $41AE  yes
        INY                             ; $41B0  two steps while it is high
sparks_chase_step:
        LDA $4332,X                     ; $41B1  its xpos
        CMP $9E                         ; $41B4  right of Bruce?
        BCS sparks_chase_left           ; $41B6  yes, or level
        INC $4332,X                     ; $41B8  one step right
        BNE sparks_chase_next           ; $41BB  always
sparks_chase_left:
        BEQ sparks_chase_next           ; $41BD  level: stay
        DEC $4332,X                     ; $41BF  one step left
sparks_chase_next:
        DEY                             ; $41C2  one step done
        BPL sparks_chase_step           ; $41C3  more
        LDA $4332,X                     ; $41C5  its xpos
        ASL A                           ; $41C8  screen x, bit 8 into carry
        PHA                             ; $41C9  kept
        LDA $D010                       ; $41CA  sprite x bit 8
        BCC sparks_clear_x_high         ; $41CD  bit 8 clear
        ORA $42C5,X                     ; $41CF  this sprite's bit
        BNE sparks_store_x_high         ; $41D2  always
sparks_clear_x_high:
        AND $42C7,X                     ; $41D4  without this sprite's bit
sparks_store_x_high:
        STA $D010                       ; $41D7  sprite x bit 8
        TXA                             ; $41DA  the spark
        ASL A                           ; $41DB  times 2
        TAX                             ; $41DC  its register pair
        PLA                             ; $41DD  screen x
        STA $D00C,X                     ; $41DE  sprite 6 x, plus X
        TXA                             ; $41E1  the spark
        LSR A                           ; $41E2  halved
        TAX                             ; $41E3  back
        LDA $4334,X                     ; $41E4  its ypos
        CLC                             ; $41E7  carry clear
        ADC #$1D                        ; $41E8  plus $1D
        PHA                             ; $41EA  kept
        TXA                             ; $41EB  the spark
        ASL A                           ; $41EC  times 2
        TAX                             ; $41ED  its register pair
        PLA                             ; $41EE  screen y
        STA $D00D,X                     ; $41EF  sprite 6 y, plus X
        TXA                             ; $41F2  the spark
        LSR A                           ; $41F3  halved
        TAX                             ; $41F4  back
        JSR noise_byte                  ; $41F5  a noise byte
        ORA #$F0                        ; $41F8  a random color
        STA $D02D,X                     ; $41FA  sprite 6 color, plus X
sparks_place_next:
        DEX                             ; $41FD  the next spark
        BPL sparks_place_loop           ; $41FE  more
        RTS                             ; $4200  back
; Room 18. Sprite 6 is turned on with image $0D, its timer at $432E is
; set, and its bytes at $4332 and $4334 start at $50 and $37, with
; hit_sound.
launch_spark_6:
        LDA #$0D                        ; $4201  image $0D
        STA $8FFE                       ; $4203  sprite 6's pointer
        LDA $D015                       ; $4206  sprite enable
        ORA #$40                        ; $4209  sprite 6 on
        STA $D015                       ; $420B  sprite enable
        LDA #$01                        ; $420E  1
        STA $432E                       ; $4210  falling
        LDA #$50                        ; $4213  xpos $50
        STA $4332                       ; $4215  stored
        LDA #$37                        ; $4218  ypos $37
        STA $4334                       ; $421A  stored
        JMP hit_sound                   ; $421D  effect $86, and return from there
; The same for sprite 7, image $0E, starting at $5E, $37.
launch_spark_7:
        LDA #$0E                        ; $4220  image $0E
        STA $8FFF                       ; $4222  sprite 7's pointer
        LDA $D015                       ; $4225  sprite enable
        ORA #$80                        ; $4228  sprite 7 on
        STA $D015                       ; $422A  sprite enable
        LDA #$01                        ; $422D  1
        STA $432F                       ; $422F  falling
        LDA #$5E                        ; $4232  xpos $5E
        STA $4333                       ; $4234  stored
        LDA #$37                        ; $4237  ypos $37
        STA $4335                       ; $4239  stored
        JMP hit_sound                   ; $423C  effect $86, and return from there

; Zero the four bytes paint_sparks writes into the two room-18 spark shapes,
; offsets 0, 3, 6, and 9 of $8340 and $8380. between_lives, game_over,
; and the room-18 finish all call this so a spark pixel is not left up.
blank_sparks:
        LDX #$09                        ; $423F  offset 9
        LDA #$00                        ; $4241  zero
blank_sparks_loop:
        STA $8340,X                     ; $4243  spark 6's shape
        STA $8380,X                     ; $4246  spark 7's shape
        DEX                             ; $4249  three bytes back
        DEX                             ; $424A  the next
        DEX                             ; $424B  row
        BPL blank_sparks_loop           ; $424C  more
        RTS                             ; $424E  back

; Effect $8A. A, X, and Y come back unchanged. OpenDoor,
; OpenLateDoor, and the room countdown hooks all come here.
play_sound_8a:
        PHA                             ; $424F  keep A
        TXA                             ; $4250  X
        PHA                             ; $4251  keep X
        TYA                             ; $4252  Y
        PHA                             ; $4253  keep Y
        LDY #$8A                        ; $4254  effect $8A
        JSR play_sound                  ; $4256  queue it
        PLA                             ; $4259  Y back
        TAY                             ; $425A  into Y
        PLA                             ; $425B  X back
        TAX                             ; $425C  into X
        PLA                             ; $425D  A back
        RTS                             ; $425E  back
; Enter hook for room 19, the treasure room. enter_room has already
; stored screen code $20 across $8C00, the solid black bar. Writing 0
; selects glyph 0, which is empty, so $D021 shows through. raster_irq
; holds that at $FC, grey, for this row and for the score row under it.
; $49/$4A become $0458. irq_service counts that pair down, one per
; raster, 1112 rasters.
hook_enter_19:
        LDA #$58                        ; $425F  $58
        STA $49                         ; $4261  the timeout, low
        LDA #$04                        ; $4263  $04
        STA $4A                         ; $4265  the timeout, high
        LDX #$27                        ; $4267  40 cells
        LDA #$00                        ; $4269  glyph 0, empty
; 40 bytes, $8C00-$8C27, row 0.
blank_top_row:
        STA $8C00,X                     ; $426B  row 0
        DEX                             ; $426E  the next
        BPL blank_top_row               ; $426F  more
        RTS                             ; $4271  back
; Per-frame hook for room 19. While $49 or $4A is still set, the flame
; rows are recoloured and string 4 is printed. String 4 is
; "** CONGRATULATIONS **". X = 0 is row 0 and Y = $0A is the column, so
; the line sits on the grey bar. The score on row 1 is left alone, and
; timed_caption keeps flashing the player word on that row. The line is
; printed again every logic frame.
; When both timer bytes are 0, $40 gains one finished game. This
; player's four bytes at $014B go back to 1. Room 13 spends the first
; three of those, once each. copy_room_defaults reloads the lamp counts,
; restore_lamps rearms the lamp flags, and rearm_room_bonus rearms the
; entry bonuses. Room 0 then opens.
hook_frame_19:
        LDA $49                         ; $4272  the timer
        ORA $4A                         ; $4274  ORed with the high byte
        BNE treasure_hold               ; $4276  still counting
        INC $40                         ; $4278  one more finished game
        LDA $03                         ; $427A  the player
        ASL A                           ; $427C  shifted up
        ASL A                           ; $427D  times 4
        TAX                             ; $427E  his room 13 flags
        LDY #$03                        ; $427F  four bytes
        LDA #$01                        ; $4281  1
; Four bytes at $014B + player*4.
reset_band:
        STA $014B,X                     ; $4283  set again
        INX                             ; $4286  the next
        DEY                             ; $4287  one fewer
        BPL reset_band                  ; $4288  more
        JSR copy_room_defaults          ; $428A  the lamp counts
        JSR restore_lamps               ; $428D  the lamp flags
        JSR rearm_room_bonus            ; $4290  the room bonuses
        LDX #$00                        ; $4293  room 0
        JMP enter_room_at               ; $4295  enter it at its spawn
; Inks 8 through 15, with the high nibble $F the rest of color RAM uses.
; Eight rows of 29 columns, from $D800+$2AC: character row 17, column 4,
; through column 32, and the seven rows under it. The flames.
treasure_hold:
        JSR noise_byte                  ; $4298  a noise byte
        AND #$07                        ; $429B  ink 0-7
        ORA #$F8                        ; $429D  with bit 3: inks 8-15
        LDX #$1C                        ; $429F  29 columns
; One ink, the same for all 29 columns of the eight rows, new each frame.
flicker_flames:
        STA $DAAC,X                     ; $42A1  color RAM, row 17 column 4, plus X
        STA $DAD4,X                     ; $42A4  color RAM, row 18 column 4, plus X
        STA $DAFC,X                     ; $42A7  color RAM, row 19 column 4, plus X
        STA $DB24,X                     ; $42AA  color RAM, row 20 column 4, plus X
        STA $DB4C,X                     ; $42AD  color RAM, row 21 column 4, plus X
        STA $DB74,X                     ; $42B0  color RAM, row 22 column 4, plus X
        STA $DB9C,X                     ; $42B3  color RAM, row 23 column 4, plus X
        STA $DBC4,X                     ; $42B6  color RAM, row 24 column 4, plus X
        DEX                             ; $42B9  the next
        BPL flicker_flames              ; $42BA  more
        LDA #$04                        ; $42BC  string $04
        LDX #$00                        ; $42BE  tile row $00
        LDY #$0A                        ; $42C0  column $0A
        JMP print_string                ; $42C2  print it, and return from there
; $42C5  1217 bytes of data. $42C9 and $42CA are the two option flags inside
; this block, then $42CB and $42CC, their copies. print_string reads the
; table at $43BE. String 0 at $4488 is 20 20 20, three spaces. String 1 at
; $448C is 31 55 50, "1UP". String 2 at $4490 is 32 55 50, "2UP".
; timed_caption prints one of those at column $2C. String $04 is
; "** CONGRATULATIONS **", printed on the blanked top row by hook_frame_19.
; String $4F is the F3 line, $50 the F5
; line, $51 the F7 line. $08, $09, $0A, and $0D are the four handedness lines.
; $42CD and $42DF are the GAME OVER picture, eighteen screen codes each.
; paint_over_word ORs $80 and stores them at column 11 of rows 1 and 2.
; A letter is two codes wide. $5C $5C is the gap between the words.
;   $42CD  10 12 00 02 18 1A 0C 0E 5C 5C 1C 1E 2C 2E 0C 0E 24 26
;   $42DF  11 13 01 03 19 1B 0D 0F 5C 5C 1D 1F 2D 2F 0D 0F 25 27
; Top row, in pairs: G A M E, the gap, O V E R. The bottom row is the
; lower half of the same letters. Both E's share 0C 0E and 0D 0F.
; $4322 is 18 3C 3C 18. paint_sparks reads it from the last byte.
; $4707 is forty score-font codes, one screen row. V copies them onto $8C00
; when that row is still the $20 bar:
;   BRUCE LEE (C) 1984 DATASOFT REV.2 BY RJF
; '(' is glyph $08 and ')' is glyph $09, ROM $28 and $29 shifted down by $20.
;
; The whole block, in order:
;   $42C5  40 80, then BF 7F: the $D010 bit of sprites 6 and 7, set and
;          clear, for the room 18 sparks.
;   $42C9  the F3 and F5 flags, then $42CB/$42CC their copies.
;   $42CD  the GAME OVER picture, two rows of eighteen codes, to $42F0.
;   $42F1  the 24 pattern bytes scroll_surface copies for rooms below 10,
;          and $4309 the 24 for room 11.
;   $4321  scroll_surface's slot in $4CB2.
;   $4322  the spark mask 18 3C 3C 18. $4326-$432D are zero and not read.
;   $432E  room 18's spark state: $432E/$432F falling, $4330/$4331 the
;          waits before a launch, $4332/$4333 xpos, $4334/$4335 ypos, and
;          $4336/$4337, stored by hook_enter_18 and not read.
;   $4338  the row pointers build_row_pointers makes, fourteen entries
;          each: $4338 screen low, $434C screen high, $4360 second-row low,
;          $4374 second-row high. The six bytes after each set are not read.
;   $4388  the top score, three binary bytes, high byte first.
;   $438B  the first extra-fall mark, 00 9C 40, 40000. $438E is the step
;          added at each crossing, 00 75 30, 30000. $4391 is not read.
;          top_replace copies four bytes, so a new top score also writes
;          $44, the raster split index, over $438B. The next game's first
;          mark is then $xx9C40. room01.vsf holds 02 9C 40 there.
;   $4392  the live mark, and $4395 the waiting player's copy.
;   $4398  the binary value stash_scores and draw_top convert. $439B-$439E
;          are the eight BCD digits that come out. lives_to_bcd borrows
;          $4398 and $439B too.
;   $439F  the waiting player's copy of $28-$43, 28 bytes: falls, room,
;          lamp counts, and score. between_lives trades the two.
;   $43BB  scale_by_eight's result, high byte then low.
;   $43BD  the 1UP/2UP caption timer.
;   $43BE  101 string pointers, then the strings themselves at
;          $4488-$4785, each ending in $A0. $4707, the credit line, sits
;          among them and has no terminator. Strings $52 and $53, "PLAYER 1"
;          and "PLAYER 2", and $62, "DATASOFT PRESENTS", are never printed.
;          The PLAYER page draws its own big letters from $4A5D instead.

; Advance ($04) by one. The unpack's upper screen cell, and the source
; pointer in expand_library.
step_ptr_04:
        INC $04                         ; $4786  one on
        BNE step_ptr_04_done            ; $4788  no carry
        INC $05                         ; $478A  the carry
step_ptr_04_done:
        RTS                             ; $478C  back
; Advance ($06) by one. The unpack's source byte.
step_ptr_06:
        INC $06                         ; $478D  one on
        BNE step_ptr_06_done            ; $478F  no carry
        INC $07                         ; $4791  the carry
step_ptr_06_done:
        RTS                             ; $4793  back
; Advance ($08) by one. The unpack's lower screen cell.
step_ptr_08:
        INC $08                         ; $4794  one on
        BNE step_ptr_08_done            ; $4796  no carry
        INC $09                         ; $4798  the carry
step_ptr_08_done:
        RTS                             ; $479A  back

; $479B  192 bytes of color and raster tables.
;   $479B  four colors init_hardware copies to $D020-$D023: border black,
;          background dark grey, multicolor 1 white, multicolor 2 light blue.
;   $479F  one byte not read.
;   $47A0  twenty room fill colors, one per room, written across color RAM
;          before the unpack.
;   $47B4  twenty bytes, save_band_colors' copy of $0153 for the idle pause.
;   $47C8  the band color sets. Each is twelve bytes ($D021, $D022, $D023
;          for four bands), and rooms that share colors share a set, so the
;          sets overlap.
;   $47F5  four raster bytes, the current room's band lines, copied from the
;          room's set below.
;   $47F9  the raster line sets.
;   $480B  twenty words, each room's band color set (rooms 0-3 share $47C8).
;   $4833  twenty words, each room's raster line set.
; The raster setup at $48EA copies the room's twelve colors to $0153 and
; its four lines to $47F5.

; After each packed cell. $F3 counts the 40 columns of a row down from
; $27. At the end of a row all four pointers move on 40 more, so with the
; 40 single steps they skip the lower row they already filled: each
; packed cell is two cells tall, the tile on top and the tile OR $80
; below. A is kept.
unpack_next_row:
        PHA                             ; $485B  keep A
        DEC $F3                         ; $485C  one column fewer
        BPL unpack_row_done             ; $485E  still in the row
        LDA #$27                        ; $4860  40 columns
        STA $F3                         ; $4862  again
        LDA $04                         ; $4864  upper screen cell, low
        CLC                             ; $4866  carry clear
        ADC #$28                        ; $4867  one row on
        STA $04                         ; $4869  stored
        BCC unpack_row_color            ; $486B  no carry
        INC $05                         ; $486D  the carry
unpack_row_color:
        LDA $08                         ; $486F  lower screen cell, low
        CLC                             ; $4871  carry clear
        ADC #$28                        ; $4872  one row on
        STA $08                         ; $4874  stored
        BCC unpack_row_upper            ; $4876  no carry
        INC $09                         ; $4878  the carry
unpack_row_upper:
        LDA $10                         ; $487A  upper color cell, low
        CLC                             ; $487C  carry clear
        ADC #$28                        ; $487D  one row on
        STA $10                         ; $487F  stored
        BCC unpack_row_lower            ; $4881  no carry
        INC $11                         ; $4883  the carry
unpack_row_lower:
        LDA $12                         ; $4885  lower color cell, low
        CLC                             ; $4887  carry clear
        ADC #$28                        ; $4888  one row on
        STA $12                         ; $488A  stored
        BCC unpack_row_done             ; $488C  no carry
        INC $13                         ; $488E  the carry
unpack_row_done:
        PLA                             ; $4890  A back
        RTS                             ; $4891  back

; Double the packed glyphs. Four source bytes are written twice through ($06),
; and the next four twice through ($08). The caller sets $F3 to the number of
; groups minus one. Startup at $047A calls this four times. The setups and
; the fact that $9000 is later overwritten are in rooms.asm. A picture row
; occupies two charset bytes because of this, which is why flicker_lamps
; stores its new value into both bytes of the pair.
expand_charset:
        LDY #$00                        ; $4892  Y stays 0
        LDX #$03                        ; $4894  four bytes
expand_first_half:
        LDA ($04),Y                     ; $4896  a source byte
        STA ($06),Y                     ; $4898  into the first copy
        JSR step_ptr_06                 ; $489A  the next
        STA ($06),Y                     ; $489D  doubled
        JSR step_ptr_06                 ; $489F  the next
        JSR step_ptr_04                 ; $48A2  the next source byte
        DEX                             ; $48A5  one fewer
        BPL expand_first_half           ; $48A6  more
        LDX #$03                        ; $48A8  four bytes
expand_second_half:
        LDA ($04),Y                     ; $48AA  a source byte
        STA ($08),Y                     ; $48AC  into the second copy
        JSR step_ptr_08                 ; $48AE  the next
        STA ($08),Y                     ; $48B1  doubled
        JSR step_ptr_08                 ; $48B3  the next
        JSR step_ptr_04                 ; $48B6  the next source byte
        DEX                             ; $48B9  one fewer
        BPL expand_second_half          ; $48BA  more
        DEC $F3                         ; $48BC  one group fewer
        BPL expand_charset              ; $48BE  more
        RTS                             ; $48C0  back

; In-game raster interrupt. arm_raster points here and compares against raster
; $FB. This pass selects charset $8800 ($D018 = $32), which is the score font,
; and arms raster $40. With the yscroll left at 3, the display starts at
; raster $33, so raster $40 is inside character row 1, the score text. $D021
; stays $FC (grey) for row 0 and for that score row. raster_open then installs
; the room charset and the first color band, before row 2 is drawn. Row 2 is
; screen code $06, solid black in that charset, which is why the strip above
; the picture is black rather than the room background. The room index in $29
; picks two tables. $480B, room*2
; is twelve color bytes, copied to $0153: four bands of $D021, $D022, $D023.
; $4833, room*2 is the split list, and only its first four bytes are copied to
; $47F5. Room 0's splits are $78, $97, and $FD. $FD ends the chain. Several
; rooms share one list; the pointers are in rooms.asm. Each color byte is
; stored with a high nibble of $F, and the VIC uses the low nibble.
; irq_service
; runs before the RTI, and that is the only pass that counts $48 down.
raster_irq:
        LDA #$32                        ; $48C1  screen $8C00, charset $8800
        STA $D018                       ; $48C3  screen and charset address
        LDA #$FC                        ; $48C6  grey
        STA $D021                       ; $48C8  background color
; The next interrupt is raster_open, at raster $40.
        LDA #$1E                        ; $48CB  raster_open, low
        STA $0408                       ; $48CD  the vector at $0408
        LDA #$49                        ; $48D0  high
        STA $0409                       ; $48D2  the vector
        LDA #$01                        ; $48D5  the raster interrupt
        STA $D01A                       ; $48D7  VIC interrupt enable
        STA $D019                       ; $48DA  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $48DD  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $48E0  raster bit 8 clear
        STA $D011                       ; $48E2  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$40                        ; $48E5  line $40
        STA $D012                       ; $48E7  raster line
        LDA $29                         ; $48EA  the room
        ASL A                           ; $48EC  times 2
        TAX                             ; $48ED  the index
        LDA $480B,X                     ; $48EE  its band colors, low
        STA $0A                         ; $48F1  pointer
        LDA $480C,X                     ; $48F3  high
        STA $0B                         ; $48F6  pointer
        LDA $4833,X                     ; $48F8  its split lines, low
        STA $0C                         ; $48FB  pointer
        LDA $4834,X                     ; $48FD  high
        STA $0D                         ; $4900  pointer
        LDY #$0B                        ; $4902  twelve colors
raster_copy_bands:
        LDA ($0A),Y                     ; $4904  a color
        STA $0153,Y                     ; $4906  the live band colors
        CPY #$04                        ; $4909  one of the first four?
        BCS raster_copy_next            ; $490B  no
        LDA ($0C),Y                     ; $490D  a split line
        STA $47F5,Y                     ; $490F  the live split lines
raster_copy_next:
        DEY                             ; $4912  the next
        BPL raster_copy_bands           ; $4913  more
        JSR irq_service                 ; $4915  the voices, sticks, sprites, and counts
        PLA                             ; $4918  Y back
        TAY                             ; $4919  into Y
        PLA                             ; $491A  X back
        TAX                             ; $491B  into X
        PLA                             ; $491C  A back
        RTI                             ; $491D  back

; Raster $40, inside the score row. The wait below runs until raster $41, then
; a short delay, still before row 2. $F2 is restored to $D018. In a normal
; room that is $38, charset $A000. The first band is then taken from $0153.
; A split list whose first byte is $FD never reaches raster_split, so this
; first band is the only one on screen. Rooms 4, 5, and 6 are that case:
; background 6, $D022 light blue, $D023 white.
raster_open:
        LDA #$41                        ; $491E  line $41
raster_open_wait:
        CMP $D012                       ; $4920  raster line
        BCS raster_open_wait            ; $4923  not yet
        LDX #$0A                        ; $4925  a few cycles
raster_open_delay:
        DEX                             ; $4927  count down
        BNE raster_open_delay           ; $4928  more
        LDA $F2                         ; $492A  the room's charset
        STA $D018                       ; $492C  screen and charset address
        LDA $0153                       ; $492F  band 1's background
        STA $D021                       ; $4932  background color
        LDA $0154                       ; $4935  band 1's multicolor 1
        STA $D022                       ; $4938  background multicolor 1
        LDA $0155                       ; $493B  band 1's multicolor 2
        STA $D023                       ; $493E  background multicolor 2
        LDA #$00                        ; $4941  zero
        STA $44                         ; $4943  the first split
        LDA #$03                        ; $4945  band 2's colors
        STA $F4                         ; $4947  the color index
; The splits after this one are raster_split.
        LDA #$82                        ; $4949  raster_split, low
        STA $0408                       ; $494B  the vector at $0408
        LDA #$49                        ; $494E  high
        STA $0409                       ; $4950  the vector

; Arm the next split from $47F5. A value of $FD points the vector back at
; raster_irq instead of raster_split.
raster_arm:
        LDA #$01                        ; $4953  the raster interrupt
        STA $D01A                       ; $4955  VIC interrupt enable
        STA $D019                       ; $4958  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $495B  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $495E  raster bit 8 clear
        STA $D011                       ; $4960  VIC control: yscroll, 25 rows, raster bit 8
        LDX $44                         ; $4963  the split
        LDA $47F5,X                     ; $4965  its line
        STA $D012                       ; $4968  raster line
        CMP #$FD                        ; $496B  the end marker?
        BEQ raster_last_split           ; $496D  yes
raster_return:
        PLA                             ; $496F  Y back
        TAY                             ; $4970  into Y
        PLA                             ; $4971  X back
        TAX                             ; $4972  into X
        PLA                             ; $4973  A back
        RTI                             ; $4974  back
raster_last_split:
; The split was $FD. Point the vector back at raster_irq.
        LDA #$C1                        ; $4975  raster_irq, low
        STA $0408                       ; $4977  the vector at $0408
        LDA #$48                        ; $497A  high
        STA $0409                       ; $497C  the vector
        JMP raster_return               ; $497F  return

; A color split. Wait until the raster in the list, then store the next three
; bytes as $D021, $D022, and $D023. $F4 starts at 3 and advances by 3, so the
; bytes are band 2, then band 3, then band 4.
raster_split:
        LDX $F4                         ; $4982  the color index
        LDY $0153,X                     ; $4984  this band's background
        LDX $44                         ; $4987  the split
        LDA $47F5,X                     ; $4989  its line
        TAX                             ; $498C  into X
        INX                             ; $498D  two lines on
        INX                             ; $498E  three lines on, in X
        TXA                             ; $498F  the line plus 2, in A
        INX                             ; $4990  the line plus 3, in X
raster_split_wait:
        CPX $D012                       ; $4991  raster line
        BEQ raster_split_colors         ; $4994  three lines past: store at once
        CMP $D012                       ; $4996  raster line
        BNE raster_split_wait           ; $4999  not two lines past yet
        LDX #$0A                        ; $499B  a few cycles
raster_split_delay:
        DEX                             ; $499D  count down
        BNE raster_split_delay          ; $499E  more
raster_split_colors:
        STY $D021                       ; $49A0  background color
        LDX $F4                         ; $49A3  the color index
        LDA $0154,X                     ; $49A5  this band's multicolor 1
        STA $D022                       ; $49A8  background multicolor 1
        LDA $0155,X                     ; $49AB  this band's multicolor 2
        STA $D023                       ; $49AE  background multicolor 2
        LDA $F4                         ; $49B1  the color index
        CLC                             ; $49B3  carry clear
        ADC #$03                        ; $49B4  the next band
        STA $F4                         ; $49B6  stored
        INC $44                         ; $49B8  the next split
        JMP raster_arm                  ; $49BA  arm it

; $49BD  1822 bytes of data between routines. The first 160 bytes are the four
; logo rows open_room copies: $49BD, $49E5, $4A0D, $4A35. $4A5D and $4A6D are
; the two PLAYER lines, 16 bytes each. $4A7D is eight digit glyphs, player 1
; then player 2. $4A85 is the four-byte left-handed stick rotation.
;
; The rest of the block, in order. rooms.asm lists most of these tables.
;   $4A89  00 3A 76, the three xpos marks hook_frame_18 sorts Bruce into.
;   $4A8C  the picture hold for each state, $00-$1B. set_state, keep_state,
;          and the timed setters store it in $0106,X.
;   $4AA8  twenty words, each room's 20 bytes for $0153, from $4AD0. The
;          sets overlap, and room 18's and room 19's run on into $4B34.
;   $4B34  the packed pictures' low bytes, and $4B49 the high bytes. Each
;          list has a 21st byte that no room reads.
;   $4B5E  the four door tables. $4B5E, $4B72, $4B86, and $4B9A are the
;          destination rooms. $4BFE/$4C12, $4C26/$4C3A, $4C4E/$4C62, and
;          $4C76/$4C8A are the xpos and ypos.
;   $4BAE  the main spawn, xpos then $4BC2 ypos. $4BD6/$4BEA are the
;          alternate spawn.
;   $4C9E  $FF in rooms 3, 8, 9, 11, 13, and 17-19. enter_room copies it
;          to $7A, and frame then skips the wake counts, so the fighters
;          never wake there. frame also skips read_sprite_hits.
;   $4CB2  scroll_surface's eight delays, 84 08 06 04 02 04 06 08.
;   $4CBA  20 bytes nothing reads: 32 1F 1E 1A 18 1D 1B 33 35 30, then
;          the same ten with $40 added, the inverse glyphs in the score font.
;   $4CCE  each room's lamp count, copied to $2A.
;   $4CE2  each room's lamp list. There is a 21st word, $4E90, that no room
;          uses. The lists run from $4D0C to $4E94, and the flags in them
;          are what changes as lamps are taken.
;   $4E95  the two players' extra-fall counts for room 16.
;   $4E97  five counters the room hooks use, $4E97-$4E9B. point_lamp_list
;          clears them before the enter hook.
;   $4E9C  the twenty enter hooks, then $4EC4 the twenty frame hooks,
;          each the address minus one.
;   $4EEC  irq_service's countdown for the landing counts at $4F45.
;   $4EED  the three columns' nibble slots for the overlap, 23 bytes each,
;          at $4EED, $4F04, and $4F1B. $4F32-$4F34 mark a column whose
;          slots are swapped, and $4F35-$4F37 keep those marks for the upper
;          body. $4F38-$4F3A are scan_row's three stop rows.
;   $4F3B  five flags flags_from_nibbles clears. $4F3B is not read again.
;          $4F3C-$4F3F become hit bits 0-3.
;   $4F40  the five voice slots claim_voice_slot gives to actors.
;   $4F45  the three landing counts, 2 each. irq_service reloads them, and
;          blow_landing spends one per landing.
;   $4F48  the pose tables, three bytes each: $4F48 and $4F4B the relative
;          libraries, $4F4E and $4F51 the absolute ones, $4F54 the last one.
;   $4F57  the step history. Each generation is twelve bytes, the four
;          counters (up, down, left, right) for the three actors, and there
;          are eleven, to $4FDA.
;   $4FDB  one byte per actor. choose_pose runs only while it is 0, and
;          then sets it.
;   $4FDE  the three crumble slots: $4FDE count, $4FE1 column, $4FE4 row.
;   $4FE7  255 bytes nothing reads. The first is $11 and the rest are 0.

; Bit 4 of $D011 turns the screen on. Bit 7 stays clear, so the raster compare uses $D012
; alone.
show_screen:
        LDA $D011                       ; $50DB  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $50DE  raster bit 8 clear
        ORA #$10                        ; $50E0  screen on
        STA $D011                       ; $50E2  VIC control: yscroll, 25 rows, raster bit 8
        RTS                             ; $50E5  back

; $50E6  73 bytes: one byte not read, then three 24-byte tables that
; point_scan_row uses for character rows 0-23. $50E7 is each row's low
; byte, $50FF the screen high byte, and $5117 the color RAM high byte.
; Called from boot. Spins until $CF8F and $CFAF are both $B9, then
; builds the sprite pictures from the library pointers at $59BD, $5A8F,
; and $5B61. $5CBF,X is the same byte place_sprites later reads.
build_sprites:
        LDA $CF8F                       ; $512F  a check byte
        CMP #$B9                        ; $5132  $B9?
        BNE build_sprites               ; $5134  no: forever
        EOR $CFAF                       ; $5136  its partner the same?
        BNE build_sprites               ; $5139  no: forever
        LDX #$D1                        ; $513B  library $D1 first
build_pose_loop:
        STX $51                         ; $513D  the library
        LDA $1239,X                     ; $513F  its scan picture, high
        BEQ build_pose_blank            ; $5142  none
        JSR expand_library              ; $5144  expand it into its page
        JMP build_pose_first            ; $5147  then the one below
build_pose_blank:
        LDY #$5F                        ; $514A  96 bytes
        LDA #$00                        ; $514C  zero
build_pose_clear:
        STA $CAE0,Y                     ; $514E  the scratch page
        DEY                             ; $5151  the next
        BPL build_pose_clear            ; $5152  more
build_pose_first:
        DEC $51                         ; $5154  the library below
        LDX $51                         ; $5156  in X
        JSR expand_library              ; $5158  expand it
        LDX $51                         ; $515B  the library
        LDA $1167,X                     ; $515D  its scan page, low
        STA $06                         ; $5160  pointer
        LDA $1239,X                     ; $5162  high
        STA $07                         ; $5165  pointer
        LDY #$5F                        ; $5167  96 bytes
build_pose_merge:
        LDA ($06),Y                     ; $5169  its picture
        ORA $CAE0,Y                     ; $516B  with the odd library's
        STA ($06),Y                     ; $516E  merged
        DEY                             ; $5170  the next
        BPL build_pose_merge            ; $5171  more
        DEX                             ; $5173  the library below
        CPX #$FF                        ; $5174  past 0?
        BEQ build_sprites_done          ; $5176  yes: done
        JMP build_pose_loop             ; $5178  the next pair
build_sprites_done:
        RTS                             ; $517B  back
        RTS                             ; $517C  two RTS that nothing reaches
        RTS                             ; $517D  the second
; One library into a hardware sprite. $1D is the height byte plus one.
; $5CBF zero reads one source byte per row. widen_bits turns four source
; bits into one sprite byte, each set bit the pair $C0, so one byte fills
; the two left columns and the third column is cleared. A nonzero $5CBF
; reads two source bytes per row: the first fills those two columns, and
; the high nibble of the second fills the right column. The pointer is
; bumped once inside the row, and Y once, so the next row starts two source
; bytes on. Rows from there through $20 are cleared.
expand_library:
        LDA $59BD,X                     ; $517E  the picture, low
        STA $04                         ; $5181  pointer
        LDA $5A8F,X                     ; $5183  high
        STA $05                         ; $5186  pointer
        LDY $5B61,X                     ; $5188  its height
        INY                             ; $518B  plus one
        STY $1D                         ; $518C  the row count
        LDA $1239,X                     ; $518E  its scan page, high
        STA $07                         ; $5191  the first column
        LDA $1167,X                     ; $5193  low
        STA $06                         ; $5196  the first column
        CLC                             ; $5198  carry clear
        ADC #$20                        ; $5199  32 bytes on
        STA $08                         ; $519B  the second column, low
        LDA $07                         ; $519D  high
        ADC #$00                        ; $519F  the carry
        STA $09                         ; $51A1  the second column, high
        LDA $06                         ; $51A3  the first column, low
        CLC                             ; $51A5  carry clear
        ADC #$40                        ; $51A6  64 bytes on
        STA $0A                         ; $51A8  the third column, low
        LDA $07                         ; $51AA  high
        ADC #$00                        ; $51AC  the carry
        STA $0B                         ; $51AE  the third column, high
        LDY #$00                        ; $51B0  row 0
        LDA $5CBF,X                     ; $51B2  one byte a row?
        BNE expand_wide_row             ; $51B5  no: two
expand_narrow_row:
        LDA ($04),Y                     ; $51B7  a source byte
        STA $1F                         ; $51B9  kept for widen_bits
        JSR widen_bits                  ; $51BB  the low nibble, widened
        STA ($08),Y                     ; $51BE  the second column
        JSR widen_bits                  ; $51C0  the high nibble, widened
        STA ($06),Y                     ; $51C3  the first column
        LDA #$00                        ; $51C5  blank
        STA ($0A),Y                     ; $51C7  the third column
        INY                             ; $51C9  the next row
        CPY $1D                         ; $51CA  the last row?
        BCC expand_narrow_row           ; $51CC  no
expand_clear_rows:
        STA ($06),Y                     ; $51CE  the first column
        STA ($08),Y                     ; $51D0  the second
        STA ($0A),Y                     ; $51D2  the third, blank
        INY                             ; $51D4  the next row
        CPY #$20                        ; $51D5  32 rows?
        BCC expand_clear_rows           ; $51D7  no
        RTS                             ; $51D9  back
expand_wide_row:
        LDA ($04),Y                     ; $51DA  the first source byte
        STA $1F                         ; $51DC  kept for widen_bits
        JSR widen_bits                  ; $51DE  the low nibble, widened
        STA ($08),Y                     ; $51E1  the second column
        JSR widen_bits                  ; $51E3  the high nibble, widened
        STA ($06),Y                     ; $51E6  the first column
        JSR step_ptr_04                 ; $51E8  the second source byte
        LDA ($04),Y                     ; $51EB  read
        LSR A                           ; $51ED  shifted down
        LSR A                           ; $51EE  shifted down
        LSR A                           ; $51EF  its high nibble
        LSR A                           ; $51F0  shifted down
        JSR widen_bits                  ; $51F1  widened
        STA ($0A),Y                     ; $51F4  the third column
        INY                             ; $51F6  the next row, which also steps the source
        CPY $1D                         ; $51F7  the last row?
        BCC expand_wide_row             ; $51F9  no
        LDA #$00                        ; $51FB  blank
        BEQ expand_clear_rows           ; $51FD  always
; Spread the low four bits of $1F into a byte, two bits each, so a
; packed collision nibble covers a multicolor pixel pair. A starts at 0,
; so whatever the caller had in A is lost.
widen_bits:
        LDX #$03                        ; $51FF  four bits
        LDA #$00                        ; $5201  empty
widen_loop:
        LSR $1F                         ; $5203  the next bit
        BCC widen_next                  ; $5205  clear
        ORA #$C0                        ; $5207  the pair set, at the top
widen_next:
        DEX                             ; $5209  one fewer
        BMI widen_done                  ; $520A  done
        LSR A                           ; $520C  shifted down
        LSR A                           ; $520D  down one pair
        JMP widen_loop                  ; $520E  the next bit
widen_done:
        RTS                             ; $5211  back


; For each active actor, place his box over the room and scan it. xpos and ypos are
; converted to a character-cell cursor. scan_row is called once per row of the box.
overlap_actors:
        LDX #$02                        ; $5212  the ninja first
overlap_loop:
        STX $50                         ; $5214  the actor
        LDA active,X                    ; $5216  active
        AND #$01                        ; $5218  in the room?
        BNE overlap_actor               ; $521A  yes
        JMP overlap_next                ; $521C  no: the next
overlap_actor:
        LDA xpos,X                      ; $521F  xpos
        SEC                             ; $5221  the borrow
        SBC #$0C                        ; $5222  the box's left edge
        STA $E6,X                       ; $5224  kept
        AND #$03                        ; $5226  steps into the cell, two pixels each
        STA $1B                         ; $5228  the sub-cell offset
        LDA ypos,X                      ; $522A  ypos
        SEC                             ; $522C  the borrow
        SBC #$1D                        ; $522D  the box's top
        STA $E9,X                       ; $522F  kept
        AND #$07                        ; $5231  rows into the cell
        STA $1C                         ; $5233  the rows above the figure
        LDA $4F4E,X                     ; $5235  the actor's library
        TAX                             ; $5238  the index
        LDA $1167,X                     ; $5239  its scan picture, low
        STA $52CC                       ; $523C  into mask_copy_loop's operand
        LDA $1239,X                     ; $523F  its scan picture, high
        STA $52CD                       ; $5242  into mask_copy_loop's operand, high
        JSR build_actor_mask            ; $5245  the mask at $CAE0
        LDA $1C                         ; $5248  rows above the figure
        CLC                             ; $524A  carry clear
        ADC #$15                        ; $524B  and 21 of figure
        STA $4F39                       ; $524D  the last mask row
        SEC                             ; $5250  the borrow
        SBC #$06                        ; $5251  less 6
        STA $4F38                       ; $5253  the row where the upper body ends
        JSR clear_overlap_tables        ; $5256  nothing marked yet
        LDX $50                         ; $5259  the actor
        LDA $E6,X                       ; $525B  the box's left edge
        LSR A                           ; $525D  halved
        LSR A                           ; $525E  four steps a cell
        STA $E6,X                       ; $525F  the cell column
        LDA $E9,X                       ; $5261  the box's top
        LSR A                           ; $5263  halved
        LSR A                           ; $5264  quartered
        LSR A                           ; $5265  eight rows a cell
        STA $E9,X                       ; $5266  the cell row
        LDY #$00                        ; $5268  0
        STY $52                         ; $526A  mask row 0
        LDA #$08                        ; $526C  8
        STA $4F3A                       ; $526E  the first cell row ends at mask row 8
        JSR load_row_cells              ; $5271  its three glyphs
        JSR scan_row                    ; $5274  scan them
        LDX $50                         ; $5277  the actor
        INC $E9,X                       ; $5279  the next cell row
        LDA #$10                        ; $527B  16
        STA $4F3A                       ; $527D  ends at mask row 16
        JSR load_row_cells              ; $5280  its three glyphs
        JSR scan_row                    ; $5283  scan them
        LDX $50                         ; $5286  the actor
        INC $E9,X                       ; $5288  the next cell row
        LDA #$18                        ; $528A  24
        STA $4F3A                       ; $528C  ends at mask row 24
        JSR load_row_cells              ; $528F  its three glyphs
        JSR scan_row                    ; $5292  scan them
        LDX $50                         ; $5295  the actor
        INC $E9,X                       ; $5297  the next cell row
        LDA #$20                        ; $5299  32
        STA $4F3A                       ; $529B  ends at mask row 32
        JSR load_row_cells              ; $529E  its three glyphs
        JSR scan_row                    ; $52A1  scan them
overlap_next:
        LDX $50                         ; $52A4  the actor
        DEX                             ; $52A6  the next one
        BMI overlap_done                ; $52A7  all three done
        JMP overlap_loop                ; $52A9  more
overlap_done:
        RTS                             ; $52AC  back
; Build the actor's collision mask at $CAE0: zero rows above, then the
; 96 bytes of the pose's scan picture, then shift the three columns right
; by the actor's sub-cell offset ($1B times two), or left by two for an
; offset of 3. overlap_actors patches the $9060 operand of mask_copy_loop
; with that picture's address.
build_actor_mask:
        LDA #$00                        ; $52AD  zero
        TAY                             ; $52AF  row 0
mask_clear_top:
        CPY $1C                         ; $52B0  rows above the figure?
        BEQ mask_offset_test            ; $52B2  done
        STA $CAE0,Y                     ; $52B4  zero
        INY                             ; $52B7  the next row
        BNE mask_clear_top              ; $52B8  always
mask_offset_test:
        LDX $1B                         ; $52BA  the sub-cell offset
        CPX #$03                        ; $52BC  3?
        BNE mask_copy                   ; $52BE  no
        LDX #$1F                        ; $52C0  32 more
mask_clear_extra:
        STA $CAE0,Y                     ; $52C2  so the picture starts one column later
        INY                             ; $52C5  the next row
        DEX                             ; $52C6  one fewer
        BPL mask_clear_extra            ; $52C7  more
mask_copy:
        LDX #$00                        ; $52C9  from the picture's first byte
mask_copy_loop:
        LDA $9060,X                     ; $52CB  the scan picture. The operand is patched
        STA $CAE0,Y                     ; $52CE  into the mask
        INY                             ; $52D1  the next mask byte
        INX                             ; $52D2  the next picture byte
        CPX #$60                        ; $52D3  96 bytes, three columns of 32
        BCC mask_copy_loop              ; $52D5  no
        LDA $1B                         ; $52D7  the sub-cell offset
        BEQ mask_done                   ; $52D9  0: done
        CMP #$03                        ; $52DB  3?
        BEQ mask_shift_left             ; $52DD  yes: two bits left
        ASL A                           ; $52DF  two bits a step
        TAY                             ; $52E0  bits to shift
mask_shift_right:
        LDX #$1F                        ; $52E1  32 rows
mask_shift_right_row:
        LSR $CAE0,X                     ; $52E3  column 0 right one bit
        ROR $CB00,X                     ; $52E6  into column 1
        ROR $CB20,X                     ; $52E9  into column 2
        DEX                             ; $52EC  the next row
        BPL mask_shift_right_row        ; $52ED  more
        DEY                             ; $52EF  the next bit
        BNE mask_shift_right            ; $52F0  more bits
mask_done:
        RTS                             ; $52F2  back
mask_shift_left:
        LDY #$02                        ; $52F3  two bits
mask_shift_left_pass:
        LDX #$1F                        ; $52F5  32 rows
mask_shift_left_row:
        ASL $CB40,X                     ; $52F7  from the fourth column
        ROL $CB20,X                     ; $52FA  into column 2
        ROL $CB00,X                     ; $52FD  into column 1
        ROL $CAE0,X                     ; $5300  into column 0
        DEX                             ; $5303  the next row
        BPL mask_shift_left_row         ; $5304  more
        DEY                             ; $5306  one bit done
        BNE mask_shift_left_pass        ; $5307  the second
        RTS                             ; $5309  back
; One character row of the overlap scan. Point at the row, then look up
; the three cells under the actor and turn each glyph number into its
; address in the charset, eight bytes a glyph, for scan_row's operands.
load_row_cells:
        LDX $50                         ; $530A  the actor
        LDA $E9,X                       ; $530C  the cell row
        TAX                             ; $530E  for point_scan_row
        JSR point_scan_row              ; $530F  ($04) screen and ($12) color RAM
        LDX $50                         ; $5312  the actor
        LDY $E6,X                       ; $5314  the cell column
        JSR check_column0               ; $5316  swap column 0's slots if the cell is a ladder
        LDA ($04),Y                     ; $5319  the glyph
        STA $43BC                       ; $531B  kept for the scale
        JSR scale_by_eight              ; $531E  times 8, high byte in $43BB
        LDA $43BC                       ; $5321  the offset, low
        SEC                             ; $5324  the borrow
        SBC $52                         ; $5325  less the mask row, so Y reads glyph rows 0-7
        STA $5381                       ; $5327  scan_row's operand, column 0
        LDA $43BB                       ; $532A  high
        SBC #$00                        ; $532D  the borrow
        CLC                             ; $532F  carry clear
        ADC $7C                         ; $5330  the charset page
        STA $5382                       ; $5332  scan_row's operand
        INY                             ; $5335  the next cell
        JSR check_column1               ; $5336  swap column 1's slots if the cell is a ladder
        LDA ($04),Y                     ; $5339  the glyph
        STA $43BC                       ; $533B  kept for the scale
        JSR scale_by_eight              ; $533E  times 8
        LDA $43BC                       ; $5341  the offset, low
        SEC                             ; $5344  the borrow
        SBC $52                         ; $5345  less the mask row
        STA $539B                       ; $5347  scan_row's operand, column 1
        LDA $43BB                       ; $534A  high
        SBC #$00                        ; $534D  the borrow
        CLC                             ; $534F  carry clear
        ADC $7C                         ; $5350  the charset page
        STA $539C                       ; $5352  scan_row's operand
        INY                             ; $5355  the next cell
        CPY #$28                        ; $5356  past column 39?
        BCC load_third_cell             ; $5358  no
        LDA #$00                        ; $535A  glyph 0, and column 2's swap is left as it was
        BEQ load_third_store            ; $535C  always
load_third_cell:
        JSR check_column2               ; $535E  swap column 2's slots if the cell is a ladder
        LDA ($04),Y                     ; $5361  the glyph
load_third_store:
        STA $43BC                       ; $5363  kept for the scale
        JSR scale_by_eight              ; $5366  times 8
        LDA $43BC                       ; $5369  the offset, low
        SEC                             ; $536C  the borrow
        SBC $52                         ; $536D  less the mask row
        STA $53B5                       ; $536F  scan_row's operand, column 2
        LDA $43BB                       ; $5372  high
        SBC #$00                        ; $5375  the borrow
        CLC                             ; $5377  carry clear
        ADC $7C                         ; $5378  the charset page
        STA $53B6                       ; $537A  scan_row's operand
        RTS                             ; $537D  back

; One row of the overlap test. The sprite row is ANDed with the room row under it. Each
; half of that byte is a 4-bit pattern, and the slot for that pattern is marked.
; The slot is the AND result. One bit of a $F nibble marks slot 1, 2, 4, or 8,
; and slots 1 and 4 are ground. Tile $32, the left wall, is $F3 $CF on every
; row of both halves. On an even screen X the overlap stays 3, 12, or 15. One
; pixel to the side it becomes 1, and the column reads as ground from top to
; bottom.
scan_row:
        LDY $52                         ; $537E  the mask row
scan_row_loop:
        LDA $A470,Y                     ; $5380  the glyph row. The operand is patched
        AND $CAE0,Y                     ; $5383  ANDed with the mask's column 0
        BEQ scan_second_column          ; $5386  nothing under it
        STA $4E                         ; $5388  kept
        LSR A                           ; $538A  shifted down
        LSR A                           ; $538B  shifted down
        LSR A                           ; $538C  shifted down
        LSR A                           ; $538D  the high nibble
        TAX                             ; $538E  the slot
        STA $4EED,X                     ; $538F  mark its slot. Any nonzero value marks
        LDA $4E                         ; $5392  the AND again
        AND #$0F                        ; $5394  the low nibble
        TAX                             ; $5396  the slot
        STA $4EED,X                     ; $5397  mark its slot
scan_second_column:
        LDA $A470,Y                     ; $539A  the glyph row
        AND $CB00,Y                     ; $539D  ANDed with the mask's column 1
        BEQ scan_third_column           ; $53A0  nothing under it
        STA $4E                         ; $53A2  kept
        LSR A                           ; $53A4  shifted down
        LSR A                           ; $53A5  shifted down
        LSR A                           ; $53A6  shifted down
        LSR A                           ; $53A7  the high nibble
        TAX                             ; $53A8  the slot
        STA $4F04,X                     ; $53A9  mark its slot
        LDA $4E                         ; $53AC  the AND again
        AND #$0F                        ; $53AE  the low nibble
        TAX                             ; $53B0  the slot
        STA $4F04,X                     ; $53B1  mark its slot
scan_third_column:
        LDA $A470,Y                     ; $53B4  the glyph row
        AND $CB20,Y                     ; $53B7  ANDed with the mask's column 2
        BEQ scan_row_next               ; $53BA  nothing under it
        STA $4E                         ; $53BC  kept
        LSR A                           ; $53BE  shifted down
        LSR A                           ; $53BF  shifted down
        LSR A                           ; $53C0  shifted down
        LSR A                           ; $53C1  the high nibble
        TAX                             ; $53C2  the slot
        STA $4F1B,X                     ; $53C3  mark its slot
        LDA $4E                         ; $53C6  the AND again
        AND #$0F                        ; $53C8  the low nibble
        TAX                             ; $53CA  the slot
        STA $4F1B,X                     ; $53CB  mark its slot
scan_row_next:
        INY                             ; $53CE  the next mask row
        CPY $4F38                       ; $53CF  the upper body's last row?
        BEQ scan_upper_body             ; $53D2  yes: take its flags
scan_row_test_end:
        CPY $4F39                       ; $53D4  the figure's last row?
        BEQ scan_row_last               ; $53D7  yes: the full flags
        CPY $4F3A                       ; $53D9  the end of this cell row?
        BEQ scan_row_done               ; $53DC  yes
        JMP scan_row_loop               ; $53DE  no: the next row
scan_row_done:
        STY $52                         ; $53E1  the mask row the next cell row starts on
        RTS                             ; $53E3  back
scan_upper_body:
        LDX #$02                        ; $53E4  three columns
scan_save_swaps:
        LDA $4F32,X                     ; $53E6  the swap state
        STA $4F35,X                     ; $53E9  kept
        DEX                             ; $53EC  the next
        BPL scan_save_swaps             ; $53ED  more
        JSR flags_from_nibbles          ; $53EF  the flags so far. They swap back first
        LDA hit,X                       ; $53F2  X is the actor again
        STA $A7,X                       ; $53F4  the upper body's hit
        LDA $4F32                       ; $53F6  column 0's swap state now
        CMP $4F35                       ; $53F9  the same as before?
        BEQ scan_restore_column1        ; $53FC  yes
        EOR #$01                        ; $53FE  no: flip it back
        STA $4F32                       ; $5400  kept
        JSR swap_column0                ; $5403  and swap again
scan_restore_column1:
        LDA $4F33                       ; $5406  column 1's swap state now
        CMP $4F36                       ; $5409  the same as before?
        BEQ scan_restore_column2        ; $540C  yes
        EOR #$01                        ; $540E  no: flip it back
        STA $4F33                       ; $5410  kept
        JSR swap_column1                ; $5413  and swap again
scan_restore_column2:
        LDA $4F34                       ; $5416  column 2's swap state now
        CMP $4F37                       ; $5419  the same as before?
        BEQ scan_row_test_end           ; $541C  yes
        EOR #$01                        ; $541E  no: flip it back
        STA $4F34                       ; $5420  kept
        JSR swap_column2                ; $5423  and swap again
        JMP scan_row_test_end           ; $5426  then the end tests
scan_row_last:
        JSR flags_from_nibbles          ; $5429  the full hit
        PLA                             ; $542C  drop the return
        PLA                             ; $542D  into overlap_actors
        JMP overlap_next                ; $542E  the next actor

; Turn the marked patterns into flags. A set slot means that nibble occurred
; in the AND result. A glyph nibble of $F is not itself slot $F once the
; sprite covers only part of it.
; Each column has 23 slots: nibbles 0-$F, then $10-$16 for nibbles 3, 7,
; B, C, D, E, and F seen on a ladder cell. The slot names are on the lines.
; $4F3C rolls in as bit 0, ground: nibbles 1, 4, 5, 6, 7, 9, and 13, plain
; or on a ladder. The ORs read column 0's ladder 7 twice and never column
; 1's, $4F15, so a 7 in the middle column of a ladder cell is not ground.
; $4F3D rolls in as bit 1, prize ink: nibbles 2, 6, 8, 9, 10, 11, and 14.
; $4F3E rolls in as bit 2 and $4F3F as bit 3. Bit 3 is the wall, nibbles
; 3, 7, and 11-15. swap_column0, swap_column1, and swap_column2 run when
; that column's property is not 0, and they exchange the wall slots with
; the ladder slots, so those nibbles become bit 2.
flags_from_nibbles:
        LDA #$00                        ; $5431  zero
        LDX #$04                        ; $5433  five counters
flags_clear:
        STA $4F3B,X                     ; $5435  $4F3B-$4F3F
        DEX                             ; $5438  the next
        BPL flags_clear                 ; $5439  more
        LDA $4F32                       ; $543B  column 0 swapped?
        BEQ flags_unswap_column1        ; $543E  no
        DEC $4F32                       ; $5440  not now
        JSR swap_column0                ; $5443  swap back. The ladder marks move to slots $10-$16
flags_unswap_column1:
        LDA $4F33                       ; $5446  column 1 swapped?
        BEQ flags_unswap_column2        ; $5449  no
        DEC $4F33                       ; $544B  not now
        JSR swap_column1                ; $544E  swap back
flags_unswap_column2:
        LDA $4F34                       ; $5451  column 2 swapped?
        BEQ flags_ground                ; $5454  no
        DEC $4F34                       ; $5456  not now
        JSR swap_column2                ; $5459  swap back
flags_ground:
        LDA $4EEE                       ; $545C  column 0, nibble 1
        ORA $4EF1                       ; $545F  column 0, nibble 4
        ORA $4EF2                       ; $5462  column 0, nibble 5
        ORA $4EF3                       ; $5465  column 0, nibble 6
        ORA $4EF4                       ; $5468  column 0, nibble 7
        ORA $4EFE                       ; $546B  column 0, nibble 7 on a ladder
        ORA $4EF6                       ; $546E  column 0, nibble 9
        ORA $4EFA                       ; $5471  column 0, nibble D
        ORA $4F01                       ; $5474  column 0, nibble D on a ladder
        ORA $4F05                       ; $5477  column 1, nibble 1
        ORA $4F08                       ; $547A  column 1, nibble 4
        ORA $4F09                       ; $547D  column 1, nibble 5
        ORA $4F0A                       ; $5480  column 1, nibble 6
        ORA $4F0B                       ; $5483  column 1, nibble 7
        ORA $4EFE                       ; $5486  column 0's ladder 7 again. Column 1's, $4F15, is left out
        ORA $4F0D                       ; $5489  column 1, nibble 9
        ORA $4F11                       ; $548C  column 1, nibble D
        ORA $4F18                       ; $548F  column 1, nibble D on a ladder
        ORA $4F1C                       ; $5492  column 2, nibble 1
        ORA $4F1F                       ; $5495  column 2, nibble 4
        ORA $4F20                       ; $5498  column 2, nibble 5
        ORA $4F21                       ; $549B  column 2, nibble 6
        ORA $4F22                       ; $549E  column 2, nibble 7
        ORA $4F2C                       ; $54A1  column 2, nibble 7 on a ladder
        ORA $4F24                       ; $54A4  column 2, nibble 9
        ORA $4F28                       ; $54A7  column 2, nibble D
        ORA $4F2F                       ; $54AA  column 2, nibble D on a ladder
        BEQ flags_prize                 ; $54AD  no ground
        INC $4F3C                       ; $54AF  ground
flags_prize:
        LDA $4EEF                       ; $54B2  column 0, nibble 2
        ORA $4EF3                       ; $54B5  column 0, nibble 6
        ORA $4EF5                       ; $54B8  column 0, nibble 8
        ORA $4EF6                       ; $54BB  column 0, nibble 9
        ORA $4EF7                       ; $54BE  column 0, nibble A
        ORA $4EF8                       ; $54C1  column 0, nibble B
        ORA $4EFB                       ; $54C4  column 0, nibble E
        ORA $4EFF                       ; $54C7  column 0, nibble B on a ladder
        ORA $4F02                       ; $54CA  column 0, nibble E on a ladder
        ORA $4F06                       ; $54CD  column 1, nibble 2
        ORA $4F0A                       ; $54D0  column 1, nibble 6
        ORA $4F0C                       ; $54D3  column 1, nibble 8
        ORA $4F0D                       ; $54D6  column 1, nibble 9
        ORA $4F0E                       ; $54D9  column 1, nibble A
        ORA $4F0F                       ; $54DC  column 1, nibble B
        ORA $4F12                       ; $54DF  column 1, nibble E
        ORA $4F16                       ; $54E2  column 1, nibble B on a ladder
        ORA $4F19                       ; $54E5  column 1, nibble E on a ladder
        ORA $4F1D                       ; $54E8  column 2, nibble 2
        ORA $4F21                       ; $54EB  column 2, nibble 6
        ORA $4F23                       ; $54EE  column 2, nibble 8
        ORA $4F24                       ; $54F1  column 2, nibble 9
        ORA $4F25                       ; $54F4  column 2, nibble A
        ORA $4F26                       ; $54F7  column 2, nibble B
        ORA $4F29                       ; $54FA  column 2, nibble E
        ORA $4F2D                       ; $54FD  column 2, nibble B on a ladder
        ORA $4F30                       ; $5500  column 2, nibble E on a ladder
        BEQ flags_ladder                ; $5503  no prize ink
        INC $4F3D                       ; $5505  prize ink
flags_ladder:
        LDA $4EFD                       ; $5508  column 0, nibble 3 on a ladder
        ORA $4EFE                       ; $550B  column 0, nibble 7 on a ladder
        ORA $4EFF                       ; $550E  column 0, nibble B on a ladder
        ORA $4F00                       ; $5511  column 0, nibble C on a ladder
        ORA $4F01                       ; $5514  column 0, nibble D on a ladder
        ORA $4F02                       ; $5517  column 0, nibble E on a ladder
        ORA $4F03                       ; $551A  column 0, nibble F on a ladder
        ORA $4F14                       ; $551D  column 1, nibble 3 on a ladder
        ORA $4F15                       ; $5520  column 1, nibble 7 on a ladder
        ORA $4F16                       ; $5523  column 1, nibble B on a ladder
        ORA $4F17                       ; $5526  column 1, nibble C on a ladder
        ORA $4F18                       ; $5529  column 1, nibble D on a ladder
        ORA $4F19                       ; $552C  column 1, nibble E on a ladder
        ORA $4F1A                       ; $552F  column 1, nibble F on a ladder
        ORA $4F2B                       ; $5532  column 2, nibble 3 on a ladder
        ORA $4F2C                       ; $5535  column 2, nibble 7 on a ladder
        ORA $4F2D                       ; $5538  column 2, nibble B on a ladder
        ORA $4F2E                       ; $553B  column 2, nibble C on a ladder
        ORA $4F2F                       ; $553E  column 2, nibble D on a ladder
        ORA $4F30                       ; $5541  column 2, nibble E on a ladder
        ORA $4F31                       ; $5544  column 2, nibble F on a ladder
        BEQ flags_wall                  ; $5547  no ladder
        INC $4F3E                       ; $5549  ladder
flags_wall:
        LDA $4EF0                       ; $554C  column 0, nibble 3
        ORA $4EF4                       ; $554F  column 0, nibble 7
        ORA $4EF8                       ; $5552  column 0, nibble B
        ORA $4EF9                       ; $5555  column 0, nibble C
        ORA $4EFA                       ; $5558  column 0, nibble D
        ORA $4EFB                       ; $555B  column 0, nibble E
        ORA $4EFC                       ; $555E  column 0, nibble F
        ORA $4F07                       ; $5561  column 1, nibble 3
        ORA $4F0B                       ; $5564  column 1, nibble 7
        ORA $4F0F                       ; $5567  column 1, nibble B
        ORA $4F10                       ; $556A  column 1, nibble C
        ORA $4F11                       ; $556D  column 1, nibble D
        ORA $4F12                       ; $5570  column 1, nibble E
        ORA $4F13                       ; $5573  column 1, nibble F
        ORA $4F1E                       ; $5576  column 2, nibble 3
        ORA $4F22                       ; $5579  column 2, nibble 7
        ORA $4F26                       ; $557C  column 2, nibble B
        ORA $4F27                       ; $557F  column 2, nibble C
        ORA $4F28                       ; $5582  column 2, nibble D
        ORA $4F29                       ; $5585  column 2, nibble E
        ORA $4F2A                       ; $5588  column 2, nibble F
        BEQ flags_store                 ; $558B  no wall
        INC $4F3F                       ; $558D  wall
flags_store:
        LDX $50                         ; $5590  the actor
        LDA #$00                        ; $5592  zero
        STA hit,X                       ; $5594  cleared
        LSR $4F3F                       ; $5596  the wall count
        ROL hit,X                       ; $5599  bit 3, after three more shifts
        LSR $4F3E                       ; $559B  the ladder count
        ROL hit,X                       ; $559E  bit 2
        LSR $4F3D                       ; $55A0  the prize count
        ROL hit,X                       ; $55A3  bit 1
        LSR $4F3C                       ; $55A5  the ground count
        ROL hit,X                       ; $55A8  bit 0
        RTS                             ; $55AA  back
; Zero the 23-byte nibble tables at $4EED, $4F04, and $4F1B and the three
; column swap flags at $4F32-$4F34.
clear_overlap_tables:
        LDA #$00                        ; $55AB  zero
        LDX #$16                        ; $55AD  23 slots
clear_overlap_loop:
        STA $4EED,X                     ; $55AF  column 0
        STA $4F04,X                     ; $55B2  column 1
        STA $4F1B,X                     ; $55B5  column 2
        DEX                             ; $55B8  the next
        BPL clear_overlap_loop          ; $55B9  more
        STA $4F32                       ; $55BB  column 0 not swapped
        STA $4F33                       ; $55BE  column 1 not swapped
        STA $4F34                       ; $55C1  column 2 not swapped
        RTS                             ; $55C4  back
; X is a character row. ($04) is that row of the screen and ($12) the
; same row of color RAM, from the tables at $50E7, $50FF, and $5117. A
; row past 23 reads on into the next table.
point_scan_row:
        LDA $50E7,X                     ; $55C5  screen row, low
        STA $04                         ; $55C8  and color RAM row, low
        STA $12                         ; $55CA  the same low byte
        LDA $50FF,X                     ; $55CC  screen row, high
        STA $05                         ; $55CF  high
        LDA $5117,X                     ; $55D1  color RAM row, high
        STA $13                         ; $55D4  high
        RTS                             ; $55D6  back
; The first column's cell property, the low three bits of its color
; byte. When it is not 0 the cell is a ladder, and the column's wall and
; ladder slots trade places once (swap_column0). When it is 0 and the
; slots were traded, they trade back.
check_column0:
        LDA ($12),Y                     ; $55D7  the color byte under column 0
        AND #$07                        ; $55D9  the cell property
        BEQ check_column0_plain         ; $55DB  0: unswap if swapped
        LDA $4F32                       ; $55DD  swapped already?
        BEQ check_column0_swap          ; $55E0  no: swap
        RTS                             ; $55E2  yes: keep
check_column0_swap:
        INC $4F32                       ; $55E3  swapped
; This column's property is not 0. Trade its wall nibble slots for its
; ladder slots, so bit 3 becomes bit 2. The other two columns are
; swap_column1 and swap_column2.
swap_column0:
        LDA $4EF0                       ; $55E6  column 0, nibble 3
        LDX $4EFD                       ; $55E9  column 0, nibble 3 on a ladder
        STX $4EF0                       ; $55EC  the ladder marks into the plain slot
        STA $4EFD                       ; $55EF  the plain marks into the ladder slot
        LDA $4EF4                       ; $55F2  column 0, nibble 7
        LDX $4EFE                       ; $55F5  column 0, nibble 7 on a ladder
        STX $4EF4                       ; $55F8  the ladder marks into the plain slot
        STA $4EFE                       ; $55FB  the plain marks into the ladder slot
        LDA $4EF8                       ; $55FE  column 0, nibble B
        LDX $4EFF                       ; $5601  column 0, nibble B on a ladder
        STX $4EF8                       ; $5604  the ladder marks into the plain slot
        STA $4EFF                       ; $5607  the plain marks into the ladder slot
        LDA $4EF9                       ; $560A  column 0, nibble C
        LDX $4F00                       ; $560D  column 0, nibble C on a ladder
        STX $4EF9                       ; $5610  the ladder marks into the plain slot
        STA $4F00                       ; $5613  the plain marks into the ladder slot
        LDA $4EFA                       ; $5616  column 0, nibble D
        LDX $4F01                       ; $5619  column 0, nibble D on a ladder
        STX $4EFA                       ; $561C  the ladder marks into the plain slot
        STA $4F01                       ; $561F  the plain marks into the ladder slot
        LDA $4EFB                       ; $5622  column 0, nibble E
        LDX $4F02                       ; $5625  column 0, nibble E on a ladder
        STX $4EFB                       ; $5628  the ladder marks into the plain slot
        STA $4F02                       ; $562B  the plain marks into the ladder slot
        LDA $4EFC                       ; $562E  column 0, nibble F
        LDX $4F03                       ; $5631  column 0, nibble F on a ladder
        STX $4EFC                       ; $5634  the ladder marks into the plain slot
        STA $4F03                       ; $5637  the plain marks into the ladder slot
        LDX $50                         ; $563A  the actor again
        RTS                             ; $563C  back
check_column0_plain:
        LDA $4F32                       ; $563D  swapped?
        BNE check_column0_unswap        ; $5640  yes: swap back
        RTS                             ; $5642  back
check_column0_unswap:
        DEC $4F32                       ; $5643  not swapped
        JMP swap_column0                ; $5646  swap back
; The same as check_column0 for the second column.
check_column1:
        LDA ($12),Y                     ; $5649  the color byte under column 1
        AND #$07                        ; $564B  the cell property
        BEQ check_column1_plain         ; $564D  0: unswap if swapped
        LDA $4F33                       ; $564F  swapped already?
        BEQ check_column1_swap          ; $5652  no: swap
        RTS                             ; $5654  yes: keep
check_column1_swap:
        INC $4F33                       ; $5655  swapped
; Trade the second column's wall and ladder slots: $4F07, $4F0B, and
; $4F0F-$4F13 with $4F14-$4F1A. check_column1 and flags_from_nibbles call
; this, and calling it again trades them back.
swap_column1:
        LDA $4F07                       ; $5658  column 1, nibble 3
        LDX $4F14                       ; $565B  column 1, nibble 3 on a ladder
        STX $4F07                       ; $565E  the ladder marks into the plain slot
        STA $4F14                       ; $5661  the plain marks into the ladder slot
        LDA $4F0B                       ; $5664  column 1, nibble 7
        LDX $4F15                       ; $5667  column 1, nibble 7 on a ladder
        STX $4F0B                       ; $566A  the ladder marks into the plain slot
        STA $4F15                       ; $566D  the plain marks into the ladder slot
        LDA $4F0F                       ; $5670  column 1, nibble B
        LDX $4F16                       ; $5673  column 1, nibble B on a ladder
        STX $4F0F                       ; $5676  the ladder marks into the plain slot
        STA $4F16                       ; $5679  the plain marks into the ladder slot
        LDA $4F10                       ; $567C  column 1, nibble C
        LDX $4F17                       ; $567F  column 1, nibble C on a ladder
        STX $4F10                       ; $5682  the ladder marks into the plain slot
        STA $4F17                       ; $5685  the plain marks into the ladder slot
        LDA $4F11                       ; $5688  column 1, nibble D
        LDX $4F18                       ; $568B  column 1, nibble D on a ladder
        STX $4F11                       ; $568E  the ladder marks into the plain slot
        STA $4F18                       ; $5691  the plain marks into the ladder slot
        LDA $4F12                       ; $5694  column 1, nibble E
        LDX $4F19                       ; $5697  column 1, nibble E on a ladder
        STX $4F12                       ; $569A  the ladder marks into the plain slot
        STA $4F19                       ; $569D  the plain marks into the ladder slot
        LDA $4F13                       ; $56A0  column 1, nibble F
        LDX $4F1A                       ; $56A3  column 1, nibble F on a ladder
        STX $4F13                       ; $56A6  the ladder marks into the plain slot
        STA $4F1A                       ; $56A9  the plain marks into the ladder slot
        LDX $50                         ; $56AC  the actor again
        RTS                             ; $56AE  back
check_column1_plain:
        LDA $4F33                       ; $56AF  swapped?
        BNE check_column1_unswap        ; $56B2  yes: swap back
        RTS                             ; $56B4  back
check_column1_unswap:
        DEC $4F33                       ; $56B5  not swapped
        JMP swap_column1                ; $56B8  swap back
; The same as check_column0 for the third column.
check_column2:
        LDA ($12),Y                     ; $56BB  the color byte under column 2
        AND #$07                        ; $56BD  the cell property
        BEQ check_column2_plain         ; $56BF  0: unswap if swapped
        LDA $4F34                       ; $56C1  swapped already?
        BEQ check_column2_swap          ; $56C4  no: swap
        RTS                             ; $56C6  yes: keep
check_column2_swap:
        INC $4F34                       ; $56C7  swapped
; The same for the third column: $4F1E, $4F22, and $4F26-$4F2A with
; $4F2B-$4F31.
swap_column2:
        LDA $4F1E                       ; $56CA  column 2, nibble 3
        LDX $4F2B                       ; $56CD  column 2, nibble 3 on a ladder
        STX $4F1E                       ; $56D0  the ladder marks into the plain slot
        STA $4F2B                       ; $56D3  the plain marks into the ladder slot
        LDA $4F22                       ; $56D6  column 2, nibble 7
        LDX $4F2C                       ; $56D9  column 2, nibble 7 on a ladder
        STX $4F22                       ; $56DC  the ladder marks into the plain slot
        STA $4F2C                       ; $56DF  the plain marks into the ladder slot
        LDA $4F26                       ; $56E2  column 2, nibble B
        LDX $4F2D                       ; $56E5  column 2, nibble B on a ladder
        STX $4F26                       ; $56E8  the ladder marks into the plain slot
        STA $4F2D                       ; $56EB  the plain marks into the ladder slot
        LDA $4F27                       ; $56EE  column 2, nibble C
        LDX $4F2E                       ; $56F1  column 2, nibble C on a ladder
        STX $4F27                       ; $56F4  the ladder marks into the plain slot
        STA $4F2E                       ; $56F7  the plain marks into the ladder slot
        LDA $4F28                       ; $56FA  column 2, nibble D
        LDX $4F2F                       ; $56FD  column 2, nibble D on a ladder
        STX $4F28                       ; $5700  the ladder marks into the plain slot
        STA $4F2F                       ; $5703  the plain marks into the ladder slot
        LDA $4F29                       ; $5706  column 2, nibble E
        LDX $4F30                       ; $5709  column 2, nibble E on a ladder
        STX $4F29                       ; $570C  the ladder marks into the plain slot
        STA $4F30                       ; $570F  the plain marks into the ladder slot
        LDA $4F2A                       ; $5712  column 2, nibble F
        LDX $4F31                       ; $5715  column 2, nibble F on a ladder
        STX $4F2A                       ; $5718  the ladder marks into the plain slot
        STA $4F31                       ; $571B  the plain marks into the ladder slot
        LDX $50                         ; $571E  the actor again
        RTS                             ; $5720  back
check_column2_plain:
        LDA $4F34                       ; $5721  swapped?
        BNE check_column2_unswap        ; $5724  yes: swap back
        RTS                             ; $5726  back
check_column2_unswap:
        DEC $4F34                       ; $5727  not swapped
        JMP swap_column2                ; $572A  swap back

; $572D  35027 bytes of data, through $DFFF. Nothing here is code. The
; map below is from the room snapshots. A range marked the same is identical
; in every room snapshot.
;
;   $572D-$59A4  zero, and nothing reads it.
;   $59A5-$59B2  actor tables. $59A5 the three library bases, 00 8C 46,
;                that store_pose picks with the rolls of active,X. $59A8
;                and $59AB the two effect columns wake_actor reads, 04 03
;                06 and 05 00 07. $59AE-$59B2 are the five bytes
;                claim_voice_slot reads for effects 3-7.
;   $59B3-$59BC  01 02 04 08 10 1E 1D 1B 17 0F, which nothing reads: the
;                five joystick bits, each one set, then each one clear.
;   $59BD-$5D90  the library tables, 210 entries each, three sets of 70:
;                $59BD source low, $5A8F source high, $5B61 height,
;                $5CBF mode. $5C33 is the color byte, 140 long, for bases
;                0 and $46. Base $8C is the ninja's, and load_library
;                stores $F0 for him in place of the table.
;   $5D91-$68F8  the source pictures. Base $46 is $5D91-$6282 and base 0
;                is $636A-$67FC. Base $8C has 35 libraries with a source.
;                They span $6283-$68F8, so they share bytes with base 0.
;                The other 35 have a zero pointer. $6667 is only
;                copy_sprite_image's operand before load_library patches it.
;   $68F9-$817F  the twenty packed room pictures, one after another, from
;                the pointers at $4B34/$4B49. Room 0 ends at $6A08 and
;                room 19 at $817F. The streams are in rooms.asm.
;   $8180-$83FF  the hardware sprite images, double buffered through the
;                pointers at $274F. They change from room to room.
;   $8400-$87FF  glyphs $80-$FF of charset $8000: the logo, the PLAYER page
;                digits, and the big score digits. The options page and the
;                PLAYER page select this charset, so its low half, which is
;                $8000-$83FF, is never drawn.
;   $8800-$8BFF  the score font, glyphs 0-$7F of charset $8800. The stub
;                at $0400 copies it from the character ROM before boot.
;   $8C00-$8FE7  the screen. $8FF8-$8FFF are the sprite pointers.
;   $9000-$9FBF  the scan pictures, $60 bytes a pose, three columns of 32
;                rows. build_sprites writes them from the $1167/$1239
;                pointers after expand_charset has used the packed charsets
;                stored here. The VIC sees the character ROM at $9000-$9FFF
;                in this bank, so this RAM never shows on screen.
;   $A000-$BFFF  the four expanded charsets. $A000 is rooms 0-9, $A800
;                rooms 10-17 and 19, $B000 room 18. $B800 is never shown.
;                Some glyphs in $A300-$AFFF differ between snapshots:
;                flicker_lamps and some room hooks rewrite them.
;   $C000-$CADF  more scan pictures, the same as $9000. Outside the VIC
;                bank. In boot01_title.vsf this RAM still holds the title
;                loader.
;   $CAE0-$CB5F  four columns of 32 bytes: $CAE0, $CB00, $CB20, $CB40.
;                build_sprites expands a pose's second library here and
;                ORs it into the first. Later build_actor_mask builds each
;                actor's shifted mask here, and scan_row ANDs it with the
;                glyphs.
;   $CB60-$CDFF  zero, and nothing reads it.
;   $CE00-$CEFF  the scratch color page. point_at_row aims ($08) here while
;                $0100 is set, so print_keep_color does not change any
;                colors.
;   $CF00-$CF78  the top of the unpacked program. Nothing reads it.
;   $CF79-$CFB8  two 32-byte copies, $CF79 and $CF99, one above the top
;                byte the decruncher writes. They are already there in
;                boot01_title.vsf. Most pairs differ, and $CF8F-$CF91
;                equals $CFAF-$CFB1. These are tamper checks:
;                checksum_hang hangs unless the six bytes at $CF8F-$CF91
;                and $CFAF-$CFB1 XOR to 0. build_sprites spins until $CF8F
;                and $CFAF are both $B9. spawn_yamo stores $CF79 EOR $CF99,
;                $89, at $1166, and the loop after scan_specials stores
;                $CF7A EOR $CF9A, $04, at $2007. score_blip moves its two
;                counters only when those bytes are 0. Once a counter
;                runs out, score_blip writes $9A, TXS, over code: at
;                $1159 in noise_byte, or at $1FFE in score_blip itself.
;                That wrecks the stack. The counters are the operand
;                bytes of those LDA and EOR instructions, so each step
;                also moves the checked pair. refresh_top's three XORs
;                branch to the same place either way. With the bytes as
;                they are, no trap fires, and the port leaves them out.
;   $D000-$DFFF  RAM under the I/O area, all zero. boot stores $35 in $01,
;                so the I/O chips are always switched in here and this RAM
;                is never used.

; Tune player under the KERNAL, at $E000. Play does not call it.
; irq_service runs the effect voices. game_over_raster runs
; service_tune, on the options page and during game over. The title
; picture plays nothing. The two players are not installed together.
reset_music:
        JMP tune_entry_reset            ; $E000  silence the tune player
; Options tune. open_room calls this when $1385 is zero.
start_tune:
        JMP tune_entry_start            ; $E003  the options tune

; Once per raster, from game_over_raster.
service_tune:
        JMP service_tune_body           ; $E006  one tick of the tune
; $E009  759 bytes. Note frequencies and the tune player's image.
; $E100 transpose, added to a nonzero note.
; $E101,X nonzero holds the gate when a note count reaches 0.
; $E104, $E105, $E106 count the three notes. $E107, $E108, $E109
; are the values that end them. $E10A,X reloads the count and
; $E10D,X reloads the end value.
; $E110,X and $E113,X are the ADSR pair written with a new note.
; $E116,X is the waveform. Gate-off stores it with bit 0 cleared.
; $E119,X is the duration mode.
; $E11C, $E122, and $E128 are the three voices' ADSR images.
; $E12E is the voice being read: 0, 1, or 2. $E12F counts the tempo.
; $E130 is the byte after the one just returned. Bit 7 set is a command.
; $E200 is the low frequency byte and $E254 the high, 84 notes, $00-$53.
; It is an NTSC table: note 0 is $01F8, B0 on a 1.023 MHz clock, and each
; index is one semitone up, so $53 is A#7. On a PAL machine every note is
; about 0.7 of a semitone flat. A note index is not clipped. $54 reads $0001
; and $55 reads $0002, the next bytes along. Those all but stop the
; oscillator. Effects $83, $84, and $86 use them.
; prime_tune copies $E2A8-$E2D5 onto $E100-$E12D.
; $E2D6 eight branch offsets: 00 03 06 09 0C 0F 12 15. The command's
; high nibble, masked to 0-7, indexes them.
; $E2E7 is 01 here. tune_duration adds $10 to its nibble while that
; is set. $E2E8 is the $D417 byte. It is 00 here, so nothing is
; routed to the filter.

; reset_music lands here.
tune_entry_reset:
        JMP reset_tune                  ; $E300  silence, and return from there
; Second entry. load_tune.
tune_entry_load:
        JMP load_tune                   ; $E303  load the tune
; start_tune lands here.
tune_entry_start:
        JMP start_tune_body             ; $E306  start the sequence

; $E309  73 bytes of tune state, not code.
; $E309 tune number. $E30A nonzero makes service_tune silence the
; player, and reset_music then clears the flag. $E30B is set when
; a voice reads $FF. $E30C is 0 until load_tune finishes, and
; service_tune returns at once while it is clear.
; $E30D is the tempo reload for $E12F. $E30E is $FF when a voice
; has ended. $E30F and $E311 are ORed into $D418. $E310 is the
; voice, plus one, whose next note writes volume and $D417.
; $E312 is scratch. $E314 is the mode open_room stored: 3 walks
; the sequence at $E870 and loops it.

; $E30C stays 0 while prime_tune runs, so a raster mid-load returns.
; It is set once each voice has read its first command.
load_tune:
        LDA #$00                        ; $E352  zero
        STA $E30C                       ; $E354  not ready, so service_tune returns
        JSR prime_tune                  ; $E357  pointers, image, opening commands
        LDA #$01                        ; $E35A  1
        STA $E30C                       ; $E35C  ready
        RTS                             ; $E35F  back
; Tune number times 8 indexes $E8C0. Six bytes, three pointers, are
; written over the operands of fetch_0, fetch_1, and fetch_2. Two
; bytes of each entry are unused. Tune 0 here is $E8D0, $E97D, $EA31.
; $E86B is 01, the last tune number, and a larger number is replaced by
; it. Tune 1's pointers are $EAB3, $EB60, and $EC14: a stale copy of tune
; 0's voice 0, then the code of voice_1, then the effect tables. Nothing
; selects tune 1, since open_room's sequence is tune 0 alone.
patch_tune_ptrs:
        LDA $E309                       ; $E360  the tune number
        CMP $E86B                       ; $E363  past the last tune?
        BCC patch_tune_index            ; $E366  no: use it
        LDA $E86B                       ; $E368  yes: the last tune
patch_tune_index:
        ASL A                           ; $E36B  times 2
        ASL A                           ; $E36C  times 4
        ASL A                           ; $E36D  times 8
        TAY                             ; $E36E  index into $E8C0
        LDX #$FE                        ; $E36F  X steps 0, 4, 8: the three operands
patch_tune_loop:
        INX                             ; $E371  the opcode's byte
        INX                             ; $E372  the next fetch's operand
        LDA $E8C0,Y                     ; $E373  stream pointer, low
        STA $E3DF,X                     ; $E376  into the operand
        INY                             ; $E379  the next pointer byte
        INX                             ; $E37A  the operand's high byte
        LDA $E8C0,Y                     ; $E37B  stream pointer, high
        STA $E3DF,X                     ; $E37E  into the operand
        INY                             ; $E381  the next entry byte
        INX                             ; $E382  past the operand
        CPX #$0A                        ; $E383  three done?
        BCC patch_tune_loop             ; $E385  more
        RTS                             ; $E387  back
; Not reached. LDA $E8C0,Y / RTS, left between the copy and prime_tune.
; The live fetches are absolute LDAs, and their operands are patched.
        .byte $B9, $C0, $E8, $60        ; $E388  LDA $E8C0,Y / RTS, not reached

; Pointers, then the image at $E2A8 copied onto $E100, then one
; command byte on each of the three voices.
prime_tune:
        JSR patch_tune_ptrs             ; $E38C  point the fetches at the tune
        JSR copy_tune_image             ; $E38F  fresh state, SID cleared
        LDX #$00                        ; $E392  voice 0
prime_tune_voice:
        STX $E12E                       ; $E394  the voice read_tune serves
        LDA #$FF                        ; $E397  pretend the next byte is a command
        STA $E130                       ; $E399  into the peek byte
        JSR tune_byte                   ; $E39C  so the opening commands run, up to the first note
        LDX $E12E                       ; $E39F  the voice
        INX                             ; $E3A2  the next
        CPX #$03                        ; $E3A3  all three voices?
        BNE prime_tune_voice            ; $E3A5  more
        RTS                             ; $E3A7  back
; Clear $E30F and $E2E8, copy the 46 bytes at $E2A8 onto $E100, and take
; the tempo from $E30D into $E12F. prime_tune runs this before it reads
; the first command on each voice.
copy_tune_image:
        LDA #$00                        ; $E3A8  zero
        STA $E30F                       ; $E3AA  filter mode bits off
        STA $E2E8                       ; $E3AD  no voice routed to the filter
        LDX #$2E                        ; $E3B0  46 bytes
copy_tune_loop:
        LDA $E2A7,X                     ; $E3B2  from $E2A8 up
        STA $E0FF,X                     ; $E3B5  onto $E100 up
        DEX                             ; $E3B8  the next
        BNE copy_tune_loop              ; $E3B9  more
        LDA $E30D                       ; $E3BB  the tempo
        STA $E12F                       ; $E3BE  starts the tempo count
        TXA                             ; $E3C1  X is 0 here
        STA $E30B                       ; $E3C2  no voice has ended
clear_tune_state:
        STA $E30A                       ; $E3C5  no stop request
        STA $E30E                       ; $E3C8  no voice at $FF
        STA $E30C                       ; $E3CB  not ready
        STA $E100                       ; $E3CE  transpose 0
        LDX #$17                        ; $E3D1  $D417 down to $D400
clear_tune_sid:
        STA $D400,X                     ; $E3D3  SID voice 1 frequency low, plus X
        DEX                             ; $E3D6  the next register
        BPL clear_tune_sid              ; $E3D7  more
        RTS                             ; $E3D9  back
; A = 0. Clears $E30A, $E30E, $E30C, and the transpose, then zeroes
; $D400 through $D417. $E30B is left as it was.
silence_tune:
        LDA #$00                        ; $E3DA  zero
        BEQ clear_tune_state            ; $E3DC  always
; Absolute LDA. patch_tune_ptrs overwrites the operand, and read_tune
; increments it, low byte then high. $E8F6 is what this snapshot still
; held. fetch_1 shows $E98A and fetch_2 shows $EA44. Those are not the
; streams of a tune that had been loaded.
fetch_0:
        LDA $E8F6                       ; $E3DE  voice 0's next byte. The operand is patched
        RTS                             ; $E3E1  back
; Stream 1. read_tune steps the operand at $E3E3/$E3E4.
fetch_1:
        LDA $E98A                       ; $E3E2  voice 1's next byte. The operand is patched
        RTS                             ; $E3E5  back
; Stream 2. read_tune steps the operand at $E3E7/$E3E8.
fetch_2:
        LDA $EA44                       ; $E3E6  voice 2's next byte. The operand is patched
        RTS                             ; $E3E9  back
; One stream byte comes back in A, with that byte's flags preserved.
; The next byte is stored in $E130. $E12E selects the stream: 0 uses
; fetch_0, bit 0 set uses fetch_1, and anything else uses fetch_2.
read_tune:
        LDA $E12E                       ; $E3EA  which voice
        BEQ read_tune_0                 ; $E3ED  voice 0
        LSR A                           ; $E3EF  bit 0
        BCS read_tune_1                 ; $E3F0  voice 1
        JSR fetch_2                     ; $E3F2  voice 2's byte
        PHP                             ; $E3F5  keep its flags
        INC $E3E7                       ; $E3F6  step the operand
        BNE read_tune_peek_2            ; $E3F9  no carry
        INC $E3E8                       ; $E3FB  carry into the high byte
read_tune_peek_2:
        PHA                             ; $E3FE  keep the byte
        JSR fetch_2                     ; $E3FF  peek at the next one
        STA $E130                       ; $E402  for tune_byte
        PLA                             ; $E405  the byte again
        PLP                             ; $E406  and its flags
        RTS                             ; $E407  back
read_tune_0:
        JSR fetch_0                     ; $E408  voice 0's byte
        PHP                             ; $E40B  keep its flags
        INC $E3DF                       ; $E40C  step the operand
        BNE read_tune_peek_0            ; $E40F  no carry
        INC $E3E0                       ; $E411  carry into the high byte
read_tune_peek_0:
        PHA                             ; $E414  keep the byte
        JSR fetch_0                     ; $E415  peek at the next one
        STA $E130                       ; $E418  for tune_byte
        PLA                             ; $E41B  the byte again
        PLP                             ; $E41C  and its flags
        RTS                             ; $E41D  back
read_tune_1:
        JSR fetch_1                     ; $E41E  voice 1's byte
        PHP                             ; $E421  keep its flags
        INC $E3E3                       ; $E422  step the operand
        BNE read_tune_peek_1            ; $E425  no carry
        INC $E3E4                       ; $E427  carry into the high byte
read_tune_peek_1:
        PHA                             ; $E42A  keep the byte
        JSR fetch_1                     ; $E42B  peek at the next one
        STA $E130                       ; $E42E  for tune_byte
        PLA                             ; $E431  the byte again
        PLP                             ; $E432  and its flags
        RTS                             ; $E433  back
; reset_music lands here, through the jump at $E300. Silence the tune
; player and return.
reset_tune:
        JSR silence_tune                ; $E434  silence
        RTS                             ; $E437  back

; Y is $E314 when a voice has ended. Bit 7: the low 7 bits are a tune
; number. Bit 1: walk $E870 from the cursor in $E86C. Otherwise step
; $E309. Past the last tune, bit 0 clear silences and bit 0 set wraps.
; A sequence byte with bit 7 set restarts from $E86D, or silences when
; bit 0 of Y is clear. Bit 6 set stores the low 6 bits in $E100, the
; transpose, and the walk continues. Any other byte is a tune number.
; open_room writes 00 FF at $E870 and $E86D is 0, so the options tune
; is tune 0, then restart.
advance_tune:
        TYA                             ; $E438  the mode
        BPL advance_tune_mode           ; $E439  bit 7 clear
        AND #$7F                        ; $E43B  a fixed tune number
        TAX                             ; $E43D  the tune
        JMP select_tune                 ; $E43E  load it
advance_tune_mode:
        AND #$02                        ; $E441  sequence?
        BNE advance_sequence            ; $E443  yes
        LDX $E309                       ; $E445  the current tune
        CPX $E86B                       ; $E448  the last one?
        BCC advance_tune_next           ; $E44B  no: the next
        LDX #$FF                        ; $E44D  0 after the INX
        TYA                             ; $E44F  the mode
        AND #$01                        ; $E450  bit 0: loop
        BEQ sequence_silence            ; $E452  no: silence
advance_tune_next:
        INX                             ; $E454  the next tune

select_tune:
        STX $E309                       ; $E455  the tune number
        JMP tune_entry_load             ; $E458  load it
advance_sequence:
        LDX $E86C                       ; $E45B  the cursor

sequence_byte:
        LDA $E870,X                     ; $E45E  a sequence byte
        BMI sequence_restart            ; $E461  bit 7: restart
        ASL A                           ; $E463  bit 6 into bit 7
        BPL sequence_tune               ; $E464  clear: a tune number
        ASL A                           ; $E466  drop bit 6
        LSR A                           ; $E467  back down
        LSR A                           ; $E468  the low 6 bits
        STA $E100                       ; $E469  the transpose
        INX                             ; $E46C  the next byte
        JMP sequence_byte               ; $E46D  the next byte
sequence_tune:
        LSR A                           ; $E470  the tune number again
        INX                             ; $E471  past it
        STX $E86C                       ; $E472  the cursor
        TAX                             ; $E475  the tune
        JMP select_tune                 ; $E476  load it
; Y = 1. Bit 0 set means a restarting sequence keeps playing. The
; cursor is reloaded from $E86D and the walk begins.
start_tune_body:
        LDY #$01                        ; $E479  loop the sequence
sequence_restart:
        LDX $E86D                       ; $E47B  the restart index
        STX $E86C                       ; $E47E  the cursor
        TYA                             ; $E481  the mode
        AND #$01                        ; $E482  bit 0: loop
        BNE sequence_byte               ; $E484  read the sequence
sequence_silence:
        JMP silence_tune                ; $E486  silence, and return from there

; $D418 is $E30F OR $E311. $D417 is $E2E8, which this tune leaves at
; 0, so the filter bits do not route a voice. Called when the voice
; named in $E310 starts a note, and $E310 is then cleared.
write_tune_volume:
        LDA $E30F                       ; $E489  filter mode bits
        ORA $E311                       ; $E48C  volume
        STA $D418                       ; $E48F  SID volume and filter mode
        LDA $E2E8                       ; $E492  voice routing
        STA $D417                       ; $E495  SID filter resonance and voice routing
        LDA #$00                        ; $E498  zero
        STA $E310                       ; $E49A  written, so no voice owes it
        RTS                             ; $E49D  back
; $E30A nonzero silences the player. $E30C zero returns. $E30E = $FF
; means a voice ended: $E314 zero silences, otherwise advance_tune
; runs and this routine starts over. $E12F counts the tempo and
; reloads from $E30D. Only then do the note counts move. At 0 the
; gate bit is cleared unless $E101,X is set. The count continues
; until it matches the end value, which starts the next note.
service_tune_body:
        LDA $E30A                       ; $E49E  stop requested?
        BNE service_tune_stop           ; $E4A1  yes: silence
        LDA $E30C                       ; $E4A3  loaded?
        BNE service_tune_running        ; $E4A6  yes
service_tune_done:
        RTS                             ; $E4A8  back
service_tune_running:
        LDX $E30E                       ; $E4A9  a voice ended?
        CPX #$FF                        ; $E4AC  $FF?
        BNE service_tune_tick           ; $E4AE  no: count
        LDY $E314                       ; $E4B0  what then
        BEQ service_tune_stop           ; $E4B3  nothing: silence
        JSR advance_tune                ; $E4B5  load the next tune
        JMP service_tune_body           ; $E4B8  and service it now
service_tune_stop:
        JMP silence_tune                ; $E4BB  silence the player
service_tune_tick:
        DEC $E12F                       ; $E4BE  the tempo count
        BNE service_tune_done           ; $E4C1  not a tick yet
        LDA $E30D                       ; $E4C3  reload it
        STA $E12F                       ; $E4C6  the count
        DEC $E104                       ; $E4C9  voice 0's count
        BPL tune_voice0_release         ; $E4CC  0 or more: maybe the gate
        LDA $E104                       ; $E4CE  the count, now negative
        CMP $E107                       ; $E4D1  reached the end?
        BNE tune_voice1                 ; $E4D4  not yet
        LDA $E10A                       ; $E4D6  reload the count
        STA $E104                       ; $E4D9  the count
        LDA $E10D                       ; $E4DC  and the end
        STA $E107                       ; $E4DF  the end
        LDA $E310                       ; $E4E2  the voice that owes the volume
        CMP #$01                        ; $E4E5  voice 0 owes the volume?
        BNE tune_voice0_note            ; $E4E7  not this one
        JSR write_tune_volume           ; $E4E9  write $D418 and $D417
tune_voice0_note:
        LDX #$00                        ; $E4EC  voice 0
        JSR play_tune_note              ; $E4EE  its next note and commands
        JMP tune_voice1                 ; $E4F1  the next voice
tune_voice0_release:
        BNE tune_voice1                 ; $E4F4  count not 0: nothing
        LDA $E101                       ; $E4F6  hold?
        BNE tune_voice1                 ; $E4F9  yes: keep the gate
        LDA $E116                       ; $E4FB  the waveform
        AND #$FE                        ; $E4FE  gate off
        STA $D404                       ; $E500  SID voice 1 waveform and gate
tune_voice1:
        DEC $E105                       ; $E503  voice 1's count
        BPL tune_voice1_release         ; $E506  0 or more: maybe the gate
        LDA $E105                       ; $E508  the count, now negative
        CMP $E108                       ; $E50B  reached the end?
        BNE tune_voice2                 ; $E50E  not yet
        LDA $E10B                       ; $E510  reload the count
        STA $E105                       ; $E513  the count
        LDA $E10E                       ; $E516  and the end
        STA $E108                       ; $E519  the end
        LDA $E310                       ; $E51C  the voice that owes the volume
        CMP #$02                        ; $E51F  voice 1 owes the volume?
        BNE tune_voice1_note            ; $E521  not this one
        JSR write_tune_volume           ; $E523  write $D418 and $D417
tune_voice1_note:
        LDX #$01                        ; $E526  voice 1
        JSR play_tune_note              ; $E528  its next note and commands
        JMP tune_voice2                 ; $E52B  the next voice
tune_voice1_release:
        BNE tune_voice2                 ; $E52E  count not 0: nothing
        LDA $E102                       ; $E530  hold?
        BNE tune_voice2                 ; $E533  yes: keep the gate
        LDA $E117                       ; $E535  the waveform
        AND #$FE                        ; $E538  gate off
        STA $D40B                       ; $E53A  SID voice 2 waveform and gate
tune_voice2:
        DEC $E106                       ; $E53D  voice 2's count
        BPL tune_voice2_release         ; $E540  0 or more: maybe the gate
        LDA $E106                       ; $E542  the count, now negative
        CMP $E109                       ; $E545  reached the end?
        BNE service_tune_return         ; $E548  not yet
        LDA $E10C                       ; $E54A  reload the count
        STA $E106                       ; $E54D  the count
        LDA $E10F                       ; $E550  and the end
        STA $E109                       ; $E553  the end
        LDA $E310                       ; $E556  the voice that owes the volume
        CMP #$03                        ; $E559  voice 2 owes the volume?
        BNE tune_voice2_note            ; $E55B  not this one
        JSR write_tune_volume           ; $E55D  write $D418 and $D417
tune_voice2_note:
        LDX #$02                        ; $E560  voice 2
        JSR play_tune_note              ; $E562  its next note and commands
        JMP service_tune_return         ; $E565  done
tune_voice2_release:
        BNE service_tune_return         ; $E568  count not 0: nothing
        LDA $E103                       ; $E56A  hold?
        BNE service_tune_return         ; $E56D  yes: keep the gate
        LDA $E118                       ; $E56F  the waveform
        AND #$FE                        ; $E572  gate off
        STA $D412                       ; $E574  SID voice 3 waveform and gate
service_tune_return:
        RTS                             ; $E577  back
; X is the voice, 0-2. $E719,X is the SID base: 00, 07, 0E. A zero
; note clears the frequency and does not write the waveform. Any
; other note adds the transpose and reads $E200/$E254. ADSR and the
; waveform are written only when $E101,X is 0.
play_tune_note:
        STX $E12E                       ; $E578  this voice
        JSR read_tune                   ; $E57B  its note
        LDX $E12E                       ; $E57E  the voice
        LDY $E719,X                     ; $E581  its SID base
        TAX                             ; $E584  the note
        BNE play_tune_pitch             ; $E585  not 0: a pitch
        STA $D400,Y                     ; $E587  rest: frequency 0
        STA $D401,Y                     ; $E58A  the gate is left as it was
        JMP tune_byte                   ; $E58D  the commands after it
play_tune_pitch:
        CLC                             ; $E590  carry clear
        ADC $E100                       ; $E591  plus the transpose
        TAX                             ; $E594  the index
        LDA $E254,X                     ; $E595  frequency high
        STA $D401,Y                     ; $E598  SID voice 1 frequency high, plus Y
        LDA $E200,X                     ; $E59B  frequency low
        STA $D400,Y                     ; $E59E  SID voice 1 frequency low, plus Y
        LDX $E12E                       ; $E5A1  the voice
        LDA $E101,X                     ; $E5A4  hold?
        BNE tune_byte                   ; $E5A7  yes: no new envelope
        LDA $E110,X                     ; $E5A9  attack and decay
        STA $D405,Y                     ; $E5AC  SID voice 1 attack and decay, plus Y
        LDA $E113,X                     ; $E5AF  sustain and release
        STA $D406,Y                     ; $E5B2  SID voice 1 sustain and release, plus Y
        LDA $E116,X                     ; $E5B5  waveform, gate set
        STA $D404,Y                     ; $E5B8  SID voice 1 waveform and gate, plus Y

; $E130 bit 7 clear: that byte was a note, already played. $FF marks
; the voice ended, in $E30E and $E30B. Any other value is a command.
; Its high nibble, masked to 0-7, indexes the offsets at $E2D6.
tune_byte:
        LDA $E130                       ; $E5BB  the byte after the last one read
        BMI tune_read_command           ; $E5BE  a command
        JMP tune_byte_done              ; $E5C0  a note: wait for its time
tune_read_command:
        JSR read_tune                   ; $E5C3  take the command
        CMP #$FF                        ; $E5C6  end of the voice?
        BNE tune_command                ; $E5C8  a command
        LDA #$01                        ; $E5CA  ended
        STA $E30B                       ; $E5CC  the ended flag
        LDA #$FF                        ; $E5CF  service_tune moves on
        STA $E30E                       ; $E5D1  the voice-ended flag
        JMP tune_byte_done              ; $E5D4  back
tune_command:
        TAY                             ; $E5D7  keep the command
        LSR A                           ; $E5D8  the high nibble
        LSR A                           ; $E5D9  down
        LSR A                           ; $E5DA  to bits 0-3
        LSR A                           ; $E5DB  high nibble
        AND #$07                        ; $E5DC  0-7, so $Fn is command 7
        TAX                             ; $E5DE  the index
        LDA $E2D6,X                     ; $E5DF  its offset
        STA $E5E7                       ; $E5E2  offset from $E2D6. Do not cache it
        CLC                             ; $E5E5  carry clear
        BCC tune_cmd_table              ; $E5E6  always, into the table
tune_cmd_table:
        JMP tune_cmd_time               ; $E5E8  command 0, the length
        JMP tune_cmd_level              ; $E5EB  command 1, the volume
        JMP tune_cmd_voice              ; $E5EE  command 2, the voice settings
        JMP tune_cmd_patch              ; $E5F1  command 3, the patch
        JMP tune_cmd_pw                 ; $E5F4  command 4, the pulse width
        JMP tune_cmd_filter             ; $E5F7  command 5, the filter
        JMP tune_cmd_tempo              ; $E5FA  command 6, the tempo
; Command 0, and command 7. Offset $15 lands here with no JMP.
; The low nibble is the duration. $E119,X is the mode. The two
; results reload the note count and the end compare.

tune_cmd_time:
        TYA                             ; $E5FD  the command
        AND #$0F                        ; $E5FE  the length nibble
        LDX $E12E                       ; $E600  the voice
        LDY $E119,X                     ; $E603  the voice's gate mode
        JSR tune_duration               ; $E606  X reload, Y end
        TXA                             ; $E609  the reload
        LDX $E12E                       ; $E60A  the voice
        STA $E10A,X                     ; $E60D  for the next note
        TYA                             ; $E610  the end
        STA $E10D,X                     ; $E611  for the next note
        JMP tune_byte                   ; $E614  the next byte

; Command 1. The low nibble is a volume half, stored at $E311.
; $E310 = voice + 1, so this voice's next note writes $D418.
tune_cmd_level:
        TYA                             ; $E617  the command
        AND #$0F                        ; $E618  volume
        STA $E311                       ; $E61A  one byte for all three voices
        LDX $E12E                       ; $E61D  the voice
        INX                             ; $E620  plus one
        STX $E310                       ; $E621  written with this voice's next note
        JMP tune_byte                   ; $E624  the next byte
; Command bytes $AC-$AF. Bit 0 is stored in $E2E7. While that
; byte is set, tune_duration adds $10 before indexing $E6F9.
tune_set_pace:
        TYA                             ; $E627  the command
        AND #$01                        ; $E628  the pace bit
        STA $E2E7                       ; $E62A  one byte for all three voices
        JMP tune_byte                   ; $E62D  the next byte
; Command 2, and command $A, since the high nibble is masked to
; 0-7. $AB stores waveform $51. A low nibble below 4 picks a
; waveform from $E71C: $11 triangle, $21 saw, $41 pulse, $81
; noise, each with the gate set. Nibbles 4-6 store the duration
; mode and copy one ADSR pair. The base is $E11C plus 0, 6, or
; 12, from tune_pair_index. Modes 0, 1, and 2 read that base,
; base+2, and base+4. Nibbles 7 and 8 store bit 0 in $E101,X.
; Nonzero holds the gate. Any other nibble writes bit 0 into
; waveform bit 2, the sync bit.
tune_cmd_voice:
        CPY #$AC                        ; $E630  $AC-$AF?
        BCS tune_set_pace               ; $E632  the pace bit
        LDA #$51                        ; $E634  tri+pulse, gate
        CPY #$AB                        ; $E636  $AB?
        BEQ tune_store_wave             ; $E638  yes
        TYA                             ; $E63A  the command
        AND #$0F                        ; $E63B  the low nibble
        CMP #$04                        ; $E63D  a waveform?
        BCS tune_mode_or_flag           ; $E63F  no
        TAX                             ; $E641  the index
        LDA $E71C,X                     ; $E642  the waveform, gate set
tune_store_wave:
        LDX $E12E                       ; $E645  the voice
        STA $E116,X                     ; $E648  used from the next note
        JMP tune_byte                   ; $E64B  the next byte
tune_mode_or_flag:
        CMP #$07                        ; $E64E  hold or sync?
        BCS tune_cmd_flag               ; $E650  yes
        AND #$03                        ; $E652  mode 0, 1, or 2
        LDX $E12E                       ; $E654  the voice
        STA $E119,X                     ; $E657  the gate mode
        TAY                             ; $E65A  the mode
        DEY                             ; $E65B  flags: mode 0 minus, 1 zero, 2 plus
        PHP                             ; $E65C  keep the flags
        LDA $E68B,X                     ; $E65D  this voice's patch base
        TAY                             ; $E660  the base
        PLP                             ; $E661  the flags back
; DEY's flags select the pair. PLP restores them after Y is the index.
        BMI tune_adsr_mode0             ; $E662  mode 0
        BEQ tune_adsr_mode1             ; $E664  mode 1
        LDA $E120,Y                     ; $E666  mode 2: the third pair
        PHA                             ; $E669  kept
        LDA $E121,Y                     ; $E66A  sustain and release
tune_store_adsr:
        STA $E113,X                     ; $E66D  sustain and release
        PLA                             ; $E670  attack and decay
        STA $E110,X                     ; $E671  attack and decay
        JMP tune_byte                   ; $E674  the next byte
tune_adsr_mode1:
        LDA $E11E,Y                     ; $E677  mode 1: the second pair
        PHA                             ; $E67A  kept
        LDA $E11F,Y                     ; $E67B  sustain and release
        JMP tune_store_adsr             ; $E67E  store them
tune_adsr_mode0:
        LDA $E11C,Y                     ; $E681  mode 0: the first pair
        PHA                             ; $E684  kept
        LDA $E11D,Y                     ; $E685  sustain and release
        JMP tune_store_adsr             ; $E688  store them
; Voice 0, 1, and 2. Base index of that voice's ADSR pairs.
tune_pair_index:
        .byte $00, $06, $0C             ; $E68B  voice 0, 1, and 2
; Command 2 with a low nibble of 7 or more. 7 and 8 store bit 0 in
; $E101,X, the hold-gate flag. 9 and up set or clear waveform bit 2 from
; bit 0, through $E312.
tune_cmd_flag:
        CMP #$09                        ; $E68E  sync?
        BCS tune_sync_bit               ; $E690  yes
        AND #$01                        ; $E692  7 holds, 8 lets go
        LDX $E12E                       ; $E694  the voice
        STA $E101,X                     ; $E697  the hold flag
; Every voice command returns to tune_byte through here.
tune_cmd_done:
        JMP tune_byte                   ; $E69A  the next byte
tune_sync_bit:
        AND #$01                        ; $E69D  the sync bit
        ASL A                           ; $E69F  times 2
        ASL A                           ; $E6A0  into bit 2
        STA $E312                       ; $E6A1  kept
        LDX $E12E                       ; $E6A4  the voice
        LDA $E116,X                     ; $E6A7  the waveform
        AND #$FB                        ; $E6AA  sync off
        ORA $E312                       ; $E6AC  then as asked
        STA $E116,X                     ; $E6AF  stored
        JMP tune_cmd_done               ; $E6B2  the next byte

; Back to the caller. The byte was a note, or the voice has ended.
tune_byte_done:
        RTS                             ; $E6B5  back
; A is the duration nibble. Y is the mode from $E119,X. $E2E7 set
; adds $10 before the index into $E6F9. Mode 0 releases for the last
; eighth, mode 1 for the second half, and mode 2 on the last count.
; X returns the reload and Y the end compare. A count reloaded with R
; and ended at -E lasts R+E ticks, and the gate drops after R of them.
; With R = 0 the count never reads 0, so the gate stays on. Mode 2 falls
; through here: R = length-1, E = 1.
tune_duration:
        LDX $E2E7                       ; $E6B6  pace?
        BEQ tune_duration_mode          ; $E6B9  no
        CLC                             ; $E6BB  carry clear
        ADC #$10                        ; $E6BC  the second half of the table
tune_duration_mode:
        TAX                             ; $E6BE  the index
        DEY                             ; $E6BF  mode 1 zero, mode 0 minus
        BEQ tune_duration_half_gate     ; $E6C0  mode 1
        BMI tune_duration_eighth        ; $E6C2  mode 0
        LDA $E6F9,X                     ; $E6C4  mode 2: the length
        TAX                             ; $E6C7  the length
        LDY #$FF                        ; $E6C8  end -1
        DEX                             ; $E6CA  reload length-1
        RTS                             ; $E6CB  back
; Mode 0. The gate is off for the last eighth, at least one count.
tune_duration_eighth:
        LDA $E6F9,X                     ; $E6CC  the length
        LSR A                           ; $E6CF  a quarter
        LSR A                           ; $E6D0  an eighth
        LSR A                           ; $E6D1  an eighth of it
        BNE tune_duration_store         ; $E6D2  at least 1
        LDA #$01                        ; $E6D4  at least 1
tune_duration_store:
        STA $E312                       ; $E6D6  e
        LDA $E6F9,X                     ; $E6D9  the length
        SEC                             ; $E6DC  the borrow
        SBC $E312                       ; $E6DD  reload length-e
        TAX                             ; $E6E0  the reload
        LDA #$00                        ; $E6E1  zero
        SEC                             ; $E6E3  the borrow
        SBC $E312                       ; $E6E4  end -e
        TAY                             ; $E6E7  the end
        RTS                             ; $E6E8  back
; Mode 1. The gate is on for the first half.
tune_duration_half_gate:
        LDA $E6F9,X                     ; $E6E9  the length
        LSR A                           ; $E6EC  half of it
        STA $E312                       ; $E6ED  half
        TAX                             ; $E6F0  reload half
        LDA #$00                        ; $E6F1  zero
        SEC                             ; $E6F3  the borrow
        SBC $E312                       ; $E6F4  end -half
        TAY                             ; $E6F7  the end
        RTS                             ; $E6F8  back

; $E6F9  32 duration bytes, in tempo ticks. The nibble of command 0
; indexes the first 16, and the second 16 while $E2E7 is set:
;   nibble   0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
;   $E2E7=0 32 16  8  4  2  1  8  8 48 24 12  6  3  2  8  8
;   $E2E7=1 64 32 16  8  4  2  8  8 96 48 24 12  6  4  8  8
; 0-5 halve from a whole note, 8-D are the same dotted, and 6, 7, E, F
; are spare. $E719 is 00 07 0E, the SID base of voices 0, 1, and 2.
; $E71C is 11 21 41 81, the four waveforms.

; Command 3. The low 3 bits times 8 select six bytes at $E80A.
; Voice 0 copies them to $E11C, voice 1 to $E122, voice 2 to
; $E128. Those are the three ADSR pairs the modes read.
tune_cmd_patch:
        TYA                             ; $E720  the command
        AND #$07                        ; $E721  patch number
        ASL A                           ; $E723  times 2
        ASL A                           ; $E724  times 4
        ASL A                           ; $E725  times 8
        TAY                             ; $E726  the index
        LDX #$00                        ; $E727  six bytes
        LDA $E12E                       ; $E729  which voice
        BEQ patch_voice0                ; $E72C  voice 0
        LSR A                           ; $E72E  bit 0
        BCS patch_voice1                ; $E72F  voice 1
patch_voice2:
        LDA $E80A,Y                     ; $E731  a patch byte
        STA $E128,X                     ; $E734  voice 2's three pairs
        INY                             ; $E737  the next patch byte
        INX                             ; $E738  the next pair byte
        CPX #$06                        ; $E739  six bytes?
        BNE patch_voice2                ; $E73B  more
        JMP tune_cmd_done               ; $E73D  the next byte
patch_voice0:
        LDA $E80A,Y                     ; $E740  a patch byte
        STA $E11C,X                     ; $E743  voice 0's three pairs
        INY                             ; $E746  the next patch byte
        INX                             ; $E747  the next pair byte
        CPX #$06                        ; $E748  six bytes?
        BNE patch_voice0                ; $E74A  more
        JMP tune_cmd_done               ; $E74C  the next byte
patch_voice1:
        LDA $E80A,Y                     ; $E74F  a patch byte
        STA $E122,X                     ; $E752  voice 1's three pairs
        INY                             ; $E755  the next patch byte
        INX                             ; $E756  the next pair byte
        CPX #$06                        ; $E757  six bytes?
        BNE patch_voice1                ; $E759  more
        JMP tune_cmd_done               ; $E75B  the next byte
; Command 4. The next two stream bytes are this voice's pulse
; low and high, $D402 and $D403 plus the SID base.
tune_cmd_pw:
        JSR read_tune                   ; $E75E  pulse width low
        LDX $E12E                       ; $E761  the voice
        LDY $E719,X                     ; $E764  the SID base
        STA $D402,Y                     ; $E767  SID voice 1 pulse width low, plus Y
        JSR read_tune                   ; $E76A  pulse width high
        LDX $E12E                       ; $E76D  the voice
        LDY $E719,X                     ; $E770  the SID base
        STA $D403,Y                     ; $E773  SID voice 1 pulse width high, plus Y
        JMP tune_cmd_done               ; $E776  the next byte
; Command 5. The low 3 bits times 4, plus $40, index $E80A.
; Two bytes go to $D415 and $D416. The next is ORed with one
; stream byte into $E2E8. The fourth is the volume half in $E30F.
tune_cmd_filter:
        TYA                             ; $E779  the command
        AND #$07                        ; $E77A  the setting
        ASL A                           ; $E77C  times 2
        ASL A                           ; $E77D  times 4
        CLC                             ; $E77E  carry clear
        ADC #$40                        ; $E77F  from $E84A
        TAY                             ; $E781  the index
        LDA $E80A,Y                     ; $E782  cutoff low
        STA $D415                       ; $E785  SID filter cutoff low
        INY                             ; $E788  the next setting byte
        LDA $E80A,Y                     ; $E789  cutoff high
        STA $D416                       ; $E78C  SID filter cutoff high
        INY                             ; $E78F  the next
        LDA $E80A,Y                     ; $E790  resonance and routing
        PHA                             ; $E793  kept
        INY                             ; $E794  the next
        LDA $E80A,Y                     ; $E795  filter mode bits
        STA $E30F                       ; $E798  for $D418
        LDX $E12E                       ; $E79B  the voice
        INX                             ; $E79E  plus one
        STX $E310                       ; $E79F  written with this voice's next note
        JSR read_tune                   ; $E7A2  the stream's routing bits
        STA $E312                       ; $E7A5  kept
        PLA                             ; $E7A8  the setting's routing
        ORA $E312                       ; $E7A9  with the setting's
        STA $E2E8                       ; $E7AC  for $D417
        JMP tune_cmd_done               ; $E7AF  the next byte
; Command 6. The next stream byte is the tempo, stored in $E30D
; and in the running count $E12F.
tune_cmd_tempo:
        JSR read_tune                   ; $E7B2  the tempo
        STA $E30D                       ; $E7B5  the reload
        STA $E12F                       ; $E7B8  the count
        JMP tune_cmd_done               ; $E7BB  the next byte
        NOP                             ; $E7BE  not reached

; $E7BF  836 bytes of tune data, up to voice_1.
;   $E7BF  75 bytes nothing reads.
;   $E80A  eight patches for command 3, eight bytes each. The first six
;          are three ADSR pairs, for modes 0, 1, and 2. The last two are
;          spare.
;            0  11 97  00 93  22 9B      4  60 00  60 00  60 00
;            1  22 97  11 95  33 9B      5  00 F0  00 F0  00 F0
;            2  11 93  11 92  11 97      6  66 00  66 00  66 00
;            3  09 00  09 00  00 70      7  88 98  55 95  BB 9B
;   $E84A  eight filter settings for command 5: cutoff low, cutoff high,
;          resonance and routing, and the mode bits for $D418.
;            0 00 11 F0 10   1 01 44 F0 20   2 02 77 F0 40   3 00 22 70 10
;            4 01 44 70 20   5 02 55 70 40   6 01 44 30 30   7 00 22 30 60
;          The options tune uses none of them. $E86A is not read.
;   $E86B  01, the last tune number. $E86C is the sequence cursor, 01
;          after tune 0 was read. $E86D is the restart index, 00.
;   $E86E  82 bytes that repeat tune 0's voice 0 from $E8D4. open_room
;          writes 00 FF over $E870 and $E871, the sequence: tune 0, then
;          restart. Only those two bytes are read.
;   $E8C0  eight bytes a tune: the three voice streams, then $E80A, which
;          this player does not read. Tune 0 is $E8D0, $E97D, $EA31.
;   $E8D0  tune 0, the options and game-over tune, to $EAAC. See below.
;   $EAAD  9F A1 B0 A4 00 FF, a stream that plays one rest and ends. No
;          pointer names it. Then $EAB3, a second copy of tune 0's voice 0,
;          cut off by $EB00.
;   $EB00  voice_1's slot, index, and delay.
;
; The tune stream. A byte below $80 is a note: 0 is a rest, which zeroes
; the frequency and leaves the gate, and any other note adds the transpose
; at $E100. A byte from $80 is a command, $FF ends the voice, and the high
; nibble, masked to 0-7, picks the command:
;   $8n  length: n indexes $E6F9.     $9n  volume n.
;   $An  0-3 waveform, 4-6 gate mode, 7-8 hold, 9-A sync, $AB tri+pulse,
;        $AC-$AF pace bit.
;   $Bn  patch n.    $Cn lo hi  pulse width.    $Dn xx  filter n.
;   $En tt  tempo.   $Fn  the same as $8n.
; Commands come before the note they set up. play_tune_note plays a note,
; then runs every command up to the next note, so the first note of a
; voice takes the commands that open its stream. The length is loaded when
; the note starts, the gate drops as tune_duration says, and the next note
; starts when the count runs out. The first voice to read $FF ends the
; tune as its last note starts: on the next call advance_tune loads the
; tune again from the top.
;
; Tune 0. service_tune runs once a screen and tempo 2 makes a tick every
; second call. Voice 0 sets the pace bit before voices 1 and 2 read
; anything, and $E2E7 is one byte for all three, so every length doubles.
; Each voice reads $FF at tick 576, which is 1152 screens or 23 seconds,
; and the closing rests are never heard out. Pitches are NTSC names.
;   Voice 0, $E8D0. Volume 12, pulse 0802, patch 3, mode 2, hold 0. Bass
;     in eighths: B2 B3 F#3 G3 six times, E3 E4 four times, B2 B3 F#3 G3
;     four times, E3 E4 four times. Then C#4 in sixteenths with B3 C#4
;     eighths, three times, five F#3 sixteenths, and two rests.
;   Voice 1, $E97D. Volume 15, pulse 04CE, patch 5, mode 0. Three whole
;     rests. The arpeggio G7 E7 B6 G6 E6 B5 G5 E5 in 32nds and a quarter
;     rest, twice. The figure B5 D5 F#5 G5 F#5 D5 C#6 B5 in sixteenths and
;     a half rest, twice. The arpeggio twice more. Four F#4 sixteenths and
;     E4 F#4 eighths, three times. The arpeggio on F#, F#7 down to C#5,
;     then F#5 and two rests.
;   Voice 2, $EA31. Volume 15, pulse 04CE, patch 0, mode 0. A whole rest.
;     B4 A4 eighths, B4 a quarter, and a half rest, twice. Then patch 5:
;     four E5 sixteenths and D5 E5 eighths, twice. The B4 A4 B4 phrase
;     twice, the E5 figure twice. F#4, E4 F#4, C#5, E4 F#4, a long F#5,
;     and two B5 B4 pairs in 32nds between rests.
; The volume byte $E311 and the voice in $E310 are one each, so the last
; voice's 15 replaces voice 0's 12 before any note starts. Voice 2 writes
; $D418 = 15 on the first tick.

; Called from irq_service, once per raster. SID voice 1, $D400.
; $EB00 bit 7 starts a script. The pointer is the word at $EBE5,
; index = id << 1. Delay $EB02 becomes 1, index $EB01 becomes 0,
; $D404 is cleared, and the slot is stored back as 1. The first
; command then runs on this same call. A delay of N counts this call.
; The STA before the BCC rewrites the offset from $EC03,X. X is the
; command byte. This snapshot's offset is 0, so the branch runs the
; end command's jump. voice_2 and voice_3 still branch to themselves
; until a command patches them.
voice_1:
        LDA $EB00                       ; $EB03  the slot
        BNE voice_1_active              ; $EB06  in use
voice_1_done:
        RTS                             ; $EB08  free
voice_1_active:
        BPL voice_1_tick                ; $EB09  running
        ASL A                           ; $EB0B  id times 2. Bit 7 drops out
        TAX                             ; $EB0C  the index
        LDA $EBE5,X                     ; $EB0D  script pointer, low
        STA $F6                         ; $EB10  the script pointer, low
        LDA $EBE6,X                     ; $EB12  script pointer, high
        STA $F7                         ; $EB15  high
        LDY #$01                        ; $EB17  1
        STY $EB02                       ; $EB19  delay 1: the first row runs on this call
        STY $EB00                       ; $EB1C  running
        DEY                             ; $EB1F  0
        STY $D404                       ; $EB20  gate off, before the first row gates it again
        STY $EB01                       ; $EB23  row index 0
voice_1_tick:
        DEC $EB02                       ; $EB26  the delay
        BNE voice_1_done                ; $EB29  still waiting
        LDY $EB01                       ; $EB2B  the row index
        LDA ($F6),Y                     ; $EB2E  the command
        TAX                             ; $EB30  the index
        LDA $EC03,X                     ; $EB31  its offset
        STA $EB39                       ; $EB34  rewrites a byte of the instruction at $EB38
        CLC                             ; $EB37  carry clear
        BCC voice_1_commands            ; $EB38  always
; Commands 0 through 7. Offsets 00 03 06 09 0C 0F 12 15.
; 0 end. 1 note. 2 note and wave. 3 note, ADSR, wave.
; 4 note, ADSR, pulse, wave. 5 and 6 note, pulse, wave. 7 wave.
voice_1_commands:
        JMP fx_end                      ; $EB3A  command 0, the end
        JMP fx_cmd_note                 ; $EB3D  command 1, a note
        JMP fx_cmd_note_wave            ; $EB40  command 2, a note and its waveform
        JMP fx_cmd_adsr                 ; $EB43  command 3, with an envelope
        JMP fx_cmd_full                 ; $EB46  command 4, with an envelope and pulse width
        JMP fx_cmd_pulse                ; $EB49  command 5, with pulse width
        JMP fx_cmd_pulse                ; $EB4C  command 6, the same
        JMP fx_cmd_wave                 ; $EB4F  command 7, the waveform alone
; Delay byte, then the note. $E200,X and $E254,X. Not clipped.
fx_note:
        INY                             ; $EB52  past the command
        LDA ($F6),Y                     ; $EB53  the delay
        STA $EB02                       ; $EB55  counted from the next call
        INY                             ; $EB58  the next byte
        LDA ($F6),Y                     ; $EB59  the note
        TAX                             ; $EB5B  the index
        LDA $E200,X                     ; $EB5C  frequency low
        STA $D400                       ; $EB5F  SID voice 1 frequency low
        LDA $E254,X                     ; $EB62  frequency high
        STA $D401                       ; $EB65  SID voice 1 frequency high
        INY                             ; $EB68  the next field
        RTS                             ; $EB69  back
; The script byte is an offset into the pairs at $EC11.
fx_adsr:
        LDA ($F6),Y                     ; $EB6A  pair offset
        TAX                             ; $EB6C  the index
        LDA $EC11,X                     ; $EB6D  attack and decay
        STA $D405                       ; $EB70  SID voice 1 attack and decay
        LDA $EC12,X                     ; $EB73  sustain and release
        STA $D406                       ; $EB76  SID voice 1 sustain and release
        INY                             ; $EB79  the next field
        RTS                             ; $EB7A  back
; Written as read. A gate bit that stays set does not restart the envelope.
; The decay state keeps comparing the counter with the sustain nibble, so
; a lower sustain written while the gate is held continues down.
fx_wave:
        LDA ($F6),Y                     ; $EB7B  the waveform
        STA $D404                       ; $EB7D  SID voice 1 waveform and gate
        INY                             ; $EB80  the next field
        RTS                             ; $EB81  back
; Zero the frequency and the slot. The waveform, gate included, stays.
fx_end:
        LDA #$00                        ; $EB82  zero
        STA $D400                       ; $EB84  SID voice 1 frequency low
        STA $D401                       ; $EB87  SID voice 1 frequency high
        STA $EB00                       ; $EB8A  slot free
        STA $EB01                       ; $EB8D  row index 0
        RTS                             ; $EB90  back
; Offset into the pairs at $EC1B. Low byte, then high.
fx_pulse:
        LDA ($F6),Y                     ; $EB91  pair offset
        INY                             ; $EB93  the next field
        TAX                             ; $EB94  the index
        LDA $EC1B,X                     ; $EB95  width low
        STA $D402                       ; $EB98  SID voice 1 pulse width low
        LDA $EC1C,X                     ; $EB9B  width high
        STA $D403                       ; $EB9E  SID voice 1 pulse width high
        RTS                             ; $EBA1  back
; Command 1.
fx_cmd_note:
        JSR fx_note                     ; $EBA2  delay and note
        STY $EB01                       ; $EBA5  the next row
        RTS                             ; $EBA8  back
; Command 2.
fx_cmd_note_wave:
        JSR fx_note                     ; $EBA9  delay and note
        JSR fx_wave                     ; $EBAC  the waveform
        STY $EB01                       ; $EBAF  the next row
        RTS                             ; $EBB2  back
; Command 3.
fx_cmd_adsr:
        JSR fx_note                     ; $EBB3  delay and note
        JSR fx_adsr                     ; $EBB6  the envelope
        JSR fx_wave                     ; $EBB9  the waveform
        STY $EB01                       ; $EBBC  the next row
        RTS                             ; $EBBF  back
; Command 4.
fx_cmd_full:
        JSR fx_note                     ; $EBC0  delay and note
        JSR fx_adsr                     ; $EBC3  the envelope
        JSR fx_pulse                    ; $EBC6  the pulse width
        JSR fx_wave                     ; $EBC9  the waveform
        STY $EB01                       ; $EBCC  the next row
        RTS                             ; $EBCF  back
; Commands 5 and 6.
fx_cmd_pulse:
        JSR fx_note                     ; $EBD0  delay and note
        JSR fx_pulse                    ; $EBD3  the pulse width
        JSR fx_wave                     ; $EBD6  the waveform
        STY $EB01                       ; $EBD9  the next row
        RTS                             ; $EBDC  back
; Command 7. The waveform alone.
fx_cmd_wave:
        INY                             ; $EBDD  past the command byte
        JSR fx_wave                     ; $EBDE  the waveform
        STY $EB01                       ; $EBE1  the next row. The delay was left at 0
        RTS                             ; $EBE4  back

; $EBE5  15 pointers, sounds $80 through $8E. The id is shifted left.
; $EC03  the command offsets, 00 03 06 ... 27. A command byte indexes it
;        unmasked, so a byte from 8 would land past the eight JMPs. No
;        script has one.
; $EC11  ADSR pairs, by byte offset: 00 11 97, 02 00 F0, 04 89 00,
;        06 09 40, 08 08 00. Offsets $0A and $0C read on into the pulse
;        table, 0C 07 and 02 08. The scripts use both.
; $EC1B  pulse pairs, low then high, by byte offset: 00 070C, 02 0802,
;        04 04CE, 06 019A, 08 0334, 0A 01EC, 0C 011F, 0E 00CD, 10 0052,
;        12 007B, 14 0668.
; $EC31  the scripts, to $EE82.
;
; A script is a list of rows. A row's first byte is the command, 0-7.
; Commands 1-6 carry the delay and the note, then the ADSR offset (3, 4),
; the pulse offset (4, 5, 6), and the waveform (2-6), in that order. 7 is
; the waveform alone and leaves the delay at 0, so the next row waits 256
; calls. A delay of 0 would also wait 256. 0 ends the script. The delay
; counts calls of voice_N, one a screen, and a row's sound lasts that long.
; The end zeroes the frequency and frees the slot. The waveform and gate
; stay, so the envelope holds, but the oscillator has stopped. Each row
; below is delay:note. The last column is the length in screens.
;   $80 $EC31  noise 81, ADSR 00 F0. 1:3D. The movement chirp, score_blip. 1
;   $81 $EC37  pulse 41, ADSR 89 00, width 070C. 8:0B 16:0D 4:0C 4:0B.
;              Yamo leaving state $10, and the $1D blink.                 32
;   $82 $EC47  pulse 41, ADSR 11 97, width 0802. 1:3D, then 46 3E 4A 44
;              4D 46 49 3D 4D 46 44 one screen each. Both spawns, through
;              blip_and_return.                                           12
;   $83 $EC7A  noise 81, ADSR 09 40. 1:49 1:55 1:54 1:55 1:31 1:0D. $54
;              and $55 nearly stop the oscillator. Nothing loads it.       6
;   $84 $EC90  noise 81, ADSR 11 97. 5:26 4:2B 4:2E, then 31 35 39 3D 41 44
;              49 one each, and 1:55. Rising. The flying kick.            21
;   $85 $ECBE  noise 81, ADSR 11 97. 2E 2E 31 35 39 3D one each. The
;              ninja's strike.                                             6
;   $86 $ECD8  noise 81, ADSR 00 F0. 1:55, nearly still, so the first
;              screen is the attack alone. Then 31 14 0D 01. hit_sound.    5
;   $87 $ECEC  triangle 11, ADSR 11 97. 25 29 2C 31 38 3D 49 50 one each.
;              The strike connect.                                         8
;   $88 $ED0E  pulse, ADSR 00 F0, width 04CE. Each of 4F 4A 47 43 3E 3B 37
;              32 is one screen gated, 41, and one ungated, 40. Then 38 for
;              two and two. Nothing loads it.                             20
;   $89 $ED59  pulse 41, ADSR 02 08, width 007B. 1:3D. slide_sound.        1
;   $8A $ED60  the long door. play_sound_8a. 16:00 with waveform 00, no
;              sound. Then ADSR 00 F0 and tri+pulse 51 for 2:00 2:00
;              2:0C 2:0C 2:0C 2:0C 1:0D 1:0E 1:00. Then ADSR 08 00, width
;              0334, pulse 41 for 47:48, which decays with the gate on, and
;              1:48 ungated. The idle handover uses this same effect.     79
;   $8B $ED8E  ADSR 11 97. Note 52 twelve screens, the waveform swapping
;              between noise 81 and tri+pulse 51, then 29 and 22 noise.
;              Room 18's death flash.                                     14
;   $8C $EDC8  ADSR 11 97. 26 and 25 by turns for nine screens. The first
;              26 and every 25 are pulse 41, the width narrowing 01EC
;              011F 00CD 0052 0052. The other 26s are tri+pulse 51. Then
;              25 24 22 20 1D tri+pulse. The shock of the hot tiles. Room
;              18 returns before it.                                      14
;   $8D $EE07  noise 81, ADSR 0C 07. 4:10 1:34 1:4C 1:28 96:10. The
;              crumble. The last row is the long tail of the decay.      103
;   $8E $EE19  saw 21, ADSR 11 97. One screen each: 3C 2B 30 27 2B twice,
;              3A 29 2E 25 29 twice, 3C 2B 30 27 2B 3C. The lamp, and the
;              room 16 ying-yang.                                         26
; $EE83  a script no pointer names: noise 81, tri+pulse 51, and pulse 41
;        by turns, one screen each, with the width changing on the pulse
;        rows. 19 screens. It starts with command 2, so it would keep the
;        ADSR of the last sound. $EED6 is a second copy of $8E.
; $EF40  stale code, an older sprite_hits_contact from CMP #$1A on. It
;        reads $4DE2,Y and $00BC,Y where the game reads $4F40,Y and
;        $00BF,Y, and has no CMP #$1B after the second load. Nothing jumps
;        here. $EF70 is voice_2's slot.
; Rows 51 and 41 without a pulse offset use whatever width that SID voice
; last held, so $8A and $8B sound a little different by voice.

; Same program as voice_1, on SID voice 2 at $D407. Slot $EF70,
; pointer $F8/$F9, delay $EF72, index $EF71. The BCC branches to
; itself until a command stores the offset.
voice_2:
        LDA $EF70                       ; $EF73  the slot
        BNE voice_2_active              ; $EF76  in use
voice_2_done:
        RTS                             ; $EF78  free
voice_2_active:
        BPL voice_2_tick                ; $EF79  running
        ASL A                           ; $EF7B  id times 2. Bit 7 drops out
        TAX                             ; $EF7C  the index
        LDA $EBE5,X                     ; $EF7D  script pointer, low
        STA $F8                         ; $EF80  the script pointer, low
        LDA $EBE6,X                     ; $EF82  script pointer, high
        STA $F9                         ; $EF85  high
        LDY #$01                        ; $EF87  1
        STY $EF72                       ; $EF89  delay 1: the first row runs on this call
        STY $EF70                       ; $EF8C  running
        DEY                             ; $EF8F  0
        STY $D40B                       ; $EF90  gate off, before the first row gates it again
        STY $EF71                       ; $EF93  row index 0
voice_2_tick:
        DEC $EF72                       ; $EF96  the delay
        BNE voice_2_done                ; $EF99  still waiting
        LDY $EF71                       ; $EF9B  the row index
        LDA ($F8),Y                     ; $EF9E  the command
        TAX                             ; $EFA0  the index
        LDA $EC03,X                     ; $EFA1  its offset
        STA $EFA9                       ; $EFA4  rewrites a byte of the instruction at $EFA8
        CLC                             ; $EFA7  carry clear
voice_2_dispatch:
        BCC voice_2_dispatch            ; $EFA8  always
; Same eight commands as voice_1, in the same order.
        JMP v2_end                      ; $EFAA  command 0, the end
        JMP v2_cmd_note                 ; $EFAD  command 1, a note
        JMP v2_cmd_note_wave            ; $EFB0  command 2, a note and its waveform
        JMP v2_cmd_adsr                 ; $EFB3  command 3, with an envelope
        JMP v2_cmd_full                 ; $EFB6  command 4, with an envelope and pulse width
        JMP v2_cmd_pulse                ; $EFB9  command 5, with pulse width
        JMP v2_cmd_pulse                ; $EFBC  command 6, the same
        JMP v2_cmd_wave                 ; $EFBF  command 7, the waveform alone
; fx_note for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_note:
        INY                             ; $EFC2  past the command
        LDA ($F8),Y                     ; $EFC3  the delay
        STA $EF72                       ; $EFC5  counted from the next call
        INY                             ; $EFC8  the next byte
        LDA ($F8),Y                     ; $EFC9  the note
        TAX                             ; $EFCB  the index
        LDA $E200,X                     ; $EFCC  frequency low
        STA $D407                       ; $EFCF  SID voice 2 frequency low
        LDA $E254,X                     ; $EFD2  frequency high
        STA $D408                       ; $EFD5  SID voice 2 frequency high
        INY                             ; $EFD8  the next field
        RTS                             ; $EFD9  back
; fx_adsr for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_adsr:
        LDA ($F8),Y                     ; $EFDA  pair offset
        TAX                             ; $EFDC  the index
        LDA $EC11,X                     ; $EFDD  attack and decay
        STA $D40C                       ; $EFE0  SID voice 2 attack and decay
        LDA $EC12,X                     ; $EFE3  sustain and release
        STA $D40D                       ; $EFE6  SID voice 2 sustain and release
        INY                             ; $EFE9  the next field
        RTS                             ; $EFEA  back
; fx_wave for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_wave:
        LDA ($F8),Y                     ; $EFEB  the waveform
        STA $D40B                       ; $EFED  SID voice 2 waveform and gate
        INY                             ; $EFF0  the next field
        RTS                             ; $EFF1  back
; fx_end for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_end:
        LDA #$00                        ; $EFF2  zero
        STA $D407                       ; $EFF4  SID voice 2 frequency low
        STA $D408                       ; $EFF7  SID voice 2 frequency high
        STA $EF70                       ; $EFFA  slot free
        STA $EF71                       ; $EFFD  row index 0
        RTS                             ; $F000  back
; fx_pulse for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_pulse:
        LDA ($F8),Y                     ; $F001  pair offset
        INY                             ; $F003  the next field
        TAX                             ; $F004  the index
        LDA $EC1B,X                     ; $F005  width low
        STA $D409                       ; $F008  SID voice 2 pulse width low
        LDA $EC1C,X                     ; $F00B  width high
        STA $D40A                       ; $F00E  SID voice 2 pulse width high
        RTS                             ; $F011  back
; Command 1 for voice 2.
v2_cmd_note:
        JSR v2_note                     ; $F012  delay and note
        STY $EF71                       ; $F015  the next row
        RTS                             ; $F018  back
; Command 2 for voice 2.
v2_cmd_note_wave:
        JSR v2_note                     ; $F019  delay and note
        JSR v2_wave                     ; $F01C  the waveform
        STY $EF71                       ; $F01F  the next row
        RTS                             ; $F022  back
; Command 3 for voice 2.
v2_cmd_adsr:
        JSR v2_note                     ; $F023  delay and note
        JSR v2_adsr                     ; $F026  the envelope
        JSR v2_wave                     ; $F029  the waveform
        STY $EF71                       ; $F02C  the next row
        RTS                             ; $F02F  back
; Command 4 for voice 2.
v2_cmd_full:
        JSR v2_note                     ; $F030  delay and note
        JSR v2_adsr                     ; $F033  the envelope
        JSR v2_pulse                    ; $F036  the pulse width
        JSR v2_wave                     ; $F039  the waveform
        STY $EF71                       ; $F03C  the next row
        RTS                             ; $F03F  back
; Commands 5 and 6 for voice 2.
v2_cmd_pulse:
        JSR v2_note                     ; $F040  delay and note
        JSR v2_pulse                    ; $F043  the pulse width
        JSR v2_wave                     ; $F046  the waveform
        STY $EF71                       ; $F049  the next row
        RTS                             ; $F04C  back
; Command 7 for voice 2.
v2_cmd_wave:
        INY                             ; $F04D  past the command byte
        JSR v2_wave                     ; $F04E  the waveform
        STY $EF71                       ; $F051  the next row. The delay was left at 0
        RTS                             ; $F054  back

; Same program as voice_1, on SID voice 3 at $D40E. Slot $F070,
; pointer $FA/$FB, delay $F072, index $F071. The BCC branches to
; itself until a command stores the offset.
voice_3:
        LDA $F070                       ; $F073  the slot
        BNE voice_3_active              ; $F076  in use
voice_3_done:
        RTS                             ; $F078  free
voice_3_active:
        BPL voice_3_tick                ; $F079  running
        ASL A                           ; $F07B  id times 2. Bit 7 drops out
        TAX                             ; $F07C  the index
        LDA $EBE5,X                     ; $F07D  script pointer, low
        STA $FA                         ; $F080  the script pointer, low
        LDA $EBE6,X                     ; $F082  script pointer, high
        STA $FB                         ; $F085  high
        LDY #$01                        ; $F087  1
        STY $F072                       ; $F089  delay 1: the first row runs on this call
        STY $F070                       ; $F08C  running
        DEY                             ; $F08F  0
        STY $D412                       ; $F090  gate off, before the first row gates it again
        STY $F071                       ; $F093  row index 0
voice_3_tick:
        DEC $F072                       ; $F096  the delay
        BNE voice_3_done                ; $F099  still waiting
        LDY $F071                       ; $F09B  the row index
        LDA ($FA),Y                     ; $F09E  the command
        TAX                             ; $F0A0  the index
        LDA $EC03,X                     ; $F0A1  its offset
        STA $F0A9                       ; $F0A4  rewrites a byte of the instruction at $F0A8
        CLC                             ; $F0A7  carry clear
voice_3_dispatch:
        BCC voice_3_dispatch            ; $F0A8  always
; Same eight commands as voice_1, in the same order.
        JMP v3_end                      ; $F0AA  command 0, the end
        JMP v3_cmd_note                 ; $F0AD  command 1, a note
        JMP v3_cmd_note_wave            ; $F0B0  command 2, a note and its waveform
        JMP v3_cmd_adsr                 ; $F0B3  command 3, with an envelope
        JMP v3_cmd_full                 ; $F0B6  command 4, with an envelope and pulse width
        JMP v3_cmd_pulse                ; $F0B9  command 5, with pulse width
        JMP v3_cmd_pulse                ; $F0BC  command 6, the same
        JMP v3_cmd_wave                 ; $F0BF  command 7, the waveform alone
; fx_note for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_note:
        INY                             ; $F0C2  past the command
        LDA ($FA),Y                     ; $F0C3  the delay
        STA $F072                       ; $F0C5  counted from the next call
        INY                             ; $F0C8  the next byte
        LDA ($FA),Y                     ; $F0C9  the note
        TAX                             ; $F0CB  the index
        LDA $E200,X                     ; $F0CC  frequency low
        STA $D40E                       ; $F0CF  SID voice 3 frequency low
        LDA $E254,X                     ; $F0D2  frequency high
        STA $D40F                       ; $F0D5  SID voice 3 frequency high
        INY                             ; $F0D8  the next field
        RTS                             ; $F0D9  back
; fx_adsr for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_adsr:
        LDA ($FA),Y                     ; $F0DA  pair offset
        TAX                             ; $F0DC  the index
        LDA $EC11,X                     ; $F0DD  attack and decay
        STA $D413                       ; $F0E0  SID voice 3 attack and decay
        LDA $EC12,X                     ; $F0E3  sustain and release
        STA $D414                       ; $F0E6  SID voice 3 sustain and release
        INY                             ; $F0E9  the next field
        RTS                             ; $F0EA  back
; fx_wave for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_wave:
        LDA ($FA),Y                     ; $F0EB  the waveform
        STA $D412                       ; $F0ED  SID voice 3 waveform and gate
        INY                             ; $F0F0  the next field
        RTS                             ; $F0F1  back
; fx_end for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_end:
        LDA #$00                        ; $F0F2  zero
        STA $D40E                       ; $F0F4  SID voice 3 frequency low
        STA $D40F                       ; $F0F7  SID voice 3 frequency high
        STA $F070                       ; $F0FA  slot free
        STA $F071                       ; $F0FD  row index 0
        RTS                             ; $F100  back
; fx_pulse for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_pulse:
        LDA ($FA),Y                     ; $F101  pair offset
        INY                             ; $F103  the next field
        TAX                             ; $F104  the index
        LDA $EC1B,X                     ; $F105  width low
        STA $D410                       ; $F108  SID voice 3 pulse width low
        LDA $EC1C,X                     ; $F10B  width high
        STA $D411                       ; $F10E  SID voice 3 pulse width high
        RTS                             ; $F111  back
; Command 1 for voice 3.
v3_cmd_note:
        JSR v3_note                     ; $F112  delay and note
        STY $F071                       ; $F115  the next row
        RTS                             ; $F118  back
; Command 2 for voice 3.
v3_cmd_note_wave:
        JSR v3_note                     ; $F119  delay and note
        JSR v3_wave                     ; $F11C  the waveform
        STY $F071                       ; $F11F  the next row
        RTS                             ; $F122  back
; Command 3 for voice 3.
v3_cmd_adsr:
        JSR v3_note                     ; $F123  delay and note
        JSR v3_adsr                     ; $F126  the envelope
        JSR v3_wave                     ; $F129  the waveform
        STY $F071                       ; $F12C  the next row
        RTS                             ; $F12F  back
; Command 4 for voice 3.
v3_cmd_full:
        JSR v3_note                     ; $F130  delay and note
        JSR v3_adsr                     ; $F133  the envelope
        JSR v3_pulse                    ; $F136  the pulse width
        JSR v3_wave                     ; $F139  the waveform
        STY $F071                       ; $F13C  the next row
        RTS                             ; $F13F  back
; Commands 5 and 6 for voice 3.
v3_cmd_pulse:
        JSR v3_note                     ; $F140  delay and note
        JSR v3_pulse                    ; $F143  the pulse width
        JSR v3_wave                     ; $F146  the waveform
        STY $F071                       ; $F149  the next row
        RTS                             ; $F14C  back
; Command 7 for voice 3.
v3_cmd_wave:
        INY                             ; $F14D  past the command byte
        JSR v3_wave                     ; $F14E  the waveform
        STY $F071                       ; $F151  the next row. The delay was left at 0
        RTS                             ; $F154  back

