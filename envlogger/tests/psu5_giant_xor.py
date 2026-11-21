"""Giant blob with v4.5-style varint parse — but widths must be plausible. Earlier
'lower' parse died at pos 289 with code 15 done. That means width char at 289 was
> 9 (like 'R'=27). UNLESS v5 width alphabet is smaller: width = DIGIT ONLY (0-9),
value chars = base62! Test: width = int(ch) if isdigit else invalid."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

pos, codes = 0, []
fail = None
while pos < len(blob):
    ch = blob[pos]
    if not ch.isdigit():
        fail = (pos, ch, len(codes))
        break
    w = int(ch)
    if w < 1 or pos + 1 + w > len(blob):
        fail = (pos, ch, len(codes)); break
    v = 0
    for c2 in blob[pos+1:pos+1+w]:
        v = v * 62 + IDX[c2]
    codes.append(v)
    pos += 1 + w
print('digit-width parse:', len(codes), 'fail:', fail)
if codes:
    print('first 20:', codes[:20])
