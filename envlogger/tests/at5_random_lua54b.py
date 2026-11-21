"""Round 2 of the Random fingerprint hunt.

Deduction from exact-mantissa analysis:
  v1 -> 53-bit mantissa, v3 -> 58-bit, v8 -> 59-bit.
Only conversions that preserve the LOW bits of a full 64-bit word survive:
  u * 2^-64            (Lua 5.4 math.random float path)
  (hi*2^32 + lo)*2^-64 (Lua 5.4 32-bit platform path, two draws per float)
Any (u >> k) * 2^-k form is impossible for v3/v8.

Lua 5.4 setseed(): state = [n1, 0xff, n2, 0], then 16 warm-up draws.
Luau's math.random is this exact generator, so Roblox's Random may share it.
My earlier probe used 0x9e0d42d3 in slot 1 -- wrong constant, never tested 0xff.
"""
M64 = (1 << 64) - 1
M32 = 0xFFFFFFFF

SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
INT_LO, INT_HI, INT_WANT = 189, 1164, 889

def rotl64(x, k):
    k %= 64
    if k == 0:
        return x
    return ((x << k) | (x >> (64 - k))) & M64

def xoshiro256ss_stream(state, discard, n):
    s = [w & M64 for w in state]
    for _ in range(discard):
        r = (rotl64((s[1] * 5) & M64, 7) * 9) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl64(s[3], 45)
    out = []
    for _ in range(n):
        r = (rotl64((s[1] * 5) & M64, 7) * 9) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl64(s[3], 45)
        out.append(r)
    return out

def rotl32(x, k):
    k &= 31
    return ((x << k) | (x >> ((32 - k) & 31))) & M32

def xoshiro128ss_stream(state, discard, n):
    s = [w & M32 for w in state]
    def step():
        r = (rotl32((s[1] * 5) & M32, 7) * 9) & M32
        t = (s[1] << 9) & M32
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl32(s[3], 11)
        return r
    for _ in range(discard):
        step()
    return [step() for _ in range(n)]

hits = []

N2 = {"0": 0, "seed": SEED, "ff": 0xFF, "one": 1, "const": 0x9E0D42D3}
for n2name, n2 in N2.items():
    st = [SEED, 0xFF, n2, 0]
    for discard in range(0, 49):
        w = xoshiro256ss_stream(st, discard, 5)
        convs = (
            ("u64", [(w[0]) * 2.0 ** -64, (w[1]) * 2.0 ** -64, (w[2]) * 2.0 ** -64, (w[3]) * 2.0 ** -64]),
            ("pair_hi", [((w[0] << 32) | w[1]) * 2.0 ** -64, ((w[2] << 32) | w[3]) * 2.0 ** -64]),
            ("pair_lo", [((w[1] << 32) | w[0]) * 2.0 ** -64, ((w[3] << 32) | w[2]) * 2.0 ** -64]),
        )
        for cname, us in convs:
            if us[0] == V1:
                ui = INT_LO + int(us[1] * (INT_HI - INT_HI and INT_HI - INT_LO or 1))
                print("*** HIT A", n2name, discard, cname, "| v3:", us[1] == V3 or us[2] == V3,
                      "| v4:", us[2] == V4 or us[3] == V4)
                hits.append(("A64", n2name, discard, cname))

for n2name, n2 in N2.items():
    st = [SEED & M32, 0xFF, n2 & M32, 0]
    for discard in range(0, 49):
        w = xoshiro128ss_stream(st, discard, 6)
        pair_hi = [((w[0] << 32) | w[1]) * 2.0 ** -64,
                   ((w[2] << 32) | w[3]) * 2.0 ** -64,
                   ((w[4] << 32) | w[5]) * 2.0 ** -64]
        pair_lo = [((w[1] << 32) | w[0]) * 2.0 ** -64,
                   ((w[3] << 32) | w[2]) * 2.0 ** -64,
                   ((w[5] << 32) | w[4]) * 2.0 ** -64]
        for cname, us in (("pair_hi", pair_hi), ("pair_lo", pair_lo)):
            if us[0] == V1:
                print("*** HIT B", n2name, discard, cname, "| v3:", us[1] == V3, "| v4:", us[2] == V4)
                hits.append(("B32", n2name, discard, cname))

def splitmix64(x):
    x = (x + 0x9E3779B97F4A7C15) & M64
    z = x
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return x, (z ^ (z >> 31)) & M64

for layout in ("n1h_n2l", "n1l_n2h", "both", "first"):
    s = SEED
    words = []
    for _ in range(2):
        s, z = splitmix64(s)
        words.append(z)
    if layout == "n1h_n2l":
        n1, n2 = words[0], words[1]
    elif layout == "n1l_n2h":
        n1, n2 = words[1], words[0]
    elif layout == "both":
        n1 = n2 = words[0]
    else:
        n1, n2 = words[0], 0
    st = [n1, 0xFF, n2, 0]
    for discard in range(0, 33):
        w = xoshiro256ss_stream(st, discard, 5)
        us = [wi * 2.0 ** -64 for wi in w]
        if us[0] == V1:
            print("*** HIT C", layout, discard, "| v3:", us[1] == V3, "| v4:", us[2] == V4)
            hits.append(("C", layout, discard, "u64"))

if not hits:
    print("no hit in Lua-5.4-seeding families")
else:
    print(len(hits), "hits")
