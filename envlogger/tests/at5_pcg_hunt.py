"""Roblox Random = PCG XSH-RR hypothesis, exhaustive small sweep.

Fixture alignment (at5_fixture.lua):
  draw1 -> v1 0.9598971928030796
  draw2 -> NextInteger(189,1164) = 889   (floor(189 + u2*976) == 889)
  draw3 -> v3 0.027539190730015265
  draw4 -> v4 0.3377740061710911
"""
import struct

MULT = 6364136223846793005
INC_DEF = 1442695040888963407
M64 = (1 << 64) - 1
M32 = 0xFFFFFFFF

SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
INT_LO, INT_HI, INT_WANT = 189, 1164, 889

def struct_d(x):
    return struct.unpack("<d", struct.pack("<d", x))[0]

def pcg_stream(state, inc, discard, n):
    s = state & M64
    c = inc & M64
    for _ in range(discard):
        s = (s * MULT + c) & M64
    out = []
    for _ in range(n):
        s = (s * MULT + c) & M64
        xorshifted = (((s >> 18) ^ s) >> 27) & M32
        rot = (s >> 59) & 31
        out.append(((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & M32)
    return out

def pcg_stream_rxs(state, inc, discard, n):
    s = state & M64
    c = inc & M64
    for _ in range(discard):
        s = (s * MULT + c) & M64
    out = []
    for _ in range(n):
        s = (s * MULT + c) & M64
        rot = (s >> 59) & 31
        x = ((s >> 18) ^ s) >> 27 & M32
        out.append(((x >> rot) | (x << ((32 - rot) & 31))) & M32)
    return out

def init_variants():
    out = {}
    out["lcg0"] = lambda: (SEED, 0)
    out["lcg1"] = lambda: (0, SEED)
    out["lcgdef"] = lambda: ((SEED + INC_DEF) & M64, INC_DEF)
    out["lcgdef2"] = lambda: ((SEED * MULT + INC_DEF) & M64, INC_DEF)
    out["lcgdef0"] = lambda: (SEED, INC_DEF)
    out["lcgdef_n1"] = lambda: ((SEED - 1) & M64, INC_DEF)
    out["lcgdef_p1"] = lambda: ((SEED + 1) & M64, INC_DEF)
    out["lcgdef_x"] = lambda: (SEED ^ INC_DEF, INC_DEF)
    out["lcgdef_lo32"] = lambda: ((SEED * MULT + INC_DEF) & M64, INC_DEF ^ 1)
    sm = 0x853C49E6748FEA9B
    out["pcg32_cpp"] = lambda: (((SEED) * MULT + sm) & M64, sm)
    out["pcg32_cpp2"] = lambda: (((SEED + 1) * MULT + sm) & M64, sm)
    return out

CONV = {
    "hi53": lambda a, b: ((a >> 5) * 1.0842021724855044e-19 + (b >> 5) * 1.1102230246251565e-16),
    "hi32": lambda a, b: a / 4294967296.0,
    "lo32": lambda a, b: b / 4294967296.0,
    "lo21hi53": lambda a, b: (b & 0x1FFFFF) * 1.1102230246251565e-16 + (a >> 11) * 1.0842021724855044e-19,
    "hi21lo53": lambda a, b: (a & 0x1FFFFF) * 1.1102230246251565e-16 + (b >> 11) * 1.0842021724855044e-19,
    "hi20lo52": lambda a, b: (a & 0xFFFFF) * 1.1102230246251565e-16 + (b >> 12) * 1.0842021724855044e-19,
    "hi11lo53": lambda a, b: (a & 0x7FF) * 1.1102230246251565e-16 + (b >> 11) * 1.0842021724855044e-19,
    "hi53p2": lambda a, b: (a >> 5) / 9007199254740992.0 + (b >> 5) / 9007199254740992.0,
    "div53": lambda a, b: (a * 4294967296.0 + b) / 9007199254740992.0,
    "div64": lambda a, b: (a * 4294967296.0 + b) / 18446744073709551616.0,
}

hits = []
for name, mk in init_variants().items():
    state0, inc = mk()
    for variant, stream in (("xsh_rr", pcg_stream), ("xsh_rr_b", pcg_stream_rxs)):
        for discard in range(0, 16):
            words = stream(state0, inc, discard, 5)
            for cname, conv in CONV.items():
                u1 = conv(words[0], words[1])
                u2 = conv(words[2], words[3])
                u3 = conv(words[3], words[4]) if False else None
                u1b = conv(words[0], words[1])
                if u1 == V1:
                    ui = INT_LO + int(u2 * (INT_HI - INT_LO + 1))
                    v3 = conv(words[2], words[3])
                    v4 = conv(words[4], words[4])
                    hits.append((name, variant, discard, cname))
                    print("MATCH v1", name, variant, discard, cname,
                          "v3==", v3 == V3, "int ok==", ui == INT_WANT)

if not hits:
    print("no v1 match in PCG sweep")
