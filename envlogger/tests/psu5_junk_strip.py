"""Test if the junk region is real code with filler chars inserted: strip &=|/#_ and see what emerges."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

FILLER = set(' &=|/#_')

B = s[500441:1000524]
stripped = ''.join(c for c in B if c not in FILLER)
print("region B len:", len(B), "-> stripped:", len(stripped), f"({len(stripped)*100.0/len(B):.1f}% kept)")
print()
print("=== first 600 chars of stripped region B:")
print(stripped[:600])
print()
print("=== last 300 chars of stripped region B:")
print(stripped[-300:])
print()

run_gap = 0
gaps = []
for c in B:
    if c in FILLER:
        run_gap += 1
    else:
        if run_gap:
            gaps.append(run_gap)
        run_gap = 0
from collections import Counter
print("gap-length histogram (filler runs between real chars):", dict(sorted(Counter(gaps).items())[:15]))
