"""Giant v5 blob: if width chars were digits-only in base36, the blob would only contain
0-9a-j as widths — but distribution shows all 62 chars. UNLESS the value digits include
uppercase (base62) and widths are ALSO base36 — first char 'R' can't be width.
Alternative: v5 giant blob = base62 varint (width 1 char base62, value base62).
That failed at 2905 with a huge value. Inspect what's at 2905: maybe LZW codes ARE huge
because v5 dict seeds bigger. Print first codes with the b62 parse and don't reject."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

pos, codes = 0, []
while pos < len(blob):
    w = IDX[blob[pos]]
    if w < 1 or pos + 1 + w > len(blob): break
    v = 0
    for ch in blob[pos+1:pos+1+w]:
        v = v * 62 + IDX[ch]
    codes.append(v)
    pos += 1 + w
print('b62 codes:', len(codes))
print('first 30:', codes[:30])
print('max:', max(codes), 'min:', min(codes))
import collections
c = collections.Counter(code < 256 for code in codes)
print('codes <256:', c[True], 'codes >=256:', c[False])
