"""Map v4's exact LZW call site (what the decoder result feeds) and diff v4<->v5 boundaries."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
v5 = open('Samples/PSU/v5/_vmcode.lua', encoding='utf-8', errors='replace').read()

i = v4.find('"PSU|')

seg = v4[max(0, i - 600):i]
print("=== 600 chars before PSU| in v4:")
print(seg)
print()

j = v4.find(',(#R-G);', i)
print("=== after ',(#R-G);':")
print(v4[j:j + 300])
print()

print("=== v4 @ 7366 region:")
print(v4[7366:7366 + 500])
print()

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
print("=== v5 @ 1000400..1000700 (VM code entry):")
print(repr(s[1000400:1000700]))
