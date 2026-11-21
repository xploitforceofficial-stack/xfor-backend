"""Maybe the stream is read BACKWARDS or the width char comes AFTER the digits.
Also v5's giant blob might be rotated (the tail 'BASH_1092.id' hints at ROT?).
Simplest test: reversed blob with base62 varint."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

for label, data in [('reversed', blob[::-1])]:
    pos, codes, bad = 0, [], None
    while pos < len(data):
        w = IDX[data[pos]]
        if w < 1 or pos + 1 + w > len(data):
            bad = (pos, len(codes)); break
        v = 0
        for ch in data[pos+1:pos+1+w]:
            v = v * 62 + IDX[ch]
        codes.append(v)
        pos += 1 + w
    print(label, 'codes:', len(codes), 'bad:', bad)
    if codes:
        print(' first 10:', codes[:10])
