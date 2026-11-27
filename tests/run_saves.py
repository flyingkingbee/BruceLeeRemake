"""Check that a save game holds the whole game: after a save, the game must
behave exactly as it does after loading that save again.

Every case in tests/cases.json is run by the port alone, in its trace mode.
No VICE recording is needed, since the port is compared with itself. Run A
plays a case through, logging the trace and, after every logic frame, a hash
of the full save text (StateLog=). That hash covers every saved variable,
not only what the trace shows.

  save/load     A saves at several frames K. Run C starts a different game,
                loads the save made after frame K, and plays on from script
                line K+1. Its trace and state hashes must equal A's from K on.
                C also saves again straight after the load, and that file must
                equal the one it loaded, apart from the [Save] header.
  every frame   the case runs with SaveEvery=1, a save and a load after every
                frame. Trace and state hashes must equal A's for the whole run.
  screens       a save is loaded from the title, the options page, the PLAYER
                page, and game over. Each must play on as A did.
  options       a save made with FixBugsInOriginal, InfiniteLives, and
                EnemiesCantHitBruce one way is loaded with the opposite
                settings. The save's gameplay options win, and the run must
                match. A display setting must stay as the loading run had it.
  format        an older format goes through the upgrade step; a newer format,
                a damaged array, a missing section, and a value out of range
                are refused, and a refused load leaves the game unchanged.
                The slot menu names are checked for an empty, a used, and a
                damaged slot.

The save points are early, middle, and late in each case, plus the frames
around each room change, each lost life, and the first frame of each state
Bruce and the fighters go through. A coverage report lists the moments the
saves landed in, and the run fails when a required one is never reached.

Run from the workspace root after a release build:

  python tests/run_saves.py                all checks, all cases
  python tests/run_saves.py hunt04 ...     only these cases
  python tests/run_saves.py --quick        three save points per case

The exit code is 0 when every check passes.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "build" / "Release" / "BruceLee.exe"
WORK = ROOT / "tmp" / "saves"
SYNC_LOG = ROOT / "tmp" / "port_sync.txt"
FLAGS = ["PauseOnFocusLoss=False", "FixBugsInOriginal=False", "InfiniteLives=False",
         "EnemiesCantHitBruce=False", "TopScore=0"]
# The games a load replaces. Each loaded run starts from one of these, never
# from the case's own start, so nothing of the old game may leak through.
BASES = [
    ["Oracle=room00"],
    ["Oracle=room13"],
    ["Oracle=room00", "Start=1"],
    ["Oracle=room05"],
    ["Oracle=room00", "Demo=1"],
]
SCREENS = ["title", "menu", "player", "gameover"]
MAX_POINTS = 8
WORKERS = max(2, min(12, (os.cpu_count() or 4)))

# Bruce's states, bruce.h.
BRUCE_STATES = {
    0x01: "climbing up", 0x02: "climbing down", 0x05: "jumping", 0x06: "jumping sideways",
    0x07: "jumping sideways", 0x0C: "in a flying kick", 0x0D: "in a flying kick", 0x0E: "falling",
    0x0F: "punched", 0x11: "punching", 0x13: "kicked down", 0x17: "carried on a scrolling floor",
    0x18: "stuck in a wall", 0x19: "zapped", 0x1A: "ducking", 0x1B: "landed on",
}
# Moments a save must land in at least once. Others are reported only.
REQUIRED = [
    "Bruce jumping", "Bruce in a flying kick", "Bruce falling", "Bruce ducking", "Bruce climbing up",
    "Bruce carried on a scrolling floor", "Bruce kicked down", "Bruce punching",
    "a fighter awake", "a fighter knocked down", "both fighters awake",
    "room 13 movers running", "room 18 sparks falling", "room 19 countdown",
    "two players, the other player waiting", "a human opponent",
    "the game finished at least once", "the extra-life mark moved by a new top score",
    "a door this frame", "the frame after a lost life",
] + [f"room {r}" for r in range(20)]


def case_args(case):
    args = list(case["args"])
    if "sync" in case:
        args.append(f"Sync={case['sync']}")
    return args


def frames_of(case):
    for a in case["args"]:
        if a.startswith("Frames="):
            return int(a[7:])
    return 24


def script_of(case):
    return [a for a in case["args"] if a.startswith(("Script=", "Seed=", "Stick=", "Fire="))]


def run_port(args, name):
    """Run the port with a trace in WORK/name.txt. Returns (exit code, trace path)."""
    out = WORK / f"{name}.txt"
    if out.exists():
        out.unlink()
    rel = out.relative_to(ROOT).as_posix()
    result = subprocess.run([str(EXE), *FLAGS, *args, f"Out={rel}"], cwd=ROOT, check=False)
    return result.returncode, out


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def read_frames(path):
    """frame -> list of trace lines, and any error line."""
    frames = {}
    error = None
    current = None
    if not Path(path).exists():
        return frames, "no trace written"
    for line in Path(path).read_text(errors="replace").splitlines():
        if line.startswith("error "):
            error = line[6:]
        elif line.startswith("frame "):
            current = int(line.split()[1])
            frames[current] = []
        elif current is not None and not line.startswith("input "):
            frames[current].append(line)
    return frames, error


def read_hashes(path):
    hashes = {}
    if Path(path).exists():
        for line in Path(path).read_text().splitlines():
            parts = line.split()
            if len(parts) == 2:
                hashes[int(parts[0])] = parts[1]
    return hashes


def first_difference(want_frames, got_frames, want_hashes, got_hashes, start):
    """The first frame from start on where the runs differ, as text, or None."""
    for frame in sorted(want_frames):
        if frame <= start:
            continue
        if frame not in got_frames:
            return f"frame {frame} missing"
        if want_frames[frame] != got_frames[frame]:
            for a, b in zip(want_frames[frame], got_frames[frame]):
                if a != b:
                    return f"frame {frame} trace: expected '{a}', got '{b}'"
            return f"frame {frame} trace differs"
    for frame in sorted(want_hashes):
        if frame < start:
            continue
        if want_hashes.get(frame) != got_hashes.get(frame):
            return f"frame {frame} saved state differs"
    if max(want_frames, default=0) != max(got_frames, default=0):
        return f"ran to frame {max(got_frames, default=0)}, expected {max(want_frames, default=0)}"
    return None


def parse_save(path):
    """section -> key -> value."""
    data = {}
    section = None
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith((";", "#")):
            continue
        if line.startswith("["):
            section = line[1:line.index("]")]
            data.setdefault(section, {})
        elif "=" in line and section:
            key, value = line.split("=", 1)
            data[section][key] = value
    return data


# The settings a load takes back. The others are written for information.
GAMEPLAY_OPTIONS = ("InfiniteLives", "EnemiesCantHitBruce", "FixBugsInOriginal")


def game_part(path):
    """The saved game without [Save] and the information-only settings."""
    data = parse_save(path)
    data.pop("Save", None)
    if "Options" in data:
        data["Options"] = {k: v for k, v in data["Options"].items() if k in GAMEPLAY_OPTIONS}
    return data


def key_difference(a, b):
    """The first [section] key whose value differs between two save files."""
    da, db = game_part(a), game_part(b)
    for section in da:
        for key, value in da[section].items():
            other = db.get(section, {}).get(key)
            if other != value:
                return f"[{section}] {key}: {value[:40]} then {str(other)[:40]}"
    return "the files differ"


def explain_state(case, base_args, a_name, c_args, frame):
    """Dump the state text of both runs at frame and name the first key that differs."""
    da = WORK / f"{a_name}_dumpA.txt"
    dc = WORK / f"{a_name}_dumpC.txt"
    run_port([*base_args, f"StateDump={frame}", f"StateDumpTo={rel(da)}"], f"{a_name}_explainA")
    run_port([*c_args, f"StateDump={frame}", f"StateDumpTo={rel(dc)}"], f"{a_name}_explainC")
    if not da.exists() or not dc.exists():
        return ""
    return " (" + key_difference(da, dc) + ")"


def pick_points(frames, total, quick):
    """Save frames for one case: early, middle, late, and around its events."""
    points = [max(1, total // 4), max(1, total // 2), max(1, total * 3 // 4)]
    if quick:
        return sorted(set(p for p in points if 1 <= p < total))
    events = []
    seen_states = set()
    prev = None
    for frame in sorted(frames):
        lines = {line.split()[0]: line.split()[1:] for line in frames[frame] if line.split()}
        if prev is not None:
            if lines.get("room") != prev.get("room"):
                events += [frame - 1, frame]  # the frame of a door, and the first frame of a new room
            if lines.get("score", [0, 0])[1:] != prev.get("score", [0, 0])[1:]:
                events += [frame - 1, frame]  # a life lost or won
        bruce = lines.get("bruce")
        if bruce and len(bruce) > 4:
            state = ("bruce", bruce[3])
            if state not in seen_states and int(bruce[4]) > 0:
                seen_states.add(state)
                events.append(frame)
        for who in ("yamo", "ninja"):
            body = lines.get(who)
            if body:
                act = body[4] if who == "yamo" else body[3]
                state = (who, act)
                if state not in seen_states:
                    seen_states.add(state)
                    events.append(frame + 1)
        prev = lines
    for e in events:
        if len(points) >= MAX_POINTS:
            break
        if 1 <= e < total and e not in points:
            points.append(e)
    return sorted(set(p for p in points if 1 <= p < total))


def coverage_of(path, labels):
    s = parse_save(path)
    game, bruce, fighters, fx = s.get("Game", {}), s.get("Bruce", {}), s.get("Fighters", {}), s.get("RoomFx", {})
    labels.add(f"room {game.get('Room')}")
    action = int(game.get("Action", "0"))
    if action in BRUCE_STATES:
        labels.add("Bruce " + BRUCE_STATES[action])
    on = [fighters.get(f"{w}.On") == "True" for w in ("Ninja", "Yamo")]
    if any(on):
        labels.add("a fighter awake")
    if all(on):
        labels.add("both fighters awake")
    for w in ("Ninja", "Yamo"):
        if fighters.get(f"{w}.On") == "True" and int(fighters.get(f"{w}.Action", "0")) in (0x13, 0x1B, 0x0E):
            labels.add("a fighter knocked down")
    if fighters.get("Held") == "True":
        labels.add("the fighters held over a door")
    if any(int(fx.get(f"Mover{i}", "00")[:2], 16) for i in range(9)) and game.get("Room") == "13":
        labels.add("room 13 movers running")
    if game.get("Room") == "18" and "1" in fx.get("BoltOn", ""):
        labels.add("room 18 sparks falling")
    if game.get("Room") == "18" and fx.get("FlashCharset", "-1") != "-1":
        labels.add("room 18 death flash")
    if game.get("Room") == "19" and int(fx.get("Victory", "0")) > 0:
        labels.add("room 19 countdown")
    if game.get("Room") == "7" and any(int(fx.get(f"Crumble{i}", "00")[:2], 16) for i in range(3)):
        labels.add("room 7 crumble running")
    if game.get("Room") == "5" and fx.get("Col71", "0") != "0":
        labels.add("room 5 beams moving")
    if game.get("TwoPlayers") == "True" and int(game.get("WaitingLives", "-1")) >= 0:
        labels.add("two players, the other player waiting")
    if game.get("HumanOpponent") == "True":
        labels.add("a human opponent")
    if game.get("OpponentYielded") == "True":
        labels.add("an idle opponent handed back to the computer")
    if int(fx.get("Difficulty", "0")) > 0:
        labels.add("the game finished at least once")
    if game.get("FirstMark", "0x009C40") != "0x009C40":
        labels.add("the extra-life mark moved by a new top score")
    if fx.get("IdleCycling") == "True":
        labels.add("the idle pause cycling colors")
    if bruce.get("AwaitingLife") == "True" or bruce.get("OutOfLives") == "True":
        labels.add("a death before the PLAYER page")
    if fighters.get("StandPageSaved") == "True":
        labels.add("the stand page changed by a 442-cell room")
    memory = "".join(s.get("Noise", {}).get(f"Memory.{i}", "") for i in range(16))
    if len(memory) >= 0x105 * 2 and memory[0x104 * 2:0x104 * 2 + 2] == "00":
        labels.add("the attract demo")


class Report:
    def __init__(self):
        self.failures = []
        self.passes = 0

    def check(self, label, problem):
        if problem:
            self.failures.append(f"{label}: {problem}")
            print(f"FAIL {label}: {problem}", flush=True)
        else:
            self.passes += 1


def baseline(case):
    """Run A: the case straight through, with a trace and the state log."""
    name = case["name"]
    log = WORK / f"{name}_A.log"
    if "sync" in case and SYNC_LOG.exists():
        SYNC_LOG.unlink()
    code, out = run_port([*case_args(case), f"StateLog={rel(log)}"], f"{name}_A")
    frames, error = read_frames(out)
    return frames, read_hashes(log), error or (None if code == 0 else f"exit code {code}")


def save_load_case(case, quick, report, labels, index):
    name = case["name"]
    total = frames_of(case)
    frames, hashes, error = baseline(case)
    if error:
        report.check(f"{name} run A", error)
        return
    points = pick_points(frames, total, quick)
    prefix = WORK / name
    log_b = WORK / f"{name}_B.log"
    # B: the same run, saving. Saving must not change the game it saves.
    code, out_b = run_port([*case_args(case), f"StateLog={rel(log_b)}",
                            "SaveAt=" + ",".join(map(str, points)), f"SaveTo={rel(prefix)}"], f"{name}_B")
    frames_b, err_b = read_frames(out_b)
    report.check(f"{name} saving does not change the game",
                 err_b or first_difference(frames, frames_b, hashes, read_hashes(log_b), 0))
    for n, k in enumerate(points):
        save = Path(f"{prefix}_{k}.sav")
        if not save.exists():
            report.check(f"{name} save after frame {k}", "no save written")
            continue
        coverage_of(save, labels)
        if k in frames and k - 1 in frames:
            prev = {l.split()[0]: l.split()[1:] for l in frames.get(k - 1, []) if l.split()}
            cur = {l.split()[0]: l.split()[1:] for l in frames.get(k, []) if l.split()}
            nxt = {l.split()[0]: l.split()[1:] for l in frames.get(k + 1, []) if l.split()}
            if cur.get("room") != nxt.get("room") and nxt:
                labels.add("a door this frame")
            if prev.get("score", [0, 0])[1:] != cur.get("score", [0, 0])[1:]:
                labels.add("the frame after a lost life")
        base = BASES[(index + n) % len(BASES)]
        resave = WORK / f"{name}_{k}_re"
        log_c = WORK / f"{name}_{k}_C.log"
        c_args = [*base, *script_of(case), f"Frames={total}", f"LoadGame={rel(save)}", f"ScriptSkip={k}",
                  f"StateLog={rel(log_c)}", f"SaveAt={k}", f"SaveTo={rel(resave)}"]
        code, out_c = run_port(c_args, f"{name}_{k}_C")
        frames_c, err_c = read_frames(out_c)
        problem = err_c or first_difference(frames, frames_c, hashes, read_hashes(log_c), k)
        if problem and "saved state" in problem:
            frame = int(problem.split()[1])
            problem += explain_state(case, [*case_args(case)], f"{name}_{k}", c_args, frame)
        report.check(f"{name} load after frame {k} over {' '.join(base)}", problem)
        again = Path(f"{resave}_{k}.sav")
        if not err_c:
            if not again.exists():
                report.check(f"{name} save again after loading frame {k}", "no save written")
            elif game_part(again) != game_part(save):
                report.check(f"{name} save again after loading frame {k}", key_difference(save, again))
            else:
                report.passes += 1


def every_frame_case(case, report):
    name = case["name"]
    frames, hashes, error = baseline(case)
    if error:
        report.check(f"{name} run A", error)
        return
    log = WORK / f"{name}_E.log"
    if "sync" in case and SYNC_LOG.exists():
        SYNC_LOG.unlink()
    code, out = run_port([*case_args(case), "SaveEvery=1", f"StateLog={rel(log)}"], f"{name}_E")
    frames_e, err = read_frames(out)
    report.check(f"{name} save and load every frame",
                 err or first_difference(frames, frames_e, hashes, read_hashes(log), 0))


def screens_case(case, report, index):
    name = case["name"]
    total = frames_of(case)
    frames, hashes, error = baseline(case)
    if error:
        report.check(f"{name} run A", error)
        return
    k = max(1, total // 2)
    prefix = WORK / f"{name}_S"
    run_port([*case_args(case), f"SaveAt={k}", f"SaveTo={rel(prefix)}"], f"{name}_S")
    save = Path(f"{prefix}_{k}.sav")
    for n, screen in enumerate(SCREENS):
        base = BASES[(index + n) % len(BASES)]
        log = WORK / f"{name}_{screen}.log"
        code, out = run_port([*base, *script_of(case), f"Frames={total}", f"LoadGame={rel(save)}",
                              f"ScriptSkip={k}", f"LoadFrom={screen}", f"StateLog={rel(log)}"],
                             f"{name}_{screen}")
        frames_c, err = read_frames(out)
        report.check(f"{name} load from the {screen} screen",
                     err or first_difference(frames, frames_c, hashes, read_hashes(log), k))


OPTION_SETS = [
    {"FixBugsInOriginal": "True", "InfiniteLives": "True", "EnemiesCantHitBruce": "True"},
    {"FixBugsInOriginal": "True", "InfiniteLives": "False", "EnemiesCantHitBruce": "False"},
    {"FixBugsInOriginal": "False", "InfiniteLives": "True", "EnemiesCantHitBruce": "False"},
    {"FixBugsInOriginal": "False", "InfiniteLives": "False", "EnemiesCantHitBruce": "True"},
]


def options_case(case, report, index):
    name = case["name"]
    total = frames_of(case)
    k = max(1, total // 3)
    for n, options in enumerate(OPTION_SETS):
        saved = [f"{key}={value}" for key, value in options.items()]
        flipped = [f"{key}={'False' if value == 'True' else 'True'}" for key, value in options.items()]
        tag = f"{name}_O{n}"
        prefix = WORK / tag
        # A plays with the options and the CRT filter on. FLAGS come first,
        # so these words win.
        if "sync" in case and SYNC_LOG.exists():
            SYNC_LOG.unlink()
        # A full save at the last frame shows every setting the run ended with.
        code, out_a = run_port([*case_args(case), *saved, "ShowCRTFilter=True", f"SaveAt={k},{total}",
                                f"SaveTo={rel(prefix)}"], f"{tag}_A")
        dump_a = Path(f"{prefix}_{total}.sav")
        frames_a, err = read_frames(out_a)
        if err:
            report.check(f"{tag} run A", err)
            continue
        base = BASES[(index + n) % len(BASES)]
        code, out_c = run_port([*base, *script_of(case), *flipped, "ShowCRTFilter=False", f"Frames={total}",
                                f"LoadGame={rel(prefix)}_{k}.sav", f"ScriptSkip={k}", f"SaveAt={total}",
                                f"SaveTo={rel(prefix)}_C"], f"{tag}_C")
        dump_c = Path(f"{prefix}_C_{total}.sav")
        frames_c, err = read_frames(out_c)
        problem = err or first_difference(frames_a, frames_c, {}, {}, k)
        if not problem:
            if not dump_a.exists() or not dump_c.exists():
                report.check(f"{tag} last-frame saves", "not written")
                continue
            a, c = parse_save(dump_a), parse_save(dump_c)
            for key, value in options.items():
                if c["Options"].get(key) != value:
                    problem = f"{key} after the load is {c['Options'].get(key)}, the save had {value}"
            if c["Options"].get("ShowCRTFilter") != "False":
                problem = "the load changed ShowCRTFilter, a display setting"
            for section in a:
                if section not in ("Options", "Save") and a[section] != c.get(section):
                    problem = problem or f"[{section}] differs at the last frame"
        report.check(f"{tag} gameplay options come back with the save ({', '.join(saved)})", problem)


def format_checks(case, report):
    """Upgrade, refusals, and slot names, on one save of this case."""
    name = case["name"]
    total = frames_of(case)
    k = max(1, total // 2)
    frames, hashes, error = baseline(case)
    prefix = WORK / f"{name}_F"
    run_port([*case_args(case), f"SaveAt={k}", f"SaveTo={rel(prefix)}"], f"{name}_F")
    save = Path(f"{prefix}_{k}.sav")
    text = save.read_text()
    base = ["Oracle=room00"]
    tail = [*script_of(case), f"Frames={total}", f"ScriptSkip={k}"]

    # An older format: Score was Points in format 0. The upgrade renames it.
    old = WORK / f"{name}_format0.sav"
    old.write_text(text.replace("Format=1", "Format=0", 1).replace("\nScore=", "\nPoints=", 1))
    log = WORK / f"{name}_format0.log"
    code, out = run_port([*base, *tail, f"LoadGame={rel(old)}", f"StateLog={rel(log)}"], f"{name}_format0")
    got, err = read_frames(out)
    report.check("format 0 save is upgraded and loads",
                 err or first_difference(frames, got, hashes, read_hashes(log), k))

    # Refused files. A refused load must leave the game it had: the run
    # goes on from Oracle=room00's own start and must equal a plain run.
    plain_log = WORK / f"{name}_plain.log"
    code, out = run_port([*base, *script_of(case), f"Frames={total}", f"StateLog={rel(plain_log)}"],
                         f"{name}_plain")
    plain, _ = read_frames(out)
    plain_hashes = read_hashes(plain_log)
    charset_line = re.search(r"\nCharset\.3=[0-9A-F]+", text).group(0)
    bad = {
        "a newer format": (text.replace("Format=1", "Format=2", 1), "newer version"),
        "a damaged array": (text.replace(charset_line, charset_line[:-2], 1), "should hold"),
        "a hex array with a bad digit": (text.replace(charset_line, charset_line[:-1] + "G", 1), "not hex"),
        "a missing section": (re.sub(r"\[Fighters\][^\[]*", "", text), "[Fighters]"),
        "a room out of range": (re.sub(r"\nRoom=\d+", "\nRoom=25", text, count=1), "out of range"),
        "a value that is not a number": (re.sub(r"\nLives=-?\d+", "\nLives=four", text, count=1),
                                         "not a number"),
        "a missing key": (re.sub(r"\nHealth=-?\d+", "", text, count=1), "missing"),
        "a file that is not a save": ("hello\n", "not"),
    }
    for n, (label, (body, words)) in enumerate(bad.items()):
        path = WORK / f"{name}_bad{n}.sav"
        path.write_text(body)
        log = WORK / f"{name}_bad{n}.log"
        code, out = run_port([*base, *script_of(case), f"Frames={total}", f"LoadGame={rel(path)}",
                              "LoadOptional=1", f"StateLog={rel(log)}"], f"{name}_bad{n}")
        got, err = read_frames(out)
        if err is None:
            problem = "the load was accepted"
        elif words not in err:
            problem = f"the message does not say '{words}': {err}"
        else:
            problem = first_difference(plain, got, plain_hashes, read_hashes(log), 0)
            if problem:
                problem = "the refused load changed the game: " + problem
        report.check(f"{label} is refused", problem)

    # Slot names, from a folder of the test's own.
    slots = WORK / "slots"
    shutil.rmtree(slots, ignore_errors=True)
    slots.mkdir(parents=True)
    shutil.copy(save, slots / "quick.sav")
    shutil.copy(save, slots / "slot3.sav")
    (slots / "slot5.sav").write_text("not a save\n")
    names_out = WORK / "slotnames.txt"
    subprocess.run([str(EXE), "SlotNames=1", f"SaveFolder={rel(slots)}", f"Out={rel(names_out)}"],
                   cwd=ROOT, check=False)
    want_name = parse_save(save)["Save"]["Name"]
    lines = names_out.read_text().splitlines() if names_out.exists() else []
    problem = None
    if len(lines) != 9:
        problem = f"expected 9 slot lines, got {len(lines)}"
    else:
        expect = {0: f"0 used {want_name}", 3: f"3 used {want_name}", 5: "5 used (unreadable)"}
        for slot in range(9):
            want = expect.get(slot, f"{slot} free (empty)")
            if lines[slot] != want:
                problem = f"slot {slot} shows '{lines[slot]}', expected '{want}'"
                break
    if not re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d   Room \d+   Completed \d+$", want_name):
        problem = problem or f"the save name does not read as date, room, and completed: {want_name}"
    report.check("slot menu names: empty, used, and damaged", problem)


def main():
    if not EXE.exists():
        raise SystemExit(f"build the release first: {EXE.relative_to(ROOT)} is missing")
    args = sys.argv[1:]
    quick = "--quick" in args
    wanted = {a for a in args if not a.startswith("--")}
    cases = json.loads((ROOT / "tests" / "cases.json").read_text())
    if wanted:
        unknown = wanted - {c["name"] for c in cases}
        if unknown:
            raise SystemExit("unknown case: " + ", ".join(sorted(unknown)))
        cases = [c for c in cases if c["name"] in wanted]
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    report = Report()
    labels = set()
    # A sync case replays VICE's noise reads by position, and that replay is
    # not part of a save, so only the every-frame check runs it. Sync cases
    # share one log file, so they run one at a time.
    plain = [c for c in cases if "sync" not in c]
    synced = [c for c in cases if "sync" in c]

    print(f"== save, load, and continue: {len(plain)} cases", flush=True)
    with ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(lambda ic: save_load_case(ic[1], quick, report, labels, ic[0]), enumerate(plain)))
    print(f"== save and load every frame: {len(cases)} cases", flush=True)
    with ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(lambda c: every_frame_case(c, report), plain))
    for case in synced:
        every_frame_case(case, report)
    screen_cases = plain[:: max(1, len(plain) // 12)] if not wanted else plain
    print(f"== load from every screen: {len(screen_cases)} cases", flush=True)
    with ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(lambda ic: screens_case(ic[1], report, ic[0]), enumerate(screen_cases)))
    # Cases with blows and falls show the options at work.
    option_cases = [c for c in plain if c["name"].startswith(("long", "hunt", "opp"))][:8] or plain[:4]
    print(f"== gameplay options: {len(option_cases)} cases", flush=True)
    with ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(lambda ic: options_case(ic[1], report, ic[0]), enumerate(option_cases)))
    if plain:
        print("== format", flush=True)
        format_checks(plain[0], report)

    print()
    print("Save points landed in:")
    for label in sorted(labels):
        print(f"  {label}")
    if not wanted and not quick:
        missing = [r for r in REQUIRED if r not in labels]
        for r in missing:
            report.check("coverage", f"no save point lands in: {r}")
    print()
    if report.failures:
        print(f"{len(report.failures)} checks FAILED, {report.passes} passed")
        return 1
    print(f"all {report.passes} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
