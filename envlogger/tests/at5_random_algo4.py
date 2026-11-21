"""Sweep generator cores x seeding schemes x output->double conversions.

Earlier sweeps assumed NextNumber() == (r >> 11) * 2^-53, which is refuted:
0.027539190730015265 is not a multiple of 2^-53. So compare candidate doubles
by exact IEEE equality for a set of conversions.
"""
import struct
from fractions import Fraction

M64 = (1 << 64) - 1
SEED = 177465824
TARGETS = [0.9598971928030796, 0.027539190730015265, 0.3377740061710911]

def as_double(x):
    return x

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def splitmix64_seq(seed, n=4):
    s = seed & M64
    out = []
    for _ in range(n):
        s = (s + 0x9E3779B97F4A7C15) & M64
        z = s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        out.append(z ^ (z >> 31))
    return out

def step_xoshiro256(kind):
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

def step_xoroshiro128(kind):
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
    x = s[0]
    x ^= x >> 12
    x ^= (x << 25) & M64
    x ^= x >> 27
    s[0] = x
    return s, (x * 2685821657736338717) & M64

def step_xorshift64(s):
    x = s[0]
    x ^= (x << 13) & M64
    x ^= x >> 7
    x ^= (x << 17) & M64
    s[0] = x
    return s, x

def step_splitmix(s):
    s[0] = (s[0] + 0x9E3779B97F4A7C15) & M64
    z = s[0]
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return s, z ^ (z >> 31)

def step_lcg(a, c):
    def step(s):
        s[0] = (s[0] * a + c) & M64
        return s, s[0]
    return step

def step_pcg64(s):

    MULT = 47026247687942121848144207491837523525
    INC = 117397592171526113268558934119004209487
    state = (s[0] << 64) | s[1]
    state = (state * MULT + INC) & ((1 << 128) - 1)
    s[0] = (state >> 64) & M64
    s[1] = state & M64
    word = ((s[0] ^ s[1]) >> 64) & M64 if False else s[0]
    x = s[0]
    xorshifted = (((x ^ (x >> 22)) >> ((x >> 61) + 22)) & M64) if False else x
    rot = x >> 59
    y = x
    y = ((y >> rot) | (y << (64 - rot))) & M64 if rot else y
    return s, y
    return s, word

CORES = {
    "xoshiro256ss": (step_xoshiro256("ss"), 4),
    "xoshiro256pp": (step_xoshiro256("pp"), 4),
    "xoshiro256plus": (step_xoshiro256("plus"), 4),
    "xoroshiro128pp": (step_xoroshiro128("pp"), 2),
    "xoroshiro128ss": (step_xoroshiro128("ss"), 2),
    "xoroshiro128plus": (step_xoroshiro128("plus"), 2),
    "xorshift64star": (step_xorshift64star, 1),
    "xorshift64": (step_xorshift64, 1),
    "splitmix64": (step_splitmix, 1),
    "lcg_pcg": (step_lcg(6364136223846793005, 1442695040888963407), 1),
    "lcg_knuth": (step_lcg(2862933555777941757, 3037000493), 1),
    "pcg64": (step_pcg64, 2),
}

CONVERSIONS = {
    "r/2^64": lambda r: r / (2.0 ** 64),
    "r/2^64-1": lambda r: r / (2.0 ** 64 - 1.0),
    "r>>11*2^-53": lambda r: (r >> 11) * (2.0 ** -53),
    "r&53*2^-53": lambda r: (r & ((1 << 53) - 1)) * (2.0 ** -53),
    "r>>12*2^-52": lambda r: (r >> 12) * (2.0 ** -52),
    "r>>10*2^-54": lambda r: (r >> 10) * (2.0 ** -54),
    "r>>32/2^32": lambda r: (r >> 32) / (2.0 ** 32),
    "low32/2^32": lambda r: (r & 0xFFFFFFFF) / (2.0 ** 32),
    "r&31/2^31": lambda r: (r & 0x7FFFFFFF) / (2.0 ** 31),
}

def seed_variants(n, arity):
    out = {
        "splitmix": splitmix64_seq(n, arity),
        "seq": [(n + i) & M64 for i in range(arity)],
        "same": [n & M64] * arity,
        "seed_first": [n & M64] + [0] * (arity - 1),
        "seed_0ff": ([n & M64, 0, 0xFF, 0][:arity]),
        "seed_ff": ([n & M64, 0xFF, 0, 0][:arity]),
        "seq32": [(n + i) & 0xFFFFFFFF for i in range(arity)],
    }
    v, x = [], n & M64
    for _ in range(arity):
        v.append(x)
        x = (x * 6364136223846793005 + 1) & M64
    out["mulseq"] = v
    v, x = [], n & M64
    for _ in range(arity):
        v.append(x)
        x = (x * 6364136223846793005 + 1442695040888963407) & M64
    out["pcgseq"] = v
    return out

hits = []
for cname, (step, arity) in CORES.items():
    for sname, state in seed_variants(SEED, arity).items():
        for discard in range(0, 25):
            s = list(state)
            for _ in range(discard):
                s, _r = step(s)
            s2 = list(s)
            produced = []
            s3 = list(s2)
            for _ in range(3):
                s3, r = step(s3)
                produced.append(r)
            for conv_name, conv in CONVERSIONS.items():
                try:
                    values = [conv(r) for r in produced]
                except OverflowError:
                    continue
                if values[0] == TARGETS[0] and values[1] == TARGETS[1] and values[2] == TARGETS[2]:
                    hits.append((cname, sname, discard, conv_name))
                    print("HIT", cname, sname, "discard", discard, conv_name)
                elif values[0] == TARGETS[0]:
                    print("partial", cname, sname, "discard", discard, conv_name, values)

if not hits:
    print("no exact triple match in sweep")
