"""Wide sweep for Roblox's Random generator.

seed 177465824, first NextNumber() == 0.9598971928030796 (top-53 bits == 8645985279643869)
We also use the later draws as confirmation:
  v3 = 0.027539190730015265, v4 = 0.3377740061710911
"""
M64 = (1 << 64) - 1
SEED = 177465824
K1 = 8645985279643869
V3 = 0.027539190730015265
V4 = 0.3377740061710911

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def shr(x, k):
    return x >> k

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

def splitmix64_next(state):
    state[0] = (state[0] + 0x9E3779B97F4A7C15) & M64
    z = state[0]
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return z ^ (z >> 31)

class G:
    """Generic 64-bit-ish generator wrapper with a next() -> 64-bit method."""

    def __init__(self, step, state):
        self.step = step
        self.state = state

    def next(self):
        self.state, out = self.step(self.state)
        return out

def mk_xoshiro256s(kind):
    def step(s):
        s = list(s)
        if kind == "ss":
            result = (rotl((s[1] * 5) & M64, 7) * 9) & M64
        elif kind == "pp":
            result = (rotl((s[0] + s[3]) & M64, 23) + s[0]) & M64
        else:
            result = (s[0] + s[3]) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return s, result
    return step

def mk_xoroshiro128s(kind):
    def step(s):
        a, b = s
        if kind == "pp":
            result = (rotl((a + b) & M64, 17) + a) & M64
        elif kind == "ss":
            result = (rotl((a * 5) & M64, 7) * 9) & M64
        elif kind == "+":
            result = (a + b) & M64
        else:
            result = (rotl((b * 5) & M64, 7) * 9) & M64
        b ^= a
        return [rotl(a, 49) ^ b ^ ((b << 21) & M64), rotl(b, 28)], result
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
    return s, splitmix64_next(s)

def step_lcg(a, c):
    def step(s):
        s[0] = (s[0] * a + c) & M64
        return s, s[0]
    return step

def step_msws(s):

    if len(s) < 2:
        s.append(0)
    s[0] = (s[0] + 0x9E3779B97F4A7C15) & M64
    x = (s[1] * s[1]) & M64
    s[1] = x
    return s, x ^ s[0]

CORES = {}
for kind in ("ss", "pp", "+"):
    CORES[f"xoshiro256{kind}"] = mk_xoshiro256s(kind)
for kind in ("pp", "ss", "+", "ss2"):
    CORES[f"xoroshiro128{kind}"] = mk_xoroshiro128s(kind)
CORES["xorshift64*"] = step_xorshift64star
CORES["xorshift64"] = step_xorshift64
CORES["splitmix64"] = step_splitmix
CORES["lcg-pcg"] = step_lcg(6364136223846793005, 1442695040888963407)
CORES["lcg-1"] = step_lcg(6364136223846793005, 1)
CORES["lcg-knuth"] = step_lcg(2862933555777941757, 3037000493)
CORES["msws64"] = step_msws

ARITY = {"xoshiro256ss": 4, "xoshiro256pp": 4, "xoshiro256+": 4,
         "xoroshiro128pp": 2, "xoroshiro128ss": 2, "xoroshiro128+": 2,
         "xoroshiro128ss2": 2}

def seed_variants(n, arity):
    variants = {}
    variants["splitmix"] = splitmix64_seq(n, arity)
    variants["seq"] = [(n + i) & M64 for i in range(arity)]
    variants["same"] = [n & M64] * arity
    variants["zeros_except0"] = [n & M64] + [0] * (arity - 1)
    variants["0xff"] = [n & M64, 0, 0xFF, 0][:arity]
    variants["lcgexpand"] = []
    x = n & M64
    for _ in range(arity):
        x = (x * 6364136223846793005 + 1442695040888963407) & M64
        variants["lcgexpand"].append(x)
    variants["splitmix32"] = splitmix64_seq(n % (2 ** 32), arity)

    v = []
    x = n & M64
    for _ in range(arity):
        v.append(x)
        x = (x * 6364136223846793005 + 1) & M64
    variants["mulseq"] = v
    return variants

hits = 0
for cname, step in CORES.items():
    arity = ARITY.get(cname, 1)
    for sname, state in seed_variants(SEED, arity).items():
        for discard in range(0, 40):
            g = G(step, list(state))
            for _ in range(discard):
                g.next()
            out = g.next()
            if (out >> 11) == K1:
                print(f"HIT core={cname} seed={sname} discard={discard}")
                hits += 1
            elif abs((out & ((1 << 53) - 1)) * (2.0 ** -53) - V3 / (2 ** 11)) < 1e-18:
                pass

if not hits:
    print("no top-53 hit in sweep")

for cname, step in CORES.items():
    arity = ARITY.get(cname, 1)
    for sname, state in seed_variants(SEED, arity).items():
        for word in state:
            if (word >> 11) == K1:
                print(f"HIT-as-state core={cname} seed={sname} word={word}")
