"""Recompute tail payload bytes precisely, then brute n0: check if decoded stream
looks like a PSU chunk header: M=d()<=64, then tag bytes from {1,2,3,5,6,...}."""
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
b5 = s[1022401:1022491]

pos, codes = 0, []
while pos < len(b5):
    w = D36.index(b5[pos].lower())
    if w < 1 or pos + 1 + w > len(b5): break
    codes.append(int(b5[pos+1:pos+1+w].lower(), 36))
    pos += 1 + w

dic = {e: chr(e) for e in range(256)}
out, prev, t = [], None, 256
for code in codes:
    if code in dic: c = dic[code]
    elif code == t and prev: c = prev + prev[0]
    else: break
    out.append(c)
    if prev: dic[t] = prev + c[0]; t += 1
    prev = c
stream = ''.join(out)
B = [ord(ch) & 0xff for ch in stream]
print('bytes:', [hex(x) for x in B])

for n0 in range(256):
    n = n0
    dec = []
    for byte in B[:12]:
        v = byte ^ n
        n = v & 0xff
        dec.append(v)
    lo, hi = dec[0], dec[1]
    M = lo + (hi << 8)
    if M <= 64:
        print('n0', n0, 'M', M, 'next10:', dec[2:])
