"""PRNG sweep, corrected alignment.

The fixture's sequence is:
  v1 = NextNumber()            -> raw #1
  v2 = NextInteger(189,1164)   -> raw #2
  v3 = NextNumber()            -> raw #3
  v4 = NextNumber()            -> raw #4

So the raw outputs to match are #1, #3, #4 (NOT three consecutive words).
Previous sweeps compared consecutive words and therefore could never hit.
"""
M64 = (1 << 64) - 1
SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
V2 = 889

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def splitmix64(s):
    s = (s + 0x9E3779B97F4A7C15) & M64
    z = s
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return s, (z ^ (z >> 31)) & M64

def splitmix_seq(seed, n):
    out, s = [], seed & M64
    for _ in range(n):
        s, z = splitmix64(s)
        out.append(z)
    return out

def mk_xoshiro256(kind):
    def step(s):
        if kind == "ss":
            r = (rotl((s[1] * 5) & M64, 7) * 9) & M64
        elif kind == "pp":
            r = (rotl((s[0] + s[3]) & M64, 23) + s[0]) & M64
        else:
            r = (s[0] + s[3]) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return s, r
    return step

def mk_xoroshiro128(kind):
    def step(s):
        a, b = s
        if kind == "pp":
            r = (rotl((a + b) & M64, 17) + a) & M64
        elif kind == "ss":
            r = (rotl((a * 5) & M64, 7) * 9) & M64
        else:
            r = (a + b) & M64
        b ^= a
        return [rotl(a, 49) ^ b ^ ((b << 21) & M64), rotl(b, 28)], r
    return step

def step_xorshift64star(s):
    x = s[0] ^ (s[0] >> 12)
    x ^= (x << 25) & M64
    x ^= x >> 27
    s[0] = x & M64
    return s, (s[0] * 2685821657736338717) & M64

def mk_lcg(a, c):
    def step(s):
        s[0] = (s[0] * a + c) & M64
        return s, s[0]
    return step

def step_pcg32(s):

    MULT = 6364136223846793005
    s[0] = (s[0] * MULT + (s[1] | 1)) & M64
    x = ((s[0] >> 18) ^ s[0]) >> 27
    rot = s[0] >> 59
    y = ((x >> rot) | (x << ((32 - rot) & 31))) & 0xFFFFFFFF
    return s, y * 0x100000001

CORES = {
    "xoshiro256ss": (mk_xoshiro256("ss"), 4),
    "xoshiro256pp": (mk_xoshiro256("pp"), 4),
    "xoshiro256plus": (mk_xoshiro256("plus"), 4),
    "xoroshiro128pp": (mk_xoroshiro128("pp"), 2),
    "xoroshiro128ss": (mk_xoroshiro128("ss"), 2),
    "xoroshiro128plus": (mk_xoroshiro128("plus"), 2),
    "xorshift64star": (step_xorshift64star, 1),
    "lcg_pcg": (mk_lcg(6364136223846793005, 1442695040888963407), 1),
    "lcg_num": (mk_lcg(6364136223846793005, 1), 1),
    "lcg_knuth": (mk_lcg(2862933555777941757, 3037000493), 1),
    "pcg32": (step_pcg32, 2),
}

def seed_variants(n, arity):
    sm = splitmix_seq(n, arity + 2)
    out = {
        "splitmix": sm[:arity],
        "splitmix_skip1": sm[1:1 + arity],
        "splitmix_rev": list(reversed(sm[:arity])),
        "splitmix_zeroed": [sm[0]] + [0] * (arity - 1),
        "seq": [(n + i) & M64 for i in range(arity)],
        "same": [n & M64] * arity,
        "seed_only": [n & M64] + [0] * (arity - 1),
        "seed_ff": ([n & M64, 0xFF, 0, 0][:arity]),
        "splitmix_hi": [(z >> 32) << 32 for z in sm[:arity]],
        "splitmix_add": [(z + i) & M64 for i, z in enumerate(sm[:arity])],
    }
    v, x = [], n & M64
    for _ in range(arity):
        v.append(x)
        x = (x * 6364136223846793005 + 1442695040888963407) & M64
    out["pcgseq"] = v
    v, x = [], (n ^ 0x2545F4914F6CDD1D) & M64
    for _ in range(arity):
        v.append(x)
        x = (x * 6364136223846793005 + 1442695040888963407) & M64
    out["pcgseq_x"] = v
    return out

CONVERSIONS = {
    "r>>11*2^-53": lambda r: (r >> 11) * (2.0 ** -53),
    "r/2^64": lambda r: r / (2.0 ** 64),
    "r/2^64-1": lambda r: r / (2.0 ** 64 - 1.0),
    "r&53*2^-53": lambda r: (r & ((1 << 53) - 1)) * (2.0 ** -53),
    "r>>12*2^-52": lambda r: (r >> 12) * (2.0 ** -52),
    "r>>10*2^-54": lambda r: (r >> 10) * (2.0 ** -54),
    "r>>32/2^32": lambda r: (r >> 32) / (2.0 ** 32),
    "low32/2^32": lambda r: (r & 0xFFFFFFFF) / (2.0 ** 32),
}

def raw4(step, state, discard):
    s = list(state)
    for _ in range(discard):
        s, _ = step(s)
    outs = []
    for _ in range(4):
        s, r = step(s)
        outs.append(r)
    return outs

seed_struct = {}
for cname, (step, arity) in CORES.items():
    for sname, state in seed_variants(SEED, arity).items():
        for discard in list(range(0, 12)) + [16, 20, 32, 64]:
            seed_struct[(cname, sname, discard)] = raw4(step, state, discard)

printed = 0
for key, outs in seed_struct.items():
    for conv_name, conv in CONVERSIONS.items():
        try:
            c1, c2, c3, c4 = (conv(r) for r in outs)
        except OverflowError:
            continue
        if c1 == V1 and c3 == V3 and c4 == V4:
            print("*** FULL MATCH:", key, conv_name)

            lo, hi = 189, 1164
            print("    NextInteger(189,1164) =", lo + int(c2 * (hi - lo + 1)))
        elif c1 == V1:
            if printed < 12:
                print("partial(a1):", key, conv_name, "->", c3, c4)
                printed += 1
print("sweep complete:", len(seed_struct), "seeds x", len(CONVERSIONS), "conversions")
