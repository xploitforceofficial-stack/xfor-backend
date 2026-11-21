"""v4.5 LZW: dict seeded via 'for e=d,t-n do' with d,n likely 0/1. codes[0]=108 works
with 1..255 seeding (108=chr(108)). code 0 appears at index 3 — so 0 must be valid:
dict seeded 0..255 (256 entries). Try dict[0..255]=chr(e). Also t starts at 256."""
s45 = open('Samples/PSU/v4.5/1.lua', encoding='latin1').read()
import re
m = re.search(r'PSU\|([0-9A-Za-z]+)', s45)
blob = m.group(1)
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"
pos, codes = 0, []
while pos < len(blob):
    w = D36.index(blob[pos].lower())
    if w < 1 or pos + 1 + w > len(blob): break
    codes.append(int(blob[pos+1:pos+1+w], 36))
    pos += 1 + w
print('codes:', len(codes))

dic = {e: chr(e) for e in range(0, 256)}
out, prev, t = [], None, 256
ok = True
for code in codes:
    if code in dic: c = dic[code]
    elif code == t and prev: c = prev + prev[0]
    else: print('break at', code, 't', t); ok = False; break
    out.append(c)
    if prev:
        dic[t] = prev + c[0]; t += 1
    prev = c
if ok:
    text = ''.join(out)
    print('LZW OK len', len(text))
    print(repr(text[:120]))
