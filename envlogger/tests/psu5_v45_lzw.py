"""Decode v4.5 payload with the v4.5 algorithm (base36 varint, k=tonumber, h=string.sub).
v4.5 reader: d() = local l=k(h(o,e,e),(36)); e=e+n; local n=k(h(o,e,e+l-n),(36)); e=e+l; return n
  n = 1 presumably (increment), k = tonumber, h = string.sub, base 36.
Then LZW: l=A[d()]; a[n]=l; while e<#o do e_code=d(); if i[e] then c=i[e] else c=l..h(l,n,n); end;
  i[t]=l..h(c,n,n); a[#a+n]=c; l=c; t=t+1; end; return F(a)  — F = table.concat.
Seed: for e=d,t-n do local l=H(e); i[e]=l; A[e]=l; A[l]=e; end — d=1? t=(#S+165)=91+165=256.
So dict i[e] for e=1..255 (n=1, so e=d(=1)..t-1(=255)) = 255 entries of H(e)... H = char?
Decode and confirm; then v5 likely = same but base62 and/or different seed."""
s45 = open('Samples/PSU/v4.5/1.lua', encoding='latin1').read()
import re
m = re.search(r'PSU\|([0-9A-Za-z]+)', s45)
blob = m.group(1)

D36 = "0123456789abcdefghijklmnopqrstuvwxyz"
def v36(ch):
    return D36.index(ch.lower()) if ch.lower() in D36 else None

pos = 0
codes = []
ok = True
while pos < len(blob):
    w = v36(blob[pos])
    if w is None or w < 1 or pos + 1 + w > len(blob):
        ok = False
        print('varint break at pos', pos, 'width', w, 'total codes', len(codes))
        break
    val = int(blob[pos+1:pos+1+w], 36)
    codes.append(val)
    pos += 1 + w
if ok:
    print('codes:', len(codes), 'first 10:', codes[:10], 'max:', max(codes))

    dic = {}
    for e in range(1, 256):
        dic[e] = chr(e)
    out = []
    prev = None
    t = 256
    ok2 = True
    for code in codes:
        if code in dic:
            c = dic[code]
        elif code == t and prev:
            c = prev + prev[0]
        else:
            print('LZW break: code', code, 'dict max', t)
            ok2 = False
            break
        out.append(c)
        if prev:
            dic[t] = prev + c[0]
            t += 1
        prev = c
    if ok2:
        text = ''.join(out)
        print('LZW OK! out len:', len(text))
        print('first 100:', repr(text[:100]))
