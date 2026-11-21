"""128-bit-state PCG families with native 64-bit outputs (1 draw per float).

Mantissa forensics: v3 needs 58 mantissa bits, v8 needs 59 -- the double keeps
the LOW bits of a 64-bit word, i.e. NextNumber() = u * 2^-64 with u a full
64-bit output from ONE draw. That rules out XSH-RR 64/32 per-draw but not the
128/64 (XSL-RR) or RXS-M-XS (64/64) variants.

Fixture alignments tested:
  A: 1 draw/call      -> draws 1,2,3,4 = v1, int, v3, v4
  B: 2 draws/NextInteger -> raw 1,3,4 = v1, v3, v4
"""
M64 = (1 << 64) - 1
M32 = 0xFFFFFFFF
MULT128 = 47026247687942121848144207491837523525
SEED = 177465824
V1 = 0.9598971928030796
V3 = 0.027539190730015265
V4 = 0.3377740061710911
INT_LO, INT_HI, INT_WANT = 189, 1164, 889

def xsl_rr(old):
    x = ((old >> 64) ^ old) & M64
    shift = (old >> 122) & 63
    return ((x >> shift) | (x << ((64 - shift) & 63))) & M64 if shift else x

def rxs_m_xs(old):
    rot = (old >> 59) & 31
    x = ((old >> ((rot + 16) & 31)) ^ old) & M64 if False else old
    x = ((old >> 32) ^ old) & M64

    x = old
    count = (old >> 61)
    rot64 = count & 63
    x = ((x >> rot64) | (x << ((64 - rot64) & 63))) & M64 if rot64 else x
    x = (x ^ (x >> (16 + (old >> 58) % 16))) & M64
    return (x * 0x9E3779B97F4A7C15) & M64

def xsh_rr64(old):

    x = ((old >> 18) ^ old) & M64
    shift = (old >> 59) & 63
    return ((x >> shift) | (x << ((64 - shift) & 63))) & M64 if shift else x

FAMILIES = {
    "xsl_rr": xsl_rr,
    "rxs_m_xs": rxs_m_xs,
    "xsh_rr64": xsh_rr64,
}

INITS = {
    "seed": (SEED, 1442695040888963407),
    "seedstep": ((SEED * MULT128 + 1442695040888963407) & ((1 << 128) - 1), 1442695040888963407),
    "def": (SEED, 0),
    "zero": (0, SEED | 1),
}

def run(family, init, inc, discard, n):
    mod = (1 << 128) - 1
    s = init & mod
    c = inc & mod
    for _ in range(discard):
        s = (s * MULT128 + c) & mod
    out = []
    for _ in range(n):
        old = s
        s = (old * MULT128 + c) & mod
        out.append(family(old))
    return out

hits = []
for fname, fam in FAMILIES.items():
    for iname, (st, inc) in INITS.items():
        for discard in range(0, 20):
            w = run(fam, st, inc, discard, 6)
            convs = {
                "u64": lambda u: u * 2.0 ** -64,
                "hi": lambda u: (u >> 32) / 2.0 ** 32,
            }
            for cname, conv in convs.items():
                us = [conv(x) for x in w]
                if us[0] == V1:
                    ok_int_a = INT_LO + int(us[1] * (INT_HI - INT_LO + 1)) == INT_WANT
                    print("*** MATCH", fname, iname, discard, cname,
                          "v3:", us[1] == V3 or us[2] == V3,
                          "v4:", us[2] == V4 or us[3] == V4,
                          "int(A):", ok_int_a)
                    hits.append((fname, iname, discard, cname))
                elif abs(us[0] - V1) < 1e-9:
                    print("near", fname, iname, discard, cname, us[0])

if not hits:
    print("no 128-bit PCG match")
