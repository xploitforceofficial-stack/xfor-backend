"""Brute force the (generator core, seeding) pair for Roblox Random.

Target (seed 177465824): first NextNumber() == 0.9598971928030796
  -> raw53 = 8645985279643869  (0.9598971928030796 * 2^53 is an exact integer)
"""
M64 = (1 << 64) - 1
SEED = 177465824
TARGET = 0.9598971928030796
TARGET53 = round(TARGET * (2 ** 53))

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

def make_ss(state):
    s = list(state)

    def nxt():
        result = (rotl((s[1] * 5) & M64, 7) * 9) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return result

    return nxt, s

def make_pp(state):
    s = list(state)

    def nxt():
        result = (rotl((s[0] + s[3]) & M64, 23) + s[0]) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return result

    return nxt, s

def make_plus(state):
    s = list(state)

    def nxt():
        result = (s[0] + s[3]) & M64
        t = (s[1] << 17) & M64
        s[2] ^= s[0]
        s[3] ^= s[1]
        s[1] ^= s[2]
        s[0] ^= s[3]
        s[2] ^= t
        s[3] = rotl(s[3], 45)
        return result

    return nxt, s

CORES = {"ss": make_ss, "pp": make_pp, "plus": make_plus}

SEEDS = {
    "sm64": lambda n: splitmix64(n, 4),
    "n000": lambda n: [n & M64, 0, 0, 0],
    "n0ff0": lambda n: [n & M64, 0, 0xFF, 0],
    "nff00": lambda n: [n & M64, 0xFF, 0, 0],
    "n0ff0_alt": lambda n: [n & M64, 0xFF, 0, 0],
    "n1010": lambda n: [n & M64, 1, 0, 1],
    "nnnn": lambda n: [n & M64] * 4,
    "sm64_raw": lambda n: [splitmix64(n, 1)[0], 1, 0, 0],
    "lu54": lambda n: [n & M64, 0, 0xFF, 0],
}

DISCARDS = (0, 16)

found = []
for core_name, core in CORES.items():
    for seed_name, seeder in SEEDS.items():
        for discard in DISCARDS:
            nxt, _ = core(seeder(SEED))
            for _ in range(discard):
                nxt()
            raw = nxt()
            if (raw >> 11) == TARGET53:
                found.append((core_name, seed_name, discard, ">>11"))
                print("MATCH", core_name, seed_name, "discard", discard, "conv >>11")
            if abs((raw & ((1 << 53) - 1)) / (2.0 ** 53) - TARGET) < 1e-15:
                print("MATCH-low53", core_name, seed_name, discard)
            if abs(raw / (2.0 ** 64) - TARGET) < 1e-15:
                print("MATCH-2^64", core_name, seed_name, discard)

if not found:
    print("no match yet; dumping candidate first draws for inspection")
    for core_name, core in CORES.items():
        for seed_name, seeder in SEEDS.items():
            nxt, _ = core(seeder(SEED))
            raw = nxt()
            print(f"{core_name:5} {seed_name:10} raw>>11*f = {(raw >> 11) * (2.0 ** -53):.17f}")
