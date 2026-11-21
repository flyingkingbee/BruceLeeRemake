"""Debug logger for the original game in VICE, for chasing a trace that diverges.

Run it through tools/vice_debug.sh, which starts x64sc with its binary monitor
first. Like tools/vice_trace.py it runs a snapshot one logic frame at a time
and feeds the stick, but it also writes health, score and lives each frame,
and it takes flags that log what the original does inside a frame. The trace
goes to tmp/oracle_vice_<stem>[_flag].txt, the console lines to
tmp/vrun_last.txt.

  bash tools/vice_debug.sh script FRAMES SCRIPT SNAPSHOT [flags]
  bash tools/vice_debug.sh seed FRAMES N [SNAPSHOT] [flags]
  bash tools/vice_debug.sh STICK FRAMES [FIRE] [SNAPSHOT] [flags]
  VICE_ARGS="-eventsnapshotdir DIR/ -eventstartsnapshot start.vsf -eventendsnapshot end.vsf" bash tools/vice_debug.sh capture FRAMES NAME [flags]
  bash tools/vice_debug.sh replay FRAMES DIR NAME [flags]

Capture watches VICE play back an event history recorded from the options
page, and reads the stick and fire instead of setting them. Start the
playback by hand from VICE's Snapshot menu (Start/Stop Playback History):
started with -playback, VICE 3.10 resets after loading start.vsf. The
"T64 snapshot support" message is harmless. Replay plays the history
without VICE's playback, feeding the events at the port reads, but it has
not yet reproduced a recorded game.
It writes tmp/capture_NAME.txt, a script for the port, and the sync trace
tmp/oracle_vice_NAME_sync.txt. Frame 1 is the first frame of the game.

Flags:
  noise           log every noise_byte read as "nb" lines, for tools/noise_cmp.py
  sync            the noise lines plus the $D01E value read_sprite_hits takes
                  each frame ("hr A frame"), and the $98 and $9B Bruce's
                  on_ground reads ("st stick fire frame"), in the trace, to
                  tmp/oracle_vice_<stem>_sync.txt. The port replays it with Sync=
  hit             log the $D01E reads (console)
  mark            log the raster line at each segment of the frame, plus i48
  markend         log the raster line at the end of the frame
  mark7c c7=N     log the death and door path points (lose, inithw, enterat,
                  unpacked) from frame N on
  watchbyte=ADDR  log the byte at ADDR (hex) at the end of every frame
  storewatch=ADDR:FROM:TO  log the PC of every store to ADDR (hex) in those frames
  execwatch=ADDR:FROM:TO   log the stack each time ADDR (hex) runs in those frames
  menustart       from a snapshot on the options page, press the button there
                  once, so the trace is a new game from its first frame
"""
import socket
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / "tmp"
TMP.mkdir(exist_ok=True)
PATH = str(ROOT / "referencematerial" / "emulatorsnapshots" / "room00.vsf")
snap = next((arg for arg in sys.argv[1:] if arg.lower().endswith(".vsf")), None)
if snap:
    PATH = snap
# Seed mode: one new stick and fire per logic frame, same sequence as the port.
# The body reads the stick the previous wait stored, so the entry rasters get
# input 0 and the waits inside frame N store input N.
seed_mode = len(sys.argv) > 1 and sys.argv[1] == "seed"
# Script mode: the same stick file the port's Script= reads. Frame 1 uses
# line 1, and the entry rasters get that line too.
script_mode = len(sys.argv) > 1 and sys.argv[1] == "script"
# Capture mode: VICE plays back an event history (tools/vice_debug.sh with
# VICE_ARGS naming it), and the logger reads the stick and fire the
# interrupt sees instead of setting them. It writes them as a script, plus
# the sync trace for the port.
capture_mode = len(sys.argv) > 1 and sys.argv[1] == "capture"
# Replay mode: VICE's own event playback can fail to load its start
# snapshot, so the logger plays the history itself. It loads DIR/start.vsf,
# reads the joystick events from DIR/end.vsf, and feeds the value due at the
# current CPU clock to the game's port reads, as script mode feeds a script:
# the options page's button ($08F8), wait_button_up ($0951), the pause
# test ($1A1E), and the interrupt's stick and fire ($16AC, $16CD). The monitor's joyport command
# is accepted by VICE 3.10 but does not reach $DC00/$DC01.
replay_mode = len(sys.argv) > 1 and sys.argv[1] == "replay"
replay_events = []
replay_end = 1 << 62
replay_columns = []


def vsf_modules(path):
    data = Path(path).read_bytes()
    i = data.find(b"VICE Snapshot File\x1a") + 19 + 2 + 16
    if data[i:i + 13] == b"VICE Version\x1a":
        i += 13 + 4 + 4
    mods = {}
    while i + 22 <= len(data):
        name = data[i:i + 16].split(b"\0")[0].decode("latin1")
        size = struct.unpack_from("<I", data, i + 18)[0]
        if size < 22 or i + size > len(data):
            break
        mods[name] = data[i + 22:i + size]
        i += size
    return mods


if replay_mode:
    replay_dir = Path(sys.argv[3])
    start_clock = struct.unpack_from("<Q", vsf_modules(replay_dir / "start.vsf")["MAINCPU"], 0)[0]
    ev = vsf_modules(replay_dir / "end.vsf")["EVENT"]
    raw = []
    i = 0
    while i + 16 <= len(ev):
        kind, clock, size = struct.unpack_from("<IQI", ev, i)
        body = ev[i + 16:i + 16 + size]
        i += 16 + size
        # Type 3 is the joystick: one 16-bit value per port, bits 0-4 are
        # up, down, left, right, and fire. Type 0 at the end closes it.
        if kind == 3:
            raw.append((clock - start_clock, [struct.unpack_from("<H", body, k)[0] for k in range(0, len(body) - 1, 2)]))
        elif kind == 0 and clock:
            replay_end = clock - start_clock
    # Column N is the monitor's joystick port N: 0 is port 1, 1 is port 2.
    replay_columns = sorted({k for _, vals in raw for k, v in enumerate(vals) if v})
    replay_events = [(clock, tuple(vals[k] if k < len(vals) else 0 for k in replay_columns)) for clock, vals in raw]
    print("replay", len(replay_events), "joystick events, ports", replay_columns, "length", replay_end, "cycles")
    capture_mode = True
    PATH = str(replay_dir / "start.vsf")
# On a C64 a joystick pulls its port's lines low under every read, so the
# keyboard scan sees it too: port 1 in $DC01, port 2 in $DC00. These are the
# instructions just after read_stick's and the scan's port reads, with the
# ports whose pressed bits that read would show.
REPLAY_MASKS = {
    0x13A9: (0, 1), 0x1403: (0, 1), 0x13C0: (1,),
    0x13D6: (0,), 0x13E0: (0,), 0x1445: (0,), 0x146D: (0,),
}
REPLAY_POINTS = (0x08F8, 0x0951, 0x1A1E) + tuple(REPLAY_MASKS)
capture_name = ""
cap_stick = 0x0F
cap_fire = 1
cap_lines = []
script = []
script_i = 0
# Columns 3 and 4 of a script line are the other joystick and its button.
# With $42CA set the interrupt stores them in $99 and $9C for Yamo.
two_sticks = False
p2_stick = 0x0F
p2_held = 0
seed = 1
rng = 1
DIRS = (0x0F, 0x0E, 0x0D, 0x0B, 0x07, 0x0A, 0x06, 0x09, 0x05)


def next_input(state):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    return state, DIRS[(state >> 24) % 9], (state >> 16) & 1


if seed_mode:
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    stick = 0
    fire = 1
    rng = seed & 0xFFFFFFFF
    rng, stick, held = next_input(rng)
    fire_reg = 0 if held else 1
elif script_mode:
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    script_path = next(arg for arg in sys.argv[1:] if arg.lower().endswith(".txt"))
    for line in Path(script_path).read_text().splitlines():
        row = line.split()
        if not row or row[0].startswith("#"):
            continue
        fire_bit = int(row[1]) if len(row) > 1 else 0
        stick2 = int(row[2], 16) & 0x0F if len(row) > 2 else 0x0F
        fire2 = int(row[3]) if len(row) > 3 else 0
        if len(row) > 2:
            two_sticks = True
        script.append((int(row[0], 16) & 0x0F, fire_bit, stick2, fire2))
    if not script:
        raise SystemExit(f"empty script {script_path}")
    stick, held, p2_stick, p2_held = script[0]
    fire = 0 if any(row[1] for row in script) else None
    fire_reg = 0 if held else 1
elif capture_mode:
    frames = int(sys.argv[2])
    capture_name = sys.argv[4] if replay_mode else sys.argv[3]
    stick = 0x0F
    held = 0
    # Set so the fire breakpoint at $16CD is placed. Capture only reads it.
    fire = 1
    fire_reg = 1
else:
    stick = int(sys.argv[1], 16) & 0x0F
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    # $9B is 0 while fire is held. Omit the argument to leave the button alone.
    fire = None
    fire_reg = None
    held = 0
    if len(sys.argv) > 3 and sys.argv[3] not in ("none", "hit", "noise", "lib", "spark") and not sys.argv[3].lower().endswith(".vsf"):
        fire = int(sys.argv[3])
        fire_reg = fire
log_hit = "hit" in sys.argv
log_spark = "spark" in sys.argv
log_noise = "noise" in sys.argv
# sync records what raster timing decides: the noise pointer at every read,
# and the $D01E latch. The port's Sync= option replays those two and nothing else.
log_sync = "sync" in sys.argv or capture_mode
if log_sync:
    log_noise = True
log_lib = "lib" in sys.argv
# ovdump=N: on logic frame N, dump Bruce's overlap inputs at each scan_row
# call and the nibble slots after overlap_actors returns.
ovdump = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("ovdump=")), None)
NL = chr(10)
watch_byte = next((int(a.split("=")[1], 16) for a in sys.argv if a.startswith("watchbyte=")), None)
mark7c = "mark7c" in sys.argv
# markscan: raster when scan_specials reaches Bruce ($2E5B with X=0), with $48.
markscan = "markscan" in sys.argv
# marksound: raster and $48 at every play_sound call ($2509), Y is the effect.
marksound = "marksound" in sys.argv
# markend: raster and $48 when the frame's work reaches check_bruce_down ($1C2F).
markend = "markend" in sys.argv
# storewatch=ADDR:FROM:TO logs the PC of every store to ADDR on frames FROM..TO.
sw = next((a.split("=")[1] for a in sys.argv if a.startswith("storewatch=")), None)
sw_addr, sw_from, sw_to = (int(sw.split(":")[0], 16), int(sw.split(":")[1]), int(sw.split(":")[2])) if sw else (None, 0, -1)
c_points = {0x1818: "lose", 0x1886: "inithw", 0x3217: "enterat", 0x0B3B: "unpacked", 0x15EC: "irq7c", 0x1C0D: "pre_overlap", 0x09BC: "enter_room", 0x0AAD: "storeF2", 0x1BC2: "frame", 0x2FC5: "sei", 0x2FD2: "cli", 0x2E5B: "scan"}
c7_from = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("c7=")), 19)
ov_points = {0x5274: 0, 0x5283: 1, 0x5292: 2, 0x52A1: 3, 0x1C10: 9}
# Stop at on_ground's LDA $98,X and record the stick and the raster, then
# continue. The frame still ends at $1BC2. A separate log so the clean
# capture stays put.
probe = "probe" in sys.argv
# Y at the sprite copy's return, the caption, and the lamp reload.
log_y = "yreg" in sys.argv
y_points = {
    0x26D6: "copy",
    0x1C2F: "afterblit",
    0x1A96: "caption",
    0x1B29: "key",
    0x40BC: "flicker",
}
# Raster at the calls that sit before on_ground's stick read.
mark = "mark" in sys.argv
marks = {
    0x1BEE: "lamps",
    0x1C0A: "hook",
    0x1C0D: "overlap",
    0x1C10: "scan",
    0x1C26: "top",
    0x1C29: "step",
    0x1C68: "hold",
    0x1DD0: "read",
}
suffix = "_fire" if fire == 0 else ""
if log_lib:
    suffix += "_lib"
if seed_mode:
    out_path = str(TMP / f"oracle_vice_room00_seed{seed}.txt")
elif script_mode:
    stem = Path(script_path).stem
    out_path = str(TMP / f"oracle_vice_{stem}.txt")
elif capture_mode:
    out_path = str(TMP / f"oracle_vice_{capture_name}.txt")
elif snap:
    stem = snap.replace("\\", "/").split("/")[-1]
    if stem.lower().endswith(".vsf"):
        stem = stem[:-4]
    stem = stem.replace(" ", "_")
    out_path = str(TMP / f"oracle_vice_{stem}_{stick:02X}{suffix}.txt")
else:
    out_path = str(TMP / f"oracle_vice_{stick:02X}{suffix}.txt")
if probe:
    out_path = out_path[:-4] + "_probe.txt"
if log_noise:
    out_path = out_path[:-4] + ("_sync.txt" if log_sync else "_noise.txt")
if log_y:
    out_path = out_path[:-4] + "_yreg.txt"
if log_hit:
    out_path = out_path[:-4] + "_hit.txt"
time_points = (0x1C29, 0x25E2)


def connect():
    last = None
    for _ in range(80):
        try:
            s = socket.create_connection(("127.0.0.1", 6510), 2)
            s.settimeout(8)
            return s
        except OSError as exc:
            last = exc
            time.sleep(0.25)
    raise SystemExit(f"no monitor: {last}")


def packet(req_id, cmd, body=b""):
    return bytes([0x02, 0x02]) + struct.pack("<IIB", len(body), req_id, cmd) + body


def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise SystemExit("socket closed")
        buf += chunk
    return buf


def recv_response(s):
    head = recv_exact(s, 12)
    if head[0] != 0x02:
        raise SystemExit(f"bad stx {head[:12].hex()}")
    length, = struct.unpack_from("<I", head, 2)
    body = recv_exact(s, length) if length else b""
    req, = struct.unpack_from("<I", head, 8)
    return head[6], head[7], req, body


def regs(body):
    if len(body) < 2:
        return {}
    count, = struct.unpack_from("<H", body, 0)
    names = {0: "A", 1: "X", 2: "Y", 3: "PC", 4: "SP", 5: "FL"}
    out = {}
    i = 2
    for _ in range(count):
        if i >= len(body):
            break
        size = body[i]
        item = body[i + 1:i + 1 + size]
        i += 1 + size
        if len(item) >= 3:
            val, = struct.unpack_from("<H", item, 1)
            out[names.get(item[0], str(item[0]))] = val
    return out


s = connect()
nxt = 1


def send(cmd, body=b""):
    global nxt
    nxt += 1
    s.sendall(packet(nxt, cmd, body))
    return nxt


def pull_until(want, limit=16):
    got = []
    for _ in range(limit):
        item = recv_response(s)
        got.append(item)
        if item[2] == want:
            return got
    raise SystemExit(f"missing {want}")


cur_frame = [0]
sw_log = []


# Replay: the CPU clock is kept from the raster position at every stop. PAL
# is 312 lines of 63 cycles, and the stops come at least once a frame. The
# joystick in VICE is set from the event list as the clock passes each event.
PAL_FRAME = 312 * 63
replay_clock = [0]
replay_pos = [None]
replay_set = [None]
replay_ended = [None]


# CIA1 timer A runs throughout, with the kernal's PAL latch $4025, so it
# repeats every 16422 cycles even while the game masks interrupts. Once per
# logic frame its count puts back any whole video frames that passed
# between two stops, as long as the gap was under about 7.8 seconds, the
# point where the raster and the timer line up again.
TIMER_PERIOD = 0x4025 + 1
replay_t0 = [None]
replay_pc = [None]
replay_fixes = [0]


def replay_timer():
    t = read_bytes(0xDC04, 0xDC05)
    return t[0] | (t[1] << 8) if len(t) >= 2 else None


def replay_correct():
    observed = replay_timer()
    if observed is None or replay_t0[0] is None:
        return
    for k in range(0, 400):
        # The reload cycle can show the latch one cycle longer.
        expected = (replay_t0[0] - (replay_clock[0] + k * PAL_FRAME)) % TIMER_PERIOD
        if min((expected - observed) % TIMER_PERIOD, (observed - expected) % TIMER_PERIOD) <= 2:
            if k:
                replay_fixes[0] += 1
                pass
            replay_clock[0] += k * PAL_FRAME
            return
    print("replay frame", cur_frame[0], "pc", hex(replay_pc[0] or 0), "timer", observed, "t0", replay_t0[0],
          "clock", replay_clock[0], "matches no frame count")


def replay_tick(got):
    lin = got.get("53")
    cyc = got.get("54")
    if lin is None or cyc is None:
        return
    pos = lin * 63 + cyc
    replay_pc[0] = got.get("PC")
    if replay_pos[0] is not None:
        replay_clock[0] += (pos - replay_pos[0]) % PAL_FRAME
    replay_pos[0] = pos
    # The interrupt runs once a video frame at the same raster line, so two
    # stops there look like no time at all. Check the timer wherever the
    # joystick is read, and once a logic frame.
    if got.get("PC") in (0x1BC2, 0x16AC, 0x08F8, 0x0951, 0x1A1E):
        replay_correct()
    value = tuple(0 for _ in replay_columns)
    for clock, v in replay_events:
        if clock > replay_clock[0]:
            break
        value = v
    if replay_ended[0] is None and replay_clock[0] >= replay_end:
        replay_ended[0] = cur_frame[0]
    replay_set[0] = dict(zip(replay_columns, value))


def replay_value(port):
    """The joystick bits due now on a port: 0 is port 1, 1 is port 2."""
    return (replay_set[0] or {}).get(port, 0)


def replay_feed(pc, reg):
    # A holds what the game just read. 0 in bit 4 is the button down.
    if pc == 0x08F8:
        set_a(0x00 if replay_value(0) & 0x10 else 0xFF)
    elif pc == 0x0951:
        set_a(0x00 if (replay_value(0) | replay_value(1)) & 0x10 else 0xFF)
    elif pc == 0x1A1E:
        # The pause test, LDA $DC00,X: X 1 is port 1, X 0 is port 2.
        port = 0 if reg.get("X") == 1 else 1
        set_a(0x00 if replay_value(port) & 0x10 else 0xFF)
    elif pc in REPLAY_MASKS:
        held = 0
        for port in REPLAY_MASKS[pc]:
            held |= replay_value(port) & 0x1F
        if held:
            set_a(reg.get("A", 0xFF) & ~held & 0xFF)


def resume_until(pcs, wait=8):
    rid = send(0xAA, b"")
    pull_until(rid)
    deadline = time.time() + wait
    while time.time() < deadline:
        s.settimeout(max(0.2, deadline - time.time()))
        rtype, err, _, body = recv_response(s)
        if rtype == 0x31:
            got = regs(body)
            pc = got.get("PC")
            if replay_mode:
                replay_tick(got)
            if pc in pcs:
                return pc, got
            if sw_addr is not None and pc is not None:
                if sw_from <= cur_frame[0] <= sw_to:
                    sp = got.get("SP", 0xFF)
                    stack = read_bytes(0x100 + sp + 1, 0x100 + min(sp + 8, 0xFF))
                    sw_log.append(f"stop {cur_frame[0]} pc {pc:04x} A {got.get('A')} X {got.get('X')} Y {got.get('Y')} sp {sp:02x} stack {stack.hex()}")
                send(0xAA)
                deadline = time.time() + 8
        elif rtype == 0x62 and err:
            print("stop err", err)
    raise SystemExit("no breakpoint")


def read_bytes(start, end):
    rid = send(0x01, bytes([0]) + struct.pack("<HHBH", start, end, 0, 0))
    for rtype, err, _, mem in pull_until(rid):
        if rtype == 0x01 and not err:
            ln, = struct.unpack_from("<H", mem, 0)
            return mem[2:2 + ln]
    return b""


def set_a(value):
    body = bytes([0x00, 0x01, 0x00, 0x03, 0x00]) + struct.pack("<H", value)
    rid = send(0x32, body)
    got = pull_until(rid)
    bad = [e for t, e, _, _ in got if e]
    if bad:
        print("set A err", bad, [(hex(t), e) for t, e, _, _ in got])


out = open(out_path, "w", encoding="ascii")
if seed_mode:
    out.write(f"seed {seed}\n")
else:
    out.write(f"stick {stick} fire {0 if fire == 0 else 1}\n")


def dump(frame):
    rid = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x90, 0xD1, 0, 0))
    for rtype, err, _, mem in pull_until(rid):
        if rtype != 0x01 or err:
            continue
        ln, = struct.unpack_from("<H", mem, 0)
        data = mem[2:2 + ln]
        def b(addr):
            return data[addr - 0x90]
        out.write(f"frame {frame}\n")
        # watchbyte=ADDR (hex) logs that byte at the end of every frame.
        if watch_byte is not None:
            wb = read_bytes(watch_byte, watch_byte)
            out.write(f"wb {wb[0] if wb else -1}" + NL)
        out.write(
            f"bruce {b(0x9E)} {b(0xA1)} {b(0xA4)} {b(0xBF)} {b(0xCE)} {b(0xB6)}\n"
        )
        libs = read_bytes(0x4F48, 0x4F48) + read_bytes(0x4F54, 0x4F54) + read_bytes(0x4FDB, 0x4FDB)
        if len(libs) >= 3:
            out.write(f"lib {libs[0]} {libs[1]} {libs[2]}\n")
        # The same three for actor 1, Yamo: library, previous library, $4FDB.
        ylibs = read_bytes(0x4F49, 0x4F49) + read_bytes(0x4F55, 0x4F55) + read_bytes(0x4FDC, 0x4FDC)
        if len(ylibs) >= 3:
            out.write(f"ylib {ylibs[0]} {ylibs[1]} {ylibs[2]}\n")
        out.write(
            f"yamo {b(0x96) & 1} {b(0x9F)} {b(0xA2)} {b(0xA5)} {b(0xC0)} {b(0xCF)} {b(0xB7)}\n"
        )
        out.write(
            f"ninja {b(0xA0)} {b(0xA3)} {b(0xA6)} {b(0xC1)} {b(0xD0)} {b(0xB8)}\n"
        )
        # $D1 Bruce, $D2 Yamo, $D3 the ninja. The read above stops at $D1.
        hp = read_bytes(0xD1, 0xD3)
        if len(hp) >= 3:
            out.write(f"hp {hp[0]} {hp[1]} {hp[2]}\n")
        # $41-$43 is the score, high byte first. $28 is the falls count.
        sc = read_bytes(0x41, 0x43) + read_bytes(0x28, 0x28)
        if len(sc) >= 4:
            out.write(f"score {(sc[0] << 16) | (sc[1] << 8) | sc[2]} {sc[3]}\n")
        # $42CA is the human opponent, $89/$8A his idle count, and $439F the
        # other player's falls.
        op = read_bytes(0x42CA, 0x42CA) + read_bytes(0x89, 0x8A) + read_bytes(0x439F, 0x439F)
        if len(op) >= 4:
            out.write(f"opp {op[0]} {op[1] | (op[2] << 8)} {op[3]}\n")
        if "wake" in sys.argv:
            wk = read_bytes(0x5D, 0x5E); vc = read_bytes(0x87, 0x88); ac = read_bytes(0x95, 0x97)
            out.write(f"wake {wk[0]} {wk[1]} visit {vc[0]} {vc[1]} act {ac[0]} {ac[1]} {ac[2]}" + NL)
        if "fx" in sys.argv:
            v1 = read_bytes(0xEB00, 0xEB02); v2 = read_bytes(0xEF70, 0xEF72); v3 = read_bytes(0xF070, 0xF072); pr = read_bytes(0x2581, 0x2583)
            out.write(f"fx {v1[0]} {pr[0]} {v1[2]} {v2[0]} {pr[1]} {v2[2]} {v3[0]} {pr[2]} {v3[2]}" + NL)
        if "spritedump" in sys.argv:
            ptr = read_bytes(0x8FF8, 0x8FFF); vic = read_bytes(0xD000, 0xD010)
            out.write("sprptr " + ptr.hex() + " vic " + vic.hex() + NL)
            for spr in (0, 1):
                blob = read_bytes(0x8000 + ptr[spr] * 64, 0x8000 + ptr[spr] * 64 + 62)
                for y in range(21):
                    bits = "".join(f"{blob[y*3+c]:08b}" for c in range(3))
                    out.write(f"spr{spr} {y:2d} " + bits.replace("0", ".").replace("1", "#") + NL)
        hold = read_bytes(0x106, 0x108)
        if len(hold) >= 3:
            out.write(f"hold {hold[0]} {hold[1]} {hold[2]}\n")
        if log_spark:
            spark = read_bytes(0x432E, 0x4335)
            if len(spark) >= 8:
                # phase, delay, x, y for bolt 0 ($432E/$4330/$4332/$4334)
                # then bolt 1. The bytes are not contiguous: 432E 432F 4330
                # 4331 4332 4333 4334 4335.
                out.write(
                    "bolt "
                    f"{spark[0]} {spark[2]} {spark[4]} {spark[6]} "
                    f"{spark[1]} {spark[3]} {spark[5]} {spark[7]}\n"
                )
        if probe:
            libs = read_bytes(0x4F48, 0x4F53)
            e0 = read_bytes(0xE0, 0xE2)
            ptr = read_bytes(0xF6, 0xFB)
            slots = read_bytes(0xEB00, 0xEB00) + read_bytes(0xEF70, 0xEF70) + read_bytes(0xF070, 0xF070)
            out.write(
                "libs "
                + " ".join(str(b) for b in libs)
                + " e0 "
                + " ".join(str(b) for b in e0)
                + " ptr "
                + " ".join(str(b) for b in ptr)
                + " slots "
                + " ".join(str(b) for b in slots)
                + "\n"
            )
        if script_mode:
            rid_room = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x29, 0x29, 0, 0))
            for rtype, err, _, mem in pull_until(rid_room):
                if rtype == 0x01 and not err:
                    ln, = struct.unpack_from("<H", mem, 0)
                    out.write(f"room {mem[2]}\n")
                    break
            surf = read_bytes(0x60, 0x66)
            slotb = read_bytes(0x4321, 0x4321)
            falls = read_bytes(0x28, 0x28)
            if len(surf) >= 7:
                out.write(
                    "surf "
                    + " ".join(str(b) for b in surf)
                    + f" {slotb[0] if slotb else -1} {falls[0] if falls else -1}\n"
                )
            # $98 is the stick the body just used or is about to use.
            # $C2 is the remembered state, $CB the step repeat.
            rid_x = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x98, 0xCC, 0, 0))
            for rtype, err, _, mem in pull_until(rid_x):
                if rtype == 0x01 and not err:
                    ln, = struct.unpack_from("<H", mem, 0)
                    raw = mem[2:2 + ln]
                    stick98 = raw[0x98 - 0x98]
                    prev = raw[0xC2 - 0x98]
                    repeat = raw[0xCB - 0x98]
                    out.write(f"extra {stick98} {prev} {repeat}\n")
                    break
            # $97 is actor 2's active flag. The ninja line has no on bit.
            act = read_bytes(0x97, 0x97)
            if act:
                out.write(f"act2 {act[0] & 1}\n")
            rid_p = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x1D, 0x1F, 0, 0))
            ptr = b""
            for rtype, err, _, mem in pull_until(rid_p):
                if rtype == 0x01 and not err:
                    ln, = struct.unpack_from("<H", mem, 0)
                    ptr = mem[2:2 + ln]
                    break
            rid_f = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x0104, 0x0105, 0, 0))
            flag = None
            for rtype, err, _, mem in pull_until(rid_f):
                if rtype == 0x01 and not err:
                    ln, = struct.unpack_from("<H", mem, 0)
                    flag = mem[2]
                    break
            lo = ptr[0] if len(ptr) > 0 else 0
            hi = ptr[1] if len(ptr) > 1 else 0
            out.write(f"play {flag} {hi:02X}{lo:02X}\n")
        if log_lib:
            rid2 = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x4F4E, 0x4F53, 0, 0))
            lib = ""
            for rtype, err, _, mem in pull_until(rid2):
                if rtype == 0x01 and not err:
                    ln, = struct.unpack_from("<H", mem, 0)
                    lib = mem[2:2 + ln].hex()
            out.write(f"lib {lib}\n")
        out.flush()
        print(
            f"f{frame}",
            f"bruce {b(0x9E):02X},{b(0xA1):02X} s{b(0xBF):02X} t{b(0xCE):02X}",
            f"ninja {b(0xA0):02X},{b(0xA3):02X} s{b(0xC1):02X} h{b(0xB8):02X}",
        )


if replay_mode or not capture_mode:
    # VICE's event playback loads its own start snapshot.
    name = PATH.encode("ascii")
    rid = send(0x42, bytes([len(name)]) + name)
    pull_until(rid)
rid = send(0x12, struct.pack("<HHBBBB", 0x1BC2, 0x1BC2, 1, 1, 4, 0))
pull_until(rid)
# The rasters still left in the wait store $98 before the body reads it.
# Patch them, or the first frame keeps the snapshot's neutral stick while
# the hook and the wake counts still run.
rid = send(0x12, struct.pack("<HHBBBB", 0x16AC, 0x16AC, 1, 1, 4, 0))
pull_until(rid)
if fire is not None:
    rid = send(0x12, struct.pack("<HHBBBB", 0x16CD, 0x16CD, 1, 1, 4, 0))
    pull_until(rid)
entry_watch = {0x1BC2, 0x16AC}
if fire is not None:
    entry_watch.add(0x16CD)
if two_sticks:
    for addr in (0x16E3, 0x1701):
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
    entry_watch.update((0x16E3, 0x1701))
if probe:
    rid = send(0x12, struct.pack("<HHBBBB", 0x1DD0, 0x1DD0, 1, 1, 4, 0))
    pull_until(rid)
    entry_watch.add(0x1DD0)
# title_loop's button test, LDA $DC01 then AND #$10. A at 0 is the button
# down, so the page goes on to menu_start and the game.
menu_start = "menustart" in sys.argv
if replay_mode:
    # The clock starts where start.vsf stopped.
    rid = send(0x31, bytes([0]))
    for rtype, err, _, body in pull_until(rid):
        if rtype == 0x31 and not err:
            replay_tick(regs(body))
    replay_t0[0] = replay_timer()
    # The options page's button tests, just after their port reads.
    for addr in REPLAY_POINTS:
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
    entry_watch.update(REPLAY_POINTS)
if menu_start:
    rid = send(0x12, struct.pack("<HHBBBB", 0x08F8, 0x08F8, 1, 1, 4, 0))
    pull_until(rid)
    entry_watch.add(0x08F8)
# Capture mode waits for the person at VICE to start the playback from its
# Snapshot menu, which loads start.vsf. VICE 3.10's -playback option fails
# to load it ("T64 snapshot support is not implemented").
entry_wait = 1800 if capture_mode and not replay_mode else 8
while True:
    pc, reg = resume_until(entry_watch, entry_wait)
    if replay_mode and pc in REPLAY_POINTS:
        replay_feed(pc, reg)
        continue
    if pc == 0x1DD0:
        continue
    if pc == 0x08F8:
        set_a(0)
        continue
    if pc == 0x16AC:
        if capture_mode:
            # A is still the raw port byte, before AND #$0F.
            if replay_mode:
                cap_stick = (~replay_value(0)) & 0x0F
                set_a(cap_stick)
            else:
                cap_stick = reg.get("A", 0x0F) & 0x0F
        else:
            set_a(stick)
        continue
    if pc == 0x16CD:
        if capture_mode:
            # A is the fire bit about to go into $9B. 0 is pressed.
            if replay_mode:
                cap_fire = 0 if replay_value(0) & 0x10 else 1
                set_a(cap_fire)
            else:
                cap_fire = reg.get("A", 1)
        else:
            set_a(fire_reg if fire_reg is not None else fire)
        continue
    if pc == 0x16E3:
        set_a(p2_stick)
        continue
    if pc == 0x1701:
        set_a(0 if p2_held else 1)
        continue
    print("entry", hex(pc))
    break
if mark:
    for addr in marks:
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
if log_y:
    for addr in y_points:
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
if log_noise:
    rid = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x0010, 0x001F, 0, 0))
    for rtype, err, _, mem in pull_until(rid):
        if rtype == 0x01 and not err:
            ln, = struct.unpack_from("<H", mem, 0)
            print(" zp", mem[2:2 + ln].hex())
if log_hit:
    rid = send(0x12, struct.pack("<HHBBBB", 0x29D1, 0x29D1, 1, 1, 4, 0))
    pull_until(rid)
    for addr in time_points:
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
if log_noise:
    rid = send(0x12, struct.pack("<HHBBBB", 0x1165, 0x1165, 1, 1, 4, 0))
    pull_until(rid)
if log_sync and not log_hit:
    rid = send(0x12, struct.pack("<HHBBBB", 0x29D1, 0x29D1, 1, 1, 4, 0))
    pull_until(rid)
if log_sync and not probe:
    rid = send(0x12, struct.pack("<HHBBBB", 0x1DD0, 0x1DD0, 1, 1, 4, 0))
    pull_until(rid)
if log_sync:
    # carry_step, where a ride on a moving surface reads $98.
    rid = send(0x12, struct.pack("<HHBBBB", 0x21B2, 0x21B2, 1, 1, 4, 0))
    pull_until(rid)
watch = {0x1BC2, 0x16AC}
if replay_mode:
    watch.update(REPLAY_POINTS)
if two_sticks:
    watch.update((0x16E3, 0x1701))
if fire is not None:
    watch.add(0x16CD)
if probe:
    watch.add(0x1DD0)
if mark:
    watch.update(marks)
if log_y:
    watch.update(y_points)
if log_hit:
    watch.add(0x29D1)
    watch.update(time_points)
if log_noise:
    watch.add(0x1165)
if log_sync:
    watch.add(0x29D1)
    watch.add(0x1DD0)
    watch.add(0x21B2)
if mark7c:
    for addr in c_points:
        if addr == 0x1BC2:
            continue
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
    watch.update(a for a in c_points if a != 0x1BC2)
sw_pcs = set()
# execwatch=ADDR:FROM:TO logs the stack at every execution of ADDR.
ew = next((a.split("=")[1] for a in sys.argv if a.startswith("execwatch=")), None)
if ew:
    ew_addr = int(ew.split(":")[0], 16)
    rid = send(0x12, struct.pack("<HHBBBB", ew_addr, ew_addr, 1, 1, 4, 0))
    pull_until(rid)
    if sw_addr is None:
        sw_addr, sw_from, sw_to = -1, int(ew.split(":")[1]), int(ew.split(":")[2])
if sw_addr is not None and sw_addr >= 0:
    rid = send(0x12, struct.pack("<HHBBBB", sw_addr, sw_addr, 1, 1, 2, 0))
    pull_until(rid)
if markend:
    rid = send(0x12, struct.pack("<HHBBBB", 0x1C2F, 0x1C2F, 1, 1, 4, 0))
    pull_until(rid)
    watch.add(0x1C2F)
if marksound:
    rid = send(0x12, struct.pack("<HHBBBB", 0x2509, 0x2509, 1, 1, 4, 0))
    pull_until(rid)
    watch.add(0x2509)
if markscan:
    rid = send(0x12, struct.pack("<HHBBBB", 0x2E5B, 0x2E5B, 1, 1, 4, 0))
    pull_until(rid)
    watch.add(0x2E5B)
if ovdump is not None:
    for addr in ov_points:
        rid = send(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        pull_until(rid)
    watch.update(ov_points)
for frame in range(1, frames + 1):
    cur_frame[0] = frame
    patched = 0
    hitreg = None
    while True:
        pc, reg = resume_until(watch)
        if replay_mode and replay_ended[0] is not None:
            # After a game over the options page runs, where no logic
            # frame comes to end this one.
            break
        if replay_mode and pc in REPLAY_POINTS:
            replay_feed(pc, reg)
            continue
        if log_y and pc in y_points:
            if frame >= 296:
                extra = ""
                if pc in (0x1C2F, 0x40BC):
                    act = read_bytes(0x95, 0x97)
                    cap = read_bytes(0x43BD, 0x43BD)
                    extra = " act " + " ".join(str(b) for b in act)
                    if cap:
                        extra += f" cap {cap[0]}"
                out.write(f"y {y_points[pc]} {reg.get('Y')} {frame}{extra}\n")
            continue
        if markend and pc == 0x1C2F:
            rast = read_bytes(0xD011, 0xD012)
            act = read_bytes(0x95, 0x97); pos = read_bytes(0x9E, 0xA0); st = read_bytes(0xBF, 0xC1)
            out.write(f"wend {rast[1] + (256 if rast[0] & 0x80 else 0)} 48 {read_bytes(0x48,0x48)[0]} act {act[0]&1}{act[1]&1}{act[2]&1} x {pos[0]} {pos[1]} {pos[2]} st {st[0]} {st[1]} {st[2]}" + NL)
            continue
        if marksound and pc == 0x2509:
            rast = read_bytes(0xD011, 0xD012)
            raster = rast[1] + (256 if rast[0] & 0x80 else 0)
            act = read_bytes(0x95, 0x97); pos = read_bytes(0x9E, 0xA0)
            out.write(f"snd {reg.get('Y')} {raster} 48 {read_bytes(0x48,0x48)[0]} act {act[0]&1}{act[1]&1}{act[2]&1} x {pos[0]} {pos[1]} {pos[2]} sp {reg.get('SP')}" + NL)
            continue
        if markscan and pc == 0x2E5B:
            if reg.get("X") == 0:
                rast = read_bytes(0xD011, 0xD012)
                raster = rast[1] + (256 if rast[0] & 0x80 else 0)
                act = read_bytes(0x95, 0x97)
                pos = read_bytes(0x9E, 0xA3); st = read_bytes(0xBF, 0xC1)
                out.write(f"scan {raster} 48 {read_bytes(0x48,0x48)[0]} act {act[0]&1}{act[1]&1}{act[2]&1} x {pos[0]} {pos[1]} {pos[2]} y {pos[3]} {pos[4]} {pos[5]} st {st[0]} {st[1]} {st[2]} hook {read_bytes(0x7B,0x7B)[0]}" + NL)
            continue
        if mark7c and pc in c_points and pc != 0x1BC2:
            if c7_from <= frame <= c7_from + 5:
                rast = read_bytes(0xD011, 0xD012)
                raster = rast[1] + (256 if rast[0] & 0x80 else 0)
                z = read_bytes(0x7C, 0x7C)[0]; f2 = read_bytes(0xF2, 0xF2)[0]; c48 = read_bytes(0x48, 0x48)[0]
                out.write(f"c7 {frame} {c_points[pc]} A {reg.get('A')} 7c {z:02x} f2 {f2:02x} 48 {c48} raster {raster}" + NL)
            continue
        if ovdump is not None and pc in ov_points:
            if frame == ovdump:
                who = read_bytes(0x50, 0x50)[0]
                if ov_points[pc] == 9:
                    slots = read_bytes(0x4EED, 0x4F3F)
                    out.write("ovslots " + slots.hex() + NL)
                    out.write("ovhit " + read_bytes(0xB6, 0xB8).hex() + " a7 " + read_bytes(0xA7, 0xA9).hex() + NL)
                elif who == 0:
                    if ov_points[pc] == 0:
                        zp = read_bytes(0x1B, 0x1C)
                        out.write(f"ovpos e6 {read_bytes(0xE6,0xE6)[0]} e9 {read_bytes(0xE9,0xE9)[0]} fine {zp[0]} {zp[1]} lib {read_bytes(0x4F4E,0x4F4E)[0]} x {read_bytes(0x9E,0x9E)[0]} y {read_bytes(0xA1,0xA1)[0]} 7c {read_bytes(0x7C,0x7C)[0]} 38 {read_bytes(0x4F38,0x4F3A).hex()}" + NL)
                        buf = read_bytes(0xCAE0, 0xCB5F)
                        out.write("ovbuf " + buf.hex() + NL)
                    a = read_bytes(0x5381, 0x5382); b2 = read_bytes(0x539B, 0x539C); c = read_bytes(0x53B5, 0x53B6)
                    y52 = read_bytes(0x52, 0x52)[0]
                    g = []
                    for lo, hi in (a, b2, c):
                        base = lo | (hi << 8)
                        g.append(read_bytes(base + y52, base + y52 + 7).hex())
                    out.write(f"ovrow {ov_points[pc]} e9 {read_bytes(0xE9,0xE9)[0]} y52 {y52} glyph {a.hex()} {b2.hex()} {c.hex()} bytes {' '.join(g)} mode {read_bytes(0x4F32,0x4F34).hex()}" + NL)
            continue
        if mark and pc in marks:
            if frame >= 1:
                rast = read_bytes(0xD011, 0xD012)
                d011 = rast[0] if len(rast) > 0 else 0
                d012 = rast[1] if len(rast) > 1 else 0
                raster = d012 + (256 if d011 & 0x80 else 0)
                extra = ""
                if pc == 0x1BEE:
                    lamps = read_bytes(0x0101, 0x0103)
                    extra = " " + " ".join(str(b) for b in lamps)
                extra += f" i48 {read_bytes(0x48, 0x48)[0]}"
                out.write(f"mark {marks[pc]} {raster}{extra}\n")
            continue
        if log_sync and pc in (0x1DD0, 0x21B2):
            # on_ground, or carry_step on a ride, is about to read $98.
            # Whether the raster had stored this frame's stick yet is the
            # stick timing the port replays.
            if reg.get("X") == 0:
                st = read_bytes(0x98, 0x9B)
                # $98 is the stick and $9B the button, 0 while held.
                out.write(f"st {st[0] if st else -1} {st[3] if len(st) > 3 else -1} {frame}" + NL)
            if not probe or pc == 0x21B2:
                continue
        if pc == 0x1DD0:
            if reg.get("X") == 0:
                mem = read_bytes(0x98, 0x98)
                rast = read_bytes(0xD011, 0xD012)
                stick98 = mem[0] if mem else -1
                d011 = rast[0] if len(rast) > 0 else 0
                d012 = rast[1] if len(rast) > 1 else 0
                raster = d012 + (256 if d011 & 0x80 else 0)
                out.write(f"read {stick98} {raster} {reg.get('A')} {reg.get('FL')}\n")
            continue
        if pc == 0x16AC:
            if probe:
                rast = read_bytes(0xD011, 0xD012)
                d011 = rast[0] if len(rast) > 0 else 0
                d012 = rast[1] if len(rast) > 1 else 0
                raster = d012 + (256 if d011 & 0x80 else 0)
                out.write(f"store {raster}\n")
            if capture_mode:
                if replay_mode:
                    cap_stick = (~replay_value(0)) & 0x0F
                    set_a(cap_stick)
                else:
                    cap_stick = reg.get("A", 0x0F) & 0x0F
            else:
                set_a(stick)
            patched += 1
            continue
        if pc == 0x16CD:
            # $9B is 0 while fire is held. Script mode tracks that per frame.
            if capture_mode:
                if replay_mode:
                    cap_fire = 0 if replay_value(0) & 0x10 else 1
                    set_a(cap_fire)
                else:
                    cap_fire = reg.get("A", 1)
            else:
                set_a(fire_reg if fire_reg is not None else fire)
            patched += 1
            continue
        if pc == 0x16E3:
            set_a(p2_stick)
            continue
        if pc == 0x1701:
            set_a(0 if p2_held else 1)
            continue
        if pc == 0x1165:
            zp = read_bytes(0x16, 0x17)
            lo = zp[0] if len(zp) > 0 else -1
            hi = zp[1] if len(zp) > 1 else -1
            out.write(f"nb {reg.get('Y')} {reg.get('A')} {lo} {hi} {frame}\n")
            continue
        if log_hit and pc in time_points:
            if 420 <= frame <= 423:
                rast = read_bytes(0xD011, 0xD012)
                d011 = rast[0] if rast else 0
                d012 = rast[1] if rast and len(rast) > 1 else 0
                raster = d012 + (256 if d011 & 0x80 else 0)
                xpos = read_bytes(0x9E, 0x9E)
                vicx = read_bytes(0xD000, 0xD007)
                out.write(
                    f"t {pc:04x} {raster} x {xpos[0] if xpos else -1} "
                    f"vic {vicx.hex() if vicx else ''} {frame}\n"
                )
            continue
        if log_sync and pc == 0x29D1:
            # A holds the $D01E value read_sprite_hits just loaded.
            out.write(f"hr {reg.get('A')} {frame}" + NL)
            if not log_hit:
                continue
        if pc == 0x29D1:
            hitreg = reg.get("A")
            if frame == 422:
                ptr = read_bytes(0x8FF8, 0x8FFC)
                banks = read_bytes(0x2763, 0x276C)
                flag = read_bytes(0x277D, 0x277D)
                out.write(
                    f"banks {banks.hex() if banks else ''} flag {flag.hex() if flag else ''} "
                    f"live {ptr.hex() if ptr else ''}\n"
                )
                seen = set()
                for base in (ptr or b"") + (banks or b""):
                    if base in seen:
                        continue
                    seen.add(base)
                    blob = read_bytes(0x8000 + base * 64, 0x8000 + base * 64 + 62)
                    out.write(f"img {base:02x} {blob.hex() if blob else ''}\n")
            if frame == 493:
                vic = read_bytes(0xD000, 0xD010)
                ptr = read_bytes(0x8FF8, 0x8FFC)
                print("vic", frame, "A", hex(hitreg or 0), "xy", vic.hex() if vic else "", "ptr", ptr.hex() if ptr else "")
                if ptr:
                    for idx in (1, 3):
                        start = 0x8000 + ptr[idx] * 64
                        blob = read_bytes(start, start + 62)
                        print(f"spr{idx} @{start:04x}", blob.hex() if blob else "")
            patched += 1
            if frame == 48:
                rid = send(0x01, bytes([0]) + struct.pack("<HHBH", 0x8FF8, 0x8FFC, 0, 0))
                for rtype, err, _, mem in pull_until(rid):
                    if rtype == 0x01 and not err:
                        ln, = struct.unpack_from("<H", mem, 0)
                        ptrs = mem[2:2 + ln]
                        print(" pointers", ptrs.hex())
                        for i in (0, 1, 4):
                            p = ptrs[i]
                            start = 0x8000 + p * 64
                            end = start + 62
                            rid = send(0x01, bytes([0]) + struct.pack("<HHBH", start, end, 0, 0))
                            for rt, er, _, body in pull_until(rid):
                                if rt == 0x01 and not er:
                                    n, = struct.unpack_from("<H", body, 0)
                                    print(f" sprite{i} @{start:04x}", body[2:2 + n].hex())
            continue
        break
    if log_hit:
        print("frame", frame, "patched", patched, "d01e", None if hitreg is None else hex(hitreg))
    else:
        print("frame", frame, "patched", patched)
    if seed_mode or script_mode:
        out.write(f"input {stick} {held}\n")
    if capture_mode:
        # The last value the interrupts stored this frame is the frame's
        # stick, as the port's script means it.
        cap_held = 1 if cap_fire == 0 else 0
        cap_lines.append(f"{cap_stick:X} {cap_held}")
        out.write(f"input {cap_stick} {cap_held}" + NL)
    if markscan:
        rast = read_bytes(0xD011, 0xD012)
        out.write(f"fstart {rast[1] + (256 if rast[0] & 0x80 else 0)} {read_bytes(0x48,0x48)[0]}" + NL)
    if probe:
        # Stopped on the first byte of frame, before $48 is reloaded.
        # The raster here is where the new logic frame actually begins.
        rast = read_bytes(0xD011, 0xD012)
        count = read_bytes(0x48, 0x48)
        d011 = rast[0] if len(rast) > 0 else 0
        d012 = rast[1] if len(rast) > 1 else 0
        raster = d012 + (256 if d011 & 0x80 else 0)
        left = count[0] if count else -1
        out.write(f"start {raster} {left}\n")
    dump(frame)
    for line in sw_log:
        out.write(line + NL)
    sw_log.clear()
    if seed_mode:
        rng, stick, held = next_input(rng)
        fire_reg = 0 if held else 1
    elif script_mode and script_i + 1 < len(script):
        script_i += 1
        stick, held, p2_stick, p2_held = script[script_i]
        fire_reg = 0 if held else 1
    if replay_mode and replay_ended[0] is not None:
        # The history is over. Past it the game can sit on the options page,
        # where no logic frame ever comes.
        break
out.close()
if capture_mode:
    script_out = TMP / f"capture_{capture_name}.txt"
    script_out.write_text(NL.join(cap_lines) + NL)
    print("wrote", script_out)
if replay_mode:
    print("recording ended at frame", replay_ended[0], "clock", replay_clock[0], "of", replay_end)
send(0xBB, b"")
s.close()
