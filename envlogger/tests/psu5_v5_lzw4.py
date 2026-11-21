"""v5: base36 varint over the 500KB blob (chars are base62 but digits 0-9 are valid
base36 too — mixed case may carry both upper and lower digit values; test both cases)."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"

def attempt(label, norm):
    pos, codes = 0, []
    while pos < len(blob):
        w = D36.index(norm(blob[pos]))
        if w < 1 or pos + 1 + w > len(blob):
            print(label, 'varint break at', pos, 'codes', len(codes)); return None
        codes.append(int(blob[pos+1:pos+1+w].translate(str.maketrans(D36, D36)) if False else ''.join(norm(ch) for ch in blob[pos+1:pos+1+w]), 36))
        pos += 1 + w
        if len(codes) > 400000:
            print(label, 'too many'); return None
    return codes

low = attempt('lower', lambda ch: ch.lower())
up = attempt('upper', lambda ch: ch.upper())
for label, codes in [('lower', low), ('upper', up)]:
    if codes:
        print(label, 'codes:', len(codes), 'first 10:', codes[:10], 'max:', max(codes))
