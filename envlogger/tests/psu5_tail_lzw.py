"""The 90-char tail payload decodes as base36 varint cleanly (33 codes).
Run LZW on it and see what it is."""
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
b5 = s[1022401:1022491]

pos, codes = 0, []
while pos < len(b5):
    w = D36.index(b5[pos].lower())
    if w < 1 or pos + 1 + w > len(b5): break
    codes.append(int(b5[pos+1:pos+1+w].lower(), 36))
    pos += 1 + w
print('codes:', codes)

dic = {e: chr(e) for e in range(256)}
out, prev, t = [], None, 256
ok = True
for code in codes:
    if code in dic: c = dic[code]
    elif code == t and prev: c = prev + prev[0]
    else: print('LZW break', code, 't', t); ok = False; break
    out.append(c)
    if prev: dic[t] = prev + c[0]; t += 1
    prev = c
print('ok:', ok)
text = ''.join(out)
print('len:', len(text))
print('repr:', repr(text))
