"""Find the correct state-read order and start for a frame's sequence bitstream.

Tries every start/end pair and every permutation of the three initial-state
reads, reporting combinations that decode to the expected literal/match lengths.
"""
import itertools
import sys

sys.path.insert(0, "tools")
from fse_ref import Rev, build_dtable
from seq_brute import LL, ML, OF, LL_BASE, LL_BITS, ML_BASE, ML_BITS

llt = build_dtable({i: v for i, v in enumerate(LL)}, 6)
mlt = build_dtable({i: v for i, v in enumerate(ML)}, 6)
oft = build_dtable({i: v for i, v in enumerate(OF)}, 5)
LOG = {"ll": 6, "of": 5, "ml": 6}
TBL = {"ll": llt, "of": oft, "ml": mlt}

def attempt(data, start, end, order):
    r = Rev(data, start, end)
    st = {}
    for key in order:
        st[key] = r.read(LOG[key])
    e = {k: TBL[k][st[k]] for k in st}
    llc, ofc, mlc = e["ll"][0], e["of"][0], e["ml"][0]
    off_val = (1 << ofc) + r.read(ofc)
    ml = ML_BASE[mlc] + r.read(ML_BITS[mlc])
    ll = LL_BASE[llc] + r.read(LL_BITS[llc])
    return ll, ml, off_val, (llc, ofc, mlc)

def main():
    data = open(sys.argv[1], "rb").read()
    want = (int(sys.argv[2]), int(sys.argv[3]))
    hits = []
    for start in range(8, len(data)):
        for end in range(start, len(data)):
            if end >= len(data) or data[end] == 0:
                continue
            for order in itertools.permutations(("ll", "of", "ml")):
                try:
                    ll, ml, off, codes = attempt(data, start, end, order)
                except Exception:
                    continue
                if (ll, ml) == want:
                    hits.append((start, end, order, ll, ml, off, codes))
    if not hits:
        print("no combination gives ll=%d ml=%d" % want)
    for h in hits[:12]:
        print("start=%d end=%d order=%s ll=%d ml=%d offVal=%d codes=%s" % h)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
