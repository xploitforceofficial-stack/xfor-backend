"""v5 varint: the width char must be a DIGIT 0-9 (v4.5 widths were digits like 2,3,7).
Widths here: R(27) f(41)... — NOT digits. So v5 uses base62 for widths/values.
Base62 varint failed at 2905. Try: width char in base36 (0-9a-z -> 0..35) but value
digits in base62. Or the reader may differ: v5 could read [2-digit width][value]."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]

A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

ws = [IDX[c] for c in blob[:2000]]
import collections
print('width-class histogram (first 2000, as IDX):', dict(sorted(collections.Counter(ws).items())[:20]))

print()
print('blob[0:20] =', blob[:20])
print('any char repeated consecutively in first 2000?', [blob[i]*2 in blob[i:i+2] for i in range(30)][:10])

for m in range(3):
    seg = blob[m:2000:3]
    print('mod', m, 'distinct:', len(set(seg)))
