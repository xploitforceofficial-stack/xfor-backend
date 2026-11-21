"""v5 payload: base36 varint (lowercase norm, widths 1..35), LZW dict 0..255, then
XOR-chain via the VM's i() reader: e = byte ^ n; n = e % 256.
The whole decoded LZW buffer IS the XOR'd stream. First deserializer read: M=d(n)=2 bytes
little-endian: lo=i(), hi=i(). First instruction count etc. Sanity: M small.
Brute n0 in 0..255; accept when M (=lo+hi*256) is small (<=100)."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"

pos, codes = 0, []
while pos < len(blob):
    w = D36.index(blob[pos].lower())
    if w < 1 or pos + 1 + w > len(blob): break
    codes.append(int(blob[pos+1:pos+1+w].lower(), 36))
    pos += 1 + w
print('codes:', len(codes))

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
print('LZW ok:', ok, 'len', sum(len(x) for x in out))
stream = ''.join(out)
b = [ord(ch) & 0xff for ch in stream]
print('stream len:', len(b), 'first 16:', b[:16])

for n0 in range(256):
    n = n0

    lo = b[0] ^ n; n = lo & 0xff
    hi = b[1] ^ n; n = hi & 0xff
    M = lo + (hi << 8)
    if 0 <= M <= 4096:
        print('n0 candidate', n0, '-> M =', M)
