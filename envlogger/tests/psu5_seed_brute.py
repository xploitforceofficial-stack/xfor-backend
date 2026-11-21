"""Brute LZW seed size: maybe v5 seeds MORE entries (e.g. 256 + padding up to 3844,
since base62 2-digit max is 3843). First code = 2.39e48 — impossible for any dict.
CONCLUSION: giant blob is NOT [w][digits] varint. Maybe it's [digits][w]? Or the
blob is an image of fixed-width codes: len 500000 = 100000 * 5, = 62500 * 8,
= 166666*3, = 41666*12? Try fixed widths: value = b62 of k chars, k in 2..6, and see
if code stats look like LZW (codes < 256 early, growing slowly)."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

for k in (2, 3, 4, 5):
    n = len(blob) // k
    codes = []
    for i in range(n):
        v = 0
        for ch in blob[i*k:(i+1)*k]:
            v = v * 62 + IDX[ch]
        codes.append(v)
    first = codes[:8]
    below256 = sum(1 for c in codes[:1000] if c < 256)
    print(f'k={k}: first={first} below256_in_first1000={below256}')
