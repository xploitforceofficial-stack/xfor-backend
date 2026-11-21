"""All PSU| occurrences in v5 with context; compare with v4's call site."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

import re
print("=== v5 PSU| occurrences:")
for m in re.finditer(r'PS[Uu]\|', s):
    p = m.start()
    print(f"  @{p}: {s[max(0,p-100):p+100]!r}")
    print()

print("=== v5 blob boundaries:")
print("before blob (400..445):", repr(s[400:445]))
print("after blob (500435..500470):", repr(s[500435:500470]))
print()
print("=== v4 call site around payload:")
i = v4.find('"PSU|')
print(f'v4 "PSU|" at {i}:')
print("before:", repr(v4[i-200:i]))
print("after :", repr(v4[i:i+80]))
print("blob end:", repr(v4[i+70:i+140]), "...")
en = v4.find('",', i+10000)
print("payload close context:", repr(v4[en-40:en+120]))
