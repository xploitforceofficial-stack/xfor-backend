"""PCG XSH-RR sweep, take 2: output derives from the PRE-update state.

Canonical pcg32:
    old = state
    state = old * MULT + inc
    x = ((old >> 18) ^ old) >> 27
    r = rotr32(x, old >> 59)
The previous sweep emitted from the new state, which can never match a
canonical implementation.
"""
M32 = 0xFFFFFFFF
M64 = (1 << 64) - 1
MULT = 6364136223846793005
INC_DEF = 1442695040888963407
INC_CPP = 0x853C49E6748FEA9B

SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
INT_LO, INT_HI, INT_WANT = 189, 1164, 889

def rotr32(x, r):
    r &= 31
    return ((x >> r) | (x << ((32 - r) & 31))) & M32

def stream_xsh_rr(state, inc, discard, n):
    s = state & M64
    c = inc & M64
    for _ in range(discard):
        s = (s * MULT + c) & M64
    out = []
    for _ in range(n):
        old = s
        s = (old * MULT + c) & M64
        x = (((old >> 18) ^ old) >> 27) & M32
        out.append(rotr32(x, old >> 59))
    return out

def stream_rxs_m_xs(state, inc, discard, n):

    s = state & M64
    c = inc & M64
    for _ in range(discard):
        s = (s * MULT + c) & M64
    out = []
    for _ in range(n):
        old = s
        s = (old * MULT + c) & M64
        rot = (old >> 61) & 31
        x = old >> (32 + (rot & 15)) & M32 if False else (old >> 32) & M32
        x = (x ^ (x >> ((rot + 16) & 31))) & M32
        out.append((x * 0x9E3779B1) & M32)
    return out

INITS = {
    "def_seed": (SEED, INC_DEF),
    "def_seedstep": ((SEED * MULT + INC_DEF) & M64, INC_DEF),
    "def_seedstep2": (((SEED * MULT + INC_DEF) * MULT + INC_DEF) & M64, INC_DEF),
    "zero_inc_seed": (0, SEED),
    "seed_inc0": (SEED, 0),
    "cpp_seed": ((SEED * MULT + INC_CPP) & M64, INC_CPP),
    "cpp_seed2": (((SEED * MULT + INC_CPP) * MULT + INC_CPP) & M64, INC_CPP),
    "def_inc1": (SEED, INC_DEF ^ 1),
    "def_seed_lo": (SEED & M32, INC_DEF),
    "def_seed_hi": (SEED << 32, INC_DEF),
    "def_seed_x": (SEED ^ 0xDEADBEEF, INC_DEF),
}

CONV = {
    "hi53": lambda a, b: (a >> 5) * 2.0 ** -53,
    "lo53": lambda a, b: (b >> 5) * 2.0 ** -53,
    "hi32": lambda a, b: a / 2.0 ** 32,
    "lo32": lambda a, b: b / 2.0 ** 32,
    "u64_53": lambda a, b: (a * 4294967296.0 + b) / 9007199254740992.0,
    "u64_64": lambda a, b: (a * 4294967296.0 + b) / 18446744073709551616.0,
    "hi21hi53": lambda a, b: ((a >> 11) & 0x1FFFFF) / 2.0 ** 21 * 2.0 ** -32 + (b >> 11) * 2.0 ** -53,
    "hi10lo53": lambda a, b: ((a & 0x3FF) / 2.0 ** 10) * 2.0 ** -53 * 2048 + (b >> 11) * 2.0 ** -53,
    "half53": lambda a, b: ((a >> 5) + (b >> 5) * 2.0 ** 26) * 2.0 ** -53,
    "hi5lo53": lambda a, b: ((a & 0x1F) * 2.0 ** 48 + (b >> 5)) * 2.0 ** -53,
}

hits = []
for iname, (st, inc) in INITS.items():
    for sname, stream in (("xsh_rr", stream_xsh_rr), ("rxs_m_xs", stream_rxs_m_xs)):
        for discard in range(0, 20):
            w = stream(st, inc, discard, 6)
            for cname, conv in CONV.items():
                pairs = [(w[0], w[1]), (w[2], w[3]), (w[4], w[5])]
                us = [conv(a, b) for a, b in pairs]
                if us[0] == V1:
                    ui = INT_LO + int(us[1] * (INT_HI - INT_LO + 1))
                    print("*** MATCH v1:", iname, sname, "discard", discard, cname,
                          "| v3 ok:", us[1] == V3 or us[2] == V3, "| int ok:", ui == INT_WANT)
                    hits.append((iname, sname, discard, cname))
                elif abs(us[0] - V1) < 1e-9:
                    print("near:", iname, sname, discard, cname, us[0])

print("done;", len(hits), "matches")
