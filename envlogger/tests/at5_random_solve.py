"""Decide whether Roblox's Random is xoshiro256** by linear algebra.

xoshiro256** is GF(2)-linear, so the 53 known high bits of each output are
linear equations in the 256 unknown state bits. Five outputs give 265 equations
for 256 unknowns: if the generator is xoshiro256** the system is consistent and
solvable; if not, it is inconsistent and the hypothesis dies.

Targets for seed 177465824 (from tests/at5_fixture.lua):
  v1 = 0.9598971928030796
  v3 = 0.027539190730015265
  v4 = 0.3377740061710911
  plus two NextInteger draws that bound their raw value:
    NextInteger(189, 1164) == 889  -> 0.717213 <= r < 0.718238
    NextInteger(75, 497)   == 340  -> 0.626477 <= r < 0.628841
"""
M64 = (1 << 64) - 1
SEED = 177465824

def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64

def xoshiro_ss_step(s):
    """One xoshiro256** step: returns (new_state, 64-bit output)."""
    a, b, c, d = s
    result = (rotl((b * 5) & M64, 7) * 9) & M64
    t = (b << 17) & M64
    c ^= a
    d ^= b
    b ^= c
    a ^= d
    c ^= t
    d = rotl(d, 45)
    return [a, b, c, d], result

OUTPUTS = 5

eq = [[0] * 64 for _ in range(OUTPUTS)]
for bit in range(256):
    state = [0, 0, 0, 0]
    state[bit // 64] = 1 << (bit % 64)
    cur = state
    for t in range(OUTPUTS):
        cur, value = xoshiro_ss_step(cur)
        for j in range(64):
            if (value >> j) & 1:
                eq[t][j] |= 1 << bit

def high53(value):
    k = round(value * (2 ** 53))
    assert abs(value * (2 ** 53) - k) < 1e-6, value
    return k

KNOWN = {
    0: high53(0.9598971928030796),
    2: high53(0.027539190730015265),
    3: high53(0.3377740061710911),
}

rows = []
for t, k in KNOWN.items():
    for offset in range(53):
        bit = 11 + offset
        mask = eq[t][bit]
        rhs = (k >> offset) & 1
        if mask == 0 and rhs == 1:
            print(f"impossible: output {t} bit {bit} is constant 0 but must be 1")
            raise SystemExit(1)
        rows.append([mask, rhs])

pivot_of = {}
inconsistent = False
for mask, rhs in rows:
    cur_mask, cur_rhs = mask, rhs
    while cur_mask:
        pivot = cur_mask.bit_length() - 1
        if pivot in pivot_of:
            pmask, prhs = pivot_of[pivot]
            cur_mask ^= pmask
            cur_rhs ^= prhs
        else:
            pivot_of[pivot] = (cur_mask, cur_rhs)
            break
    else:
        if cur_rhs:
            inconsistent = True
            break

print("rank:", len(pivot_of), "of 256")
print("consistent:", not inconsistent)
if inconsistent:
    print("=> xoshiro256** with that unknown state is RULED OUT by the data")
    raise SystemExit(0)

solution = 0
for pivot in sorted(pivot_of):
    mask, rhs = pivot_of[pivot]
    value = rhs
    rest = mask & ~(1 << pivot)
    while rest:
        low = rest & -rest
        index = low.bit_length() - 1
        if (solution >> index) & 1:
            value ^= 1
        rest ^= low
    if value:
        solution |= 1 << pivot

state = [
    (solution >> 0) & M64,
    (solution >> 64) & M64,
    (solution >> 128) & M64,
    (solution >> 192) & M64,
]
print("recovered initial state:")
for index, word in enumerate(state):
    print(f"  s{index} = 0x{word:016x}")
cur = state
outs = []
for _ in range(5):
    cur, value = xoshiro_ss_step(cur)
    outs.append(value)
print("outputs:", [f"0x{v:016x}" for v in outs])
print("doubles:", [f"{(v >> 11) * (2.0 ** -53):.17f}" for v in outs])

def next_integer(raw, low, high):
    return low + int((raw >> 11) * (2.0 ** -53) * (high - low + 1))

print("integer draw 1 (expect 889) :", next_integer(outs[1], 189, 1164))
print("integer draw 2 (expect 340) :", next_integer(outs[4], 75, 497))

def splitmix64(seed, n=4):
    s = seed & M64
    out = []
    for _ in range(n):
        s = (s + 0x9E3779B97F4A7C15) & M64
        z = s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        out.append(z ^ (z >> 31))
    return out

print("splitmix64(seed):", [f"0x{w:016x}" for w in splitmix64(SEED)])
print("seed words      :", [f"0x{w:016x}" for w in [SEED, 0, 0, 0]])
