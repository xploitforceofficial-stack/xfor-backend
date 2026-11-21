"""Decode v5 blob: base62 alphabet, v4-style [width][value] framing, 64-bit wrap."""
import json

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

qi = s.find('"', 439, 500441)
ci = s.find(',', 439, 500441)
print("stray quote at:", qi, " stray comma at:", ci)
print("context around quote:", repr(s[qi - 40:qi + 40]))
print("context around comma:", repr(s[ci - 40:ci + 40]))

blob = s[439:500441]
clean = blob.replace('"', '').replace(',', '')
print("\nclean blob len:", len(clean))

ALPHA = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
idx = {c: i for i, c in enumerate(ALPHA)}
assert len(set(clean)) <= 62

pos = 0
values = []
widths = {}
overflows = 0
M64 = 1 << 64
while pos < len(clean):
    w = idx[clean[pos]]
    widths[w] = widths.get(w, 0) + 1
    pos += 1
    if pos + w > len(clean):
        break
    v = 0
    for ch in clean[pos:pos + w]:
        v = v * 62 + idx[ch]
    if v >= (1 << 63):
        overflows += 1
    pos += w
    values.append(v & (M64 - 1))

print("decoded values:", len(values), "consumed:", pos, "/", len(clean))
print("width histogram:", dict(sorted(widths.items())))
print("overflows past 2^63:", overflows)
print("first 24 values:", values[:24])

env = json.load(open('Samples/PSU/v5/_envtable.json', encoding='utf-8'))
envn = {}
for k, v in env.items():
    try:
        envn[int(k)] = v
    except ValueError:
        pass

hits = [v for v in values if v in envn]
print("exact env-key hits:", len(hits), hits[:10])
