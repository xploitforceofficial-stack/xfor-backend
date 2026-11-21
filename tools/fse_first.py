"""Find the FSE weight stream's lower bound for a frame, scored on real output.

The backward FSE reader's exhaustion point (`first`) is not stated directly by
the format, and getting it wrong yields a plausible-looking but wrong weight
set. The decoded literals are the first Regenerated_Size bytes of the known
decompressed output, so a candidate bound is verifiable: keep the one whose
literals match exactly.

The normalized distribution and its tableLog come from the Luau decoder, whose
NCount parse is verified independently (it yields a whole huffman tree).
"""
import sys

sys.path.insert(0, "tools")
from fse_ref import Rev, build_dtable, highbit
from lit_ref import build_huff

NORM = {0: 11, 1: 5, 2: 5, 3: 4, 4: 4, 5: 2, 6: 1}
MAX_SYM = 6
TLOG = 5

def weights_from(data, first, last, tbl, tlog):
    rst = Rev(data, first, last)
    s1 = rst.read(tlog)
    s2 = rst.read(tlog)
    w = [0]
    while len(w) < 400:
        e1 = tbl[s1]
        w.append(e1[0])
        s1 = e1[1] + rst.read(e1[2])
        if rst.over:
            w.append(tbl[s2][0])
            return w
        e2 = tbl[s2]
        w.append(e2[0])
        s2 = e2[1] + rst.read(e2[2])
        if rst.over:
            w.append(tbl[s1][0])
            return w
    return None

def main():
    data = open(sys.argv[1], "rb").read()
    expected = open(sys.argv[2], "rb").read()

    lit_start = 16
    isize = data[lit_start]
    fse_last = lit_start + isize
    regen = 2732
    comp = 2003
    lit_end = lit_start - 4 + 4 + comp - 1

    tbl = build_dtable(NORM, TLOG)
    jt = fse_last + 1
    sizes = [int.from_bytes(data[jt + i * 2:jt + i * 2 + 2], "little") for i in range(3)]
    sizes.append((lit_end - (jt + 6) + 1) - sum(sizes))
    seg = (regen + 3) // 4
    targets = [seg, seg, seg, regen - 3 * seg]

    found = []
    for first in range(1, fse_last + 1):
        w = weights_from(data, first, fse_last, tbl, TLOG)
        if not w:
            continue
        n = len(w) - 1
        dt, tlog = build_huff(w, n)
        if not dt:
            continue
        out = bytearray()
        sp = jt + 6
        ok = True
        for i in range(4):
            sEnd = sp + sizes[i] - 1
            try:
                r = Rev(data, sp, sEnd)
            except Exception:
                ok = False
                break
            for _ in range(targets[i]):
                idx = r.peek(tlog)
                e = dt[idx]
                if not e:
                    ok = False
                    break
                r.skip(e[1])
                out.append(e[0])
            if not ok:
                break
            sp = sEnd + 1
        if ok and bytes(out) == expected[:regen]:
            found.append((first, n, tlog))
            print("MATCH first=%d weights=%d tableLog=%d" % (first, n, tlog))
    if not found:
        print("no first value reproduces the literals (tried 1..%d)" % fse_last)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
