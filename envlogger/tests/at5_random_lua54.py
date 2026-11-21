"""Test Lua 5.4's math.random seeding scheme (and neighbors) for Roblox Random.

Lua 5.4 setseed():
    s[0] = (n1 == 0) ? 0x9e0d42d3 : n1
    s[1] = 0x9e0d42d3
    s[2] = n2
    s[3] = 0
    discards 16 outputs
and math.random() == (double)rv * 0x1p-64  (all 64 bits, not >>11).
"""
M64 = (1 << 64) - 1
SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def xoshiro256ss(s):
    r = (rotl((s[1] * 5) & M64, 7) * 9) & M64
    t = (s[1] << 17) & M64
    s[2] ^= s[0]
    s[3] ^= s[1]
    s[1] ^= s[2]
    s[0] ^= s[3]
    s[2] ^= t
    s[3] = rotl(s[3], 45)
    return r

def run(state, discards, n=4):
    s = list(state)
    for _ in range(discards):
        xoshiro256ss(s)
    outs = []
    for _ in range(n):
        outs.append(xoshiro256ss(s))
    return outs

def convs(r):
    return {
        "r*2^-64": r / (2.0 ** 64),
        "r>>11*2^-53": (r >> 11) * (2.0 ** -53),
    }

CONST = 0x9e0d42d3
candidates = {
    "lua54": [SEED, CONST, 0, 0],
    "lua54_swap": [SEED, 0, CONST, 0],
    "lua54_s1s0": [CONST, SEED, 0, 0],
    "lua54_n1n2hi": [SEED, CONST, (SEED >> 32) & 0xFFFFFFFF, 0],
    "lua54_dup": [SEED, CONST, SEED, 0],
    "lua54_rev": [0, CONST, SEED, 0],
}

hits = []
for name, st in candidates.items():
    for disc in [0, 1, 4, 8, 16, 17, 32, 64]:
        outs = run(st, disc)
        for cname in ("r*2^-64", "r>>11*2^-53"):
            c = [convs(r)[cname] for r in outs]
            if c[0] == V1:
                hits.append((name, disc, cname))
                print("MATCH a1:", name, "discard", disc, cname)
                print("   a3 =", c[2], "want", V3, c[2] == V3)
                print("   a4 =", c[3], "want", V4, c[3] == V4)
                if c[2] == V3 and c[3] == V4:
                    print("   *** FULL SEQUENCE MATCH ***")
                    print("   a2 -> NextInteger(189,1164) =",
                          189 + int(c[1] * (1164 - 189 + 1)))

if not hits:
    print("no Lua-5.4-seeding match")

for pad_name, pad in {"0": 0, "const": CONST, "1": 1,
                      "golden": 0x9E3779B97F4A7C15}.items():
    for lay in range(4):
        st = [0, 0, 0, 0]
        st[lay] = SEED
        for i in range(4):
            if i != lay and st[i] == 0:
                st[i] = pad
        for disc in [0, 16]:
            outs = run(st, disc)
            for cname in ("r*2^-64", "r>>11*2^-53"):
                c = [convs(r)[cname] for r in outs]
                if c[0] == V1:
                    print("layered MATCH:", pad_name, lay, disc, cname,
                          c[2] == V3, c[3] == V4)
