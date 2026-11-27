"""Run every regression test: the VICE trace cases, the save games, then the
real-time timing cases.

  tests/run_traces.py   compares the port with the original game frame by frame
  tests/run_saves.py    checks that loading a save plays on exactly as the game did
  tests/run_timing.py   checks that the game runs at the original speed

The trace cases take about a minute, and the save checks about two. Neither
depends on the machine. The
timing cases open a real window for about three minutes, and a busy machine
can fail them, so leave it alone while they run. --no-timing runs only the
trace cases.

Run from the workspace root after a release build:

  python tests/run_all.py
  python tests/run_all.py --no-timing

The exit code is 0 when every test passes.
"""
import subprocess
import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parent


def run(script):
    print(f"== {script}", flush=True)
    return subprocess.run([sys.executable, str(TESTS / script)], check=False).returncode == 0


def main():
    args = sys.argv[1:]
    unknown = [a for a in args if a != "--no-timing"]
    if unknown:
        print("unknown option: " + " ".join(unknown))
        return 1
    suites = ["run_traces.py", "run_saves.py"]
    if "--no-timing" not in args:
        suites.append("run_timing.py")
    failed = [s for s in suites if not run(s)]
    print()
    if failed:
        print("FAILED: " + " ".join(failed))
        return 1
    print("all suites passed: " + " ".join(suites))
    return 0


if __name__ == "__main__":
    sys.exit(main())
