"""Compare the port against traces recorded from the original in VICE.

Each case in tests/cases.json runs build/Release/BruceLee.exe in its trace
mode (Oracle=), with a stick script or a seed, from a room or a snapshot in
referencematerial/emulatorsnapshots. The port writes one trace line per body
per logic frame. The reference was recorded from the Commodore 64 game with
tools/vice_trace.py, using the same script.

Every frame must match: position, facing, state, timer, and the overlap's hit
bits. Yamo is compared only while he is on screen. shift is how many logged
frames the port runs ahead of the reference; a snapshot taken in the middle
of a frame logs one frame early, so those cases use a script with the first
line repeated and a shift of 1. bodies lists what is compared: room 15's
snapshot logs the fighters a frame ahead of Bruce, so that case is Bruce only.

Run from the workspace root after a release build:

  python tests/run_traces.py            all cases
  python tests/run_traces.py hunt04 ... only these cases

The exit code is 0 when every case passes.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "build" / "Release" / "BruceLee.exe"
OUT = ROOT / "tests" / "out"
FLAGS = ["PauseOnFocusLoss=False", "FixBugsInOriginal=False", "InfiniteLives=False"]


def read_trace(path):
    frames = []
    for line in Path(path).read_text(errors="replace").splitlines():
        part = line.split()
        if not part:
            continue
        if part[0] == "frame":
            frames.append({"frame": int(part[1])})
        elif part[0] in ("bruce", "yamo", "ninja") and frames:
            frames[-1][part[0]] = [int(v) for v in part[1:]]
    return frames


def core(who, values):
    """The compared fields. The port also logs the pose; the reference does not."""
    if who == "yamo":
        # on, x, y, facing, state, timer, hit. The port adds the pose last.
        return tuple(values[:7])
    # x, y, facing, state, timer, hit. The port puts the pose before the hit.
    if len(values) == 7:
        return tuple(values[:5]) + (values[6],)
    return tuple(values[:6])


def compare(port, reference, shift, bodies):
    compared = 0
    for i, ref in enumerate(reference):
        j = i + shift
        if j < 0 or j >= len(port):
            continue
        compared += 1
        mine = port[j]
        for who in bodies:
            if who not in ref or who not in mine:
                continue
            want = core(who, ref[who])
            got = core(who, mine[who])
            if who == "yamo" and not want[0] and not got[0]:
                continue
            # clear_work_ram zeros the ninja's bytes, and they stay 0 until
            # he first wakes. The port keeps whatever it last had there.
            if who == "ninja" and not any(ref[who]):
                continue
            if want != got:
                return compared, f"frame {ref['frame']} {who}: port {got} original {want}"
    if compared < len(reference) - abs(shift):
        return compared, f"port logged {len(port)} frames, expected {len(reference)}"
    return compared, None


def run(case):
    OUT.mkdir(exist_ok=True)
    out = OUT / f"{case['name']}.txt"
    if out.exists():
        out.unlink()
    rel = out.relative_to(ROOT).as_posix()
    subprocess.run([str(EXE), *FLAGS, *case["args"], f"Out={rel}"], cwd=ROOT, check=False)
    if not out.exists():
        return 0, "the port wrote no trace"
    return compare(read_trace(out), read_trace(ROOT / case["reference"]), case["shift"], case["bodies"])


def main():
    if not EXE.exists():
        raise SystemExit(f"build the release first: {EXE.relative_to(ROOT)} is missing")
    cases = json.loads((ROOT / "tests" / "cases.json").read_text())
    wanted = set(sys.argv[1:])
    if wanted:
        unknown = wanted - {c["name"] for c in cases}
        if unknown:
            raise SystemExit("unknown case: " + ", ".join(sorted(unknown)))
        cases = [c for c in cases if c["name"] in wanted]
    failed = 0
    for case in cases:
        compared, problem = run(case)
        if problem:
            failed += 1
            print(f"FAIL {case['name']}: {problem}", flush=True)
        else:
            print(f"pass {case['name']} ({compared} frames)", flush=True)
    print(f"{len(cases) - failed} of {len(cases)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
