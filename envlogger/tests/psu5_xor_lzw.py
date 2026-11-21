"""Maybe the giant blob chars are XORed/rotated first. Test: XOR each char code with a
constant k (0..255) then parse as base36 varint (lowered). Valid parse = widths 1..9
mostly and values < 1e7. Only chars mapping into [0-9a-z] after XOR are usable."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+2000]
D36 = set("0123456789abcdefghijklmnopqrstuvwxyz")

def try_parse(fn):
    pos, codes = 0, []
    while pos < len(blob):
        ch = fn(blob[pos])
        if ch not in D36: return None, pos, len(codes)
        w = "0123456789abcdefghijklmnopqrstuvwxyz".index(ch)
        if w < 1 or pos + 1 + w > len(blob): return None, pos, len(codes)
        val_chars = ''.join(fn(c) for c in blob[pos+1:pos+1+w])
        if not all(c in D36 for c in val_chars): return None, pos, len(codes)
        codes.append(int(val_chars, 36))
        pos += 1 + w
    return codes, None, len(codes)

found = []
for k in range(1, 256):
    def fn(c, k=k):
        return chr((ord(c) ^ k) & 0xff)
    codes, bad, n = try_parse(fn)
    if codes and n > 50:
        found.append(('xor', k, n))
        break
for k in range(0, 256):
    def fn(c, k=k):
        v = (ord(c) - 32 + k) % 95 + 32
        ch = chr(v)
        return ch.lower() if ch.lower() in D36 else ch
    codes, bad, n = try_parse(fn)
    if codes and n > 50:
        found.append(('rot', k, n))
        break
print('hits:', found)
