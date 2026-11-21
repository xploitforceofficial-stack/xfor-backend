"""Recover Roblox Random's exact PCG XSH-RR state from the fixture's v1.

Given: v1 = 0.9598971928030796 is an exact multiple of 2^-64, consistent with
NextNumber() = (hi * 2^32 + lo) * 2^-64 where hi, lo are two consecutive 32-bit
XSH-RR outputs.

XSH-RR output: out = rotr32(((old >> 18) ^ old) >> 27, old >> 59)
Key inversion fact: X = (old>>18) ^ old has
    X bit k = old bit k          for k >= 46 (since k+18 > 63)
    X bit k = old bit k+18 ^ old bit k   for k < 46
so old bits 63..46 come free from X, and old bits 45..0 follow by downward
recurrence: old bit k = X bit k ^ old bit k+18.
y = X >> 27 is known from the output (after un-rotating), leaving X bits 18..26
(9 bits) unknown -> 2^9 * 64 rotations = 4608 candidates. Verify each by
stepping the LCG and checking the second output. False positives: ~4608/2^32.
"""
M64 = (1 << 64) - 1
M32 = 0xFFFFFFFF
MULT = 6364136223846793005
INCS = (1442695040888963407, 0, 1, 0x853C49E6748FEA9B)

V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
V8 = 0.010722157288309652
V10 = 0.9163096810250362
V11 = 0.7297156848095374
V13 = 0.17877278448733477

u_pair = (V1 * (2 ** 64))
assert u_pair == int(u_pair), "v1 not a multiple of 2^-64"
u_pair = int(u_pair)
assert u_pair < (1 << 64)

def rotr32(x, r):
    r &= 31
    return ((x >> r) | (x << ((32 - r) & 31))) & M32 if r else x

def rotl32(x, r):
    r &= 31
    return ((x << r) | (x >> ((32 - r) & 31))) & M32 if r else x

def xsh_rr(old):
    x = ((old >> 18) ^ old) & M64
    y = (x >> 27) & M32
    return rotr32(y, old >> 59)

def recover_pair(u_first, u_second):
    """Find 64-bit `old` with xsh_rr(old)=u_first and xsh_rr(step(old))=u_second."""
    cands = []
    for rot in range(0, 64):
        y = rotl32(u_first, rot)
        X_hi = y << 27
        for low9 in range(0, 1 << 9):
            X = X_hi | low9

            old = 0

            for k in range(63, 45, -1):
                if (X >> k) & 1:
                    old |= 1 << k

            for k in range(45, -1, -1):
                bit = ((X >> k) & 1) ^ ((old >> (k + 18)) & 1)
                if bit:
                    old |= 1 << k

            if xsh_rr(old) != u_first:
                continue
            cands.append(old)

    for inc in INCS:
        for old in cands:
            nxt = (old * MULT + inc) & M64
            if xsh_rr(nxt) == u_second:
                yield old, inc, nxt

def lcg_inv(state, inc):

    inv = pow(MULT, -1, 1 << 64)
    return ((state - inc) * inv) & M64

found = []
for order in ("hi_first", "lo_first"):
    if order == "hi_first":
        a, b = u_pair >> 32, u_pair & M32
    else:
        a, b = u_pair & M32, u_pair >> 32
    print("order %s: outputs 0x%08x 0x%08x" % (order, a, b))
    for old, inc, nxt in recover_pair(a, b):
        print("  RECOVERED state old=0x%016x inc=%d" % (old, inc))
        found.append((old, inc, order))

if not found:
    print("no state recovered")
else:
    old, inc, order = found[0]
    print("\n--- verifying full sequence from state old=0x%016x inc=%d (%s) ---"
          % (old, inc, order))
    s = old
    draws = []
    for _ in range(16):
        draws.append(xsh_rr(s))
        s = (s * MULT + inc) & M64

    def pair(i):
        return (draws[i] * 2 ** 32 + draws[i + 1]) * 2.0 ** -64

    print("pair-based NextNumbers (2 draws each):")
    for i in range(0, 14, 2):
        print("  draw pair %d: %.17g" % (i // 2, pair(i)))
    print("targets: v1=0.9598971928030796 v3=0.027539190730015265 v4=0.3377740061710911")
    print("backwards from old1 (seeding hunt), inc=%d:" % inc)
    st = old
    for k in range(0, 17):
        tag = ""
        if st == 177465824:
            tag = " == SEED"
        if (st >> 32) == 177465824:
            tag = " hi32 == SEED"
        if (st & M32) == 177465824:
            tag = " lo32 == SEED"
        if st == 0:
            tag = " == 0"
        print("  back %2d: 0x%016x%s" % (k, st, tag))
        st = lcg_inv(st, inc)
