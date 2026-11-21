"""Show every use of p( and c/n usage in the v5 VM code to figure out what they really are."""
import re
s = open('Samples/PSU/v5/_rebulled_full.lua', encoding='utf-8', errors='replace').read()
print("total len:", len(s))
print()

print("=== p( uses:")
for m in list(re.finditer(r'.{60}\bp\(.{40}', s))[:20]:
    print(repr(m.group(0)))
print()

print("=== c usage (c as var):")
for m in list(re.finditer(r'.{50}\bc\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== n usage (n as var):")
for m in list(re.finditer(r'.{50}\bn\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== u usage (u as var):")
for m in list(re.finditer(r'.{50}\bu\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== o usage (o as var):")
for m in list(re.finditer(r'.{50}\bo\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== a usage (a as var):")
for m in list(re.finditer(r'.{50}\ba\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== t usage (t as var):")
for m in list(re.finditer(r'.{50}\bt\b.{40}', s))[:15]:
    print(repr(m.group(0)))
print()

print("=== A/h/g/w/y/x usage:")
for name in ['A', 'h', 'g', 'w', 'y', 'x']:
    print(f"--- {name}:")
    for m in list(re.finditer(r'.{50}\b' + name + r'\b.{40}', s))[:8]:
        print(repr(m.group(0)))
    print()
