"""Strip filler chars from PSU v5 region B (between payload string close and VM body)
to see if the LZW decoder is hidden there."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

B = s[500441:1000524]
print("region B len:", len(B))

FILLER = set(' &=|/#_')
stripped = ''.join(c for c in B if c not in FILLER)
print("stripped len:", len(stripped), f"({len(stripped)*100.0/len(B):.1f}%)")
print()
print("=== first 1500 stripped:")
print(stripped[:1500])
print()
print("=== count of alnum vs punctuation in stripped:")
import collections
cls = collections.Counter()
for c in stripped:
    if c.isalnum(): cls['alnum'] += 1
    elif c in '(){}[]': cls['brace'] += 1
    else: cls['other'] += 1
print(dict(cls))
