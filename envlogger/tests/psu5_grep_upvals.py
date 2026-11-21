"""The VM body references deserializer locals (c, l, u, x...) that were defined in the
MISSING wrapper. The v4 equivalent: c/w=({}),({}) byte<->char maps, u=stream, t=cursor.
Find their use sites in the v5 body to understand which values they need."""
import re

full = open('Samples/PSU/v5/_rebulled_full.lua', encoding='utf-8').read()

m = re.search(r'.{80}\bc\b.{80}', full)
print("first c use:", m.group(0) if m else None)
print()

i = full.find('local function i(')
print("=== local function i() :")
print(full[i:i + 400])
print()
i = full.find('local function d(')
print("=== local function d() :")
print(full[i:i + 400])
print()
i = full.find('local function f(')
print("=== local function f() :")
print(full[i:i + 400])
print()
i = full.find('local function a(')
print("=== local function a() :")
print(full[i:i + 400])
