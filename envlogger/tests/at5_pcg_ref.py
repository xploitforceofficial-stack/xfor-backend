"""Reference implementation of Luau's math.random PCG (lmathlib.cpp).

Verifies the at5 fixture's 17 pinned Random values and decides Clone semantics:
  (a) copy state, no advance
  (b) advance one pcg draw, then copy
  (c) advance one float (2 draws), then copy

lmathlib.cpp:
  PCG32_INC = 105
  pcg32_random: old=s; s = old*6364136223846793005 + 105;
                x = uint32(((old>>18)^old)>>27); rot = uint32(old>>59);
                return rotr32(x, rot)
  pcg32_seed:   s=0; draw(); s+=seed; draw()
  math.random() : rl=draw(); rh=draw(); ldexp(rl | rh<<32, -64)
  math.random(l,u): x=(uint32(u)-uint32(l)+1)*draw(); r = l + (x>>32)
"""
M64 = (1 << 64) - 1
MULT = 6364136223846793005
INC = 105

def step(s):
    return (s * MULT + INC) & M64

def out32(s):
    x = (((s >> 18) ^ s) >> 27) & 0xFFFFFFFF
    rot = (s >> 59) & 31
    return ((x >> rot) | (x << ((-rot) & 31))) & 0xFFFFFFFF

class R:
    def __init__(self, seed):
        s = 0
        s = step(s)
        s = (s + (seed & M64)) & M64
        s = step(s)
        self.s = s

    def next32(self):
        o = out32(self.s)
        self.s = step(self.s)
        return o

    def number(self):
        rl = self.next32()
        rh = self.next32()
        return (rl + rh * (1 << 32)) / (1 << 64)

    def integer(self, lo, hi):
        o = self.next32()
        span = (hi - lo + 1) & 0xFFFFFFFF
        x = (span * o) & M64
        return lo + (x >> 32)

    def clone(self, mode):
        c = R.__new__(R)
        if mode == "copy":
            c.s = self.s
        elif mode == "step":
            self.next32()
            c.s = self.s
        elif mode == "float":
            self.number()
            c.s = self.s
        else:
            raise ValueError(mode)
        return c

V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
V7 = 1338
V8 = 0.010722157288309652
V10 = 0.9163096810250362
V11 = 0.7297156848095374
V13 = 0.17877278448733477
V14 = 665
V15 = 0.17877278448733477
V16 = 785
V17 = 826

for mode in ("copy", "step", "float"):
    orig = R(177465824)
    bad = []
    v1 = orig.number()
    if v1 != V1: bad.append(f"v1 {v1!r}")
    v2 = orig.integer(189, 1164)
    if v2 != 889: bad.append(f"v2 {v2}")
    v3 = orig.number()
    if v3 != V3: bad.append(f"v3 {v3!r}")
    v4 = orig.number()
    if v4 != V4: bad.append(f"v4 {v4!r}")
    v5 = orig.integer(75, 497)
    if v5 != 340: bad.append(f"v5 {v5}")
    clone1 = orig.clone(mode)
    v7 = orig.integer(979, 1379)
    if v7 != V7: bad.append(f"v7 {v7}")
    v8 = clone1.number()
    if v8 != V8: bad.append(f"v8 {v8!r}")
    clone2 = orig.clone(mode)
    v10 = clone2.number()
    if v10 != V10: bad.append(f"v10 {v10!r}")
    v11 = clone2.number()
    if v11 != V11: bad.append(f"v11 {v11!r}")
    clone3 = clone2.clone(mode)
    v13 = clone3.number()
    if v13 != V13: bad.append(f"v13 {v13!r}")
    v14 = clone3.integer(35, 888)
    if v14 != V14: bad.append(f"v14 {v14}")
    v15 = clone2.number()
    if v15 != V15: bad.append(f"v15 {v15!r}")
    v16 = clone2.integer(721, 807)
    if v16 != V16: bad.append(f"v16 {v16}")
    v17 = clone3.integer(353, 1335)
    if v17 != V17: bad.append(f"v17 {v17}")
    status = "ALL 17 MATCH" if not bad else f"{len(bad)} mismatches"
    print(f"clone={mode:5s}: {status}")
    for b in bad:
        print("   ", b)

r = R(177465824)
print("\nseeded state hi/lo: 0x%08X 0x%08X" % (r.s >> 32, r.s & 0xFFFFFFFF))
r.number(); r.integer(189, 1164)
print("after v1+v2:        0x%08X 0x%08X" % (r.s >> 32, r.s & 0xFFFFFFFF))
