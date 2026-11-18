"""Build the fighter picture files from the original game's sprite libraries.

Reads the running game's memory from a VICE snapshot and writes, for Bruce,
Yamo, and the ninja, two files in the port's picture format:

  data/<name>.bin       what the hardware sprite shows (copy_sprite_image)
  data/<name>_scan.bin  what overlap_actors scans (expand_library)

Run from the workspace root:

  python tools/extract_pictures.py [snapshot.vsf]

The default snapshot is referencematerial/emulatorsnapshots/room00.vsf.

Library X has its source at $59BD,X (low) and $5A8F,X (high), its height
byte at $5B61,X, and its mode at $5CBF,X. Mode 0 is one source byte per row
and mode 1 is two. The two routines that read a library do not copy the same
number of rows:

  expand_library ($517E) builds the page overlap_actors scans. It stores
  $5B61,X + 1 rows in both modes.

  copy_sprite_image ($26A0) builds the hardware sprite. Mode 0 counts X down
  from $5B61,X to 0, which is $5B61,X + 1 rows. Mode 1 starts X at
  $5B61,X * 2 - 1 and takes two bytes per row, which is $5B61,X rows.

So a mode-1 library (the punches, the extended flying kicks, the duck's
black picture, the late knockdowns) is one row taller in the scan than on
screen. That row is the two source bytes just past the picture.

The port's picture format: 21 rows of 4 bytes, one bit per screen pixel.
Each source bit is two screen pixels. The first source byte fills pixels
0-15, and in mode 1 the second fills pixels 16-31. A pose is two pictures,
the first and second sprite, one after the other.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SNAPSHOT = ROOT / "referencematerial" / "emulatorsnapshots" / "room00.vsf"

ROWS = 21
ROW_BYTES = 4
PICTURE = ROWS * ROW_BYTES

# Relative libraries for each pose, first sprite then second, in the order the
# port numbers poses. The punches store the yellow picture first.
POSES = [
    (0x02, 0x03),
    (0x00, 0x01),
    (0x0E, 0x0F),
    (0x10, 0x11),
    (0x12, 0x13),
    (0x14, 0x15),
    (0x08, 0x09),
    (0x1E, 0x1F),
    (0x20, 0x21),
    (0x22, 0x23),
    (0x24, 0x25),
    (0x26, 0x27),
    (0x28, 0x29),
    (0x05, 0x04),
    (0x07, 0x06),
    (0x16, 0x17),
    (0x18, 0x19),
    (0x1A, 0x1B),
    (0x1C, 0x1D),
    (0x0A, 0x0B),
    (0x0C, 0x0D),
    (0x40, 0x41),
    (0x42, 0x43),
    (0x2A, 0x2B),
    (0x2C, 0x2D),
    (0x2E, 0x2F),
    (0x30, 0x31),
    (0x32, 0x33),
    (0x34, 0x35),
    (0x36, 0x37),
    (0x38, 0x39),
    (0x3A, 0x3B),
    (0x3C, 0x3D),
    (0x3E, 0x3F),
]

# Where a file shows another library than the table above. Bruce's pose 23 is
# his open-air fall, library $44, which choose_pose stores for state $0E when
# hit bit 3 is clear. In yamo.bin (the ninja, base $8C) the first picture of
# pose 8 is his own $44, the open-air fall that his file shows in place of
# the legs.
OVERRIDES = {
    "bruce": {(23, 0): 0x44, (23, 1): 0x45},
    "yamo": {(8, 0): 0x44},
}

# The absolute library base of each file. store_pose adds $59A5's byte for
# the actor: room 0 holds 00 8C 46. ninja.bin is Yamo's set and yamo.bin is
# the ninja's.
FILES = {"bruce": 0x00, "ninja": 0x46, "yamo": 0x8C}


def load_ram(path):
    data = path.read_bytes()
    mark = data.find(b"C64MEM")
    if mark < 0:
        raise SystemExit(f"no C64MEM block in {path}")
    ram = data[mark + 26:mark + 26 + 65536]
    if len(ram) != 65536:
        raise SystemExit(f"short C64MEM block in {path}")
    return ram


def expand(ram, library, scan):
    """One library as a port picture. scan picks expand_library's row count."""
    source = ram[0x59BD + library] | (ram[0x5A8F + library] << 8)
    height = ram[0x5B61 + library]
    mode = ram[0x5CBF + library]
    rows = height + 1 if scan or mode == 0 else height
    step = 2 if mode else 1
    out = bytearray(PICTURE)
    for y in range(min(rows, ROWS)):
        row = [0, 0, 0, 0]
        for half in range(step):
            byte = ram[source + y * step + half]
            for bit in range(8):
                if byte & (0x80 >> bit):
                    for k in range(2):
                        px = half * 16 + bit * 2 + k
                        row[px // 8] |= 0x80 >> (px & 7)
        out[y * ROW_BYTES:(y + 1) * ROW_BYTES] = bytes(row)
    return bytes(out)


def build(ram, name, scan):
    base = FILES[name]
    override = OVERRIDES.get(name, {})
    blob = bytearray()
    for pose, pair in enumerate(POSES):
        for plane in range(2):
            library = override.get((pose, plane), pair[plane])
            blob += expand(ram, base + library, scan)
    return bytes(blob)


def main():
    snapshot = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SNAPSHOT
    ram = load_ram(snapshot)
    for name in FILES:
        for scan, suffix in ((False, ""), (True, "_scan")):
            path = ROOT / "data" / f"{name}{suffix}.bin"
            path.write_bytes(build(ram, name, scan))
            print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
