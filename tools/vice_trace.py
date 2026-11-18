"""Record a reference trace from the original game in VICE.

Starts x64sc (VICE's Commodore 64, which must be on the PATH) with its binary
monitor, loads a snapshot, and runs it one logic frame at a time while it
feeds the stick and fire button from a script or a seed. After each frame it
writes the same lines the port's trace mode writes, for tests/run_traces.py.

  python tools/vice_trace.py SNAPSHOT FRAMES OUT script SCRIPT
  python tools/vice_trace.py SNAPSHOT FRAMES OUT seed N

SNAPSHOT is a .vsf file, OUT is the trace to write, SCRIPT is a stick file
(one hex stick per line, then an optional fire bit), and N is the seed the
port's Seed= takes. Example:

  python tools/vice_trace.py referencematerial/emulatorsnapshots/room04.vsf 100 \\
      tests/reference/hunt04.txt script tests/scripts/hunt.txt

The game stores the stick in $98 at $16BD and the fire button in $9B at
$16CD, from the raster interrupt. Breakpoints there replace A with the
scripted value. A breakpoint at frame ($1BC2) ends each logic frame. Frame 1
uses the first script line, and the interrupts still left before the first
frame get that line too.
"""
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

PORT = 6510
FRAME = 0x1BC2
STICK_STORE = 0x16BD
FIRE_STORE = 0x16CD
# The order the port's Seed= draws sticks from.
DIRS = (0x0F, 0x0E, 0x0D, 0x0B, 0x07, 0x0A, 0x06, 0x09, 0x05)


def next_seed_input(state):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    return state, DIRS[(state >> 24) % 9], (state >> 16) & 1


class Monitor:
    """VICE binary monitor protocol: request, response, and stop events."""

    def __init__(self):
        last = None
        for _ in range(120):
            try:
                self.sock = socket.create_connection(("127.0.0.1", PORT), 2)
                self.sock.settimeout(10)
                break
            except OSError as exc:
                last = exc
                time.sleep(0.25)
        else:
            raise SystemExit(f"no VICE monitor on port {PORT}: {last}")
        self.request_id = 1

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise SystemExit("VICE closed the monitor connection")
            buf += chunk
        return buf

    def receive(self):
        head = self._recv_exact(12)
        length, = struct.unpack_from("<I", head, 2)
        body = self._recv_exact(length) if length else b""
        req, = struct.unpack_from("<I", head, 8)
        return head[6], head[7], req, body

    def send(self, command, body=b""):
        self.request_id += 1
        self.sock.sendall(bytes([2, 2]) + struct.pack("<IIB", len(body), self.request_id, command) + body)
        return self.request_id

    def call(self, command, body=b""):
        rid = self.send(command, body)
        for _ in range(32):
            item = self.receive()
            if item[2] == rid:
                return item
        raise SystemExit(f"no reply to monitor command {command:#x}")

    def read(self, start, end):
        rtype, err, _, body = self.call(0x01, bytes([0]) + struct.pack("<HHBH", start, end, 0, 0))
        if err:
            raise SystemExit(f"memory read {start:#06x} failed")
        n, = struct.unpack_from("<H", body, 0)
        return body[2:2 + n]

    def set_a(self, value):
        self.call(0x32, bytes([0x00, 0x01, 0x00, 0x03, 0x00]) + struct.pack("<H", value))

    def breakpoint(self, address):
        self.call(0x12, struct.pack("<HHBBBB", address, address, 1, 1, 4, 0))

    def run_until(self, addresses):
        """Resume, then return the program counter of the next stop in addresses."""
        self.call(0xAA)
        deadline = time.time() + 20
        while time.time() < deadline:
            rtype, _, _, body = self.receive()
            if rtype != 0x31:
                continue
            count, = struct.unpack_from("<H", body, 0)
            i = 2
            for _ in range(count):
                size = body[i]
                item = body[i + 1:i + 1 + size]
                i += 1 + size
                if len(item) >= 3 and item[0] == 3:
                    pc, = struct.unpack_from("<H", item, 1)
                    if pc in addresses:
                        return pc
                    break
            # Some other stop: keep going.
            self.send(0xAA)
        raise SystemExit("VICE did not reach the next breakpoint")


def load_inputs(mode, value):
    """A function that returns (stick, fire held) for frame 1, 2, ..."""
    if mode == "script":
        rows = []
        for line in Path(value).read_text().splitlines():
            part = line.split()
            if not part or part[0].startswith("#"):
                continue
            rows.append((int(part[0], 16) & 0x0F, int(part[1]) if len(part) > 1 else 0))
        if not rows:
            raise SystemExit(f"empty script {value}")
        return lambda frame: rows[min(frame - 1, len(rows) - 1)], any(bit for _, bit in rows)
    if mode == "seed":
        state = int(value) & 0xFFFFFFFF
        drawn = []

        def seeded(frame):
            nonlocal state
            while len(drawn) < frame:
                state, stick, held = next_seed_input(state)
                drawn.append((stick, held))
            return drawn[frame - 1]

        return seeded, True
    raise SystemExit("the input mode is script or seed")


def record(snapshot, frames, out_path, inputs, uses_fire):
    vice = subprocess.Popen(
        ["x64sc", "+sound", "-warp", "-silent", "-binarymonitor",
         "-binarymonitoraddress", f"ip4://127.0.0.1:{PORT}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(3)
        mon = Monitor()
        name = str(Path(snapshot).resolve()).encode("ascii")
        mon.call(0x42, bytes([len(name)]) + name)
        watch = {FRAME, STICK_STORE}
        mon.breakpoint(FRAME)
        mon.breakpoint(STICK_STORE)
        if uses_fire:
            mon.breakpoint(FIRE_STORE)
            watch.add(FIRE_STORE)

        def feed(frame, pc):
            stick, held = inputs(frame)
            mon.set_a(stick if pc == STICK_STORE else (0 if held else 1))

        # Finish the frame the snapshot is in, with frame 1's input.
        while (pc := mon.run_until(watch)) != FRAME:
            feed(1, pc)
        lines = []
        for frame in range(1, frames + 1):
            # The interrupts inside logic frame N store input N.
            while (pc := mon.run_until(watch)) != FRAME:
                feed(frame, pc)
            zp = mon.read(0x90, 0xD0)

            def b(address):
                return zp[address - 0x90]

            lines.append(f"frame {frame}")
            lines.append(f"bruce {b(0x9E)} {b(0xA1)} {b(0xA4)} {b(0xBF)} {b(0xCE)} {b(0xB6)}")
            lines.append(f"yamo {b(0x96) & 1} {b(0x9F)} {b(0xA2)} {b(0xA5)} {b(0xC0)} {b(0xCF)} {b(0xB7)}")
            lines.append(f"ninja {b(0xA0)} {b(0xA3)} {b(0xA6)} {b(0xC1)} {b(0xD0)} {b(0xB8)}")
        Path(out_path).write_text("\n".join(lines) + "\n")
        mon.send(0xBB)
    finally:
        try:
            vice.wait(timeout=5)
        except subprocess.TimeoutExpired:
            vice.kill()


def main():
    if len(sys.argv) != 6:
        raise SystemExit(__doc__)
    snapshot, frames, out_path, mode, value = sys.argv[1:]
    inputs, uses_fire = load_inputs(mode, value)
    record(snapshot, int(frames), out_path, inputs, uses_fire)
    print("wrote", out_path)


if __name__ == "__main__":
    main()
