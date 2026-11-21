"""Compare the two PSU| payloads in v5: tail one starts '161027525v21222B...' which
reads naturally as base36 varint (width 1,6,1,0,2,7,5,2,5... no). Parse it:
'16' '1027525' ... widths are digits. Actually v4.5's started '230151510277278...' with
width chars as digits — same style! Compare: v4.5 first codes were [108,5,5,0,259...] —
width 2, value 30? '2''30' -> 30, then '1''5' -> 5? '5' alone can't (width 0 invalid).
Reparse v4.5 from scratch to confirm widths, then apply the SAME to the tail v5 payload."""
D36 = "0123456789abcdefghijklmnopqrstuvwxyz"

def parse(blob, label):
    pos, codes = 0, []
    while pos < len(blob):
        w = D36.index(blob[pos].lower())
        if w < 1 or pos + 1 + w > len(blob):
            print(label, 'end at pos', pos, 'codes', len(codes))
            break
        codes.append(int(blob[pos+1:pos+1+w].lower(), 36))
        pos += 1 + w
    else:
        print(label, 'complete, codes', len(codes))
    return codes

s45 = open('Samples/PSU/v4.5/1.lua', encoding='latin1').read()
import re
b45 = re.search(r'PSU\|([0-9A-Za-z]+)', s45).group(1)
c45 = parse(b45, 'v4.5')
print('v4.5 first 20:', c45[:20])

s5 = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
b5 = s5[1022401:1022491]
c5 = parse(b5, 'v5tail')
print('v5tail first 20:', c5[:20])
