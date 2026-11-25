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
        LDX #$07                        ; $0466
boot_patch_glyphs:
        LDA #$FF                        ; $0468
        STA $8900,X                     ; $046A
        LDA #$03                        ; $046D
        STA $8A10,X                     ; $046F
        LDA #$C0                        ; $0472
        STA $8AB0,X                     ; $0474
        DEX                             ; $0477
        BPL boot_patch_glyphs           ; $0478
        LDA #$7F                        ; $047A
        STA $F3                         ; $047C
        LDA #$00                        ; $047E
        STA $04                         ; $0480
        LDA #$90                        ; $0482
        STA $05                         ; $0484
        LDA #$00                        ; $0486
        STA $06                         ; $0488
        STA $08                         ; $048A
        LDA #$A0                        ; $048C
        STA $07                         ; $048E
        LDA #$A4                        ; $0490
        STA $09                         ; $0492
        JSR expand_charset              ; $0494
        LDA #$7F                        ; $0497
        STA $F3                         ; $0499
        LDA #$00                        ; $049B
        STA $04                         ; $049D
        LDA #$94                        ; $049F
        STA $05                         ; $04A1
        LDA #$00                        ; $04A3
        STA $06                         ; $04A5
        STA $08                         ; $04A7
        LDA #$A8                        ; $04A9
        STA $07                         ; $04AB
        LDA #$AC                        ; $04AD
        STA $09                         ; $04AF
        JSR expand_charset              ; $04B1
        LDA #$7F                        ; $04B4
        STA $F3                         ; $04B6
        LDA #$00                        ; $04B8
        STA $04                         ; $04BA
        LDA #$98                        ; $04BC
        STA $05                         ; $04BE
        LDA #$00                        ; $04C0
        STA $06                         ; $04C2
        STA $08                         ; $04C4
        LDA #$B0                        ; $04C6
        STA $07                         ; $04C8
        LDA #$B4                        ; $04CA
        STA $09                         ; $04CC
        JSR expand_charset              ; $04CE
        LDA #$7F                        ; $04D1
        STA $F3                         ; $04D3
        LDA #$00                        ; $04D5
        STA $04                         ; $04D7
        LDA #$9C                        ; $04D9
        STA $05                         ; $04DB
        LDA #$00                        ; $04DD
        STA $06                         ; $04DF
        STA $08                         ; $04E1
        LDA #$B8                        ; $04E3
        TAX                             ; $04E5
        TXS                             ; $04E6
        STA $07                         ; $04E7
        LDA #$BC                        ; $04E9
        STA $09                         ; $04EB
        JSR expand_charset              ; $04ED
        JSR build_sprites               ; $04F0
        JSR empty_hook                  ; $04F3
        LDA #$35                        ; $04F6
        STA $01                         ; $04F8
        LDA #$F0                        ; $04FA
        STA $D028                       ; $04FC  sprite 1 color
        STA $D02A                       ; $04FF  sprite 3 color
        STA $D02B                       ; $0502  sprite 4 color
        LDA #$F7                        ; $0505
        STA $D027                       ; $0507  sprite 0 color
        LDA #$F5                        ; $050A
        STA $D029                       ; $050C  sprite 2 color

; Cold start. The screen is turned off until the room is ready.
; boot falls into here. The per-room pointers enter_room walks are in
; rooms.asm.
start:
        SEI                             ; $050F
        CLD                             ; $0510
        LDX #$FD                        ; $0511
        TXS                             ; $0513
        LDA $D011                       ; $0514  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0517
        STA $D011                       ; $0519  VIC control: yscroll, 25 rows, raster bit 8
        JSR reset_music                 ; $051C
        LDA #$00                        ; $051F
        STA $16                         ; $0521
        LDA #$02                        ; $0523
        STA $17                         ; $0525
        SEI                             ; $0527
        JSR clear_work_ram              ; $0528
        JSR init_hardware               ; $052B
        JMP open_room                   ; $052E
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
        SEI                             ; $0531
        LDA $D011                       ; $0532  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0535
        STA $D011                       ; $0537  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $053A
        STA $D015                       ; $053C  sprite enable
        STA $D000                       ; $053F  sprite 0 x
        STA $D001                       ; $0542  sprite 0 y
; $E30A = 1 would make service_tune silence itself. reset_music
; clears that flag and the SID. The tune does not follow into play.
        LDA #$01                        ; $0545
        STA $E30A                       ; $0547
        JSR reset_music                 ; $054A
        LDX #$FD                        ; $054D
        TXS                             ; $054F
        JSR clear_work_ram              ; $0550
        JSR init_hardware               ; $0553
        LSR $0104                       ; $0556
        LDA $42C9                       ; $0559
        STA $42CB                       ; $055C
        LDA $42CA                       ; $055F
        STA $42CC                       ; $0562
        LDA #$00                        ; $0565
        STA $42CA                       ; $0567
        STA $42C9                       ; $056A
        JSR enter_room                  ; $056D
        LDA #$00                        ; $0570
        STA $1D                         ; $0572
        LDA #$F3                        ; $0574
        STA $1E                         ; $0576
        JSR show_screen                 ; $0578
        NOP                             ; $057B
        NOP                             ; $057C
        NOP                             ; $057D
        NOP                             ; $057E
        NOP                             ; $057F
        CLI                             ; $0580
        JMP frame                       ; $0581
; Options page. Screen off, then the logo from the four rows at $49BD, the
; three prompt strings, and the highlight on F3, 1 PLAYER, F5, COMPUTER, and
; F7. Sprite 0 is the TM mark: twelve bytes from $0E40, X-expanded, at
; $83C0+$0C. The raster is game_over_raster, which keeps charset $8000 and
; multicolor on through row 9 and switches at raster $82. $49/$4A start at
; $0960, 2400 frames. title_loop returns on F7 or the button; the timeout
; jumps to attract_demo instead, which skips the PLAYER page.
open_room:
        SEI                             ; $0584
        LDA $D011                       ; $0585  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0588
        STA $D011                       ; $058A  VIC control: yscroll, 25 rows, raster bit 8
        JSR silence_sid                 ; $058D
        LDA #$00                        ; $0590
        STA $0100                       ; $0592
        JSR clear_playfield             ; $0595
        JSR tm_dummy_read               ; $0598
        LDX #$3F                        ; $059B
        LDA #$00                        ; $059D
open_room_clear_tm:
        STA $83C0,X                     ; $059F
        DEX                             ; $05A2
        BPL open_room_clear_tm          ; $05A3
        LDA #$01                        ; $05A5
        STA $D015                       ; $05A7  sprite enable
        STA $D01D                       ; $05AA  sprite double width
        STA $D010                       ; $05AD  sprite x bit 8
        LDA #$00                        ; $05B0
        STA $D017                       ; $05B2  sprite double height
        STA $D01B                       ; $05B5  sprite behind the background
        STA $D01C                       ; $05B8  sprite multicolor
        LDA #$0A                        ; $05BB
        STA $D000                       ; $05BD  sprite 0 x
        LDA #$56                        ; $05C0
        STA $D001                       ; $05C2  sprite 0 y
        LDA #$FF                        ; $05C5
        STA $D027                       ; $05C7  sprite 0 color
        LDA #$0F                        ; $05CA
        STA $8FF8                       ; $05CC
        LDX #$0B                        ; $05CF
; Four rows of the TM sprite, placed on sprite image $0F.
copy_tm:
        LDA $0E40,X                     ; $05D1
        STA $83CC,X                     ; $05D4
        DEX                             ; $05D7
        BPL copy_tm                     ; $05D8
        LDA #$2C                        ; $05DA
        STA $0408                       ; $05DC
        LDA #$15                        ; $05DF
        STA $0409                       ; $05E1
        LDA #$01                        ; $05E4
        STA $D01A                       ; $05E6  VIC interrupt enable
        STA $D019                       ; $05E9  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $05EC  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $05EF
        STA $D011                       ; $05F1  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FD                        ; $05F4
        STA $D012                       ; $05F6  raster line
        LDA #$F6                        ; $05F9
        STA $D020                       ; $05FB  border color
        STA $D021                       ; $05FE  background color
        LDA #$FF                        ; $0601
        STA $D022                       ; $0603  background multicolor 1
        STA $D023                       ; $0606  background multicolor 2
        LDX #$08                        ; $0609
        STX $D016                       ; $060B  VIC control: xscroll, multicolor
        JSR fill_color_ram              ; $060E
        LDX #$00                        ; $0611
open_room_blank_rows:
        LDA #$F1                        ; $0613
        STA $D9E0,X                     ; $0615  color RAM, row 12 column 0, plus X
        STA $DAE0,X                     ; $0618  color RAM, row 18 column 16, plus X
        LDA #$DC                        ; $061B
        STA $8C00,X                     ; $061D
        STA $8C68,X                     ; $0620
        DEX                             ; $0623
        BNE open_room_blank_rows        ; $0624
        LDX #$27                        ; $0626
; Logo rows. Bit 7 selects the upper half of the $8000 charset, $8400-$87FF. $4A0D is
; character row 2, $49BD row 5, $49E5 row 6, $4A35 row 9.
copy_logo:
        LDA $4A0D,X                     ; $0628
        ORA #$80                        ; $062B
        STA $8C50,X                     ; $062D
        LDA $49BD,X                     ; $0630
        ORA #$80                        ; $0633
        STA $8CC8,X                     ; $0635
        LDA $49E5,X                     ; $0638
        ORA #$80                        ; $063B
        STA $8CF0,X                     ; $063D
        LDA $4A35,X                     ; $0640
        ORA #$80                        ; $0643
        STA $8D68,X                     ; $0645
        DEX                             ; $0648
        BPL copy_logo                   ; $0649
        LDA #$FF                        ; $064B
        STA $0100                       ; $064D
        LDA #$4F                        ; $0650
        LDX #$06                        ; $0652
        LDY #$31                        ; $0654
        JSR print_string                ; $0656
        LDA #$50                        ; $0659
        LDX #$07                        ; $065B
        LDY #$2B                        ; $065D
        JSR print_string                ; $065F
        LDA #$51                        ; $0662
        LDX #$08                        ; $0664
        LDY #$31                        ; $0666
        JSR print_string                ; $0668
        LDX #$09                        ; $066B
; Highlight the default choices. ADC #$40 sets bit 6, the inverse glyph.
; X = 0 and 1 also cover the F of F3, F5, and F7. The wider run is 1 PLAYER
; and COMPUTER. 2 PLAYERS, OPPONENT, and the dash stay plain.
highlight_menu:
        LDA $8DF0,X                     ; $066D
        CLC                             ; $0670
        ADC #$40                        ; $0671
        STA $8DF0,X                     ; $0673
        LDA $8E40,X                     ; $0676
        CLC                             ; $0679
        ADC #$40                        ; $067A
        STA $8E40,X                     ; $067C
        CPX #$02                        ; $067F
        BCS highlight_next              ; $0681
        LDA $8DEB,X                     ; $0683
        CLC                             ; $0686
        ADC #$40                        ; $0687
        STA $8DEB,X                     ; $0689
        LDA $8E3B,X                     ; $068C
        CLC                             ; $068F
        ADC #$40                        ; $0690
        STA $8E3B,X                     ; $0692
        LDA $8E8B,X                     ; $0695
        CLC                             ; $0698
        ADC #$40                        ; $0699
        STA $8E8B,X                     ; $069B
highlight_next:
        DEX                             ; $069E
        BPL highlight_menu              ; $069F
        LDA $42CB                       ; $06A1
        STA $42C9                       ; $06A4
        LDA $42CC                       ; $06A7
        STA $42CA                       ; $06AA
        LDA $42C9                       ; $06AD
        BEQ open_room_check_f5          ; $06B0
        JSR flip_menu_a                 ; $06B2
open_room_check_f5:
        LDA $42CA                       ; $06B5
        BEQ open_room_tune              ; $06B8
        JSR flip_menu_b                 ; $06BA
open_room_tune:
; $1385 nonzero skips the tune. The title picture is not this page.
; $09BB counts down. Below zero it is reloaded with 4, $E314 is set
; to 3 (walk the sequence and loop), $E870 is tune 0, $E871 is $FF
; (then restart), and start_tune runs.
        LDA $1385                       ; $06BD
        BNE open_room_check_bytes       ; $06C0
        DEC $09BB                       ; $06C2
        BPL open_room_check_bytes       ; $06C5
        LDA #$04                        ; $06C7
        STA $09BB                       ; $06C9
        LDA #$03                        ; $06CC
        STA $E314                       ; $06CE
        LDX #$00                        ; $06D1
        STX $E870                       ; $06D3
        DEX                             ; $06D6
        STX $E871                       ; $06D7
        JSR start_tune                  ; $06DA
open_room_check_bytes:
        LDX #$00                        ; $06DD
        LDA $CF8F,X                     ; $06DF
        EOR $CFB1,X                     ; $06E2
        EOR $CF90,X                     ; $06E5
        EOR $CFAF,X                     ; $06E8
        EOR $CF91,X                     ; $06EB
        EOR $CFB0,X                     ; $06EE
        BEQ open_room_show              ; $06F1
; The check of the bytes around $CF8F failed. Stay here and walk ($1D) forward.
checksum_hang:
        STA ($1D),Y                     ; $06F3
        INC $1E                         ; $06F5
        JMP checksum_hang               ; $06F7
open_room_show:
        LDA #$09                        ; $06FA
        STA $4A                         ; $06FC
        LDA #$60                        ; $06FE
        STA $49                         ; $0700
        JSR show_screen                 ; $0702
        NOP                             ; $0705
        NOP                             ; $0706
        NOP                             ; $0707
        NOP                             ; $0708
        NOP                             ; $0709
        CLI                             ; $070A
        JSR title_loop                  ; $070B
        SEI                             ; $070E
        LDA $D011                       ; $070F  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0712
        STA $D011                       ; $0714  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $0717
        STA $D015                       ; $0719  sprite enable
        STA $D000                       ; $071C  sprite 0 x
        STA $D001                       ; $071F  sprite 0 y
        STA $03                         ; $0722
; Same stop as attract_demo. Leaving the options page silences the tune.
        LDA #$01                        ; $0724
        STA $E30A                       ; $0726
        JSR reset_music                 ; $0729
        LDA $42C9                       ; $072C
        STA $42CB                       ; $072F
        LDA $42CA                       ; $0732
        STA $42CC                       ; $0735
        JSR between_rooms               ; $0738
        LDA $D011                       ; $073B  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $073E
        STA $D011                       ; $0740  VIC control: yscroll, 25 rows, raster bit 8
        LDX #$FD                        ; $0743
        TXS                             ; $0745
; A new game. clear_work_ram zeroes $03-$F5, so the noise pointer $16/$17
; starts over at $0000, and the six interrupts before the first frame leave
; $16 and $7F at 6 and the visit clock $87 at 4. Every new game therefore
; reads the same noise for the same input. $4E97/$4E98 and the rest of page
; 1 above $0107 keep what the options page left.
        JSR clear_work_ram              ; $0746
        JSR init_hardware               ; $0749
        JSR enter_room                  ; $074C
; ($1D) points at $F300 in play too, not only in the attract demo.
        LDA #$00                        ; $074F
        STA $1D                         ; $0751
        LDA #$F3                        ; $0753
        STA $1E                         ; $0755
        JSR show_screen                 ; $0757
        NOP                             ; $075A
        NOP                             ; $075B
        NOP                             ; $075C
        NOP                             ; $075D
        NOP                             ; $075E
        CLI                             ; $075F
        JMP frame                       ; $0760
; VIC bank $8000, multicolor on, sprites expanded in X. Then the row pointers, the score
; row, and the room tables.
init_hardware:
        LDA #$00                        ; $0763
        STA $8B                         ; $0765
        STA $8C                         ; $0767
        JSR arm_raster                  ; $0769
        JSR init_cia                    ; $076C
        LDA #$FF                        ; $076F
        STA $4B                         ; $0771
        LDY #$8B                        ; $0773
        LDA #$D8                        ; $0775
        JSR build_row_pointers          ; $0777
        LDA #$00                        ; $077A
        STA $4338                       ; $077C
        STA $4360                       ; $077F
        STA $4361                       ; $0782
        LDA #$8C                        ; $0785
        STA $434C                       ; $0787
        LDA #$CE                        ; $078A
        STA $4374                       ; $078C
        STA $4375                       ; $078F
        JSR clear_playfield             ; $0792
        LDA #$F8                        ; $0795
        JSR fill_color_ram              ; $0797
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
        LDX #$27                        ; $079A
init_top_rows:
        LDA #$00                        ; $079C
        STA $D800,X                     ; $079E  color RAM, row 0 column 0, plus X
        STA $D828,X                     ; $07A1  color RAM, row 1 column 0, plus X
        LDA #$20                        ; $07A4
        STA $8C00,X                     ; $07A6
        LDA #$06                        ; $07A9
        STA $8C50,X                     ; $07AB
        CPX #$08                        ; $07AE
        BCS init_top_next               ; $07B0
        LDA #$0F                        ; $07B2
        STA $8FF8,X                     ; $07B4
        LDA #$FF                        ; $07B7
        STA $8900,X                     ; $07B9
init_top_next:
        DEX                             ; $07BC
        BPL init_top_rows               ; $07BD
        LDA #$00                        ; $07BF
        TAX                             ; $07C1
init_clear_sprites:
        STA $8180,X                     ; $07C2
        STA $8280,X                     ; $07C5
        STA $8300,X                     ; $07C8
        INX                             ; $07CB
        BNE init_clear_sprites          ; $07CC
        LDX #$03                        ; $07CE
init_border_colors:
        LDA $479B,X                     ; $07D0
        STA $D020,X                     ; $07D3  border color, plus X
        DEX                             ; $07D6
        BPL init_border_colors          ; $07D7
        LDA #$01                        ; $07D9
        STA $DD00                       ; $07DB  CIA 2 port A: VIC bank
        LDA #$38                        ; $07DE
        STA $D018                       ; $07E0  screen and charset address
        STA $F2                         ; $07E3
        LDA #$18                        ; $07E5
        STA $D016                       ; $07E7  VIC control: xscroll, multicolor
        LDA #$00                        ; $07EA
        STA $D015                       ; $07EC  sprite enable
        STA $D017                       ; $07EF  sprite double height
        STA $D01B                       ; $07F2  sprite behind the background
        STA $D01C                       ; $07F5  sprite multicolor
        LDA #$FF                        ; $07F8
        STA $D01D                       ; $07FA  sprite double width
        LDA #$80                        ; $07FD
        JSR draw_score                  ; $07FF
        JSR draw_top                    ; $0802
; $43BD starts at $11. timed_caption decrements it to $10 and prints the
; player word, so the score row comes up with "1UP" or "2UP" already there.
        LDA #$11                        ; $0805
        STA $43BD                       ; $0807
        JSR timed_caption               ; $080A
        JSR print_top_word              ; $080D
        JSR print_falls_word            ; $0810
        JSR lives_to_bcd                ; $0813
; Countdown and copy count for scroll_surface. The first call copies, and
; that copy does not move the delay slot. $64 is 0 in the opening snapshot,
; which is the picture expand_charset wrote.
        LDA #$01                        ; $0816
        STA $60                         ; $0818
        STA $66                         ; $081A
        LDX #$04                        ; $081C
        LDA #$FF                        ; $081E
init_clear_voice_owners:
        STA $4F40,X                     ; $0820
        DEX                             ; $0823
        BPL init_clear_voice_owners     ; $0824
        LDX #$00                        ; $0826
        LDA #$00                        ; $0828
        JMP wake_actor                  ; $082A
; Turn off CIA interrupts, enable the raster interrupt, and open the SID noise channel that
; the effects use. The vector is raster_irq and the compare starts at raster $FB.
arm_raster:
        LDA #$7F                        ; $082D
        STA $DD0D                       ; $082F  CIA 2 interrupt control
        STA $DC0D                       ; $0832  CIA 1 interrupt control
        LDA $DD0D                       ; $0835  CIA 2 interrupt control
        LDA $DC0D                       ; $0838  CIA 1 interrupt control
        CLD                             ; $083B
        LDA #$C1                        ; $083C
        STA $0408                       ; $083E
        LDA #$48                        ; $0841
        STA $0409                       ; $0843
        LDA #$01                        ; $0846
        STA $D01A                       ; $0848  VIC interrupt enable
        STA $D019                       ; $084B  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $084E  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $0851
        STA $D011                       ; $0853  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FB                        ; $0856
        STA $D012                       ; $0858  raster line
        LDA #$FF                        ; $085B
        STA $D40E                       ; $085D  SID voice 3 frequency low
        STA $D40F                       ; $0860  SID voice 3 frequency high
        LDA #$80                        ; $0863
        STA $D412                       ; $0865  SID voice 3 waveform and gate
        RTS                             ; $0868
; A is the low byte and Y the high byte of the first row. Builds 13 pointers, each $50
; bytes (two character rows) after the last.
build_row_pointers:
        LDX #$00                        ; $0869
        STA $4338                       ; $086B
        STY $434C                       ; $086E
build_even_rows:
        LDA $4338,X                     ; $0871
        CLC                             ; $0874
        ADC #$50                        ; $0875
        STA $4339,X                     ; $0877
        LDA $434C,X                     ; $087A
        ADC #$00                        ; $087D
        STA $434D,X                     ; $087F
        INX                             ; $0882
        CPX #$0D                        ; $0883
        BCC build_even_rows             ; $0885
        LDA $4338                       ; $0887
        CLC                             ; $088A
        ADC #$28                        ; $088B
        STA $4360                       ; $088D
        LDA $434C                       ; $0890
        ADC #$00                        ; $0893
        STA $4374                       ; $0895
        LDX #$00                        ; $0898
build_odd_rows:
        LDA $4360,X                     ; $089A
        CLC                             ; $089D
        ADC #$50                        ; $089E
        STA $4361,X                     ; $08A0
        LDA $4374,X                     ; $08A3
        ADC #$00                        ; $08A6
        STA $4375,X                     ; $08A8
        INX                             ; $08AB
        CPX #$0D                        ; $08AC
        BCC build_odd_rows              ; $08AE
        RTS                             ; $08B0
; Wait on the options page. $49/$4A count down once a frame in game_over_raster.
; At 0 this jumps to attract_demo and never reaches the PLAYER page. A fresh
; key in $0109 is dispatched. The button is bit 4 of $DC01, active low.
; Key codes, after AND #$7F: F7 is 3, F3 is 5, F5 is 6. Bit 7 of $0109 is Shift.
title_loop:
        LDA $49                         ; $08B1
        ORA $4A                         ; $08B3
        BNE title_read_key              ; $08B5
        JMP attract_demo                ; $08B7
title_read_key:
        LDA #$00                        ; $08BA
        STA $010E                       ; $08BC
        JSR read_stick                  ; $08BF
        LDA $010C                       ; $08C2
        BEQ title_check_wipe            ; $08C5
        LDA #$00                        ; $08C7
        STA $010C                       ; $08C9
        LDA $0109                       ; $08CC
        JMP title_key                   ; $08CF
; F7, F5, F3. Anything else falls through to the button test.
menu_key:
        AND #$7F                        ; $08D2
        CMP #$03                        ; $08D4
        BEQ menu_start                  ; $08D6
        CMP #$06                        ; $08D8
        BEQ menu_f5                     ; $08DA
        CMP #$05                        ; $08DC
        BEQ menu_f3                     ; $08DE
title_check_wipe:
        LDA $4A                         ; $08E0
        CMP #$08                        ; $08E2
        BNE title_check_button          ; $08E4
        LDA $49                         ; $08E6
        CMP #$02                        ; $08E8
        BCS title_check_button          ; $08EA
; String $0E is spaces. It wipes the handedness line once the count is at
; $0800 or $0801, which is 351 screens, about seven seconds, after the last
; option key. Only row 10 from column 2 is wiped, the same 36 cells.
        LDA #$0E                        ; $08EC
        LDX #$0A                        ; $08EE
        LDY #$02                        ; $08F0
        JSR print_string                ; $08F2
title_check_button:
        LDA $DC01                       ; $08F5  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $08F8
        BNE title_loop                  ; $08FA
; F7 or the joystick button. $48 is 16 frames of debounce, counted by the raster.
menu_start:
        JSR wait_button_up              ; $08FC
        LDA #$10                        ; $08FF
        STA $48                         ; $0901
menu_start_wait:
        LDA $48                         ; $0903
        BNE menu_start_wait             ; $0905
        RTS                             ; $0907
; F5. $42CA is 0 for the computer and 1 for a human opponent. $42CC keeps a copy.
menu_f5:
        LDA $42CA                       ; $0908
        EOR #$01                        ; $090B
        STA $42CA                       ; $090D
        STA $42CC                       ; $0910
        JSR flip_menu_b                 ; $0913
; Let the key up, put the 2400-frame timeout back, and pause four frames.
menu_settle:
        JSR wait_button_up              ; $0916
        LDA #$09                        ; $0919
        STA $4A                         ; $091B
        LDA #$60                        ; $091D
        STA $49                         ; $091F
        LDA #$04                        ; $0921
        STA $48                         ; $0923
menu_settle_wait:
        LDA $48                         ; $0925
        BNE menu_settle_wait            ; $0927
        JMP title_loop                  ; $0929
; F3. $42C9 is 0 for one player and 1 for two. $42CB keeps a copy.
menu_f3:
        LDA $42C9                       ; $092C
        EOR #$01                        ; $092F
        STA $42C9                       ; $0931
        STA $42CB                       ; $0934
        JSR flip_menu_a                 ; $0937
        JSR wait_button_up              ; $093A
        LDA #$09                        ; $093D
        STA $4A                         ; $093F
        LDA #$60                        ; $0941
        STA $49                         ; $0943
        LDA #$04                        ; $0945
        STA $48                         ; $0947
        BNE menu_settle_wait            ; $0949
; Stay here while either joystick button is still down.
wait_button_up:
        LDA $DC00                       ; $094B  CIA 1 port A: joystick 2, keyboard columns
        AND $DC01                       ; $094E  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $0951
        BEQ wait_button_up              ; $0953
        RTS                             ; $0955
; Handedness. L is $2A and R is $11. Shift sets bit 7, so Shift-L is $AA and
; Shift-R is $91. $1383 is port 1 and $1384 is port 2. 0 is left-handed, which
; rotates the stick through the table at $4A85. 1 is right-handed, the stick as read.
; The four strings are $08, $0A, $09, and $0D.
title_key:
        CMP #$2A                        ; $0956
        BEQ joy1_left                   ; $0958
        CMP #$AA                        ; $095A
        BEQ joy2_left                   ; $095C
        CMP #$11                        ; $095E
        BEQ joy1_right                  ; $0960
        CMP #$91                        ; $0962
        BEQ joy2_right                  ; $0964
        JMP menu_key                    ; $0966
; L. Joystick 1, left-handed.
joy1_left:
        LDA #$08                        ; $0969
        LDX #$0A                        ; $096B
        LDY #$02                        ; $096D
        JSR print_string                ; $096F
        LDA #$00                        ; $0972
        STA $1383                       ; $0974
        BEQ hand_done                   ; $0977
; Shift-L. Joystick 2, left-handed.
joy2_left:
        LDA #$0A                        ; $0979
        TAX                             ; $097B
        LDY #$02                        ; $097C
        JSR print_string                ; $097E
        LDA #$00                        ; $0981
        STA $1384                       ; $0983
        BEQ hand_done                   ; $0986
; R. Joystick 1, right-handed.
joy1_right:
        LDA #$09                        ; $0988
        LDX #$0A                        ; $098A
        LDY #$02                        ; $098C
        JSR print_string                ; $098E
        LDA #$01                        ; $0991
        STA $1383                       ; $0993
        BNE hand_done                   ; $0996
; Shift-R. Joystick 2, right-handed.
joy2_right:
        LDA #$0D                        ; $0998
        LDX #$0A                        ; $099A
        LDY #$02                        ; $099C
        JSR print_string                ; $099E
        LDA #$01                        ; $09A1
        STA $1384                       ; $09A3
hand_done:
        JMP menu_settle                 ; $09A6
; Write A through all four pages of color RAM, $D800 to $DBFF.
fill_color_ram:
        LDX #$00                        ; $09A9
fill_color_loop:
        STA $D800,X                     ; $09AB  color RAM, row 0 column 0, plus X
        STA $D900,X                     ; $09AE  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $09B1  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $09B4  color RAM, row 19 column 8, plus X
        INX                             ; $09B7
        BNE fill_color_loop             ; $09B8
        RTS                             ; $09BA
        .byte $04

; Blank the screen and load room $29. $42CA set means a human opponent.
; Yamo's wake count $5E is forced to 8 here, ahead of the room table.
; try_yamo and load_yamo_count store $30 when he appears and when he is
; knocked out. $42CA clear, after the idle handover, uses the table again.
enter_room:
        LDA $D011                       ; $09BC  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $09BF
        STA $D011                       ; $09C1  VIC control: yscroll, 25 rows, raster bit 8
        LDA $D015                       ; $09C4  sprite enable
        AND #$1F                        ; $09C7
; $47 is the actors' sprites. $0B3B writes it back after the unpack.
; Sprites are blank until then. room_11_to_13 restores $47 before it
; calls enter_room_at, so the second entry saves this mask and not 0.
        STA $47                         ; $09C9
        LDA #$00                        ; $09CB
        STA $D015                       ; $09CD  sprite enable
        LDX #$27                        ; $09D0
        LDA #$20                        ; $09D2
enter_room_black_bar:
        STA $8C00,X                     ; $09D4
        DEX                             ; $09D7
        BPL enter_room_black_bar        ; $09D8
        LDX $29                         ; $09DA
        LDA $47A0,X                     ; $09DC
        LDX #$00                        ; $09DF
; $D878 is character row 3. Rows 0 and 1 keep the black written at $079C.
; Row 2 keeps the $F8 from fill_color_ram, which is multicolor black.
; hook_enter_19 runs later and stores 0 over the $20 just written on row 0.
enter_room_fill_color:
        STA $D878,X                     ; $09E1  color RAM, row 3 column 0, plus X
        STA $D900,X                     ; $09E4  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $09E7  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $09EA  color RAM, row 19 column 8, plus X
        INX                             ; $09ED
        BNE enter_room_fill_color       ; $09EE
        JSR blank_sparks                ; $09F0
        JSR silence_sid                 ; $09F3
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
        LDA $29                         ; $09F6
        CMP #$0B                        ; $09F8
        BNE enter_room_body             ; $09FA
        LDA $36                         ; $09FC
        ORA $38                         ; $09FE
        ORA $3A                         ; $0A00
        BNE enter_room_body             ; $0A02
        LDA $47                         ; $0A04
        STA $D015                       ; $0A06  sprite enable
        LDX #$0D                        ; $0A09
        JMP enter_room_at               ; $0A0B
; Every room except the room 13 shortcut. X becomes room*2 + player, the
; index of this player's entry flag at $0300.
enter_room_body:
        LDA $29                         ; $0A0E
        ASL A                           ; $0A10
        ADC $03                         ; $0A11
        TAX                             ; $0A13
; $0300 + room*2 + player. A nonzero flag pays 2000, $07 into score byte 1
; and $D0 into byte 2, and the LSR spends it. The two adds are separate, so
; check_life_mark runs between them. rearm_room_bonus puts the flags back
; when the treasure room ends. Room 0's flag stays clear. room_11_to_13 has
; already switched a cleared room 11 over to room 13, so this pays room 13
; and leaves room 11's flag unspent.
        LDA $0300,X                     ; $0A14
        BEQ enter_room_clear_steps      ; $0A17
        LSR $0300,X                     ; $0A19
        LDA #$07                        ; $0A1C
        LDX #$01                        ; $0A1E
        JSR add_score                   ; $0A20
        LDA #$D0                        ; $0A23
        LDX #$02                        ; $0A25
        JSR add_score                   ; $0A27
enter_room_clear_steps:
        LDA #$00                        ; $0A2A
        LDY #$83                        ; $0A2C
enter_room_clear_loop:
        STA $4F57,Y                     ; $0A2E
        DEY                             ; $0A31
        BPL enter_room_clear_loop       ; $0A32
; Visit clock. Both bytes start at 0, so treasure_stick begins on up and
; test_visit reports a fresh room. See count_visit.
        STA $87                         ; $0A34
        STA $88                         ; $0A36
; scroll_surface direction and delay slot. 0 moves the picture up. Slot 7
; is the last byte of $4CB2, an $08. $60, $64, and $66 keep running.
        STA $65                         ; $0A38
        LDA #$07                        ; $0A3A
        STA $4321                       ; $0A3C
        LDX $29                         ; $0A3F
        LDA $4C9E,X                     ; $0A41
        STA $7A                         ; $0A44
        BEQ enter_room_wake_counts      ; $0A46
        LDA #$00                        ; $0A48
        STA $8B                         ; $0A4A
        STA $8C                         ; $0A4C
enter_room_wake_counts:
        LDA $130B,X                     ; $0A4E
        STA $5D                         ; $0A51
        LDA $1347,X                     ; $0A53
        STA $5E                         ; $0A56
        LDA $40                         ; $0A58
        BEQ enter_room_check_opponent   ; $0A5A
        LDA #$03                        ; $0A5C
        STA $5D                         ; $0A5E
        STA $5E                         ; $0A60
enter_room_check_opponent:
; Human opponent. Actor 1's wake count $5E is 8 instead of the room's value.
        LDA $42CA                       ; $0A62
        BEQ enter_room_reset_bruce      ; $0A65
        LDA #$08                        ; $0A67
        STA $5E                         ; $0A69
enter_room_reset_bruce:
        LDA #$01                        ; $0A6B
        STA hit                         ; $0A6D
        LDA #$04                        ; $0A6F
        STA timer                       ; $0A71
        LDA #$00                        ; $0A73
        STA $4FDE                       ; $0A75
        STA $4FDF                       ; $0A78
        STA $4FE0                       ; $0A7B
        STA state                       ; $0A7E
        STA $0106                       ; $0A80
        LDA $29                         ; $0A83
        ASL A                           ; $0A85
        TAX                             ; $0A86
        LDA $4AA8,X                     ; $0A87
        STA $06                         ; $0A8A
        LDA $4AA9,X                     ; $0A8C
        STA $07                         ; $0A8F
        LDY #$13                        ; $0A91
enter_room_copy_colors:
        LDA ($06),Y                     ; $0A93
        STA $0153,Y                     ; $0A95
        DEY                             ; $0A98
        BPL enter_room_copy_colors      ; $0A99
        ; $D018 follows the room. Below $0A the value is $38, charset $A000.
        ; Room $12 is $3C, charset $B000. Every other room is $3A, charset
        ; $A800. $B800 is expanded at startup and never selected here.
        ; boot expands each bank once. scroll_surface writes into the bank
        ; selected here, and this routine does not expand it again.
        LDA #$38                        ; $0A9B
        LDX $29                         ; $0A9D
        CPX #$0A                        ; $0A9F
        BCC enter_room_store_charset    ; $0AA1
        CPX #$12                        ; $0AA3
        BEQ enter_room_charset_18       ; $0AA5
        LDA #$3A                        ; $0AA7
        BNE enter_room_store_charset    ; $0AA9
enter_room_charset_18:
        LDA #$3C                        ; $0AAB
enter_room_store_charset:
        STA $F2                         ; $0AAD
        LDA $4B34,X                     ; $0AAF
        STA $06                         ; $0AB2
        LDA $4B49,X                     ; $0AB4
        STA $07                         ; $0AB7
        LDA #$78                        ; $0AB9
        STA $04                         ; $0ABB
        STA $10                         ; $0ABD
        LDA #$A0                        ; $0ABF
        STA $08                         ; $0AC1
        STA $12                         ; $0AC3
        LDA #$8C                        ; $0AC5
        STA $05                         ; $0AC7
        STA $09                         ; $0AC9
        LDA #$D8                        ; $0ACB
        STA $11                         ; $0ACD
        STA $13                         ; $0ACF
        LDA #$27                        ; $0AD1
        STA $F3                         ; $0AD3
        LDY #$00                        ; $0AD5
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
        LDA ($06),Y                     ; $0AD7
        BPL unpack_run                  ; $0AD9
        AND #$7F                        ; $0ADB
        BEQ unpack_done                 ; $0ADD
        TAX                             ; $0ADF
        JSR step_ptr_06                 ; $0AE0
unpack_literal:
        LDA ($06),Y                     ; $0AE3
        BPL unpack_literal_store        ; $0AE5
        JSR bright_cell                 ; $0AE7
unpack_literal_store:
        STA ($04),Y                     ; $0AEA
        ORA #$80                        ; $0AEC
        STA ($08),Y                     ; $0AEE
        JSR step_ptr_04                 ; $0AF0
        JSR step_ptr_06                 ; $0AF3
        JSR step_ptr_08                 ; $0AF6
        JSR step_ptr_10                 ; $0AF9
        JSR step_ptr_12                 ; $0AFC
        JSR unpack_next_row             ; $0AFF
        DEX                             ; $0B02
        BNE unpack_literal              ; $0B03
        BEQ unpack_command              ; $0B05
unpack_run:
        TAX                             ; $0B07
        JSR step_ptr_06                 ; $0B08
unpack_run_cell:
        LDA ($06),Y                     ; $0B0B
        BPL unpack_run_store            ; $0B0D
        JSR bright_cell                 ; $0B0F
unpack_run_store:
        STA ($04),Y                     ; $0B12
        ORA #$80                        ; $0B14
        STA ($08),Y                     ; $0B16
        JSR step_ptr_04                 ; $0B18
        JSR step_ptr_08                 ; $0B1B
        JSR step_ptr_10                 ; $0B1E
        JSR step_ptr_12                 ; $0B21
        JSR unpack_next_row             ; $0B24
        DEX                             ; $0B27
        BNE unpack_run_cell             ; $0B28
        JSR step_ptr_06                 ; $0B2A
        JMP unpack_command              ; $0B2D
unpack_done:
        JSR point_lamp_list             ; $0B30
        JSR show_screen                 ; $0B33
        NOP                             ; $0B36
        NOP                             ; $0B37
        NOP                             ; $0B38
        NOP                             ; $0B39
        NOP                             ; $0B3A
        LDA $47                         ; $0B3B
        STA $D015                       ; $0B3D  sprite enable
        JMP run_frame_hook              ; $0B40
; Advance ($04) by one, the same as step_ptr_04. swap_room_lamps uses it
; to walk the waiting player's flags at $0340.
step_ptr_04b:
        INC $04                         ; $0B43
        BNE step_ptr_04b_done           ; $0B45
        INC $05                         ; $0B47
step_ptr_04b_done:
        RTS                             ; $0B49

; $0B4A  7 bytes that no instruction reaches. They decode as a second copy
; of step_ptr_06: INC $06, BNE +2, INC $07, RTS.

; Advance ($10) by one. The unpack's upper color cell.
step_ptr_10:
        INC $10                         ; $0B51
        BNE step_ptr_10_done            ; $0B53
        INC $11                         ; $0B55
step_ptr_10_done:
        RTS                             ; $0B57
; Advance ($12) by one. The unpack's lower color cell.
step_ptr_12:
        INC $12                         ; $0B58
        BNE step_ptr_12_done            ; $0B5A
        INC $13                         ; $0B5C
step_ptr_12_done:
        RTS                             ; $0B5E
; A packed tile with bit 7 set. Color $F8 goes on both color rows, over
; the room fill, and A comes back as the tile without bit 7.
bright_cell:
        PHA                             ; $0B5F
        LDA #$F8                        ; $0B60
        STA ($10),Y                     ; $0B62
        STA ($12),Y                     ; $0B64
        PLA                             ; $0B66
        AND #$7F                        ; $0B67
        RTS                             ; $0B69

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
        ORA #$01                        ; $0B8E
        STA active,X                    ; $0B90
        ROL A                           ; $0B92
        ROL A                           ; $0B93
        ROL A                           ; $0B94
        AND #$03                        ; $0B95
        TAY                             ; $0B97
        STY $52                         ; $0B98
        LDA $59A8,Y                     ; $0B9A
        STA $EC,X                       ; $0B9D
        JSR claim_voice_slot            ; $0B9F
        LDY $52                         ; $0BA2
        LDA $59AB,Y                     ; $0BA4
        STA $EF,X                       ; $0BA7
        BEQ wake_reset_fields           ; $0BA9
        JSR claim_voice_slot            ; $0BAB
wake_reset_fields:
        LDY $52                         ; $0BAE
        LDA #$00                        ; $0BB0
        STA state,X                     ; $0BB2
        STA timer,X                     ; $0BB4
        STA $0106,X                     ; $0BB6
        LDA #$0F                        ; $0BB9
        STA $98,X                       ; $0BBB
        LDA #$01                        ; $0BBD
        STA $9B,X                       ; $0BBF
        LDA #$01                        ; $0BC1
        STA hit,X                       ; $0BC3
        LDA #$01                        ; $0BC5
        STA facing,X                    ; $0BC7
        LDA #$02                        ; $0BC9
        STA $4F48,X                     ; $0BCB
        STA $4F4E,X                     ; $0BCE
        LDA #$03                        ; $0BD1
        STA $4F4B,X                     ; $0BD3
        STA $4F51,X                     ; $0BD6
        LDA #$24                        ; $0BD9
        STA $D1,X                       ; $0BDB
        STX $51                         ; $0BDD
        LDA $0104                       ; $0BDF
        BEQ main_spawn                  ; $0BE2
        TXA                             ; $0BE4
        BNE spawn_pick_side             ; $0BE5
; The room's first spawn point, xpos from $4BAE+room and ypos from
; $4BC2+room. spawn_store_position stores them for the actor saved in $51.
main_spawn:
        LDX $29                         ; $0BE7
        LDA $4BC2,X                     ; $0BE9
        TAY                             ; $0BEC
        LDA $4BAE,X                     ; $0BED
spawn_store_position:
        LDX $51                         ; $0BF0
        STA xpos,X                      ; $0BF2
        TYA                             ; $0BF4
        STA ypos,X                      ; $0BF5
        JMP spawn_place_sprites         ; $0BF7
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
        LDA $8A,X                       ; $0BFA
        BNE spawn_resume                ; $0BFC
        CPX #$01                        ; $0BFE
        BNE ninja_side                  ; $0C00
        LDX $29                         ; $0C02
        LDA $136F,X                     ; $0C04
        BEQ toss_side                   ; $0C07
        JSR noise_byte                  ; $0C09
        CMP #$C0                        ; $0C0C
        BCS toss_side                   ; $0C0E
        LDA $136F,X                     ; $0C10
        BPL main_spawn                  ; $0C13
        BMI alt_spawn                   ; $0C15
; A fresh noise byte picks the side: bit 0 clear is main_spawn, set is
; alt_spawn.
toss_side:
        JSR noise_byte                  ; $0C17
        AND #$01                        ; $0C1A
        BEQ main_spawn                  ; $0C1C
; The room's second spawn point, xpos from $4BD6+room and ypos from
; $4BEA+room.
alt_spawn:
        LDX $29                         ; $0C1E
        LDA $4BEA,X                     ; $0C20
        TAY                             ; $0C23
        LDA $4BD6,X                     ; $0C24
        JMP spawn_store_position        ; $0C27
; The ninja's side choice. $1333+room of 0 tosses. Otherwise a noise byte
; of $C0 or more tosses, and a smaller one lets bit 7 of $136F+room decide:
; clear is main_spawn, set is alt_spawn. $136F is the table Yamo reads too.
ninja_side:
        LDX $29                         ; $0C2A
        LDA $1333,X                     ; $0C2C
        BEQ toss_side                   ; $0C2F
        JSR noise_byte                  ; $0C31
        CMP #$C0                        ; $0C34
        BCS toss_side                   ; $0C36
        LDA $136F,X                     ; $0C38
        BPL main_spawn                  ; $0C3B
        BMI alt_spawn                   ; $0C3D
spawn_resume:
        STA xpos,X                      ; $0C3F
        LDA $8C,X                       ; $0C41
        STA ypos,X                      ; $0C43
        LDA $8E,X                       ; $0C45
        STA $D1,X                       ; $0C47
        LDA #$00                        ; $0C49
        STA $8A,X                       ; $0C4B
spawn_place_sprites:
        LDA $276D,X                     ; $0C4D
        LDY $277D                       ; $0C50
        BEQ spawn_set_pointers          ; $0C53
        CLC                             ; $0C55
        ADC #$05                        ; $0C56
spawn_set_pointers:
        TAY                             ; $0C58
        LDA $2763,Y                     ; $0C59
        LDY $276D,X                     ; $0C5C
        STA $8FF8,Y                     ; $0C5F
        INY                             ; $0C62
        CLC                             ; $0C63
        ADC #$01                        ; $0C64
        STA $8FF8,Y                     ; $0C66
        LDA xpos,X                      ; $0C69
        ASL A                           ; $0C6B
        PHA                             ; $0C6C
        LDY $276D,X                     ; $0C6D
        LDA $D010                       ; $0C70  sprite x bit 8
        BCC spawn_clear_x_high          ; $0C73
        ORA $2773,Y                     ; $0C75
        BNE spawn_store_x_high          ; $0C78
spawn_clear_x_high:
        AND $2778,Y                     ; $0C7A
spawn_store_x_high:
        STA $D010                       ; $0C7D  sprite x bit 8
        TYA                             ; $0C80
        ASL A                           ; $0C81
        TAY                             ; $0C82
        PLA                             ; $0C83
        STA $D000,Y                     ; $0C84  sprite 0 x, plus Y
        LDA ypos,X                      ; $0C87
        CLC                             ; $0C89
        ADC #$1D                        ; $0C8A
        STA $D001,Y                     ; $0C8C  sprite 0 y, plus Y
        LDA $2770,X                     ; $0C8F
        BMI spawn_enable_sprites        ; $0C92
        LDA xpos,X                      ; $0C94
        ASL A                           ; $0C96
        PHA                             ; $0C97
        LDY $2770,X                     ; $0C98
        LDA $D010                       ; $0C9B  sprite x bit 8
        BCC spawn_clear_x_high2         ; $0C9E
        ORA $2773,Y                     ; $0CA0
        BNE spawn_store_x_high2         ; $0CA3
spawn_clear_x_high2:
        AND $2778,Y                     ; $0CA5
spawn_store_x_high2:
        STA $D010                       ; $0CA8  sprite x bit 8
        TYA                             ; $0CAB
        ASL A                           ; $0CAC
        TAY                             ; $0CAD
        PLA                             ; $0CAE
        STA $D000,Y                     ; $0CAF  sprite 0 x, plus Y
        LDA ypos,X                      ; $0CB2
        CLC                             ; $0CB4
        ADC #$1D                        ; $0CB5
        STA $D001,Y                     ; $0CB7  sprite 0 y, plus Y
spawn_enable_sprites:
        LDY $276D,X                     ; $0CBA
        LDA $D015                       ; $0CBD  sprite enable
        ORA $2773,Y                     ; $0CC0
        STA $D015                       ; $0CC3  sprite enable
        LDY $2770,X                     ; $0CC6
        BMI spawn_done                  ; $0CC9
        LDA $D015                       ; $0CCB  sprite enable
        ORA $2773,Y                     ; $0CCE
        STA $D015                       ; $0CD1  sprite enable
spawn_done:
        RTS                             ; $0CD4
; Actor 1. Active becomes $81. State $10, timer $0A. $D1 above $14 is
; brought down to $14. The four stores name libraries $2A/$2B and absolute
; $6C/$6D. choose_pose runs before blit_sprites and writes $4F4E from state
; $10, so the picture drawn is relative library $2A.
spawn_yamo:
        JSR blip_and_return             ; $0CD5
        LDA $CF79                       ; $0CD8
        EOR $CF99                       ; $0CDB
        STA $1166                       ; $0CDE
        LDX #$01                        ; $0CE1
        LDA #$80                        ; $0CE3
        JSR wake_actor                  ; $0CE5
        LDA #$10                        ; $0CE8
        STA state,X                     ; $0CEA
        LDA #$2A                        ; $0CEC
        STA $4F48,X                     ; $0CEE
        LDA #$2B                        ; $0CF1
        STA $4F4B,X                     ; $0CF3
        LDA #$6C                        ; $0CF6
        STA $4F4E,X                     ; $0CF8
        LDA #$6D                        ; $0CFB
        STA $4F51,X                     ; $0CFD
        LDA #$0A                        ; $0D00
        STA timer,X                     ; $0D02
        LDA $D1,X                       ; $0D04
        CMP #$14                        ; $0D06
        BCC spawn_yamo_done             ; $0D08
        LDA #$14                        ; $0D0A
        STA $D1,X                       ; $0D0C
spawn_yamo_done:
        RTS                             ; $0D0E
; Wake Yamo when $5E has reached 0 and actor 1's active bit 0 is
; clear. $135B for this room is then stored back into $5E. $42CA set
; replaces that with $30. test_visit: V set (long, $88 >= $20) or $40 set
; stores 3, carry set (middle, $88 >= $19) halves it, and a short visit
; leaves the table byte.
try_yamo:
        LDA $5E                         ; $0D0F
        BNE try_yamo_done               ; $0D11
        LDX #$01                        ; $0D13
        LDA active,X                    ; $0D15
        AND #$01                        ; $0D17
        BNE try_yamo_done               ; $0D19
        JSR spawn_yamo                  ; $0D1B
        LDX $29                         ; $0D1E
        LDA $135B,X                     ; $0D20
        STA $5E                         ; $0D23
; Human opponent reloads actor 1's count with $30.
        LDA $42CA                       ; $0D25
        BEQ try_yamo_visit              ; $0D28
        LDA #$30                        ; $0D2A
        STA $5E                         ; $0D2C
try_yamo_visit:
        JSR test_visit                  ; $0D2E
        BVS yamo_soon                   ; $0D31
        BCS try_yamo_halve              ; $0D33
        LDA $40                         ; $0D35
        BNE yamo_soon                   ; $0D37
        RTS                             ; $0D39
try_yamo_halve:
        LSR $5E                         ; $0D3A
try_yamo_done:
        RTS                             ; $0D3C
; A long visit, or a finished game in $40: Yamo's next wake is in 3 frames.
yamo_soon:
        LDA #$03                        ; $0D3D
        STA $5E                         ; $0D3F
        RTS                             ; $0D41
; X = 1 reloads Yamo only. X = 2 branches to the ninja's count.
; Any other X, including the 0 finish_exit passes before a room starts,
; reloads both. retire_actor jumps here with the fighter who just left.
; The LDA $E000 is rewritten to $135B+room or $131F+room. The visit
; adjustments match try_yamo and try_ninja.
load_wake_counts:
        CPX #$01                        ; $0D42
        BNE load_wake_not_yamo          ; $0D44
; $5E = the byte at $135B+room, through the operand the stores above rewrite.
; A human opponent then stores $30 over it.
load_yamo_count:
        LDA #$5B                        ; $0D46
        CLC                             ; $0D48
        ADC $29                         ; $0D49
        STA $0D56                       ; $0D4B
        LDA #$13                        ; $0D4E
        ADC #$00                        ; $0D50
        STA $0D57                       ; $0D52
        LDA $E000                       ; $0D55
        STA $5E                         ; $0D58
; Same override when actor 1 is the one being restarted.
        LDA $42CA                       ; $0D5A
        BEQ load_yamo_visit             ; $0D5D
        LDA #$30                        ; $0D5F
        STA $5E                         ; $0D61
load_yamo_visit:
        JSR test_visit                  ; $0D63
        BVS yamo_soon                   ; $0D66
        BCS load_yamo_halve             ; $0D68
        LDA $40                         ; $0D6A
        BNE yamo_soon                   ; $0D6C
        RTS                             ; $0D6E
load_yamo_halve:
        LSR $5E                         ; $0D6F
        RTS                             ; $0D71
load_wake_not_yamo:
        CPX #$02                        ; $0D72
        BNE load_both_counts            ; $0D74
; $5D = the byte at $131F+room, the same way.
load_ninja_count:
        LDA #$1F                        ; $0D76
        CLC                             ; $0D78
        ADC $29                         ; $0D79
        STA $0D86                       ; $0D7B
        LDA #$13                        ; $0D7E
        ADC #$00                        ; $0D80
        STA $0D87                       ; $0D82
        LDA $E000                       ; $0D85
        STA $5D                         ; $0D88
        JSR test_visit                  ; $0D8A
        BVS ninja_soon                  ; $0D8D
        BCS load_ninja_halve            ; $0D8F
        LDA $40                         ; $0D91
        BNE ninja_soon                  ; $0D93
        RTS                             ; $0D95
load_ninja_halve:
        LSR $5D                         ; $0D96
        RTS                             ; $0D98
; A long visit, or a finished game in $40: the ninja's next wake is in 3 frames.
ninja_soon:
        LDA #$03                        ; $0D99
        STA $5D                         ; $0D9B
        RTS                             ; $0D9D
load_both_counts:
        JSR load_yamo_count             ; $0D9E
        JMP load_ninja_count            ; $0DA1
; frame calls this once per logic frame, and skips it while $7A is set.
; A count of 0 is left at 0, which is why a table byte of 0 wakes on the
; first check. Both counts move while the fighters are already on screen.
tick_wake_counts:
        LDA $5D                         ; $0DA4
        BEQ tick_yamo_count             ; $0DA6
        DEC $5D                         ; $0DA8
tick_yamo_count:
        LDA $5E                         ; $0DAA
        BEQ tick_wake_done              ; $0DAC
        DEC $5E                         ; $0DAE
tick_wake_done:
        RTS                             ; $0DB0
; Wake the ninja when $5D has reached 0 and actor 2's active bit 0 is clear.
; Bit 0 of $96 can hold that off: $40 clear, $42CA clear, and test_visit
; returning a short visit, a noise byte of $19 or more stores $10 back
; into $5D and returns. Otherwise $131F for this room is stored into $5D
; and the same visit adjustment as Yamo's is applied.
try_ninja:
        LDA $5D                         ; $0DB1
        BNE try_ninja_done              ; $0DB3
        LDA $96                         ; $0DB5
        AND #$01                        ; $0DB7
        BEQ try_ninja_wake              ; $0DB9
        LDA $40                         ; $0DBB
        BNE try_ninja_wake              ; $0DBD
        LDA $42CA                       ; $0DBF
        BNE try_ninja_wake              ; $0DC2
        JSR test_visit                  ; $0DC4
        BVS try_ninja_wake              ; $0DC7
        BCS try_ninja_wake              ; $0DC9
        JSR noise_byte                  ; $0DCB
        CMP #$19                        ; $0DCE
        BCC try_ninja_wake              ; $0DD0
        LDA #$10                        ; $0DD2
        STA $5D                         ; $0DD4
        RTS                             ; $0DD6
try_ninja_wake:
        LDX #$02                        ; $0DD7
        LDA active,X                    ; $0DD9
        AND #$01                        ; $0DDB
        BNE try_ninja_done              ; $0DDD
        JSR spawn_ninja                 ; $0DDF
        LDX $29                         ; $0DE2
        LDA $131F,X                     ; $0DE4
        STA $5D                         ; $0DE7
        JSR test_visit                  ; $0DE9
        BVS ninja_soon                  ; $0DEC
        BCS try_ninja_halve             ; $0DEE
        LDA $40                         ; $0DF0
        BNE ninja_soon                  ; $0DF2
        RTS                             ; $0DF4
try_ninja_halve:
        LSR $5D                         ; $0DF5
try_ninja_done:
        RTS                             ; $0DF7
; Actor 2. Active becomes $41. $D1 above 7 is brought down to 7. Timer
; $10 of state 0, so he stands until it expires. $4F4B and $4F51 are
; cleared: $2770 for actor 2 is $FF, and blit_sprites skips his second
; image on its own. $4F4E is set to $82. choose_pose on this same frame
; replaces it from state 0 before the blit. range_to_bruce and
; face_from_dx turn him toward Bruce. Bit 7 of $63 means Bruce is to his
; right.
spawn_ninja:
        JSR blip_and_return             ; $0DF8
        LDA #$40                        ; $0DFB
        JSR wake_actor                  ; $0DFD
        LDA #$82                        ; $0E00
        STA $4F4E,X                     ; $0E02
        LDA #$00                        ; $0E05
        STA $4F4B,X                     ; $0E07
        STA $4F51,X                     ; $0E0A
        LDA $D1,X                       ; $0E0D
        CMP #$07                        ; $0E0F
        BCC spawn_ninja_timer           ; $0E11
        LDA #$07                        ; $0E13
        STA $D1,X                       ; $0E15
spawn_ninja_timer:
        LDA #$10                        ; $0E17
        STA timer,X                     ; $0E19
        JSR range_to_bruce              ; $0E1B
        JMP face_from_dx                ; $0E1E
; A is an effect number of 3 or more. $59AE,A-3 picks a byte of $4F40,
; and X, the actor, is stored there.
; The room snapshots hold 04 00 01 02 03 01 02 04 08 10 at $59AE.
claim_voice_slot:
        SEC                             ; $0E21
        SBC #$03                        ; $0E22
        TAY                             ; $0E24
        LDA $59AE,Y                     ; $0E25
        TAY                             ; $0E28
        TXA                             ; $0E29
        STA $4F40,Y                     ; $0E2A
        RTS                             ; $0E2D
; Reads the five bytes at $0E3B and throws them away, keeping X. open_room
; calls it before the TM sprite is copied. It has no effect; it may be
; left from a check that was taken out.
tm_dummy_read:
        TXA                             ; $0E2E
        PHA                             ; $0E2F
        LDX #$04                        ; $0E30
tm_dummy_loop:
        LDA $0E3B,X                     ; $0E32
        DEX                             ; $0E35
        BPL tm_dummy_loop               ; $0E36
        PLA                             ; $0E38
        TAX                             ; $0E39
        RTS                             ; $0E3A

; $0E3B  5 bytes read and discarded by tm_dummy_read. $0E40 is 12 bytes, four rows of
; the TM sprite copied to $83CC.

; Flip bit 6 on the F5 row ($8E40, twenty bytes: row 14, columns 16-35), then
; draw the word selected by $42CA. $4D is the inverse dash and is left as it is.
flip_menu_b:
        LDX #$13                        ; $0E4C
flip_menu_b_loop:
        LDA $8E40,X                     ; $0E4E
        CMP #$4D                        ; $0E51
        BEQ flip_menu_b_next            ; $0E53
        EOR #$40                        ; $0E55
        STA $8E40,X                     ; $0E57
flip_menu_b_next:
        DEX                             ; $0E5A
        BPL flip_menu_b_loop            ; $0E5B
        LDX #$50                        ; $0E5D
        LDA $42CA                       ; $0E5F
        JMP draw_menu_word              ; $0E62
; Flip bit 6 on the F3 row ($8DF0, row 12, columns 16-35), then the word for $42C9.
flip_menu_a:
        LDX #$13                        ; $0E65
flip_menu_a_loop:
        LDA $8DF0,X                     ; $0E67
        CMP #$4D                        ; $0E6A
        BEQ flip_menu_a_next            ; $0E6C
        EOR #$40                        ; $0E6E
        STA $8DF0,X                     ; $0E70
flip_menu_a_next:
        DEX                             ; $0E73
        BPL flip_menu_a_loop            ; $0E74
        LDX #$00                        ; $0E76
        LDA $42C9                       ; $0E78
; X is 0 for the F3 row and $50 for the F5 row, one double-row lower. A = 0 keeps
; the first choice, 1 PLAYER or COMPUTER. A nonzero selects 2 PLAYERS or
; OPPONENT. The EOR above flips the letters. These four stores repair the
; key-cap glyphs and the extra S, which are not a plain inverse.
draw_menu_word:
        BNE menu_second_choice          ; $0E7B
        LDA #$42                        ; $0E7D
        STA $8DEF,X                     ; $0E7F
        LDA #$40                        ; $0E82
        STA $8DF8,X                     ; $0E84
        LDA #$56                        ; $0E87
        STA $8DFA,X                     ; $0E89
        LDA #$00                        ; $0E8C
        STA $8E04,X                     ; $0E8E
        RTS                             ; $0E91
; A nonzero: the glyphs for 2 PLAYERS or OPPONENT.
menu_second_choice:
        LDA #$00                        ; $0E92
        STA $8DEF,X                     ; $0E94
        LDA #$42                        ; $0E97
        STA $8DF8,X                     ; $0E99
        LDA #$40                        ; $0E9C
        STA $8DFA,X                     ; $0E9E
        LDA #$56                        ; $0EA1
        STA $8E04,X                     ; $0EA3
        RTS                             ; $0EA6
; PLAYER page. The whole screen is charset $8000, multicolor, background blue.
; $03 picks the player. His two digit glyphs are copied from $4A7D into the
; lines at $4A5D, and those lines are stored with bit 7 set at $8D24 and
; $8D4C, row 7 column 12 and row 8 column 12. The glyphs are multicolor pair
; 01, so the ink is $D022, which between_raster cycles. $48 starts at $40
; frames, or $80 when $42C9 is set. The raster decrements it. The countdown in
; $18/$19/$1A is longer than either of those, so the page ends on $48.
between_rooms:
        SEI                             ; $0EA7
        LDA $D011                       ; $0EA8  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $0EAB
        STA $D011                       ; $0EAD  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $0EB0
        STA $D015                       ; $0EB2  sprite enable
        LDA #$06                        ; $0EB5
        STA $D020                       ; $0EB7  border color
        STA $D021                       ; $0EBA  background color
        LDX #$00                        ; $0EBD
        LDA #$DC                        ; $0EBF
between_rooms_blank:
        STA $8C00,X                     ; $0EC1
        STA $8D00,X                     ; $0EC4
        STA $8E00,X                     ; $0EC7
        STA $8F00,X                     ; $0ECA
        INX                             ; $0ECD
        BNE between_rooms_blank         ; $0ECE
        JSR silence_sid                 ; $0ED0
        LDA $03                         ; $0ED3
        ASL A                           ; $0ED5
        TAX                             ; $0ED6
        LDY #$00                        ; $0ED7
; $4A7D is eight digit glyphs: player 1, then player 2, each line pair.
; X is $03 times 2. The first pair replaces columns 14-15 of line 1, the
; second pair the same columns of line 2.
patch_player_digits:
        LDA $4A7D,X                     ; $0ED9
        STA $4A6B,Y                     ; $0EDC
        LDA $4A81,X                     ; $0EDF
        STA $4A7B,Y                     ; $0EE2
        INX                             ; $0EE5
        INY                             ; $0EE6
        CPY #$02                        ; $0EE7
        BCC patch_player_digits         ; $0EE9
        LDX #$0F                        ; $0EEB
between_rooms_player_word:
        LDA $4A5D,X                     ; $0EED
        ORA #$80                        ; $0EF0
        STA $8D24,X                     ; $0EF2
        LDA $4A6D,X                     ; $0EF5
        ORA #$80                        ; $0EF8
        STA $8D4C,X                     ; $0EFA
        DEX                             ; $0EFD
        BPL between_rooms_player_word   ; $0EFE
        LDA #$A4                        ; $0F00  low byte of between_raster
        STA $0408                       ; $0F02
        LDA #$14                        ; $0F05
        STA $0409                       ; $0F07
        LDA #$01                        ; $0F0A
        STA $D01A                       ; $0F0C  VIC interrupt enable
        STA $D019                       ; $0F0F  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $0F12  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $0F15
        STA $D011                       ; $0F17  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$63                        ; $0F1A
        STA $D012                       ; $0F1C  raster line
        LDA #$30                        ; $0F1F
        STA $D018                       ; $0F21  screen and charset address
        LDA #$18                        ; $0F24
        STA $D016                       ; $0F26  VIC control: xscroll, multicolor
        JSR show_screen                 ; $0F29
        NOP                             ; $0F2C
        NOP                             ; $0F2D
        NOP                             ; $0F2E
        NOP                             ; $0F2F
        NOP                             ; $0F30
        CLI                             ; $0F31
        LDA #$80                        ; $0F32
        STA $18                         ; $0F34
        STA $19                         ; $0F36
        LDA #$03                        ; $0F38
        STA $1A                         ; $0F3A
        LDA #$40                        ; $0F3C
        STA $48                         ; $0F3E
        LDA $42C9                       ; $0F40
        BEQ player_page_wait            ; $0F43
        ASL $48                         ; $0F45
player_page_wait:
        LDA $48                         ; $0F47
        BEQ player_page_done            ; $0F49
        LDA $18                         ; $0F4B
        BEQ player_page_count_mid       ; $0F4D
        DEC $18                         ; $0F4F
        JMP player_page_test            ; $0F51
player_page_count_mid:
        LDA $19                         ; $0F54
        BEQ player_page_count_high      ; $0F56
        DEC $18                         ; $0F58
        DEC $19                         ; $0F5A
        JMP player_page_test            ; $0F5C
player_page_count_high:
        LDA $1A                         ; $0F5F
        BEQ player_page_test            ; $0F61
        DEC $18                         ; $0F63
        DEC $19                         ; $0F65
        DEC $1A                         ; $0F67
player_page_test:
        LDA $18                         ; $0F69
        ORA $19                         ; $0F6B
        ORA $1A                         ; $0F6D
        BNE player_page_wait            ; $0F6F
player_page_done:
        RTS                             ; $0F71
; Zero $03 through $F5, the nibble tables at $4EED, and the per-room slots
; at $0300. $28, $29, $40, and the score at $41-$43 are in that range, so a
; game that reaches here through open_room starts in room 0 with no score
; and difficulty 0. The top score at $4388 is not in the range and remains.
; Falls are then stored as 4, or 9 when $42CA is set, and the 40000 mark
; is copied back. $4E95 and $4E96, the extra-fall counters, go back to 5.
clear_work_ram:
        LDA #$00                        ; $0F72
        TAX                             ; $0F74
clear_work_loop:
        CPX #$F3                        ; $0F75
        BCS clear_work_nibbles          ; $0F77
        STA $03,X                       ; $0F79
clear_work_nibbles:
        CPX #$FB                        ; $0F7B
        BCS clear_work_next             ; $0F7D
        STA $4EED,X                     ; $0F7F
clear_work_next:
        INX                             ; $0F82
        BNE clear_work_loop             ; $0F83
        STA $89                         ; $0F85
        STA $8A                         ; $0F87
        LDX #$07                        ; $0F89
        LDA #$01                        ; $0F8B
clear_work_page1:
        STA $014B,X                     ; $0F8D
        STA $0100,X                     ; $0F90
        DEX                             ; $0F93
        BPL clear_work_page1            ; $0F94
        JSR silence_sid                 ; $0F96
        LDA #$05                        ; $0F99
        STA $4E95                       ; $0F9B
        STA $4E96                       ; $0F9E
        JSR copy_room_defaults          ; $0FA1
        LDX #$27                        ; $0FA4
        LDA #$01                        ; $0FA6
clear_work_room_flags:
        STA $0300,X                     ; $0FA8
        DEX                             ; $0FAB
        BPL clear_work_room_flags       ; $0FAC
        LDA #$00                        ; $0FAE
        STA $0300                       ; $0FB0
        STA $0301                       ; $0FB3
        JSR restore_lamps               ; $0FB6
        JSR fill_0340                   ; $0FB9
; Falls. 4 against the computer. 9 when $42CA is the human opponent.
; FALLS 00 is still a life. The count is Bruce's. Yamo has none, and his
; hits do not add to the score. The Remember trainer can turn the later
; DEC and INC of $28 into LDA.
        LDA #$04                        ; $0FBC
        STA $28                         ; $0FBE
        LDA $42CA                       ; $0FC0
        BEQ clear_work_marks            ; $0FC3
        LDA #$09                        ; $0FC5
        STA $28                         ; $0FC7
clear_work_marks:
; Extra-fall mark for both players. $438B in room00.vsf is 00 9C 40,
; 40000. $4392 is the live mark and $4395 is the other player's copy.
; The step added on a crossing sits at $438E: 00 75 30, 30000.
        LDX #$02                        ; $0FC9
clear_work_mark_loop:
        LDA $438B,X                     ; $0FCB
        STA $4392,X                     ; $0FCE
        STA $4395,X                     ; $0FD1
        DEX                             ; $0FD4
        BPL clear_work_mark_loop        ; $0FD5
        LDX #$1B                        ; $0FD7
clear_work_save_player:
        LDA $28,X                       ; $0FD9
        STA $439F,X                     ; $0FDB
        DEX                             ; $0FDE
        BPL clear_work_save_player      ; $0FDF
        RTS                             ; $0FE1
; Fill $0340-$03A0 with the value in A. Called with 1.
fill_0340:
        LDA #$01                        ; $0FE2
        LDX #$60                        ; $0FE4
fill_0340_loop:
        STA $0340,X                     ; $0FE6
        DEX                             ; $0FE9
        BPL fill_0340_loop              ; $0FEA
        RTS                             ; $0FEC
; Two players. Trade the live lamp-taken flags with the waiting player's
; copy at $0340, one room list at a time, rooms 0 through 19.
swap_waiting_lamps:
        LDA #$40                        ; $0FED
        STA $04                         ; $0FEF
        LDA #$03                        ; $0FF1
        STA $05                         ; $0FF3
        LDA #$00                        ; $0FF5
        STA $4E                         ; $0FF7
swap_waiting_room:
        ASL A                           ; $0FF9
        TAX                             ; $0FFA
        JSR swap_room_lamps             ; $0FFB
        INC $4E                         ; $0FFE
        LDA $4E                         ; $1000
        CMP #$14                        ; $1002
        BCC swap_waiting_room           ; $1004
        RTS                             ; $1006
; One room's list at $4CE2,X. Each four-byte record starts with a flag,
; and a record whose first byte has bit 7 set ends the list. The flag
; and the byte at ($04) change places, then ($04) steps one and ($0A)
; steps one record.
swap_room_lamps:
        LDA $4CE2,X                     ; $1007
        STA $0A                         ; $100A
        LDA $4CE3,X                     ; $100C
        STA $0B                         ; $100F
        LDY #$00                        ; $1011
swap_room_record:
        LDA ($0A),Y                     ; $1013
        BMI swap_room_done              ; $1015
        PHA                             ; $1017
        LDA ($04),Y                     ; $1018
        TAX                             ; $101A
        PLA                             ; $101B
        STA ($04),Y                     ; $101C
        TXA                             ; $101E
        STA ($0A),Y                     ; $101F
        JSR next_lamp_record            ; $1021
        JSR step_ptr_04b                ; $1024
        JMP swap_room_record            ; $1027
swap_room_done:
        RTS                             ; $102A

; The idle pause. The twenty band color bytes at $0153 go to $47B4, and $82
; becomes $FE, so irq_service starts cycling the bands from that copy.
save_band_colors:
        LDX #$13                        ; $102B
save_band_loop:
        LDA $0153,X                     ; $102D
        STA $47B4,X                     ; $1030
        DEX                             ; $1033
        BPL save_band_loop              ; $1034
        LDA #$FE                        ; $1036
        STA $82                         ; $1038
        RTS                             ; $103A

; The end of the idle pause. The colors at $47B4 go back to $0153 and $82
; is cleared, so the idle count starts over.
restore_band_colors:
        LDX #$13                        ; $103B
restore_band_loop:
        LDA $47B4,X                     ; $103D
        STA $0153,X                     ; $1040
        DEX                             ; $1043
        BPL restore_band_loop           ; $1044
        LDA #$00                        ; $1046
        STA $82                         ; $1048
        RTS                             ; $104A

; The sliding blocks, up to nine of them in $010F-$0149. A slot whose
; $010F byte is 0 is empty. A positive byte moves the block left, a
; negative one right, and it wraps between the bounds at $0137 and
; $0141. $70 and $6F are stored before the step and $6E after it. The
; column it left goes to $012D,X and the new one to $0119,X.
step_sliders:
        LDX #$08                        ; $104B
slider_loop:
        LDA $010F,X                     ; $104D
        BEQ slider_next                 ; $1050
        TXA                             ; $1052
        PHA                             ; $1053
        LDA $0119,X                     ; $1054
        STA $012D,X                     ; $1057
        STA $70                         ; $105A
        LDA $0123,X                     ; $105C
        STA $6F                         ; $105F
        LDA $010F,X                     ; $1061
        BMI slider_right                ; $1064
        DEC $0119,X                     ; $1066
        LDA $0119,X                     ; $1069
        CMP $0137,X                     ; $106C
        BCS slider_left_draw            ; $106F
        LDA $0141,X                     ; $1071
        STA $0119,X                     ; $1074
slider_left_draw:
        STA $6E                         ; $1077
        LDA $6F                         ; $1079
        CMP #$05                        ; $107B
        BEQ slider_draw_tall            ; $107D
        CMP #$0A                        ; $107F
        BEQ slider_draw_tall            ; $1081
        JSR draw_slider                 ; $1083
        JMP slider_restore_x            ; $1086
slider_draw_tall:
        JSR draw_slider_tall            ; $1089
        JMP slider_restore_x            ; $108C
slider_right:
        INC $0119,X                     ; $108F
        LDA $0119,X                     ; $1092
        CMP $0141,X                     ; $1095
        BCC slider_right_draw           ; $1098
        LDA $0137,X                     ; $109A
        STA $0119,X                     ; $109D
slider_right_draw:
        STA $6E                         ; $10A0
        LDA $6F                         ; $10A2
        CMP #$05                        ; $10A4
        BEQ slider_draw_tall            ; $10A6
        CMP #$0A                        ; $10A8
        BEQ slider_draw_tall            ; $10AA
        JSR draw_slider                 ; $10AC
slider_restore_x:
        PLA                             ; $10AF
        TAX                             ; $10B0
slider_next:
        DEX                             ; $10B1
        BPL slider_loop                 ; $10B2
        RTS                             ; $10B4

; Effect $82, restoring A, X, and Y. spawn_yamo and spawn_ninja
; both return through here.
blip_and_return:
        PHA                             ; $10B5
        TXA                             ; $10B6
        PHA                             ; $10B7
        TYA                             ; $10B8
        PHA                             ; $10B9
        LDY #$82                        ; $10BA
        JSR play_sound                  ; $10BC
        PLA                             ; $10BF
        TAY                             ; $10C0
        PLA                             ; $10C1
        TAX                             ; $10C2
        PLA                             ; $10C3
        RTS                             ; $10C4
; Copy the 20 default bytes at $4CCE into $2A. $2A,X is the lamps still
; to take in room X. claim_lamp decrements that byte. Rooms 13 and 19
; start at 0. The room 11 gate reads three of them by address:
;   $36 room 12, $38 room 14, $3A room 16.
copy_room_defaults:
        LDX #$13                        ; $10C5
copy_room_defaults_loop:
        LDA $4CCE,X                     ; $10C7
        STA $2A,X                       ; $10CA
        DEX                             ; $10CC
        BPL copy_room_defaults_loop     ; $10CD
        RTS                             ; $10CF
; $88 against two marks. Carry comes back set when $88 is at least $19.
; Overflow comes back set when $88 is at least $20. A fresh room has $88
; at 0, so both are clear. Callers that BVS take the long visit: the spawn
; wait becomes 3, and a hit recovery uses the short timer. Callers that
; BCS, with V clear, take the middle visit and halve the wait. The
; two-player idle path stores $20, which is a long visit on the next test.
; $10DF is the RTS below. BIT of that $60 sets V from bit 6.
test_visit:
        LDA $88                         ; $10D0
        CMP #$20                        ; $10D2
        BCS visit_hard                  ; $10D4
        CMP #$19                        ; $10D6
        CLV                             ; $10D8
        RTS                             ; $10D9
; $88 is $20 or more. Carry is still set from the CMP, and BIT of the $60
; at $10DF sets V, so the caller sees both.
visit_hard:
        LDA #$FF                        ; $10DA
        BIT $10DF                       ; $10DC
        RTS                             ; $10DF

; The current player's room-entry flags, $0300 + room*2 + player. Every
; room is set back to 1, then room 0 is cleared, so the opening room does
; not pay again. enter_room spends a set flag. Only the treasure ending
; calls this.
rearm_room_bonus:
        LDA $03                         ; $10E0
        CLC                             ; $10E2
        ADC #$26                        ; $10E3
        TAX                             ; $10E5
        LDA #$01                        ; $10E6
; X starts at $26 + player, room 19's flag, and steps two bytes per room.
rearm_slot:
        STA $0300,X                     ; $10E8
        DEX                             ; $10EB
        DEX                             ; $10EC
        BPL rearm_slot                  ; $10ED
        LDX $03                         ; $10EF
        LDA #$00                        ; $10F1
        STA $0300,X                     ; $10F3
        RTS                             ; $10F6
; A bare RTS that boot calls. Something here may have been removed.
empty_hook:
        RTS                             ; $10F7
; $10F8  11 bytes that no instruction reads. The first two are $10F7, the
; address of empty_hook. The rest do not decode as anything the game uses.
; Hardware IRQ. $FFFE points here. Both branches jump through the
; pointer at $0408, which is $491E in this snapshot. $FFFA and $FFFC
; point at the RTI below.
irq_vector:
        PHA                             ; $1103
        TXA                             ; $1104
        PHA                             ; $1105
        TYA                             ; $1106
        PHA                             ; $1107
        TSX                             ; $1108
        LDA $0104,X                     ; $1109
        AND #$00                        ; $110C
        BEQ irq_jump                    ; $110E
        JMP ($0408)                     ; $1110
irq_jump:
        JMP ($0408)                     ; $1113
; NMI and reset. The RESTORE key lands here and nothing happens.
nmi_vector:
        RTI                             ; $1116
; $1117  26 bytes of code that nothing calls. JMP ($FFFC) and JMP ($0000),
; then a routine that zeroes $8180-$81FF and $82C0-$833F, the sprite images
; next to the ones clear_sprite_ram clears. It is likely an earlier
; clear_sprite_ram from before the images moved.

; Zero $8200-$827F and $8340-$83BF.
clear_sprite_ram:
        PHA                             ; $1131
        TXA                             ; $1132
        PHA                             ; $1133
        LDA #$00                        ; $1134
        LDX #$7F                        ; $1136
clear_sprite_loop:
        STA $8200,X                     ; $1138
        STA $8340,X                     ; $113B
        DEX                             ; $113E
        BPL clear_sprite_loop           ; $113F
        PLA                             ; $1141
        TAX                             ; $1142
        PLA                             ; $1143
        RTS                             ; $1144
; Zero $8280-$82BF and $83C0-$83FF.
clear_upper_sprites:
        PHA                             ; $1145
        TXA                             ; $1146
        PHA                             ; $1147
        LDA #$00                        ; $1148
        LDX #$3F                        ; $114A
clear_upper_loop:
        STA $8280,X                     ; $114C
        STA $83C0,X                     ; $114F
        DEX                             ; $1152
        BPL clear_upper_loop            ; $1153
        PLA                             ; $1155
        TAX                             ; $1156
        PLA                             ; $1157
        RTS                             ; $1158
; One noise byte. While $0104 is 0 the result is 1, and flicker_lamps then
; rewrites a steady row every frame. In play, $16 advances and ($16),Y is
; returned. Y belongs to the caller.
noise_byte:
        LDA $0104                       ; $1159
        BNE noise_next                  ; $115C
        LDA #$01                        ; $115E
        RTS                             ; $1160
noise_next:
        INC $16                         ; $1161
        LDA ($16),Y                     ; $1163
        RTS                             ; $1165

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
        LDX #$FF                        ; $1386
        STX $0109                       ; $1388
        INX                             ; $138B
        STX $010C                       ; $138C
        STX $DC02                       ; $138F  CIA 1 port A directions
        STX $DC03                       ; $1392  CIA 1 port B directions
        LDA #$7F                        ; $1395
        STA $DC0D                       ; $1397  CIA 1 interrupt control
        STA $DD0D                       ; $139A  CIA 2 interrupt control
        RTS                             ; $139D
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
        LDX #$FF                        ; $13AE
        STX $DC03                       ; $13B0  port B drives
        STX $010A                       ; $13B3  no key yet
        INX                             ; $13B6
        STX $010B                       ; $13B7  no Shift yet
        STX $DC01                       ; $13BA  every line low
        LDA $DC00                       ; $13BD  any key pulls a line
        CMP #$FF                        ; $13C0  none?
        BEQ read_stick_recheck          ; $13C2  none: recheck and store $FF
        STA $010D                       ; $13C4  the lines that are low
        STX $DC03                       ; $13C7  port B reads
        DEX                             ; $13CA
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
        JMP read_stick_recheck          ; $13EF
read_stick_play_keys:
        JSR scan_stick_only             ; $13F2
read_stick_recheck:
        LDA #$00                        ; $13F5
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
        LDA $010A                       ; $141F
        CMP #$FF                        ; $1422  none?
        BEQ read_stick_return           ; $1424  yes: nothing waiting
        LDA #$01                        ; $1426
        STA $010C                       ; $1428  a key is waiting
read_stick_return:
        RTS                             ; $142B
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
        BPL scan_keyboard_row           ; $1434
        STX $010A                       ; $1436  $FF: no key
        RTS                             ; $1439
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
        BPL scan_keyboard_column        ; $144D
        BMI scan_keyboard_next_row      ; $144F  always
scan_keyboard_found:
        TYA                             ; $1451  the column
        CLC                             ; $1452
        ADC $149C,X                     ; $1453  plus row times 8
        CMP #$0F                        ; $1456  Left Shift?
        BEQ scan_keyboard_next_column   ; $1458  skip it
        CMP #$34                        ; $145A  Right Shift?
        BEQ scan_keyboard_next_column   ; $145C  skip it
        STA $010A                       ; $145E  the key
        RTS                             ; $1461
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
        BNE scan_play_key               ; $1476
        LDA #$6F                        ; $1478  none
        STA $010A                       ; $147A  $6F, which nothing tests
        RTS                             ; $147D
scan_play_key_found:
        TYA                             ; $147E
        LSR A                           ; $147F  pair number
        TAY                             ; $1480
        LDA $1490,Y                     ; $1481  its code
        STA $010A                       ; $1484  the key
        RTS                             ; $1487

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
        LDX #$6D                        ; $14A4
        LDA #$6E                        ; $14A6
between_raster_wait:
        CMP $D012                       ; $14A8  raster line
        BEQ between_raster_band         ; $14AB
        CPX $D012                       ; $14AD  raster line
        BNE between_raster_wait         ; $14B0
        LDX #$0A                        ; $14B2
between_raster_delay:
        DEX                             ; $14B4
        BNE between_raster_delay        ; $14B5
between_raster_band:
        LDA #$FB                        ; $14B7  dark grey
        STA $D022                       ; $14B9  background multicolor 1
        JSR raster_wait                 ; $14BC
        JSR raster_wait                 ; $14BF
        LDA #$FC                        ; $14C2  grey
        STA $D022                       ; $14C4  background multicolor 1
        JSR raster_wait                 ; $14C7
        JSR raster_wait                 ; $14CA
        LDA #$FF                        ; $14CD  light grey
        STA $D022                       ; $14CF  background multicolor 1
        JSR raster_wait                 ; $14D2
        JSR raster_wait                 ; $14D5
        LDA #$F1                        ; $14D8  white
        STA $D022                       ; $14DA  background multicolor 1
        JSR raster_wait                 ; $14DD
        LDA #$FF                        ; $14E0  light grey again
        STA $D022                       ; $14E2  background multicolor 1
        JSR raster_wait                 ; $14E5
        JSR raster_wait                 ; $14E8
        LDA #$FC                        ; $14EB  grey again
        STA $D022                       ; $14ED  background multicolor 1
        JSR raster_wait                 ; $14F0
        JSR raster_wait                 ; $14F3
        LDA #$FB                        ; $14F6  dark grey again
        STA $D022                       ; $14F8  background multicolor 1
        LDA #$30                        ; $14FB
        STA $D018                       ; $14FD  screen and charset address
        LDA #$18                        ; $1500
        STA $D016                       ; $1502  VIC control: xscroll, multicolor
        LDA #$01                        ; $1505
        STA $D01A                       ; $1507  VIC interrupt enable
        STA $D019                       ; $150A  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $150D  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1510
        STA $D011                       ; $1512  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$63                        ; $1515
        STA $D012                       ; $1517  raster line
        LDA $48                         ; $151A
        BEQ between_raster_done         ; $151C
        DEC $48                         ; $151E
between_raster_done:
        PLA                             ; $1520
        TAY                             ; $1521
        PLA                             ; $1522
        TAX                             ; $1523
        PLA                             ; $1524
        RTI                             ; $1525

; Burn about ten iterations. The between-lives flash pauses on each $D022 color.
raster_wait:
        LDX #$0A                        ; $1526
raster_wait_loop:
        DEX                             ; $1528
        BNE raster_wait_loop            ; $1529
        RTS                             ; $152B

; Options page and game over both point here. From raster $FD, charset $8000
; and multicolor stay on through the logo, rows 0-9. Raster $82 is the top of
; row 10, where options_late takes over. On the logo, color RAM is $0F:
; pair 00 is $D021 blue, 01 and 10 are $D022/$D023 light grey, 11 would be
; yellow. The logo glyphs use 00 and 01. $48, and $49/$4A, count down here.
options_raster:
game_over_raster:
        LDA $48                         ; $152C
        BEQ options_raster_timeout      ; $152E
        DEC $48                         ; $1530
options_raster_timeout:
        LDA $49                         ; $1532
        BEQ options_raster_split        ; $1534
        DEC $49                         ; $1536
        BNE options_raster_split        ; $1538
        LDA $4A                         ; $153A
        BEQ options_raster_split        ; $153C
        DEC $4A                         ; $153E
        DEC $49                         ; $1540
options_raster_split:
        LDA #$30                        ; $1542
        STA $D018                       ; $1544  screen and charset address
        LDA #$18                        ; $1547
        STA $D016                       ; $1549  VIC control: xscroll, multicolor
; The tune advances here, once per raster. Play does not install this
; raster and the effect voices together.
        JSR service_tune                ; $154C
        LDA #$74                        ; $154F
        STA $0408                       ; $1551
        LDA #$15                        ; $1554
        STA $0409                       ; $1556
        LDA #$01                        ; $1559
        STA $D01A                       ; $155B  VIC interrupt enable
        STA $D019                       ; $155E  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $1561  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1564
        STA $D011                       ; $1566  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$82                        ; $1569
        STA $D012                       ; $156B  raster line
        PLA                             ; $156E
        TAY                             ; $156F
        PLA                             ; $1570
        TAX                             ; $1571
        PLA                             ; $1572
        RTI                             ; $1573

; Raster $82. Charset $8800 is the score font, copied from the character ROM
; with the inverse $40 codes higher. $D016 drops to $16: multicolor off,
; xscroll 6. Rows 10-24 are hires, white ink on the blue background, and bit
; 6 of a code is the highlighted glyph. The vector returns to options_raster
; at raster $FD.
options_late:
game_over_late:
        LDX #$04                        ; $1574
options_late_delay:
        DEX                             ; $1576
        BNE options_late_delay          ; $1577
        LDA #$32                        ; $1579
        STA $D018                       ; $157B  screen and charset address
        LDA #$16                        ; $157E
        STA $D016                       ; $1580  VIC control: xscroll, multicolor
        LDA #$2C                        ; $1583
        STA $0408                       ; $1585
        LDA #$15                        ; $1588
        STA $0409                       ; $158A
        LDA #$01                        ; $158D
        STA $D01A                       ; $158F  VIC interrupt enable
        STA $D019                       ; $1592  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $1595  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $1598
        STA $D011                       ; $159A  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FD                        ; $159D
        STA $D012                       ; $159F  raster line
        PLA                             ; $15A2
        TAY                             ; $15A3
        PLA                             ; $15A4
        TAX                             ; $15A5
        PLA                             ; $15A6
        RTI                             ; $15A7

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
        CLD                             ; $15A8
        LDA #$00                        ; $15A9
        STA $44                         ; $15AB
        LDX $29                         ; $15AD
        JSR voice_1                     ; $15AF
        JSR voice_2                     ; $15B2
        JSR voice_3                     ; $15B5
        INC $16                         ; $15B8
        JSR place_sprites               ; $15BA
        LDA $4EEC                       ; $15BD
        BNE irq_check_charset           ; $15C0
        LDA #$02                        ; $15C2
        STA $4F45                       ; $15C4
        STA $4F46                       ; $15C7
        STA $4F47                       ; $15CA
irq_check_charset:
        DEC $4EEC                       ; $15CD
        LDA $F2                         ; $15D0
        CMP #$38                        ; $15D2
        BNE irq_charset_a800            ; $15D4
        LDA #$A0                        ; $15D6
        BNE irq_store_charset           ; $15D8
irq_charset_a800:
        CMP #$3A                        ; $15DA
        BNE irq_charset_b000            ; $15DC
        LDA #$A8                        ; $15DE
        BNE irq_store_charset           ; $15E0
irq_charset_b000:
        CMP #$3C                        ; $15E2
        BNE irq_charset_b800            ; $15E4
        LDA #$B0                        ; $15E6
        BNE irq_store_charset           ; $15E8
irq_charset_b800:
        LDA #$B8                        ; $15EA
irq_store_charset:
        STA $7C                         ; $15EC
; $1383 = 0 prints L at row 1 column 2. Right-handed clears it. The second L,
; at $8C4D, is drawn only in two-player or opponent mode, from $1384.
        LDA $1383                       ; $15EE
        BEQ irq_hand1_mark              ; $15F1
        LDA #$00                        ; $15F3
        BEQ irq_store_hand1             ; $15F5
irq_hand1_mark:
        LDA #$2C                        ; $15F7
irq_store_hand1:
        STA $8C2A                       ; $15F9
        LDA $42CA                       ; $15FC
        BNE irq_hand2                   ; $15FF
        LDA $42C9                       ; $1601
        BEQ irq_store_hand2             ; $1604
irq_hand2:
        LDA $1384                       ; $1606
        BEQ irq_hand2_mark              ; $1609
        LDA #$00                        ; $160B
        BEQ irq_store_hand2             ; $160D
irq_hand2_mark:
        LDA #$2C                        ; $160F
irq_store_hand2:
        STA $8C4D                       ; $1611
; One raster of the visit clock. $0104 clear is the demo, and a negative
; $0105 is the pause, so neither one advances it. Space toggles that flag
; from in_game_key. The idle count below sets it when $82 wraps negative.
; $88 stops when its own sign bit is set, at $80. That is 128 wraps,
; 32768 rasters.
count_visit:
        LDA $0104                       ; $1614
        BEQ count_idle                  ; $1617
        LDA $0105                       ; $1619
        BMI count_idle                  ; $161C
        INC $87                         ; $161E
        BNE count_idle                  ; $1620
        LDA $88                         ; $1622
        BMI count_idle                  ; $1624
        INC $88                         ; $1626
count_idle:
        INC $7F                         ; $1628
        BNE count_band_mask             ; $162A
        LDA $82                         ; $162C
        BMI count_slow                  ; $162E
        INC $82                         ; $1630
        BPL count_slow                  ; $1632
; Idle pause. $86 sets the sign bit and the three-frame lockout in bits 1-2.
; enter_pause forces the player word on and prints "** PAUSED **".
        LDA #$86                        ; $1634
        STA $0105                       ; $1636
        JSR enter_pause                 ; $1639
        JSR save_band_colors            ; $163C
count_slow:
        INC $80                         ; $163F
        BNE count_band_mask             ; $1641
        INC $81                         ; $1643
count_band_mask:
        LDA #$FE                        ; $1645
        LDX #$00                        ; $1647
        LDY $82                         ; $1649
        BPL count_store_mask            ; $164B
        STA $82                         ; $164D
        LDX $80                         ; $164F
        LDA #$F7                        ; $1651
count_store_mask:
        STA $84                         ; $1653
        STX $83                         ; $1655
        LDA $82                         ; $1657
        BPL count_timers                ; $1659
        LDX #$13                        ; $165B
count_cycle_bands:
        LDA $47B4,X                     ; $165D
        EOR $83                         ; $1660
        AND $84                         ; $1662
        STA $0153,X                     ; $1664
        DEX                             ; $1667
        BPL count_cycle_bands           ; $1668
count_timers:
        NOP                             ; $166A
        NOP                             ; $166B
        NOP                             ; $166C
        NOP                             ; $166D
        NOP                             ; $166E
        NOP                             ; $166F
        NOP                             ; $1670
        NOP                             ; $1671
        LDA $48                         ; $1672
        BEQ count_timer_low             ; $1674
        DEC $48                         ; $1676
count_timer_low:
        LDA $49                         ; $1678
        BEQ count_timer_high            ; $167A
        DEC $49                         ; $167C
        JMP irq_read_sticks             ; $167E
count_timer_high:
        LDA $4A                         ; $1681
        BEQ irq_read_sticks             ; $1683
        DEC $4A                         ; $1685
        DEC $49                         ; $1687
irq_read_sticks:
        LDA $DC02                       ; $1689  CIA 1 port A directions
        STA $2005                       ; $168C
        LDA $DC03                       ; $168F  CIA 1 port B directions
        STA $2006                       ; $1692
        LDA #$00                        ; $1695
        STA $DC02                       ; $1697  CIA 1 port A directions
        STA $DC03                       ; $169A  CIA 1 port B directions
        LDA $0104                       ; $169D
        BEQ irq_check_02                ; $16A0
; Port follows $03. Left-handed ($1383,X = 0) rotates the nibble through $4A85
; ($00, $08, $04, $0C): up becomes right, right becomes down, and so on.
; $42CA set also reads the other port into $99 and the button into $9C.
; Those are Yamo's, actor 1. actor_tick tests $98,X and the fire byte
; beside it, so his walk, climb, jump, duck, punch, and flying kick are
; the same branches Bruce takes on $98 and $9B. $9C is 0 while held.
        LDA $DC01                       ; $16A2  CIA 1 port B: joystick 1, keyboard rows
        LDX $03                         ; $16A5
        BEQ irq_bruce_port              ; $16A7
        LDA $DC00                       ; $16A9  CIA 1 port A: joystick 2, keyboard columns
irq_bruce_port:
        AND #$0F                        ; $16AC
        LDY $1383,X                     ; $16AE
        BNE irq_store_bruce_stick       ; $16B1
        PHA                             ; $16B3
        AND #$03                        ; $16B4
        TAY                             ; $16B6
        PLA                             ; $16B7
        LSR A                           ; $16B8
        LSR A                           ; $16B9
        ORA $4A85,Y                     ; $16BA
irq_store_bruce_stick:
        STA $98                         ; $16BD
        LDA $03                         ; $16BF
        EOR #$01                        ; $16C1
        TAX                             ; $16C3
        LDA $DC00,X                     ; $16C4  CIA 1 port A: joystick 2, keyboard columns, plus X
        LSR A                           ; $16C7
        LSR A                           ; $16C8
        LSR A                           ; $16C9
        LSR A                           ; $16CA
        AND #$01                        ; $16CB
        STA $9B                         ; $16CD
        LDA $42CA                       ; $16CF
        BEQ irq_check_02                ; $16D2
        LDA $03                         ; $16D4
        EOR #$01                        ; $16D6
        TAX                             ; $16D8
        PHP                             ; $16D9
        LDA $DC01                       ; $16DA  CIA 1 port B: joystick 1, keyboard rows
        PLP                             ; $16DD
        BEQ irq_yamo_port               ; $16DE
        LDA $DC00                       ; $16E0  CIA 1 port A: joystick 2, keyboard columns
irq_yamo_port:
        AND #$0F                        ; $16E3
        LDY $1383,X                     ; $16E5
        BNE irq_store_yamo_stick        ; $16E8
        PHA                             ; $16EA
        AND #$03                        ; $16EB
        TAY                             ; $16ED
        PLA                             ; $16EE
        LSR A                           ; $16EF
        LSR A                           ; $16F0
        ORA $4A85,Y                     ; $16F1
irq_store_yamo_stick:
        STA $99                         ; $16F4
        LDX $03                         ; $16F6
        LDA $DC00,X                     ; $16F8  CIA 1 port A: joystick 2, keyboard columns, plus X
        LSR A                           ; $16FB
        LSR A                           ; $16FC
        LSR A                           ; $16FD
        LSR A                           ; $16FE
        AND #$01                        ; $16FF
        STA $9C                         ; $1701
; A tamper check. Unless $02 holds $32, every raster fills memory with
; the value in $02, a page at a time, downward from the page that value
; names. The page count is $0539, the high byte of the STA $D011 in
; attract_demo, so the loop also rewrites that instruction. The game is
; wrecked within one interrupt. $02 is $32 in every snapshot, so this never runs.
; hook_enter_5 also spins until $02 is $32.
irq_check_02:
        LDA $02                         ; $1703
        CMP #$32                        ; $1705
        BEQ irq_restore_ddr             ; $1707
        STA $05                         ; $1709
irq_wipe_memory:
        STA ($04),Y                     ; $170B
        DEY                             ; $170D
        BNE irq_wipe_memory             ; $170E
        DEC $05                         ; $1710
        DEC $0539                       ; $1712
        BNE irq_wipe_memory             ; $1715
irq_restore_ddr:
        LDA $2005                       ; $1717
        STA $DC02                       ; $171A  CIA 1 port A directions
        LDA $2006                       ; $171D
        STA $DC03                       ; $1720  CIA 1 port B directions
        LDA $0104                       ; $1723
        BEQ idle_reset                  ; $1726
        LDA $0105                       ; $1728
        BMI opponent_idle               ; $172B
        LDA $98                         ; $172D
        ORA $99                         ; $172F
        CMP #$0F                        ; $1731
        BNE idle_reset                  ; $1733
        LDA $9B                         ; $1735
        AND $9C                         ; $1737
        BNE opponent_idle               ; $1739
idle_reset:
        LDA #$00                        ; $173B
        STA $82                         ; $173D
opponent_idle:
        LDA $7A                         ; $173F
        BNE irq_service_done            ; $1741
        LDA $0105                       ; $1743
        BMI irq_service_done            ; $1746
        LDA $0104                       ; $1748
        BEQ irq_service_done            ; $174B
        LDA $42CA                       ; $174D
        BEQ irq_service_done            ; $1750
        LDA $99                         ; $1752
        CMP #$0F                        ; $1754
        BNE opponent_idle_reset         ; $1756
        LDA $9C                         ; $1758
        BEQ opponent_idle_reset         ; $175A
        INC $89                         ; $175C
        BNE irq_service_done            ; $175E
        INC $8A                         ; $1760
        LDA $8A                         ; $1762
        CMP #$07                        ; $1764
        BCC irq_service_done            ; $1766
        LDA #$00                        ; $1768
        STA $42CA                       ; $176A
; $89 counts screens while $99 is $0F and $9C is up. $8A counts the
; wraps. Seven of them is about 36 seconds. A direction or a held button
; clears both at opponent_idle_reset. $42CA is cleared for the rest of this game, so
; enemy_turn takes Yamo back and later wake counts use the room table.
; $42CC is left set. The next options page still shows OPPONENT, and the
; next game from that page gives him back. Effect $8A plays. Five falls
; come off $28 and off $439F, the other player's stock, clamped at 0.
; $88 becomes $20, which test_visit treats as a long visit. Yamo has no
; fall counter of his own. The five falls are Bruce's.
        LDA #$20                        ; $176D
        STA $88                         ; $176F
        JSR play_sound_8a               ; $1771
        LDA $28                         ; $1774
        CMP #$05                        ; $1776
        BCC opponent_falls_zero         ; $1778
        SBC #$05                        ; $177A
        JMP opponent_store_falls        ; $177C
opponent_falls_zero:
        LDA #$00                        ; $177F
opponent_store_falls:
        STA $28                         ; $1781
        LDA $439F                       ; $1783
        CMP #$05                        ; $1786
        BCC opponent_other_zero         ; $1788
        SBC #$05                        ; $178A
        JMP opponent_store_other        ; $178C
opponent_other_zero:
        LDA #$00                        ; $178F
opponent_store_other:
        STA $439F                       ; $1791
        JSR lives_to_bcd                ; $1794
opponent_idle_reset:
        LDA #$00                        ; $1797
        STA $89                         ; $1799
        STA $8A                         ; $179B
irq_service_done:
        RTS                             ; $179D


; For each active actor, release the pose hold and then choose the picture. X = 0 is Bruce.
step_actors:
        JSR enemy_turn                  ; $179E
; $0104 clear is the attract demo. Bruce's stick and button come from
; ($1D), one byte a frame from $F300, in place of what irq_service read.
        LDA $0104                       ; $17A1  the demo?
        BNE step_actors_loop_start      ; $17A4  no
        LDY #$00                        ; $17A6
        LDA ($1D),Y                     ; $17A8  the demo byte
        AND #$0F                        ; $17AA  the stick nibble
        STA $98                         ; $17AC  Bruce's stick
        LDA ($1D),Y                     ; $17AE
        LSR A                           ; $17B0
        LSR A                           ; $17B1
        LSR A                           ; $17B2
        LSR A                           ; $17B3  the high nibble
        STA $9B                         ; $17B4  Bruce's fire
        INC $1D                         ; $17B6  the next byte
        BNE step_actors_loop_start      ; $17B8
        INC $1E                         ; $17BA  carry into the high byte
step_actors_loop_start:
        LDX #$02                        ; $17BC  the ninja first
step_actors_loop:
        LDA active,X                    ; $17BE
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
        LDA #$0F                        ; $17D4
; A is the stick for Bruce: $0E up during the first 512 rasters, then $0F.
treasure_store:
        STA $98                         ; $17D6  Bruce's stick only
; Every room. The hold, then the picture, for actor X.
release_actor:
        JSR release_hold                ; $17D8  the hold, then the move
        JSR choose_pose                 ; $17DB  his picture
step_actors_next:
        DEX                             ; $17DE  the next actor
        BPL step_actors_loop            ; $17DF
        RTS                             ; $17E1
; A selects a string from the table at $43BE. X is the row passed to
; point_at_row. Y is the column. Copies until the $A0 terminator. The plain
; byte goes to ($04), the same byte with bit 7 set goes to ($08).
; Subtracting $20 from the stored bytes is what makes them screen codes
; in the score font: glyph 0 is a space, $0A is a star, and $21 is A.
print_string:
        PHA                             ; $17E2
        JSR point_at_row                ; $17E3
        PLA                             ; $17E6
        ASL A                           ; $17E7
        TAX                             ; $17E8
        STY $06                         ; $17E9
        LDA $43BE,X                     ; $17EB
        SEC                             ; $17EE
        SBC $06                         ; $17EF
        STA $06                         ; $17F1
        LDA $43BF,X                     ; $17F3
        SBC #$00                        ; $17F6
        STA $07                         ; $17F8
print_string_loop:
        LDA ($06),Y                     ; $17FA
        SEC                             ; $17FC
        SBC #$20                        ; $17FD
        CMP #$80                        ; $17FF
        BEQ print_string_done           ; $1801
        AND #$7F                        ; $1803
        STA ($04),Y                     ; $1805
        ORA #$80                        ; $1807
        STA ($08),Y                     ; $1809
        INY                             ; $180B
        BNE print_string_loop           ; $180C
        INC $05                         ; $180E
        INC $07                         ; $1810
        INC $09                         ; $1812
        JMP print_string_loop           ; $1814
print_string_done:
        RTS                             ; $1817
; Silence the SID. If $0104 is 0, the attract demo, spend nothing: $09BB = 0
; makes the options tune start at once, and open_room is the options page.
; Otherwise one fall is spent. A result with the sign bit clear, including 0,
; shows the PLAYER page and comes back to $29. A negative result is game over.
lose_life:
        JSR silence_sid                 ; $1818
        LDA $0104                       ; $181B
        BNE spend_fall                  ; $181E
        STA $09BB                       ; $1820
        JMP open_room                   ; $1823
; One fall. The trainer's first question stores $A5 here, so this becomes LDA $28
; and the count never moves. The same byte is stored over the INC at $2FE5 and
; $3155. The frozen value is the one clear_work_ram wrote, 4 or 9, so the line
; stays on that full count. LDA of either is positive, so BMI never fires and
; the PLAYER page still runs. Game over does not.
spend_fall:
        DEC $28                         ; $1826
        BMI game_over                   ; $1828
; spend_fall already counted. Zero stays here. Two-player mode swaps the
; saved block at $439F before the next room. That block is $28 through $43,
; so it holds the falls and the score. The two extra-fall marks at $4392
; and $4395 are swapped after it. The room that opens is still $29.
between_lives:
        LDA #$24                        ; $182A
        STA $D1                         ; $182C  Bruce, Yamo, and the ninja. The caps apply again at the next wake.
        STA $D2                         ; $182E
        STA $D3                         ; $1830
        LDA #$00                        ; $1832
        STA $8B                         ; $1834
        STA $8C                         ; $1836
        JSR blank_sparks                ; $1838
        LDA $42C9                       ; $183B
        BEQ between_lives_page          ; $183E
        LDA $439F                       ; $1840
        BMI between_lives_page          ; $1843
        LDA $03                         ; $1845
        EOR #$01                        ; $1847
        STA $03                         ; $1849
between_lives_page:
        JSR between_rooms               ; $184B
        LDA $D011                       ; $184E  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $1851
        STA $D011                       ; $1853  VIC control: yscroll, 25 rows, raster bit 8
        LDA $42C9                       ; $1856
        BEQ between_lives_enter         ; $1859
        LDA $439F                       ; $185B
        BMI between_lives_enter         ; $185E
        LDX #$1B                        ; $1860
between_lives_swap_block:
        LDA $28,X                       ; $1862
        LDY $439F,X                     ; $1864
        STA $439F,X                     ; $1867
        TYA                             ; $186A
        STA $28,X                       ; $186B
        DEX                             ; $186D
        BPL between_lives_swap_block    ; $186E
        JSR swap_waiting_lamps          ; $1870
        LDX #$02                        ; $1873
between_lives_swap_marks:
        LDA $4392,X                     ; $1875
        PHA                             ; $1878
        LDA $4395,X                     ; $1879
        STA $4392,X                     ; $187C
        PLA                             ; $187F
        STA $4395,X                     ; $1880
        DEX                             ; $1883
        BPL between_lives_swap_marks    ; $1884
between_lives_enter:
        JSR init_hardware               ; $1886
        LDX $29                         ; $1889
        JMP enter_room_at               ; $188B
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
        JSR blank_sparks                ; $188E
        JSR clear_playfield             ; $1891
        SEI                             ; $1894
        LDA $D011                       ; $1895  VIC control: yscroll, 25 rows, raster bit 8
        AND #$EF                        ; $1898
        STA $D011                       ; $189A  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$00                        ; $189D
        STA $D015                       ; $189F  sprite enable
        LDA #$2C                        ; $18A2  low byte of game_over_raster
        STA $0408                       ; $18A4
        LDA #$15                        ; $18A7
        STA $0409                       ; $18A9
        LDA #$01                        ; $18AC
        STA $D01A                       ; $18AE  VIC interrupt enable
        STA $D019                       ; $18B1  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $18B4  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $18B7
        STA $D011                       ; $18B9  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$FB                        ; $18BC
        STA $D012                       ; $18BE  raster line
        LDA #$06                        ; $18C1
        STA $D020                       ; $18C3  border color
        STA $D021                       ; $18C6  background color
        LDA #$0F                        ; $18C9
        STA $D022                       ; $18CB  background multicolor 1
        STA $D023                       ; $18CE  background multicolor 2
        LDX #$08                        ; $18D1
        STX $D016                       ; $18D3  VIC control: xscroll, multicolor
        JSR fill_color_ram              ; $18D6
        LDX #$00                        ; $18D9
; A is still $0F, so fill_color_ram left light grey. $F1 repaints from row 12
; down in white. The words are above that, on the $0F cells. $DC covers
; $8C00 and $8C90 for 256 bytes each, through row 9.
blank_over_screen:
        LDA #$F1                        ; $18DB
        STA $D9E0,X                     ; $18DD  color RAM, row 12 column 0, plus X
        STA $DAE0,X                     ; $18E0  color RAM, row 18 column 16, plus X
        LDA #$DC                        ; $18E3
        STA $8C00,X                     ; $18E5
        STA $8C90,X                     ; $18E8
        INX                             ; $18EB
        BNE blank_over_screen           ; $18EC
        LDX #$11                        ; $18EE
; Eighteen screen codes. $8C33 is row 1 column 11, $8C5B row 2 column 11.
paint_over_word:
        LDA $42CD,X                     ; $18F0
        ORA #$80                        ; $18F3
        STA $8C33,X                     ; $18F5
        LDA $42DF,X                     ; $18F8
        ORA #$80                        ; $18FB
        STA $8C5B,X                     ; $18FD
        DEX                             ; $1900
        BPL paint_over_word             ; $1901
        LDA $03                         ; $1903
        ASL A                           ; $1905
        TAX                             ; $1906
        LDY #$00                        ; $1907
; between_rooms copies both digit bytes and advances X. DEY here runs once:
; Y is 0, then $FF, and BPL stops. Column 14 of each PLAYER line ($4A6B and
; $4A7B) takes one byte from $4A7D,X and $4A81,X. Player 0's stored line
; already says PLAYER 1, so that byte matches the glyph that is there.
poke_over_digit:
        LDA $4A7D,X                     ; $1909
        STA $4A6B,Y                     ; $190C
        LDA $4A81,X                     ; $190F
        STA $4A7B,Y                     ; $1912
        DEY                             ; $1915
        BPL poke_over_digit             ; $1916
        LDX #$0F                        ; $1918
; $8CD4 is row 5 column 12. $8CFC is row 6. Sixteen glyphs, bit 7 set.
paint_over_player:
        LDA $4A5D,X                     ; $191A
        ORA #$80                        ; $191D
        STA $8CD4,X                     ; $191F
        LDA $4A6D,X                     ; $1922
        ORA #$80                        ; $1925
        STA $8CFC,X                     ; $1927
        DEX                             ; $192A
        BPL paint_over_player           ; $192B
        JSR stash_scores                ; $192D
        LDA #$4E                        ; $1930
        STA $04                         ; $1932
        LDA #$76                        ; $1934
        STA $06                         ; $1936
        LDA #$8D                        ; $1938
        STA $05                         ; $193A
        STA $07                         ; $193C
        LDY #$00                        ; $193E
        LDX #$01                        ; $1940
; X starts at 1, so the high BCD byte $439B is skipped. $439C-$439E are the
; low six digits. $04/$06 point at $8D4E and $8D76, row 8 and row 9, column 14.
; draw_digit advances Y once, and the caller advances it again, two columns
; per digit.
paint_over_score:
        LDA $439B,X                     ; $1942
        LSR A                           ; $1945
        LSR A                           ; $1946
        LSR A                           ; $1947
        LSR A                           ; $1948
        JSR draw_digit                  ; $1949
        INY                             ; $194C
        LDA $439B,X                     ; $194D
        AND #$0F                        ; $1950
        JSR draw_digit                  ; $1952
        INY                             ; $1955
        INX                             ; $1956
        CPX #$04                        ; $1957
        BCC paint_over_score            ; $1959
        JSR show_screen                 ; $195B
        NOP                             ; $195E
        NOP                             ; $195F
        NOP                             ; $1960
        NOP                             ; $1961
        NOP                             ; $1962
        CLI                             ; $1963
        LDA #$FE                        ; $1964
        STA $48                         ; $1966
; $48 = $FE. game_over_raster counts it down once a frame, about five
; seconds with GAME OVER on screen. A second player with falls left goes
; on to between_lives.
wait_over_long:
        LDA $48                         ; $1968
        BNE wait_over_long              ; $196A
        LDA $42C9                       ; $196C
        BEQ over_fresh_game             ; $196F
        LDA $439F                       ; $1971
        BMI over_fresh_game             ; $1974
        JMP between_lives               ; $1976
; The other player is absent, or his saved falls are already negative.
over_fresh_game:
        LDA #$40                        ; $1979
        STA $48                         ; $197B
; $40 more frames, about 1.3 seconds, then open_room shows the options page.
wait_over_short:
        LDA $48                         ; $197D
        BNE wait_over_short             ; $197F
        JMP open_room                   ; $1981
; A is one hex digit. Four screen bytes: two on the row at ($04) and two on
; the row at ($06). Nibble N starts at glyph $34+N*4, with bit 7 set, so the
; block lives in the upper half of charset $8000. The status line does not
; use these. It uses the score font at $8800.
draw_digit:
        AND #$0F                        ; $1984
        ASL A                           ; $1986
        ASL A                           ; $1987
        ADC #$34                        ; $1988
        ORA #$80                        ; $198A
        STA ($04),Y                     ; $198C
        CLC                             ; $198E
        ADC #$01                        ; $198F
        STA ($06),Y                     ; $1991
        CLC                             ; $1993
        ADC #$01                        ; $1994
        INY                             ; $1996
        STA ($04),Y                     ; $1997
        CLC                             ; $1999
        ADC #$01                        ; $199A
        STA ($06),Y                     ; $199C
        RTS                             ; $199E
; Shift $43BC left three places into the pair $43BB/$43BC.
scale_by_eight:
        LDA #$00                        ; $199F
        STA $43BB                       ; $19A1
        CLC                             ; $19A4
        ROL $43BC                       ; $19A5
        ROL $43BB                       ; $19A8
        ROL $43BC                       ; $19AB
        ROL $43BB                       ; $19AE
        ROL $43BC                       ; $19B1
        ROL $43BB                       ; $19B4
        RTS                             ; $19B7
; The demo only. Joystick 1's button ($DC01 bit 4), or key code 4, which is
; F1, waits for the button to come up and six more screens, then jumps to
; start, the cold start: clear_work_ram and the options page, with the two
; options copied back. In play this returns at once.
demo_exit_check:
        LDA $0104                       ; $19B8
        BNE demo_exit_done              ; $19BB
        LDA $DC01                       ; $19BD  CIA 1 port B: joystick 1, keyboard rows
        AND #$10                        ; $19C0
        BEQ demo_exit                   ; $19C2
        LDA #$01                        ; $19C4
        STA $010E                       ; $19C6
        JSR read_stick                  ; $19C9
        LDA $010C                       ; $19CC
        BEQ demo_exit_done              ; $19CF
        LDA #$00                        ; $19D1
        STA $010C                       ; $19D3
        LDA $0109                       ; $19D6
        CMP #$04                        ; $19D9
        BNE demo_exit_done              ; $19DB
demo_exit:
        JSR wait_button_up              ; $19DD
        LDA #$06                        ; $19E0
        STA $48                         ; $19E2
demo_exit_wait:
        LDA $48                         ; $19E4
        BNE demo_exit_wait              ; $19E6
        JMP start                       ; $19E8
demo_exit_done:
        RTS                             ; $19EB
; Bits 1-2 of $0105 are the three-frame lockout after the pause flag
; flips. Each call takes one off and keeps bit 7. While it counts, $4B
; is set to $FF.
pause_lockout:
        LDA $0105                       ; $19EC
        PHA                             ; $19EF
        AND #$80                        ; $19F0
        STA $0105                       ; $19F2
        PLA                             ; $19F5
        AND #$06                        ; $19F6
        BEQ pause_lockout_done          ; $19F8
        SEC                             ; $19FA
        SBC #$01                        ; $19FB
        ORA $0105                       ; $19FD
        STA $0105                       ; $1A00
        LDA #$FF                        ; $1A03
        STA $4B                         ; $1A05
pause_lockout_done:
        RTS                             ; $1A07
; While paused and the lockout is spent, the current player's joystick
; button ($DC01 for player 1, $DC00 for player 2) leaves the pause.
; Space, through in_game_key, also toggles it.
fire_resumes:
        LDA $0105                       ; $1A08
        AND #$06                        ; $1A0B
        BNE fire_resumes_done           ; $1A0D
        LDA $0105                       ; $1A0F
        BPL fire_resumes_done           ; $1A12
        LDA $03                         ; $1A14
        EOR #$01                        ; $1A16
        AND #$01                        ; $1A18
        TAX                             ; $1A1A
        LDA $DC00,X                     ; $1A1B  CIA 1 port A: joystick 2, keyboard columns, plus X
        AND #$10                        ; $1A1E
        BNE fire_resumes_done           ; $1A20
; Toggle bit 7 of $0105. The $06 is a three-frame lockout, counted down by
; pause_lockout, so the pass that set the flag cannot toggle it straight back.
; Clearing the bit wipes "** PAUSED **" with string $0C and reprints TOP.
toggle_pause:
        LDA $0105                       ; $1A22
        EOR #$80                        ; $1A25
        ORA #$06                        ; $1A27
        STA $0105                       ; $1A29
        BMI enter_pause                 ; $1A2C
        JSR wipe_paused                 ; $1A2E
        LDA $82                         ; $1A31
        BPL leave_pause                 ; $1A33
        JSR restore_band_colors         ; $1A35
leave_pause:
        LDA #$00                        ; $1A38
        STA $82                         ; $1A3A
        JSR print_top_word              ; $1A3C
        JMP draw_top                    ; $1A3F
; Enter the pause. The same $11 and timed_caption pair as init_hardware,
; so the player word is forced on and $43BD sits at $10. frame then sees
; the sign bit and skips timed_caption, and the word stays up until the
; flag clears. The next live frame decrements $10, so the visible phase
; runs on.
enter_pause:
        LDA #$11                        ; $1A42
        STA $43BD                       ; $1A44
        JSR timed_caption               ; $1A47
        LDA #$51                        ; $1A4A
        STA $82                         ; $1A4C
; String $0B is "** PAUSED **", twelve codes. X = 1 is row 1, whose pointer
; is $8C28, and Y = $0F, so the line covers columns 15-26: TOP and the top
; score. FALLS, at column 28, stays. wipe_paused clears it with twelve spaces.
        JMP print_paused                ; $1A4E
fire_resumes_done:
        RTS                             ; $1A51
        .byte $A2, $02, $D0, $05

; Clear 13 character rows, using the pointers built at startup.
clear_playfield:
        LDX #$00                        ; $1A56
        STX $0100                       ; $1A58
clear_playfield_loop:
        JSR point_at_row                ; $1A5B
        JSR clear_row                   ; $1A5E
        INX                             ; $1A61
        CPX #$0D                        ; $1A62
        BCC clear_playfield_loop        ; $1A64
        RTS                             ; $1A66
; X is a row number. ($04) and ($08) become that row's two pointers. If $0100 is set, ($08)
; is forced to $CE00.
point_at_row:
        LDA $4338,X                     ; $1A67
        STA $04                         ; $1A6A
        LDA $434C,X                     ; $1A6C
        STA $05                         ; $1A6F
        LDA $4360,X                     ; $1A71
        STA $08                         ; $1A74
        LDA $4374,X                     ; $1A76
        STA $09                         ; $1A79
        LDA $0100                       ; $1A7B
        BNE point_at_scratch            ; $1A7E
        RTS                             ; $1A80
point_at_scratch:
        LDA #$00                        ; $1A81
        STA $08                         ; $1A83
        LDA #$CE                        ; $1A85
        STA $09                         ; $1A87
        RTS                             ; $1A89
; Write 40 zero bytes through ($04) and ($08).
clear_row:
        LDY #$27                        ; $1A8A
        LDA #$00                        ; $1A8C
clear_row_loop:
        STA ($04),Y                     ; $1A8E
        STA ($08),Y                     ; $1A90
        DEY                             ; $1A92
        BPL clear_row_loop              ; $1A93
        RTS                             ; $1A95
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
        DEC $43BD                       ; $1A96
        BNE timed_caption_check         ; $1A99
        LDA #$20                        ; $1A9B
        STA $43BD                       ; $1A9D
        LDA #$00                        ; $1AA0
        TAX                             ; $1AA2
        LDY #$2C                        ; $1AA3
        JMP print_string                ; $1AA5
timed_caption_check:
        LDA $43BD                       ; $1AA8
        CMP #$10                        ; $1AAB
        BNE timed_caption_done          ; $1AAD
        LDX $03                         ; $1AAF
        INX                             ; $1AB1
        TXA                             ; $1AB2
        LDX #$00                        ; $1AB3
        LDY #$2C                        ; $1AB5
        JMP print_string                ; $1AB7
timed_caption_done:
        RTS                             ; $1ABA
; String 3, "TOP", on row 1 at column 16, colors kept. Leaving the
; pause and init_hardware both call it.
print_top_word:
        LDA #$03                        ; $1ABB
        STA $0100                       ; $1ABD
        LDX #$00                        ; $1AC0
        LDY #$38                        ; $1AC2
        JMP print_keep_color            ; $1AC4
; String 5, "FALLS", on row 1 at column 28. init_hardware only.
print_falls_word:
        LDA #$05                        ; $1AC7
        LDX #$00                        ; $1AC9
        LDY #$44                        ; $1ACB
        JMP print_string                ; $1ACD

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
        LDA #$00                        ; $1AED
        STA $439B                       ; $1AEF
        LDA $28                         ; $1AF2
        STA $4398                       ; $1AF4
lives_tens_loop:
        SEC                             ; $1AF7
        SBC #$0A                        ; $1AF8
        BCC lives_units                 ; $1AFA
        INC $439B                       ; $1AFC
        JMP lives_tens_loop             ; $1AFF
lives_units:
        CLC                             ; $1B02
        ADC #$0A                        ; $1B03
        STA $4398                       ; $1B05
        LDA $439B                       ; $1B08
        ASL A                           ; $1B0B
        ASL A                           ; $1B0C
        ASL A                           ; $1B0D
        ASL A                           ; $1B0E
        ORA $4398                       ; $1B0F
        LDY #$4A                        ; $1B12
        JMP draw_bcd_digits             ; $1B14
; Draw both nibbles of A at screen column Y. The callers pass $3C, $3E,
; $40, and $4A. Each of those is past the 40 cells of row 0, so the digits
; land on row 1 ($8C28), on the grey $D021 bar between the two black rows.
draw_split_digits:
        PHA                             ; $1B17
        JSR high_nibble                 ; $1B18
        ORA #$10                        ; $1B1B
        STA $8C00,Y                     ; $1B1D
        PLA                             ; $1B20
        AND #$0F                        ; $1B21
        ORA #$10                        ; $1B23
        STA $8C01,Y                     ; $1B25
        RTS                             ; $1B28
; Keys during play, the four codes from scan_stick_only. Bit 7 is Shift
; and is masked off, so a shifted key still matches.
; $04 is F1, and jumps back to the cold start.
; $0D is S. It toggles $1385. Nonzero skips the options tune. $09BB is
; cleared, so the next options page starts the tune at once.
; $3C is Space, and toggles the $0105 pause.
; $1F is V, and toggles the credit line on row 0.
in_game_key:
        LDA #$01                        ; $1B29
        STA $010E                       ; $1B2B
        JSR read_stick                  ; $1B2E
        LDA $010C                       ; $1B31
        BNE in_game_key_take            ; $1B34
        RTS                             ; $1B36
in_game_key_take:
        LDA #$00                        ; $1B37
        STA $010C                       ; $1B39
        LDA $0109                       ; $1B3C
        AND #$7F                        ; $1B3F
        STA $4B                         ; $1B41
        CMP #$04                        ; $1B43
        BNE in_game_key_s               ; $1B45
        JMP start                       ; $1B47
in_game_key_s:
        CMP #$0D                        ; $1B4A
        BNE in_game_key_space_v         ; $1B4C
        LDA $1385                       ; $1B4E
        EOR #$01                        ; $1B51
        STA $1385                       ; $1B53
        LDA #$00                        ; $1B56
        STA $09BB                       ; $1B58
        RTS                             ; $1B5B
in_game_key_space_v:
        CMP #$3C                        ; $1B5C
        BEQ in_game_key_pause           ; $1B5E
        CMP #$1F                        ; $1B60
        BEQ toggle_credit_line          ; $1B62
        RTS                             ; $1B64
in_game_key_pause:
        JMP toggle_pause                ; $1B65
; V. Row 0 normally holds screen code $20, the solid black bar. The forty
; codes at $4707 replace it: "BRUCE LEE (C) 1984 DATASOFT REV.2 BY RJF".
; They are score-font codes, the same numbers print_string stores. A first
; cell that is not $20 fills the row with $20 again.
toggle_credit_line:
        LDA #$20                        ; $1B68
        CMP $8C00                       ; $1B6A
        BNE credit_line_clear           ; $1B6D
        LDX #$27                        ; $1B6F
credit_line_copy:
        LDA $4707,X                     ; $1B71
        STA $8C00,X                     ; $1B74
        DEX                             ; $1B77
        BPL credit_line_copy            ; $1B78
        RTS                             ; $1B7A
credit_line_clear:
        LDX #$27                        ; $1B7B
credit_line_clear_loop:
        STA $8C00,X                     ; $1B7D
        DEX                             ; $1B80
        BPL credit_line_clear_loop      ; $1B81
        RTS                             ; $1B83
; Draw both digits of A at column Y. A nibble past 9 is moved seven glyphs
; on, which is A through F. lives_to_bcd is the caller that reaches those
; glyphs. The score path uses draw_split_digits, whose nibbles are real BCD.
draw_bcd_digits:
        PHA                             ; $1B84
        JSR high_nibble                 ; $1B85
        ORA #$10                        ; $1B88
        CMP #$1A                        ; $1B8A
        BCC bcd_store_high              ; $1B8C
        CLC                             ; $1B8E
        ADC #$07                        ; $1B8F
bcd_store_high:
        STA $8C00,Y                     ; $1B91
        PLA                             ; $1B94
        AND #$0F                        ; $1B95
        ORA #$10                        ; $1B97
        CMP #$1A                        ; $1B99
        BCC bcd_store_low               ; $1B9B
        CLC                             ; $1B9D
        ADC #$07                        ; $1B9E
bcd_store_low:
        STA $8C01,Y                     ; $1BA0
        RTS                             ; $1BA3
; String $0B, "** PAUSED **", on row 1 at column 15, without touching
; color RAM.
print_paused:
        LDA #$0B                        ; $1BA4
        STA $0100                       ; $1BA6
        LDX #$01                        ; $1BA9
        LDY #$0F                        ; $1BAB
; print_string with $0100 set, so point_at_row aims the color pointer at
; the scratch page $CE00 and the cells keep their colors. $0100 is
; cleared after.
print_keep_color:
        JSR print_string                ; $1BAD
        LDA #$00                        ; $1BB0
        STA $0100                       ; $1BB2
        RTS                             ; $1BB5
; String $0C, twelve spaces, over the PAUSED line.
wipe_paused:
        LDA #$0C                        ; $1BB6
        STA $0100                       ; $1BB8
        LDX #$01                        ; $1BBB
        LDY #$0F                        ; $1BBD
        JMP print_keep_color            ; $1BBF
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
        JSR pause_lockout               ; $1BD1
        JSR fire_resumes                ; $1BD4
        LDA $0105                       ; $1BD7  paused?
        BPL frame_live                  ; $1BDA  no
        JMP wait_for_tick               ; $1BDC  paused: wait out the frame
frame_live:
        LDA $D2                         ; $1BDF  bit 6 cleared
        AND #$BF                        ; $1BE1
        STA $D2                         ; $1BE3
        LDA $D3                         ; $1BE5  bits 3-6 cleared
        AND #$87                        ; $1BE7
        STA $D3                         ; $1BE9
; Player word. Runs when $0104 is clear as well. A negative $0105 has
; already jumped to wait_for_tick, which is what holds the word during pause.
        JSR timed_caption               ; $1BEB
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
        LDA #$01                        ; $1C02
        STA $7B                         ; $1C04  0: now 1
        BNE frame_run                   ; $1C06  always
frame_hook_phase_clear:
        DEC $7B                         ; $1C08  now 0
frame_run:
        JSR run_frame_hook              ; $1C0A  the room's own frame code
        JSR overlap_actors              ; $1C0D  the overlap scan for each actor
        JSR scan_specials               ; $1C10  ladders, hot tiles, lamps
        LDA $CF7A                       ; $1C13
        EOR $CF9A                       ; $1C16
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
        LDA $48                         ; $1C32
        BNE wait_for_tick               ; $1C34
        JMP frame                       ; $1C36
; xpos and ypos of actor X, shifted down to a character cell in $E6,X and $E9,X.
; Room $0D adds 4 to ypos before the row shift only. The edge test at $30D4
; still sees the real ypos. scan_specials uses this same pair of cells.
cell_of_actor:
        LDA xpos,X                      ; $1C39  xpos
        SEC                             ; $1C3B
        SBC #$0C                        ; $1C3C  the box's left edge
        LSR A                           ; $1C3E
        LSR A                           ; $1C3F  four steps a cell
        STA $E6,X                       ; $1C40  the cell column
        LDA $29                         ; $1C42  the room
        CMP #$0D                        ; $1C44  room 13?
        BNE cell_plain_ypos             ; $1C46  no
        LDA ypos,X                      ; $1C48  ypos
        CLC                             ; $1C4A
        ADC #$04                        ; $1C4B  four rows lower
        BNE cell_store_row              ; $1C4D  always
cell_plain_ypos:
        LDA ypos,X                      ; $1C4F  ypos
cell_store_row:
        SEC                             ; $1C51
        SBC #$0C                        ; $1C52  the box's top
        LSR A                           ; $1C54
        LSR A                           ; $1C55
        LSR A                           ; $1C56
        LSR A                           ; $1C57  divided by 16
        STA $E9,X                       ; $1C58  the cell row
        RTS                             ; $1C5A
; The pose holds for $0106,X frames. While that count is running, the rest of the actor is
; skipped. $86 starts at 8. push_out decrements it once per generation, and
; the extra step is taken only when it is no longer 7, so the first
; generation does not take it. $4A8C is the hold for the state keep_state
; is about to store. States 1 and 2 are 3, state $1A is 1, and states
; $14, $15, $16, and $18 are 0, so the chase, the sidestep, the strike,
; and the bounce are not held.
release_hold:
        LDA #$08                        ; $1C5B  the extra step's count
        STA $86                         ; $1C5D
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
        ORA $4F5A,X                     ; $1C6E
        ORA $4F5D,X                     ; $1C71
        ORA $4F60,X                     ; $1C74
        BEQ hold_clear_current          ; $1C77  none: nothing to age
        LDA #$27                        ; $1C79  40 counters
        STA $4E                         ; $1C7B  kept
        TXA                             ; $1C7D  the actor
        CLC                             ; $1C7E
        ADC #$75                        ; $1C7F  from the oldest kept generation
        TAY                             ; $1C81  down to the current one
hold_age_history:
        LDA $4F57,Y                     ; $1C82  one counter
        STA $4F63,Y                     ; $1C85  one generation older
        DEY                             ; $1C88
        DEY                             ; $1C89
        DEY                             ; $1C8A  three bytes on: the same actor
        DEC $4E                         ; $1C8B  one fewer
        BPL hold_age_history            ; $1C8D  more
hold_clear_current:
        LDA #$00                        ; $1C8F
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
        LDA hit,X                       ; $1CC7
        AND #$08                        ; Bit 3, the solid flag.
        BNE push_out_start              ; $1CCB  a wall
        JMP actor_tick                  ; $1CCD  no wall: the move
push_out_start:
        LDA #$00                        ; $1CD0
        STA $C8,X                       ; $1CD2  move_up may run
; Walk the four oldest step counters back to 0, each step reversed: up is
; undone with move_down, down with move_up, left with move_right, and right
; with move_left. $85 starts at 1, and any undo except a down one clears
; it. Then 36 bytes, stride 3, are copied from $4F6F,X over $4F57,X, the
; older history over the newer. while_stuck comes back here through
; undo_again.
undo_steps:
        LDA #$01                        ; $1CD4  an up or sideways undo will clear it
        STA $85                         ; $1CD6
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
        TAY                             ; $1D0F
undo_slide_loop:
        LDA $4F6F,Y                     ; $1D10  two generations older
        STA $4F57,Y                     ; $1D13  over the current one
        INY                             ; $1D16
        INY                             ; $1D17
        INY                             ; $1D18  three bytes on: the same actor
        DEC $4E                         ; $1D19  one fewer
        BPL undo_slide_loop             ; $1D1B  more
        LDA #$00                        ; $1D1D
        STA $0106,X                     ; $1D1F  no hold
        STA $4FC3,X                     ; $1D22  the two oldest generations, left stale by the slide
        STA $4FC6,X                     ; $1D25
        STA $4FC9,X                     ; $1D28
        STA $4FCC,X                     ; $1D2B
        STA $4FCF,X                     ; $1D2E
        STA $4FD2,X                     ; $1D31
        STA $4FD5,X                     ; $1D34
        STA $4FD8,X                     ; $1D37
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
        LDA #$18                        ; $1D66
        STA state,X                     ; $1D68  pushed out
        LDA #$40                        ; $1D6A
        STA timer,X                     ; $1D6C  $40 frames
        RTS                             ; $1D6E

; One actor, for the X register passed in. The state timer gates the scripted mover.
actor_tick:
        STA $C8,X                       ; $1D6F  A from the caller. Bit 0 set refuses move_up
        LDA #$FF                        ; $1D71
        STA $C5,X                       ; $1D73  $FF. Nothing in this listing reads $C5,X
        LDA #$00                        ; $1D75
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
        TXA                             ; $1D84
        BEQ bruce_fall                  ; $1D85  Bruce
        LDA hit,X                       ; $1D87  the full hit
        AND #$05                        ; $1D89  ground or ladder
        BEQ fall_drop                   ; $1D8B  neither: keep falling
        LDA facing,X                    ; $1D8D
        CMP #$01                        ; $1D8F  facing right?
        BNE enemy_fall_left             ; $1D91
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
        BEQ bruce_fall_drift_left       ; $1DA5
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
        JMP set_state                   ; $1DC1
begin_fall:
        LDA #$02                        ; $1DC4
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
        JMP set_state                   ; $1E05
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
        JMP set_state                   ; $1E46
duck_from_down:
        TXA                             ; $1E49
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
        JMP clear_state                 ; $1E83

; One step left, if xpos is still above $0D. Facing becomes 0 and the state becomes 3 until
; the caller replaces it. Bit 3 is not tested. A wall is push_out's job on
; the next frame, from the count stored at $4F5D,X.
move_left:
        LDA xpos,X                      ; $1E86  xpos
        CMP #$0D                        ; $1E88  the left edge?
        BCC stop_move                   ; $1E8A  past it: refused
        DEC xpos,X                      ; $1E8C  one step left
        INC $4F5D,X                     ; $1E8E  count the left step
        LDA #$00                        ; $1E91
        STA facing,X                    ; $1E93  facing left
        LDA #$03                        ; $1E95  walk left
        JMP set_state                   ; $1E97
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
        LDA #$01                        ; $1ECF
        STA facing,X                    ; $1ED1  facing right
        LDA #$04                        ; $1ED3  walk right
        JMP set_state                   ; $1ED5
stick_down_left:
; $09: down and left. A ladder clears the state. On the ground Bruce ducks,
; state $1A, facing left, unless xpos has reached $A2.
        CMP #$09                        ; $1ED8
        BNE stick_down_right            ; $1EDA  not down and left
        TXA                             ; $1EDC
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
        LDA #$00                        ; $1EF1
        STA facing,X                    ; $1EF3  facing left
        LDA #$1A                        ; $1EF5  duck
        JMP set_state                   ; $1EF7
yamo_down:
        CMP #$01                        ; $1EFA  Yamo?
        BNE stick_clear                 ; $1EFC  no: clear the state
        LDA hit,X                       ; $1EFE  the full hit
        AND #$04                        ; $1F00  ladder?
        BNE stick_clear                 ; $1F02  yes: clear the state
        JMP yamo_appear                 ; $1F04  Yamo's first picture
stick_clear:
        JMP clear_state                 ; $1F07
stick_down_right:
; $05: down and right. The duck faces right unless xpos is below $10.
        CMP #$05                        ; $1F0A
        BNE stick_jump_or_punch         ; $1F0C  not down and right
        TXA                             ; $1F0E
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
        LDA #$01                        ; $1F23
        STA facing,X                    ; $1F25  facing right
        LDA #$1A                        ; $1F27  duck
        JMP set_state                   ; $1F29
; Wall bit 3 goes to try_punch and does not jump. Effect $80 plays
; when the sideways jump is taken: $0A left, $06 right, not a ladder.
stick_jump_or_punch:
        PHA                             ; $1F2C
        LDA hit,X                       ; $1F2D
        AND #$08                        ; $1F2F
        BEQ stick_jump_left             ; $1F31
        PLA                             ; $1F33
        JMP try_punch                   ; $1F34
stick_jump_left:
        PLA                             ; $1F37
        CMP #$0A                        ; $1F38
        BNE stick_jump_right            ; $1F3A
        LDA hit,X                       ; $1F3C
        AND #$04                        ; $1F3E
        BNE ladder_refuse               ; $1F40
        LDA #$00                        ; $1F42
        STA facing,X                    ; $1F44
        JSR score_blip                  ; $1F46
        LDA #$06                        ; $1F49
        JMP set_state_15                ; $1F4B
stick_jump_right:
        CMP #$06                        ; $1F4E
        BNE try_punch                   ; $1F50
        LDA hit,X                       ; $1F52
        AND #$04                        ; $1F54
        BNE ladder_refuse               ; $1F56
        LDA #$01                        ; $1F58
        STA facing,X                    ; $1F5A
        JSR score_blip                  ; $1F5C
        LDA #$07                        ; $1F5F
        JMP set_state_15                ; $1F61

; Flying kick to the left. Facing 0, state $0C, timer 12.
begin_kick_left:
        LDA #$00                        ; $1F64
        STA facing,X                    ; $1F66
        LDA #$0C                        ; $1F68
        JMP set_state_12                ; $1F6A

; Flying kick to the right. Facing 1, state $0D, timer 12.
begin_kick_right:
        LDA #$01                        ; $1F6D
        STA facing,X                    ; $1F6F
        LDA #$0D                        ; $1F71
        JMP set_state_12                ; $1F73

; Fire with no direction. State $11, then begin_punch forces the timer to 4.
try_punch:
        CMP #$0F                        ; $1F76
        BNE clear_state                 ; $1F78
        LDA $9B,X                       ; $1F7A
        BNE clear_state                 ; $1F7C
; try_punch after the stick and button tests. On a ladder the punch is
; refused and the state is cleared.
punch_unless_ladder:
        LDA hit,X                       ; $1F7E
        AND #$04                        ; $1F80
        BNE clear_state                 ; $1F82
        LDA #$11                        ; $1F84
        JMP begin_punch                 ; $1F86

; State 0 and timer 0. If $C2,X is 0, $4FDB,X is incremented first.
; The picture hold from the state table is still stored.
clear_state:
        LDA $C2,X                       ; $1F89
        BNE clear_state_store           ; $1F8B
        INC $4FDB,X                     ; $1F8D
clear_state_store:
        LDA #$00                        ; $1F90
; A is the new state. The picture hold comes from $4A8C+state, and the
; timer is 0, so actor_tick does not run a script for it.
set_state:
        STA state,X                     ; $1F92
        TAY                             ; $1F94
        LDA $4A8C,Y                     ; $1F95
        STA $0106,X                     ; $1F98
        LDA #$00                        ; $1F9B
        STA timer,X                     ; $1F9D
        RTS                             ; $1F9F

; Store A as the state and start the timer at 15. The standing jump and both sideways jumps
; use this.
set_state_15:
        STA state,X                     ; $1FA0
        TAY                             ; $1FA2
        LDA $4A8C,Y                     ; $1FA3
        STA $0106,X                     ; $1FA6
        LDA #$0F                        ; $1FA9
        STA timer,X                     ; $1FAB
        RTS                             ; $1FAD

; Store A as the state and start the timer at 12. Both flying kicks use this.
set_state_12:
        STA state,X                     ; $1FAE
        TAY                             ; $1FB0
        LDA $4A8C,Y                     ; $1FB1
        STA $0106,X                     ; $1FB4
        LDA #$0C                        ; $1FB7
        STA timer,X                     ; $1FB9
        RTS                             ; $1FBB

; A is already $11. set_state_12 records that state, then the timer is replaced with 4.
; That is the punch.
begin_punch:
        JSR set_state_12                ; $1FBC
        LDA #$04                        ; $1FBF
        STA timer,X                     ; $1FC1
        RTS                             ; $1FC3
; Effect $80, the movement chirp. Walk, climb, the sideways jump, and
; a pure-direction carry step. add_score does not call it. A chase
; step starts past the walk's call, so it is silent.
; $0CD9 is a BCD counter for this effect, not the player score at $41.
; It increments unless $1166 is set, and the compare with $99 is what
; shows those digits are BCD. A second counter at $1C14 moves only
; when the check byte $2007 is zero.
score_blip:
        PHA                             ; $1FC4
        TXA                             ; $1FC5
        PHA                             ; $1FC6
        TYA                             ; $1FC7
        PHA                             ; $1FC8
        LDY #$80                        ; $1FC9
        JSR play_sound                  ; $1FCB
        LDA $1166                       ; $1FCE
        BNE blip_check_second           ; $1FD1
        INC $0CD9                       ; $1FD3
        INC $0CDC                       ; $1FD6
        LDA $0CD9                       ; $1FD9
        CMP #$99                        ; $1FDC
        BCC blip_check_second           ; $1FDE
        LDA #$9A                        ; $1FE0
        STA $1159                       ; $1FE2
blip_check_second:
        LDA $2007                       ; $1FE5
        BNE blip_done                   ; $1FE8
        INC $1C14                       ; $1FEA
        INC $1C17                       ; $1FED
        LDA $1C14                       ; $1FF0
        CMP #$9A                        ; $1FF3
        BCC blip_done                   ; $1FF5
        LDX #$04                        ; $1FF7
        LDA #$9A                        ; $1FF9
        STA $1FFE                       ; $1FFB
        CLC                             ; $1FFE
blip_done:
        PLA                             ; $1FFF
        TAY                             ; $2000
        PLA                             ; $2001
        TAX                             ; $2002
        PLA                             ; $2003
        RTS                             ; $2004
        .byte $00, $00, $04


; Scripted motion. Y is timer,X from before this frame's decrement. It is copied to $52,
; which the state compares use. keep_state then decrements $52 and writes it back to
; timer,X.
move_for_state:
        STY $52                         ; $2008
        LDA state,X                     ; $200A
        CMP #$05                        ; $200C
        BNE state_kick_left             ; $200E
        LDA hit,X                       ; $2010
        AND #$04                        ; $2012
        BNE script_land_if_set          ; $2014
        CPY #$0D                        ; State 5, standing jump. The compares are on the timer in Y.
        BCS jump_keep                   ; $2018
        CPY #$02                        ; $201A
        BCC jump_keep                   ; $201C
        CPY #$08                        ; $201E
        BCS jump_rise                   ; $2020
        LDA hit,X                       ; $2022
        AND #$01                        ; $2024
        BNE script_land_if_set          ; $2026
        JSR move_down                   ; Timers 2 through 7: two steps down.
        JSR move_down                   ; $202B
jump_keep:
        LDA #$05                        ; $202E
        JMP keep_state                  ; $2030
jump_rise:
        CPY #$0C                        ; $2033
        BNE jump_rise_two               ; $2035
        JSR move_up                     ; Timer 12: four steps up.
        JSR move_up                     ; $203A
jump_rise_two:
        JSR move_up                     ; $203D
        JSR move_up                     ; $2040
        LDA #$05                        ; $2043
        JMP keep_state                  ; $2045
state_kick_left:
        CMP #$0C                        ; State $0C, flying kick left. One step sideways on every count.
        BNE state_kick_right            ; $204A
        LDA hit,X                       ; $204C
        AND #$0C                        ; $204E
        BNE script_land_if_set          ; $2050
; Timer still $0C, and the ladder and wall tests above have passed.
; Effect $84. Bruce and the fighters share this kick.
        CPY #$0C                        ; $2052
        BNE kick_left_steps             ; $2054
        STX $51                         ; $2056
        LDY #$84                        ; $2058
        JSR play_sound                  ; $205A
        LDX $51                         ; $205D
        LDY $52                         ; $205F
kick_left_steps:
        CPY #$0A                        ; $2061
        BCC kick_left_glide             ; $2063
        JSR move_up                     ; $2065
        JSR move_left                   ; $2068
        LDA #$0C                        ; $206B
        JMP keep_state                  ; $206D
kick_left_glide:
        CPY #$03                        ; $2070
        BCC kick_left_land_test         ; $2072
        JSR move_left                   ; $2074
        LDA #$0C                        ; $2077
        JMP keep_state                  ; $2079
kick_left_land_test:
        LDA hit,X                       ; $207C
        AND #$01                        ; $207E
script_land_if_set:
        BNE script_land                 ; $2080
        JSR move_down                   ; $2082
        JSR move_left                   ; $2085
        LDA #$0C                        ; $2088
        JMP keep_state                  ; $208A
state_kick_right:
        CMP #$0D                        ; State $0D, flying kick right.
        BNE state_jump_left             ; $208F
        LDA hit,X                       ; $2091
        AND #$0C                        ; $2093
        BNE script_land                 ; $2095
; Timer still $0C, and the ladder and wall tests above have passed.
; Effect $84.
        CPY #$0C                        ; $2097
        BNE kick_right_steps            ; $2099
        STX $51                         ; $209B
        LDY #$84                        ; $209D
        JSR play_sound                  ; $209F
        LDX $51                         ; $20A2
        LDY $52                         ; $20A4
kick_right_steps:
        CPY #$0A                        ; $20A6
        BCC kick_right_glide            ; $20A8
        JSR move_up                     ; $20AA
        JSR move_right                  ; $20AD
        LDA #$0D                        ; $20B0
        JMP keep_state                  ; $20B2
kick_right_glide:
        CPY #$03                        ; $20B5
        BCC kick_right_land_test        ; $20B7
        JSR move_right                  ; $20B9
        LDA #$0D                        ; $20BC
        JMP keep_state                  ; $20BE
kick_right_land_test:
        LDA hit,X                       ; $20C1
        AND #$01                        ; $20C3
        BNE script_land                 ; $20C5
        JSR move_down                   ; $20C7
        JSR move_right                  ; $20CA
        LDA #$0D                        ; $20CD
        JMP keep_state                  ; $20CF
state_jump_left:
        CMP #$06                        ; State 6, sideways jump left. Two steps sideways on every count.
        BNE state_jump_right            ; $20D4
        LDA hit,X                       ; $20D6
        AND #$04                        ; $20D8
        BNE script_land                 ; $20DA
        CPY #$0A                        ; $20DC
        BCC jump_left_level             ; $20DE
        BEQ jump_left_rise              ; $20E0
        JSR move_up                     ; $20E2
jump_left_rise:
        JSR move_up                     ; $20E5
        JSR move_left                   ; $20E8
        JSR move_left                   ; $20EB
        LDA #$06                        ; $20EE
        JMP keep_state                  ; $20F0
script_land:
        JMP land                        ; $20F3
jump_left_level:
        CPY #$07                        ; $20F6
        BCC jump_left_descend           ; $20F8
        JSR move_left                   ; $20FA
        JSR move_left                   ; $20FD
        LDA #$06                        ; $2100
        JMP keep_state                  ; $2102
jump_left_descend:
        LDA hit,X                       ; $2105
        AND #$01                        ; $2107
        BNE script_land                 ; $2109
        JSR move_left                   ; $210B
        JSR move_left                   ; $210E
        CPY #$06                        ; $2111
        BEQ jump_left_drop              ; $2113
        JSR move_down                   ; $2115
jump_left_drop:
        JSR move_down                   ; $2118
        LDA #$06                        ; $211B
        JMP keep_state                  ; $211D
state_jump_right:
        CMP #$07                        ; State 7, sideways jump right.
        BNE state_shocked               ; $2122
        LDA hit,X                       ; $2124
        AND #$04                        ; $2126
        BNE script_land                 ; $2128
        CPY #$0A                        ; $212A
        BCC jump_right_level            ; $212C
        BEQ jump_right_rise             ; $212E
        JSR move_up                     ; $2130
jump_right_rise:
        JSR move_up                     ; $2133
        JSR move_right                  ; $2136
        JSR move_right                  ; $2139
        LDA #$07                        ; $213C
        JMP keep_state                  ; $213E
jump_right_level:
        CPY #$07                        ; $2141
        BCC jump_right_descend          ; $2143
        JSR move_right                  ; $2145
        JSR move_right                  ; $2148
        LDA #$07                        ; $214B
        JMP keep_state                  ; $214D
jump_right_descend:
        LDA hit,X                       ; $2150
        AND #$01                        ; $2152
        BNE script_land                 ; $2154
        JSR move_right                  ; $2156
        JSR move_right                  ; $2159
        CPY #$06                        ; $215C
        BEQ jump_right_drop             ; $215E
        JSR move_down                   ; $2160
jump_right_drop:
        JSR move_down                   ; $2163
        LDA #$07                        ; $2166
        JMP keep_state                  ; $2168
state_shocked:
        CMP #$19                        ; $216B
        BNE state_ride                  ; $216D
        CPX #$00                        ; $216F
        BNE shocked_keep                ; $2171
        CPY #$01                        ; $2173
        BEQ shocked_lose_life           ; $2175
shocked_keep:
        JMP keep_state                  ; $2177
shocked_lose_life:
        JMP lose_life                   ; $217A
ride_land:
        JMP land                        ; $217D
state_ride:
        CMP #$17                        ; $2180
        BEQ ride_surface                ; $2182
        JMP state_yamo_rise             ; $2184
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
        LDA hit,X                       ; $2187
        AND #$04                        ; $2189
        BEQ ride_land                   ; $218B
        LDA #$01                        ; $218D
        STA $AA,X                       ; $218F
        TXA                             ; $2191
        BEQ ride_wait                   ; $2192
        LDA $42CA                       ; $2194
        BNE ride_wait                   ; $2197
        LDA facing,X                    ; $2199
        CMP #$01                        ; $219B
        BNE ride_stick_left             ; $219D
        LDA #$07                        ; $219F
        STA $98,X                       ; $21A1
        BNE ride_wait                   ; $21A3
ride_stick_left:
        LDA #$0B                        ; $21A5
        STA $98,X                       ; $21A7
ride_wait:
        LDA $AD,X                       ; $21A9
        BEQ carry_step                  ; $21AB
        DEC $AD,X                       ; $21AD
        JMP shove_with_surface          ; $21AF
; $AD has run out. Two pixels, and only a pure direction. A diagonal
; leaves $AA set and does not arm the next wait.
carry_step:
        LDA $98,X                       ; $21B2
        CMP #$0E                        ; $21B4
        BNE carry_step_down             ; $21B6
        JSR move_up                     ; $21B8
        JSR move_up                     ; $21BB
        JMP own_step_taken              ; $21BE
carry_step_down:
        CMP #$0D                        ; $21C1
        BNE carry_step_left             ; $21C3
        JSR move_down                   ; $21C5
        JSR move_down                   ; $21C8
        JMP own_step_taken              ; $21CB
carry_step_left:
        CMP #$0B                        ; $21CE
        BNE carry_step_right            ; $21D0
        JSR move_left                   ; $21D2
        JSR move_left                   ; $21D5
        JMP own_step_taken              ; $21D8
carry_step_right:
        CMP #$07                        ; $21DB
        BNE shove_with_surface          ; $21DD
        JSR move_right                  ; $21DF
        JSR move_right                  ; $21E2
; His own step was taken. $AA shifts to 0, so pose_carry will flip, and
; the next step waits four frames. Effect $80. Bruce and a carried
; fighter both reach this, on a pure-direction step.
own_step_taken:
        LSR $AA,X                       ; $21E5
        LDA #$04                        ; $21E7
        STA $AD,X                       ; $21E9
        JSR score_blip                  ; $21EB
; State $17. The stick has already stepped him two pixels. $60 is read
; after scroll_surface, so a 1 here is the frame before that copy. The
; compare is exact: the $84 pause has bit 7 set and does not shove. $65
; clear moves him up two pixels, the same two rows one pattern byte covers.
; $65 set moves him down.
shove_with_surface:
        LDA $60                         ; $21EE
        CMP #$01                        ; $21F0
        BNE ride_finish                 ; $21F2
        LDA $65                         ; $21F4
        BEQ shove_up                    ; $21F6
        JSR move_down                   ; $21F8
        JSR move_down                   ; $21FB
        JMP ride_finish                 ; $21FE
shove_up:
        JSR move_up                     ; $2201
        JSR move_up                     ; $2204
; Stick back to none, and fire released. $52 still holds the timer from
; the start of move_for_state. The increment cancels the decrement in
; keep_state, so the $10 catch_surface stored is not consumed. The steps
; above zeroed that timer on their way through set_state, and this write
; puts it back. The two counters are then reduced to the difference.
; $4F57 keeps the extra upward pixels, $4F5A the extra downward ones, and
; the other is cleared. A frame that stepped both ways records only the
; net. exit_allowed reads $4F57 and does not read $4F5A.
ride_finish:
        LDA #$0F                        ; $2207
        STA $98,X                       ; $2209
        LDA #$01                        ; $220B
        STA $9B,X                       ; $220D
        INC $52                         ; $220F
        LDA $4F57,X                     ; $2211
        SEC                             ; $2214
        SBC $4F5A,X                     ; $2215
        BPL ride_net_up                 ; $2218
        EOR #$FF                        ; $221A
        ADC #$01                        ; $221C
        STA $4F5A,X                     ; $221E
        LDA #$00                        ; $2221
        STA $4F57,X                     ; $2223
        BEQ ride_keep                   ; $2226
ride_net_up:
        STA $4F57,X                     ; $2228
        LDA #$00                        ; $222B
        STA $4F5A,X                     ; $222D
ride_keep:
        LDA #$17                        ; $2230
        JMP keep_state                  ; $2232
state_yamo_rise:
        CMP #$10                        ; $2235
        BNE state_punch                 ; $2237
        LDA timer,X                     ; $2239
        CMP #$01                        ; $223B
        BEQ yamo_appear                 ; $223D
        LDA #$10                        ; $223F
        JMP keep_state                  ; $2241
yamo_appear:
        LDA xpos,X                      ; $2244
        CMP xpos                        ; $2246
        BCC yamo_appear_right           ; $2248
        LDA #$00                        ; $224A
yamo_appear_store:
        STA facing,X                    ; $224C
        LDA #$12                        ; $224E
        STA state,X                     ; $2250
        LDA #$10                        ; $2252
        STA timer,X                     ; $2254
        LDA #$00                        ; $2256
        STA $0106,X                     ; $2258
        TXA                             ; $225B
        PHA                             ; $225C
; Effect $81. State $10's timer was exactly 1, so Yamo is appearing.
        LDY #$81                        ; $225D
        JSR play_sound                  ; $225F
        PLA                             ; $2262
        TAX                             ; $2263
        RTS                             ; $2264
yamo_appear_right:
        LDA #$01                        ; $2265
        JMP yamo_appear_store           ; $2267
state_punch:
        CMP #$11                        ; $226A
        BNE try_strike                  ; $226C
        LDA hit,X                       ; $226E
        AND #$0C                        ; $2270
        BNE land_if_wall                ; $2272
; Compared with 8. begin_punch stores 4, so this never plays.
; Effect $85 is the strike below, not the punch.
        CPY #$08                        ; $2274
        BNE punch_keep                  ; $2276
        STX $51                         ; $2278
        LDY #$85                        ; $227A
        JSR play_sound                  ; $227C
        LDX $51                         ; $227F
        LDY $52                         ; $2281
punch_keep:
        CPY #$01                        ; $2283
        BEQ stand_down                  ; $2285
        LDA #$11                        ; $2287
        JMP keep_state                  ; $2289
; State 0 and timer 6, and the pose hold is cleared. A timer still running
; keeps actor_tick inside move_for_state, so these frames do not fall.
; Bruce: a long or middle visit doubles the 6, a short visit halves it.
; Another fighter: a long visit or a set $40 stores 1, a middle visit
; halves the 6, and a short visit with $40 clear keeps 6. The kick path in
; enemy_turn calls this and then stores $18 over the timer.
stand_down:
        LDA #$00                        ; $228C
        STA state,X                     ; $228E
        LDA #$06                        ; $2290
        STA timer,X                     ; $2292
        LDA #$00                        ; $2294
        STA $0106,X                     ; $2296
        TXA                             ; $2299
        BNE stand_down_enemy            ; $229A
        JSR test_visit                  ; $229C
        BVS stand_down_double           ; $229F
        BCS stand_down_double           ; $22A1
        LSR timer,X                     ; $22A3
        RTS                             ; $22A5
stand_down_enemy:
        JSR test_visit                  ; $22A6
        BVS stand_down_short            ; $22A9
        BCS stand_down_halve            ; $22AB
        LDA $40                         ; $22AD
        BNE stand_down_short            ; $22AF
        RTS                             ; $22B1
stand_down_halve:
        LSR timer,X                     ; $22B2
        RTS                             ; $22B4
stand_down_double:
        ASL timer,X                     ; $22B5
        RTS                             ; $22B7
stand_down_short:
        LDA #$01                        ; $22B8
        STA timer,X                     ; $22BA
        RTS                             ; $22BC
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
        CMP #$16                        ; $22BD
        BNE state_chase                 ; $22BF
        LDA hit,X                       ; $22C1
        AND #$08                        ; $22C3
land_if_wall:
        BEQ strike_sound                ; $22C5
        JMP land                        ; $22C7
strike_sound:
; Timer still $0C, and wall bit 3 did not end the strike. Effect $85.
        CPY #$0C                        ; $22CA
        BNE strike_push                 ; $22CC
        STX $51                         ; $22CE
        LDY #$85                        ; $22D0
        JSR play_sound                  ; $22D2
        LDX $51                         ; $22D5
        LDY $52                         ; $22D7
strike_push:
        CPY #$01                        ; $22D9
        BEQ strike_done                 ; $22DB
        LDA facing,X                    ; $22DD
        CMP #$01                        ; $22DF
        BNE strike_push_left            ; $22E1
        INC $4F60,X                     ; $22E3
        BNE strike_keep                 ; $22E6
strike_push_left:
        INC $4F5D,X                     ; $22E8
strike_keep:
        LDA #$16                        ; $22EB
        JMP keep_state                  ; $22ED
strike_done:
        JMP stand_down                  ; $22F0
state_chase:
        CMP #$14                        ; $22F3
        BEQ chase_test                  ; $22F5
        JMP state_sidestep              ; $22F7
chase_test:
        LDA hit,X                       ; $22FA
        AND #$01                        ; $22FC
        BEQ chase_ladder                ; $22FE
        JSR range_to_bruce              ; $2300
        LDA $62                         ; $2303
        AND #$7F                        ; $2305
        CMP #$10                        ; $2307
        BCS bruce_above                 ; $2309
        LDA facing,X                    ; $230B
        LDY $63                         ; $230D
        BMI chase_facing_test           ; $230F
        EOR #$01                        ; $2311
chase_facing_test:
        CMP #$01                        ; $2313
        BEQ facing_bruce                ; $2315
        TYA                             ; $2317
        AND #$7F                        ; $2318
        CMP #$21                        ; $231A
        BCC start_sidestep              ; $231C
        LDA facing,X                    ; $231E
        EOR #$01                        ; $2320
        STA facing,X                    ; $2322
        JMP chase_walk                  ; $2324
; Not facing Bruce, and |dx| is below $21. State $15, and no walk on
; this frame. The timer is the distance to Bruce's xpos plus or minus
; $0F, and at least 5. push_out has usually just left him facing away
; from the wall. This sidestep then walks that way, so a close Bruce
; on the far side of the wall does not turn him back into it. |dx| of
; $21 or more is the branch above: facing flips and chase_walk runs
; on this same frame, back toward Bruce.
start_sidestep:
        LDA xpos                        ; $2327
        LDY $63                         ; $2329
        BPL sidestep_right_target       ; $232B
        SEC                             ; $232D
        SBC #$0F                        ; $232E
        BNE sidestep_distance           ; $2330
sidestep_right_target:
        CLC                             ; $2332
        ADC #$0F                        ; $2333
sidestep_distance:
        SEC                             ; $2335
        SBC xpos,X                      ; $2336
        BCS sidestep_min                ; $2338
        EOR #$FF                        ; $233A
        ADC #$01                        ; $233C
sidestep_min:
        CMP #$05                        ; $233E
        BCS sidestep_store              ; $2340
        LDA #$05                        ; $2342
sidestep_store:
        STA timer,X                     ; $2344
        LDA #$15                        ; $2346
        STA state,X                     ; $2348
        LDA #$00                        ; $234A
        STA $0106,X                     ; $234C
        STA $C8,X                       ; $234F
        RTS                             ; $2351
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
        LDA facing,X                    ; $2352
        CMP #$01                        ; $2354
        BNE chase_walk_left             ; $2356
        JSR right_two_steps             ; $2358
; Both walk directions finish here.
keep_chase:
        INC $52                         ; $235B
        LDA #$14                        ; $235D
        JMP keep_state                  ; $235F
; |dy| is at least $10, and hit bit 0 was set. Bit 7 of $62 means this
; fighter is above Bruce, so he keeps walking at chase_walk. Bruce above:
; face_from_dx, then stand_down. chase_ladder is the bit-0-clear path,
; and that one walks without this compare. Neither path climbs.
bruce_above:
        LDA $62                         ; $2362
        BMI chase_walk                  ; $2364
        JSR face_from_dx                ; $2366
        JMP stand_down                  ; $2369
chase_walk_left:
        JSR left_two_steps              ; $236C
        JMP keep_chase                  ; $236F
; Ground bit clear. The ladder bit walks, at chase_walk. Neither bit
; set falls. This is a ladder with no floor under him, and he does not
; climb it.
chase_ladder:
        LDA hit,X                       ; $2372
        AND #$04                        ; $2374
        BNE chase_walk                  ; $2376
chase_fall:
        JMP begin_fall                  ; $2378
; Facing Bruce. Active $81 is Yamo. |dx| below 5 sidesteps, below
; $0C punches, below $13 starts the flying kick, and anything farther
; walks. The ninja walks at $0B or more, sidesteps below 5, and the distances
; in between are state $16 with timer $13.
facing_bruce:
        LDA active,X                    ; $237B
        AND #$81                        ; $237D
        CMP #$81                        ; $237F
        BNE facing_ninja                ; $2381
        LDA $63                         ; $2383
        AND #$7F                        ; $2385
        CMP #$05                        ; $2387
facing_close:
        BCC start_sidestep              ; $2389
        CMP #$0C                        ; $238B
        BCS facing_kick                 ; $238D
        JSR punch_unless_ladder         ; $238F
        LDA state,X                     ; $2392
        CMP #$11                        ; $2394
        BNE facing_punch_refused        ; $2396
        RTS                             ; $2398
facing_punch_refused:
        JMP stand_down                  ; $2399
facing_kick:
        CMP #$13                        ; $239C
        BCS chase_walk                  ; $239E
        LDA facing,X                    ; $23A0
        CMP #$01                        ; $23A2
        BEQ facing_kick_right           ; $23A4
        LDA #$0C                        ; $23A6
facing_kick_store:
        STA state,X                     ; $23A8
        LDA #$0C                        ; $23AA
        STA timer,X                     ; $23AC
        LDA #$00                        ; $23AE
        STA $0106,X                     ; $23B0
        RTS                             ; $23B3
facing_kick_right:
        LDA #$0D                        ; $23B4
        BNE facing_kick_store           ; $23B6
facing_ninja:
        LDA $63                         ; $23B8
        AND #$7F                        ; $23BA
        CMP #$0B                        ; $23BC
        BCS chase_walk                  ; $23BE
        CMP #$05                        ; $23C0
        BCC facing_close                ; $23C2
        LDA #$16                        ; $23C4
        STA state,X                     ; $23C6
        LDA #$13                        ; $23C8
        STA timer,X                     ; $23CA
        RTS                             ; $23CC
; State $15, the sidestep. Bit 0 clear is a fall, ladder or otherwise.
; Timer 1 turns him around and stores state $14 with timer $80.
state_sidestep:
        CMP #$15                        ; $23CD
        BNE state_rising                ; $23CF
        LDA hit,X                       ; $23D1
        AND #$01                        ; $23D3
        BEQ chase_fall                  ; $23D5
        LDA timer,X                     ; $23D7
        CMP #$01                        ; $23D9
        BNE sidestep_walk               ; $23DB
        LDA facing,X                    ; $23DD
        EOR #$01                        ; $23DF
        STA facing,X                    ; $23E1
        LDA #$14                        ; $23E3
        STA state,X                     ; $23E5
        LDA #$00                        ; $23E7
        STA $0106,X                     ; $23E9
        LDA #$80                        ; $23EC
        STA timer,X                     ; $23EE
        RTS                             ; $23F0
sidestep_walk:
        LDA facing,X                    ; $23F1
        CMP #$01                        ; $23F3
        BNE sidestep_walk_left          ; $23F5
        JSR right_two_steps             ; $23F7
        LDA #$15                        ; $23FA
        JMP keep_state                  ; $23FC
sidestep_walk_left:
        JSR left_two_steps              ; $23FF
        LDA #$15                        ; $2402
        JMP keep_state                  ; $2404
state_rising:
        CMP #$12                        ; $2407
        BNE state_flinch                ; $2409
        JMP keep_state                  ; $240B
state_flinch:
; State $0F, the flinch. A non-Bruce whose timer in Y is below 2 goes to
; stand_down. Facing right slides two steps left, facing left two steps
; right, and the facing is written back. The picture is the stand.
        CMP #$0F                        ; $240E
        BNE state_knockdown             ; $2410
        TXA                             ; $2412
        BEQ flinch_slide                ; $2413
        CPY #$02                        ; $2415
        BCC flinch_done                 ; $2417
flinch_slide:
        LDA facing,X                    ; $2419
        CMP #$01                        ; $241B
        BNE flinch_slide_right          ; $241D
        JSR move_left                   ; $241F
        JSR move_left                   ; $2422
        LDA #$01                        ; $2425
        STA facing,X                    ; $2427
        LDA #$0F                        ; $2429
        JMP keep_state                  ; $242B
flinch_slide_right:
        JSR move_right                  ; $242E
        JSR move_right                  ; $2431
        LDA #$00                        ; $2434
        STA facing,X                    ; $2436
        LDA #$0F                        ; $2438
        JMP keep_state                  ; $243A
flinch_done:
        JMP stand_down                  ; $243D
; State $13, the knockdown. A non-Bruce whose $D1 is still positive leaves
; through stand_down once Y is below 2. Negative $D1 stays here until the
; timer reaches 0 and check_bruce_down removes him. Bits 0 and 2 both clear
; drops one pixel. Facing right slides left, facing left slides right, two
; steps, and the facing is written back. The ninja on the frame Y is $0A adds
; eight steps to that left slide, or four steps to that right slide.
state_knockdown:
        CMP #$13                        ; $2440
        BNE state_stuck                 ; $2442
        TXA                             ; $2444
        BEQ knockdown_slide             ; $2445
        LDA $D1,X                       ; $2447
        BMI knockdown_slide             ; $2449
        CPY #$02                        ; $244B
        BCC knockdown_done              ; $244D
knockdown_slide:
        LDA hit,X                       ; $244F
        AND #$05                        ; $2451
        BNE knockdown_dir               ; $2453
        JSR move_down                   ; $2455
knockdown_dir:
        LDA facing,X                    ; $2458
        CMP #$01                        ; $245A
        BNE knockdown_right             ; $245C
        CPY #$0A                        ; $245E
        BNE knockdown_left              ; $2460
        CPX #$02                        ; $2462
        BNE knockdown_left              ; $2464
        JSR move_left                   ; $2466
        JSR move_left                   ; $2469
        JSR move_left                   ; $246C
        JSR move_left                   ; $246F
        JSR move_left                   ; $2472
        JSR move_left                   ; $2475
        JSR move_left                   ; $2478
        JSR move_left                   ; $247B
knockdown_left:
        JSR move_left                   ; $247E
        JSR move_left                   ; $2481
        LDA #$01                        ; $2484
        STA facing,X                    ; $2486
        LDA #$13                        ; $2488
        JMP keep_state                  ; $248A
knockdown_right:
        CPY #$0A                        ; $248D
        BNE knockdown_right_steps       ; $248F
        CPX #$02                        ; $2491
        BNE knockdown_right_steps       ; $2493
        JSR move_right                  ; $2495
        JSR move_right                  ; $2498
        JSR move_right                  ; $249B
        JSR move_right                  ; $249E
knockdown_right_steps:
        JSR move_right                  ; $24A1
        JSR move_right                  ; $24A4
        LDA #$00                        ; $24A7
        STA facing,X                    ; $24A9
        LDA #$13                        ; $24AB
        JMP keep_state                  ; $24AD
knockdown_done:
        JMP stand_down                  ; $24B0
state_stuck:
        CMP #$18                        ; $24B3
        BNE keep_state                  ; $24B5
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
        LDA hit,X                       ; $24B7
        AND #$08                        ; $24B9
        BNE stuck_check_history         ; $24BB
        LDA #$01                        ; $24BD
        STA $52                         ; $24BF
        LDA #$18                        ; $24C1
        JMP keep_state                  ; $24C3
stuck_check_history:
        TXA                             ; $24C6
        PHA                             ; $24C7
        LDA #$00                        ; $24C8
        LDY #$27                        ; $24CA
stuck_or_history:
        ORA $4F63,X                     ; $24CC
        INX                             ; $24CF
        INX                             ; $24D0
        INX                             ; $24D1
        DEY                             ; $24D2
        BPL stuck_or_history            ; $24D3
        TAY                             ; $24D5
        PLA                             ; $24D6
        TAX                             ; $24D7
        TYA                             ; $24D8
        BNE undo_again                  ; $24D9
; Same registers as enter_room_at, for the room already in $29. finish_exit
; places him on that room's spawn. enter_room then runs, so room 11 can
; still open room 13 when rooms 12, 14, and 16 are clear. $51 is 0, so
; the life counter is not touched.
stuck_reenter:
        LDA #$00                        ; $24DB
        STA $51                         ; $24DD
        LDX $29                         ; $24DF
        STX $4E                         ; $24E1
        LDA $4BC2,X                     ; $24E3
        TAY                             ; $24E6
        LDA $4BAE,X                     ; $24E7
        JMP finish_exit                 ; $24EA
; An older counter was still set. $4C keeps the facing, and the undo
; runs again on this frame.
undo_again:
        LDA facing,X                    ; $24ED
        STA $4C                         ; $24EF
        JMP undo_steps                  ; $24F1

; A is the state to keep. $52 still holds the timer from the start of move_for_state. It is
; decremented here and stored back to timer,X.
keep_state:
        STA state,X                     ; $24F4
        TAY                             ; $24F6
        LDA $4A8C,Y                     ; $24F7
        STA $0106,X                     ; $24FA
        DEC $52                         ; Decrement after the state has used the old value.
        LDA $52                         ; $24FF
        STA timer,X                     ; $2501
        RTS                             ; $2503

; Leave the script. State 0, timer 0. A sideways jump that has started to fall uses this
; when it meets the ground.
land:
        LDA #$00                        ; $2504
        JMP set_state                   ; $2506
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
        LDA #$15                        ; $2509
        STA $D418                       ; $250B  SID volume and filter mode
        LDA $EB00                       ; $250E  slot 1 busy?
        BNE play_sound_try_2            ; $2511  yes: try slot 2
; Y goes into slot 1, $EB00, and the priority for its low nibble goes to $2581.
claim_voice_1:
        STY $EB00                       ; $2513  claim slot 1. Bit 7 of the id starts it
        TYA                             ; $2516
        AND #$0F                        ; $2517  the id's low nibble
        TAX                             ; $2519
        LDA $2572,X                     ; $251A  its priority
        STA $2581                       ; $251D  kept for slot 1
        RTS                             ; $2520
play_sound_try_2:
        LDA $EF70                       ; $2521  slot 2 busy?
        BNE play_sound_try_3            ; $2524  yes: try slot 3
; The same for slot 2, $EF70, with the priority at $2582.
claim_voice_2:
        STY $EF70                       ; $2526  claim slot 2
        TYA                             ; $2529
        AND #$0F                        ; $252A  the id's low nibble
        TAX                             ; $252C
        LDA $2572,X                     ; $252D  its priority
        STA $2582                       ; $2530  kept for slot 2
        RTS                             ; $2533
play_sound_try_3:
        LDA $F070                       ; $2534  slot 3 busy?
        BNE play_sound_replace          ; $2537  yes: all three are busy
; The same for slot 3, $F070, with the priority at $2583.
claim_voice_3:
        STY $F070                       ; $2539  claim slot 3
        TYA                             ; $253C
        AND #$0F                        ; $253D  the id's low nibble
        TAX                             ; $253F
        LDA $2572,X                     ; $2540  its priority
        STA $2583                       ; $2543  kept for slot 3
        RTS                             ; $2546
play_sound_replace:
        TYA                             ; $2547
        AND #$0F                        ; $2548  the id's low nibble
        TAX                             ; $254A
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
        LDA #$00                        ; $255E
        STA $EB00                       ; $2560  free slot 1
        STA $EF70                       ; $2563  free slot 2
        STA $F070                       ; $2566  free slot 3
        LDX #$20                        ; $2569  $D420 down to $D400
silence_sid_loop:
        STA $D400,X                     ; $256B  SID voice 1 frequency low, plus X
        DEX                             ; $256E
        BPL silence_sid_loop            ; $256F
        RTS                             ; $2571

; $2572  15 priority bytes, low nibbles 0 through $0E:
; 0B 0C 0A 00 08 07 09 06 00 00 01 02 03 04 05.
; $2581, $2582, $2583 are the live priorities of the three slots.
; Nibble $0F is not an effect id. That lookup would read $2581.

; For each active actor, copy his two sprite images into the hardware image slots.
blit_sprites:
        LDX #$02                        ; $2584
blit_loop:
        STX $51                         ; $2586
        LDA active,X                    ; $2588
        AND #$01                        ; $258A
        BEQ blit_next                   ; $258C
        LDA $276D,X                     ; $258E
        JSR blit_target                 ; $2591
        LDA $4F4E,X                     ; $2594
        TAX                             ; $2597
        JSR load_library                ; $2598
        PHA                             ; $259B
        TXA                             ; $259C
        LDX $51                         ; $259D
        STA $D4,X                       ; $259F
        PLA                             ; $25A1
        STA $DA,X                       ; $25A2
        TYA                             ; $25A4
        ASL A                           ; $25A5
        ADC $E0,X                       ; $25A6
        TAY                             ; $25A8
        LDA $D4,X                       ; $25A9
        JSR copy_sprite_image           ; $25AB
        LDX $51                         ; $25AE
; Actor 2 stops here. In the room 0 snapshot $276D is 00 02 04 and $2770
; is 01 03 FF: Bruce is sprites 0 and 1, Yamo is 2 and 3, the ninja is
; sprite 4. The $FF also makes the BMI below skip a second image.
        CPX #$02                        ; $25B0
        BEQ blit_next                   ; $25B2
        LDA $2770,X                     ; $25B4
        BMI blit_next                   ; $25B7
        JSR blit_target                 ; $25B9
        LDA $4F4E,X                     ; $25BC
        TAX                             ; $25BF
        INX                             ; $25C0
        JSR load_library                ; $25C1
        PHA                             ; $25C4
        TXA                             ; $25C5
        LDX $51                         ; $25C6
        STA $D7,X                       ; $25C8
        PLA                             ; $25CA
        STA $DD,X                       ; $25CB
        TYA                             ; $25CD
        ASL A                           ; $25CE
        ADC $E0,X                       ; $25CF
        TAY                             ; $25D1
        LDA $D7,X                       ; $25D2
        JSR copy_sprite_image           ; $25D4
blit_next:
        LDX $51                         ; $25D7
        DEX                             ; $25D9
        BPL blit_loop                   ; $25DA
        LDA #$00                        ; $25DC
        STA $277E                       ; $25DE
        RTS                             ; $25E1

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
        LDA $277E                       ; $25E2
        BEQ place_sprites_go            ; $25E5
        RTS                             ; $25E7
place_sprites_go:
        INC $277E                       ; $25E8
        LDX #$02                        ; $25EB
        STX $51                         ; $25ED
place_loop:
        LDA active,X                    ; $25EF
        AND #$01                        ; $25F1
        BEQ place_second                ; $25F3
        LDA xpos,X                      ; $25F5
        STA $B9,X                       ; $25F7
        LDY $D4,X                       ; $25F9
        BEQ place_first_x               ; $25FB
        LDY facing,X                    ; $25FD
        CPY #$01                        ; $25FF
        BEQ place_first_x               ; $2601
        SEC                             ; $2603
        SBC #$08                        ; $2604
place_first_x:
        ASL A                           ; $2606
        PHA                             ; $2607
        LDY $276D,X                     ; $2608
        LDA $D010                       ; $260B  sprite x bit 8
        BCC place_first_clear_high      ; $260E
        ORA $2773,Y                     ; $2610
        BNE place_first_store_high      ; $2613
place_first_clear_high:
        AND $2778,Y                     ; $2615
place_first_store_high:
        STA $D010                       ; $2618  sprite x bit 8
        TYA                             ; $261B
        ASL A                           ; $261C
        TAY                             ; $261D
        PLA                             ; $261E
        STA $D000,Y                     ; $261F  sprite 0 x, plus Y
        LDA ypos,X                      ; $2622
        CLC                             ; $2624
        ADC #$1D                        ; $2625
        STA $D001,Y                     ; $2627  sprite 0 y, plus Y
        LDY $276D,X                     ; $262A
        LDA $DA,X                       ; $262D
        STA $D027,Y                     ; $262F  sprite 0 color, plus Y
place_first_done:
        CPX #$02                        ; $2632
place_second:
        BEQ place_next                  ; $2634
        LDY $4F4B,X                     ; $2636
        LDA xpos,X                      ; $2639
        CPY #$05                        ; $263B
        BEQ place_second_shift          ; $263D
        CPY #$3F                        ; $263F
        BEQ place_second_shift          ; $2641
        CPY #$43                        ; $2643
        BEQ place_second_shift          ; $2645
        CPY #$19                        ; $2647
        BNE place_second_x              ; $2649
place_second_shift:
        SEC                             ; $264B
        SBC #$08                        ; $264C
place_second_x:
        ASL A                           ; $264E
        PHA                             ; $264F
        LDY $2770,X                     ; $2650
        LDA $D010                       ; $2653  sprite x bit 8
        BCC place_second_clear_high     ; $2656
        ORA $2773,Y                     ; $2658
        BNE place_second_store_high     ; $265B
place_second_clear_high:
        AND $2778,Y                     ; $265D
place_second_store_high:
        STA $D010                       ; $2660  sprite x bit 8
        TYA                             ; $2663
        ASL A                           ; $2664
        TAY                             ; $2665
        PLA                             ; $2666
        STA $D000,Y                     ; $2667  sprite 0 x, plus Y
        LDA ypos,X                      ; $266A
        CLC                             ; $266C
        ADC #$1D                        ; $266D
        STA $D001,Y                     ; $266F  sprite 0 y, plus Y
        LDY $2770,X                     ; $2672
        LDA $DD,X                       ; $2675
        STA $D027,Y                     ; $2677  sprite 0 color, plus Y
place_next:
        LDX $51                         ; $267A
        DEX                             ; $267C
        BMI place_pointers              ; $267D
        JMP place_loop                  ; $267F
place_pointers:
        LDX #$04                        ; $2682
        LDY #$04                        ; $2684
        LDA $277D                       ; $2686
        BEQ place_pointer_loop          ; $2689
        LDY #$09                        ; $268B
place_pointer_loop:
        LDA $2763,Y                     ; $268D
        STA $8FF8,X                     ; $2690
        DEY                             ; $2693
        DEX                             ; $2694
        BPL place_pointer_loop          ; $2695
        LDA $277D                       ; $2697
        EOR #$01                        ; $269A
        STA $277D                       ; $269C
        RTS                             ; $269F


; Copy one image from the library at $6667 into the sprite buffer at ($0E). A zero in A
; means the buffer is cleared instead.
copy_sprite_image:
        BNE copy_wide                   ; $26A0
        LDA #$3F                        ; $26A2
        STA $277F                       ; $26A4
        LDA $E0,X                       ; $26A7
        TAX                             ; $26A9
copy_narrow_row:
        LDA $6667,X                     ; $26AA
        STA ($0E),Y                     ; $26AD
        DEC $277F                       ; $26AF
        DEX                             ; $26B2
        BMI copy_clear_rest             ; $26B3
        DEY                             ; $26B5
        LDA #$00                        ; $26B6
        STA ($0E),Y                     ; $26B8
        DEC $277F                       ; $26BA
        DEY                             ; $26BD
        STA ($0E),Y                     ; $26BE
        DEC $277F                       ; $26C0
        DEY                             ; $26C3
        BPL copy_narrow_row             ; $26C4
copy_clear_rest:
        LDA $277F                       ; $26C6
        EOR #$3F                        ; $26C9
        TAY                             ; $26CB
        LDA #$00                        ; $26CC
copy_clear_loop:
        STA ($0E),Y                     ; $26CE
        INY                             ; $26D0
        DEC $277F                       ; $26D1
        BPL copy_clear_loop             ; $26D4
        RTS                             ; $26D6
copy_wide:
        LDA #$3F                        ; $26D7
        STA $277F                       ; $26D9
        LDA $E0,X                       ; $26DC
        ASL A                           ; $26DE
        TAX                             ; $26DF
        DEX                             ; $26E0
        DEY                             ; $26E1
        DEY                             ; $26E2
copy_wide_row:
        LDA $6667,X                     ; $26E3
        STA ($0E),Y                     ; $26E6
        DEC $277F                       ; $26E8
        DEX                             ; $26EB
        DEY                             ; $26EC
        LDA $6667,X                     ; $26ED
        STA ($0E),Y                     ; $26F0
        DEC $277F                       ; $26F2
        DEX                             ; $26F5
        BMI copy_clear_rest             ; $26F6
        DEY                             ; $26F8
        LDA #$00                        ; $26F9
        STA ($0E),Y                     ; $26FB
        DEC $277F                       ; $26FD
        DEY                             ; $2700
        BPL copy_wide_row               ; $2701
        BRK                             ; $2703
; A is a sprite slot. ($0E) becomes that slot's image address from
; $274F. $277D picks the half of the double buffer: when it is set the
; slot moves on ten entries, to the other set of images.
blit_target:
        ASL A                           ; $2704
        LDY $277D                       ; $2705
        BEQ blit_target_store           ; $2708
        CLC                             ; $270A
        ADC #$0A                        ; $270B
blit_target_store:
        TAY                             ; $270D
        LDA $274F,Y                     ; $270E
        STA $0E                         ; $2711
        LDA $2750,Y                     ; $2713
        STA $0F                         ; $2716
        RTS                             ; $2718
; Library X: pointer from $59BD/$5A8F, height from $5B61, color from
; $5C33. A returns the color, Y the height, X the $5CBF byte. $51 = 2
; stores $F0 in place of the table color. The VIC takes the low nibble, so
; The ninja is black. Yamo's table bytes are $F5 then $F0, green under
; black, except relative $04, $06, $18, $1C, and $3E, where the first byte
; is $F0 and the second is $F5. Those are the two punches, the extended
; kicks, and the late left knockdown.
load_library:
        LDA $59BD,X                     ; $2719
        STA $26AB                       ; $271C
        STA $26E4                       ; $271F
        STA $26EE                       ; $2722
        LDA $5A8F,X                     ; $2725
        STA $26AC                       ; $2728
        STA $26E5                       ; $272B
        STA $26EF                       ; $272E
        LDY $5B61,X                     ; $2731
        LDA #$02                        ; $2734
        CMP $51                         ; $2736
        BNE load_library_color          ; $2738
        LDA #$F0                        ; $273A
        BNE load_library_mode           ; $273C
load_library_color:
        LDA $5C33,X                     ; $273E
load_library_mode:
        PHA                             ; $2741
; X returns the $5CBF byte for this library. place_sprites shifts a
; left-facing body eight xpos when the byte is nonzero.
        LDA $5CBF,X                     ; $2742
        PHA                             ; $2745
        LDX $51                         ; $2746
        TYA                             ; $2748
        STA $E0,X                       ; $2749
        PLA                             ; $274B
        TAX                             ; $274C
        PLA                             ; $274D
choose_pose_done:
        RTS                             ; $274E

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
        LDA $4FDB,X                     ; $2780
        BNE choose_pose_done            ; $2783
        INC $4FDB,X                     ; $2785
        LDA $4F48,X                     ; $2788
        STA $4F54,X                     ; $278B
        LDY facing,X                    ; $278E
        LDA state,X                     ; $2790
; Fall. Bit 3 selects library 8, the legs together. Otherwise library $44,
; the arms. The two pictures do not cover the same cells. One pixel is
; enough for $44 to touch a wall that library 8 misses. Room 4's right lip
; is that case: see rooms.asm. $1CC7 then puts the pixel back.
        CMP #$0E                        ; $2792
        BNE pose_duck                   ; $2794
        LDA hit,X                       ; $2796
        AND #$08                        ; $2798
        BEQ pose_fall_arms              ; $279A
        LDY #$08                        ; $279C
        JMP store_pose                  ; $279E
pose_fall_arms:
        LDY #$44                        ; $27A1
        JMP store_pose                  ; $27A3
pose_duck:
        CMP #$1A                        ; $27A6  duck. Facing right is library $42, facing left is library $40.
        BNE pose_shocked                ; $27A8
        CPY #$01                        ; $27AA
        BNE pose_duck_left              ; $27AC
        LDY #$42                        ; $27AE
        JMP store_pose                  ; $27B0
pose_duck_left:
        LDY #$40                        ; $27B3
        JMP store_pose                  ; $27B5
pose_shocked:
        CMP #$19                        ; $27B8
        BNE pose_stuck                  ; $27BA
        LDY #$08                        ; $27BC
        JMP store_pose                  ; $27BE
; State $18. The library already showing is kept, unless it is $44 or
; either mode byte is set, in which case library 8 replaces it. The
; walk pictures are chosen for states $14 and $15, so the run keeps
; cycling only while those states last. This state freezes the picture.
pose_stuck:
        CMP #$18                        ; $27C1
        BNE pose_landed_on              ; $27C3
        LDY $4F54,X                     ; $27C5
        CPY #$44                        ; $27C8
        BEQ pose_stuck_legs             ; $27CA
        LDA $D4,X                       ; $27CC
        ORA $D7,X                       ; $27CE
        BNE pose_stuck_legs             ; $27D0
        JMP store_pose                  ; $27D2
pose_stuck_legs:
        LDY #$08                        ; $27D5
        JMP store_pose                  ; $27D7
pose_landed_on:
        CMP #$1B                        ; $27DA
        BNE pose_knockdown              ; $27DC
        LDA timer,X                     ; $27DE
        CPY #$00                        ; $27E0
        BEQ pose_landed_left            ; $27E2
        CMP #$04                        ; $27E4
        BCC pose_landed_late_right      ; $27E6
        LDY #$38                        ; $27E8
        JMP store_pose                  ; $27EA
pose_landed_late_right:
        LDY #$3A                        ; $27ED
        JMP store_pose                  ; $27EF
pose_landed_left:
        CMP #$04                        ; $27F2
        BCC pose_landed_late_left       ; $27F4
        LDY #$3C                        ; $27F6
        JMP store_pose                  ; $27F8
pose_landed_late_left:
        LDY #$3E                        ; $27FB
        JMP store_pose                  ; $27FD
pose_knockdown:
        CMP #$13                        ; $2800
        BNE pose_yamo_rise              ; $2802
        LDA timer,X                     ; $2804
        CMP #$0A                        ; $2806
        BCC pose_knockdown_late         ; $2808
        CPY #$00                        ; $280A
        BNE pose_knockdown_right        ; $280C
        LDY #$3C                        ; $280E
        JMP store_pose                  ; $2810
pose_knockdown_right:
        LDY #$38                        ; $2813
        JMP store_pose                  ; $2815
pose_knockdown_late:
        CPY #$00                        ; $2818
        BNE pose_knockdown_late_right   ; $281A
        LDY #$3E                        ; $281C
        JMP store_pose                  ; $281E
pose_knockdown_late_right:
        LDY #$3A                        ; $2821
        JMP store_pose                  ; $2823
pose_yamo_rise:
; State $10. Yamo's first picture, library $2A, both facings.
        CMP #$10                        ; $2826
        BNE pose_punch                  ; $2828
        LDY #$2A                        ; $282A
        JMP store_pose                  ; $282C
pose_punch:
        CMP #$11                        ; $282F
        BNE pose_rising                 ; $2831
        CPY #$01                        ; $2833
        BNE pose_punch_left             ; $2835
        LDY #$06                        ; $2837
        JMP store_pose                  ; $2839
pose_punch_left:
        LDY #$04                        ; $283C
        JMP store_pose                  ; $283E
pose_rising:
; State $12. Facing right is library $2E, facing left is $2C.
        CMP #$12                        ; $2841
        BNE pose_strike                 ; $2843
        CPY #$01                        ; $2845
        BNE pose_rising_left            ; $2847
        LDY #$2E                        ; $2849
        JMP store_pose                  ; $284B
pose_rising_left:
        LDY #$2C                        ; $284E
        JMP store_pose                  ; $2850
pose_strike:
; State $16, the ninja's strike. Timer >= $0B is library $34 facing right and
; $30 facing left. Below $0B that is $36 and $32.
        CMP #$16                        ; $2853
        BNE pose_flinch                 ; $2855
        LDA timer,X                     ; $2857
        CMP #$0B                        ; $2859
        BCC pose_strike_late            ; $285B
        CPY #$01                        ; $285D
        BNE pose_strike_left            ; $285F
        LDY #$34                        ; $2861
        JMP store_pose                  ; $2863
pose_strike_left:
        LDY #$30                        ; $2866
        JMP store_pose                  ; $2868
pose_strike_late:
        CPY #$01                        ; $286B
        BNE pose_strike_late_left       ; $286D
        LDY #$36                        ; $286F
        JMP store_pose                  ; $2871
pose_strike_late_left:
        LDY #$32                        ; $2874
        JMP store_pose                  ; $2876
pose_flinch:
        CMP #$0F                        ; $2879
        BNE pose_kick_left              ; $287B
        CPY #$01                        ; $287D
        BNE pose_flinch_left            ; $287F
        LDY #$02                        ; $2881
        JMP store_pose                  ; $2883
pose_flinch_left:
        LDY #$00                        ; $2886
        JMP store_pose                  ; $2888

; Picture for flying kick left. Timer 10 or more is library $16 (tucked). The rest is
; library $18 (leg out).
pose_kick_left:
        CMP #$0C                        ; $288B
        BNE pose_kick_right             ; $288D
        LDA timer,X                     ; $288F
        CMP #$0A                        ; $2891
        BCC pose_kick_left_out          ; $2893
        LDY #$16                        ; $2895
        JMP store_pose                  ; $2897
pose_kick_left_out:
        LDY #$18                        ; $289A
        JMP store_pose                  ; $289C

; Picture for flying kick right. Libraries $1A and $1C.
pose_kick_right:
        CMP #$0D                        ; $289F
        BNE pose_chase                  ; $28A1
        LDA timer,X                     ; $28A3
        CMP #$0A                        ; $28A5
        BCC pose_kick_right_out         ; $28A7
        LDY #$1A                        ; $28A9
        JMP store_pose                  ; $28AB
pose_kick_right_out:
        LDY #$1C                        ; $28AE
        JMP store_pose                  ; $28B0
pose_chase:
        CMP #$14                        ; $28B3
        BNE pose_sidestep               ; $28B5
        CPY #$01                        ; $28B7
        BEQ pose_walk_right_test        ; $28B9
        BNE pose_walk_left_test         ; $28BB
pose_sidestep:
        CMP #$15                        ; $28BD
        BNE pose_walk_left              ; $28BF
        CPY #$01                        ; $28C1
        BEQ pose_walk_right_test        ; $28C3
        BNE pose_walk_left_test         ; $28C5
pose_walk_left:
        CMP #$03                        ; $28C7
        BNE pose_walk_right             ; $28C9
pose_walk_left_test:
        LDA hit,X                       ; $28CB
        AND #$04                        ; $28CD
        BEQ pose_walk_left_cycle        ; $28CF
        JMP flip_climb                  ; $28D1
pose_walk_left_cycle:
        LDY $4F48,X                     ; $28D4
        CPY #$0E                        ; $28D7
        BEQ pose_walk_left_second       ; $28D9
        LDY #$0E                        ; $28DB
        JMP store_pose                  ; $28DD
pose_walk_left_second:
        LDY #$10                        ; $28E0
        JMP store_pose                  ; $28E2
pose_walk_right:
        CMP #$04                        ; $28E5
        BNE pose_jump                   ; $28E7
pose_walk_right_test:
        LDA hit,X                       ; $28E9
        AND #$04                        ; $28EB
        BEQ pose_walk_right_cycle       ; $28ED
        JMP flip_climb                  ; $28EF
pose_walk_right_cycle:
        LDY $4F48,X                     ; $28F2
        CPY #$12                        ; $28F5
        BEQ pose_walk_right_second      ; $28F7
        LDY #$12                        ; $28F9
        JMP store_pose                  ; $28FB
pose_walk_right_second:
        LDY #$14                        ; $28FE
        JMP store_pose                  ; $2900

; Picture for the standing jump, state 5. Timer 15 is library 8 (legs together). 12 through
; 14 are library $1E. 2 through 11 are library $20. Timer 1 is library $1E again, and 0 is
; library 8.
pose_jump:
        CMP #$05                        ; $2903
        BNE pose_side_left              ; $2905
        LDY timer,X                     ; $2907
        CPY #$0F                        ; $2909
        BCC pose_jump_tuck              ; $290B
        LDY #$08                        ; $290D
        JMP store_pose                  ; $290F
pose_jump_tuck:
        CPY #$0C                        ; $2912
        BCC pose_jump_mid               ; $2914
        LDY #$1E                        ; $2916
        JMP store_pose                  ; $2918
pose_jump_mid:
        CPY #$02                        ; $291B
        BCC pose_jump_end               ; $291D
        LDY #$20                        ; $291F
        JMP store_pose                  ; $2921
pose_jump_end:
        CPY #$01                        ; $2924
        BCC pose_jump_legs              ; $2926
        LDY #$1E                        ; $2928
        JMP store_pose                  ; $292A
pose_jump_legs:
        LDY #$08                        ; $292D
        JMP store_pose                  ; $292F

; Picture for sideways jump left, state 6. Timer 12 or more, and timers 0, 1 and 2, are
; library $22. The counts between are library $24.
pose_side_left:
        CMP #$06                        ; $2932
        BNE pose_side_right             ; $2934
        LDY timer,X                     ; $2936
        CPY #$0C                        ; $2938
        BCC pose_side_left_mid          ; $293A
pose_side_left_tuck:
        LDY #$22                        ; $293C
        JMP store_pose                  ; $293E
pose_side_left_mid:
        CPY #$03                        ; $2941
        BCC pose_side_left_tuck         ; $2943
        LDY #$24                        ; $2945
        JMP store_pose                  ; $2947

; Picture for sideways jump right, state 7. Libraries $26 and $28.
pose_side_right:
        CMP #$07                        ; $294A
        BNE pose_carry                  ; $294C
        LDY timer,X                     ; $294E
        CPY #$0C                        ; $2950
        BCC pose_side_right_mid         ; $2952
pose_side_right_tuck:
        LDY #$26                        ; $2954
        JMP store_pose                  ; $2956
pose_side_right_mid:
        CPY #$03                        ; $2959
        BCC pose_side_right_tuck        ; $295B
        LDY #$28                        ; $295D
        JMP store_pose                  ; $295F
; State $17. $4F54 is the library stored last time. $AA still set means
; this frame did not take its own step, and that library is kept. $AA
; clear falls into flip_climb. The surface shove does not change $AA.
pose_carry:
        CMP #$17                        ; $2962
        BNE pose_stand                  ; $2964
        LDY $4F54,X                     ; $2966
        LDA $AA,X                       ; $2969
        BEQ flip_climb                  ; $296B
        JMP store_pose                  ; $296D
; State 0. On a ladder, $0A or $0C stays up. Any other picture on a
; ladder, and every state not named above, falls into flip_climb. Off
; the ladder, facing left is library 0 and facing right is library 2.
pose_stand:
        CMP #$00                        ; $2970
        BNE flip_climb                  ; $2972
        LDA hit,X                       ; $2974
        AND #$04                        ; $2976
        BEQ pose_stand_floor            ; $2978
        LDY $4F54,X                     ; $297A
        CPY #$0A                        ; $297D
        BEQ pose_keep_climb             ; $297F
        CPY #$0C                        ; $2981
        BEQ pose_keep_climb             ; $2983
; Libraries $0A and $0C, the two climb pictures. $0A is showing, so the
; next one is $0C. Anything else becomes $0A. State $17 reaches this only
; on the frame his own step shifted $AA to 0. A walk that overlaps a
; ladder jumps here too. State 0 on a ladder keeps $0A or $0C, and only
; arrives here when the picture is neither. A state choose_pose does not
; name falls through to here as well, and the climbs are that case.
flip_climb:
        LDY $4F54,X                     ; $2985
        CPY #$0A                        ; $2988
        BEQ flip_climb_second           ; $298A
        LDY #$0A                        ; $298C
pose_keep_climb:
        JMP store_pose                  ; $298E
flip_climb_second:
        LDY #$0C                        ; $2991
        JMP store_pose                  ; $2993
pose_stand_floor:
        CPY #$01                        ; $2996
        BEQ pose_stand_right            ; $2998
        LDY #$00                        ; $299A
        JMP store_pose                  ; $299C
pose_stand_right:
        LDY #$02                        ; $299F

; Y is the relative library. It is kept at $4F48, and the next one at $4F4B.
; Three rolls of active,X pick the base in $59A5. Room 0 holds 00 8C 46 04,
; and $01, $41, and $81 select the first three. The sum is the absolute
; library blit_sprites reads from $4F4E. The following absolute library is
; $4F51. Carry into the rolls does not change those three results.
store_pose:
        TYA                             ; $29A1
        STA $4F48,X                     ; $29A2
        CLC                             ; $29A5
        ADC #$01                        ; $29A6
        STA $4F4B,X                     ; $29A8
        LDA active,X                    ; $29AB
        ROL A                           ; $29AD
        ROL A                           ; $29AE
        ROL A                           ; $29AF
        AND #$03                        ; $29B0
        TAY                             ; $29B2
        LDA $59A5,Y                     ; $29B3
        CLC                             ; $29B6
        ADC $4F48,X                     ; $29B7
        STA $4F4E,X                     ; $29BA
        ADC #$01                        ; $29BD
        STA $4F51,X                     ; $29BF
        RTS                             ; $29C2
; Clear $B3 and $BC, then read the VIC sprite-sprite register $D01E. A hit is kept in $67.
read_sprite_hits:
        LDA #$00                        ; $29C3
        LDX #$02                        ; $29C5
sprite_hits_clear:
        STA $B3,X                       ; $29C7
        STA $BC,X                       ; $29C9
        DEX                             ; $29CB
        BPL sprite_hits_clear           ; $29CC
        LDA $D01E                       ; $29CE  sprite-sprite contacts. Reading clears it
        BNE sprite_hits_bruce           ; $29D1
        RTS                             ; $29D3
sprite_hits_bruce:
        STA $67                         ; $29D4
        AND #$03                        ; $29D6
        BNE sprite_hits_bruce_yamo      ; $29D8
        JMP sprite_hits_yamo_ninja      ; $29DA
sprite_hits_bruce_yamo:
        LDA $67                         ; $29DD
        AND #$0C                        ; $29DF
; The trainer's second question writes $09 over this branch offset. The
; branch then lands on LDA $B4, so the ORA #$08 into $B3 is skipped and the
; Yamo's own hit bit is still stored. $B3 is Bruce's sprite-hit bits.
; $29F7 is the ninja's pair, and $09 there lands on LDA $B5. The swing itself
; was chosen earlier. This only drops Bruce's recorded contact, so he never
; flinches, and a blow he lands on either fighter is still recorded.
        BNE sprite_hits_mark_yamo       ; $29E1
        JMP sprite_hits_bruce_ninja     ; $29E3
sprite_hits_mark_yamo:
        LDA $B3                         ; $29E6
        ORA #$08                        ; $29E8
        STA $B3                         ; $29EA
        LDA $B4                         ; $29EC
        ORA #$02                        ; $29EE
        STA $B4                         ; $29F0
sprite_hits_bruce_ninja:
        LDA $67                         ; $29F2
        AND #$30                        ; $29F4
; Same patch. Offset $09 lands on LDA $B5, so the ninja's hit bit is still stored.
        BNE sprite_hits_mark_ninja      ; $29F6
        JMP sprite_hits_yamo_ninja      ; $29F8
sprite_hits_mark_ninja:
        LDA $B3                         ; $29FB
        ORA #$10                        ; $29FD
        STA $B3                         ; $29FF
        LDA $B5                         ; $2A01
        ORA #$02                        ; $2A03
        STA $B5                         ; $2A05
sprite_hits_yamo_ninja:
        LDA $67                         ; $2A07
        AND #$0C                        ; $2A09
        BEQ sprite_hits_victims         ; $2A0B
        LDA $67                         ; $2A0D
        AND #$30                        ; $2A0F
        BEQ sprite_hits_victims         ; $2A11
        LDA $B4                         ; $2A13
        ORA #$10                        ; $2A15
        STA $B4                         ; $2A17
        LDA $B5                         ; $2A19
        ORA #$08                        ; $2A1B
        STA $B5                         ; $2A1D
sprite_hits_victims:
        LDX #$02                        ; $2A1F
sprite_hits_victim_loop:
        LDA $B3,X                       ; $2A21
        STA $4C                         ; $2A23
        LDY #$00                        ; $2A25
sprite_hits_bit_loop:
        LSR $4C                         ; $2A27
        BCS sprite_hits_contact         ; $2A29
sprite_hits_next_bit:
        INY                             ; $2A2B
        CPY #$05                        ; $2A2C
        BCC sprite_hits_bit_loop        ; $2A2E
        DEX                             ; $2A30
        BPL sprite_hits_victim_loop     ; $2A31
        JMP resolve_blows               ; $2A33
sprite_hits_contact:
        STY $52                         ; $2A36
        LDA state,X                     ; $2A38
        CMP #$18                        ; $2A3A
        BEQ sprite_hits_next_bit        ; $2A3C
        CMP #$1A                        ; $2A3E
        BEQ sprite_hits_next_bit        ; $2A40
        CMP #$0F                        ; $2A42
        BEQ sprite_hits_next_bit        ; $2A44
        CMP #$13                        ; $2A46
        BEQ sprite_hits_next_bit        ; $2A48
        CMP #$19                        ; $2A4A
        BEQ sprite_hits_next_bit        ; $2A4C
        CMP #$1B                        ; $2A4E
        BEQ sprite_hits_next_bit        ; $2A50
        LDA $4F40,Y                     ; $2A52
        BMI sprite_hits_no_blow         ; $2A55
        TAY                             ; $2A57
        LDA $00BF,Y                     ; $2A58
        CMP #$1B                        ; $2A5B
        BEQ sprite_hits_no_blow         ; $2A5D
        CMP #$16                        ; $2A5F
        BEQ blow_strike                 ; $2A61
        CMP #$11                        ; $2A63
        BEQ blow_punch                  ; $2A65
        CMP #$0D                        ; $2A67
        BEQ blow_kick                   ; $2A69
        CMP #$0C                        ; $2A6B
        BEQ blow_kick                   ; $2A6D
        CMP #$0E                        ; $2A6F
        BNE sprite_hits_no_blow         ; $2A71
        JMP blow_landing                ; $2A73
sprite_hits_no_blow:
        LDY $52                         ; $2A76
        JMP sprite_hits_next_bit        ; $2A78
blow_strike:
        LDA $00CE,Y                     ; $2A7B
        CMP #$08                        ; $2A7E
        BCS sprite_hits_no_blow         ; $2A80
        LDA #$04                        ; $2A82
        STA $61                         ; $2A84
        JSR reach_test                  ; $2A86
        BCC sprite_hits_no_blow         ; $2A89
        BMI sprite_hits_no_blow         ; $2A8B
        TXA                             ; $2A8D
        PHA                             ; $2A8E
        TYA                             ; $2A8F
        PHA                             ; $2A90
; Effect $87, the strike connect. Blow 2. A punch, a kick, and a
; landing go to hit_sound instead.
        LDY #$87                        ; $2A91
        JSR play_sound                  ; $2A93
        PLA                             ; $2A96
        TAY                             ; $2A97
        PLA                             ; $2A98
        TAX                             ; $2A99
        JSR mark_swing                  ; $2A9A
        LDA $BC,X                       ; $2A9D
        ORA #$02                        ; $2A9F
        STA $BC,X                       ; $2AA1
        BNE sprite_hits_no_blow         ; $2AA3
blow_punch:
        LDA #$06                        ; $2AA5
        STA $61                         ; $2AA7
        JSR reach_test                  ; $2AA9
        BCC sprite_hits_no_blow         ; $2AAC
        BMI sprite_hits_no_blow         ; $2AAE
        LDA $00A1,Y                     ; $2AB0
        SEC                             ; $2AB3
        SBC ypos,X                      ; $2AB4
        BPL blow_punch_height           ; $2AB6
        EOR #$FF                        ; $2AB8
        ADC #$01                        ; $2ABA
blow_punch_height:
        CMP #$16                        ; $2ABC
        BCS sprite_hits_no_blow         ; $2ABE
        JSR hit_sound                   ; $2AC0
        JSR mark_swing                  ; $2AC3
        LDA $BC,X                       ; $2AC6
        ORA #$04                        ; $2AC8
        CPY #$00                        ; $2ACA
        BNE blow_punch_store            ; $2ACC
        ORA #$80                        ; $2ACE
blow_punch_store:
        STA $BC,X                       ; $2AD0
        BNE sprite_hits_no_blow         ; $2AD2
blow_kick:
        LDA $00CE,Y                     ; $2AD4
        CMP #$0A                        ; $2AD7
        BCS blow_done                   ; $2AD9
        LDA #$06                        ; $2ADB
        STA $61                         ; $2ADD
        JSR reach_test                  ; $2ADF
        BCC blow_done                   ; $2AE2
        BMI blow_done                   ; $2AE4
        JSR hit_sound                   ; $2AE6
        JSR mark_swing                  ; $2AE9
        LDA $BC,X                       ; $2AEC
        ORA #$08                        ; $2AEE
        CPY #$00                        ; $2AF0
        BNE blow_kick_store             ; $2AF2
        ORA #$80                        ; $2AF4
blow_kick_store:
        STA $BC,X                       ; $2AF6
        BNE blow_done                   ; $2AF8
blow_landing:
        LDA ypos,X                      ; $2AFA
        SEC                             ; $2AFC
        SBC $00A1,Y                     ; $2AFD
        CMP #$0A                        ; $2B00
        BMI blow_done                   ; $2B02
        BCC blow_done                   ; $2B04
        LDA $4F45,Y                     ; $2B06
        BEQ blow_done                   ; $2B09
        SEC                             ; $2B0B
        SBC #$01                        ; $2B0C
        STA $4F45,Y                     ; $2B0E
        LDA $BC,X                       ; $2B11
        AND #$10                        ; $2B13
        BNE blow_done                   ; $2B15
        LDA $00BC,Y                     ; $2B17
        AND #$10                        ; $2B1A
        BNE blow_done                   ; $2B1C
        LDA state,X                     ; $2B1E
        CMP #$0C                        ; $2B20
        BEQ blow_done                   ; $2B22
        CMP #$0D                        ; $2B24
        BEQ blow_done                   ; $2B26
        CMP #$11                        ; $2B28
        BEQ blow_done                   ; $2B2A
        JSR hit_sound                   ; $2B2C
        LDA $BC,X                       ; $2B2F
        ORA #$10                        ; $2B31
        CPY #$00                        ; $2B33
        BNE blow_landing_store          ; $2B35
        ORA #$80                        ; $2B37
blow_landing_store:
        STA $BC,X                       ; $2B39
blow_done:
        JMP sprite_hits_no_blow         ; $2B3B
; Y is the attacker that connected, X the victim. Bit 0 of the attacker's
; $BC marks the blow for resolve_blows, and the victim turns to face him
; (the attacker's facing, flipped). A landing does not come here, so a
; stomp does not turn the victim round.
mark_swing:
        LDA $00BC,Y                     ; $2B3E
        ORA #$01                        ; $2B41
        STA $00BC,Y                     ; $2B43
        LDA $00A4,Y                     ; $2B46
        EOR #$01                        ; $2B49
        STA facing,X                    ; $2B4B
        RTS                             ; $2B4D
; One pass over the three actors, high X first. Bit 0 of $BC was set on
; the attacker by $2B3E. He leaves the attack for state 0. Bruce keeps
; timer $18. Another fighter keeps $18 on a short visit with $40 clear,
; stores $0A on a middle visit, and stores 2 on a long visit or when $40
; is set. The four blow tests then run in order, and a set bit is not
; cleared, so a later test still sees it.
resolve_blows:
        LDX #$02                        ; $2B4E
; X is the victim, saved in $51. The loop counts it down to 0.
resolve_actor:
        STX $51                         ; $2B50
        LDA $BC,X                       ; $2B52
        AND #$01                        ; $2B54
        BEQ strike_blow                 ; $2B56
        LDA #$00                        ; $2B58
        STA state,X                     ; $2B5A
        LDA #$04                        ; $2B5C
        STA $0106,X                     ; $2B5E
        LDA #$18                        ; $2B61
        STA timer,X                     ; $2B63
        INC $4FDB,X                     ; $2B65
        TXA                             ; $2B68
        BEQ resolve_bruce_timer         ; $2B69
        JSR test_visit                  ; $2B6B
        BVS resolve_enemy_long          ; $2B6E
        BCS resolve_enemy_middle        ; $2B70
        LDA $40                         ; $2B72
        BNE resolve_enemy_long          ; $2B74
        JMP strike_blow                 ; $2B76
resolve_enemy_middle:
        LDA #$0A                        ; $2B79
        STA timer,X                     ; $2B7B
        BNE strike_blow                 ; $2B7D
resolve_enemy_long:
        LDA #$02                        ; $2B7F
        STA timer,X                     ; $2B81
resolve_bruce_timer:
        JSR test_visit                  ; $2B83
        BVS resolve_bruce_long          ; $2B86
        BCS resolve_bruce_middle        ; $2B88
        LDA #$03                        ; $2B8A
        STA timer,X                     ; $2B8C
        BNE strike_blow                 ; $2B8E
resolve_bruce_middle:
        LDA #$08                        ; $2B90
        STA timer,X                     ; $2B92
        BNE strike_blow                 ; $2B94
resolve_bruce_long:
        LDA #$0A                        ; $2B96
        STA timer,X                     ; $2B98
; Bit 1. Two health, state $0F, timer 3. No points. A negative byte
; shares kick_result, whose first test is the knockdown.
strike_blow:
        LDA $BC,X                       ; $2B9A
        AND #$02                        ; $2B9C
        BEQ punch_blow                  ; $2B9E
        LDA $D1,X                       ; $2BA0
        SEC                             ; $2BA2
        SBC #$02                        ; $2BA3
        STA $D1,X                       ; $2BA5
        BMI kick_result                 ; $2BA7
        LDA #$0F                        ; $2BA9
        STA state,X                     ; $2BAB
        LDA #$03                        ; $2BAD
        STA timer,X                     ; $2BAF
; Bit 2. $64 into the low score byte, 100, then 3 health. Bit 7 clear
; skips the points and still subtracts. Below zero is force_knockdown.
; A blow that stays positive is state $0F, timer 4.
punch_blow:
        LDA $BC,X                       ; $2BB1
        AND #$04                        ; $2BB3
        BEQ kick_blow                   ; $2BB5
        LDA $BC,X                       ; $2BB7
        BPL punch_damage                ; $2BB9
        LDA #$64                        ; $2BBB
        LDX #$02                        ; $2BBD
        JSR add_score                   ; $2BBF
        LDX $51                         ; $2BC2
punch_damage:
        LDA $D1,X                       ; $2BC4
        SEC                             ; $2BC6
        SBC #$03                        ; $2BC7
        STA $D1,X                       ; $2BC9
        BMI force_knockdown             ; $2BCB
        LDA #$0F                        ; $2BCD
        STA state,X                     ; $2BCF
        LDA #$04                        ; $2BD1
        STA timer,X                     ; $2BD3
; Bit 3. $4B into the low score byte, 75, then 7 health. The same bit 7
; gate as the punch. Below zero is force_knockdown. A kick that stays
; positive still stores the knockdown pose, state $13, timer $0C.
kick_blow:
        LDA $BC,X                       ; $2BD5
        AND #$08                        ; $2BD7
        BEQ landing_blow                ; $2BD9
        LDA $BC,X                       ; $2BDB
        BPL kick_damage                 ; $2BDD
        LDA #$4B                        ; $2BDF
        LDX #$02                        ; $2BE1
        JSR add_score                   ; $2BE3
        LDX $51                         ; $2BE6
kick_damage:
        LDA $D1,X                       ; $2BE8
        SEC                             ; $2BEA
        SBC #$07                        ; $2BEB
        STA $D1,X                       ; $2BED
; The kick's health, or the strike's when it went negative. Minus is the
; knockdown. Otherwise the kick pose, state $13, timer $0C. A strike that
; reaches here only through BMI never takes that store.
kick_result:
        BMI force_knockdown             ; $2BEF
        LDA #$13                        ; $2BF1
        STA state,X                     ; $2BF3
        LDA #$0C                        ; $2BF5
        STA timer,X                     ; $2BF7
; Bit 4. $32 into the low score byte, 50, then 5 health. Bit 7 clear
; skips the points. Below zero is force_knockdown, and that routine
; jumps back here with the bit still set. A landing that stays positive
; is state $1B, timer 8, and that store is also how the bug loop ends.
landing_blow:
        LDA $BC,X                       ; $2BF9
        AND #$10                        ; $2BFB
        BEQ resolve_next                ; $2BFD
        LDA $BC,X                       ; $2BFF
        BPL landing_damage              ; $2C01
        LDA #$32                        ; $2C03
        LDX #$02                        ; $2C05
        JSR add_score                   ; $2C07
        LDX $51                         ; $2C0A
; Bit 7 clear arrives here without the 50 points.
landing_damage:
        LDA $D1,X                       ; $2C0C
        SEC                             ; $2C0E
        SBC #$05                        ; $2C0F
        STA $D1,X                       ; $2C11
        BMI force_knockdown             ; $2C13
        LDA #$1B                        ; $2C15
        STA state,X                     ; $2C17
        LDA #$08                        ; $2C19
        STA timer,X                     ; $2C1B
resolve_next:
        DEX                             ; $2C1D
        BMI resolve_done                ; $2C1E
        JMP resolve_actor               ; $2C20
resolve_done:
        RTS                             ; $2C23
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
        LDA $BC,X                       ; $2C24
        AND #$80                        ; $2C26
        BEQ store_knockdown             ; $2C28
        STX $51                         ; $2C2A
        CPX #$01                        ; $2C2C
        BNE knockout_ninja              ; $2C2E
; Actor 1. $01 into byte 1, then $C2 into byte 2: 256 + 194 = 450.
knockout_yamo:
        LDA #$01                        ; $2C30
        TAX                             ; $2C32
        JSR add_score                   ; $2C33
        LDA #$C2                        ; $2C36
        LDX #$02                        ; $2C38
        JSR add_score                   ; $2C3A
        JMP store_knockdown             ; $2C3D
; Not actor 1. The ninja takes this path. $C8 in the low byte is 200.
knockout_ninja:
        LDA #$C8                        ; $2C40
        LDX #$02                        ; $2C42
        JSR add_score                   ; $2C44
; Every knockdown, paid or not. State $13, timer $0C.
store_knockdown:
        LDX $51                         ; $2C47
        LDA #$13                        ; $2C49
        STA state,X                     ; $2C4B
        LDA #$0C                        ; $2C4D
        STA timer,X                     ; $2C4F
; Bit 4 is still set, so a killing landing runs landing_blow again.
        JMP landing_blow                ; $2C51
; Y is the attacker, X the victim. A is the attacker's xpos minus the
; victim's, negated when the attacker faces right, so a positive A is in
; front of him. Carry set means A >= the reach in $61. Bit 7 means he is
; behind, or the gap is $80 or more. Callers treat carry clear or minus
; as a miss. The strike passes 4, the punch and the kick pass 6.
reach_test:
        LDA $009E,Y                     ; $2C54
        SEC                             ; $2C57
        SBC xpos,X                      ; $2C58
        PHA                             ; $2C5A
        PHP                             ; $2C5B
        LDA $00A4,Y                     ; $2C5C
        CMP #$01                        ; $2C5F
        BNE reach_compare               ; $2C61
        PLP                             ; $2C63
        PLA                             ; $2C64
        EOR #$FF                        ; $2C65
        ADC #$01                        ; $2C67
        PHA                             ; $2C69
        PHP                             ; $2C6A
reach_compare:
        PLP                             ; $2C6B
        PLA                             ; $2C6C
        CMP $61                         ; $2C6D
        RTS                             ; $2C6F

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
        LDA $60                         ; $2C70
        BMI scroll_pause                ; $2C72
        DEC $60                         ; $2C74
        BEQ scroll_copy                 ; $2C76
        RTS                             ; $2C78
scroll_pause:
        AND #$7F                        ; $2C79
        SEC                             ; $2C7B
        SBC #$01                        ; $2C7C
        BEQ scroll_pause_done           ; $2C7E
        ORA #$80                        ; $2C80
        STA $60                         ; $2C82
        RTS                             ; $2C84
scroll_pause_done:
        LDX $4321                       ; $2C85
        LDA $4CB2,X                     ; $2C88
        STA $60                         ; $2C8B
        DEC $66                         ; $2C8D
        BMI scroll_next_slot            ; $2C8F
        RTS                             ; $2C91
scroll_copy:
        LDA #$A0                        ; $2C92
        STA $7C                         ; $2C94
        LDA #$F1                        ; $2C96
        STA $7D                         ; $2C98
        LDA #$42                        ; $2C9A
        STA $7E                         ; $2C9C
        LDA $29                         ; $2C9E
        CMP #$0A                        ; $2CA0
        BCC scroll_next_delay           ; $2CA2
        LDA #$A8                        ; $2CA4
        STA $7C                         ; $2CA6
        LDA #$09                        ; $2CA8
        STA $7D                         ; $2CAA
        LDA #$43                        ; $2CAC
        STA $7E                         ; $2CAE
scroll_next_delay:
        LDX $4321                       ; $2CB0
        LDA $4CB2,X                     ; $2CB3
        STA $60                         ; $2CB6
        DEC $66                         ; $2CB8
        BPL scroll_move                 ; $2CBA
scroll_next_slot:
        DEC $4321                       ; $2CBC
        BPL scroll_load_delay           ; $2CBF
        LDX #$07                        ; $2CC1
        STX $4321                       ; $2CC3
        LDA $65                         ; $2CC6
        EOR #$01                        ; $2CC8
        STA $65                         ; $2CCA
scroll_load_delay:
        LDX $4321                       ; $2CCC
        LDA $4CB2,X                     ; $2CCF
        STA $60                         ; $2CD2
        LDA #$10                        ; $2CD4
        STA $66                         ; $2CD6
scroll_move:
        LDA $65                         ; $2CD8
        BNE scroll_move_down            ; $2CDA
        INC $64                         ; $2CDC
        LDA $64                         ; $2CDE
        CMP #$08                        ; $2CE0
        BCC scroll_glyphs               ; $2CE2
        BCS $2CED                       ; $2CE4  lands on LDA #$00 inside $2CEC
scroll_move_down:
        DEC $64                         ; $2CE6
        BPL scroll_glyphs               ; $2CE8
        LDA #$07                        ; $2CEA
        BIT $00A9                       ; $2CEC
        STA $64                         ; $2CEF
scroll_glyphs:
        LDX #$02                        ; $2CF1
scroll_glyph_loop:
        STX $51                         ; $2CF3
        TXA                             ; $2CF5
        ASL A                           ; $2CF6
        ASL A                           ; $2CF7
        ASL A                           ; $2CF8
        CLC                             ; $2CF9
        ADC $7D                         ; $2CFA
        STA $2D2C                       ; $2CFC  rewrites a byte of the instruction at $2D2B
        LDA $7E                         ; $2CFF
        ADC #$00                        ; $2D01
        STA $2D2D                       ; $2D03  rewrites a byte of the instruction at $2D2B
        TXA                             ; $2D06
        CLC                             ; $2D07
        ADC #$61                        ; $2D08
        STA $43BC                       ; $2D0A
        JSR scale_by_eight              ; $2D0D
        LDA $43BC                       ; $2D10
        STA $06                         ; $2D13
        SEC                             ; $2D15
        SBC #$04                        ; $2D16
        STA $08                         ; $2D18
        LDA $43BB                       ; $2D1A
        CLC                             ; $2D1D
        ADC $7C                         ; $2D1E
        STA $07                         ; $2D20
        CLC                             ; $2D22
        ADC #$04                        ; $2D23
        STA $09                         ; $2D25
        LDY #$00                        ; $2D27
        LDX $64                         ; $2D29
scroll_byte_loop:
        LDA $E000,X                     ; $2D2B
        CPY #$04                        ; $2D2E
        BCS scroll_shadow_byte          ; $2D30
        STA ($06),Y                     ; $2D32
        JSR step_ptr_06                 ; $2D34
        STA ($06),Y                     ; $2D37
        JMP scroll_next_byte            ; $2D39
scroll_shadow_byte:
        STA ($08),Y                     ; $2D3C
        JSR step_ptr_08                 ; $2D3E
        STA ($08),Y                     ; $2D41
scroll_next_byte:
        INY                             ; $2D43
        INX                             ; $2D44
        CPX #$08                        ; $2D45
        BNE scroll_byte_test            ; $2D47
        LDX #$00                        ; $2D49
scroll_byte_test:
        CPY #$08                        ; $2D4B
        BNE scroll_byte_loop            ; $2D4D
        LDX $51                         ; $2D4F
        DEX                             ; $2D51
        BPL scroll_glyph_loop           ; $2D52
        RTS                             ; $2D54

; If Bruce (X = 0) has $D1 negative, he has lost a life. The other actors
; call retire_actor. State $13 and state $19 are skipped while the timer
; is still running, so the knockdown from force_knockdown is drawn through.
check_bruce_down:
        LDX #$02                        ; $2D55
check_down_loop:
        LDA active,X                    ; $2D57
        AND #$01                        ; $2D59
        BEQ check_down_next             ; $2D5B
        LDA state,X                     ; $2D5D
        CMP #$13                        ; $2D5F
        BEQ check_down_timer            ; $2D61
        CMP #$19                        ; $2D63
        BNE check_down_health           ; $2D65
check_down_timer:
        LDA timer,X                     ; $2D67
        BNE check_down_next             ; $2D69
check_down_health:
        LDA $D1,X                       ; $2D6B
        BPL check_down_next             ; $2D6D
        TXA                             ; $2D6F
        BEQ check_down_bruce            ; $2D70
        JSR retire_actor                ; $2D72
check_down_next:
        DEX                             ; $2D75
        BPL check_down_loop             ; $2D76
        RTS                             ; $2D78
check_down_bruce:
        JMP lose_life                   ; $2D79
; The other fighters. State 0, timer already 0, and hit bit 0 or bit 2 set:
; $C2 still $0C or $0D is a kick that just ended, and stand_down's 6 is
; replaced with $18. A long visit or a set $40 then stores 1. A middle
; visit stores 3. Any other remembered state starts state $14 with timer
; $14. A timer still counting, or a fighter in the air, is left for
; actor_tick. $42CA set skips the $81 test, so Yamo is not started here.
; He stays on the stick in $99, and actor_tick runs him on it. Actor 2,
; the ninja, is still accepted when active is $41.
enemy_turn:
        LDX #$02                        ; $2D7C
enemy_turn_loop:
        LDA $D1,X                       ; $2D7E
        BMI enemy_turn_next             ; $2D80
        LDA $42CA                       ; $2D82
        BNE enemy_turn_ninja            ; $2D85
        LDA active,X                    ; $2D87
        AND #$81                        ; $2D89
        CMP #$81                        ; $2D8B
        BEQ enemy_turn_idle             ; $2D8D
enemy_turn_ninja:
        LDA active,X                    ; $2D8F
        AND #$41                        ; $2D91
        CMP #$41                        ; $2D93
        BNE enemy_turn_next             ; $2D95
enemy_turn_idle:
        LDA state,X                     ; $2D97
        CMP #$00                        ; $2D99
        BNE enemy_turn_next             ; $2D9B
        LDA timer,X                     ; $2D9D
        BNE enemy_turn_next             ; $2D9F
        LDA hit,X                       ; $2DA1
        AND #$05                        ; $2DA3
        BEQ enemy_turn_next             ; $2DA5
        LDA $C2,X                       ; $2DA7
        CMP #$0D                        ; $2DA9
        BEQ enemy_turn_after_kick       ; $2DAB
        CMP #$0C                        ; $2DAD
        BEQ enemy_turn_after_kick       ; $2DAF
        LDA #$14                        ; $2DB1
        STA state,X                     ; $2DB3
        STA timer,X                     ; $2DB5
        LDA #$00                        ; $2DB7
        STA $0106,X                     ; $2DB9
enemy_turn_next:
        DEX                             ; $2DBC
        BPL enemy_turn_loop             ; $2DBD
        RTS                             ; $2DBF
enemy_turn_after_kick:
        JSR stand_down                  ; $2DC0
        LDA #$18                        ; $2DC3
        STA timer,X                     ; $2DC5
        JSR test_visit                  ; $2DC7
        BVS enemy_turn_long             ; $2DCA
        BCS enemy_turn_middle           ; $2DCC
        LDA $40                         ; $2DCE
        BNE enemy_turn_long             ; $2DD0
        RTS                             ; $2DD2
enemy_turn_middle:
        LDA #$03                        ; $2DD3
        STA timer,X                     ; $2DD5
        RTS                             ; $2DD7
enemy_turn_long:
        LDA #$01                        ; $2DD8
        STA timer,X                     ; $2DDA
        RTS                             ; $2DDC
; $62 is this fighter's ypos minus Bruce's, $63 the same for xpos. The
; magnitude is capped at $30. Bit 7 is set when this fighter's coordinate
; is the smaller one: he is above Bruce, or Bruce is to his right.
; face_from_dx writes facing 1 when bit 7 of $63 is set.
range_to_bruce:
        LDA ypos,X                      ; $2DDD
        SEC                             ; $2DDF
        SBC ypos                        ; $2DE0
        PHP                             ; $2DE2
        BCS range_dy_cap                ; $2DE3
        EOR #$FF                        ; $2DE5
        ADC #$01                        ; $2DE7
range_dy_cap:
        CMP #$31                        ; $2DE9
        BCC range_dy_sign               ; $2DEB
        LDA #$30                        ; $2DED
range_dy_sign:
        PLP                             ; $2DEF
        BCS range_store_dy              ; $2DF0
        ORA #$80                        ; $2DF2
range_store_dy:
        STA $62                         ; $2DF4
        LDA xpos,X                      ; $2DF6
        SEC                             ; $2DF8
        SBC xpos                        ; $2DF9
        PHP                             ; $2DFB
        BCS range_dx_cap                ; $2DFC
        EOR #$FF                        ; $2DFE
        ADC #$01                        ; $2E00
range_dx_cap:
        CMP #$31                        ; $2E02
        BCC range_dx_sign               ; $2E04
        LDA #$30                        ; $2E06
range_dx_sign:
        PLP                             ; $2E08
        BCS range_store_dx              ; $2E09
        ORA #$80                        ; $2E0B
range_store_dx:
        STA $63                         ; $2E0D
        RTS                             ; $2E0F
; Drop state $17 before the tile window is read. The timer and the pose
; hold go with it. $AA and $AD are left as they were, so a step that was
; still waiting keeps waiting if the next cell catches him again.
clear_carry:
        LDA #$00                        ; $2E10
        STA state,X                     ; $2E12
        LDA #$00                        ; $2E14
        STA timer,X                     ; $2E16
        STA $0106,X                     ; $2E18
        RTS                             ; $2E1B
; Face Bruce. Bit 7 of $63 means Bruce is to the right: facing 1. Otherwise
; facing 0. spawn_ninja and bruce_above call this.
face_from_dx:
        LDA $63                         ; $2E1C
        BPL face_left                   ; $2E1E
        LDA #$01                        ; $2E20
        BNE face_store                  ; $2E22
face_left:
        LDA #$00                        ; $2E24
face_store:
        STA facing,X                    ; $2E26
        RTS                             ; $2E28
; Effect $86. Punch connect, kick connect, and a landing. Room 18
; also jumps here when a spark is armed. Blow 2 does not.
hit_sound:
        PHA                             ; $2E29
        TXA                             ; $2E2A
        PHA                             ; $2E2B
        TYA                             ; $2E2C
        PHA                             ; $2E2D
        LDY #$86                        ; $2E2E
        JSR play_sound                  ; $2E30
        PLA                             ; $2E33
        TAY                             ; $2E34
        PLA                             ; $2E35
        TAX                             ; $2E36
        PLA                             ; $2E37
        RTS                             ; $2E38
; For each active actor except state $19, look at his tile row and the row
; below. cell_of_actor has his column in $E6,X and his tile row in $E9,X.
; Each of those rows checks that column and the two to the right. Hit bit 1
; is kept in $53 and gates the prize tiles, the lamps among them. State $17
; is cleared first, through clear_carry, and catch_surface puts it back
; only when tile $62 is in this window and hit bit 2 is set. $AD is left
; alone. The same window still tests the doors and the other tiles after
; the catch, so a hot tile can shock him on the frame he was caught.
scan_specials:
        LDA #$00                        ; $2E39
        STA $0100                       ; $2E3B
        LDX #$02                        ; $2E3E
scan_specials_loop:
        STX $51                         ; $2E40
        LDA active,X                    ; $2E42
        AND #$01                        ; $2E44
        BEQ scan_specials_next          ; $2E46
        LDA state,X                     ; $2E48
        CMP #$19                        ; $2E4A
        BEQ scan_specials_next          ; $2E4C
        CMP #$17                        ; $2E4E
        BNE scan_specials_rows          ; $2E50
        JSR clear_carry                 ; $2E52
scan_specials_rows:
        LDA hit,X                       ; $2E55
        AND #$02                        ; $2E57
        STA $53                         ; $2E59
        JSR cell_of_actor               ; $2E5B
        JSR scan_special_row            ; $2E5E
        LDX $51                         ; $2E61
        INC $E9,X                       ; $2E63
        JSR scan_special_row            ; $2E65
scan_specials_next:
        LDX $51                         ; $2E68
        DEX                             ; $2E6A
        BPL scan_specials_loop          ; $2E6B
        RTS                             ; $2E6D
; $4C counts 2, 1, 0, so three columns from $E6,X. Bit 7 of the tile is
; ignored. A shadow row therefore matches the same number as the row above.
scan_special_row:
        LDA $E9,X                       ; $2E6E
        TAX                             ; $2E70
        JSR point_at_row                ; $2E71
        LDX $51                         ; $2E74
        LDY $E6,X                       ; $2E76
        LDA #$02                        ; $2E78
        STA $4C                         ; $2E7A
scan_special_cell:
        LDA ($04),Y                     ; $2E7C
        AND #$7F                        ; $2E7E
        JSR match_special               ; $2E80
        INY                             ; $2E83
        DEC $4C                         ; $2E84
        BPL scan_special_cell           ; $2E86
        RTS                             ; $2E88
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
        CMP #$05                        ; $2E89
        BNE match_tile_2                ; $2E8B
        JMP exit_tile_5                 ; $2E8D
match_tile_2:
        CMP #$02                        ; $2E90
        BNE match_tile_3                ; $2E92
        JMP exit_tile_2                 ; $2E94
match_tile_3:
        CMP #$03                        ; $2E97
        BNE match_tile_4                ; $2E99
        JMP exit_tile_3                 ; $2E9B
match_tile_4:
        CMP #$04                        ; $2E9E
        BNE match_ladder                ; $2EA0
        JMP exit_tile_4                 ; $2EA2
; Tile $62 is the scrolling ladder. $61 and $63 move with it and do not
; catch. Bit 7 was masked, so the shadow's $E2 matches this compare too.
match_ladder:
        CMP #$62                        ; $2EA5
        BEQ match_catch                 ; $2EA7
match_extra_fall:
        CMP #$2D                        ; $2EA9
        BEQ match_room_16               ; $2EAB
        CMP #$2E                        ; $2EAD
        BEQ match_room_16               ; $2EAF
; $53 held hit bit 1. The shift leaves zero when that bit was clear, and
; every prize tile below is then skipped. The tiles compared above, the
; doors among them, are tested either way.
        ASL $53                         ; $2EB1
        BEQ match_none                  ; $2EB3
        CMP #$13                        ; $2EB5
        BEQ take_lamp                   ; $2EB7
        CMP #$14                        ; $2EB9
        BEQ take_lamp                   ; $2EBB
        CMP #$31                        ; $2EBD
        BEQ take_lamp                   ; $2EBF
        CMP #$64                        ; $2EC1
        BEQ match_shock                 ; $2EC3
        CMP #$66                        ; $2EC5
        BEQ match_tile_66               ; $2EC7
        CMP #$0F                        ; $2EC9
        BEQ match_shock                 ; $2ECB
        CMP #$40                        ; $2ECD
        BEQ match_shock                 ; $2ECF
        CMP #$57                        ; $2ED1
        BEQ match_hot                   ; $2ED3
        CMP #$54                        ; $2ED5
        BCC match_none                  ; $2ED7
        CMP #$5B                        ; $2ED9
        BCC match_shock                 ; $2EDB
; $71-$7C are hot, and shock is where they go. The flames that step_crumble
; prints over a nozzle are this range. $60 is the nozzle itself. Bit 1 arms
; start_crumble. The nozzle is not hot, and its screen code is not a wall.
match_hot:
        CMP #$71                        ; $2EDD
        BCC match_nozzle                ; $2EDF
        CMP #$7D                        ; $2EE1
        BCC match_shock                 ; $2EE3
match_nozzle:
        CMP #$60                        ; $2EE5
        BEQ match_crumble               ; $2EE7
match_none:
        RTS                             ; $2EE9
match_room_16:
        LDA $29                         ; $2EEA
        CMP #$10                        ; $2EEC
        BEQ match_extra_fall_go         ; $2EEE
        RTS                             ; $2EF0
match_extra_fall_go:
        JMP extra_fall                  ; $2EF1
match_catch:
        JMP catch_surface               ; $2EF4
match_crumble:
        JMP start_crumble               ; $2EF7
match_tile_66:
        LDA $29                         ; $2EFA
        CMP #$0A                        ; $2EFC
        BCS match_shock                 ; $2EFE
        RTS                             ; $2F00
match_shock:
        JMP shock                       ; $2F01
; Tiles $13, $14, and $31. Bruce only: any other actor returns. claim_lamp
; returns the bare mount, or sets carry when this cell is not in the room's
; list. The mount is written on this row. The same byte with bit 7 set is
; written $28 bytes later, the shadow row. $7D is added to the low score
; byte. That add is binary, and 125 is what the six digits then show.
; Sound $8E plays.
take_lamp:
        TXA                             ; $2F04
        BNE match_none                  ; $2F05
        JSR stash_axy                   ; $2F07
        JSR claim_lamp                  ; $2F0A
        BCS take_lamp_done              ; $2F0D
        PHA                             ; $2F0F
        JSR restore_axy                 ; $2F10
        PLA                             ; $2F13
        STA ($04),Y                     ; $2F14
        ORA #$80                        ; $2F16
        PHA                             ; $2F18
        TYA                             ; $2F19
        CLC                             ; $2F1A
        ADC #$28                        ; $2F1B
        TAY                             ; $2F1D
        PLA                             ; $2F1E
        STA ($04),Y                     ; $2F1F
        AND #$7F                        ; $2F21
        PHA                             ; $2F23
        TYA                             ; $2F24
        SEC                             ; $2F25
        SBC #$28                        ; $2F26
        TAY                             ; $2F28
        PLA                             ; $2F29
        JSR stash_axy                   ; $2F2A
        LDA #$7D                        ; $2F2D
        LDX #$02                        ; $2F2F
        JSR add_score                   ; $2F31
        LDY #$8E                        ; $2F34
        JSR play_sound                  ; $2F36
take_lamp_done:
        JMP restore_axy                 ; $2F39
; One slot. exit_allowed returns carry clear to take it. $4E becomes
; the destination room, Y the ypos, A the xpos. A zero xpos falls
; through to the next slot. Tile 5 does not test A. $51 is the actor
; the scan is on. Bruce, $51 = 0, is the one who changes rooms.
exit_tile_2:
        JSR exit_allowed                ; $2F3C
exit_slot_0_test:
        BCS match_none                  ; $2F3F
        LDX $29                         ; $2F41
        LDA $4B5E,X                     ; $2F43
        STA $4E                         ; $2F46
        LDA $4C12,X                     ; $2F48
        TAY                             ; $2F4B
        LDA $4BFE,X                     ; $2F4C
        BNE finish_exit                 ; $2F4F
; Door slot 1: $4B72 room, $4C26 xpos, $4C3A ypos.
exit_tile_3:
        JSR exit_allowed                ; $2F51
        BCS exit_slot_0_test            ; $2F54
        LDX $29                         ; $2F56
        LDA $4B72,X                     ; $2F58
        STA $4E                         ; $2F5B
        LDA $4C3A,X                     ; $2F5D
        TAY                             ; $2F60
        LDA $4C26,X                     ; $2F61
        BNE finish_exit                 ; $2F64
; Door slot 2: $4B86 room, $4C4E xpos, $4C62 ypos.
exit_tile_4:
        JSR exit_allowed                ; $2F66
exit_slot_2_test:
        BCS exit_slot_0_test            ; $2F69
        LDX $29                         ; $2F6B
        LDA $4B86,X                     ; $2F6D
        STA $4E                         ; $2F70
        LDA $4C62,X                     ; $2F72
        TAY                             ; $2F75
        LDA $4C4E,X                     ; $2F76
        BNE finish_exit                 ; $2F79
; Door slot 3: $4B9A room, $4C76 xpos, $4C8A ypos. The xpos is not tested.
exit_tile_5:
        JSR exit_allowed                ; $2F7B
        BCS exit_slot_2_test            ; $2F7E
        LDX $29                         ; $2F80
        LDA $4B9A,X                     ; $2F82
        STA $4E                         ; $2F85
        LDA $4C8A,X                     ; $2F87
        TAY                             ; $2F8A
        LDA $4C76,X                     ; $2F8B
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
        LDX $51                         ; $2F8E
        BEQ finish_exit_bruce           ; $2F90
        JSR retire_actor                ; $2F92
        PLA                             ; $2F95
        PLA                             ; $2F96
        JMP scan_specials_next          ; $2F97
; Bruce. Store the new position and the room, then go through the
; fighters from X = 2.
finish_exit_bruce:
        STA xpos,X                      ; $2F9A
        TYA                             ; $2F9C
        STA ypos,X                      ; $2F9D
        LDA $4E                         ; $2F9F
        STA $29                         ; $2FA1
        LDX #$02                        ; $2FA3
; Active: keep Bruce's xpos and ypos, and this fighter's $D1, for the next
; wake. Inactive: the xpos and ypos bytes are cleared, so that wake uses
; the room's spawn tables.
save_fighter_loop:
        LDA active,X                    ; $2FA5
        AND #$01                        ; $2FA7
        BEQ save_fighter_clear          ; $2FA9
        LDA $D1,X                       ; $2FAB
        STA $8E,X                       ; $2FAD
        LDA xpos                        ; $2FAF
        STA $8A,X                       ; $2FB1
        LDA ypos                        ; $2FB3
        STA $8C,X                       ; $2FB5
        BNE save_fighter_retire         ; $2FB7
save_fighter_clear:
        LDA #$00                        ; $2FB9
        STA $8A,X                       ; $2FBB
        STA $8C,X                       ; $2FBD
save_fighter_retire:
        JSR retire_actor                ; $2FBF
        DEX                             ; $2FC2
        BNE save_fighter_loop           ; $2FC3
        SEI                             ; $2FC5
        JSR load_wake_counts            ; $2FC6
        LDX #$FF                        ; $2FC9
        TXS                             ; $2FCB
        JSR enter_room                  ; $2FCC
        JSR blit_sprites                ; $2FCF
        CLI                             ; $2FD2
        JMP frame                       ; $2FD3
; Tiles $2D and $2E, and the caller has already required room 16. Bruce
; only, and only when ypos is at least $A0. The DEC of $4E95,X is not
; tested, so the fall is given every time the scan matches, including after
; the counter has gone through zero. hook_enter_16 reads that counter only to
; decide whether to print the caption. The trainer overwrites the INC with
; LDA, the same byte as at $1826.
; Effect $8E, the same phrase as take_lamp. The extra fall that
; check_life_mark gives for a score mark is silent.
extra_fall:
        TXA                             ; $2FD6
        BEQ extra_fall_bruce            ; $2FD7
extra_fall_done:
        RTS                             ; $2FD9
extra_fall_bruce:
        LDA ypos                        ; $2FDA
        CMP #$A0                        ; $2FDC
        BCC extra_fall_done             ; $2FDE
        LDX $03                         ; $2FE0
        DEC $4E95,X                     ; $2FE2
        INC $28                         ; $2FE5
        JSR lives_to_bcd                ; $2FE7
        LDY #$8E                        ; $2FEA
        JSR play_sound                  ; $2FEC
; String $56 at column $24 of tile rows $0A and $0B. hook_enter_16 also
; prints it, once the room's extra falls are spent.
extra_fall_caption:
        LDA #$56                        ; $2FEF
        LDX #$0A                        ; $2FF1
        LDY #$24                        ; $2FF3
        JSR print_string                ; $2FF5
        LDA #$56                        ; $2FF8
        LDX #$0B                        ; $2FFA
        LDY #$24                        ; $2FFC
        JMP print_string                ; $2FFE
; Clear active bit 0, turn off his hardware sprites, and drop the two
; object slots at $EC,X and $EF,X, then jumps to load_wake_counts to arm
; the next wake for this X.
retire_actor:
        LDA #$01                        ; $3001
        EOR #$FF                        ; $3003
        AND active,X                    ; $3005
        STA active,X                    ; $3007
        LDY $276D,X                     ; $3009
        LDA $D015                       ; $300C  sprite enable
        AND $2778,Y                     ; $300F
        STA $D015                       ; $3012  sprite enable
        LDY $2770,X                     ; $3015
        BMI retire_voice_1              ; $3018
        LDA $D015                       ; $301A  sprite enable
        AND $2778,Y                     ; $301D
        STA $D015                       ; $3020  sprite enable
retire_voice_1:
        LDA $EC,X                       ; $3023
        BEQ retire_voice_2              ; $3025
        JSR claim_voice_slot            ; $3027
        LDA #$FF                        ; $302A
        STA $4F40,Y                     ; $302C
retire_voice_2:
        LDA $EF,X                       ; $302F
        BEQ retire_clear_images         ; $3031
        JSR claim_voice_slot            ; $3033
        LDA #$FF                        ; $3036
        STA $4F40,Y                     ; $3038
retire_clear_images:
        CPX #$01                        ; $303B
        BNE retire_ninja_images         ; $303D
        JSR clear_sprite_ram            ; $303F
        JMP retire_reload_count         ; $3042
retire_ninja_images:
        JSR clear_upper_sprites         ; $3045
retire_reload_count:
        JMP load_wake_counts            ; $3048
; Hot tiles from match_special: $0F, $40, $64, $66 from room 10 on, $54-$5A
; except $57, and $71-$7C. Sound $8C. Room 18 returns without a shock.
; Bruce, $51 = 0, goes to state $19 for $10 frames. Any other actor loses
; active bit 0.
shock:
        LDA $29                         ; $304B
        CMP #$12                        ; $304D
        BNE shock_play                  ; $304F
        RTS                             ; $3051
shock_play:
        PHA                             ; $3052
        TXA                             ; $3053
        PHA                             ; $3054
        TYA                             ; $3055
        PHA                             ; $3056
        LDY #$8C                        ; $3057
        JSR play_sound                  ; $3059
        PLA                             ; $305C
        TAY                             ; $305D
        PLA                             ; $305E
        TAX                             ; $305F
        PLA                             ; $3060
        LDX $51                         ; $3061
        BEQ shock_bruce_go              ; $3063
        JMP retire_actor                ; $3065
shock_bruce_go:
        JMP shock_bruce                 ; $3068
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
        LDA $05                         ; $306B
        CLC                             ; $306D
        ADC #$4C                        ; $306E
        STA $05                         ; $3070
        LDA ($04),Y                     ; $3072
        AND #$07                        ; $3074
        CMP #$05                        ; $3076
        BEQ crumble_return              ; $3078
        LDA $4FDE                       ; $307A
        BNE crumble_slot_2              ; $307D
        LDA #$01                        ; $307F
        STA $4FDE                       ; $3081
        LDA $E9,X                       ; $3084
        STA $4FE4                       ; $3086
        STY $4FE1                       ; $3089
        DEC $4FE1                       ; $308C
        DEC $4FE4                       ; $308F
        JMP mark_crumble_spent          ; $3092
crumble_slot_2:
        LDA $4FDF                       ; $3095
        BNE crumble_slot_3              ; $3098
        LDA #$01                        ; $309A
        STA $4FDF                       ; $309C
        LDA $E9,X                       ; $309F
        STA $4FE5                       ; $30A1
        STY $4FE2                       ; $30A4
        DEC $4FE2                       ; $30A7
        DEC $4FE5                       ; $30AA
        JMP mark_crumble_spent          ; $30AD
crumble_slot_3:
        LDA $4FE0                       ; $30B0
        BNE crumble_return              ; $30B3
        LDA #$01                        ; $30B5
        STA $4FE0                       ; $30B7
        LDA $E9,X                       ; $30BA
        STA $4FE6                       ; $30BC
        STY $4FE3                       ; $30BF
        DEC $4FE3                       ; $30C2
        DEC $4FE6                       ; $30C5
; Write $FD to the cell's color byte, so its ink becomes 5 and the
; scan skips it from now on.
mark_crumble_spent:
        LDA #$FD                        ; $30C8
        STA ($04),Y                     ; $30CA
; Put $05 back on the screen row.
crumble_return:
        LDA $05                         ; $30CC
        SEC                             ; $30CE
        SBC #$4C                        ; $30CF
        STA $05                         ; $30D1
        RTS                             ; $30D3
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
        LDA $29                         ; $30D4
        CMP #$0B                        ; $30D6
        BEQ exit_yes                    ; $30D8
        SEC                             ; $30DA
        LDA xpos,X                      ; $30DB
        CMP #$10                        ; $30DD
        BCS exit_test_right             ; $30DF
        LDA $4F5D,X                     ; $30E1
        BNE exit_yes                    ; $30E4
exit_test_right:
        LDA #$A1                        ; $30E6
        CMP xpos,X                      ; $30E8
        BCS exit_test_bottom            ; $30EA
        LDA $4F60,X                     ; $30EC
        BNE exit_yes                    ; $30EF
exit_test_bottom:
        LDA #$C5                        ; $30F1
        CMP ypos,X                      ; $30F3
        BCS exit_test_top               ; $30F5
        LDA state,X                     ; $30F7
        CMP #$0E                        ; $30F9
        BEQ exit_yes                    ; $30FB
exit_test_top:
        LDA ypos,X                      ; $30FD
        CMP #$31                        ; $30FF
        BCS exit_no                     ; $3101
        LDA $4F57,X                     ; $3103
        BNE exit_yes                    ; $3106
; Carry set: the door stays shut for this step.
exit_no:
        SEC                             ; $3108
        RTS                             ; $3109
; Carry clear: the door is taken.
exit_yes:
        CLC                             ; $310A
        RTS                             ; $310B
; Tile $62. State $19 does not catch. Hit bit 2 clear does not catch.
; Otherwise state $17, timer $10, the pose hold cleared, and $AA cleared.
; $AD is not written. Control then continues at match_extra_fall, so a later test
; on the same cell can still shock him. Every actor is tested. This is
; how Yamo and the ninja get onto the moving ladder. They do not jump,
; and chase never climbs.
catch_surface:
        LDA state,X                     ; $310C
        CMP #$19                        ; $310E
        BEQ catch_continue              ; $3110
        LDA hit,X                       ; $3112
        AND #$04                        ; $3114
        BEQ catch_continue              ; $3116
        LDA #$17                        ; $3118
        STA state,X                     ; $311A
        LDA #$10                        ; $311C
        STA timer,X                     ; $311E
        LDA #$00                        ; $3120
        STA $0106,X                     ; $3122
        STA $AA,X                       ; $3125
catch_continue:
        LDA ($04),Y                     ; $3127
        JMP match_extra_fall            ; $3129
; Add the three bytes at $25 into the score at $41. $41 is the high byte and
; $43 is the low byte. The add is binary, with the carry kept between bytes,
; and a carry out of $41 is dropped, so the total wraps at 24 bits.
; check_life_mark then compares from the high byte. The first byte that is
; below its pair in $4392 skips the fall. When none is below, $28 is
; incremented and the step at $438E is added into the mark. draw_score runs
; either way and prints only the low six BCD digits.
apply_score:
        LDX #$02                        ; $312C
        CLC                             ; $312E
apply_score_add:
        LDA $41,X                       ; $312F
        ADC $25,X                       ; $3131
        STA $41,X                       ; $3133
        DEX                             ; $3135
        BPL apply_score_add             ; $3136
; High byte first. BCC on a short byte waits, even when a lower byte has
; already carried the total past the mark.
        LDX #$00                        ; $3138
; X = 0, 1, 2: compare one score byte with the mark at $4392,X.
check_life_mark:
        LDA $41,X                       ; $313A
        CMP $4392,X                     ; $313C
        BCC draw_score                  ; $313F
        INX                             ; $3141
        CPX #$03                        ; $3142
        BCC check_life_mark             ; $3144
        LDX #$02                        ; $3146
        CLC                             ; $3148
life_mark_step:
        LDA $4392,X                     ; $3149
        ADC $438E,X                     ; $314C
        STA $4392,X                     ; $314F
        DEX                             ; $3152
        BPL life_mark_step              ; $3153
; Extra fall when the score crosses the next mark. The trainer's LDA patch covers this too.
        INC $28                         ; $3155
        JSR lives_to_bcd                ; $3157
; Low six digits of the current total. Columns $30, $32, and $34.
draw_score:
        JSR stash_scores                ; $315A
        LDY #$30                        ; $315D
        LDA $439C                       ; $315F
        JSR draw_split_digits           ; $3162
        LDY #$32                        ; $3165
        LDA $439D                       ; $3167
        JSR draw_split_digits           ; $316A
        LDY #$34                        ; $316D
        LDA $439E                       ; $316F
        JMP draw_split_digits           ; $3172
; Add A to score byte X. The other two bytes of the addend are cleared, so
; one call moves one byte of the total. X = 0 is $41, X = 1 is $42, and
; X = 2 is $43. A lamp passes $7D with X = 2, which is 125.
add_score:
        PHA                             ; $3175
        LDA #$00                        ; $3176
        STA $25                         ; $3178
        STA $26                         ; $317A
        STA $27                         ; $317C
        PLA                             ; $317E
        STA $25,X                       ; $317F
        JMP apply_score                 ; $3181
; Every frame. With $0104 clear, draw_score redraws the current total. In
; play, compare $4388 with $41 from the high byte as an unsigned 24-bit
; value. A smaller top is replaced from the score and draw_top reprints it.
; The top score is not cleared with the working RAM, so it survives a game.
refresh_top:
        LDA $0104                       ; $3184
        BEQ draw_score                  ; $3187
        LDA $CF7B                       ; $3189
        EOR $CF9B                       ; $318C
        BNE top_compare                 ; $318F
        LDA $CF7E                       ; $3191
        EOR $CF9E                       ; $3194
        BNE top_compare                 ; $3197
        LDA $CF81                       ; $3199
        EOR $CFA1                       ; $319C
        BNE top_compare                 ; $319F
        NOP                             ; $31A1
        NOP                             ; $31A2
        NOP                             ; $31A3
top_compare:
        LDX #$00                        ; $31A4
top_compare_loop:
        LDA $4388,X                     ; $31A6
        CMP $41,X                       ; $31A9
        BCC top_replace                 ; $31AB
        BEQ top_compare_next            ; $31AD
        BCS draw_score                  ; $31AF
top_compare_next:
        INX                             ; $31B1
        CPX #$03                        ; $31B2
        BCC top_compare_loop            ; $31B4
        BCS draw_score                  ; $31B6
top_replace:
        LDX #$03                        ; $31B8
top_replace_loop:
        LDA $41,X                       ; $31BA
        STA $4388,X                     ; $31BC
        DEX                             ; $31BF
        BPL top_replace_loop            ; $31C0
; Low six digits of the top score. Columns $3C, $3E, and $40.
draw_top:
        LDX #$03                        ; $31C2
top_copy:
        LDA $4388,X                     ; $31C4
        STA $4398,X                     ; $31C7
        LDA #$00                        ; $31CA
        STA $439B,X                     ; $31CC
        DEX                             ; $31CF
        BPL top_copy                    ; $31D0
        STA $439E                       ; $31D2
        PHP                             ; $31D5
        SED                             ; $31D6
        LDX #$17                        ; $31D7
top_bcd_bit:
        ASL $439A                       ; $31D9
        ROL $4399                       ; $31DC
        ROL $4398                       ; $31DF
        LDY #$03                        ; $31E2
top_bcd_double:
        LDA $439B,Y                     ; $31E4
        ADC $439B,Y                     ; $31E7
        STA $439B,Y                     ; $31EA
        DEY                             ; $31ED
        BPL top_bcd_double              ; $31EE
        DEX                             ; $31F0
        BPL top_bcd_bit                 ; $31F1
        PLP                             ; $31F3
        LDY #$3C                        ; $31F4
        LDA $439C                       ; $31F6
        JSR draw_split_digits           ; $31F9
        LDY #$3E                        ; $31FC
        LDA $439D                       ; $31FE
        JSR draw_split_digits           ; $3201
        LDY #$40                        ; $3204
        LDA $439E                       ; $3206
        JMP draw_split_digits           ; $3209
        .byte $B0, $04

; A is shifted down by four. Used before a digit is drawn.
high_nibble:
        LSR A                           ; $320E
        LSR A                           ; $320F
        LSR A                           ; $3210
        LSR A                           ; $3211
        AND #$0F                        ; $3212
        RTS                             ; $3214
        .byte $A6, $29

; X is the room. $51 is forced to 0, so finish_exit treats the caller as
; Bruce. A and Y are that room's spawn at $4BAE,X and $4BC2,X, not an
; exit slot. room_11_to_13 calls this with X = $0D once rooms 12, 14, and
; 16 are clear. between_lives calls it with X = $29. $24DB is this same
; sequence inlined for the current room.
enter_room_at:
        LDA #$00                        ; $3217
        STA $51                         ; $3219
        TXA                             ; $321B
        STA $4E                         ; $321C
        LDA $4BC2,X                     ; $321E
        TAY                             ; $3221
        LDA $4BAE,X                     ; $3222
        JMP finish_exit                 ; $3225

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
        LDX #$02                        ; $3228
        STX $4F                         ; $322A
crumble_loop:
        LDX $4F                         ; $322C
        LDA $4FDE,X                     ; $322E
        BNE crumble_count               ; $3231
        JMP crumble_next                ; $3233
crumble_count:
        INC $4FDE,X                     ; $3236
        CMP #$08                        ; $3239
        BNE crumble_second_test         ; $323B
        JSR crumble_sound               ; $323D
crumble_first_flame:
        LDX $4F                         ; $3240
        LDY $4FE1,X                     ; $3242
        LDA $4FE4,X                     ; $3245
        TAX                             ; $3248
        LDA #$2F                        ; $3249
        JSR print_string                ; $324B
        LDX $4F                         ; $324E
        LDY $4FE1,X                     ; $3250
        LDA $4FE4,X                     ; $3253
        TAX                             ; $3256
        INX                             ; $3257
        LDA #$30                        ; $3258
        JSR print_string                ; $325A
        JMP crumble_next                ; $325D
crumble_second_test:
        CMP #$0C                        ; $3260
        BNE crumble_clear_test          ; $3262
        LDY $4FE1,X                     ; $3264
        LDA $4FE4,X                     ; $3267
        TAX                             ; $326A
        LDA #$31                        ; $326B
        JSR print_string                ; $326D
        LDX $4F                         ; $3270
        LDY $4FE1,X                     ; $3272
        LDA $4FE4,X                     ; $3275
        TAX                             ; $3278
        INX                             ; $3279
        LDA #$32                        ; $327A
        JSR print_string                ; $327C
        JMP crumble_next                ; $327F
crumble_clear_test:
        CMP #$10                        ; $3282
        BEQ crumble_first_flame         ; $3284
        CMP #$14                        ; $3286
        BNE crumble_free_test           ; $3288
        LDY $4FE1,X                     ; $328A
        LDA $4FE4,X                     ; $328D
        TAX                             ; $3290
        LDA #$00                        ; $3291
        JSR print_string                ; $3293
        DEY                             ; $3296
        DEY                             ; $3297
        LDA $04                         ; $3298
        CLC                             ; $329A
        ADC #$50                        ; $329B
        STA $04                         ; $329D
        LDA $05                         ; $329F
        ADC #$4C                        ; $32A1
        STA $05                         ; $32A3
        LDA #$F8                        ; $32A5
        STA ($04),Y                     ; $32A7
        LDX $4F                         ; $32A9
        LDY $4FE1,X                     ; $32AB
        LDA $4FE4,X                     ; $32AE
        TAX                             ; $32B1
        INX                             ; $32B2
        LDA #$33                        ; $32B3
        JSR print_string                ; $32B5
        JMP crumble_next                ; $32B8
crumble_free_test:
        CMP #$18                        ; $32BB
        BNE crumble_next                ; $32BD
        LDA #$00                        ; $32BF
        STA $4FDE,X                     ; $32C1
crumble_next:
        DEC $4F                         ; $32C4
        BMI crumble_done                ; $32C6
        JMP crumble_loop                ; $32C8
crumble_done:
        RTS                             ; $32CB
; Sound $8D. Played when a nozzle's count leaves 8, the first flame frame.
crumble_sound:
        PHA                             ; $32CC
        TXA                             ; $32CD
        PHA                             ; $32CE
        TYA                             ; $32CF
        PHA                             ; $32D0
        LDY #$8D                        ; $32D1
        JSR play_sound                  ; $32D3
        PLA                             ; $32D6
        TAY                             ; $32D7
        PLA                             ; $32D8
        TAX                             ; $32D9
        PLA                             ; $32DA
        RTS                             ; $32DB

; Copy the three score bytes at $41 into $4398 and convert that binary
; value to BCD with SED. The eight digits land in $439B-$439E. draw_score
; prints the low six, $439C-$439E. draw_top converts $4388 the same way.
stash_scores:
        LDX #$02                        ; $32DC
stash_copy:
        LDA $41,X                       ; $32DE
        STA $4398,X                     ; $32E0
        LDA #$00                        ; $32E3
        STA $439B,X                     ; $32E5
        DEX                             ; $32E8
        BPL stash_copy                  ; $32E9
        STA $439E                       ; $32EB
        PHP                             ; $32EE
        SED                             ; $32EF
        LDX #$17                        ; $32F0
stash_bcd_bit:
        ASL $439A                       ; $32F2
        ROL $4399                       ; $32F5
        ROL $4398                       ; $32F8
        LDY #$03                        ; $32FB
stash_bcd_double:
        LDA $439B,Y                     ; $32FD
        ADC $439B,Y                     ; $3300
        STA $439B,Y                     ; $3303
        DEY                             ; $3306
        BPL stash_bcd_double            ; $3307
        DEX                             ; $3309
        BPL stash_bcd_bit               ; $330A
        PLP                             ; $330C
        RTS                             ; $330D
; Keep A, X, and Y in $57-$59. take_lamp brackets claim_lamp with these.
stash_axy:
        STA $57                         ; $330E
        STX $58                         ; $3310
        STY $59                         ; $3312
        RTS                             ; $3314
; The other half. A, X, and Y come back from $57-$59.
restore_axy:
        LDA $57                         ; $3315
        LDX $58                         ; $3317
        LDY $59                         ; $3319
        RTS                             ; $331B
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
        LDX $51                         ; $331C
        LDA $E9,X                       ; $331E
        STA $5B                         ; $3320
        STY $5A                         ; $3322
        LDA $29                         ; $3324
        ASL A                           ; $3326
        TAX                             ; $3327
        LDA $4CE2,X                     ; $3328
        STA $14                         ; $332B
        LDA $4CE3,X                     ; $332D
        STA $15                         ; $3330
        LDY #$00                        ; $3332
claim_lamp_record:
        LDA #$01                        ; $3334
        STA $5C                         ; $3336
        LDA ($14),Y                     ; $3338
        BMI claim_lamp_none             ; $333A
        BNE claim_lamp_column           ; $333C
        LSR $5C                         ; $333E
claim_lamp_column:
        INY                             ; $3340
        INY                             ; $3341
        LDA ($14),Y                     ; $3342
        CMP $5A                         ; $3344
        BEQ claim_lamp_row              ; $3346
        LSR $5C                         ; $3348
claim_lamp_row:
        INY                             ; $334A
        LDA ($14),Y                     ; $334B
        CMP $5B                         ; $334D
        BEQ claim_lamp_test             ; $334F
        LSR $5C                         ; $3351
claim_lamp_test:
        LDA $5C                         ; $3353
        BNE claim_lamp_found            ; $3355
        INY                             ; $3357
        BNE claim_lamp_record           ; $3358
claim_lamp_none:
        SEC                             ; $335A
        RTS                             ; $335B
claim_lamp_found:
        DEY                             ; $335C
        DEY                             ; $335D
        DEY                             ; $335E
        LDA #$00                        ; $335F
        STA ($14),Y                     ; $3361
        LDX $29                         ; $3363
        DEC $2A,X                       ; $3365
        INY                             ; $3367
        LDA ($14),Y                     ; $3368
        AND #$7F                        ; $336A
        CLC                             ; $336C
        RTS                             ; $336D
; ($14) becomes the room's lamp list from $4CE2, room*2, for claim_lamp
; and the enter path. Y is left at four times the records in the list.
point_lamp_list:
        LDA $29                         ; $336E
        ASL A                           ; $3370
        TAX                             ; $3371
        LDA $4CE2,X                     ; $3372
        STA $14                         ; $3375
        LDA $4CE3,X                     ; $3377
        STA $15                         ; $337A
        LDY #$00                        ; $337C
paint_lamp_record:
        LDA ($14),Y                     ; $337E
        BMI run_enter_hook              ; $3380
        BNE paint_lamp_skip             ; $3382
        INY                             ; $3384
        LDA ($14),Y                     ; $3385
        PHA                             ; $3387
        INY                             ; $3388
        LDA ($14),Y                     ; $3389
        PHA                             ; $338B
        INY                             ; $338C
        STY $52                         ; $338D
        LDA ($14),Y                     ; $338F
        TAX                             ; $3391
        JSR point_at_row                ; $3392
        PLA                             ; $3395
        TAY                             ; $3396
        PLA                             ; $3397
        AND #$7F                        ; $3398
        STA ($04),Y                     ; $339A
        ORA #$80                        ; $339C
        PHA                             ; $339E
        TYA                             ; $339F
        CLC                             ; $33A0
        ADC #$28                        ; $33A1
        TAY                             ; $33A3
        PLA                             ; $33A4
        STA ($04),Y                     ; $33A5
        LDY $52                         ; $33A7
        JMP paint_lamp_next             ; $33A9
paint_lamp_skip:
        INY                             ; $33AC
        INY                             ; $33AD
        INY                             ; $33AE
paint_lamp_next:
        INY                             ; $33AF
        JMP paint_lamp_record           ; $33B0
run_enter_hook:
        LDX #$04                        ; $33B3
        LDA #$00                        ; $33B5
enter_hook_clear:
        STA $4E97,X                     ; $33B7
        DEX                             ; $33BA
        BPL enter_hook_clear            ; $33BB
        LDA $29                         ; $33BD
        ASL A                           ; $33BF
        TAX                             ; $33C0
        LDA $4E9D,X                     ; $33C1
        PHA                             ; $33C4
        LDA $4E9C,X                     ; $33C5
        PHA                             ; $33C8
        RTS                             ; $33C9
; Put every lamp flag back to 1. A flag with bit 7 set is the end of that
; room's list and is left alone. step_lamp advances four bytes, one record.
; Cold start calls this, and so does the treasure ending, so a finished
; game collects the lamps again. The counts at $2A are a separate copy.
; copy_room_defaults reloads those.
restore_lamps:
        LDA #$13                        ; $33CA
        STA $4E                         ; $33CC
; Rooms 19 down to 0. X is room*2, an index into $4CE2.
restore_next:
        LDA $4E                         ; $33CE
        ASL A                           ; $33D0
        TAX                             ; $33D1
        JSR restore_room                ; $33D2
        DEC $4E                         ; $33D5
        BPL restore_next                ; $33D7
        RTS                             ; $33D9
; $14/$15 = this room's lamp list from $4CE2,X.
restore_room:
        LDA $4CE2,X                     ; $33DA
        STA $14                         ; $33DD
        LDA $4CE3,X                     ; $33DF
        STA $15                         ; $33E2
        LDY #$00                        ; $33E4
; Store 1 in each record's flag until the bit-7 end marker.
next_flag:
        LDA ($14),Y                     ; $33E6
        BMI list_end                    ; $33E8
        LDA #$01                        ; $33EA
        STA ($14),Y                     ; $33EC
        JSR step_lamp                   ; $33EE
        JMP next_flag                   ; $33F1
; The end marker of this room's list.
list_end:
        RTS                             ; $33F4

; Per-room hooks. The word at $4E9C, room*2 is the enter hook, and the
; word at $4EC4, room*2 is the per-frame hook. Both store the address
; minus one. point_lamp_list calls the enter hook after the taken lamps are
; painted. run_frame_hook calls the per-frame hook once a logic frame.
;
; Enter hook for rooms 0, 2, 6, 10, and 11.
hook_enter_0:
        RTS                             ; $33F5
; Enter hook for room 1. Arms the trap-door count at $4E97 with 3.
hook_enter_1:
        LDA #$03                        ; $33F6
        STA $4E97                       ; $33F8
        RTS                             ; $33FB
; Enter hook for room 3.
hook_enter_3:
        LDA #$03                        ; $33FC
        STA $4E97                       ; $33FE
        RTS                             ; $3401
; Enter hook for room 4. Arms the three beams. It does not change $64 or
; $65. enter_room has already set the upward direction.
hook_enter_4:
        LDA #$1F                        ; $3402
        STA $4E9A                       ; $3404
        LDA #$01                        ; $3407
        STA $71                         ; $3409
        LDA #$0B                        ; $340B
        STA $74                         ; $340D
        LDA #$0B                        ; $340F
        STA $72                         ; $3411
        LDA #$07                        ; $3413
        STA $75                         ; $3415
        STA $76                         ; $3417
        LDA #$1A                        ; $3419
        STA $73                         ; $341B
        LDA #$FF                        ; $341D
        STA $77                         ; $341F
        STA $78                         ; $3421
        LDA #$F4                        ; $3423
        STA $79                         ; $3425
        RTS                             ; $3427
; Enter hook for room 5. Repeats until the byte at $02 is $32, writes
; color $FC across $D89A-$D89C and $D8C2-$D8C4, and reloads the three
; beam columns, rows, and timers. $74, $75, and $76 are tile rows 9,
; $0A, and 5. A timer is a byte, so $FF, $FC, and $F8 are the pauses.
hook_enter_5:
        LDX #$00                        ; $3428
        LDA $02,X                       ; $342A
        TAY                             ; $342C
        CPY #$32                        ; $342D
        BNE hook_enter_5                ; $342F
        LDA #$FC                        ; $3431
        LDX #$02                        ; $3433
hook5_colors:
        STA $D89A,X                     ; $3435  color RAM, row 3 column 34, plus X
        STA $D8C2,X                     ; $3438  color RAM, row 4 column 34, plus X
        DEX                             ; $343B
        BPL hook5_colors                ; $343C
        LDA #$1B                        ; $343E
        STA $71                         ; $3440
        STA $72                         ; $3442
        LDA #$01                        ; $3444
        STA $73                         ; $3446
        LDA #$09                        ; $3448
        STA $74                         ; $344A
        LDA #$0A                        ; $344C
        STA $75                         ; $344E
        LDA #$05                        ; $3450
        STA $76                         ; $3452
        LDA #$FF                        ; $3454
        STA $77                         ; $3456
        LDA #$FC                        ; $3458
        STA $78                         ; $345A
        LDA #$F8                        ; $345C
        STA $79                         ; $345E
        RTS                             ; $3460
; Enter hook for room 7.
hook_enter_7:
        LDA #$05                        ; $3461
        STA $6E                         ; $3463
        STA $70                         ; $3465
        LDA #$0B                        ; $3467
        STA $6F                         ; $3469
        LDA #$22                        ; $346B
        STA $71                         ; $346D
        LDA #$04                        ; $346F
        STA $74                         ; $3471
        LDA #$FF                        ; $3473
        STA $77                         ; $3475
        RTS                             ; $3477
; Enter hook for room 8.
hook_enter_8:
        LDA #$06                        ; $3478
        STA $71                         ; $347A
        LDA #$1B                        ; $347C
        STA $72                         ; $347E
        LDA #$05                        ; $3480
        STA $74                         ; $3482
        STA $75                         ; $3484
        LDA #$FF                        ; $3486
        STA $77                         ; $3488
        LDA #$F2                        ; $348A
        STA $78                         ; $348C
        RTS                             ; $348E
; Enter hook for room 9.
hook_enter_9:
        LDA #$FA                        ; $348F
        LDX #$03                        ; $3491
hook9_colors:
        STA $D89B,X                     ; $3493  color RAM, row 3 column 35, plus X
        STA $D8C3,X                     ; $3496  color RAM, row 4 column 35, plus X
        DEX                             ; $3499
        BPL hook9_colors                ; $349A
        LDA #$04                        ; $349C
        STA $6E                         ; $349E
        STA $70                         ; $34A0
        LDA #$0C                        ; $34A2
        STA $6F                         ; $34A4
        LDA #$10                        ; $34A6
        STA $71                         ; $34A8
        STA $72                         ; $34AA
        LDA #$05                        ; $34AC
        STA $74                         ; $34AE
        LDA #$06                        ; $34B0
        STA $75                         ; $34B2
        LDA #$FC                        ; $34B4
        STA $77                         ; $34B6
        LDA #$FF                        ; $34B8
        STA $78                         ; $34BA
        RTS                             ; $34BC
; Enter hook for room 12.
hook_enter_12:
        LDA #$01                        ; $34BD
        STA $4E97                       ; $34BF
        RTS                             ; $34C2
; Enter hook for room 13.
hook_enter_13:
        LDX #$04                        ; $34C3
hook13_sliders:
        LDA #$02                        ; $34C5
        STA $010F,X                     ; $34C7
        LDA #$82                        ; $34CA
        STA $0114,X                     ; $34CC
        DEX                             ; $34CF
        BPL hook13_sliders              ; $34D0
        LDA #$00                        ; $34D2
        STA $0118                       ; $34D4
        STA $0112                       ; $34D7
        LDA #$06                        ; $34DA
        STA $0138                       ; $34DC
        STA $011E                       ; $34DF
        STA $0132                       ; $34E2
        STA $013C                       ; $34E5
        STA $013D                       ; $34E8
        LDA #$02                        ; $34EB
        STA $011B                       ; $34ED
        STA $012F                       ; $34F0
        STA $0139                       ; $34F3
        STA $013B                       ; $34F6
        LDX $40                         ; $34F9
        BNE hook13_store_a              ; $34FB
        LDA #$06                        ; $34FD
hook13_store_a:
        STA $0120                       ; $34FF
        STA $0134                       ; $3502
        STA $013E                       ; $3505
        LDA #$12                        ; $3508
        LDX $40                         ; $350A
        BNE hook13_store_b              ; $350C
        LDA #$14                        ; $350E
hook13_store_b:
        STA $0137                       ; $3510
        STA $0148                       ; $3513
        LDA #$15                        ; $3516
        LDX $40                         ; $3518
        BNE hook13_store_c              ; $351A
        LDA #$13                        ; $351C
hook13_store_c:
        STA $011A                       ; $351E
        STA $012E                       ; $3521
        STA $0142                       ; $3524
        LDA #$16                        ; $3527
        STA $011F                       ; $3529
        STA $0133                       ; $352C
        STA $011D                       ; $352F
        STA $0131                       ; $3532
        LDX $40                         ; $3535
        BNE hook13_store_d              ; $3537
        LDA #$14                        ; $3539
hook13_store_d:
        STA $0121                       ; $353B
        STA $0135                       ; $353E
        STA $013F                       ; $3541
        LDA #$21                        ; $3544
        STA $0119                       ; $3546
        STA $012D                       ; $3549
        STA $0141                       ; $354C
        LDX $40                         ; $354F
        BEQ hook13_store_e              ; $3551
        LDA #$25                        ; $3553
hook13_store_e:
        STA $0143                       ; $3555
        STA $0145                       ; $3558
        LDA #$26                        ; $355B
        LDX $40                         ; $355D
        BNE hook13_store_f              ; $355F
        LDA #$22                        ; $3561
hook13_store_f:
        STA $0146                       ; $3563
        STA $0147                       ; $3566
        STA $0149                       ; $3569
        LDA #$05                        ; $356C
        STA $0128                       ; $356E
        STA $0129                       ; $3571
        LDA #$07                        ; $3574
        STA $0123                       ; $3576
        STA $012A                       ; $3579
        LDA #$0A                        ; $357C
        STA $0124                       ; $357E
        STA $012B                       ; $3581
        LDA #$0C                        ; $3584
        STA $0125                       ; $3586
        STA $0127                       ; $3589
        RTS                             ; $358C
; Enter hook for room 14.
hook_enter_14:
        LDA #$01                        ; $358D
        STA $4E97                       ; $358F
        RTS                             ; $3592
; Enter hook for room 15.
hook_enter_15:
        LDA #$01                        ; $3593
        STA $4E97                       ; $3595
        STA $4E98                       ; $3598
        STA $4E99                       ; $359B
        RTS                             ; $359E
; Enter hook for room 16.
hook_enter_16:
        LDA #$FF                        ; $359F
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
        LDX $03                         ; $35B9
        LDA $4E95,X                     ; $35BB
        BNE hook16_done                 ; $35BE
        JSR extra_fall_caption          ; $35C0
hook16_done:
        RTS                             ; $35C3
; Enter hook for room 17.
hook_enter_17:
        LDA #$FF                        ; $35C4
        STA $DB1E                       ; $35C6  color RAM, row 19 column 38
        LDA #$01                        ; $35C9
        STA $4E97                       ; $35CB
        STA $4E98                       ; $35CE
        LDA #$08                        ; $35D1
        STA $71                         ; $35D3
        STA $72                         ; $35D5
        STA $73                         ; $35D7
        LDA #$03                        ; $35D9
        STA $74                         ; $35DB
        LDA #$05                        ; $35DD
        STA $6F                         ; $35DF
        LDA #$07                        ; $35E1
        STA $75                         ; $35E3
        LDA #$09                        ; $35E5
        STA $76                         ; $35E7
        LDA #$0B                        ; $35E9
        STA $6E                         ; $35EB
        LDA #$F8                        ; $35ED
        STA $77                         ; $35EF
        LDA #$F1                        ; $35F1
        STA $78                         ; $35F3
        LDA #$EA                        ; $35F5
        STA $79                         ; $35F7
        RTS                             ; $35F9
; Enter hook for room 18.
hook_enter_18:
        LDX #$00                        ; $35FA
        LDA #$FE                        ; $35FC
hook18_colors:
        STA $D878,X                     ; $35FE  color RAM, row 3 column 0, plus X
        STA $D900,X                     ; $3601  color RAM, row 6 column 16, plus X
        STA $DA00,X                     ; $3604  color RAM, row 12 column 32, plus X
        STA $DB00,X                     ; $3607  color RAM, row 19 column 8, plus X
        INX                             ; $360A
        BNE hook18_colors               ; $360B
        LDX #$7F                        ; $360D
        LDA #$00                        ; $360F
hook18_clear_sprite:
        STA $8340,X                     ; $3611
        DEX                             ; $3614
        BPL hook18_clear_sprite         ; $3615
        STA $D017                       ; $3617  sprite double height
        LDA #$FF                        ; $361A
        STA $D01D                       ; $361C  sprite double width
        LDA #$01                        ; $361F
        STA $4E97                       ; $3621
        STA $4E98                       ; $3624
        LDA #$00                        ; $3627
        STA $432E                       ; $3629
        STA $432F                       ; $362C
        STA $4330                       ; $362F
        LDA #$10                        ; $3632
        STA $4331                       ; $3634
        LDA #$06                        ; $3637
        STA $4336                       ; $3639
        LDA #$07                        ; $363C
        STA $4337                       ; $363E
        RTS                             ; $3641
; Per-frame hook for room 0.
hook_frame_0:
        LDA $30                         ; $3642
        BNE hook0_done                  ; $3644
        LDA $7B                         ; $3646
        BNE hook0_done                  ; $3648
        DEC $4E97                       ; $364A
        BPL hook0_done                  ; $364D
        LDA $4E98                       ; $364F
        BNE hook0_blink_off             ; $3652
; Effect $81 with string $1D. The other phase of this blink is silent.
        LDY #$81                        ; $3654
        JSR play_sound                  ; $3656
        LDA #$1D                        ; $3659
        LDX #$09                        ; $365B
        LDY #$07                        ; $365D
        JSR print_string                ; $365F
        INC $4E98                       ; $3662
        BNE hook0_done                  ; $3665
hook0_blink_off:
        LDA #$1E                        ; $3667
        LDX #$09                        ; $3669
        LDY #$07                        ; $366B
        JSR print_string                ; $366D
        DEC $4E98                       ; $3670
        LDA #$05                        ; $3673
        STA $4E97                       ; $3675
hook0_done:
        RTS                             ; $3678
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
        LDA $7B                         ; $3679
        BNE hook1_done                  ; $367B
        LDA $4E97                       ; $367D
        BMI hook1_done                  ; $3680
        LDA $30                         ; $3682
        BEQ hook1_done                  ; $3684
        LDA $2A                         ; $3686
        ORA $2B                         ; $3688
        ORA $2C                         ; $368A
        BNE hook1_done                  ; $368C
        DEC $4E97                       ; $368E
        LDA $4E97                       ; $3691
        CMP #$02                        ; $3694
        BNE hook1_paint_door            ; $3696
        JSR play_sound_8a               ; $3698
hook1_paint_door:
        CLC                             ; $369B
        ADC #$10                        ; $369C
        LDX #$0C                        ; $369E
        LDY #$11                        ; $36A0
        JMP print_string                ; $36A2
hook1_done:
        RTS                             ; $36A5
; Per-frame hook for room 2.
hook_frame_2:
        NOP                             ; $36A6
        NOP                             ; $36A7
        NOP                             ; $36A8
        NOP                             ; $36A9
        NOP                             ; $36AA
        NOP                             ; $36AB
        NOP                             ; $36AC
        NOP                             ; $36AD
        LDA $30                         ; $36AE
        BNE hook2_done                  ; $36B0
        LDA $4E98                       ; $36B2
        BMI hook2_blink                 ; $36B5
        DEC $4E98                       ; $36B7
        JSR play_sound_8a               ; $36BA
        LDA #$1A                        ; $36BD
        LDX #$0B                        ; $36BF
        LDY #$25                        ; $36C1
        JSR print_string                ; $36C3
        LDA #$07                        ; $36C6
        LDX #$0C                        ; $36C8
        LDY #$25                        ; $36CA
        JSR print_string                ; $36CC
hook2_blink:
        LDA $7B                         ; $36CF
        BNE hook2_done                  ; $36D1
        DEC $4E99                       ; $36D3
        BPL hook2_done                  ; $36D6
        LDA $4E97                       ; $36D8
        BNE hook2_blink_off             ; $36DB
; Effect $81 with string $1D. The other phase of this blink is silent.
        LDY #$81                        ; $36DD
        JSR play_sound                  ; $36DF
        LDA #$1D                        ; $36E2
        LDX #$09                        ; $36E4
        LDY #$21                        ; $36E6
        JSR print_string                ; $36E8
        INC $4E97                       ; $36EB
        BNE hook2_done                  ; $36EE
hook2_blink_off:
        LDA #$1E                        ; $36F0
        LDX #$09                        ; $36F2
        LDY #$21                        ; $36F4
        JSR print_string                ; $36F6
        DEC $4E97                       ; $36F9
        LDA #$05                        ; $36FC
        STA $4E99                       ; $36FE
hook2_done:
        RTS                             ; $3701
; Per-frame hook for room 3.
hook_frame_3:
        LDA $7B                         ; $3702
        BNE hook3_swap_timer            ; $3704
        LDA $4E97                       ; $3706
        BMI hook3_swap_timer            ; $3709
        LDA $2D                         ; $370B
        BNE hook3_swap_timer            ; $370D
        DEC $4E97                       ; $370F
        LDA $4E97                       ; $3712
        CMP #$02                        ; $3715
        BNE hook3_paint_door            ; $3717
        JSR play_sound_8a               ; $3719
hook3_paint_door:
        CLC                             ; $371C
        ADC #$10                        ; $371D
        LDX #$0C                        ; $371F
        LDY #$1D                        ; $3721
        JSR print_string                ; $3723
hook3_swap_timer:
        DEC $4E99                       ; $3726
        BMI hook3_swap                  ; $3729
        RTS                             ; $372B
hook3_swap:
        LDA #$20                        ; $372C
        STA $4E99                       ; $372E
        LDA $4E98                       ; $3731
        BEQ hook3_swap_back             ; $3734
        DEC $4E98                       ; $3736
        LDA #$06                        ; $3739
        LDX #$06                        ; $373B
        LDY #$09                        ; $373D
        JSR print_string                ; $373F
        LDA #$60                        ; $3742
        LDX #$06                        ; $3744
        LDY #$15                        ; $3746
        JMP print_string                ; $3748
hook3_swap_back:
        INC $4E98                       ; $374B
        LDA #$60                        ; $374E
        LDX #$06                        ; $3750
        LDY #$09                        ; $3752
        JSR print_string                ; $3754
        LDA #$06                        ; $3757
        LDX #$06                        ; $3759
        LDY #$15                        ; $375B
        JMP print_string                ; $375D
; Per-frame hook for room 4. It ends in scroll_surface. The ladder is the
; vertical run of tiles $61, $62, $62, $63.
hook_frame_4:
        LDA $4D70                       ; $3760
        BEQ hook4_open_door             ; $3763
        INC $4E99                       ; $3765
        LDA $4E99                       ; $3768
        CMP #$20                        ; $376B
        BNE hook4_lamp_blink_off        ; $376D
        LDA #$34                        ; $376F
        LDX #$04                        ; $3771
        LDY #$0B                        ; $3773
        JSR print_string                ; $3775
        JMP hook4_open_door             ; $3778
hook4_lamp_blink_off:
        CMP #$40                        ; $377B
        BNE hook4_open_door             ; $377D
        LDA #$00                        ; $377F
        STA $4E99                       ; $3781
        LDA #$36                        ; $3784
        LDX #$04                        ; $3786
        LDY #$0B                        ; $3788
        JSR print_string                ; $378A
hook4_open_door:
        LDA $4D70                       ; $378D
        BNE hook4_second_lamp           ; $3790
        LDA $4E97                       ; $3792
        BMI hook4_second_lamp           ; $3795
        DEC $4E97                       ; $3797
        JSR play_sound_8a               ; $379A
        LDA #$16                        ; $379D
        LDX #$08                        ; $379F
        LDY #$0B                        ; $37A1
        JSR print_string                ; $37A3
        LDA #$16                        ; $37A6
        LDX #$09                        ; $37A8
        LDY #$0B                        ; $37AA
        JSR print_string                ; $37AC
        LDA #$06                        ; $37AF
        JSR print_row75                 ; $37B1
hook4_second_lamp:
        LDA $4D74                       ; $37B4
        BEQ hook4_open_second_door      ; $37B7
        INC $4E9A                       ; $37B9
        LDA $4E9A                       ; $37BC
        CMP #$20                        ; $37BF
        BNE hook4_lamp2_blink_off       ; $37C1
        LDA #$35                        ; $37C3
        LDX #$04                        ; $37C5
        LDY #$1C                        ; $37C7
        JSR print_string                ; $37C9
        JMP hook4_open_second_door      ; $37CC
hook4_lamp2_blink_off:
        CMP #$40                        ; $37CF
        BNE hook4_open_second_door      ; $37D1
        LDA #$00                        ; $37D3
        STA $4E9A                       ; $37D5
        LDA #$37                        ; $37D8
        LDX #$04                        ; $37DA
        LDY #$1C                        ; $37DC
        JSR print_string                ; $37DE
hook4_open_second_door:
        LDA $4D74                       ; $37E1
        BNE hook4_beam1                 ; $37E4
        LDA $4E98                       ; $37E6
        BMI hook4_beam1                 ; $37E9
        DEC $4E98                       ; $37EB
; Lamp $4D74 has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $37EE
        STA $65                         ; $37F0
        LDA #$07                        ; $37F2
        STA $4321                       ; $37F4
        JSR play_sound_8a               ; $37F7
        LDA #$16                        ; $37FA
        LDX #$08                        ; $37FC
        LDY #$19                        ; $37FE
        JSR print_string                ; $3800
        LDA #$16                        ; $3803
        LDX #$09                        ; $3805
        LDY #$19                        ; $3807
        JSR print_string                ; $3809
        LDA #$06                        ; $380C
        JSR print_row76                 ; $380E
hook4_beam1:
        INC $77                         ; $3811
        BMI hook4_beam2                 ; $3813
        LDA $77                         ; $3815
        CMP #$03                        ; $3817
        BEQ hook4_beam1_advance         ; $3819
        CMP #$07                        ; $381B
        BEQ hook4_beam1_reload          ; $381D
hook4_beam1_draw:
        JSR print_row74_later           ; $381F
        JMP hook4_beam2                 ; $3822
hook4_beam1_advance:
        LDX $71                         ; $3825
        CPX #$03                        ; $3827
        BCS hook4_beam1_draw            ; $3829
        LDA #$06                        ; $382B
        JSR print_row74_later           ; $382D
        INC $71                         ; $3830
        LDA #$02                        ; $3832
        STA $77                         ; $3834
        BNE hook4_beam1_draw            ; $3836
hook4_beam1_reload:
        LDA #$A0                        ; $3838
        STA $77                         ; $383A
        LDA #$01                        ; $383C
        STA $71                         ; $383E
hook4_beam2:
        LDA $4D70                       ; $3840
        BEQ hook4_beam3                 ; $3843
        INC $78                         ; $3845
        BMI hook4_beam3                 ; $3847
        LDA $78                         ; $3849
        CMP #$03                        ; $384B
        BEQ hook4_beam2_advance         ; $384D
        CMP #$07                        ; $384F
        BEQ hook4_beam2_reload          ; $3851
hook4_beam2_draw:
        JSR print_row75                 ; $3853
        JMP hook4_beam3                 ; $3856
hook4_beam2_advance:
        LDX $72                         ; $3859
        CPX #$0C                        ; $385B
        BCS hook4_beam2_draw            ; $385D
        LDA #$06                        ; $385F
        JSR print_row75                 ; $3861
        INC $72                         ; $3864
        LDA #$02                        ; $3866
        STA $78                         ; $3868
        BNE hook4_beam2_draw            ; $386A
hook4_beam2_reload:
        LDA #$E4                        ; $386C
        STA $78                         ; $386E
        LDA #$0B                        ; $3870
        STA $72                         ; $3872
hook4_beam3:
        LDA $4D74                       ; $3874
        BEQ hook4_scroll                ; $3877
        INC $79                         ; $3879
        BMI hook4_scroll                ; $387B
        LDA $79                         ; $387D
        CMP #$03                        ; $387F
        BEQ hook4_beam3_advance         ; $3881
        CMP #$07                        ; $3883
        BEQ hook4_beam3_reload          ; $3885
hook4_beam3_draw:
        JSR print_row76                 ; $3887
        JMP hook4_scroll                ; $388A
hook4_beam3_advance:
        LDX $73                         ; $388D
        CPX #$1B                        ; $388F
        BCS hook4_beam3_draw            ; $3891
        LDA #$06                        ; $3893
        JSR print_row76                 ; $3895
        INC $73                         ; $3898
        LDA #$02                        ; $389A
        STA $79                         ; $389C
        BNE hook4_beam3_draw            ; $389E
hook4_beam3_reload:
        LDA #$E4                        ; $38A0
        STA $79                         ; $38A2
        LDA #$1A                        ; $38A4
        STA $73                         ; $38A6
hook4_scroll:
        JMP scroll_surface              ; $38A8
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
        LDA $4D99                       ; $38AB
        BNE hook5_second_passage        ; $38AE
        LDA $4E99                       ; $38B0
        BMI hook5_second_passage        ; $38B3
        DEC $4E99                       ; $38B5
        LDA #$0A                        ; $38B8
        LDY #$19                        ; $38BA
        JSR draw_passage                ; $38BC
        LDA #$0A                        ; $38BF
        LDY #$1A                        ; $38C1
        JSR draw_passage                ; $38C3
        LDA #$06                        ; $38C6
        JSR print_row75                 ; $38C8
hook5_second_passage:
        LDA $4D91                       ; $38CB
        BNE hook5_third_passage         ; $38CE
        LDA $4E9A                       ; $38D0
        BMI hook5_third_passage         ; $38D3
        DEC $4E9A                       ; $38D5
        LDA #$0A                        ; $38D8
        LDY #$00                        ; $38DA
        JSR draw_passage                ; $38DC
        LDA #$15                        ; $38DF
        LDX #$0B                        ; $38E1
        LDY #$00                        ; $38E3
        JSR print_string                ; $38E5
hook5_third_passage:
        LDA $30                         ; $38E8
        ORA $4D81                       ; $38EA
        BEQ hook5_open_third            ; $38ED
        LDA $30                         ; $38EF
        ORA $4D89                       ; $38F1
        BNE hook5_beam1                 ; $38F4
hook5_open_third:
        LDA $4E9B                       ; $38F6
        BMI hook5_beam1                 ; $38F9
        DEC $4E9B                       ; $38FB
        LDA #$19                        ; $38FE
        LDX #$02                        ; $3900
        LDY #$22                        ; $3902
        JSR print_string                ; $3904
        LDA #$03                        ; $3907
        LDY #$1E                        ; $3909
        JSR draw_passage                ; $390B
        LDA #$06                        ; $390E
        LDY #$20                        ; $3910
        JSR draw_passage                ; $3912
hook5_beam1:
        INC $77                         ; $3915
        BMI hook5_beam2                 ; $3917
        LDA $77                         ; $3919
        CMP #$03                        ; $391B
        BEQ hook5_beam1_advance         ; $391D
        CMP #$07                        ; $391F
        BEQ hook5_beam1_reload          ; $3921
hook5_beam1_draw:
        JSR print_row74                 ; $3923
        JMP hook5_beam2                 ; $3926
hook5_beam1_advance:
        LDX $71                         ; $3929
        CPX #$1C                        ; $392B
        BCS hook5_beam1_draw            ; $392D
        LDA #$06                        ; $392F
        JSR print_row74                 ; $3931
        INC $71                         ; $3934
        LDA #$02                        ; $3936
        STA $77                         ; $3938
        BNE hook5_beam1_draw            ; $393A
hook5_beam1_reload:
        LDA #$E0                        ; $393C
        STA $77                         ; $393E
        LDA #$1B                        ; $3940
        STA $71                         ; $3942
hook5_beam2:
        LDA $4D99                       ; $3944
        BEQ hook5_beam3                 ; $3947
        INC $78                         ; $3949
        BMI hook5_beam3                 ; $394B
        LDA $78                         ; $394D
        CMP #$03                        ; $394F
        BEQ hook5_beam2_advance         ; $3951
        CMP #$07                        ; $3953
        BEQ hook5_beam2_reload          ; $3955
hook5_beam2_draw:
        JSR print_row75                 ; $3957
        JMP hook5_beam3                 ; $395A
hook5_beam2_advance:
        LDX $72                         ; $395D
        CPX #$1C                        ; $395F
        BCS hook5_beam2_draw            ; $3961
        LDA #$06                        ; $3963
        JSR print_row75                 ; $3965
        INC $72                         ; $3968
        LDA #$02                        ; $396A
        STA $78                         ; $396C
        BNE hook5_beam2_draw            ; $396E
hook5_beam2_reload:
        LDA #$E0                        ; $3970
        STA $78                         ; $3972
        LDA #$1B                        ; $3974
        STA $72                         ; $3976
hook5_beam3:
        INC $79                         ; $3978
        BMI hook5_scroll                ; $397A
        LDA $79                         ; $397C
        CMP #$03                        ; $397E
        BEQ hook5_beam3_advance         ; $3980
        CMP #$07                        ; $3982
        BEQ hook5_beam3_reload          ; $3984
hook5_beam3_draw:
        JSR print_row76_later           ; $3986
        JMP hook5_scroll                ; $3989
hook5_beam3_advance:
        LDX $73                         ; $398C
        CPX #$02                        ; $398E
        BCS hook5_beam3_draw            ; $3990
        LDA #$06                        ; $3992
        JSR print_row76_later           ; $3994
        INC $73                         ; $3997
        LDA #$02                        ; $3999
        STA $79                         ; $399B
        BNE hook5_beam3_draw            ; $399D
hook5_beam3_reload:
        LDA #$E2                        ; $399F
        STA $79                         ; $39A1
        LDA #$01                        ; $39A3
        STA $73                         ; $39A5
hook5_scroll:
        JMP scroll_surface              ; $39A7
; Per-frame hook for room 6. It ends in scroll_surface.
hook_frame_6:
        LDA $30                         ; $39AA
        BNE hook6_crumble               ; $39AC
        LDA $4E97                       ; $39AE
        BMI hook6_crumble               ; $39B1
        DEC $4E97                       ; $39B3
        LDA #$05                        ; $39B6
        LDY #$01                        ; $39B8
        JSR draw_passage_17             ; $39BA
hook6_crumble:
        JSR step_crumble                ; $39BD
        JMP scroll_surface              ; $39C0
; Per-frame hook for room 7. step_crumble runs first. The hook itself runs
; before the overlap, so a nozzle armed on the previous frame is still
; screen code $60 when that walk is tested again.
hook_frame_7:
        JSR step_crumble                ; $39C3
        LDA $4DC3                       ; $39C6
        ORA $4DC7                       ; $39C9
        ORA $4DCB                       ; $39CC
        ORA $4DCF                       ; $39CF
        ORA $4DD3                       ; $39D2
        BNE hook7_second_passage        ; $39D5
        LDA $4E97                       ; $39D7
        BMI hook7_second_passage        ; $39DA
        DEC $4E97                       ; $39DC
        LDA #$02                        ; $39DF
        LDY #$21                        ; $39E1
        JMP draw_passage_17             ; $39E3
hook7_second_passage:
        LDA $4DD7                       ; $39E6
        ORA $4DDB                       ; $39E9
        ORA $4DDF                       ; $39EC
        ORA $4DE3                       ; $39EF
        ORA $4DE7                       ; $39F2
        ORA $4DEB                       ; $39F5
        BNE hook7_beam                  ; $39F8
        LDA $4E98                       ; $39FA
        BMI hook7_beam                  ; $39FD
        DEC $4E98                       ; $39FF
        LDA #$05                        ; $3A02
        LDY #$26                        ; $3A04
        JMP draw_passage_17             ; $3A06
hook7_beam:
        INC $77                         ; $3A09
        BMI hook7_slider                ; $3A0B
        LDA $77                         ; $3A0D
        CMP #$03                        ; $3A0F
        BEQ hook7_beam_advance          ; $3A11
        CMP #$07                        ; $3A13
        BEQ hook7_beam_reload           ; $3A15
hook7_beam_draw:
        JSR print_row74_later           ; $3A17
        JMP hook7_slider                ; $3A1A
hook7_beam_advance:
        LDX $71                         ; $3A1D
        CPX #$24                        ; $3A1F
        BCS hook7_beam_draw             ; $3A21
        LDA #$06                        ; $3A23
        JSR print_row74_later           ; $3A25
        INC $71                         ; $3A28
        LDA #$02                        ; $3A2A
        STA $77                         ; $3A2C
        BNE hook7_beam_draw             ; $3A2E
hook7_beam_reload:
        LDA #$22                        ; $3A30
        STA $71                         ; $3A32
        LDA #$E0                        ; $3A34
        STA $77                         ; $3A36
hook7_slider:
        LDA $4DEF                       ; $3A38
        ORA $4DF3                       ; $3A3B
        BEQ hook7_slider_left           ; $3A3E
        LDA $6E                         ; $3A40
        STA $70                         ; $3A42
        INC $6E                         ; $3A44
        CMP #$23                        ; $3A46
        BCC hook7_slider_draw_right     ; $3A48
        LDA #$05                        ; $3A4A
        STA $6E                         ; $3A4C
hook7_slider_draw_right:
        JMP draw_slider                 ; $3A4E
hook7_slider_left:
        LDA $6E                         ; $3A51
        STA $70                         ; $3A53
        DEC $6E                         ; $3A55
        CMP #$06                        ; $3A57
        BCS hook7_slider_draw_left      ; $3A59
        LDA #$24                        ; $3A5B
        STA $6E                         ; $3A5D
hook7_slider_draw_left:
        JMP draw_slider                 ; $3A5F
; $3A62  one RTS that nothing reaches.

; Add 4 to the lamp-list pointer in $14/$15. restore_lamps uses this
; to walk from one record to the next.
step_lamp:
        LDA $14                         ; $3A63
        CLC                             ; $3A65
        ADC #$04                        ; $3A66
        STA $14                         ; $3A68
        BCC step_lamp_done              ; $3A6A
        INC $15                         ; $3A6C
step_lamp_done:
        RTS                             ; $3A6E
; Once per logic frame, from frame, and once more at the end of
; enter_room. The word at $4EC4, room*2 is the hook address minus one,
; because RTS adds one. Room 1's hook opens the trap door. Room 5's hook
; slides three energy beams and does not read $7B, so those move on every
; logic frame. hook_frame_5 is the beam code. The lamp counts are in
; rooms.asm.
run_frame_hook:
        LDA $29                         ; $3A6F
        ASL A                           ; $3A71
        TAX                             ; $3A72
        LDA $4EC5,X                     ; $3A73
        PHA                             ; $3A76
        LDA $4EC4,X                     ; $3A77
        PHA                             ; $3A7A
        RTS                             ; $3A7B
; Move ($0A) on four bytes, one lamp record.
next_lamp_record:
        LDA $0A                         ; $3A7C
        CLC                             ; $3A7E
        ADC #$04                        ; $3A7F
        STA $0A                         ; $3A81
        LDA $0B                         ; $3A83
        ADC #$00                        ; $3A85
        STA $0B                         ; $3A87
        RTS                             ; $3A89

; Calls play_sound_8a, which keeps A, then prints strings $13, $13, and $14.
; Open a passage once a room's lamps are taken. A is the row and Y the
; column. play_sound_8a sounds it, then strings $13, $13, and $14 draw
; three rows of the opening, one row lower each.
draw_passage:
        JSR play_sound_8a               ; $3A8A
        STA $6C                         ; $3A8D
        STY $6D                         ; $3A8F
        LDA #$13                        ; $3A91
        JSR print_and_step_row          ; $3A93
        LDA #$13                        ; $3A96
        JSR print_and_step_row          ; $3A98
        LDA #$14                        ; $3A9B
        JMP print_and_step_row          ; $3A9D
; draw_passage, then string $17 one row back up, over the third row.
; Room 6's opening.
draw_passage_17:
        JSR draw_passage                ; $3AA0
        DEC $6C                         ; $3AA3
        LDA #$17                        ; $3AA5
        JMP print_and_step_row          ; $3AA7
; draw_passage, then string $2D one row back up. Room 8's opening.
draw_passage_2d:
        JSR draw_passage                ; $3AAA
        DEC $6C                         ; $3AAD
        LDA #$2D                        ; $3AAF
        JMP print_and_step_row          ; $3AB1
; The other opening: strings $63, $63, and $64, one row lower each, with
; the same sound.
draw_passage_63:
        JSR play_sound_8a               ; $3AB4
        STA $6C                         ; $3AB7
        STY $6D                         ; $3AB9
        LDA #$63                        ; $3ABB
        JSR print_and_step_row          ; $3ABD
        LDA #$63                        ; $3AC0
        JSR print_and_step_row          ; $3AC2
        LDA #$64                        ; $3AC5
        JMP print_and_step_row          ; $3AC7
; Print string A at row $6C, column $6D, then move $6C down one row.
print_and_step_row:
        LDX $6C                         ; $3ACA
        LDY $6D                         ; $3ACC
        JSR print_string                ; $3ACE
        INC $6C                         ; $3AD1
        RTS                             ; $3AD3
; Per-frame hook for room 8. It ends in scroll_surface.
hook_frame_8:
        LDA $31                         ; $3AD4
        ORA $4E00                       ; $3AD6
        BNE hook8_second_passage        ; $3AD9
        LDA $4E99                       ; $3ADB
        BMI hook8_second_passage        ; $3ADE
        DEC $4E99                       ; $3AE0
        LDA #$07                        ; $3AE3
        LDY #$0E                        ; $3AE5
        JSR draw_passage                ; $3AE7
hook8_second_passage:
        LDA $4DF8                       ; $3AEA
        ORA $4DFC                       ; $3AED
        BNE hook8_third_passage         ; $3AF0
        LDA $4E9A                       ; $3AF2
        BMI hook8_third_passage         ; $3AF5
        DEC $4E9A                       ; $3AF7
        LDA $4E04                       ; $3AFA
        BEQ hook8_open_second           ; $3AFD
; Lamp $4E04 is still present. Force the surface down and restart its slot.
        LDA #$01                        ; $3AFF
        STA $65                         ; $3B01
        LDA #$07                        ; $3B03
        STA $4321                       ; $3B05
hook8_open_second:
        LDA #$07                        ; $3B08
        LDY #$19                        ; $3B0A
        JSR draw_passage                ; $3B0C
hook8_third_passage:
        LDA $32                         ; $3B0F
        ORA $4E11                       ; $3B11
        ORA $4E15                       ; $3B14
        BNE hook8_fourth_passage        ; $3B17
        LDA $4E9B                       ; $3B19
        BMI hook8_fourth_passage        ; $3B1C
        DEC $4E9B                       ; $3B1E
        LDA #$02                        ; $3B21
        LDY #$26                        ; $3B23
        JSR draw_passage_2d             ; $3B25
hook8_fourth_passage:
        LDA $4E00                       ; $3B28
        BNE hook8_fifth_passage         ; $3B2B
        LDA $4E97                       ; $3B2D
        BMI hook8_fifth_passage         ; $3B30
        DEC $4E97                       ; $3B32
        LDA #$0A                        ; $3B35
        LDY #$01                        ; $3B37
        JSR draw_passage                ; $3B39
hook8_fifth_passage:
        LDA $31                         ; $3B3C
        ORA $32                         ; $3B3E
        BNE hook8_beam1                 ; $3B40
        LDA $4E98                       ; $3B42
        BMI hook8_beam1                 ; $3B45
        DEC $4E98                       ; $3B47
        LDA #$0A                        ; $3B4A
        LDY #$26                        ; $3B4C
        JSR draw_passage                ; $3B4E
hook8_beam1:
        INC $77                         ; $3B51
        BMI hook8_beam2                 ; $3B53
        LDA $77                         ; $3B55
        CMP #$03                        ; $3B57
        BEQ hook8_beam1_advance         ; $3B59
        CMP #$07                        ; $3B5B
        BEQ hook8_beam1_reload          ; $3B5D
hook8_beam1_draw:
        JSR print_row74                 ; $3B5F
        JMP hook8_beam2                 ; $3B62
hook8_beam1_advance:
        LDX $71                         ; $3B65
        CPX #$0B                        ; $3B67
        BCS hook8_beam1_draw            ; $3B69
        LDA #$06                        ; $3B6B
        JSR print_row74                 ; $3B6D
        INC $71                         ; $3B70
        LDA #$02                        ; $3B72
        STA $77                         ; $3B74
        BNE hook8_beam1_draw            ; $3B76
hook8_beam1_reload:
        LDA #$06                        ; $3B78
        STA $71                         ; $3B7A
        LDA #$DA                        ; $3B7C
        STA $77                         ; $3B7E
hook8_beam2:
        INC $78                         ; $3B80
        BMI hook8_scroll                ; $3B82
        LDA $78                         ; $3B84
        CMP #$03                        ; $3B86
        BEQ hook8_beam2_advance         ; $3B88
        CMP #$07                        ; $3B8A
        BEQ hook8_beam2_reload          ; $3B8C
hook8_beam2_draw:
        JSR print_row75                 ; $3B8E
        JMP hook8_scroll                ; $3B91
hook8_beam2_advance:
        LDX $72                         ; $3B94
        CPX #$20                        ; $3B96
        BCS hook8_beam2_draw            ; $3B98
        LDA #$06                        ; $3B9A
        JSR print_row75                 ; $3B9C
        INC $72                         ; $3B9F
        LDA #$02                        ; $3BA1
        STA $78                         ; $3BA3
        BNE hook8_beam2_draw            ; $3BA5
hook8_beam2_reload:
        LDA #$1B                        ; $3BA7
        STA $72                         ; $3BA9
        LDA #$DA                        ; $3BAB
        STA $78                         ; $3BAD
hook8_scroll:
        JMP scroll_surface              ; $3BAF
; Per-frame hook for room 9. It ends in scroll_surface.
hook_frame_9:
        LDA $4E99                       ; $3BB2
        BMI hook9_first_passage         ; $3BB5
        LDA $4E09                       ; $3BB7
        BNE hook9_first_passage         ; $3BBA
        DEC $4E99                       ; $3BBC
; Lamp $4E09 is gone. Pin the surface down, and the slot at 7, until this
; counter runs out. The slot never wraps while this runs, so it cannot
; reverse on its own.
        LDA #$01                        ; $3BBF
        STA $65                         ; $3BC1
        LDA #$07                        ; $3BC3
        STA $4321                       ; $3BC5
hook9_first_passage:
        LDA $4E0D                       ; $3BC8
        BNE hook9_lamps_clear           ; $3BCB
        LDA $4E97                       ; $3BCD
        BMI hook9_lamps_clear           ; $3BD0
        DEC $4E97                       ; $3BD2
        LDA #$07                        ; $3BD5
        LDY #$17                        ; $3BD7
        JSR draw_passage                ; $3BD9
; Lamp $4E0D has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $3BDC
        STA $65                         ; $3BDE
        LDA #$07                        ; $3BE0
        STA $4321                       ; $3BE2
hook9_lamps_clear:
        LDA $33                         ; $3BE5
        BNE hook9_slider                ; $3BE7
        LDA $4E98                       ; $3BE9
        BMI hook9_slider                ; $3BEC
        DEC $4E98                       ; $3BEE
; Room 9's lamps are clear. Force the surface up and restart its slot.
        LDA #$00                        ; $3BF1
        STA $65                         ; $3BF3
        LDA #$07                        ; $3BF5
        STA $4321                       ; $3BF7
        JSR play_sound_8a               ; $3BFA
        LDA #$18                        ; $3BFD
        LDX #$02                        ; $3BFF
        LDY #$23                        ; $3C01
        JSR print_string                ; $3C03
hook9_slider:
        LDA $4E11                       ; $3C06
        ORA $4E15                       ; $3C09
        BNE hook9_slider_right          ; $3C0C
        LDA $6E                         ; $3C0E
        STA $70                         ; $3C10
        DEC $6E                         ; $3C12
        CMP #$05                        ; $3C14
        BCS hook9_slider_draw           ; $3C16
        LDA #$18                        ; $3C18
        STA $6E                         ; $3C1A
        BNE hook9_slider_draw           ; $3C1C
hook9_slider_right:
        LDA $6E                         ; $3C1E
        STA $70                         ; $3C20
        INC $6E                         ; $3C22
        CMP #$18                        ; $3C24
        BCC hook9_slider_draw           ; $3C26
        LDA #$04                        ; $3C28
        STA $6E                         ; $3C2A
hook9_slider_draw:
        JSR draw_slider                 ; $3C2C
        INC $77                         ; $3C2F
        BMI hook9_beam2                 ; $3C31
        LDA $77                         ; $3C33
        CMP #$03                        ; $3C35
        BEQ hook9_beam1_advance         ; $3C37
        CMP #$07                        ; $3C39
        BEQ hook9_beam1_reload          ; $3C3B
hook9_beam1_draw:
        JSR print_row74_later           ; $3C3D
        JMP hook9_beam2                 ; $3C40
hook9_beam1_advance:
        LDX $71                         ; $3C43
        CPX #$14                        ; $3C45
        BCS hook9_beam1_draw            ; $3C47
        LDA #$06                        ; $3C49
        JSR print_row74_later           ; $3C4B
        INC $71                         ; $3C4E
        LDA #$02                        ; $3C50
        STA $77                         ; $3C52
        BNE hook9_beam1_draw            ; $3C54
hook9_beam1_reload:
        LDA #$10                        ; $3C56
        STA $71                         ; $3C58
        LDA #$C0                        ; $3C5A
        STA $77                         ; $3C5C
hook9_beam2:
        INC $78                         ; $3C5E
        BMI hook9_scroll                ; $3C60
        LDA $78                         ; $3C62
        CMP #$03                        ; $3C64
        BEQ hook9_beam2_advance         ; $3C66
        CMP #$07                        ; $3C68
        BEQ hook9_beam2_reload          ; $3C6A
hook9_beam2_draw:
        JSR print_row75_later           ; $3C6C
        JMP hook9_scroll                ; $3C6F
hook9_beam2_advance:
        LDX $72                         ; $3C72
        CPX #$14                        ; $3C74
        BCS hook9_beam2_draw            ; $3C76
        LDA #$06                        ; $3C78
        JSR print_row75_later           ; $3C7A
        INC $72                         ; $3C7D
        LDA #$02                        ; $3C7F
        STA $78                         ; $3C81
        BNE hook9_beam2_draw            ; $3C83
hook9_beam2_reload:
        LDA #$10                        ; $3C85
        STA $72                         ; $3C87
        LDA #$C0                        ; $3C89
        STA $78                         ; $3C8B
hook9_scroll:
        JMP scroll_surface              ; $3C8D
; Per-frame hook for room 10.
hook_frame_10:
        LDA $4E97                       ; $3C90
        BMI hook10_crumble              ; $3C93
        LDA $4E1E                       ; $3C95
        ORA $4E22                       ; $3C98
        BNE hook10_crumble              ; $3C9B
        DEC $4E97                       ; $3C9D
        LDA #$04                        ; $3CA0
        LDY #$26                        ; $3CA2
        JSR draw_passage_63             ; $3CA4
hook10_crumble:
        NOP                             ; $3CA7
        NOP                             ; $3CA8
        NOP                             ; $3CA9
        NOP                             ; $3CAA
        NOP                             ; $3CAB
        NOP                             ; $3CAC
        NOP                             ; $3CAD
        NOP                             ; $3CAE
        NOP                             ; $3CAF
        NOP                             ; $3CB0
        NOP                             ; $3CB1
        NOP                             ; $3CB2
        NOP                             ; $3CB3
        NOP                             ; $3CB4
        NOP                             ; $3CB5
        NOP                             ; $3CB6
        NOP                             ; $3CB7
        NOP                             ; $3CB8
        NOP                             ; $3CB9
        NOP                             ; $3CBA
        NOP                             ; $3CBB
        NOP                             ; $3CBC
        JMP step_crumble                ; $3CBD
; Per-frame hook for room 11. It ends in scroll_surface. The pattern is
; the block at $4309, written into charset $A800.
hook_frame_11:
        LDA $4E97                       ; $3CC0
        BMI hook11_crumble              ; $3CC3
        LDA $4E33                       ; $3CC5
        BNE hook11_crumble              ; $3CC8
        DEC $4E97                       ; $3CCA
; Lamp $4E33 has been taken. Force the surface up and restart its slot.
        LDA #$00                        ; $3CCD
        STA $65                         ; $3CCF
        LDA #$07                        ; $3CD1
        STA $4321                       ; $3CD3
hook11_crumble:
        JSR step_crumble                ; $3CD6
        JMP scroll_surface              ; $3CD9
; Per-frame hook for room 18.
hook_frame_18:
        LDA $4E97                       ; $3CDC
        BNE hook18_boss                 ; $3CDF
        JMP hook18_after_boss           ; $3CE1
hook18_boss:
        LDA $4E86                       ; $3CE4
        BNE hook18_sparks               ; $3CE7
        STA $4E97                       ; $3CE9
        JSR blank_sparks                ; $3CEC
        LDA $D015                       ; $3CEF  sprite enable
        AND #$1F                        ; $3CF2
        STA $D015                       ; $3CF4  sprite enable
        LDA #$61                        ; $3CF7
        LDX #$0B                        ; $3CF9
        LDY #$00                        ; $3CFB
        JSR print_string                ; $3CFD
; 3000 for the wizard. The low byte $B8 is added first, then $0B in the
; middle byte, and check_life_mark runs on each add.
        LDA #$B8                        ; $3D00
        LDX #$02                        ; $3D02
        JSR add_score                   ; $3D04
        LDA #$0B                        ; $3D07
        LDX #$01                        ; $3D09
        JSR add_score                   ; $3D0B
        LDX #$01                        ; $3D0E
        LDA #$00                        ; $3D10
        STA $4E9A                       ; $3D12
        LDA #$50                        ; $3D15
        STA $4E98                       ; $3D17
        JMP hook18_show_band            ; $3D1A
hook18_sparks:
        JSR paint_sparks                ; $3D1D
        LDA $D01E                       ; $3D20  sprite-sprite contacts. Reading clears it
        TAX                             ; $3D23
        AND #$03                        ; $3D24
        BEQ hook18_band_timer           ; $3D26
        TXA                             ; $3D28
        AND #$C0                        ; $3D29
        BEQ hook18_band_timer           ; $3D2B
        LDX #$00                        ; $3D2D
        LDA $BF                         ; $3D2F
        CMP #$19                        ; $3D31
        BEQ hook18_band_timer           ; $3D33
        JSR shock_bruce                 ; $3D35
hook18_band_timer:
        DEC $4E98                       ; $3D38
        BNE hook18_done                 ; $3D3B
        LDA #$08                        ; $3D3D
        STA $4E98                       ; $3D3F
        LDA $9E                         ; $3D42
        LDX #$02                        ; $3D44
hook18_band_loop:
        CMP $4A89,X                     ; $3D46
        BCS hook18_show_band            ; $3D49
        DEX                             ; $3D4B
        BNE hook18_band_loop            ; $3D4C
hook18_show_band:
        STX $4E99                       ; $3D4E
        LDA #$38                        ; $3D51
        CLC                             ; $3D53
        ADC $4E99                       ; $3D54
        LDX #$02                        ; $3D57
        LDY #$10                        ; $3D59
        JSR print_string                ; $3D5B
        LDA $4E9A                       ; $3D5E
        BNE hook18_flash_off            ; $3D61
        INC $4E9A                       ; $3D63
        LDA #$06                        ; $3D66
        JSR flash_row_3                 ; $3D68
        LDA #$06                        ; $3D6B
        JSR flash_row_4                 ; $3D6D
        JMP hook18_done                 ; $3D70
hook18_flash_off:
        DEC $4E9A                       ; $3D73
        LDA #$00                        ; $3D76
        JSR flash_row_3                 ; $3D78
        LDA #$00                        ; $3D7B
        JSR flash_row_4                 ; $3D7D
hook18_done:
        RTS                             ; $3D80
; Room 18. String $3B plus A plus $4E99 on row 3 at column $12. $4E99 is
; the band of the room Bruce's xpos is in, from the marks at $4A89, and A
; is 0 or 6, so the strings alternate every eight frames.
flash_row_3:
        CLC                             ; $3D81
        ADC #$3B                        ; $3D82
        ADC $4E99                       ; $3D84
        LDX #$03                        ; $3D87
        LDY #$12                        ; $3D89
        JMP print_string                ; $3D8B
; The same for row 4, from string $3E.
flash_row_4:
        CLC                             ; $3D8E
        ADC #$3E                        ; $3D8F
        ADC $4E99                       ; $3D91
        LDX #$04                        ; $3D94
        LDY #$12                        ; $3D96
        JMP print_string                ; $3D98
hook18_defeated:
        LDA #$00                        ; $3D9B
        LDA #$5E                        ; $3D9D
        LDX #$0B                        ; $3D9F
        LDY #$25                        ; $3DA1
        JSR print_string                ; $3DA3
        LDA #$5F                        ; $3DA6
        LDX #$0C                        ; $3DA8
        LDY #$26                        ; $3DAA
        JMP print_string                ; $3DAC
hook18_after_boss:
        LDA $4E98                       ; $3DAF
        BEQ hook18_defeated             ; $3DB2
        TAX                             ; $3DB4
        JSR noise_byte                  ; $3DB5
        AND #$0F                        ; $3DB8
        ORA #$80                        ; $3DBA
        CPX #$01                        ; $3DBC
        BNE hook18_flash_ink            ; $3DBE
        LDA #$00                        ; $3DC0
        BEQ hook18_store_ink            ; $3DC2
hook18_flash_ink:
        JSR noise_byte                  ; $3DC4
        AND #$07                        ; $3DC7
hook18_store_ink:
        ORA #$F8                        ; $3DC9
        LDX #$11                        ; $3DCB
hook18_ink_loop:
        STA $D8D3,X                     ; $3DCD  color RAM, row 5 column 11, plus X
        STA $D8FB,X                     ; $3DD0  color RAM, row 6 column 11, plus X
        STA $D923,X                     ; $3DD3  color RAM, row 7 column 11, plus X
        STA $D94B,X                     ; $3DD6  color RAM, row 8 column 11, plus X
        CPX #$0C                        ; $3DD9
        BCS hook18_ink_next             ; $3DDB
        STA $D886,X                     ; $3DDD  color RAM, row 3 column 14, plus X
        STA $D8AE,X                     ; $3DE0  color RAM, row 4 column 14, plus X
        STA $D976,X                     ; $3DE3  color RAM, row 9 column 14, plus X
        STA $D99E,X                     ; $3DE6  color RAM, row 10 column 14, plus X
        STA $D9C6,X                     ; $3DE9  color RAM, row 11 column 14, plus X
        STA $D9EE,X                     ; $3DEC  color RAM, row 12 column 14, plus X
hook18_ink_next:
        DEX                             ; $3DEF
        BPL hook18_ink_loop             ; $3DF0
        LDX $4E98                       ; $3DF2
        DEC $4E98                       ; $3DF5
        LDA #$3E                        ; $3DF8
        STA $F2                         ; $3DFA
        CPX #$11                        ; $3DFC
        BCC hook18_flash_sound          ; $3DFE
        JSR noise_byte                  ; $3E00
        CMP #$10                        ; $3E03
        BCS hook18_flash_sound          ; $3E05
        LDA #$3C                        ; $3E07
        STA $F2                         ; $3E09
hook18_flash_sound:
; Effect $8B. $4E98 is still nonzero, so this is a flash frame.
; The zero count prints at hook18_defeated and does not play it.
        LDY #$8B                        ; $3E0B
        JSR play_sound                  ; $3E0D
        LDA $4E9A                       ; $3E10
        EOR #$01                        ; $3E13
        STA $4E9A                       ; $3E15
        LDA #$47                        ; $3E18
        CLC                             ; $3E1A
        ADC $4E9A                       ; $3E1B
        LDX #$03                        ; $3E1E
        LDY #$0C                        ; $3E20
        JSR print_string                ; $3E22
        LDA #$49                        ; $3E25
        CLC                             ; $3E27
        ADC $4E9A                       ; $3E28
        LDX #$03                        ; $3E2B
        LDY #$19                        ; $3E2D
        JSR print_string                ; $3E2F
        LDA #$4B                        ; $3E32
        CLC                             ; $3E34
        ADC $4E9A                       ; $3E35
        LDX #$06                        ; $3E38
        LDY #$0E                        ; $3E3A
        JSR print_string                ; $3E3C
        LDA #$4D                        ; $3E3F
        CLC                             ; $3E41
        ADC $4E9A                       ; $3E42
        LDX #$06                        ; $3E45
        LDY #$17                        ; $3E47
        JMP print_string                ; $3E49
; Per-frame hook for room 12.
hook_frame_12:
        LDA $4E97                       ; $3E4C
        BMI hook12_second_passage       ; $3E4F
        LDA $4E40                       ; $3E51
        BNE hook12_second_passage       ; $3E54
        DEC $4E97                       ; $3E56
        LDA #$0A                        ; $3E59
        LDY #$26                        ; $3E5B
        JSR draw_passage_63             ; $3E5D
hook12_second_passage:
        LDA $4E98                       ; $3E60
        BMI hook12_crumble              ; $3E63
        LDA $36                         ; $3E65
        ORA $4E52                       ; $3E67
        ORA $4E56                       ; $3E6A
        BNE hook12_crumble              ; $3E6D
        DEC $4E98                       ; $3E6F
        LDA #$07                        ; $3E72
        LDY #$26                        ; $3E74
        JSR draw_passage_63             ; $3E76
hook12_crumble:
        JMP step_crumble                ; $3E79
; Per-frame hook for room 13. $014B + player*4 holds three one-shot
; flags. ypos below $64 pays nothing. From $64 to $89 the first flag
; pays, from $8A to $B5 the second, and from $B6 down the third. Each
; pays 500: $01 into score byte 1 and $F4 into byte 2, as two adds, so the
; extra-fall test runs between them. The fourth byte
; of the group is not read. hook_frame_19 writes 1 back into all four
; when the treasure room ends.
hook_frame_13:
        LDA $03                         ; $3E7C
        ASL A                           ; $3E7E
        ASL A                           ; $3E7F
        TAX                             ; $3E80
        LDA $A1                         ; $3E81
        CMP #$64                        ; $3E83
        BCC hook13_sliders_step         ; $3E85
        CMP #$8A                        ; $3E87
        BCS height_lower                ; $3E89
        LDA $014B,X                     ; $3E8B
        BEQ hook13_sliders_step         ; $3E8E
        DEC $014B,X                     ; $3E90
        JMP pay_height                  ; $3E93
; ypos $8A or more. The second flag, unless ypos is $B6 or more.
height_lower:
        INX                             ; $3E96
        CMP #$B6                        ; $3E97
        BCS height_low                  ; $3E99
        LDA $014B,X                     ; $3E9B
        BEQ hook13_sliders_step         ; $3E9E
        DEC $014B,X                     ; $3EA0
        JMP pay_height                  ; $3EA3
; ypos $B6 or more. The third flag.
height_low:
        INX                             ; $3EA6
        LDA $014B,X                     ; $3EA7
        BEQ hook13_sliders_step         ; $3EAA
        DEC $014B,X                     ; $3EAC
; 500 points: $01 into byte 1, then $F4 into byte 2.
pay_height:
        LDA #$01                        ; $3EAF
        TAX                             ; $3EB1
        JSR add_score                   ; $3EB2
        LDA #$F4                        ; $3EB5
        LDX #$02                        ; $3EB7
        JMP add_score                   ; $3EB9
hook13_sliders_step:
        LDA $7B                         ; $3EBC
        BNE hook13_sprites              ; $3EBE
        JSR step_sliders                ; $3EC0
hook13_sprites:
        LDA $D015                       ; $3EC3  sprite enable
        AND #$03                        ; $3EC6
        STA $D015                       ; $3EC8  sprite enable
        RTS                             ; $3ECB
; Per-frame hook for room 14.
hook_frame_14:
        LDA $4E97                       ; $3ECC
        BMI hook14_crumble              ; $3ECF
        LDA $4E4A                       ; $3ED1
        ORA $4E4E                       ; $3ED4
        BNE hook14_crumble              ; $3ED7
        DEC $4E97                       ; $3ED9
        LDA #$04                        ; $3EDC
        LDY #$26                        ; $3EDE
        JSR draw_passage_63             ; $3EE0
hook14_crumble:
        JMP step_crumble                ; $3EE3
; Per-frame hook for room 15.
hook_frame_15:
        LDA $4E97                       ; $3EE6
        BMI hook15_second_door          ; $3EE9
        LDA $4E5B                       ; $3EEB
        BNE hook15_second_door          ; $3EEE
        LDA #$57                        ; $3EF0
        LDX #$03                        ; $3EF2
        LDY #$11                        ; $3EF4
        JSR print_string                ; $3EF6
        LDA #$58                        ; $3EF9
        LDX #$04                        ; $3EFB
        LDY #$11                        ; $3EFD
        JSR print_string                ; $3EFF
        DEC $4E97                       ; $3F02
        JSR play_sound_8a               ; $3F05
hook15_second_door:
        LDA $4E98                       ; $3F08
        BMI hook15_third_door           ; $3F0B
        LDA $4E5F                       ; $3F0D
        ORA $4E63                       ; $3F10
        ORA $4E6B                       ; $3F13
        BNE hook15_third_door           ; $3F16
        LDA #$57                        ; $3F18
        LDX #$03                        ; $3F1A
        LDY #$17                        ; $3F1C
        JSR print_string                ; $3F1E
        LDA #$58                        ; $3F21
        LDX #$04                        ; $3F23
        LDY #$17                        ; $3F25
        JSR print_string                ; $3F27
        DEC $4E98                       ; $3F2A
        JSR play_sound_8a               ; $3F2D
hook15_third_door:
        LDA $4E99                       ; $3F30
        BMI hook15_done                 ; $3F33
        LDA $39                         ; $3F35
        BNE hook15_done                 ; $3F37
        LDA #$59                        ; $3F39
        LDX #$09                        ; $3F3B
        LDY #$25                        ; $3F3D
        JSR print_string                ; $3F3F
        LDA #$5A                        ; $3F42
        LDX #$08                        ; $3F44
        LDY #$25                        ; $3F46
        JSR print_string                ; $3F48
        LDA #$5B                        ; $3F4B
        LDX #$07                        ; $3F4D
        LDY #$25                        ; $3F4F
        JSR print_string                ; $3F51
        JSR play_sound_8a               ; $3F54
        DEC $4E99                       ; $3F57
hook15_done:
        RTS                             ; $3F5A
; Per-frame hook for room 16.
hook_frame_16:
        LDA $4E97                       ; $3F5B
        BMI hook16_crumble              ; $3F5E
        LDA $3A                         ; $3F60
        BNE hook16_crumble              ; $3F62
        DEC $4E97                       ; $3F64
        LDA #$07                        ; $3F67
        LDY #$01                        ; $3F69
        JSR draw_passage_63             ; $3F6B
hook16_crumble:
        JMP step_crumble                ; $3F6E
; Per-frame hook for room 17.
hook_frame_17:
        DEC $4E99                       ; $3F71
        BPL hook17_slider_timer         ; $3F74
        LDA #$0A                        ; $3F76
        STA $4E99                       ; $3F78
        LDA $D880                       ; $3F7B  color RAM, row 3 column 8
        AND #$07                        ; $3F7E
        EOR #$02                        ; $3F80
        ORA #$F8                        ; $3F82
        LDX #$1B                        ; $3F84
hook17_floor_ink:
        STA $D880,X                     ; $3F86  color RAM, row 3 column 8, plus X
        DEX                             ; $3F89
        BPL hook17_floor_ink            ; $3F8A
hook17_slider_timer:
        DEC $4E9A                       ; $3F8C
        BEQ hook17_first_door           ; $3F8F
        BPL hook17_slider               ; $3F91
        LDA #$01                        ; $3F93
        STA $4E9A                       ; $3F95
hook17_slider:
        LDA $6E                         ; $3F98
        STA $70                         ; $3F9A
        INC $6E                         ; $3F9C
        CMP #$1B                        ; $3F9E
        BCC hook17_slider_draw          ; $3FA0
        LDA #$0B                        ; $3FA2
        STA $6E                         ; $3FA4
hook17_slider_draw:
        JSR draw_slider                 ; $3FA6
hook17_first_door:
        LDA $4E97                       ; $3FA9
        BEQ hook17_second_door          ; $3FAC
        LDA $4E7D                       ; $3FAE
        BNE hook17_second_door          ; $3FB1
        DEC $4E97                       ; $3FB3
        LDA #$5D                        ; $3FB6
        LDX #$0A                        ; $3FB8
        LDY #$25                        ; $3FBA
        JSR print_string                ; $3FBC
hook17_second_door:
        LDA $4E98                       ; $3FBF
        BEQ hook17_beams                ; $3FC2
        LDA $4E81                       ; $3FC4
        BNE hook17_beams                ; $3FC7
        DEC $4E98                       ; $3FC9
        LDA #$5C                        ; $3FCC
        LDX #$0A                        ; $3FCE
        LDY #$18                        ; $3FD0
        JSR print_string                ; $3FD2
hook17_beams:
        JSR step_crumble                ; $3FD5
        LDA #$02                        ; $3FD8
        STA $4C                         ; $3FDA
hook17_beam_loop:
        LDX $4C                         ; $3FDC
        INC $77,X                       ; $3FDE
        BMI hook17_beam_next            ; $3FE0
        LDA $77,X                       ; $3FE2
        CMP #$03                        ; $3FE4
        BEQ hook17_beam_advance         ; $3FE6
        CMP #$07                        ; $3FE8
        BEQ hook17_beam_reload          ; $3FEA
hook17_beam_draw:
        CPX #$00                        ; $3FEC
        BNE hook17_beam_draw_75         ; $3FEE
        JSR print_row74                 ; $3FF0
        JMP hook17_beam_next            ; $3FF3
hook17_beam_draw_75:
        CPX #$01                        ; $3FF6
        BNE hook17_beam_draw_76         ; $3FF8
        JSR print_row75                 ; $3FFA
        JMP hook17_beam_next            ; $3FFD
hook17_beam_draw_76:
        JSR print_row76                 ; $4000
        JMP hook17_beam_next            ; $4003
hook17_beam_advance:
        LDY $71,X                       ; $4006
        CPX #$00                        ; $4008
        BNE hook17_beam_limit           ; $400A
        CPY #$23                        ; $400C
        BCS hook17_beam_draw            ; $400E
        BCC hook17_beam_erase           ; $4010
hook17_beam_limit:
        CPY #$25                        ; $4012
        BCS hook17_beam_draw            ; $4014
hook17_beam_erase:
        LDA #$06                        ; $4016
        CPX #$00                        ; $4018
        BNE hook17_beam_erase_75        ; $401A
        JSR print_row74                 ; $401C
        JMP hook17_beam_step            ; $401F
hook17_beam_erase_75:
        CPX #$01                        ; $4022
        BNE hook17_beam_erase_76        ; $4024
        JSR print_row75                 ; $4026
        JMP hook17_beam_step            ; $4029
hook17_beam_erase_76:
        JSR print_row76                 ; $402C
hook17_beam_step:
        LDX $4C                         ; $402F
        INC $71,X                       ; $4031
        LDA #$02                        ; $4033
        STA $77,X                       ; $4035
        BNE hook17_beam_draw            ; $4037
hook17_beam_reload:
        LDA #$CA                        ; $4039
        STA $77,X                       ; $403B
        LDA #$08                        ; $403D
        STA $71,X                       ; $403F
        CPX #$00                        ; $4041
        BNE hook17_beam_next            ; $4043
        LDA #$C8                        ; $4045
        STA $77,X                       ; $4047
hook17_beam_next:
        DEC $4C                         ; $4049
        BPL hook17_beam_loop            ; $404B
        RTS                             ; $404D
; One slider block moved. $6F is its row, $70 the column it left and $6E
; the new column. String $1C clears the old cell and $1B draws the new
; one, with slide_sound.
draw_slider:
        JSR slide_sound                 ; $404E
        LDA #$1C                        ; $4051
        LDX $6F                         ; $4053
        LDY $70                         ; $4055
        JSR print_string                ; $4057
        LDA #$1B                        ; $405A
        LDX $6F                         ; $405C
        LDY $6E                         ; $405E
        JMP print_string                ; $4060
; The same as draw_slider for a slider on row 5 or 10, which uses
; strings $55 and $54.
draw_slider_tall:
        JSR slide_sound                 ; $4063
        LDA #$55                        ; $4066
        LDX $6F                         ; $4068
        LDY $70                         ; $406A
        JSR print_string                ; $406C
        LDA #$54                        ; $406F
        LDX $6F                         ; $4071
        LDY $6E                         ; $4073
        JMP print_string                ; $4075
; Effect $89. Both slide painters call this. One pulse click,
; retriggered every logic frame the slide paints. The beams do not.
slide_sound:
        LDY #$89                        ; $4078
        JMP play_sound                  ; $407A

; State $19 for $10 frames. shock uses it for Bruce. The room 18 spark
; uses it when the sprite hit lands and he is not already in that state.
shock_bruce:
        LDA #$19                        ; $407D
        STA state,X                     ; $407F
        LDA #$10                        ; $4081
        STA timer,X                     ; $4083
        RTS                             ; $4085

; Beam frames for room 5. A is the frame number. $1F selects the string,
; which print_string stores as the screen code minus $20. X is the tile row
; and Y is the column. print_row74 uses row $74 and column $71, print_row75
; uses $75 and $72, and print_row76 uses $76 and $73. The three entries that
; add 7 first are how the upper beam reaches its own strings. The BNE after
; each JMP is not reached from these entries.
print_row74:
        CLC                             ; $4086
        ADC #$1F                        ; $4087
        LDX $74                         ; $4089
        LDY $71                         ; $408B
        JMP print_string                ; $408D
; The middle beam row, $75 and $72.
print_row75:
        CLC                             ; $4090
        ADC #$1F                        ; $4091
        LDX $75                         ; $4093
        LDY $72                         ; $4095
        JMP print_string                ; $4097
; The bottom beam row, $76 and $73.
print_row76:
        CLC                             ; $409A
        ADC #$1F                        ; $409B
        LDX $76                         ; $409D
        LDY $73                         ; $409F
        JMP print_string                ; $40A1
; Strings 7 higher, the upper beam's own frames. The three _later entries
; match the three rows above.
print_row74_later:
        CLC                             ; $40A4
        ADC #$07                        ; $40A5
        JMP print_row74                 ; $40A7
        BNE print_row74                 ; $40AA
; Strings 7 higher, on the middle row.
print_row75_later:
        CLC                             ; $40AC
        ADC #$07                        ; $40AD
        JMP print_row75                 ; $40AF
        BNE print_row75                 ; $40B2
; Strings 7 higher, on the bottom row.
print_row76_later:
        CLC                             ; $40B4
        ADC #$07                        ; $40B5
        JMP print_row76                 ; $40B7
        BNE print_row76                 ; $40BA


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
        DEC $0101                       ; $40BC
        BNE flicker_second_count        ; $40BF
flicker_first:
        JSR noise_byte                  ; $40C1
        AND #$0F                        ; $40C4
        BEQ flicker_first               ; $40C6
        STA $0101                       ; $40C8
        JSR noise_byte                  ; $40CB
        AND #$30                        ; $40CE
        STA $AC9A                       ; $40D0
        STA $AC9B                       ; $40D3
        ORA #$CC                        ; $40D6
        STA $A49A                       ; $40D8
        STA $A49B                       ; $40DB
        AND #$B8                        ; $40DE
        STA $A432                       ; $40E0
        STA $A433                       ; $40E3
flicker_second_count:
        DEC $0102                       ; $40E6
        BNE flicker_third_count         ; $40E9
flicker_second:
        JSR noise_byte                  ; $40EB
        AND #$0F                        ; $40EE
        BEQ flicker_second              ; $40F0
        STA $0102                       ; $40F2
        JSR noise_byte                  ; $40F5
        AND #$30                        ; $40F8
        STA $AD8A                       ; $40FA
        STA $AD8B                       ; $40FD
        ORA #$CC                        ; $4100
        STA $A58A                       ; $4102
        STA $A58B                       ; $4105
flicker_third_count:
        DEC $0103                       ; $4108
        BNE flicker_done                ; $410B
flicker_third:
        JSR noise_byte                  ; $410D
        AND #$0F                        ; $4110
        BEQ flicker_third               ; $4112
        STA $0103                       ; $4114
        JSR noise_byte                  ; $4117
        AND #$0C                        ; $411A
        STA $ACA2                       ; $411C
        STA $ACA3                       ; $411F
        ORA #$33                        ; $4122
        STA $A4A2                       ; $4124
        STA $A4A3                       ; $4127
        AND #$2E                        ; $412A
        STA $A73A                       ; $412C
        STA $A73B                       ; $412F
flicker_done:
        RTS                             ; $4132

; Room 18's two sparks, sprites at $8340 and $8380. X runs 3 down to 0
; and Y steps 0, 3, 6, 9, so each shape gets four bytes. The byte is
; noise AND $4322,X. Those four mask bytes are 18 3C 3C 18, read from
; the end, so the rows come out 18, 3C, 3C, 18. blank_sparks zeros
; the same four offsets.
paint_sparks:
        LDX #$03                        ; $4133
        LDY #$00                        ; $4135
sparks_shape_loop:
        JSR noise_byte                  ; $4137
        AND $4322,X                     ; $413A
        STA $8340,Y                     ; $413D
        JSR noise_byte                  ; $4140
        AND $4322,X                     ; $4143
        STA $8380,Y                     ; $4146
        INY                             ; $4149
        INY                             ; $414A
        INY                             ; $414B
        DEX                             ; $414C
        BPL sparks_shape_loop           ; $414D
        LDA $432E                       ; $414F
        BNE sparks_check_7              ; $4152
        LDA $4330                       ; $4154
        BNE sparks_wait_6               ; $4157
        JSR launch_spark_6              ; $4159
        JMP sparks_fall                 ; $415C
sparks_wait_6:
        DEC $4330                       ; $415F
sparks_check_7:
        LDA $432F                       ; $4162
        BNE sparks_fall                 ; $4165
        LDA $4331                       ; $4167
        BNE sparks_wait_7               ; $416A
        JSR launch_spark_7              ; $416C
        JMP sparks_fall                 ; $416F
sparks_wait_7:
        DEC $4331                       ; $4172
sparks_fall:
        LDX #$01                        ; $4175
sparks_fall_loop:
        LDA $432E,X                     ; $4177
        BEQ sparks_fall_next            ; $417A
        LDA $4334,X                     ; $417C
        CLC                             ; $417F
        ADC #$05                        ; $4180
        STA $4334,X                     ; $4182
        CMP #$E0                        ; $4185
        BCC sparks_fall_next            ; $4187
        LDA #$00                        ; $4189
        STA $432E,X                     ; $418B
        LDA #$02                        ; $418E
        STA $4330,X                     ; $4190
sparks_fall_next:
        DEX                             ; $4193
        BPL sparks_fall_loop            ; $4194
        LDA $432E                       ; $4196
        BEQ sparks_check_second         ; $4199
; This BEQ and the one before it both have offset 0, so neither one
; changes where the code goes.
sparks_check_second:
        LDA $432F                       ; $419B
        BEQ sparks_place                ; $419E
sparks_place:
        LDX #$01                        ; $41A0
sparks_place_loop:
        LDA $432E,X                     ; $41A2
        BEQ sparks_place_next           ; $41A5
        LDY #$01                        ; $41A7
        LDA $4334,X                     ; $41A9
        CMP #$A8                        ; $41AC
        BCS sparks_chase_step           ; $41AE
        INY                             ; $41B0
sparks_chase_step:
        LDA $4332,X                     ; $41B1
        CMP $9E                         ; $41B4
        BCS sparks_chase_left           ; $41B6
        INC $4332,X                     ; $41B8
        BNE sparks_chase_next           ; $41BB
sparks_chase_left:
        BEQ sparks_chase_next           ; $41BD
        DEC $4332,X                     ; $41BF
sparks_chase_next:
        DEY                             ; $41C2
        BPL sparks_chase_step           ; $41C3
        LDA $4332,X                     ; $41C5
        ASL A                           ; $41C8
        PHA                             ; $41C9
        LDA $D010                       ; $41CA  sprite x bit 8
        BCC sparks_clear_x_high         ; $41CD
        ORA $42C5,X                     ; $41CF
        BNE sparks_store_x_high         ; $41D2
sparks_clear_x_high:
        AND $42C7,X                     ; $41D4
sparks_store_x_high:
        STA $D010                       ; $41D7  sprite x bit 8
        TXA                             ; $41DA
        ASL A                           ; $41DB
        TAX                             ; $41DC
        PLA                             ; $41DD
        STA $D00C,X                     ; $41DE  sprite 6 x, plus X
        TXA                             ; $41E1
        LSR A                           ; $41E2
        TAX                             ; $41E3
        LDA $4334,X                     ; $41E4
        CLC                             ; $41E7
        ADC #$1D                        ; $41E8
        PHA                             ; $41EA
        TXA                             ; $41EB
        ASL A                           ; $41EC
        TAX                             ; $41ED
        PLA                             ; $41EE
        STA $D00D,X                     ; $41EF  sprite 6 y, plus X
        TXA                             ; $41F2
        LSR A                           ; $41F3
        TAX                             ; $41F4
        JSR noise_byte                  ; $41F5
        ORA #$F0                        ; $41F8
        STA $D02D,X                     ; $41FA  sprite 6 color, plus X
sparks_place_next:
        DEX                             ; $41FD
        BPL sparks_place_loop           ; $41FE
        RTS                             ; $4200
; Room 18. Sprite 6 is turned on with image $0D, its timer at $432E is
; set, and its bytes at $4332 and $4334 start at $50 and $37, with
; hit_sound.
launch_spark_6:
        LDA #$0D                        ; $4201
        STA $8FFE                       ; $4203
        LDA $D015                       ; $4206  sprite enable
        ORA #$40                        ; $4209
        STA $D015                       ; $420B  sprite enable
        LDA #$01                        ; $420E
        STA $432E                       ; $4210
        LDA #$50                        ; $4213
        STA $4332                       ; $4215
        LDA #$37                        ; $4218
        STA $4334                       ; $421A
        JMP hit_sound                   ; $421D
; The same for sprite 7, image $0E, starting at $5E, $37.
launch_spark_7:
        LDA #$0E                        ; $4220
        STA $8FFF                       ; $4222
        LDA $D015                       ; $4225  sprite enable
        ORA #$80                        ; $4228
        STA $D015                       ; $422A  sprite enable
        LDA #$01                        ; $422D
        STA $432F                       ; $422F
        LDA #$5E                        ; $4232
        STA $4333                       ; $4234
        LDA #$37                        ; $4237
        STA $4335                       ; $4239
        JMP hit_sound                   ; $423C

; Zero the four bytes paint_sparks writes into the two room-18 spark shapes,
; offsets 0, 3, 6, and 9 of $8340 and $8380. between_lives, game_over,
; and the room-18 finish all call this so a spark pixel is not left up.
blank_sparks:
        LDX #$09                        ; $423F
        LDA #$00                        ; $4241
blank_sparks_loop:
        STA $8340,X                     ; $4243
        STA $8380,X                     ; $4246
        DEX                             ; $4249
        DEX                             ; $424A
        DEX                             ; $424B
        BPL blank_sparks_loop           ; $424C
        RTS                             ; $424E

; Effect $8A. A, X, and Y come back unchanged. OpenDoor,
; OpenLateDoor, and the room countdown hooks all come here.
play_sound_8a:
        PHA                             ; $424F
        TXA                             ; $4250
        PHA                             ; $4251
        TYA                             ; $4252
        PHA                             ; $4253
        LDY #$8A                        ; $4254
        JSR play_sound                  ; $4256
        PLA                             ; $4259
        TAY                             ; $425A
        PLA                             ; $425B
        TAX                             ; $425C
        PLA                             ; $425D
        RTS                             ; $425E
; Enter hook for room 19, the treasure room. enter_room has already
; stored screen code $20 across $8C00, the solid black bar. Writing 0
; selects glyph 0, which is empty, so $D021 shows through. raster_irq
; holds that at $FC, grey, for this row and for the score row under it.
; $49/$4A become $0458. irq_service counts that pair down, one per
; raster, 1112 rasters.
hook_enter_19:
        LDA #$58                        ; $425F
        STA $49                         ; $4261
        LDA #$04                        ; $4263
        STA $4A                         ; $4265
        LDX #$27                        ; $4267
        LDA #$00                        ; $4269
; 40 bytes, $8C00-$8C27, row 0.
blank_top_row:
        STA $8C00,X                     ; $426B
        DEX                             ; $426E
        BPL blank_top_row               ; $426F
        RTS                             ; $4271
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
        LDA $49                         ; $4272
        ORA $4A                         ; $4274
        BNE treasure_hold               ; $4276
        INC $40                         ; $4278
        LDA $03                         ; $427A
        ASL A                           ; $427C
        ASL A                           ; $427D
        TAX                             ; $427E
        LDY #$03                        ; $427F
        LDA #$01                        ; $4281
; Four bytes at $014B + player*4.
reset_band:
        STA $014B,X                     ; $4283
        INX                             ; $4286
        DEY                             ; $4287
        BPL reset_band                  ; $4288
        JSR copy_room_defaults          ; $428A
        JSR restore_lamps               ; $428D
        JSR rearm_room_bonus            ; $4290
        LDX #$00                        ; $4293
        JMP enter_room_at               ; $4295
; Inks 8 through 15, with the high nibble $F the rest of color RAM uses.
; Eight rows of 29 columns, from $D800+$2AC: character row 17, column 4,
; through column 32, and the seven rows under it. The flames.
treasure_hold:
        JSR noise_byte                  ; $4298
        AND #$07                        ; $429B
        ORA #$F8                        ; $429D
        LDX #$1C                        ; $429F
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
        DEX                             ; $42B9
        BPL flicker_flames              ; $42BA
        LDA #$04                        ; $42BC
        LDX #$00                        ; $42BE
        LDY #$0A                        ; $42C0
        JMP print_string                ; $42C2
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
        INC $04                         ; $4786
        BNE step_ptr_04_done            ; $4788
        INC $05                         ; $478A
step_ptr_04_done:
        RTS                             ; $478C
; Advance ($06) by one. The unpack's source byte.
step_ptr_06:
        INC $06                         ; $478D
        BNE step_ptr_06_done            ; $478F
        INC $07                         ; $4791
step_ptr_06_done:
        RTS                             ; $4793
; Advance ($08) by one. The unpack's lower screen cell.
step_ptr_08:
        INC $08                         ; $4794
        BNE step_ptr_08_done            ; $4796
        INC $09                         ; $4798
step_ptr_08_done:
        RTS                             ; $479A

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
        PHA                             ; $485B
        DEC $F3                         ; $485C
        BPL unpack_row_done             ; $485E
        LDA #$27                        ; $4860
        STA $F3                         ; $4862
        LDA $04                         ; $4864
        CLC                             ; $4866
        ADC #$28                        ; $4867
        STA $04                         ; $4869
        BCC unpack_row_color            ; $486B
        INC $05                         ; $486D
unpack_row_color:
        LDA $08                         ; $486F
        CLC                             ; $4871
        ADC #$28                        ; $4872
        STA $08                         ; $4874
        BCC unpack_row_upper            ; $4876
        INC $09                         ; $4878
unpack_row_upper:
        LDA $10                         ; $487A
        CLC                             ; $487C
        ADC #$28                        ; $487D
        STA $10                         ; $487F
        BCC unpack_row_lower            ; $4881
        INC $11                         ; $4883
unpack_row_lower:
        LDA $12                         ; $4885
        CLC                             ; $4887
        ADC #$28                        ; $4888
        STA $12                         ; $488A
        BCC unpack_row_done             ; $488C
        INC $13                         ; $488E
unpack_row_done:
        PLA                             ; $4890
        RTS                             ; $4891

; Double the packed glyphs. Four source bytes are written twice through ($06),
; and the next four twice through ($08). The caller sets $F3 to the number of
; groups minus one. Startup at $047A calls this four times. The setups and
; the fact that $9000 is later overwritten are in rooms.asm. A picture row
; occupies two charset bytes because of this, which is why flicker_lamps
; stores its new value into both bytes of the pair.
expand_charset:
        LDY #$00                        ; $4892
        LDX #$03                        ; $4894
expand_first_half:
        LDA ($04),Y                     ; $4896
        STA ($06),Y                     ; $4898
        JSR step_ptr_06                 ; $489A
        STA ($06),Y                     ; $489D
        JSR step_ptr_06                 ; $489F
        JSR step_ptr_04                 ; $48A2
        DEX                             ; $48A5
        BPL expand_first_half           ; $48A6
        LDX #$03                        ; $48A8
expand_second_half:
        LDA ($04),Y                     ; $48AA
        STA ($08),Y                     ; $48AC
        JSR step_ptr_08                 ; $48AE
        STA ($08),Y                     ; $48B1
        JSR step_ptr_08                 ; $48B3
        JSR step_ptr_04                 ; $48B6
        DEX                             ; $48B9
        BPL expand_second_half          ; $48BA
        DEC $F3                         ; $48BC
        BPL expand_charset              ; $48BE
        RTS                             ; $48C0

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
        LDA #$32                        ; $48C1
        STA $D018                       ; $48C3  screen and charset address
        LDA #$FC                        ; $48C6
        STA $D021                       ; $48C8  background color
; The next interrupt is raster_open, at raster $40.
        LDA #$1E                        ; $48CB
        STA $0408                       ; $48CD
        LDA #$49                        ; $48D0
        STA $0409                       ; $48D2
        LDA #$01                        ; $48D5
        STA $D01A                       ; $48D7  VIC interrupt enable
        STA $D019                       ; $48DA  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $48DD  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $48E0
        STA $D011                       ; $48E2  VIC control: yscroll, 25 rows, raster bit 8
        LDA #$40                        ; $48E5
        STA $D012                       ; $48E7  raster line
        LDA $29                         ; $48EA
        ASL A                           ; $48EC
        TAX                             ; $48ED
        LDA $480B,X                     ; $48EE
        STA $0A                         ; $48F1
        LDA $480C,X                     ; $48F3
        STA $0B                         ; $48F6
        LDA $4833,X                     ; $48F8
        STA $0C                         ; $48FB
        LDA $4834,X                     ; $48FD
        STA $0D                         ; $4900
        LDY #$0B                        ; $4902
raster_copy_bands:
        LDA ($0A),Y                     ; $4904
        STA $0153,Y                     ; $4906
        CPY #$04                        ; $4909
        BCS raster_copy_next            ; $490B
        LDA ($0C),Y                     ; $490D
        STA $47F5,Y                     ; $490F
raster_copy_next:
        DEY                             ; $4912
        BPL raster_copy_bands           ; $4913
        JSR irq_service                 ; $4915
        PLA                             ; $4918
        TAY                             ; $4919
        PLA                             ; $491A
        TAX                             ; $491B
        PLA                             ; $491C
        RTI                             ; $491D

; Raster $40, inside the score row. The wait below runs until raster $41, then
; a short delay, still before row 2. $F2 is restored to $D018. In a normal
; room that is $38, charset $A000. The first band is then taken from $0153.
; A split list whose first byte is $FD never reaches raster_split, so this
; first band is the only one on screen. Rooms 4, 5, and 6 are that case:
; background 6, $D022 light blue, $D023 white.
raster_open:
        LDA #$41                        ; $491E
raster_open_wait:
        CMP $D012                       ; $4920  raster line
        BCS raster_open_wait            ; $4923
        LDX #$0A                        ; $4925
raster_open_delay:
        DEX                             ; $4927
        BNE raster_open_delay           ; $4928
        LDA $F2                         ; $492A
        STA $D018                       ; $492C  screen and charset address
        LDA $0153                       ; $492F
        STA $D021                       ; $4932  background color
        LDA $0154                       ; $4935
        STA $D022                       ; $4938  background multicolor 1
        LDA $0155                       ; $493B
        STA $D023                       ; $493E  background multicolor 2
        LDA #$00                        ; $4941
        STA $44                         ; $4943
        LDA #$03                        ; $4945
        STA $F4                         ; $4947
; The splits after this one are raster_split.
        LDA #$82                        ; $4949
        STA $0408                       ; $494B
        LDA #$49                        ; $494E
        STA $0409                       ; $4950

; Arm the next split from $47F5. A value of $FD points the vector back at
; raster_irq instead of raster_split.
raster_arm:
        LDA #$01                        ; $4953
        STA $D01A                       ; $4955  VIC interrupt enable
        STA $D019                       ; $4958  VIC interrupt flags. Writing 1 acknowledges
        LDA $D011                       ; $495B  VIC control: yscroll, 25 rows, raster bit 8
        AND #$7F                        ; $495E
        STA $D011                       ; $4960  VIC control: yscroll, 25 rows, raster bit 8
        LDX $44                         ; $4963
        LDA $47F5,X                     ; $4965
        STA $D012                       ; $4968  raster line
        CMP #$FD                        ; $496B
        BEQ raster_last_split           ; $496D
raster_return:
        PLA                             ; $496F
        TAY                             ; $4970
        PLA                             ; $4971
        TAX                             ; $4972
        PLA                             ; $4973
        RTI                             ; $4974
raster_last_split:
; The split was $FD. Point the vector back at raster_irq.
        LDA #$C1                        ; $4975
        STA $0408                       ; $4977
        LDA #$48                        ; $497A
        STA $0409                       ; $497C
        JMP raster_return               ; $497F

; A color split. Wait until the raster in the list, then store the next three
; bytes as $D021, $D022, and $D023. $F4 starts at 3 and advances by 3, so the
; bytes are band 2, then band 3, then band 4.
raster_split:
        LDX $F4                         ; $4982
        LDY $0153,X                     ; $4984
        LDX $44                         ; $4987
        LDA $47F5,X                     ; $4989
        TAX                             ; $498C
        INX                             ; $498D
        INX                             ; $498E
        TXA                             ; $498F
        INX                             ; $4990
raster_split_wait:
        CPX $D012                       ; $4991  raster line
        BEQ raster_split_colors         ; $4994
        CMP $D012                       ; $4996  raster line
        BNE raster_split_wait           ; $4999
        LDX #$0A                        ; $499B
raster_split_delay:
        DEX                             ; $499D
        BNE raster_split_delay          ; $499E
raster_split_colors:
        STY $D021                       ; $49A0  background color
        LDX $F4                         ; $49A3
        LDA $0154,X                     ; $49A5
        STA $D022                       ; $49A8  background multicolor 1
        LDA $0155,X                     ; $49AB
        STA $D023                       ; $49AE  background multicolor 2
        LDA $F4                         ; $49B1
        CLC                             ; $49B3
        ADC #$03                        ; $49B4
        STA $F4                         ; $49B6
        INC $44                         ; $49B8
        JMP raster_arm                  ; $49BA

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
        AND #$7F                        ; $50DE
        ORA #$10                        ; $50E0
        STA $D011                       ; $50E2  VIC control: yscroll, 25 rows, raster bit 8
        RTS                             ; $50E5

; $50E6  73 bytes: one byte not read, then three 24-byte tables that
; point_scan_row uses for character rows 0-23. $50E7 is each row's low
; byte, $50FF the screen high byte, and $5117 the color RAM high byte.
; Called from boot. Spins until $CF8F and $CFAF are both $B9, then
; builds the sprite pictures from the library pointers at $59BD, $5A8F,
; and $5B61. $5CBF,X is the same byte place_sprites later reads.
build_sprites:
        LDA $CF8F                       ; $512F
        CMP #$B9                        ; $5132
        BNE build_sprites               ; $5134
        EOR $CFAF                       ; $5136
        BNE build_sprites               ; $5139
        LDX #$D1                        ; $513B
build_pose_loop:
        STX $51                         ; $513D
        LDA $1239,X                     ; $513F
        BEQ build_pose_blank            ; $5142
        JSR expand_library              ; $5144
        JMP build_pose_first            ; $5147
build_pose_blank:
        LDY #$5F                        ; $514A
        LDA #$00                        ; $514C
build_pose_clear:
        STA $CAE0,Y                     ; $514E
        DEY                             ; $5151
        BPL build_pose_clear            ; $5152
build_pose_first:
        DEC $51                         ; $5154
        LDX $51                         ; $5156
        JSR expand_library              ; $5158
        LDX $51                         ; $515B
        LDA $1167,X                     ; $515D
        STA $06                         ; $5160
        LDA $1239,X                     ; $5162
        STA $07                         ; $5165
        LDY #$5F                        ; $5167
build_pose_merge:
        LDA ($06),Y                     ; $5169
        ORA $CAE0,Y                     ; $516B
        STA ($06),Y                     ; $516E
        DEY                             ; $5170
        BPL build_pose_merge            ; $5171
        DEX                             ; $5173
        CPX #$FF                        ; $5174
        BEQ build_sprites_done          ; $5176
        JMP build_pose_loop             ; $5178
build_sprites_done:
        RTS                             ; $517B
        RTS                             ; $517C
        RTS                             ; $517D
; One library into a hardware sprite. $1D is the height byte plus one.
; $5CBF zero reads one source byte per row. widen_bits turns four source
; bits into one sprite byte, each set bit the pair $C0, so one byte fills
; the two left columns and the third column is cleared. A nonzero $5CBF
; reads two source bytes per row: the first fills those two columns, and
; the high nibble of the second fills the right column. The pointer is
; bumped once inside the row, and Y once, so the next row starts two source
; bytes on. Rows from there through $20 are cleared.
expand_library:
        LDA $59BD,X                     ; $517E
        STA $04                         ; $5181
        LDA $5A8F,X                     ; $5183
        STA $05                         ; $5186
        LDY $5B61,X                     ; $5188
        INY                             ; $518B
        STY $1D                         ; $518C
        LDA $1239,X                     ; $518E
        STA $07                         ; $5191
        LDA $1167,X                     ; $5193
        STA $06                         ; $5196
        CLC                             ; $5198
        ADC #$20                        ; $5199
        STA $08                         ; $519B
        LDA $07                         ; $519D
        ADC #$00                        ; $519F
        STA $09                         ; $51A1
        LDA $06                         ; $51A3
        CLC                             ; $51A5
        ADC #$40                        ; $51A6
        STA $0A                         ; $51A8
        LDA $07                         ; $51AA
        ADC #$00                        ; $51AC
        STA $0B                         ; $51AE
        LDY #$00                        ; $51B0
        LDA $5CBF,X                     ; $51B2
        BNE expand_wide_row             ; $51B5
expand_narrow_row:
        LDA ($04),Y                     ; $51B7
        STA $1F                         ; $51B9
        JSR widen_bits                  ; $51BB
        STA ($08),Y                     ; $51BE
        JSR widen_bits                  ; $51C0
        STA ($06),Y                     ; $51C3
        LDA #$00                        ; $51C5
        STA ($0A),Y                     ; $51C7
        INY                             ; $51C9
        CPY $1D                         ; $51CA
        BCC expand_narrow_row           ; $51CC
expand_clear_rows:
        STA ($06),Y                     ; $51CE
        STA ($08),Y                     ; $51D0
        STA ($0A),Y                     ; $51D2
        INY                             ; $51D4
        CPY #$20                        ; $51D5
        BCC expand_clear_rows           ; $51D7
        RTS                             ; $51D9
expand_wide_row:
        LDA ($04),Y                     ; $51DA
        STA $1F                         ; $51DC
        JSR widen_bits                  ; $51DE
        STA ($08),Y                     ; $51E1
        JSR widen_bits                  ; $51E3
        STA ($06),Y                     ; $51E6
        JSR step_ptr_04                 ; $51E8
        LDA ($04),Y                     ; $51EB
        LSR A                           ; $51ED
        LSR A                           ; $51EE
        LSR A                           ; $51EF
        LSR A                           ; $51F0
        JSR widen_bits                  ; $51F1
        STA ($0A),Y                     ; $51F4
        INY                             ; $51F6
        CPY $1D                         ; $51F7
        BCC expand_wide_row             ; $51F9
        LDA #$00                        ; $51FB
        BEQ expand_clear_rows           ; $51FD
; Spread the low four bits of $1F into a byte, two bits each, so a
; packed collision nibble covers a multicolor pixel pair. A starts at 0,
; so whatever the caller had in A is lost.
widen_bits:
        LDX #$03                        ; $51FF
        LDA #$00                        ; $5201
widen_loop:
        LSR $1F                         ; $5203
        BCC widen_next                  ; $5205
        ORA #$C0                        ; $5207
widen_next:
        DEX                             ; $5209
        BMI widen_done                  ; $520A
        LSR A                           ; $520C
        LSR A                           ; $520D
        JMP widen_loop                  ; $520E
widen_done:
        RTS                             ; $5211


; For each active actor, place his box over the room and scan it. xpos and ypos are
; converted to a character-cell cursor. scan_row is called once per row of the box.
overlap_actors:
        LDX #$02                        ; $5212  the ninja first
overlap_loop:
        STX $50                         ; $5214  the actor
        LDA active,X                    ; $5216
        AND #$01                        ; $5218  in the room?
        BNE overlap_actor               ; $521A
        JMP overlap_next                ; $521C  no: the next
overlap_actor:
        LDA xpos,X                      ; $521F
        SEC                             ; $5221
        SBC #$0C                        ; $5222  the box's left edge
        STA $E6,X                       ; $5224  kept
        AND #$03                        ; $5226  steps into the cell, two pixels each
        STA $1B                         ; $5228  the sub-cell offset
        LDA ypos,X                      ; $522A
        SEC                             ; $522C
        SBC #$1D                        ; $522D  the box's top
        STA $E9,X                       ; $522F  kept
        AND #$07                        ; $5231  rows into the cell
        STA $1C                         ; $5233  the rows above the figure
        LDA $4F4E,X                     ; $5235  the actor's library
        TAX                             ; $5238
        LDA $1167,X                     ; $5239  its scan picture, low
        STA $52CC                       ; $523C  into mask_copy_loop's operand
        LDA $1239,X                     ; $523F  its scan picture, high
        STA $52CD                       ; $5242
        JSR build_actor_mask            ; $5245  the mask at $CAE0
        LDA $1C                         ; $5248  rows above the figure
        CLC                             ; $524A
        ADC #$15                        ; $524B  and 21 of figure
        STA $4F39                       ; $524D  the last mask row
        SEC                             ; $5250
        SBC #$06                        ; $5251  less 6
        STA $4F38                       ; $5253  the row where the upper body ends
        JSR clear_overlap_tables        ; $5256
        LDX $50                         ; $5259  the actor
        LDA $E6,X                       ; $525B
        LSR A                           ; $525D
        LSR A                           ; $525E
        STA $E6,X                       ; $525F  the cell column
        LDA $E9,X                       ; $5261
        LSR A                           ; $5263
        LSR A                           ; $5264
        LSR A                           ; $5265
        STA $E9,X                       ; $5266  the cell row
        LDY #$00                        ; $5268
        STY $52                         ; $526A  mask row 0
        LDA #$08                        ; $526C
        STA $4F3A                       ; $526E  the first cell row ends at mask row 8
        JSR load_row_cells              ; $5271  its three glyphs
        JSR scan_row                    ; $5274  scan them
        LDX $50                         ; $5277
        INC $E9,X                       ; $5279  the next cell row
        LDA #$10                        ; $527B
        STA $4F3A                       ; $527D  ends at mask row 16
        JSR load_row_cells              ; $5280
        JSR scan_row                    ; $5283
        LDX $50                         ; $5286
        INC $E9,X                       ; $5288  the next cell row
        LDA #$18                        ; $528A
        STA $4F3A                       ; $528C  ends at mask row 24
        JSR load_row_cells              ; $528F
        JSR scan_row                    ; $5292
        LDX $50                         ; $5295
        INC $E9,X                       ; $5297  the next cell row
        LDA #$20                        ; $5299
        STA $4F3A                       ; $529B  ends at mask row 32
        JSR load_row_cells              ; $529E
        JSR scan_row                    ; $52A1
overlap_next:
        LDX $50                         ; $52A4  the actor
        DEX                             ; $52A6  the next one
        BMI overlap_done                ; $52A7  all three done
        JMP overlap_loop                ; $52A9
overlap_done:
        RTS                             ; $52AC
; Build the actor's collision mask at $CAE0: zero rows above, then the
; 96 bytes of the pose's scan picture, then shift the three columns right
; by the actor's sub-cell offset ($1B times two), or left by two for an
; offset of 3. overlap_actors patches the $9060 operand of mask_copy_loop
; with that picture's address.
build_actor_mask:
        LDA #$00                        ; $52AD
        TAY                             ; $52AF  row 0
mask_clear_top:
        CPY $1C                         ; $52B0  rows above the figure?
        BEQ mask_offset_test            ; $52B2  done
        STA $CAE0,Y                     ; $52B4  zero
        INY                             ; $52B7
        BNE mask_clear_top              ; $52B8  always
mask_offset_test:
        LDX $1B                         ; $52BA  the sub-cell offset
        CPX #$03                        ; $52BC  3?
        BNE mask_copy                   ; $52BE  no
        LDX #$1F                        ; $52C0  32 more
mask_clear_extra:
        STA $CAE0,Y                     ; $52C2  so the picture starts one column later
        INY                             ; $52C5
        DEX                             ; $52C6
        BPL mask_clear_extra            ; $52C7
mask_copy:
        LDX #$00                        ; $52C9  from the picture's first byte
mask_copy_loop:
        LDA $9060,X                     ; $52CB  the scan picture. The operand is patched
        STA $CAE0,Y                     ; $52CE
        INY                             ; $52D1
        INX                             ; $52D2
        CPX #$60                        ; $52D3  96 bytes, three columns of 32
        BCC mask_copy_loop              ; $52D5
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
        DEX                             ; $52EC
        BPL mask_shift_right_row        ; $52ED
        DEY                             ; $52EF  the next bit
        BNE mask_shift_right            ; $52F0
mask_done:
        RTS                             ; $52F2
mask_shift_left:
        LDY #$02                        ; $52F3  two bits
mask_shift_left_pass:
        LDX #$1F                        ; $52F5  32 rows
mask_shift_left_row:
        ASL $CB40,X                     ; $52F7  from the fourth column
        ROL $CB20,X                     ; $52FA  into column 2
        ROL $CB00,X                     ; $52FD  into column 1
        ROL $CAE0,X                     ; $5300  into column 0
        DEX                             ; $5303
        BPL mask_shift_left_row         ; $5304
        DEY                             ; $5306
        BNE mask_shift_left_pass        ; $5307
        RTS                             ; $5309
; One character row of the overlap scan. Point at the row, then look up
; the three cells under the actor and turn each glyph number into its
; address in the charset, eight bytes a glyph, for scan_row's operands.
load_row_cells:
        LDX $50                         ; $530A  the actor
        LDA $E9,X                       ; $530C  the cell row
        TAX                             ; $530E
        JSR point_scan_row              ; $530F  ($04) screen and ($12) color RAM
        LDX $50                         ; $5312
        LDY $E6,X                       ; $5314  the cell column
        JSR check_column0               ; $5316  swap column 0's slots if the cell is a ladder
        LDA ($04),Y                     ; $5319  the glyph
        STA $43BC                       ; $531B
        JSR scale_by_eight              ; $531E  times 8, high byte in $43BB
        LDA $43BC                       ; $5321
        SEC                             ; $5324
        SBC $52                         ; $5325  less the mask row, so Y reads glyph rows 0-7
        STA $5381                       ; $5327  scan_row's operand, column 0
        LDA $43BB                       ; $532A
        SBC #$00                        ; $532D  the borrow
        CLC                             ; $532F
        ADC $7C                         ; $5330  the charset page
        STA $5382                       ; $5332  scan_row's operand
        INY                             ; $5335  the next cell
        JSR check_column1               ; $5336  swap column 1's slots if the cell is a ladder
        LDA ($04),Y                     ; $5339  the glyph
        STA $43BC                       ; $533B
        JSR scale_by_eight              ; $533E  times 8
        LDA $43BC                       ; $5341
        SEC                             ; $5344
        SBC $52                         ; $5345  less the mask row
        STA $539B                       ; $5347  scan_row's operand, column 1
        LDA $43BB                       ; $534A
        SBC #$00                        ; $534D  the borrow
        CLC                             ; $534F
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
        STA $43BC                       ; $5363
        JSR scale_by_eight              ; $5366  times 8
        LDA $43BC                       ; $5369
        SEC                             ; $536C
        SBC $52                         ; $536D  less the mask row
        STA $53B5                       ; $536F  scan_row's operand, column 2
        LDA $43BB                       ; $5372
        SBC #$00                        ; $5375  the borrow
        CLC                             ; $5377
        ADC $7C                         ; $5378  the charset page
        STA $53B6                       ; $537A  scan_row's operand
        RTS                             ; $537D

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
        LSR A                           ; $538A
        LSR A                           ; $538B
        LSR A                           ; $538C
        LSR A                           ; $538D  the high nibble
        TAX                             ; $538E
        STA $4EED,X                     ; $538F  mark its slot. Any nonzero value marks
        LDA $4E                         ; $5392  the AND again
        AND #$0F                        ; $5394  the low nibble
        TAX                             ; $5396
        STA $4EED,X                     ; $5397  mark its slot
scan_second_column:
        LDA $A470,Y                     ; $539A  the glyph row
        AND $CB00,Y                     ; $539D  ANDed with the mask's column 1
        BEQ scan_third_column           ; $53A0  nothing under it
        STA $4E                         ; $53A2  kept
        LSR A                           ; $53A4
        LSR A                           ; $53A5
        LSR A                           ; $53A6
        LSR A                           ; $53A7  the high nibble
        TAX                             ; $53A8
        STA $4F04,X                     ; $53A9  mark its slot
        LDA $4E                         ; $53AC  the AND again
        AND #$0F                        ; $53AE  the low nibble
        TAX                             ; $53B0
        STA $4F04,X                     ; $53B1  mark its slot
scan_third_column:
        LDA $A470,Y                     ; $53B4  the glyph row
        AND $CB20,Y                     ; $53B7  ANDed with the mask's column 2
        BEQ scan_row_next               ; $53BA  nothing under it
        STA $4E                         ; $53BC  kept
        LSR A                           ; $53BE
        LSR A                           ; $53BF
        LSR A                           ; $53C0
        LSR A                           ; $53C1  the high nibble
        TAX                             ; $53C2
        STA $4F1B,X                     ; $53C3  mark its slot
        LDA $4E                         ; $53C6  the AND again
        AND #$0F                        ; $53C8  the low nibble
        TAX                             ; $53CA
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
        RTS                             ; $53E3
scan_upper_body:
        LDX #$02                        ; $53E4  three columns
scan_save_swaps:
        LDA $4F32,X                     ; $53E6  the swap state
        STA $4F35,X                     ; $53E9  kept
        DEX                             ; $53EC
        BPL scan_save_swaps             ; $53ED
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
        LDA #$00                        ; $5431
        LDX #$04                        ; $5433  five counters
flags_clear:
        STA $4F3B,X                     ; $5435  $4F3B-$4F3F
        DEX                             ; $5438
        BPL flags_clear                 ; $5439
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
        BEQ flags_prize                 ; $54AD
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
        BEQ flags_ladder                ; $5503
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
        BEQ flags_wall                  ; $5547
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
        BEQ flags_store                 ; $558B
        INC $4F3F                       ; $558D  wall
flags_store:
        LDX $50                         ; $5590  the actor
        LDA #$00                        ; $5592
        STA hit,X                       ; $5594  cleared
        LSR $4F3F                       ; $5596  the wall count
        ROL hit,X                       ; $5599  bit 3, after three more shifts
        LSR $4F3E                       ; $559B  the ladder count
        ROL hit,X                       ; $559E  bit 2
        LSR $4F3D                       ; $55A0  the prize count
        ROL hit,X                       ; $55A3  bit 1
        LSR $4F3C                       ; $55A5  the ground count
        ROL hit,X                       ; $55A8  bit 0
        RTS                             ; $55AA
; Zero the 23-byte nibble tables at $4EED, $4F04, and $4F1B and the three
; column swap flags at $4F32-$4F34.
clear_overlap_tables:
        LDA #$00                        ; $55AB
        LDX #$16                        ; $55AD  23 slots
clear_overlap_loop:
        STA $4EED,X                     ; $55AF  column 0
        STA $4F04,X                     ; $55B2  column 1
        STA $4F1B,X                     ; $55B5  column 2
        DEX                             ; $55B8
        BPL clear_overlap_loop          ; $55B9
        STA $4F32                       ; $55BB  column 0 not swapped
        STA $4F33                       ; $55BE  column 1 not swapped
        STA $4F34                       ; $55C1  column 2 not swapped
        RTS                             ; $55C4
; X is a character row. ($04) is that row of the screen and ($12) the
; same row of color RAM, from the tables at $50E7, $50FF, and $5117. A
; row past 23 reads on into the next table.
point_scan_row:
        LDA $50E7,X                     ; $55C5  screen row, low
        STA $04                         ; $55C8  and color RAM row, low
        STA $12                         ; $55CA  the same low byte
        LDA $50FF,X                     ; $55CC  screen row, high
        STA $05                         ; $55CF
        LDA $5117,X                     ; $55D1  color RAM row, high
        STA $13                         ; $55D4
        RTS                             ; $55D6
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
        RTS                             ; $563C
check_column0_plain:
        LDA $4F32                       ; $563D  swapped?
        BNE check_column0_unswap        ; $5640  yes: swap back
        RTS                             ; $5642
check_column0_unswap:
        DEC $4F32                       ; $5643  not swapped
        JMP swap_column0                ; $5646  swap back
; The same as check_column0 for the second column.
check_column1:
        LDA ($12),Y                     ; $5649
        AND #$07                        ; $564B
        BEQ check_column1_plain         ; $564D
        LDA $4F33                       ; $564F
        BEQ check_column1_swap          ; $5652
        RTS                             ; $5654
check_column1_swap:
        INC $4F33                       ; $5655
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
        LDX $50                         ; $56AC
        RTS                             ; $56AE
check_column1_plain:
        LDA $4F33                       ; $56AF
        BNE check_column1_unswap        ; $56B2
        RTS                             ; $56B4
check_column1_unswap:
        DEC $4F33                       ; $56B5
        JMP swap_column1                ; $56B8
; The same as check_column0 for the third column.
check_column2:
        LDA ($12),Y                     ; $56BB
        AND #$07                        ; $56BD
        BEQ check_column2_plain         ; $56BF
        LDA $4F34                       ; $56C1
        BEQ check_column2_swap          ; $56C4
        RTS                             ; $56C6
check_column2_swap:
        INC $4F34                       ; $56C7
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
        LDX $50                         ; $571E
        RTS                             ; $5720
check_column2_plain:
        LDA $4F34                       ; $5721
        BNE check_column2_unswap        ; $5724
        RTS                             ; $5726
check_column2_unswap:
        DEC $4F34                       ; $5727
        JMP swap_column2                ; $572A

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
        JMP tune_entry_reset            ; $E000
; Options tune. open_room calls this when $1385 is zero.
start_tune:
        JMP tune_entry_start            ; $E003

; Once per raster, from game_over_raster.
service_tune:
        JMP service_tune_body           ; $E006
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
        JMP reset_tune                  ; $E300
; Second entry. load_tune.
tune_entry_load:
        JMP load_tune                   ; $E303
; start_tune lands here.
tune_entry_start:
        JMP start_tune_body             ; $E306

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
        LDA #$00                        ; $E352
        STA $E30C                       ; $E354  not ready, so service_tune returns
        JSR prime_tune                  ; $E357  pointers, image, opening commands
        LDA #$01                        ; $E35A
        STA $E30C                       ; $E35C  ready
        RTS                             ; $E35F
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
        ASL A                           ; $E36B
        ASL A                           ; $E36C
        ASL A                           ; $E36D  times 8
        TAY                             ; $E36E  index into $E8C0
        LDX #$FE                        ; $E36F  X steps 0, 4, 8: the three operands
patch_tune_loop:
        INX                             ; $E371
        INX                             ; $E372  the next fetch's operand
        LDA $E8C0,Y                     ; $E373  stream pointer, low
        STA $E3DF,X                     ; $E376  into the operand
        INY                             ; $E379
        INX                             ; $E37A
        LDA $E8C0,Y                     ; $E37B  stream pointer, high
        STA $E3DF,X                     ; $E37E  into the operand
        INY                             ; $E381
        INX                             ; $E382
        CPX #$0A                        ; $E383  three done?
        BCC patch_tune_loop             ; $E385
        RTS                             ; $E387
; Not reached. LDA $E8C0,Y / RTS, left between the copy and prime_tune.
; The live fetches are absolute LDAs, and their operands are patched.
        .byte $B9, $C0, $E8, $60

; Pointers, then the image at $E2A8 copied onto $E100, then one
; command byte on each of the three voices.
prime_tune:
        JSR patch_tune_ptrs             ; $E38C  point the fetches at the tune
        JSR copy_tune_image             ; $E38F  fresh state, SID cleared
        LDX #$00                        ; $E392  voice 0
prime_tune_voice:
        STX $E12E                       ; $E394  the voice read_tune serves
        LDA #$FF                        ; $E397  pretend the next byte is a command
        STA $E130                       ; $E399
        JSR tune_byte                   ; $E39C  so the opening commands run, up to the first note
        LDX $E12E                       ; $E39F
        INX                             ; $E3A2
        CPX #$03                        ; $E3A3  all three voices?
        BNE prime_tune_voice            ; $E3A5
        RTS                             ; $E3A7
; Clear $E30F and $E2E8, copy the 46 bytes at $E2A8 onto $E100, and take
; the tempo from $E30D into $E12F. prime_tune runs this before it reads
; the first command on each voice.
copy_tune_image:
        LDA #$00                        ; $E3A8
        STA $E30F                       ; $E3AA  filter mode bits off
        STA $E2E8                       ; $E3AD  no voice routed to the filter
        LDX #$2E                        ; $E3B0  46 bytes
copy_tune_loop:
        LDA $E2A7,X                     ; $E3B2  from $E2A8 up
        STA $E0FF,X                     ; $E3B5  onto $E100 up
        DEX                             ; $E3B8
        BNE copy_tune_loop              ; $E3B9
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
        DEX                             ; $E3D6
        BPL clear_tune_sid              ; $E3D7
        RTS                             ; $E3D9
; A = 0. Clears $E30A, $E30E, $E30C, and the transpose, then zeroes
; $D400 through $D417. $E30B is left as it was.
silence_tune:
        LDA #$00                        ; $E3DA
        BEQ clear_tune_state            ; $E3DC  always
; Absolute LDA. patch_tune_ptrs overwrites the operand, and read_tune
; increments it, low byte then high. $E8F6 is what this snapshot still
; held. fetch_1 shows $E98A and fetch_2 shows $EA44. Those are not the
; streams of a tune that had been loaded.
fetch_0:
        LDA $E8F6                       ; $E3DE
        RTS                             ; $E3E1
; Stream 1. read_tune steps the operand at $E3E3/$E3E4.
fetch_1:
        LDA $E98A                       ; $E3E2
        RTS                             ; $E3E5
; Stream 2. read_tune steps the operand at $E3E7/$E3E8.
fetch_2:
        LDA $EA44                       ; $E3E6
        RTS                             ; $E3E9
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
        BNE read_tune_peek_2            ; $E3F9
        INC $E3E8                       ; $E3FB  carry into the high byte
read_tune_peek_2:
        PHA                             ; $E3FE  keep the byte
        JSR fetch_2                     ; $E3FF  peek at the next one
        STA $E130                       ; $E402  for tune_byte
        PLA                             ; $E405  the byte again
        PLP                             ; $E406  and its flags
        RTS                             ; $E407
read_tune_0:
        JSR fetch_0                     ; $E408  voice 0's byte
        PHP                             ; $E40B  keep its flags
        INC $E3DF                       ; $E40C  step the operand
        BNE read_tune_peek_0            ; $E40F
        INC $E3E0                       ; $E411  carry into the high byte
read_tune_peek_0:
        PHA                             ; $E414  keep the byte
        JSR fetch_0                     ; $E415  peek at the next one
        STA $E130                       ; $E418  for tune_byte
        PLA                             ; $E41B  the byte again
        PLP                             ; $E41C  and its flags
        RTS                             ; $E41D
read_tune_1:
        JSR fetch_1                     ; $E41E  voice 1's byte
        PHP                             ; $E421  keep its flags
        INC $E3E3                       ; $E422  step the operand
        BNE read_tune_peek_1            ; $E425
        INC $E3E4                       ; $E427  carry into the high byte
read_tune_peek_1:
        PHA                             ; $E42A  keep the byte
        JSR fetch_1                     ; $E42B  peek at the next one
        STA $E130                       ; $E42E  for tune_byte
        PLA                             ; $E431  the byte again
        PLP                             ; $E432  and its flags
        RTS                             ; $E433
; reset_music lands here, through the jump at $E300. Silence the tune
; player and return.
reset_tune:
        JSR silence_tune                ; $E434
        RTS                             ; $E437

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
        TAX                             ; $E43D
        JMP select_tune                 ; $E43E  load it
advance_tune_mode:
        AND #$02                        ; $E441  sequence?
        BNE advance_sequence            ; $E443  yes
        LDX $E309                       ; $E445  the current tune
        CPX $E86B                       ; $E448  the last one?
        BCC advance_tune_next           ; $E44B  no: the next
        LDX #$FF                        ; $E44D  0 after the INX
        TYA                             ; $E44F
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
        ASL A                           ; $E466
        LSR A                           ; $E467
        LSR A                           ; $E468  the low 6 bits
        STA $E100                       ; $E469  the transpose
        INX                             ; $E46C  the next byte
        JMP sequence_byte               ; $E46D
sequence_tune:
        LSR A                           ; $E470  the tune number again
        INX                             ; $E471  past it
        STX $E86C                       ; $E472  the cursor
        TAX                             ; $E475
        JMP select_tune                 ; $E476  load it
; Y = 1. Bit 0 set means a restarting sequence keeps playing. The
; cursor is reloaded from $E86D and the walk begins.
start_tune_body:
        LDY #$01                        ; $E479  loop the sequence
sequence_restart:
        LDX $E86D                       ; $E47B  the restart index
        STX $E86C                       ; $E47E  the cursor
        TYA                             ; $E481
        AND #$01                        ; $E482  bit 0: loop
        BNE sequence_byte               ; $E484  read the sequence
sequence_silence:
        JMP silence_tune                ; $E486

; $D418 is $E30F OR $E311. $D417 is $E2E8, which this tune leaves at
; 0, so the filter bits do not route a voice. Called when the voice
; named in $E310 starts a note, and $E310 is then cleared.
write_tune_volume:
        LDA $E30F                       ; $E489  filter mode bits
        ORA $E311                       ; $E48C  volume
        STA $D418                       ; $E48F  SID volume and filter mode
        LDA $E2E8                       ; $E492  voice routing
        STA $D417                       ; $E495  SID filter resonance and voice routing
        LDA #$00                        ; $E498
        STA $E310                       ; $E49A  written, so no voice owes it
        RTS                             ; $E49D
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
        RTS                             ; $E4A8
service_tune_running:
        LDX $E30E                       ; $E4A9  a voice ended?
        CPX #$FF                        ; $E4AC
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
        STA $E12F                       ; $E4C6
        DEC $E104                       ; $E4C9  voice 0's count
        BPL tune_voice0_release         ; $E4CC  0 or more: maybe the gate
        LDA $E104                       ; $E4CE
        CMP $E107                       ; $E4D1  reached the end?
        BNE tune_voice1                 ; $E4D4  not yet
        LDA $E10A                       ; $E4D6  reload the count
        STA $E104                       ; $E4D9
        LDA $E10D                       ; $E4DC  and the end
        STA $E107                       ; $E4DF
        LDA $E310                       ; $E4E2
        CMP #$01                        ; $E4E5  voice 0 owes the volume?
        BNE tune_voice0_note            ; $E4E7
        JSR write_tune_volume           ; $E4E9  write $D418 and $D417
tune_voice0_note:
        LDX #$00                        ; $E4EC  voice 0
        JSR play_tune_note              ; $E4EE  its next note and commands
        JMP tune_voice1                 ; $E4F1
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
        LDA $E105                       ; $E508
        CMP $E108                       ; $E50B  reached the end?
        BNE tune_voice2                 ; $E50E  not yet
        LDA $E10B                       ; $E510  reload the count
        STA $E105                       ; $E513
        LDA $E10E                       ; $E516  and the end
        STA $E108                       ; $E519
        LDA $E310                       ; $E51C
        CMP #$02                        ; $E51F  voice 1 owes the volume?
        BNE tune_voice1_note            ; $E521
        JSR write_tune_volume           ; $E523  write $D418 and $D417
tune_voice1_note:
        LDX #$01                        ; $E526  voice 1
        JSR play_tune_note              ; $E528  its next note and commands
        JMP tune_voice2                 ; $E52B
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
        LDA $E106                       ; $E542
        CMP $E109                       ; $E545  reached the end?
        BNE service_tune_return         ; $E548  not yet
        LDA $E10C                       ; $E54A  reload the count
        STA $E106                       ; $E54D
        LDA $E10F                       ; $E550  and the end
        STA $E109                       ; $E553
        LDA $E310                       ; $E556
        CMP #$03                        ; $E559  voice 2 owes the volume?
        BNE tune_voice2_note            ; $E55B
        JSR write_tune_volume           ; $E55D  write $D418 and $D417
tune_voice2_note:
        LDX #$02                        ; $E560  voice 2
        JSR play_tune_note              ; $E562  its next note and commands
        JMP service_tune_return         ; $E565
tune_voice2_release:
        BNE service_tune_return         ; $E568  count not 0: nothing
        LDA $E103                       ; $E56A  hold?
        BNE service_tune_return         ; $E56D  yes: keep the gate
        LDA $E118                       ; $E56F  the waveform
        AND #$FE                        ; $E572  gate off
        STA $D412                       ; $E574  SID voice 3 waveform and gate
service_tune_return:
        RTS                             ; $E577
; X is the voice, 0-2. $E719,X is the SID base: 00, 07, 0E. A zero
; note clears the frequency and does not write the waveform. Any
; other note adds the transpose and reads $E200/$E254. ADSR and the
; waveform are written only when $E101,X is 0.
play_tune_note:
        STX $E12E                       ; $E578  this voice
        JSR read_tune                   ; $E57B  its note
        LDX $E12E                       ; $E57E
        LDY $E719,X                     ; $E581  its SID base
        TAX                             ; $E584
        BNE play_tune_pitch             ; $E585  not 0: a pitch
        STA $D400,Y                     ; $E587  rest: frequency 0
        STA $D401,Y                     ; $E58A  the gate is left as it was
        JMP tune_byte                   ; $E58D  the commands after it
play_tune_pitch:
        CLC                             ; $E590
        ADC $E100                       ; $E591  plus the transpose
        TAX                             ; $E594
        LDA $E254,X                     ; $E595  frequency high
        STA $D401,Y                     ; $E598  SID voice 1 frequency high, plus Y
        LDA $E200,X                     ; $E59B  frequency low
        STA $D400,Y                     ; $E59E  SID voice 1 frequency low, plus Y
        LDX $E12E                       ; $E5A1
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
        BNE tune_command                ; $E5C8
        LDA #$01                        ; $E5CA  ended
        STA $E30B                       ; $E5CC
        LDA #$FF                        ; $E5CF  service_tune moves on
        STA $E30E                       ; $E5D1
        JMP tune_byte_done              ; $E5D4
tune_command:
        TAY                             ; $E5D7  keep the command
        LSR A                           ; $E5D8
        LSR A                           ; $E5D9
        LSR A                           ; $E5DA
        LSR A                           ; $E5DB  high nibble
        AND #$07                        ; $E5DC  0-7, so $Fn is command 7
        TAX                             ; $E5DE
        LDA $E2D6,X                     ; $E5DF  its offset
        STA $E5E7                       ; $E5E2  offset from $E2D6. Do not cache it
        CLC                             ; $E5E5
        BCC tune_cmd_table              ; $E5E6  always, into the table
tune_cmd_table:
        JMP tune_cmd_time               ; $E5E8
        JMP tune_cmd_level              ; $E5EB
        JMP tune_cmd_voice              ; $E5EE
        JMP tune_cmd_patch              ; $E5F1
        JMP tune_cmd_pw                 ; $E5F4
        JMP tune_cmd_filter             ; $E5F7
        JMP tune_cmd_tempo              ; $E5FA
; Command 0, and command 7. Offset $15 lands here with no JMP.
; The low nibble is the duration. $E119,X is the mode. The two
; results reload the note count and the end compare.

tune_cmd_time:
        TYA                             ; $E5FD
        AND #$0F                        ; $E5FE  the length nibble
        LDX $E12E                       ; $E600
        LDY $E119,X                     ; $E603  the voice's gate mode
        JSR tune_duration               ; $E606  X reload, Y end
        TXA                             ; $E609  the reload
        LDX $E12E                       ; $E60A
        STA $E10A,X                     ; $E60D  for the next note
        TYA                             ; $E610  the end
        STA $E10D,X                     ; $E611  for the next note
        JMP tune_byte                   ; $E614

; Command 1. The low nibble is a volume half, stored at $E311.
; $E310 = voice + 1, so this voice's next note writes $D418.
tune_cmd_level:
        TYA                             ; $E617
        AND #$0F                        ; $E618  volume
        STA $E311                       ; $E61A  one byte for all three voices
        LDX $E12E                       ; $E61D
        INX                             ; $E620
        STX $E310                       ; $E621  written with this voice's next note
        JMP tune_byte                   ; $E624
; Command bytes $AC-$AF. Bit 0 is stored in $E2E7. While that
; byte is set, tune_duration adds $10 before indexing $E6F9.
tune_set_pace:
        TYA                             ; $E627
        AND #$01                        ; $E628  the pace bit
        STA $E2E7                       ; $E62A  one byte for all three voices
        JMP tune_byte                   ; $E62D
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
        BEQ tune_store_wave             ; $E638
        TYA                             ; $E63A
        AND #$0F                        ; $E63B  the low nibble
        CMP #$04                        ; $E63D  a waveform?
        BCS tune_mode_or_flag           ; $E63F  no
        TAX                             ; $E641
        LDA $E71C,X                     ; $E642  the waveform, gate set
tune_store_wave:
        LDX $E12E                       ; $E645
        STA $E116,X                     ; $E648  used from the next note
        JMP tune_byte                   ; $E64B
tune_mode_or_flag:
        CMP #$07                        ; $E64E  hold or sync?
        BCS tune_cmd_flag               ; $E650
        AND #$03                        ; $E652  mode 0, 1, or 2
        LDX $E12E                       ; $E654
        STA $E119,X                     ; $E657  the gate mode
        TAY                             ; $E65A
        DEY                             ; $E65B  flags: mode 0 minus, 1 zero, 2 plus
        PHP                             ; $E65C
        LDA $E68B,X                     ; $E65D  this voice's patch base
        TAY                             ; $E660
        PLP                             ; $E661
; DEY's flags select the pair. PLP restores them after Y is the index.
        BMI tune_adsr_mode0             ; $E662
        BEQ tune_adsr_mode1             ; $E664
        LDA $E120,Y                     ; $E666  mode 2: the third pair
        PHA                             ; $E669
        LDA $E121,Y                     ; $E66A
tune_store_adsr:
        STA $E113,X                     ; $E66D  sustain and release
        PLA                             ; $E670
        STA $E110,X                     ; $E671  attack and decay
        JMP tune_byte                   ; $E674
tune_adsr_mode1:
        LDA $E11E,Y                     ; $E677  mode 1: the second pair
        PHA                             ; $E67A
        LDA $E11F,Y                     ; $E67B
        JMP tune_store_adsr             ; $E67E
tune_adsr_mode0:
        LDA $E11C,Y                     ; $E681  mode 0: the first pair
        PHA                             ; $E684
        LDA $E11D,Y                     ; $E685
        JMP tune_store_adsr             ; $E688
; Voice 0, 1, and 2. Base index of that voice's ADSR pairs.
tune_pair_index:
        .byte $00, $06, $0C             ; $E68B
; Command 2 with a low nibble of 7 or more. 7 and 8 store bit 0 in
; $E101,X, the hold-gate flag. 9 and up set or clear waveform bit 2 from
; bit 0, through $E312.
tune_cmd_flag:
        CMP #$09                        ; $E68E  sync?
        BCS tune_sync_bit               ; $E690
        AND #$01                        ; $E692  7 holds, 8 lets go
        LDX $E12E                       ; $E694
        STA $E101,X                     ; $E697  the hold flag
; Every voice command returns to tune_byte through here.
tune_cmd_done:
        JMP tune_byte                   ; $E69A
tune_sync_bit:
        AND #$01                        ; $E69D
        ASL A                           ; $E69F
        ASL A                           ; $E6A0  into bit 2
        STA $E312                       ; $E6A1
        LDX $E12E                       ; $E6A4
        LDA $E116,X                     ; $E6A7  the waveform
        AND #$FB                        ; $E6AA  sync off
        ORA $E312                       ; $E6AC  then as asked
        STA $E116,X                     ; $E6AF
        JMP tune_cmd_done               ; $E6B2

; Back to the caller. The byte was a note, or the voice has ended.
tune_byte_done:
        RTS                             ; $E6B5
; A is the duration nibble. Y is the mode from $E119,X. $E2E7 set
; adds $10 before the index into $E6F9. Mode 0 releases for the last
; eighth, mode 1 for the second half, and mode 2 on the last count.
; X returns the reload and Y the end compare. A count reloaded with R
; and ended at -E lasts R+E ticks, and the gate drops after R of them.
; With R = 0 the count never reads 0, so the gate stays on. Mode 2 falls
; through here: R = length-1, E = 1.
tune_duration:
        LDX $E2E7                       ; $E6B6  pace?
        BEQ tune_duration_mode          ; $E6B9
        CLC                             ; $E6BB
        ADC #$10                        ; $E6BC  the second half of the table
tune_duration_mode:
        TAX                             ; $E6BE
        DEY                             ; $E6BF  mode 1 zero, mode 0 minus
        BEQ tune_duration_half_gate     ; $E6C0
        BMI tune_duration_eighth        ; $E6C2
        LDA $E6F9,X                     ; $E6C4  mode 2: the length
        TAX                             ; $E6C7
        LDY #$FF                        ; $E6C8  end -1
        DEX                             ; $E6CA  reload length-1
        RTS                             ; $E6CB
; Mode 0. The gate is off for the last eighth, at least one count.
tune_duration_eighth:
        LDA $E6F9,X                     ; $E6CC  the length
        LSR A                           ; $E6CF
        LSR A                           ; $E6D0
        LSR A                           ; $E6D1  an eighth of it
        BNE tune_duration_store         ; $E6D2  at least 1
        LDA #$01                        ; $E6D4
tune_duration_store:
        STA $E312                       ; $E6D6  e
        LDA $E6F9,X                     ; $E6D9
        SEC                             ; $E6DC
        SBC $E312                       ; $E6DD  reload length-e
        TAX                             ; $E6E0
        LDA #$00                        ; $E6E1
        SEC                             ; $E6E3
        SBC $E312                       ; $E6E4  end -e
        TAY                             ; $E6E7
        RTS                             ; $E6E8
; Mode 1. The gate is on for the first half.
tune_duration_half_gate:
        LDA $E6F9,X                     ; $E6E9  the length
        LSR A                           ; $E6EC  half of it
        STA $E312                       ; $E6ED
        TAX                             ; $E6F0  reload half
        LDA #$00                        ; $E6F1
        SEC                             ; $E6F3
        SBC $E312                       ; $E6F4  end -half
        TAY                             ; $E6F7
        RTS                             ; $E6F8

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
        TYA                             ; $E720
        AND #$07                        ; $E721  patch number
        ASL A                           ; $E723
        ASL A                           ; $E724
        ASL A                           ; $E725  times 8
        TAY                             ; $E726
        LDX #$00                        ; $E727  six bytes
        LDA $E12E                       ; $E729  which voice
        BEQ patch_voice0                ; $E72C  voice 0
        LSR A                           ; $E72E
        BCS patch_voice1                ; $E72F  voice 1
patch_voice2:
        LDA $E80A,Y                     ; $E731  a patch byte
        STA $E128,X                     ; $E734  voice 2's three pairs
        INY                             ; $E737
        INX                             ; $E738
        CPX #$06                        ; $E739  six bytes?
        BNE patch_voice2                ; $E73B
        JMP tune_cmd_done               ; $E73D
patch_voice0:
        LDA $E80A,Y                     ; $E740  a patch byte
        STA $E11C,X                     ; $E743  voice 0's three pairs
        INY                             ; $E746
        INX                             ; $E747
        CPX #$06                        ; $E748  six bytes?
        BNE patch_voice0                ; $E74A
        JMP tune_cmd_done               ; $E74C
patch_voice1:
        LDA $E80A,Y                     ; $E74F  a patch byte
        STA $E122,X                     ; $E752  voice 1's three pairs
        INY                             ; $E755
        INX                             ; $E756
        CPX #$06                        ; $E757  six bytes?
        BNE patch_voice1                ; $E759
        JMP tune_cmd_done               ; $E75B
; Command 4. The next two stream bytes are this voice's pulse
; low and high, $D402 and $D403 plus the SID base.
tune_cmd_pw:
        JSR read_tune                   ; $E75E  pulse width low
        LDX $E12E                       ; $E761
        LDY $E719,X                     ; $E764  the SID base
        STA $D402,Y                     ; $E767  SID voice 1 pulse width low, plus Y
        JSR read_tune                   ; $E76A  pulse width high
        LDX $E12E                       ; $E76D
        LDY $E719,X                     ; $E770  the SID base
        STA $D403,Y                     ; $E773  SID voice 1 pulse width high, plus Y
        JMP tune_cmd_done               ; $E776
; Command 5. The low 3 bits times 4, plus $40, index $E80A.
; Two bytes go to $D415 and $D416. The next is ORed with one
; stream byte into $E2E8. The fourth is the volume half in $E30F.
tune_cmd_filter:
        TYA                             ; $E779
        AND #$07                        ; $E77A  the setting
        ASL A                           ; $E77C
        ASL A                           ; $E77D  times 4
        CLC                             ; $E77E
        ADC #$40                        ; $E77F  from $E84A
        TAY                             ; $E781
        LDA $E80A,Y                     ; $E782  cutoff low
        STA $D415                       ; $E785  SID filter cutoff low
        INY                             ; $E788
        LDA $E80A,Y                     ; $E789  cutoff high
        STA $D416                       ; $E78C  SID filter cutoff high
        INY                             ; $E78F
        LDA $E80A,Y                     ; $E790  resonance and routing
        PHA                             ; $E793
        INY                             ; $E794
        LDA $E80A,Y                     ; $E795  filter mode bits
        STA $E30F                       ; $E798  for $D418
        LDX $E12E                       ; $E79B
        INX                             ; $E79E
        STX $E310                       ; $E79F  written with this voice's next note
        JSR read_tune                   ; $E7A2  the stream's routing bits
        STA $E312                       ; $E7A5
        PLA                             ; $E7A8
        ORA $E312                       ; $E7A9  with the setting's
        STA $E2E8                       ; $E7AC  for $D417
        JMP tune_cmd_done               ; $E7AF
; Command 6. The next stream byte is the tempo, stored in $E30D
; and in the running count $E12F.
tune_cmd_tempo:
        JSR read_tune                   ; $E7B2  the tempo
        STA $E30D                       ; $E7B5  the reload
        STA $E12F                       ; $E7B8  the count
        JMP tune_cmd_done               ; $E7BB
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
        TAX                             ; $EB0C
        LDA $EBE5,X                     ; $EB0D  script pointer, low
        STA $F6                         ; $EB10
        LDA $EBE6,X                     ; $EB12  script pointer, high
        STA $F7                         ; $EB15
        LDY #$01                        ; $EB17
        STY $EB02                       ; $EB19  delay 1: the first row runs on this call
        STY $EB00                       ; $EB1C  running
        DEY                             ; $EB1F
        STY $D404                       ; $EB20  gate off, before the first row gates it again
        STY $EB01                       ; $EB23  row index 0
voice_1_tick:
        DEC $EB02                       ; $EB26  the delay
        BNE voice_1_done                ; $EB29  still waiting
        LDY $EB01                       ; $EB2B  the row index
        LDA ($F6),Y                     ; $EB2E  the command
        TAX                             ; $EB30
        LDA $EC03,X                     ; $EB31  its offset
        STA $EB39                       ; $EB34  rewrites a byte of the instruction at $EB38
        CLC                             ; $EB37
        BCC voice_1_commands            ; $EB38  always
; Commands 0 through 7. Offsets 00 03 06 09 0C 0F 12 15.
; 0 end. 1 note. 2 note and wave. 3 note, ADSR, wave.
; 4 note, ADSR, pulse, wave. 5 and 6 note, pulse, wave. 7 wave.
voice_1_commands:
        JMP fx_end                      ; $EB3A
        JMP fx_cmd_note                 ; $EB3D
        JMP fx_cmd_note_wave            ; $EB40
        JMP fx_cmd_adsr                 ; $EB43
        JMP fx_cmd_full                 ; $EB46
        JMP fx_cmd_pulse                ; $EB49
        JMP fx_cmd_pulse                ; $EB4C
        JMP fx_cmd_wave                 ; $EB4F
; Delay byte, then the note. $E200,X and $E254,X. Not clipped.
fx_note:
        INY                             ; $EB52
        LDA ($F6),Y                     ; $EB53  the delay
        STA $EB02                       ; $EB55  counted from the next call
        INY                             ; $EB58
        LDA ($F6),Y                     ; $EB59  the note
        TAX                             ; $EB5B
        LDA $E200,X                     ; $EB5C  frequency low
        STA $D400                       ; $EB5F  SID voice 1 frequency low
        LDA $E254,X                     ; $EB62  frequency high
        STA $D401                       ; $EB65  SID voice 1 frequency high
        INY                             ; $EB68  the next field
        RTS                             ; $EB69
; The script byte is an offset into the pairs at $EC11.
fx_adsr:
        LDA ($F6),Y                     ; $EB6A  pair offset
        TAX                             ; $EB6C
        LDA $EC11,X                     ; $EB6D  attack and decay
        STA $D405                       ; $EB70  SID voice 1 attack and decay
        LDA $EC12,X                     ; $EB73  sustain and release
        STA $D406                       ; $EB76  SID voice 1 sustain and release
        INY                             ; $EB79  the next field
        RTS                             ; $EB7A
; Written as read. A gate bit that stays set does not restart the envelope.
; The decay state keeps comparing the counter with the sustain nibble, so
; a lower sustain written while the gate is held continues down.
fx_wave:
        LDA ($F6),Y                     ; $EB7B  the waveform
        STA $D404                       ; $EB7D  SID voice 1 waveform and gate
        INY                             ; $EB80  the next field
        RTS                             ; $EB81
; Zero the frequency and the slot. The waveform, gate included, stays.
fx_end:
        LDA #$00                        ; $EB82
        STA $D400                       ; $EB84  SID voice 1 frequency low
        STA $D401                       ; $EB87  SID voice 1 frequency high
        STA $EB00                       ; $EB8A  slot free
        STA $EB01                       ; $EB8D  row index 0
        RTS                             ; $EB90
; Offset into the pairs at $EC1B. Low byte, then high.
fx_pulse:
        LDA ($F6),Y                     ; $EB91  pair offset
        INY                             ; $EB93  the next field
        TAX                             ; $EB94
        LDA $EC1B,X                     ; $EB95  width low
        STA $D402                       ; $EB98  SID voice 1 pulse width low
        LDA $EC1C,X                     ; $EB9B  width high
        STA $D403                       ; $EB9E  SID voice 1 pulse width high
        RTS                             ; $EBA1
; Command 1.
fx_cmd_note:
        JSR fx_note                     ; $EBA2
        STY $EB01                       ; $EBA5  the next row
        RTS                             ; $EBA8
; Command 2.
fx_cmd_note_wave:
        JSR fx_note                     ; $EBA9
        JSR fx_wave                     ; $EBAC
        STY $EB01                       ; $EBAF  the next row
        RTS                             ; $EBB2
; Command 3.
fx_cmd_adsr:
        JSR fx_note                     ; $EBB3
        JSR fx_adsr                     ; $EBB6
        JSR fx_wave                     ; $EBB9
        STY $EB01                       ; $EBBC  the next row
        RTS                             ; $EBBF
; Command 4.
fx_cmd_full:
        JSR fx_note                     ; $EBC0
        JSR fx_adsr                     ; $EBC3
        JSR fx_pulse                    ; $EBC6
        JSR fx_wave                     ; $EBC9
        STY $EB01                       ; $EBCC  the next row
        RTS                             ; $EBCF
; Commands 5 and 6.
fx_cmd_pulse:
        JSR fx_note                     ; $EBD0
        JSR fx_pulse                    ; $EBD3
        JSR fx_wave                     ; $EBD6
        STY $EB01                       ; $EBD9  the next row
        RTS                             ; $EBDC
; Command 7. The waveform alone.
fx_cmd_wave:
        INY                             ; $EBDD  past the command byte
        JSR fx_wave                     ; $EBDE
        STY $EB01                       ; $EBE1  the next row. The delay was left at 0
        RTS                             ; $EBE4

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
        TAX                             ; $EF7C
        LDA $EBE5,X                     ; $EF7D  script pointer, low
        STA $F8                         ; $EF80
        LDA $EBE6,X                     ; $EF82  script pointer, high
        STA $F9                         ; $EF85
        LDY #$01                        ; $EF87
        STY $EF72                       ; $EF89  delay 1: the first row runs on this call
        STY $EF70                       ; $EF8C  running
        DEY                             ; $EF8F
        STY $D40B                       ; $EF90  gate off, before the first row gates it again
        STY $EF71                       ; $EF93  row index 0
voice_2_tick:
        DEC $EF72                       ; $EF96  the delay
        BNE voice_2_done                ; $EF99  still waiting
        LDY $EF71                       ; $EF9B  the row index
        LDA ($F8),Y                     ; $EF9E  the command
        TAX                             ; $EFA0
        LDA $EC03,X                     ; $EFA1  its offset
        STA $EFA9                       ; $EFA4  rewrites a byte of the instruction at $EFA8
        CLC                             ; $EFA7
voice_2_dispatch:
        BCC voice_2_dispatch            ; $EFA8  always
; Same eight commands as voice_1, in the same order.
        JMP v2_end                      ; $EFAA
        JMP v2_cmd_note                 ; $EFAD
        JMP v2_cmd_note_wave            ; $EFB0
        JMP v2_cmd_adsr                 ; $EFB3
        JMP v2_cmd_full                 ; $EFB6
        JMP v2_cmd_pulse                ; $EFB9
        JMP v2_cmd_pulse                ; $EFBC
        JMP v2_cmd_wave                 ; $EFBF
; fx_note for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_note:
        INY                             ; $EFC2
        LDA ($F8),Y                     ; $EFC3  the delay
        STA $EF72                       ; $EFC5  counted from the next call
        INY                             ; $EFC8
        LDA ($F8),Y                     ; $EFC9  the note
        TAX                             ; $EFCB
        LDA $E200,X                     ; $EFCC  frequency low
        STA $D407                       ; $EFCF  SID voice 2 frequency low
        LDA $E254,X                     ; $EFD2  frequency high
        STA $D408                       ; $EFD5  SID voice 2 frequency high
        INY                             ; $EFD8  the next field
        RTS                             ; $EFD9
; fx_adsr for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_adsr:
        LDA ($F8),Y                     ; $EFDA  pair offset
        TAX                             ; $EFDC
        LDA $EC11,X                     ; $EFDD  attack and decay
        STA $D40C                       ; $EFE0  SID voice 2 attack and decay
        LDA $EC12,X                     ; $EFE3  sustain and release
        STA $D40D                       ; $EFE6  SID voice 2 sustain and release
        INY                             ; $EFE9  the next field
        RTS                             ; $EFEA
; fx_wave for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_wave:
        LDA ($F8),Y                     ; $EFEB  the waveform
        STA $D40B                       ; $EFED  SID voice 2 waveform and gate
        INY                             ; $EFF0  the next field
        RTS                             ; $EFF1
; fx_end for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_end:
        LDA #$00                        ; $EFF2
        STA $D407                       ; $EFF4  SID voice 2 frequency low
        STA $D408                       ; $EFF7  SID voice 2 frequency high
        STA $EF70                       ; $EFFA  slot free
        STA $EF71                       ; $EFFD  row index 0
        RTS                             ; $F000
; fx_pulse for SID voice 2 ($D407), through ($F8) and the slot at $EF70.
v2_pulse:
        LDA ($F8),Y                     ; $F001  pair offset
        INY                             ; $F003  the next field
        TAX                             ; $F004
        LDA $EC1B,X                     ; $F005  width low
        STA $D409                       ; $F008  SID voice 2 pulse width low
        LDA $EC1C,X                     ; $F00B  width high
        STA $D40A                       ; $F00E  SID voice 2 pulse width high
        RTS                             ; $F011
; Command 1 for voice 2.
v2_cmd_note:
        JSR v2_note                     ; $F012
        STY $EF71                       ; $F015  the next row
        RTS                             ; $F018
; Command 2 for voice 2.
v2_cmd_note_wave:
        JSR v2_note                     ; $F019
        JSR v2_wave                     ; $F01C
        STY $EF71                       ; $F01F  the next row
        RTS                             ; $F022
; Command 3 for voice 2.
v2_cmd_adsr:
        JSR v2_note                     ; $F023
        JSR v2_adsr                     ; $F026
        JSR v2_wave                     ; $F029
        STY $EF71                       ; $F02C  the next row
        RTS                             ; $F02F
; Command 4 for voice 2.
v2_cmd_full:
        JSR v2_note                     ; $F030
        JSR v2_adsr                     ; $F033
        JSR v2_pulse                    ; $F036
        JSR v2_wave                     ; $F039
        STY $EF71                       ; $F03C  the next row
        RTS                             ; $F03F
; Commands 5 and 6 for voice 2.
v2_cmd_pulse:
        JSR v2_note                     ; $F040
        JSR v2_pulse                    ; $F043
        JSR v2_wave                     ; $F046
        STY $EF71                       ; $F049  the next row
        RTS                             ; $F04C
; Command 7 for voice 2.
v2_cmd_wave:
        INY                             ; $F04D  past the command byte
        JSR v2_wave                     ; $F04E
        STY $EF71                       ; $F051  the next row. The delay was left at 0
        RTS                             ; $F054

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
        TAX                             ; $F07C
        LDA $EBE5,X                     ; $F07D  script pointer, low
        STA $FA                         ; $F080
        LDA $EBE6,X                     ; $F082  script pointer, high
        STA $FB                         ; $F085
        LDY #$01                        ; $F087
        STY $F072                       ; $F089  delay 1: the first row runs on this call
        STY $F070                       ; $F08C  running
        DEY                             ; $F08F
        STY $D412                       ; $F090  gate off, before the first row gates it again
        STY $F071                       ; $F093  row index 0
voice_3_tick:
        DEC $F072                       ; $F096  the delay
        BNE voice_3_done                ; $F099  still waiting
        LDY $F071                       ; $F09B  the row index
        LDA ($FA),Y                     ; $F09E  the command
        TAX                             ; $F0A0
        LDA $EC03,X                     ; $F0A1  its offset
        STA $F0A9                       ; $F0A4  rewrites a byte of the instruction at $F0A8
        CLC                             ; $F0A7
voice_3_dispatch:
        BCC voice_3_dispatch            ; $F0A8  always
; Same eight commands as voice_1, in the same order.
        JMP v3_end                      ; $F0AA
        JMP v3_cmd_note                 ; $F0AD
        JMP v3_cmd_note_wave            ; $F0B0
        JMP v3_cmd_adsr                 ; $F0B3
        JMP v3_cmd_full                 ; $F0B6
        JMP v3_cmd_pulse                ; $F0B9
        JMP v3_cmd_pulse                ; $F0BC
        JMP v3_cmd_wave                 ; $F0BF
; fx_note for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_note:
        INY                             ; $F0C2
        LDA ($FA),Y                     ; $F0C3  the delay
        STA $F072                       ; $F0C5  counted from the next call
        INY                             ; $F0C8
        LDA ($FA),Y                     ; $F0C9  the note
        TAX                             ; $F0CB
        LDA $E200,X                     ; $F0CC  frequency low
        STA $D40E                       ; $F0CF  SID voice 3 frequency low
        LDA $E254,X                     ; $F0D2  frequency high
        STA $D40F                       ; $F0D5  SID voice 3 frequency high
        INY                             ; $F0D8  the next field
        RTS                             ; $F0D9
; fx_adsr for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_adsr:
        LDA ($FA),Y                     ; $F0DA  pair offset
        TAX                             ; $F0DC
        LDA $EC11,X                     ; $F0DD  attack and decay
        STA $D413                       ; $F0E0  SID voice 3 attack and decay
        LDA $EC12,X                     ; $F0E3  sustain and release
        STA $D414                       ; $F0E6  SID voice 3 sustain and release
        INY                             ; $F0E9  the next field
        RTS                             ; $F0EA
; fx_wave for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_wave:
        LDA ($FA),Y                     ; $F0EB  the waveform
        STA $D412                       ; $F0ED  SID voice 3 waveform and gate
        INY                             ; $F0F0  the next field
        RTS                             ; $F0F1
; fx_end for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_end:
        LDA #$00                        ; $F0F2
        STA $D40E                       ; $F0F4  SID voice 3 frequency low
        STA $D40F                       ; $F0F7  SID voice 3 frequency high
        STA $F070                       ; $F0FA  slot free
        STA $F071                       ; $F0FD  row index 0
        RTS                             ; $F100
; fx_pulse for SID voice 3 ($D40E), through ($FA) and the slot at $F070.
v3_pulse:
        LDA ($FA),Y                     ; $F101  pair offset
        INY                             ; $F103  the next field
        TAX                             ; $F104
        LDA $EC1B,X                     ; $F105  width low
        STA $D410                       ; $F108  SID voice 3 pulse width low
        LDA $EC1C,X                     ; $F10B  width high
        STA $D411                       ; $F10E  SID voice 3 pulse width high
        RTS                             ; $F111
; Command 1 for voice 3.
v3_cmd_note:
        JSR v3_note                     ; $F112
        STY $F071                       ; $F115  the next row
        RTS                             ; $F118
; Command 2 for voice 3.
v3_cmd_note_wave:
        JSR v3_note                     ; $F119
        JSR v3_wave                     ; $F11C
        STY $F071                       ; $F11F  the next row
        RTS                             ; $F122
; Command 3 for voice 3.
v3_cmd_adsr:
        JSR v3_note                     ; $F123
        JSR v3_adsr                     ; $F126
        JSR v3_wave                     ; $F129
        STY $F071                       ; $F12C  the next row
        RTS                             ; $F12F
; Command 4 for voice 3.
v3_cmd_full:
        JSR v3_note                     ; $F130
        JSR v3_adsr                     ; $F133
        JSR v3_pulse                    ; $F136
        JSR v3_wave                     ; $F139
        STY $F071                       ; $F13C  the next row
        RTS                             ; $F13F
; Commands 5 and 6 for voice 3.
v3_cmd_pulse:
        JSR v3_note                     ; $F140
        JSR v3_pulse                    ; $F143
        JSR v3_wave                     ; $F146
        STY $F071                       ; $F149  the next row
        RTS                             ; $F14C
; Command 7 for voice 3.
v3_cmd_wave:
        INY                             ; $F14D  past the command byte
        JSR v3_wave                     ; $F14E
        STY $F071                       ; $F151  the next row. The delay was left at 0
        RTS                             ; $F154

