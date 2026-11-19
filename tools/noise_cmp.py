"""Line up the original's and the port's noise_byte reads to find where they part.

  python tools/noise_cmp.py VICE_LOG PORT_LOG SHIFT [LIMIT]

VICE_LOG is a tools/vice_debug.py trace run with the noise flag. PORT_LOG is
the port's tmp/port_nb.txt, which trace mode writes when it is run without
Out=. SHIFT is the case's alignment (0 or 1, see tools/add_trace_case.py).
Reads are matched by the noise counter at $16, so a read the port makes on a
different frame still pairs up. Prints the first LIMIT mismatches (default
12) and the total.

The number at the start of each line folds in how often $16 has wrapped; the
address printed after it is the byte read, (counter mod 256) + Y. A first
mismatch with no death before it is usually a zero-page or page-1 byte the
port never mirrors with NoisePoke.
"""
import sys


def load(path):
    out = []
    for line in open(path):
        words = line.split()
        if words and words[0] == "nb":
            out.append(tuple(int(x) for x in words[1:]))
    return out


def by_counter(reads, shift):
    out = {}
    base = 0
    last = -1
    for y, a, lo, hi, frame in reads:
        if lo < last - 100:
            base += 256
        last = lo
        out[base + lo] = (y, a, frame - shift)
    return out


def main():
    vice = by_counter(load(sys.argv[1]), 0)
    port = by_counter(load(sys.argv[2]), int(sys.argv[3]))
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 12
    bad = 0
    for k in sorted(set(vice) | set(port)):
        a = vice.get(k)
        b = port.get(k)
        if not (a and b and a[:2] == b[:2]):
            bad += 1
            if bad <= limit:
                print(k, "addr", hex((k + (a or b)[0]) & 0xFFFF), "vice", a, "port", b)
    print("mismatched", bad, "vice reads", len(vice))


if __name__ == "__main__":
    main()
