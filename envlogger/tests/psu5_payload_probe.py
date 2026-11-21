"""Decode the v5 500KB base36 blob using v4's [width][value] framing with 64-bit wrap."""
import json

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
blob = s[439:500441]
print("blob len:", len(blob))

ALPHA = '0123456789abcdefghijklmnopqrstuvwxyz'
assert all(c in ALPHA for c in blob), "non-base36 char in blob"

pos = 0
values = []
widths = {}
M64 = (1 << 64)
while pos < len(blob):
    w = ALPHA.index(blob[pos])
    widths[w] = widths.get(w, 0) + 1
    pos += 1
    if pos + w > len(blob):
        break
    digits = blob[pos:pos + w]
    pos += w
    v = 0
    for ch in digits:
        v = v * 36 + ALPHA.index(ch)
    values.append(v & (M64 - 1) if v >= (1 << 63) else v)

print("decoded values:", len(values), "consumed:", pos, "of", len(blob))
print("width histogram:", dict(sorted(widths.items())))
print("first 20 values:", values[:20])
print("max value:", max(values) if values else None)

env = json.load(open('Samples/PSU/v5/_envtable.json', encoding='utf-8'))
envn = {}
envc = {}
for k, v in env.items():
    try:
        ki = int(k)
    except ValueError:
        continue
    try:
        envn[ki] = float(v)
    except (TypeError, ValueError):
        envc[ki] = v

resolved = 0
for v in values[:200]:
    if v in envn or v in envc:
        resolved += 1
print("values[:200] hitting env keys:", resolved)

print("\n=== do any values match env keys exactly?")
hits = [v for v in values if v in envn or v in envc]
print("exact key hits:", len(hits), hits[:10])
