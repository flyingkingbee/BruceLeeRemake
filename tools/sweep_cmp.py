"""Run one stick script from many snapshots in VICE and the port, and compare.

  python tools/sweep_cmp.py SCRIPT FRAMES SNAPSHOT... [--record] [--poke ADDR=VAL]...

SCRIPT is a stick file such as tests/scripts/fight2.txt. Each SNAPSHOT is a
stem in referencematerial/emulatorsnapshots, such as room04 or "room05 2".
With --record, each snapshot is first recorded in VICE through
tools/vice_debug.sh (allow about a minute per snapshot); without it, the VICE
traces from an earlier --record run are reused. The traces go to
tmp/sweep_<script>_vice_<stem>.txt and tmp/sweep_<script>_port_<stem>.txt.

--poke changes a byte of each snapshot's memory first, both hex, for example
--poke 42CA=1 for a human opponent or --poke 40=1 for the harder second
round. VICE runs a changed copy written to tmp/, the port gets the same change as
Poke=ADDR:VAL, and the traces are named after the pokes. A script line's third and fourth columns are the other
joystick and its button, which a human opponent plays Yamo with.

For each snapshot it prints the alignment and the first frame where the
bodies (as tests/run_traces.py compares them), the health or the score and
lives differ, or None if the whole trace matches. Check whether a mismatch is
raster timing (see "Testing against the original" in DESIGN.md) before adding
the trace with tools/add_trace_case.py, capped with --frames if it is.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from add_trace_case import ROOT, past_stick_read, read_snapshot

EXE = ROOT / "build" / "Release" / "BruceLee.exe"
SNAPS = ROOT / "referencematerial" / "emulatorsnapshots"
TMP = ROOT / "tmp"


def frames(path):
    out = []
    for line in open(path, errors="replace"):
        p = line.split()
        if not p:
            continue
        if p[0] == "frame":
            out.append({"f": int(p[1])})
        elif out and p[0] in ("bruce", "yamo", "ninja", "hp", "score", "opp"):
            out[-1][p[0]] = [int(v) for v in p[1:]]
    return out


def core(who, v):
    if who == "yamo":
        return tuple(v[:7])
    if who in ("bruce", "ninja"):
        return tuple(v[:5]) + (v[6],) if len(v) == 7 else tuple(v[:6])
    if who == "opp":
        # The idle count in the middle follows the raster, so it can drift.
        return (v[0], v[2])
    if who == "hp":
        return tuple(x & 0xFF for x in v[:3])
    return tuple(v[:2])


def compare(port, vice, shift):
    for i, v in enumerate(vice):
        j = i + shift
        if j < 0 or j >= len(port):
            continue
        p = port[j]
        for who in ("bruce", "yamo", "ninja", "hp", "score", "opp"):
            if who not in v or who not in p:
                continue
            a, b = core(who, p[who]), core(who, v[who])
            if who == "yamo" and not a[0] and not b[0]:
                continue
            # A new game leaves the ninja's bytes at 0 until he is placed.
            if who == "ninja" and not any(v[who]):
                continue
            if who == "hp" and "ninja" in v and not any(v["ninja"]):
                a, b = a[:2], b[:2]
            if a != b:
                return v["f"], who, a, b
    return None


def poke_snapshot(snap, pokes, out):
    data = bytearray(snap.read_bytes())
    mem = data.find(b"C64MEM") + 26
    for addr, value in pokes:
        data[mem + addr] = value
    out.write_bytes(data)
    return out


def record(script, nframes, snap, out):
    rc = subprocess.run(["bash", "tools/vice_debug.sh", "script", str(nframes), str(script), str(snap)],
                        cwd=ROOT).returncode
    if rc:
        return False
    shutil.copy(TMP / f"oracle_vice_{script.stem}.txt", out)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("script", type=Path)
    parser.add_argument("frames", type=int)
    parser.add_argument("snapshots", nargs="+")
    parser.add_argument("--record", action="store_true", help="record the VICE traces first")
    parser.add_argument("--poke", action="append", default=[], help="ADDR=VAL in hex")
    args = parser.parse_args()
    pokes = [tuple(int(v, 16) for v in p.split("=")) for p in args.poke]
    poke_tag = "".join(f"_{a:04X}-{v:02X}" for a, v in pokes)

    TMP.mkdir(exist_ok=True)
    script = args.script.resolve()
    lines = script.read_text().splitlines()
    lag = TMP / f"{script.stem}_lag.txt"
    lag.write_text("\n".join([lines[0]] + lines) + "\n")

    for stem in args.snapshots:
        orig = SNAPS / f"{stem}.vsf"
        snap = orig
        tag = stem.replace(" ", "_") + poke_tag
        if pokes:
            snap = poke_snapshot(snap, pokes, TMP / f"{tag}.vsf")
        vice = TMP / f"sweep_{script.stem}_vice_{tag}.txt"
        if args.record and not record(script, args.frames, snap, vice):
            print(f"{stem:22} VICE run failed")
            continue
        if not vice.exists():
            print(f"{stem:22} no VICE trace, run with --record")
            continue
        pc, room = read_snapshot(snap)
        shift = 0 if past_stick_read(pc) else 1
        port = TMP / f"sweep_{script.stem}_port_{tag}.txt"
        subprocess.run([str(EXE), "PauseOnFocusLoss=False", "FixBugsInOriginal=False",
                        "InfiniteLives=False", f"Oracle=room{17 if room == 18 else room:02d}",
                        f"Frames={args.frames + shift}", f"Script={script if shift == 0 else lag}",
                        f"Snap={orig}", f"Out={port}"] + [f"Poke={a:X}:{v:X}" for a, v in pokes],
                       cwd=ROOT)
        v = frames(vice)
        print(f"{stem:22} shift {shift} vice {len(v)} first {compare(frames(port), v, shift)}")


if __name__ == "__main__":
    sys.exit(main())
