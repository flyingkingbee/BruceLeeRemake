"""Add a reference trace from VICE to the regression tests.

Takes a trace that tools/vice_trace.py recorded from a snapshot, keeps the
frames the port should match, writes it to tests/reference, and adds or
replaces the case in tests/cases.json. Run from the workspace root:

  python tools/add_trace_case.py NAME SNAPSHOT TRACE SCRIPT [--frames N]

NAME is the case name and the reference file's name. SNAPSHOT is the .vsf
the trace was recorded from, TRACE is vice_trace.py's output, and SCRIPT is
the stick file it was given. --frames keeps only frames 1 to N, for a trace
that stops matching after that, for example where the original's raster
timing (the noise counter, or which frame first sees a new stick) takes it
somewhere the port does not follow. Example:

  python tools/vice_trace.py referencematerial/emulatorsnapshots/room04.vsf 400 \\
      tmp/rand04.txt script tests/scripts/rand.txt
  python tools/add_trace_case.py rand04 referencematerial/emulatorsnapshots/room04.vsf \\
      tmp/rand04.txt tests/scripts/rand.txt

The room is $29 in the snapshot. Room 18 runs as Oracle=room17, because the
port's trace mode has no room 18 entry and the snapshot replaces the room
anyway.

The alignment comes from the snapshot's program counter, against step_actors's
stick read. A snapshot past that read needs no script line for the rest of
its frame, so the port runs SCRIPT and its frame N is the reference's frame
N (shift 0). That is the frame wait ($1C32-$1C36), between_lives's wait
($0F47-$0F71), blit_sprites and the routines it calls ($2584-$277F), and
check_bruce_down ($2D55-$2D78). Anywhere else, the rest of the snapshot's
frame still reads the stick, so the port runs SCRIPT with its first line
repeated, written as <SCRIPT>_lag.txt beside it if that file is missing, and
the case has shift 1. --shift overrides the choice.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "tests" / "cases.json"
KEPT = ("frame", "bruce", "yamo", "ninja")


def read_snapshot(path):
    data = path.read_bytes()
    cpu = data.find(b"MAINCPU")
    mem = data.find(b"C64MEM")
    if cpu < 0 or mem < 0:
        raise SystemExit(f"{path} is not a VICE snapshot with MAINCPU and C64MEM")
    pc = data[cpu + 34] | (data[cpu + 35] << 8)
    room = data[mem + 26 + 0x29]
    return pc, room


def past_stick_read(pc):
    return (pc in (0x1C32, 0x1C34, 0x1C36) or 0x0F47 <= pc <= 0x0F71
            or 0x2584 <= pc <= 0x277F or 0x2D55 <= pc <= 0x2D78)


def lag_script(script):
    lag = script.with_name(script.stem + "_lag" + script.suffix)
    lines = script.read_text().splitlines()
    want = "\n".join([lines[0]] + lines) + "\n"
    if lag.exists():
        if lag.read_text().replace("\r\n", "\n") != want:
            raise SystemExit(f"{lag} exists but is not {script} with its first line repeated")
    else:
        lag.write_text(want)
        print("wrote", rel(lag))
    return lag


def keep_frames(trace, last):
    out = []
    frame = 0
    for line in trace.read_text().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == "frame":
            frame = int(words[1])
        if frame >= 1 and (last is None or frame <= last) and words[0] in KEPT:
            out.append(line)
    if not out:
        raise SystemExit(f"{trace} has no frame lines")
    return out, frame if last is None else min(last, frame)


def rel(path):
    return path.resolve().relative_to(ROOT).as_posix()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("name")
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("trace", type=Path)
    parser.add_argument("script", type=Path)
    parser.add_argument("--frames", type=int, help="keep frames 1 to N only")
    parser.add_argument("--shift", type=int, choices=(0, 1), help="override the alignment")
    args = parser.parse_args()

    pc, room = read_snapshot(args.snapshot)
    shift = args.shift if args.shift is not None else (0 if past_stick_read(pc) else 1)
    script = args.script if shift == 0 else lag_script(args.script)
    oracle = 17 if room == 18 else room

    lines, frames = keep_frames(args.trace, args.frames)
    reference = ROOT / "tests" / "reference" / f"{args.name}.txt"
    reference.write_text("\n".join(lines) + "\n")

    case = {
        "name": args.name,
        "args": [
            f"Oracle=room{oracle:02d}",
            f"Frames={frames + shift}",
            f"Snap={rel(args.snapshot)}",
            f"Script={rel(script)}",
        ],
        "reference": rel(reference),
        "shift": shift,
        "bodies": ["bruce", "yamo", "ninja"],
    }
    cases = json.loads(CASES.read_text())
    replaced = any(c["name"] == args.name for c in cases)
    cases = [case if c["name"] == args.name else c for c in cases]
    if not replaced:
        cases.append(case)
    CASES.write_text(json.dumps(cases, indent=2) + "\n")
    print(f"{'replaced' if replaced else 'added'} {args.name}: room {room}, pc ${pc:04X}, "
          f"shift {shift}, {frames} frames")


if __name__ == "__main__":
    sys.exit(main())
