"""Compare obfuscation strength: skidfuscator.txt vs PSU v5 sample."""
import re

sk = open('Samples/skidfuscator.txt', encoding='utf-8', errors='replace').read()
psu = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

print("=== SIZE")
print("skid:", len(sk), " psu5:", len(psu))

print()
print("=== LINE COUNT")
print("skid:", sk.count('\n'), " psu5:", psu.count('\n'))

print()
print("=== OBFUSCATION PRIMITIVES (count)")
prims = {
    'repeat loops': r'\brepeat\b',
    'while loops': r'\bwhile\b',
    'loadstring': r'loadstring',
    'string.dump': r'string\.dump',
    'getfenv': r'getfenv',
    'bit32': r'bit32',
    'bit ops (band/bxor)': r'(band|bxor)\(',
    'charcode math (byte)': r':byte\(',
    'char build (char)': r'string\.char',
    'long strings [[..]]': r'\[\[',
    'numeric garbage': r'\(\(\d{6,}\)\)',
    'vararg usage': r'\.\.\.',
    'pcall': r'pcall',
    'rawset/rawget': r'raw(set|get)',
    'metatables': r'setmetatable',
    'VM dispatcher hints': r'(local function [a-zA-Z]\(\w+,\w+,\.\.\.\))',
}
for name, pat in prims.items():
    print(f"  {name:28} skid={len(re.findall(pat, sk)):6}  psu5={len(re.findall(pat, psu)):6}")

print()
print("=== PAYLOAD CONTAINERS")
print("skid: table-of-strings G-separated  =", len(re.findall(r'"G[^\"]{20,}"', sk)) > 0)
print("psu5: giant [[..]] long string      =", '[[' in psu and ']]' in psu)
