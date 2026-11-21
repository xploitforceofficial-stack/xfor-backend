"""Find where the sequence bitstream really starts for one frame.

The state reads look self-consistent but produce the wrong literal length, so
try every plausible start position and report which one decodes to the expected
(literal length, match length, offset).
"""
import sys

sys.path.insert(0, "tools")
from fse_ref import Rev, build_dtable

LL = [4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
      2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1]
ML = [1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      -1, -1, -1, -1, -1]
OF = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1]

LL_BASE = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
           16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024,
           2048, 4096, 8192, 16384, 32768, 65536]
LL_BITS = [0] * 16 + [1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
ML_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
           19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
           35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027,
           2051, 4099, 8195, 16387, 32771, 65539]
ML_BITS = [0] * 32 + [1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

llt = build_dtable({i: v for i, v in enumerate(LL)}, 6)
mlt = build_dtable({i: v for i, v in enumerate(ML)}, 6)
oft = build_dtable({i: v for i, v in enumerate(OF)}, 5)

def try_start(data, start, end):
    if end >= len(data) or end < start or data[end] == 0:
        return None
    r = Rev(data, start, end)
    try:
        lls = r.read(6)
        ofs = r.read(5)
        mls = r.read(6)
    except Exception:
        return None
    lle, ofe, mle = llt[lls], oft[ofs], mlt[mls]
    llc, ofc, mlc = lle[0], ofe[0], mle[0]
    off_val = (1 << ofc) + r.read(ofc)
    ml = ML_BASE[mlc] + r.read(ML_BITS[mlc])
    ll = LL_BASE[llc] + r.read(LL_BITS[llc])
    return (llc, ofc, mlc, ll, ml, off_val)

def main():
    data = open(sys.argv[1], "rb").read()
    want_ll = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    want_ml = int(sys.argv[3]) if len(sys.argv) > 3 else 22
    for start in range(10, len(data)):
        for end in range(start, len(data)):
            res = try_start(data, start, end)
            if res and res[3] == want_ll and res[4] == want_ml:
                print("start=%d end=%d llc=%d ofc=%d mlc=%d ll=%d ml=%d offVal=%d"
                      % (start, end, res[0], res[1], res[2], res[3], res[4], res[5]))

if __name__ == "__main__":
    raise SystemExit(main())
