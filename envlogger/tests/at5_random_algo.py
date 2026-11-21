"""Identify the exact PRNG Roblox's `Random.new(seed)` uses.

Fixture (tests/at5_fixture.lua) pins these for seed 177465824:
  NextNumber()            == 0.9598971928030796
  NextInteger(189, 1164)  == 889
  NextNumber()            == 0.027539190730015265
  NextNumber()            == 0.3377740061710911
  NextInteger(75, 497)    == 340
"""
M64 = (1 << 64) - 1

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def splitmix64(seed, n=4):
    s = seed & M64
    out = []
    for _ in range(n):
        s = (s + 0x9E3779B97F4A7C15) & M64
        z = s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        z ^= z >> 31
        out.append(z & M64)
    return out

class Xoshiro256ss:
    name = "xoshiro256**"

    def __init__(self, seed):
        self.s = splitmix64(seed, 4)

    def next(self):
        s = self.s
        result = (rotl((s[1] * 5) & M64, 7) * 9) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return result

class Xoshiro256pp:
    name = "xoshiro256++"

    def __init__(self, seed):
        self.s = splitmix64(seed, 4)

    def next(self):
        s = self.s
        result = (rotl((s[0] + s[3]) & M64, 23) + s[0]) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return result

class Xoroshiro128pp:
    name = "xoroshiro128++"

    def __init__(self, seed):
        self.s = splitmix64(seed, 2)

    def next(self):
        s = self.s
        result = (rotl((s[0] + s[1]) & M64, 17) + s[0]) & M64
        s1 = s[1] ^ s[0]
        self.s = [rotl(s[0], 49) ^ s1 ^ ((s1 << 21) & M64), rotl(s1, 28)]
        return result

class Xoroshiro128ss:
    name = "xoroshiro128**"

    def __init__(self, seed):
        self.s = splitmix64(seed, 2)

    def next(self):
        s = self.s
        result = (rotl((s[0] * 5) & M64, 7) * 9) & M64
        s1 = s[1] ^ s[0]
        self.s = [rotl(s[0], 49) ^ s1 ^ ((s1 << 21) & M64), rotl(s1, 28)]
        return result

CONVERTERS = {
    ">>11 * 2^-53": lambda r: (r >> 11) * (2.0 ** -53),
    ">>12 * 2^-52": lambda r: (r >> 12) * (2.0 ** -52),
    "top53 >> 11": lambda r: (r >> 11) * (2.0 ** -53),
    "low53 / 2^53": lambda r: (r & ((1 << 53) - 1)) / (2.0 ** 53),
}

EXPECTED = [0.9598971928030796, None, 0.027539190730015265, 0.3377740061710911]
SEED = 177465824

for cls in (Xoshiro256ss, Xoshiro256pp, Xoroshiro128pp, Xoroshiro128ss):
    for conv_name, conv in CONVERTERS.items():
        rng = cls(SEED)
        got = [conv(rng.next()) for _ in range(4)]
        hits = sum(1 for g, e in zip(got, EXPECTED) if e is not None and abs(g - e) < 1e-15)
        if hits >= 2:
            print(f"{cls.name:18} {conv_name:16} hits={hits} {got}")

print("--- brute force raw-vs-expected relationships ---")

for name, denom in (("2^53", 2 ** 53), ("2^52", 2 ** 52), ("2^32", 2 ** 32)):
    v = 0.9598971928030796 * denom
    print(name, "->", v, "integer?", abs(v - round(v)) < 1e-6)
