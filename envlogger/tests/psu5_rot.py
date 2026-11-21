"""v5 reader chain with n0 = 104 (envmap value): M = d() = 2 bytes LE.
Also test v5's d() could be 4-byte: env h=4 => a() reads 4 bytes with weights
g=3? w=65536? Let's check what 'M=d(n)' means: n is the outer param of _(...)
which is '...' — no. Actually the stream vars u,c,n are FREE locals — so n0 is
whatever the destroyed prelude set. Brute-force n0 over 0..255 for M <= 64.
Also test b() = RotateLeft as v5's l() — env key 701981504=550549531? no,
envmap 701981504->550549531 is an alias. b (bxor) = 503101675->'b'.
Try reading M with plain XOR first."""
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

dic = {e: chr(e) for e in range(256)}
out, prev, t = [], None, 256
ok = True
for code in codes:
    if code in dic: c = dic[code]
    elif code == t and prev: c = prev + prev[0]
    else: print('LZW break', code); ok = False; break
    out.append(c)
    if prev: dic[t] = prev + c[0]; t += 1
    prev = c
print('LZW ok:', ok, 'stream len:', sum(len(x) for x in out))
stream = ''.join(out)
B = [ord(ch) & 0xff for ch in stream]
print('first 20 bytes:', B[:20])

hits = []
for n0 in range(256):
    n = n0
    lo = B[0] ^ n; n = lo & 0xff
    hi = B[1] ^ n; n = hi & 0xff
    M = lo + (hi << 8)
    if M <= 64:
        hits.append((n0, M))
print('n0 candidates (M<=64):', hits[:20])
