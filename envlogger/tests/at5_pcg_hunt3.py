"""PCG sweep, take 3: canonical pcg32_srandom seeding.

    state = 0; inc = (seq << 1) | 1
    step(); state += initstate; step()      -- both outputs discarded
Sweep seq over small ids + derived values, then discard 0..8 more.
"""
M32 = 0xFFFFFFFF
M64 = (1 << 64) - 1
MULT = 6364136223846793005

SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
INT_LO, INT_HI, INT_WANT = 189, 1164, 889

def rotr32(x, r):
    r &= 31
    return ((x >> r) | (x << ((32 - r) & 31))) & M32

def pcg32(seq, initstate, discard, n):
    state = 0
    inc = ((seq << 1) | 1) & M64
    def step():
        nonlocal state
        old = state
        state = (old * MULT + inc) & M64
        x = (((old >> 18) ^ old) >> 27) & M32
        return rotr32(x, old >> 59)
    step()
    state = (state + (initstate & M64)) & M64
    step()
    for _ in range(discard):
        step()
    return [step() for _ in range(n)]

seqs = list(range(0, 64)) + [
    0x853C49E6748FEA9B & 0xFFFF, SEED, SEED & 0xFFFF, 54, 0x9E3779B9 & 0xFFFF,
    0x9E3779B97F4A7C15 & 0xFFFF, 1, 2, 3,
]
initstates = [SEED, SEED & M32, SEED * 2, SEED ^ 0x9E3779B9, 54, SEED | 1]

hits = []
for seq in seqs:
    for init in initstates:
        for discard in range(0, 9):
            w = pcg32(seq, init, discard, 6)
            convs = [
                ("hi53", (w[0] >> 5) * 2.0 ** -53),
                ("lo53", (w[0] / 64.0) * 2.0 ** -26),
                ("hi32", w[0] / 2.0 ** 32),
                ("pair53", (w[0] * 4294967296.0 + w[1]) / 9007199254740992.0),
                ("pair64", (w[0] * 4294967296.0 + w[1]) / 18446744073709551616.0),
            ]
            for cname, u1 in convs:
                if u1 == V1:
                    print("*** MATCH:", seq, init, discard, cname)
                    hits.append((seq, init, discard, cname))
                elif abs(u1 - V1) < 1e-7:
                    print("near:", seq, init, discard, cname, u1)

if not hits:
    print("no match in pcg32_srandom sweep")
