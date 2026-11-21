"""Check the ORIGINAL v5 body (not clean): what string literal is used where clean shows (S)?
The troll head strings might have eaten the real constant. Compare original vs clean around key spots."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
body = s[1000524:]

import re
i = body.find('#((')
print("first #( in original body @", i)
print(repr(body[i - 100:i + 100]))
print()

clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()
j = clean.find('#((')
print("first #( in clean @", j)
print(repr(clean[j - 100:j + 100]))
print()

strs = []
i2 = 0
n = len(body)
BS = chr(92)
while i2 < n:
    c = body[i2]
    if c == '"' or c == "'":
        q = c
        st = i2
        j2 = i2 + 1
        while j2 < n:
            if body[j2] == BS:
                j2 += 2
                continue
            if body[j2] == q:
                j2 += 1
                break
            j2 += 1
        strs.append((st, j2, body[st:j2]))
        i2 = j2
    else:
        i2 += 1

print(f"body string literals: {len(strs)}")
for st, en, txt in strs[:40]:
    print(f"  @{st} ({en-st} ch): {txt[:80]!r}")
