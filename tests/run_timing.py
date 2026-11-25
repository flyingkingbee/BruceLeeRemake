"""Check that the port runs at the original game's speed in real time.

One logic frame of the Commodore 64 game is three PAL screens, 3 * 19656
cycles at 985248 Hz, 59.852 ms. The trace tests in run_traces.py do not run
in real time, so they cannot see the pacing. This test runs
build/Release/BruceLee.exe in its timing mode (TimingLog=): the game opens its
window and runs as usual for a number of frames, writes how long each frame
took and how long its paint took, and closes without saving the settings.

Each case passes when:
  - the mean frame period is within 0.5% of 59.852 ms, so the game neither
    runs slow nor fast over the run,
  - at least 95% of frames are within 3 ms of it, so the pacing is steady.
    A stall once a second puts about 11% of frames off.
The first frames are skipped while the window and the sound start.

The cases cover a plain window, the CRT filter in full screen, and a
synthetic 30 ms of extra paint work, which stands in for a slower PC. The
paint time must come out of the frame, not be added to it.

The test opens a real window for about 30 seconds per case. Leave the
machine alone while it runs: a busy machine can fail it.

Run from the workspace root after a release build:

  python tests/run_timing.py            all cases
  python tests/run_timing.py window ... only these cases

The exit code is 0 when every case passes.
"""
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "build" / "Release" / "BruceLee.exe"
TARGET_MS = 3 * 19656 / 985248 * 1000.0
MEAN_TOLERANCE = 0.005
STEADY_MS = 3.0
STEADY_SHARE = 0.95
TICKS = 500
SKIP = 20
FLAGS = ["PauseOnFocusLoss=False"]

CASES = {
    "window": ["ShowCRTFilter=False", "FullScreen=False"],
    "crtfull": ["ShowCRTFilter=True", "FullScreen=True"],
    "slowpaint": ["ShowCRTFilter=False", "FullScreen=False", "TimingPaintMs=30"],
}


def run_case(name, args):
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / f"timing_{name}.txt"
        command = [str(EXE), f"TimingLog={log}", f"TimingTicks={TICKS}"] + FLAGS + args
        limit = TICKS * TARGET_MS / 1000.0 * 2 + 20
        try:
            subprocess.run(command, cwd=ROOT, timeout=limit, check=False)
        except subprocess.TimeoutExpired:
            return False, f"did not finish within {limit:.0f} s"
        if not log.exists():
            return False, "wrote no timing log"
        rows = []
        for line in log.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            period, paint = (float(v) for v in line.split())
            rows.append((period, paint))
    rows = rows[SKIP:]
    if not rows:
        return False, "logged no frames"
    periods = [r[0] for r in rows]
    paints = [r[1] for r in rows]
    mean = statistics.fmean(periods)
    steady = sum(1 for p in periods if abs(p - TARGET_MS) <= STEADY_MS) / len(periods)
    summary = (f"mean {mean:.3f} ms (target {TARGET_MS:.3f}), "
               f"{steady * 100:.1f}% within {STEADY_MS:.0f} ms, max {max(periods):.1f} ms, "
               f"paint {statistics.fmean(paints):.1f} ms")
    problems = []
    if abs(mean - TARGET_MS) > TARGET_MS * MEAN_TOLERANCE:
        problems.append("mean is off target")
    if steady < STEADY_SHARE:
        problems.append(f"fewer than {STEADY_SHARE * 100:.0f}% of frames are steady")
    if problems:
        return False, summary + ": " + ", ".join(problems)
    return True, summary


def main():
    if not EXE.exists():
        print(f"missing {EXE}, build release first")
        return 1
    names = sys.argv[1:] or list(CASES)
    unknown = [n for n in names if n not in CASES]
    if unknown:
        print("unknown case: " + " ".join(unknown))
        return 1
    passed = 0
    for name in names:
        ok, text = run_case(name, CASES[name])
        print(f"{'pass' if ok else 'FAIL'} {name}: {text}")
        passed += ok
    print(f"{passed} of {len(names)} passed")
    return 0 if passed == len(names) else 1


if __name__ == "__main__":
    sys.exit(main())
